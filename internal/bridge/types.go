// Package bridge định nghĩa hợp đồng dữ liệu JSON trao đổi frontend↔backend.
// Toàn bộ struct đều camelCase để JS tiêu thụ trực tiếp không cần chuyển đổi.
package bridge

import "hcstudio/internal/engine"

// AppState snapshot khởi động trả về cho GetAppState.
type AppState struct {
	Version        string   `json:"version"`
	IsDarkWin      bool     `json:"isDarkWin"`
	NeuralLinked   bool     `json:"neuralLinked"`
	NeuralReady    bool     `json:"neuralReady"`
	MissingFiles   []string `json:"missingFiles"`
	ModelDir       string   `json:"modelDir"`
	VoiceCountHint int      `json:"voiceCountHint"`
	CPUThreads     int      `json:"cpuThreads"`
	ExportsDir     string   `json:"exportsDir"`
}

// SynthRequest yêu cầu tổng hợp từ UI.
type SynthRequest struct {
	Text           string  `json:"text"`
	VoiceID        string  `json:"voiceId"`
	EngineOverride string  `json:"engineOverride"` // auto | neural | sapi
	Speed          float64 `json:"speed"`
	Pitch          float64 `json:"pitch"`
	Volume         float64 `json:"volume"`
	AutoPlay       bool    `json:"autoPlay"`

	// PATCH FIX46 — Nhân bản giọng: đường dẫn file WAV mẫu (thử nghiệm).
	// Khi khác rỗng, job buộc dùng engine neural và BỎ VoiceID — engine
	// encode file mẫu thành "giọng" tham chiếu (zero-shot clone).
	RefAudioPath string `json:"refAudioPath,omitempty"`

	// PATCH FIX46 — SkipTextNorm: tắt normalizer (mặc định bật).
	SkipTextNorm bool `json:"skipTextNorm,omitempty"`
}

// JobSnapshot trạng thái một phiên tổng hợp phát qua event `hcstudio:job`.
type JobSnapshot struct {
	ID          string  `json:"id"`
	State       string  `json:"state"` // splitting|synthesizing|dsp|done|error|cancelled
	Pct         float64 `json:"pct"`
	Stage       string  `json:"stage"`
	Message     string  `json:"message,omitempty"`
	DurationSec float64 `json:"durationSec,omitempty"`
	EtaSec      float64 `json:"etaSec,omitempty"`
}

// PlayEvent vị trí phát thanh phát qua event `hcstudio:play`.
type PlayEvent struct {
	JobID    string  `json:"jobId"`
	CursorMs int     `json:"cursorMs"`
	TotalMs  int     `json:"totalMs"`
	Pct      float64 `json:"pct"`
	Playing  bool    `json:"playing"`
}

// ToastPayload thông báo hệ thống qua event `hcstudio:toast`.
type ToastPayload struct {
	Level   string `json:"level"` // info | success | warn | error
	Title   string `json:"title"`
	Message string `json:"message,omitempty"`
}

// Voice alias trực tiếp engine.Voice — hợp đồng một nguồn duy nhất.
type Voice = engine.Voice
