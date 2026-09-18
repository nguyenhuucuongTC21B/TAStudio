//go:build windows && cgo && vieneu

// Package vienneu — driver gắn trực tiếp C ABI của VieNeu-TTS.cpp vào Go.
//
// Yêu cầu build: CGO_ENABLED=1 GOOS=windows GOARCH=amd64 với tag `vieneu`;
// CGO_CFLAGS / CGO_LDFLAGS do scripts/build.ps1 -Full cấu hình, trỏ tới static
// lib `vieneu-tts-core` + ggml/llama.cpp + ONNX Runtime liên kết tĩnh.
//
// Thiết kế hai pha khớp ABI chính thức:
//
//	vieneu_init_v2_default_params → vieneu_init_v2          (load models MỘT lần)
//	vieneu_tts_v2_default_params  → vieneu_synthesize_v2    (per chunk)
//	vieneu_set_progress_callback                            (tiến trình realtime)
//
// run #38: khớp đúng tên struct theo vieneu/vieneu_tts.h — các biến trước đây
// khai báo C.struct_vienu_* (thiếu chữ "e") khiến cgo sinh kiểu mờ KHÔNG có
// field; sửa thành C.struct_vieneu_*. Bổ sung ListVoices để thoả mãn trọn vẹn
// interface engine.Driver (app.go gán vienneu.New vào engine.NeuralFactory).
// Chuyển PCM bằng vòng lặp float32 thay cho copy() (C.float là kiểu định nghĩa
// riêng của cgo, copy() yêu cầu kiểu phần tử giống hệt nhau).
package vienneu

/*
#include <stdlib.h>
#include <string.h>
#include "vieneu/vieneu_tts.h"

extern void hcstudioGoProgress(int cur, int tot, float prog);

// Bridge tiến trình C -> Go; gắn bằng vieneu_set_progress_callback một lần.
static void hcstudio_progress_sink(const struct vieneu_progress *p, void *ud) {
        if (p != NULL) {
                hcstudioGoProgress((int)p->current, (int)p->total, p->progress);
        }
}

static void attach_progress(struct vieneu_context *ctx) {
        vieneu_set_progress_callback(ctx, hcstudio_progress_sink, NULL);
}
*/
import "C"
import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"unsafe"

	"hcstudio/internal/engine"
	"hcstudio/internal/textnorm"
)

// Linked là hằng nhận diện có engine thật tại compile-time.
const Linked = true

// Bảo hiểm compile-time: Driver phải thoả mãn trọn vẹn contract engine.Driver
// (Name + ListVoices + Synthesize + Close) — nếu thiếu method nào, go build
// chặn ngay tại package này thay vì ở package main.
var _ engine.Driver = (*Driver)(nil)

type progressFn func(cur, tot int, sub float64)

var (
	activeSink atomic.Pointer[progressFn]
	initMu     sync.Mutex
	globalCtx  *C.struct_vieneu_context
)

//export hcstudioGoProgress
func hcstudioGoProgress(cur C.int, tot C.int, prog C.float) {
	if fn := activeSink.Load(); fn != nil {
		run := *fn
		run(int(cur), int(tot), float64(prog))
	}
}

// Driver quản lý context engine toàn tiến trình.
type Driver struct {
	modelDir string
	threads  int
	mu       sync.Mutex // serialize toàn bộ synthesis (KV cache dùng chung)
}

// New khởi tạo driver nhưng CHƯA load model — diễn ra lười ở lần dùng đầu.
func New(modelDir string) *Driver {
	threads := runtime.NumCPU()
	if threads > 8 {
		threads = 8 // máy laptop CPU yếu — không oversubscribe
	}
	// PATCH FIX41: knob môi trường để chẩn đoán — hạ số thread engine
	// khi nghi nghi vấn oversubscription/threading. VD:
	//   set HCSTUDIO_TTS_THREADS=2  rồi mới chạy HCStudio.exe
	if s := os.Getenv("HCSTUDIO_TTS_THREADS"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n >= 1 && n <= 64 {
			threads = n
		}
	}
	vlogf("New: modelDir=%q · n_threads=%d · NumCPU=%d", modelDir, threads, runtime.NumCPU())
	return &Driver{modelDir: modelDir, threads: threads}
}

// ensureLoaded load model pack nếu chưa load. Trả lỗi chi tiết tiếng Việt.
func (d *Driver) ensureLoaded() error {
	initMu.Lock()
	defer initMu.Unlock()
	if globalCtx != nil {
		return nil
	}
	if !engine.AssetsReady(d.modelDir) {
		return engine.ErrNeuralNoAssets
	}
	paths := engine.ResolveModelPaths(d.modelDir)

	// PATCH FIX41: libgomp đọc OMP_NUM_THREADS đúng MỘT lần tại vùng
	// song song đầu tiên — set trước lần gọi native đầu để OpenMP
	// không phóng số thread = NumCPU chồng lên ggml threadpool khi cả
	// hai cùng bật (nghi phạm oversubscription chưa được loại trừ).
	if os.Getenv("OMP_NUM_THREADS") == "" {
		omp := d.threads
		if omp > 4 {
			omp = 4
		}
		if err := os.Setenv("OMP_NUM_THREADS", strconv.Itoa(omp)); err == nil {
			vlogf("init: set OMP_NUM_THREADS=%d", omp)
		}
	}

	cProfile := C.CString("vieneu-v3-onnx")
	defer freeC(unsafe.Pointer(cProfile))
	cModel := C.CString(paths.ModelDir)
	defer freeC(unsafe.Pointer(cModel))
	cOnnx := C.CString(paths.OnnxDir)
	defer freeC(unsafe.Pointer(cOnnx))
	cCodec := C.CString(paths.CodecDir)
	defer freeC(unsafe.Pointer(cCodec))
	cConfig := C.CString(paths.Config)
	defer freeC(unsafe.Pointer(cConfig))
	cTok := C.CString(paths.Tokenize)
	defer freeC(unsafe.Pointer(cTok))
	cVoices := C.CString(paths.Voices)
	defer freeC(unsafe.Pointer(cVoices))

	var ip C.struct_vieneu_init_params_v2
	C.vieneu_init_v2_default_params(&ip)
	ip.profile = cProfile
	ip.model_dir = cModel
	ip.onnx_dir = cOnnx
	ip.codec_dir = cCodec
	ip.config_path = cConfig
	ip.tokenizer_path = cTok
	ip.voices_json_path = cVoices
	ip.n_threads = C.int(d.threads)

	// PATCH FIX41: mốc CHÍNH XÁC quanh vieneu_init_v2 — lần synth đầu
	// nạp toàn bộ ggml/llama/ONNX model tại đây; nếu tiến trình chết
	// mà vieneu.log dừng ở dòng "init: gọi vieneu_init_v2..." thì
	// crash nằm trong nội bộ hàm nạp model (nghi phạm số 1).
	vlogf("init: gọi vieneu_init_v2 · profile=%q · model_dir=%q · onnx_dir=%q · codec_dir=%q · config=%q · tokenizer=%q · voices=%q · n_threads=%d",
		"vieneu-v3-onnx", paths.ModelDir, paths.OnnxDir, paths.CodecDir,
		paths.Config, paths.Tokenize, paths.Voices, d.threads)
	ctx := C.vieneu_init_v2(&ip)
	vlogf("init: vieneu_init_v2 đã trả về · ctx!=nil: %v", ctx != nil)
	if ctx == nil {
		vlogf("init: THẤT BẠI: %s", lastError())
		return fmt.Errorf("vieneu_init_v2 thất bại: %s", lastError())
	}
	globalCtx = ctx
	C.attach_progress(globalCtx)
	runtime.KeepAlive(ip)
	return nil
}

// ListVoices chỉ để thoả mãn interface engine.Driver — catalog hiển thị do
// tầng hybrid nắm (NeuralCatalog 20 giọng + SAPI máy cài), driver neural
// không tự liệt kê gì thêm.
func (d *Driver) ListVoices() ([]engine.Voice, error) { return nil, nil }

// ensureInitOnly đảm bảo engine đã load trước khi thao tác.
func (d *Driver) ensureInitOnly() error { return d.ensureLoaded() }

// Synthesize tổng hợp một đoạn text thành PCM float32 @48kHz.
func (d *Driver) Synthesize(text string, opts engine.SynthOptions) (*engine.SynthResult, error) {
	d.mu.Lock()
	defer d.mu.Unlock()

	if err := d.ensureInitOnly(); err != nil {
		return nil, err
	}

	sink := progressFn(func(cur, tot int, sub float64) {
		pct := sub
		if tot > 0 && pct <= 0 || pct > 1 {
			pct = float64(cur) / float64(maxInt(tot, 1))
		}
		if opts.ProgressFn != nil {
			opts.ProgressFn(clamp01(pct))
		}
	})
	activeSink.Store(&sink)
	defer activeSink.Store(nil)

	temp := opts.Temperature
	if temp == 0 {
		temp = 0.8 // khuyến nghị tác giả v3 Turbo
	}
	topK := opts.TopK
	if topK <= 0 {
		topK = 25
	}
	topP := opts.TopP
	if topP <= 0 {
		topP = 0.95
	}

	// PATCH FIX46: text normalizer — engine v3 dùng Byte-BPE thô, không có
	// bước normalize/phonemize. Số, ký hiệu toán, ký tự đặc biệt, emoji phải
	// được chuyển sang dạng "đọc được" trước khi token hóa, ngược lại model
	// đọc lộn hoặc bỏ sót. Bỏ qua khi opts.SkipTextNorm=true.
	if !opts.SkipTextNorm {
		if normed := textnorm.Normalize(text); strings.TrimSpace(normed) != "" {
			text = normed
		}
	}

	cText := C.CString(text)
	defer freeC(unsafe.Pointer(cText))
	cVoice := C.CString(opts.VoiceID)
	defer freeC(unsafe.Pointer(cVoice))

	var tp C.struct_vieneu_tts_params_v2
	C.vieneu_tts_v2_default_params(&tp)
	tp.text = cText
	tp.voice_id = cVoice
	tp.temperature = C.float(temp)
	tp.top_k = C.int(topK)
	tp.top_p = C.float(topP)
	// tp.max_chars chuyển xuống khối PATCH FIX42 bên dưới (256).

	// PATCH FIX46: nhân bản giọng zero-shot — ref_audio_path khác rỗng thì
	// core BỎ voice preset (xem VieneuV3OnnxEngine::synthesize: nhánh
	// ref_audio_path có ưu tiên cao hơn resolve_voice_preset) và encode
	// file WAV mẫu qua MOSS codec thành codes tham chiếu. Xác thực file
	// tồn tại trước khi xuống C để báo lỗi tiếng Việt rõ ràng.
	if opts.RefAudioPath != "" {
		if _, err := os.Stat(opts.RefAudioPath); err != nil {
			return nil, fmt.Errorf("file audio mẫu không đọc được: %w", err)
		}
		cRef := C.CString(opts.RefAudioPath)
		defer freeC(unsafe.Pointer(cRef))
		tp.ref_audio_path = cRef
		vlogf("tts: nhân bản giọng từ %q (bỏ qua voice preset %q)", opts.RefAudioPath, opts.VoiceID)
	}

	// PATCH FIX42: khoá BỘ THAM SỐ CHÍNH THỨC của tác giả (bằng đúng
	// default UI của Space pnnbao-ump/VieNeu-TTS-v3-Turbo và default
	// của vieneu_tts_v2_default_params trong C++ core):
	//   temperature 0.8 · top_k 25 · top_p 0.95 · repetition_penalty 1.2
	//   max_new_frames 300 · max_chars 256
	// Trước đây ta chỉ set 5 tham số đầu và default-max_chars=384 —
	// lệch với khuyến nghị 256 của tác giả (đoạn dài hơn dễ lặp).
	// rep_penalty/max_frames trước đây *_Phụ thuộc default core_* —
	// giờ khoá tường minh để không bị vỡ nếu core đổi default.
	tp.repetition_penalty = C.float(1.2)
	tp.max_new_frames = C.int(300)
	tp.max_chars = C.int(256)

	var audio C.struct_vieneu_audio
	vlogf("tts: gọi vieneu_synthesize_v2 (globalCtx!=nil: %v)", globalCtx != nil)
	code := C.vieneu_synthesize_v2(globalCtx, &tp, &audio)
	// PATCH FIX41: mốc NGAY SAU synthesize_v2 — giá trị trả về được in
	// trước khi đụng tới samples để nếu struct/ABI lệch thì log vẫn kịp.
	vlogf("tts: synthesize_v2 trả rc=%d · samples!=nil: %v · n_samples=%d · sr=%d",
		int(code), audio.samples != nil, int(audio.n_samples), int(audio.sample_rate))
	if code != 0 || audio.samples == nil {
		msg := lastError()
		vlogf("tts: THẤT BẠI rc=%d: %s", int(code), msg)
		C.vieneu_audio_free(&audio)
		return nil, fmt.Errorf("%w: rc=%d (%s)", engine.ErrSynthesisFailed, int(code), msg)
	}

	n := int(audio.n_samples)
	sr := int(audio.sample_rate)
	if sr <= 0 {
		sr = 48000
	}
	src := unsafe.Slice(audio.samples, maxInt(n, 0))
	out := make([]float32, len(src))
	for i, v := range src {
		out[i] = float32(v) // C.float -> float32: copy() không nhận kiểu phần tử khác nhau
	}
	vlogf("tts: copy %d mẫu @%dHz vào Go xong", n, sr)
	C.vieneu_audio_free(&audio)
	vlogf("tts: vieneu_audio_free xong · %d mẫu", n)

	runtime.GC() // nhả trang nhớ lớn sau mỗi chunk — RSS ổn định trên máy yếu

	return &engine.SynthResult{
		Samples:     out,
		SampleRate:  sr,
		NativeSpeed: true,
	}, nil
}

func (d *Driver) Close() error {
	initMu.Lock()
	defer initMu.Unlock()
	if globalCtx != nil {
		vlogf("close: gọi vieneu_free")
		C.vieneu_free(globalCtx)
		globalCtx = nil
		vlogf("close: vieneu_free xong")
	}
	return nil
}

func (d *Driver) Name() string { return "VieNeu v3 Turbo (native C++)" }

// ---- tiện ích ----

func freeC(p unsafe.Pointer) {
	if p != nil {
		C.free(p)
	}
}

func lastError() string {
	c := C.vieneu_last_error()
	if c == nil {
		return "unknown"
	}
	return C.GoString(c)
}

func clamp01(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
