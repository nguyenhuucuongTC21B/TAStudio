package engine

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
)

// atomicBool là bí danh dễ đọc trong file này.
type atomicBool = atomic.Bool

// AssetSpec mô tả một tệp trọng số của profile vieneu-v3-onnx cần tải về.
// URL bám đúng 1-1 script chính thức run-v3-tts-test.ps1 của VieNeu-TTS.cpp.
type AssetSpec struct {
	URL       string `json:"url"`
	DestRel   string `json:"destRel"`  // đường dẫn tương đối trong ModelsDir()
	SizeHint  int64  `json:"sizeHint"` // 0 nếu chưa biết trước (hiển thị khi server trả Content-Length)
	Mandatory bool   `json:"mandatory"`
}

const (
	// PATCH FIX42: PIN REVISION — không còn tải "main" nữa.
	//
	// Bằng chứng drift (ngày 2026-09-05..06, tra cứu HF API + GitHub):
	//  - Repo model thêm onnx_int8/ + onnx_update/ + update/ và tác giả
	//    revert/restore weights 2 lần trong NGÀY 05-09 (commit a010b3e
	//    revert, 8b7e9cff restore) — main KHÔNG còn bất biến.
	//  - voices_v3_turbo.json trên GitHub main đổi liên tục (v3.3.0:
	//    20 giọng / 140.175 B / Adam @f49d7024; bản curated mới: 25
	//    giọng / 180.240 B / default "Minh Quân Pro").
	//
	// PATCH FIX46: nâng cấp CÓ KIỂM CHỨNG lên revision fa2b1afa (25
	// giọng). Bằng chứng tương thích với C++ core @cc037cf:
	//  - vieneu_v3_onnx_voice.cpp:load_voices duyệt MỌI entry "presets"
	//    (không hard-count 20), đọc "codes" (shape n_vq=16 — config int8
	//    / turbo đều giữ n_vq=16) và "reserved_id" (null hợp lệ).
	//  - default_voice mới "Minh Quân Pro" tồn tại trong presets.
	//  - 20 giọng v3.3.0 giữ nguyên ID + codes → settings cũ không vỡ.
	// Giải pháp: khoá cứng URL vào đúng revision đã được xác minh cấu
	// trúc. Muốn nâng cấp revision mới phải qua một FIX package có
	// kiểm chứng, không bao giờ tự đổi dưới chân app.
	hfV3Commit = "8b7e9cffb4b41918cb638b9f62f0a751184d14a6"
	hfV3Base   = "https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/" + hfV3Commit
	// PATCH FIX49: subfolder onnx_update/ @8b7e9cff - weights arch vieneu_v3
	// (acoustic 1 layer, speaker_emb 192, style tokens). Xac minh 2026-09-18:
	// tree API du 7 file; HEAD sizes khop SizeHint trong manifest; prefill +
	// decode_step LFS oid TRUNG onnx/ (graph backbone khong doi); acoustic +
	// heads + backbone_shared khac oid (weights moi). Day chinh la bo weights
	// Space demo HF chay (onnx_runtime_lite.py mac dinh onnx_update).
	hfV3Update = hfV3Base + "/onnx_update"
	// PATCH FIX51: subfolder onnx_int8/ @8b7e9cff - weights luong tu hoa
	// (backbone 103.891.968 B ~ 1/4 f32; decode/prefill int8 graph to hon
	// nhung nhe RAM khi chay). Xac minh 2026-09-18 qua HF tree API: du 7
	// file, ten TRUNG KHOP update/ (config, tokenizer, prefill, decode,
	// acoustic, heads, backbone). Tong 165.496.148 B ~ 158 MB.
	hfInt8Base = hfV3Base + "/onnx_int8"
	// PATCH FIX48: pin cả MOSS theo commit — trước đây trỏ "resolve/main"
	// (không bất biến). Commit ceff0d07 là HEAD của repo ngày 2026-04-17,
	// khớp đúng 4 file codec app đang dùng (SizeHint xác minh bằng HEAD).
	// Từ giờ MỌI asset đều khóa revision, không còn URL nào trôi.
	hfMossCommit = "ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae"
	hfMossBase   = "https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX/resolve/" + hfMossCommit
	voicesCommit = "fa2b1afa1ed7657ca47987b6b799ec20d645047e" // FIX46: 25 giọng, Minh Quân Pro, 180.240 B (v3.3.0 cũ: f49d7024…, 20 giọng)
	hfVoicesJSON = "https://raw.githubusercontent.com/pnnbao97/VieNeu-TTS/" + voicesCommit + "/src/vieneu/assets/voices_v3_turbo.json"
)

// PATCH FIX48 — CHỦ QUYỀN NGUỒN (supply-chain ownership):
//
// Toàn bộ weights sau khi tải xong nằm 100% trên máy người dùng
// (%AppData%\HCStudio\models\vieneu-v3-turbo\) và engine chạy offline
// vĩnh viễn — onnxruntime.dll ship cạnh exe, KHÔNG có điểm nào lúc
// inference gọi server. Mạng CHỈ dùng trong 2 thời điểm:
//   (1) lần đầu chạy app (tải weights), (2) khi bấm tải lại.
//
// Rủi ro còn lại duy nhất: upstream chết (HF/GitHub xoá repo hoặc đổi
// đường dẫn) làm NGƯỜI DÙNG MỚI không tải được lần đầu. Cơ chế phòng:
//
//   - Biến môi trường HCSTUDIO_ASSET_MIRROR: nếu đặt (ví dụ
//     "https://huggingface.co/<ban>/HCStudio-Models" hoặc
//     "https://may-chu-cua-ban.com/hcstudio-models"), app ƯU TIÊN tải
//     từ mirror trước theo đúng cấu trúc thư mục models (config.json,
//     tokenizer.json, voices_v3_turbo.json, onnx/…, codec/…); mirror
//     lỗi thì tự fallback về URL gốc đã pin. File trên mirror PHẢI
//     byte-identical với bản gốc (kiểm tra bằng SizeHint).
//   - ImportOfflinePackage (app.go): nhập gói ZIP weights tải từ bất
//     kỳ đâu bạn chủ (GitHub Release riêng, NAS, USB) — máy KHÔNG
//     mạng vẫn cài đầy đủ.
//   - Chi tiết cách tự dựng mirror xem README-FIX48.md.

// mirrorBase trả về mirror do người dùng chủ cấu hình, rỗng nếu không đặt.
// Đọc mỗi lần gọi (không cache) để có thể đổi mà không cần khởi động lại.
func mirrorBase() string {
	return strings.TrimRight(os.Getenv("HCSTUDIO_ASSET_MIRROR"), "/")
}

// AssetURLs trả về danh sách URL thử lần lượt cho một asset:
// mirror (nếu cấu hình) trước, URL gốc đã pin sau.
func AssetURLs(a AssetSpec) []string {
	urls := make([]string, 0, 2)
	if mb := mirrorBase(); mb != "" {
		urls = append(urls, mb+"/"+filepath.ToSlash(a.DestRel))
	}
	urls = append(urls, a.URL)
	return urls
}

// AssetManifest là danh sách cố định nhúng trong binary.
// Thứ tự: tệp nhỏ trước để người dùng thấy tiến trình khởi động nhanh.
//
// PATCH run #31: điền ĐỦ SizeHint = Content-Length thật từ HF/CDN (kiem tra
// HEAD ngày 2026-09-03, tổng 546.433.245 byte ≈ 521 MB). Trước đây mọi
// SizeHint = 0 ⇒ Downloader tính total = 0 ⇒ pct = done/1*100 ⇒ UI hiển thị
// 14.227.792.400% (screenshot run #30). SizeHint thật còn giúp:
//   - skip-resume chính xác (file đủ cỡ mới được bỏ qua)
//   - hiển thị "X MB / 521,2 MB" đúng thay vì "X MB / X MB".
var AssetManifest = []AssetSpec{
	{
		// FIX46: revision fa2b1afa — 25 giọng (thêm Adam bựa, Anh Khôi,
		// Minh Quân Pro, Thiền Tâm Đức, Mạnh Dũng), default "Minh Quân Pro".
		URL: hfVoicesJSON, DestRel: "voices_v3_turbo.json",
		SizeHint: 180_240, Mandatory: true,
	},
	{
		// PATCH FIX49: config cua kien truc update NAM TRONG onnx_update/
		// (model_type vieneu_v3, acoustic 1 layer, speaker_embedding_dim
		// 192, 8 emotion + 10 style tokens). So khop byte-identical voi
		// config_update.json da luu o fix46_build.
		URL: hfV3Update + "/config.json", DestRel: filepath.Join("update", "config.json"),
		SizeHint: 2_152, Mandatory: true,
	},
	{
		URL: hfV3Update + "/tokenizer.json", DestRel: filepath.Join("update", "tokenizer.json"),
		SizeHint: 22_320, Mandatory: true,
	},
	{
		URL:      hfMossBase + "/moss_audio_tokenizer_encode.onnx",
		DestRel:  filepath.Join("codec", "moss_audio_tokenizer_encode.onnx"),
		SizeHint: 815_775, Mandatory: true,
	},
	{
		URL:      hfMossBase + "/moss_audio_tokenizer_encode.data",
		DestRel:  filepath.Join("codec", "moss_audio_tokenizer_encode.data"),
		SizeHint: 44_507_136, Mandatory: true,
	},
	{
		URL:      hfMossBase + "/moss_audio_tokenizer_decode_full.onnx",
		DestRel:  filepath.Join("codec", "moss_audio_tokenizer_decode_full.onnx"),
		SizeHint: 681_902, Mandatory: true,
	},
	{
		URL:      hfMossBase + "/moss_audio_tokenizer_decode_shared.data",
		DestRel:  filepath.Join("codec", "moss_audio_tokenizer_decode_shared.data"),
		SizeHint: 44_198_912, Mandatory: true,
	},
	{
		// PATCH FIX49: chuyen sang onnx_update/ (fp32, arch vieneu_v3).
		// DestRel dung thu muc MOI "update/" - khong tai su dung "onnx/"
		// vi backbone_shared.data CUNG size 415.319.040 B nhung KHAC
		// noi dung (LFS oid 6f28d660... vs c7c07219...): neu giu path cu,
		// skip-theo-size se giu nham weights cu duoi may user.
		// prefill + decode_step byte-identical voi onnx/ (oid trung) -
		// tai lai chi ton 630 KB nen khong can toi uu skip.
		URL:      hfV3Update + "/vieneu_prefill.onnx",
		DestRel:  filepath.Join("update", "vieneu_prefill.onnx"),
		SizeHint: 324_499, Mandatory: true,
	},
	{
		URL:      hfV3Update + "/vieneu_decode_step.onnx",
		DestRel:  filepath.Join("update", "vieneu_decode_step.onnx"),
		SizeHint: 306_134, Mandatory: true,
	},
	{
		URL:      hfV3Update + "/vieneu_v3_heads.npz",
		DestRel:  filepath.Join("update", "vieneu_v3_heads.npz"),
		SizeHint: 52_219_622, Mandatory: true,
	},
	{
		URL:      hfV3Update + "/vieneu_acoustic_cached.onnx",
		DestRel:  filepath.Join("update", "vieneu_acoustic_cached.onnx"),
		SizeHint: 7_207_223, Mandatory: true,
	},
	{
		URL:      hfV3Update + "/vieneu_backbone_shared.data",
		DestRel:  filepath.Join("update", "vieneu_backbone_shared.data"),
		SizeHint: 415_319_040, Mandatory: true,
	},
	{
		// PATCH FIX50: denoiser (resemble-enhance denoise, ONNX) cho đường
		// clone giọng - làm sạch audio mẫu trước khi trích x-vector. Bằng
		// chứng 2026-09-18: root repo @pin 8b7e9cff, size khớp HEAD,
		// sha256 b7621953... == LFS oid trên HF. Graph IO: mag/cos/sin
		// (1,841,T) -> sep_mag/sep_cos/sep_sin (STFT 1680/420).
		URL:      hfV3Base + "/denoiser.onnx",
		DestRel:  "denoiser.onnx",
		SizeHint: 42_661_414, Mandatory: true,
	},
	{
		// PATCH FIX50: speaker encoder xvector 192-d cho đường clone -
		// trích speaker embedding từ audio mẫu (fbank 80 @16k -> 192-d),
		// rồi đi qua xvec_w (768x192) của heads.npz thành anchor. sha256
		// a6ac6a63... == LFS oid. Tổng manifest FIX50: 14 file,
		// 636.749.792 byte ≈ 607 MB.
		URL:      hfV3Base + "/speaker_encoder.onnx",
		DestRel:  "speaker_encoder.onnx",
		SizeHint: 28_303_423, Mandatory: true,
	},

	// ── PATCH FIX51: BỘ INT8 (TÙY CHỌN, NHẸ RAM ~4 LẦN) ──────
	// Mandatory: false -> không bao giờ chặn wizard/ready/import.
	// Lấy khi: nút "Tải gói int8" trong UI, gói ZIP offline kèm theo,
	// hoặc Setup 1-file (Phương án B) chép sẵn. Bật qua nút gạt
	// "Nhẹ RAM (int8)"; engine chỉ đọc int8/ khi ĐỦ 7 file đúng byte
	// (Int8AssetsReady) — thiếu là tự rơi về update/ (f32), không nửa vời.
	{
		URL:      hfInt8Base + "/config.json",
		DestRel:  filepath.Join("int8", "config.json"),
		SizeHint: 2_152, Mandatory: false,
	},
	{
		URL:      hfInt8Base + "/tokenizer.json",
		DestRel:  filepath.Join("int8", "tokenizer.json"),
		SizeHint: 22_320, Mandatory: false,
	},
	{
		URL:      hfInt8Base + "/vieneu_prefill.onnx",
		DestRel:  filepath.Join("int8", "vieneu_prefill.onnx"),
		SizeHint: 1_090_823, Mandatory: false,
	},
	{
		URL:      hfInt8Base + "/vieneu_decode_step.onnx",
		DestRel:  filepath.Join("int8", "vieneu_decode_step.onnx"),
		SizeHint: 1_062_040, Mandatory: false,
	},
	{
		URL:      hfInt8Base + "/vieneu_v3_heads.npz",
		DestRel:  filepath.Join("int8", "vieneu_v3_heads.npz"),
		SizeHint: 52_219_622, Mandatory: false,
	},
	{
		URL:      hfInt8Base + "/vieneu_acoustic_cached.onnx",
		DestRel:  filepath.Join("int8", "vieneu_acoustic_cached.onnx"),
		SizeHint: 7_207_223, Mandatory: false,
	},
	{
		URL:      hfInt8Base + "/vieneu_backbone_shared.data",
		DestRel:  filepath.Join("int8", "vieneu_backbone_shared.data"),
		SizeHint: 103_891_968, Mandatory: false,
	},
}

// ModelPaths là bộ đường dẫn tuyệt đối dùng cho vieneu_init_params_v2.
type ModelPaths struct {
	ModelDir string
	OnnxDir  string
	CodecDir string
	Voices   string
	Config   string
	Tokenize string
}

// ResolveModelPaths tính các đường dẫn chuẩn từ thư mục models gốc.
func ResolveModelPaths(modelDir string) ModelPaths {
	// PATCH FIX49: engine doc weights tu thu muc update/ (config +
	// tokenizer + 4 file graph/weights deu nam trong do). Codec va voices
	// giu nguyen vi khong doi. Thu muc onnx/ cu con lai tren disk lam
	// rollback offline (FIX48 tro ve) nhung engine khong con doc.
	// PATCH FIX51: nếu người dùng bật "Nhẹ RAM (int8)" (PreferInt8Dir)
	// và máy ĐỦ 7 file int8/ đúng byte thì nạp bản int8 — cùng tên file,
	// cùng kiến trúc (L=1), engine C++ KHÔNG đổi. Thiếu bất kỳ file nào
	// là tự rơi về update/ (f32) — không bao giờ nửa vời.
	upd := filepath.Join(modelDir, "update")
	if PreferInt8Dir.Load() && Int8AssetsReady(modelDir) {
		upd = filepath.Join(modelDir, "int8")
	}
	return ModelPaths{
		ModelDir: modelDir,
		OnnxDir:  upd,
		CodecDir: filepath.Join(modelDir, "codec"),
		Voices:   filepath.Join(modelDir, "voices_v3_turbo.json"),
		Config:   filepath.Join(upd, "config.json"),
		Tokenize: filepath.Join(upd, "tokenizer.json"),
	}
}

// PATCH FIX51 — PreferInt8Dir: công tắc "Nhẹ RAM (int8)". app.go set
// lúc startup ĐỨNG TRƯỚC NewHybrid (engine chỉ đọc một lần khi init).
var PreferInt8Dir atomicBool

// Int8Files là số file int8 bắt buộc phải đủ để bật chế độ nhẹ RAM.
const Int8Files = 7

// Int8AssetsReady kiểm tra ĐỦ 7 file int8 với ĐÚNG kích thước byte.
// Khác MissingAssets (chỉ cần tồn tại >0), ở đây nghiêm hơn: sai size
// là coi như không có — weights âm thầm sai byte còn nguy hơn thiếu.
func Int8AssetsReady(modelDir string) bool {
	n := 0
	for _, a := range AssetManifest {
		if !strings.HasPrefix(filepath.ToSlash(a.DestRel), "int8/") {
			continue
		}
		full := filepath.Join(modelDir, a.DestRel)
		st, err := os.Stat(full)
		if err != nil || st.Size() != a.SizeHint {
			return false
		}
		n++
	}
	return n == Int8Files
}

// MissingAssets liệt kê những tệp bắt buộc còn thiếu trong modelDir.
func MissingAssets(modelDir string) []string {
	var missing []string
	for _, a := range AssetManifest {
		if !a.Mandatory {
			continue
		}
		full := filepath.Join(modelDir, a.DestRel)
		st, err := os.Stat(full)
		if err != nil || st.Size() <= 0 {
			missing = append(missing, a.DestRel)
		}
	}
	return missing
}

// AssetsReady trả true nếu toàn bộ assets bắt buộc đã tải xong.
func AssetsReady(modelDir string) bool {
	return len(MissingAssets(modelDir)) == 0
}

// DescribeBytes format số byte dễ đọc cho event UI.
func DescribeBytes(b int64) string {
	const kb, mb, gb = 1 << 10, 1 << 20, 1 << 30
	switch {
	case b >= gb:
		return fmt.Sprintf("%.2f GB", float64(b)/gb)
	case b >= mb:
		return fmt.Sprintf("%.1f MB", float64(b)/mb)
	case b >= kb:
		return fmt.Sprintf("%.1f KB", float64(b)/kb)
	default:
		return fmt.Sprintf("%d B", b)
	}
}
