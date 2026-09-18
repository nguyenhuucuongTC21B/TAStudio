// Package engine định nghĩa hợp đồng chung cho mọi lõi TTS của HCStudio.
package engine

import "fmt"

// VoiceEngine các lõi được hỗ trợ.
type VoiceEngine string

const (
	EngineNeural VoiceEngine = "neural" // VieNeu v3 Turbo qua C ABI
	EngineSAPI   VoiceEngine = "sapi"   // SAPI5 hệ thống Windows
)

// Voice mô tả một giọng đọc hiển thị trên UI.
type Voice struct {
	ID          string      `json:"id"` // neural: tên tiếng Việt gốc; sapi: chuỗi Description
	Name        string      `json:"name"`
	Gender      string      `json:"gender"` // male | female | unknown
	Region      string      `json:"region"` // Bắc | Trung | Nam | Hệ thống
	Style       string      `json:"style"`  // tu_nhien | tin_tuc | doc_truyen |…
	Engine      VoiceEngine `json:"engine"`
	Description string      `json:"description"`
	Available   bool        `json:"available"`
	Rank        int         `json:"rank"` // thứ tự ưu tiên sắp xếp UI
}

// SynthOptions tham số cho một lần tổng hợp chunk.
type SynthOptions struct {
	VoiceID     string
	Speed       float64 // chỉ đọc tham khảo; WSOLA ở tầng pipeline xử lý residual
	Temperature float64
	TopK        int
	TopP        float64
	Threads     int
	ProgressFn  func(subPct float64) // callback tiến trình trong chunk [0..1]

	// PATCH FIX46 — Nhân bản giọng (zero-shot): đường dẫn file WAV mẫu
	// (mono/stereo, mọi sample-rate — core tự resample về 48kHz). Khi khác
	// rỗng, engine BỎ voice preset và dùng tham chiếu âm thanh này làm
	// "giọng" (encode qua MOSS codec thành codes, chèn vào audio ref slot).
	RefAudioPath string

	// PATCH FIX46 — SkipTextNorm: tắt text normalizer (số/ký hiệu/emoji).
	// Mặc định false = luôn chuẩn hoá văn bản trước khi đưa xuống engine.
	SkipTextNorm bool
}

// SynthResult PCM float32 mono.
type SynthResult struct {
	Samples      []float32
	SampleRate   int
	NativeSpeed  bool    // true nếu engine đã tự áp đúng Speed của request
	SpeedApplied float64 // hệ số tốc độ engine đã áp sẵn (SAPI rate); pipeline chỉ xử phần dư
}

// Driver là contract mà cả hai tầng engine phải implement.
type Driver interface {
	Name() string
	ListVoices() ([]Voice, error)
	Synthesize(text string, opts SynthOptions) (*SynthResult, error)
	Close() error
}

// Lỗi chuẩn hoá để pipeline nhận diện và fallback.
var (
	ErrNeuralNotLinked = fmt.Errorf("engine neural chưa được biên dịch vào binary (build với -tags vieneu)")
	ErrNeuralNoAssets  = fmt.Errorf("trọng số VieNeu chưa tải về máy")
	ErrVoiceNotFound   = fmt.Errorf("không tìm thấy giọng đọc tương ứng")
	ErrSynthesisFailed = fmt.Errorf("tổng hợp thất bại")
)
