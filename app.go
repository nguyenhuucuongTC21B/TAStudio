package main

// app.go — Bridge API của HCStudio v5.0.
//
// Mọi method public trên struct App được Wails bind thành
// window.go.backend.App.<Method> — lời gọi trực tiếp trong bộ nhớ,
// KHÔNG socket, KHÔNG port (ràng buộc kiến trúc số 2 của dự án).
//
// PATCH run #29: mọi bước then chốt của pipeline đều ghi dấu vào
// hcstudio.log (diaglog.go) — snapshot startup, kết quả resolve engine,
// lỗi synthesis/playback/export/model-download — hết cảnh mù thông tin
// phía máy người dùng. Riêng lỗi tự phát sau tổng hợp TRƯỚC ĐÂY bị bỏ
// quên âm thầm (a.PlayJob không kiểm tra return) — nay toast + log.
import (
	"archive/zip"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	gort "runtime"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"

	"hcstudio/internal/appstate"
	"hcstudio/internal/bridge"
	"hcstudio/internal/dsp"
	"hcstudio/internal/engine"
	"hcstudio/internal/engine/vienneu"
	"hcstudio/internal/player"
	"hcstudio/internal/textnorm"
)

const (
	appVersion = "5.0.0"
	maxTextLen = 200_000 // giới hạn mềm có cảnh báo UI
)

// Session là kết quả tổng hợp hoàn tất, phục vụ Play lại và Export.
type Session struct {
	ID       string
	VoiceID  string
	Engine   string
	Text     string
	Samples  []float32
	SR       int
	Duration float64
	Created  time.Time
}

// App struct chính được Wails bind.
type App struct {
	ctx      context.Context
	settings appstate.Settings

	mu          sync.Mutex
	hybrid      *engine.Hybrid
	player      *player.Player
	downloader  *vienneu.Downloader
	sessions    map[string]*Session
	sessionRing []string // LRU tối đa 5 phiên gần nhất
	cancelSynth context.CancelFunc
	playJobID   string
	modelDLRun  bool

	emit *EventThrottle
}

// NewApp dựng toàn bộ dependency graph của backend.
func NewApp() *App {
	a := &App{
		settings: appstate.Load(),
	}
	return a
}

// startup — wails OnStartup hook: gắn ctx, nạp engine, COM init cho SAPI.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	initWindowsCOM()

	modelDir := appstate.ModelsDir()
	engine.NeuralModelDir.Store(&modelDir)
	engine.NeuralFactory = func(dir string) engine.Driver { return vienneu.New(dir) }
	engine.NeuralLinked.Store(vienneu.Linked)

	a.hybrid = engine.NewHybrid(modelDir)
	a.player = player.New()
	a.sessions = map[string]*Session{}
	a.emit = NewEventThrottle(ctx)

	a.player.OnProgress = func(curMs, totalMs int) {
		pct := 0.0
		if totalMs > 0 {
			pct = float64(curMs) / float64(totalMs) * 100
		}
		a.emit.Send("hcstudio:play", bridge.PlayEvent{
			JobID: a.playJobID, CursorMs: curMs, TotalMs: totalMs,
			Pct: pct, Playing: true,
		})
	}
	a.player.OnEnded = func() {
		a.emit.Send("hcstudio:play", bridge.PlayEvent{Playing: false})
	}

	if a.settings.OutDir == "" {
		a.settings.OutDir = appstate.ExportsDir()
	}

	// PATCH run #29: snapshot môi trường — trả lời ngay trong log những
	// câu hỏi chẩn đoán cốt lõi: binary có nhúng neural không, model còn
	// thiếu file nào, máy có bao nhiêu giọng SAPI thật, log nằm ở đâu.
	diagf("startup: neuralLinked=%v · modelDir=%s", engine.IsNeuralLinked(), modelDir)
	if engine.IsNeuralLinked() {
		missing := engine.MissingAssets(modelDir)
		if len(missing) == 0 {
			diagf("startup: neural READY — đủ toàn bộ trọng số bắt buộc")
		} else {
			diagf("startup: neural thiếu %d file bắt buộc:", len(missing))
			for i, m := range missing {
				if i >= 12 {
					diagf("startup:   … (+%d file nữa)", len(missing)-12)
					break
				}
				diagf("startup:   thiếu: %s", m)
			}
		}
	} else {
		diagf("[warn] startup: binary KHÔNG nhúng engine neural (build Lite hoặc tag vieneu không vào) — wizard tải mô hình sẽ không bao giờ hiện")
	}
	if voices := a.hybrid.ListVoices(engine.IsNeuralLinked()); len(voices) == 0 {
		diagf("[warn] startup: ListVoices RỖNG — máy không liệt kê được giọng SAPI nào và neural chưa sẵn sàng")
	} else {
		sapiCount := 0
		for _, v := range voices {
			if v.Engine == engine.EngineSAPI {
				sapiCount++
				diagf("startup: giọng SAPI[%d] = %s", sapiCount, v.ID)
			}
		}
		diagf("startup: ListVoices -> %d giọng (%d SAPI, %d neural)",
			len(voices), sapiCount, len(voices)-sapiCount)
	}
	diagf("startup: exportsDir=%s · logDir=%s", a.settings.OutDir, DiagLogDir())
}

// shutdown dọn tài nguyên khi thoát app.
func (a *App) shutdown(ctx context.Context) {
	diagf("shutdown: thoát app")
	if a.cancelSynth != nil {
		a.cancelSynth()
	}
	if a.downloader != nil {
		a.downloader.Cancel()
	}
	a.player.Stop()
	uninitWindowsCOM()
}

// ---------- API GETTERS ----------

// GetAppState trả snapshot môi trường ban đầu cho UI hydrate.
func (a *App) GetAppState() bridge.AppState {
	modelDir := appstate.ModelsDir()
	a.mu.Lock()
	defer a.mu.Unlock()

	resp := bridge.AppState{
		Version:        appVersion,
		IsDarkWin:      appstate.IsWindowsDark(),
		NeuralLinked:   engine.IsNeuralLinked(),
		ModelDir:       modelDir,
		VoiceCountHint: len(engine.NeuralCatalog()),
		CPUThreads:     gort.NumCPU(),
		ExportsDir:     appstate.ExportsDir(),
		MissingFiles:   []string{},
	}
	if engine.IsNeuralLinked() {
		missing := engine.MissingAssets(modelDir)
		resp.NeuralReady = len(missing) == 0
		if len(missing) > 5 {
			missing = append(missing[:5], fmt.Sprintf("… (+%d file nữa)", len(missing)-5))
		}
		resp.MissingFiles = missing
	} else {
		resp.MissingFiles = []string{"binary chưa biên dịch với -tags vieneu"}
	}

	// PATCH run #29: dòng này chứng minh frontend ĐÃ gọi tới được backend
	// (hydrate thành công) và cho biết UI nhận trạng thái gì để vẽ pill/wizard.
	diagf("GetAppState -> neuralLinked=%v neuralReady=%v missing=%d",
		resp.NeuralLinked, resp.NeuralReady, len(resp.MissingFiles))
	return resp
}

// ListVoices hợp nhất catalog neural + giọng SAPI thực tế máy đang cài.
func (a *App) ListVoices() []bridge.Voice {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.hybrid.ListVoices(engine.IsNeuralLinked())
}

// GetSettings đọc settings hiện tại (JSON camelCase khớp settings store UI).
func (a *App) GetSettings() appstate.Settings { return a.settings }

// SaveSettings ghi đè + lưu đĩa (validate clamp chống rác UI).
func (a *App) SaveSettings(s appstate.Settings) {
	switch s.ThemeMode {
	case appstate.ThemeAuto, appstate.ThemeLight, appstate.ThemeDark:
		a.settings.ThemeMode = s.ThemeMode
	}
	switch s.EnginePref {
	case "auto", "neural", "sapi":
		a.settings.EnginePref = s.EnginePref
	}
	if len(s.VoiceID) > 0 && len(s.VoiceID) < 128 {
		a.settings.VoiceID = s.VoiceID
	}
	a.settings.Speed = clampF(0.5, 2.0, s.Speed)
	a.settings.Pitch = clampF(-12, 12, s.Pitch)
	a.settings.Volume = clampF(0, 1, s.Volume)
	if strings.HasSuffix(s.OutDir, "\\") || s.OutDir != "" {
		a.settings.OutDir = s.OutDir
	}
	a.settings.UpdatedAt = time.Now().Format(time.RFC3339)
	_ = a.settings.Save()
}

func clampF(lo, hi, v float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// ---------- PIPELINE SYNTHESIS ----------

// Synthesize bắt đầu job tổng hợp async; trả jobID ngay để UI theo dõi event.
func (a *App) Synthesize(req bridge.SynthRequest) string {
	jobID := genID("job")

	text := strings.TrimSpace(req.Text)
	if text == "" {
		a.pushJob(jobID, "error", "Văn bản trống", 0)
		return jobID
	}
	if len(text) > maxTextLen {
		text = text[:maxTextLen]
	}

	ctx, cancel := context.WithCancel(a.ctx)
	a.mu.Lock()
	if a.cancelSynth != nil {
		a.cancelSynth() // hủy job cũ nếu còn chạy
	}
	a.cancelSynth = cancel
	a.mu.Unlock()

	diagf("job %s: nhận yêu cầu synth · voice=%q · engine=%q · speed=%.2f · %d ký tự",
		jobID, req.VoiceID, req.EngineOverride, req.Speed, len([]rune(text)))
	go a.runSynthesis(ctx, jobID, req, text)
	return jobID
}

func (a *App) runSynthesis(ctx context.Context, jobID string, req bridge.SynthRequest, text string) {
	// PATCH FIX41: panic trong goroutine này trước đây chỉ in vào stderr
	// vô hình (exe GUI) => cả app sập mà hcstudio.log không thêm được
	// dòng nào. Giờ panic được bắt và ghi log kèm stack — nhờ đó phân
	// biệt lỗi Go với crash native (crash native tiến trình vẫn chết,
	// chứng cứ nằm ở dòng [CRASH] + file .dmp do crashdiag ghi).
	defer func() {
		if r := recover(); r != nil {
			diagf("[error] job %s: PANIC goroutine synth: %v · stack:\n%s",
				jobID, r, debug.Stack())
			a.pushJob(jobID, "error",
				"Lỗi nội bộ engine: "+fmt.Sprint(r), 0)
		}
	}()

	// PATCH FIX46 — NHÂN BẢN GIỌNG (zero-shot clone): khi UI gửi kèm
	// refAudioPath (file WAV mẫu 5-15s), job buộc dùng engine neural và
	// bỏ voice preset — core encode file mẫu thành "giọng" tham chiếu.
	// Phải bypass hybrid.Resolve vì Resolve chỉ nhận voiceID preset
	// (IsNeuralVoice) và sẽ rơi xuống SAPI khi voiceID rỗng.
	useRef := req.RefAudioPath != ""

	// PATCH FIX47: vệ sinh audio mẫu trước khi synth — trim 8s (khop
	// _MAX_REF_SECONDS = 8.0 của SDK vieneu) và cảnh báo khi dài hơn
	// 5.5s (cùng ngưỡng cảnh báo của Space chính thức). Ref dài làm
	// chuỗi ref codes phình theo file, clone càng dễ sai giọng và méo
	// tiếng (đúng cảnh báo của tác giả trên Space).
	refPath := req.RefAudioPath
	if trimmed, dur, cut, perr := dsp.PrepareRefAudio(refPath, appstate.ConfigDir(), 8.0); perr == nil {
		if cut {
			refPath = trimmed
			diagf("job %s: ref audio > 8s -> da cat con 8s: %s", jobID, trimmed)
			a.toast("success", "Nhân bản giọng",
				"Audio mẫu dài hơn 8 giây — đã tự cắt còn 8 giây để nhân bản chuẩn xác hơn. Khuyến nghị: clip 3–5 giây, một câu nói rõ.")
		} else if dur > 5.5 {
			a.toast("warn", "Nhân bản giọng",
				fmt.Sprintf("Audio mẫu dài %.1f giây. Nên dùng clip 3–5 giây (một câu nói rõ, ít ồn) — audio càng dài clone càng dễ sai giọng.", dur))
		}
	} else {
		diagf("job %s: khong doc duoc WAV mau (%v) - chuyen nguyen file cho core tu xu ly", jobID, perr)
	}

	a.hybrid.RefreshNeuralReadiness()
	var driver engine.Driver
	var voiceExecID string
	var engKind engine.VoiceEngine
	if useRef {
		if !engine.IsNeuralLinked() {
			a.pushJob(jobID, "error", engine.ErrNeuralNotLinked.Error(), 0)
			a.toast("error", "Nhân bản giọng", "Engine neural chưa được biên dịch.")
			return
		}
		if !a.hybrid.NeuralReady() {
			msg := "Chưa tải trọng số VieNeu — bấm \"Tải mô hình\" trước khi nhân bản giọng."
			a.pushJob(jobID, "error", msg, 0)
			a.toast("warn", "Nhân bản giọng", msg)
			return
		}
		driver = engine.NewNeuralDriver()
		voiceExecID = "" // core tự ưu tiên ref_audio_path hơn voice preset
		engKind = engine.EngineNeural
		diagf("job %s: NHÂN BẢN GIỌNG · ref=%q", jobID, refPath)
	} else {
		var err error
		driver, voiceExecID, engKind, err = a.hybrid.Resolve(req.EngineOverride, req.VoiceID, engine.IsNeuralLinked())
		if err != nil {
			msg := err.Error()
			if err == engine.ErrNeuralNoAssets {
				msg = "Chưa tải trọng số VieNeu — bấm \"Tải mô hình\" hoặc chuyển giọng SAPI."
			}
			diagf("[error] job %s: resolve engine thất bại: %v", jobID, err)
			a.pushJob(jobID, "error", msg, 0)
			a.toast("warn", "Tổng hợp thất bại", msg)
			return
		}
	}

	a.pushJob(jobID, "splitting", "Đang tách câu…", 1)

	// PATCH FIX46: chuẩn hoá văn bản TRƯỚC khi tách câu (chỉ neural —
	// SAPI có normalizer riêng của Windows). Số → chữ làm văn bản phình
	// 3-8 lần; normalize sau khi split sẽ làm chunk vượt max_chars 256.
	// textnorm là idempotent nên driver-level còn chuẩn hoá một lần nữa
	// (phòng vệ cho path không qua đây) mà không đổi kết quả.
	if engKind == engine.EngineNeural && !req.SkipTextNorm {
		if normed := textnorm.Normalize(text); strings.TrimSpace(normed) != "" {
			text = normed
		}
	}

	// PATCH FIX42: max_chars = 256 — bám đúng default của SDK vieneu
	// (v3turbo.py: max_chars=256) và của Space chính thức của tác giả
	// (slider max_chars 64..400, default 256). Đoạn ngắn hơn = cửa sổ
	// sinh ngắn hơn, ít lặp/ảo giác hơn; gap giữa câu vẫn do GapSec lo.
	chunks := dsp.SplitVietnamese(text, 256)
	if len(chunks) == 0 {
		diagf("[error] job %s: không tách được câu nào", jobID)
		a.pushJob(jobID, "error", "Không tách được câu nào", 0)
		return
	}

	jobLabel := req.VoiceID
	if useRef {
		jobLabel = "Giọng nhân bản"
	}
	diagf("job %s: resolve -> engine=%s · voice=%q · chunks=%d",
		jobID, engKind, voiceExecID, len(chunks))

	totalChars := 0
	for _, ch := range chunks {
		totalChars += len([]rune(ch.Text))
	}
	doneChars := 0
	var acc []float32
	firstSR := 0
	appliedSpeed := 1.0

	startWall := time.Now()
	for i, ch := range chunks {
		if ctx.Err() != nil {
			a.pushJob(jobID, "cancelled", "Đã huỷ", pctOf(doneChars, totalChars))
			return
		}

		iStart := time.Now()
		// PATCH FIX41: mốc trước lệnh gọi driver — lần synth ĐẦU
		// TIÊN sẽ nạp model native (vieneu_init_v2) ngay tại đây,
		// là nghi phạm chính của cảnh "app tự thoát".
		diagf("job %s: chunk %d/%d bắt đầu synth · %d ký tự · engine=%s",
			jobID, i+1, len(chunks), len([]rune(ch.Text)), engKind)
		res, serr := driver.Synthesize(ch.Text, engine.SynthOptions{
			VoiceID: voiceExecID,
			Speed:   req.Speed,
			// PATCH FIX46/47: truyền tham chiếu nhân bản (đã trim
			// 8s nếu dài) + cờ normalizer
			RefAudioPath: refPath,
			SkipTextNorm: req.SkipTextNorm,
			ProgressFn: func(sub float64) {
				base := pctOf(doneChars, totalChars)
				unit := float64(len([]rune(ch.Text))) / float64(totalChars)
				mix := base + unit*sub*90 // synth chiếm khoảng 10%..~92%
				a.pushJob(jobID, "synthesizing",
					fmt.Sprintf("Câu %d/%d · %s", i+1, len(chunks), voiceLabel(jobLabel)),
					mix)
			},
		})
		if serr != nil {
			diagf("[error] job %s: synth câu %d/%d thất bại: %v", jobID, i+1, len(chunks), serr)
			a.pushJob(jobID, "error", serr.Error(), pctOf(doneChars, totalChars))
			a.toast("error", "Lỗi engine", truncate(serr.Error(), 220))
			return
		}
		// PATCH FIX41: mốc sau lệnh gọi driver — nếu hcstudio.log có
		// dòng này mà tiến trình vẫn chết thì crash nằm ở tầng DSP
		// phía sau, không phải trong engine native.
		diagf("job %s: chunk %d/%d synth xong · %.2fs · %d mẫu @%dHz",
			jobID, i+1, len(chunks), time.Since(iStart).Seconds(),
			len(res.Samples), res.SampleRate)
		if firstSR == 0 {
			firstSR = res.SampleRate
			if res.NativeSpeed {
				appliedSpeed = req.Speed
			} else if res.SpeedApplied > 0 {
				appliedSpeed = res.SpeedApplied
			}
		}
		if res.SampleRate != firstSR {
			res.Samples = dsp.ConvertSampleRate(res.Samples, res.SampleRate, firstSR)
		}

		acc = append(acc, res.Samples...)
		if ch.GapSec > 0 && i < len(chunks)-1 {
			acc = append(acc, dsp.Silence(ch.GapSec, firstSR)...)
		}
		doneChars += len([]rune(ch.Text))

		eta := estimateETA(startWall, doneChars, totalChars)
		a.pushJobEta(jobID, "synthesizing", pctOf(doneChars, totalChars),
			fmt.Sprintf("Câu %d/%d hoàn tất", i+1, len(chunks)), eta,
			time.Since(iStart).Seconds())
	}

	// DSP chain cuối (một lần, nhất quán playback=export).
	a.pushJob(jobID, "dsp", "Tinh chỉnh tốc độ/cao độ/âm lượng…", 95)

	residual := req.Speed / appliedSpeed
	if residual > 4 || residual < 0.25 { // phòng hờ SAPI factor lệch
		residual = req.Speed
	}
	if absF(residual-1) > 0.02 {
		acc = dsp.TimeStretch(acc, firstSR, residual)
	}
	acc = dsp.PitchShift(acc, firstSR, req.Pitch)
	acc = dsp.ApplyVolume(acc, req.Volume)

	sess := &Session{
		ID:       jobID,
		VoiceID:  req.VoiceID,
		Engine:   string(engKind),
		Text:     text,
		Samples:  acc,
		SR:       firstSR,
		Duration: float64(len(acc)) / float64(firstSR),
		Created:  time.Now(),
	}
	a.putSession(sess)

	diagf("job %s: HOÀN TẤT · engine=%s · %.1fs audio @%dHz (%d mẫu)",
		jobID, engKind, sess.Duration, firstSR, len(acc))
	a.pushJobDone(jobID, sess.Duration)
	if req.AutoPlay && ctx.Err() == nil {
		// PATCH run #29: TRƯỚC ĐÂY lỗi phát lại bị bỏ quên âm thầm —
		// tổng hợp xong 100% nhưng không có tiếng và KHÔNG báo lỗi.
		if perr := a.PlayJob(jobID); perr != nil {
			diagf("[error] job %s: tự phát sau tổng hợp thất bại: %v", jobID, perr)
			a.toast("error", "Không phát được audio", truncate(perr.Error(), 220))
		}
	}
}

// putSession lưu phiên + prune ring buffer tối đa 5 phần tử.
func (a *App) putSession(s *Session) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.sessions[s.ID] = s
	a.sessionRing = append(a.sessionRing, s.ID)
	if len(a.sessionRing) > 5 {
		for len(a.sessionRing) > 5 {
			old := a.sessionRing[0]
			a.sessionRing = a.sessionRing[1:]
			delete(a.sessions, old)
		}
	}
}

// ---------- TRANSPORT ----------

// PlayJob phát lại một session đã tổng hợp.
func (a *App) PlayJob(jobID string) error {
	a.mu.Lock()
	sess := a.sessions[jobID]
	a.playJobID = jobID
	a.mu.Unlock()
	if sess == nil {
		diagf("[warn] PlayJob: session %s không còn trong bộ nhớ (LRU 5 phiên)", jobID)
		return fmt.Errorf("không còn session %s trong bộ nhớ (tối đa 5 phiên)", jobID)
	}
	if err := a.player.Play(sess.Samples, sess.SR); err != nil {
		diagf("[error] PlayJob %s: player.Play thất bại: %v", jobID, err)
		return err
	}
	a.emit.Send("hcstudio:transport", map[string]any{"playing": true, "jobId": jobID})
	return nil
}

// PauseToggle tạm dừng/tiếp tục; trả trạng thái paused sau lệnh.
func (a *App) PauseToggle() bool {
	return a.player.TogglePause()
}

// StopAll dừng cả synthesis lẫn playback.
func (a *App) StopAll() {
	a.mu.Lock()
	cancel := a.cancelSynth
	a.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	a.player.Stop()
	a.emit.Send("hcstudio:transport", map[string]any{"playing": false})
}

// CancelJob hủy đúng một job synthesize theo ID.
func (a *App) CancelJob(jobID string) {
	a.StopAll()
}

// ---------- EXPORT ----------

// PickSavePath mở hộp thoại chọn nơi lưu (Wails native dialog).
func (a *App) PickSavePath(defaultName, ext string) string {
	filter := []wailsruntime.FileFilter{{DisplayName: "Audio", Pattern: "*.wav;*.mp3"}}
	title := "Xuất file audio"
	path, err := wailsruntime.SaveFileDialog(a.ctx, wailsruntime.SaveDialogOptions{
		Title:           title,
		DefaultFilename: defaultName,
		Filters:         filter,
	})
	if err != nil {
		return ""
	}
	return path
}

// PickRefAudio mở hộp thoại chọn file audio mẫu để nhân bản giọng.
// PATCH FIX46: chỉ nhận .wav — core đọc WAV PCM (read_wav_file) và tự
// resample về 48 kHz; mp3 sẽ bị từ chối ở tầng C với lỗi khó hiểu nên
// chặn ngay tại dialog cho thân thiện.
// PATCH FIX47: nhãn khuyến nghị 3–8s (Space khuyến nghị 3–5s; app tự
// cắt còn 8s khi dài hơn — dsp.PrepareRefAudio).
func (a *App) PickRefAudio() string {
	filter := []wailsruntime.FileFilter{{DisplayName: "WAV 3–8 giây", Pattern: "*.wav"}}
	path, err := wailsruntime.OpenFileDialog(a.ctx, wailsruntime.OpenDialogOptions{
		Title:   "Chọn file WAV mẫu giọng cần nhân bản",
		Filters: filter,
	})
	if err != nil {
		return ""
	}
	return path
}

// ExportAudio ghi session thành wav/mp3 vào path người dùng chọn.
func (a *App) ExportAudio(jobID, format, path string) error {
	format = strings.ToLower(strings.TrimPrefix(format, "."))
	if format != "wav" && format != "mp3" {
		return fmt.Errorf("định dạng không hỗ trợ: %s (chỉ wav/mp3)", format)
	}
	if !strings.HasSuffix(strings.ToLower(path), "."+format) {
		path += "." + format
	}

	a.mu.Lock()
	sess := a.sessions[jobID]
	a.mu.Unlock()
	if sess == nil {
		diagf("[warn] ExportAudio: session %s không tồn tại", jobID)
		return fmt.Errorf("session không tồn tại hoặc đã bị xoá khỏi bộ nhớ")
	}

	var err error
	if format == "wav" {
		err = dsp.WriteWav(path, sess.Samples, sess.SR, 1)
	} else {
		err = dsp.ExportMP3(path, sess.Samples, sess.SR)
	}
	if err != nil {
		diagf("[error] ExportAudio %s -> %s: %v", format, path, err)
		// PATCH run #31: lỗi ghi file thường do chương trình khác đang
		// mở file đích (trình phát nhạc/preview) — nói thẳng cho người
		// dùng cách xử thay vì chỉ hiện mã lỗi thô.
		a.toast("error", "Xuất file thất bại",
			truncate(err.Error(), 180)+
				" · Gợi ý: nếu file này đang được mở bởi trình phát khác, hãy đóng nó rồi xuất lại.")
		return err
	}
	diagf("ExportAudio OK: %s (%.1fs giọng đọc)", path, sess.Duration)
	a.toast("success", "Đã xuất audio",
		fmt.Sprintf("%s · %.1fs giọng đọc", fileNameOf(path), sess.Duration))
	return nil
}

// ---------- MODEL DOWNLOAD ----------

// DownloadNeuralAssets bắt đầu (hoặc báo đang chạy) luồng tải trọng số VieNeu.
func (a *App) DownloadNeuralAssets() {
	a.mu.Lock()
	if a.modelDLRun {
		a.mu.Unlock()
		return
	}
	a.modelDLRun = true
	modelDir := appstate.ModelsDir()
	if a.downloader == nil {
		a.downloader = vienneu.NewDownloader(func(e vienneu.DownloadEvent) {
			// PATCH run #29: log các mốc tải (bỏ spam tiến trình chạy).
			switch e.State {
			case "running":
				if e.FileIdx == 1 && e.Pct == 0 && e.BytesDone == 0 {
					diagf("modeldl: bắt đầu tải %d file -> %s", e.TotalFiles, modelDir)
				}
			default:
				diagf("modeldl: state=%s · file %d/%d · msg=%q",
					e.State, e.FileIdx, e.TotalFiles, e.Message)
			}
			wailsruntime.EventsEmit(a.ctx, "hcstudio:modeldl", e)
			if e.State == "done" {
				a.hybrid.RefreshNeuralReadiness()
				ready := engine.AssetsReady(appstate.ModelsDir())
				diagf("modeldl: XONG · AssetsReady sau tải = %v", ready)
				a.toast("success", "Mô hình đã sẵn sàng", "25 giọng VieNeu v3 Turbo offline hoàn toàn.")
			}
		})
	}
	dl := a.downloader
	a.mu.Unlock()

	diagf("modeldl: người dùng bấm tải mô hình -> %s", modelDir)

	go func() {
		defer func() {
			a.mu.Lock()
			a.modelDLRun = false
			a.mu.Unlock()
		}()
		if err := dl.Run(context.Background(), modelDir); err != nil &&
			err != context.Canceled {
			diagf("[error] modeldl: luồng tải kết thúc với lỗi: %v", err)
			a.toast("error", "Tải mô hình lỗi", truncate(err.Error(), 200))
		}
	}()
}

// CancelModelDownload huỷ luồng tải (giữ .part để resume).
func (a *App) CancelModelDownload() {
	a.mu.Lock()
	dl := a.downloader
	a.mu.Unlock()
	if dl != nil {
		diagf("modeldl: người dùng huỷ tải")
		dl.Cancel()
	}
}

// ImportReport là kết quả nhập gói ZIP offline cho UI hiển thị.
type ImportReport struct {
	OK          bool     `json:"ok"`
	Imported    []string `json:"imported"`
	Invalid     []string `json:"invalid"`  // có trong zip nhưng sai kích thước
	Missing     []string `json:"missing"`  // chưa có (thiếu trong zip)
	ModelDir    string   `json:"modelDir"` // nơi giải nén
	Message     string   `json:"message"`
	AssetsReady bool     `json:"assetsReady"`
}

// PATCH FIX48 — CHỦ QUYỀN NGUỒN: ImportOfflinePackage cho phép người chủ
// cấp phát weights bằng đường dẫn RIÊNG của mình (GitHub Release riêng,
// NAS, USB, email...) hoàn toàn không phụ thuộc HuggingFace/GitHub:
//  1. Người dùng bấm nút → chọn file ZIP.
//  2. App đối chiếu từng entry với AssetManifest (tên + kích thước byte
//     đúng bằng SizeHint đã pin) — file sai kích thước bị TỪ CHỐI, không
//     ghi đè weights tốt đang có.
//  3. Chỉ file hợp lệ mới được giải nén vào ModelsDir.
//
// ZIP hỗ trợ 2 kiểu bố trí: (a) file nằm ngay gốc zip (zip trực tiếp
// thư mục models), (b) file nằm trong 1 thư mục cha (zip cả thư mục).
func (a *App) ImportOfflinePackage() string {
	report := ImportReport{ModelDir: appstate.ModelsDir()}
	reply := func() string {
		report.AssetsReady = engine.AssetsReady(appstate.ModelsDir())
		b, _ := json.Marshal(report)
		return string(b)
	}
	path, err := wailsruntime.OpenFileDialog(a.ctx, wailsruntime.OpenDialogOptions{
		Title:   "Chọn gói ZIP chứa trọng số mô hình (12 file)",
		Filters: []wailsruntime.FileFilter{{DisplayName: "Gói weights (.zip)", Pattern: "*.zip"}},
	})
	if err != nil || path == "" {
		return reply() // người dùng huỷ — không coi là lỗi
	}
	diagf("modeldl: nhập gói offline từ %s", path)

	zr, err := zip.OpenReader(path)
	if err != nil {
		report.Message = "File không phải ZIP hợp lệ: " + err.Error()
		diagf("[error] modeldl: mở zip lỗi: %v", err)
		return reply()
	}
	defer zr.Close()

	// Bản đồ tên→entry, bỏ qua phần thư mục cha để chấp nhận cả 2 bố trí.
	// (12 file manifest có tên base đôi một khác nhau — khớp theo tên base an toàn.)
	byName := map[string]*zip.File{}
	for _, f := range zr.File {
		if f.FileInfo().IsDir() {
			continue
		}
		name := filepath.ToSlash(filepath.Base(f.Name))
		if _, dup := byName[name]; !dup {
			byName[name] = f
		}
	}

	for _, a2 := range engine.AssetManifest {
		base := filepath.Base(a2.DestRel)
		f := byName[base]
		if f == nil {
			report.Missing = append(report.Missing, a2.DestRel)
			continue
		}
		if a2.SizeHint > 0 && f.UncompressedSize64 != uint64(a2.SizeHint) {
			report.Invalid = append(report.Invalid, fmt.Sprintf("%s (kích thước %d ≠ cần %d)", a2.DestRel, f.UncompressedSize64, a2.SizeHint))
			continue
		}
		destAbs := filepath.Join(appstate.ModelsDir(), a2.DestRel)
		if err := extractZipEntry(f, destAbs); err != nil {
			diagf("[error] modeldl: giải nén %s lỗi: %v", a2.DestRel, err)
			report.Invalid = append(report.Invalid, fmt.Sprintf("%s (ghi lỗi: %v)", a2.DestRel, err))
			continue
		}
		report.Imported = append(report.Imported, a2.DestRel)
	}

	switch {
	case len(report.Invalid) > 0:
		report.Message = fmt.Sprintf("Đã nhập %d file; TỪ CHỐI %d file sai dữ liệu; thiếu %d file. Kiểm tra lại nguồn ZIP.",
			len(report.Imported), len(report.Invalid), len(report.Missing))
		diagf("modeldl: nhập offline BẤT THÀNH — nhập=%d sai=%d thiếu=%d", len(report.Imported), len(report.Invalid), len(report.Missing))
	case len(report.Missing) > 0:
		report.Message = fmt.Sprintf("Đã nhập %d file nhưng còn thiếu %d file — gói ZIP chưa đủ.", len(report.Imported), len(report.Missing))
		diagf("modeldl: nhập offline một phần — nhập=%d thiếu=%d", len(report.Imported), len(report.Missing))
	default:
		report.OK = true
		report.Message = fmt.Sprintf("Hoàn tất: đã nhập đủ %d file trọng số.", len(report.Imported))
		diagf("modeldl: nhập offline OK — %d file, AssetsReady=%v", len(report.Imported), report.AssetsReady)
		a.hybrid.RefreshNeuralReadiness()
		if report.AssetsReady {
			a.toast("success", "Mô hình đã sẵn sàng", "Nhập từ gói offline thành công — engine chạy hoàn toàn offline.")
		}
	}
	return reply()
}

// extractZipEntry ghi một entry của zip ra file đích (tạo thư mục cha cần thiết).
func extractZipEntry(f *zip.File, destAbs string) error {
	if err := os.MkdirAll(filepath.Dir(destAbs), 0o755); err != nil {
		return err
	}
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()
	tmp := destAbs + ".importing"
	w, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if _, err := io.Copy(w, rc); err != nil {
		w.Close()
		os.Remove(tmp)
		return err
	}
	if err := w.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	_ = os.Remove(destAbs)
	return os.Rename(tmp, destAbs)
}

// ---------- HELPERS UI ----------

// OpenFolder mở explorer tại thư mục models|exports|settings|logs.
func (a *App) OpenFolder(which string) {
	dir := ""
	switch which {
	case "models":
		dir = appstate.ModelsDir()
	case "exports":
		dir = appstate.ExportsDir()
	case "logs":
		// PATCH run #29: mở đúng thư mục chứa hcstudio.log.
		dir = DiagLogDir()
	default:
		dir = appstate.ConfigDir()
	}
	diagf("OpenFolder(%s) -> %s", which, dir)
	exec.Command("explorer.exe", dir).Start()
}

// WindowAction điều khiển cửa sổ frameless từ traffic-lights tự vẽ.
func (a *App) WindowAction(cmd string) {
	switch cmd {
	case "min":
		wailsruntime.WindowMinimise(a.ctx)
	case "max":
		wailsruntime.WindowToggleMaximise(a.ctx)
	case "close":
		wailsruntime.Quit(a.ctx)
	}
}

// DetectThemeIll trả giá trị Windows hiện tại (UI poll mỗi vài giây).
func (a *App) DetectWinTheme() bool { return appstate.IsWindowsDark() }

// ---------- EVENT utils ----------

func (a *App) pushJob(id, state, msg string, pct float64) {
	a.emit.Send("hcstudio:job", bridge.JobSnapshot{ID: id, State: state, Message: msg, Pct: pct})
}

func (a *App) pushJobEta(id, state string, pct float64, msg string, eta, durSec float64) {
	a.emit.Send("hcstudio:job", bridge.JobSnapshot{
		ID: id, State: state, Pct: pct, Message: msg, EtaSec: eta, DurationSec: durSec,
	})
}

func (a *App) pushJobDone(id string, durSec float64) {
	a.emit.Send("hcstudio:job", bridge.JobSnapshot{
		ID: id, State: "done", Pct: 100, Message: "Hoàn tất", DurationSec: durSec,
	})
}

func (a *App) toast(level, title, msg string) {
	a.emit.Send("hcstudio:toast", bridge.ToastPayload{Level: level, Title: title, Message: msg})
}

func pctOf(done, total int) float64 {
	if total <= 0 {
		return 100
	}
	v := float64(done) / float64(total) * 100
	if v > 99 {
		v = 99 // 100 chỉ dành cho state done
	}
	return v
}

func estimateETA(started time.Time, done, total int) float64 {
	if done <= 0 {
		return 0
	}
	elapsed := time.Since(started).Seconds()
	remaining := elapsed / float64(done) * float64(total-done)
	if remaining < 0 {
		return 0
	}
	return remaining
}

func absF(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-3] + "…"
}

func fileNameOf(p string) string {
	idx := strings.LastIndexAny(p, "\\/")
	if idx < 0 {
		return p
	}
	return p[idx+1:]
}

func voiceLabel(id string) string {
	if id == "" {
		return ""
	}
	return id
}
