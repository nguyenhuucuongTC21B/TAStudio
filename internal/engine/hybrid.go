package engine

import (
	"sync"
	"sync/atomic"
)

// Hybrid điều phối giữa hai tầng engine theo yêu cầu của UI.
//
// Quy tắc chọn:
//   - EnginePref == "sapi"                → luôn SAPI
//   - EnginePref == "neural"              → neural nếu dùng được, không thì lỗi có mô tả
//   - auto (mặc định): giọng thuộc catalog 25 giọng VieNeu → neural khi sẵn sàng,
//     ngược lại (hoặc chưa tải model) → SAPI gần nhất (ưu tiên vi-VN).
type Hybrid struct {
	mu       sync.Mutex
	modelDir string

	neuralReady atomic.Bool // cập nhật sau mỗi lần kiểm assets/downloader xong

	sapiOnce sync.Once
	sapi     Driver
}

// NewHybrid khởi tạo dispatcher.
func NewHybrid(modelDir string) *Hybrid {
	h := &Hybrid{modelDir: modelDir}
	h.RefreshNeuralReadiness()
	return h
}

// RefreshNeuralReadiness quét lại thư mục models.
func (h *Hybrid) RefreshNeuralReadiness() {
	h.neuralReady.Store(AssetsReady(h.modelDir))
}

// NeuralReady trạng thái hiện tại.
func (h *Hybrid) NeuralReady() bool { return h.neuralReady.Load() }

func (h *Hybrid) sapiDriver() Driver {
	h.sapiOnce.Do(func() { h.sapi = NewSapiDriver() })
	return h.sapi
}

// ListVoices hợp nhất catalog: 25 giọng VieNeu trước (rank tăng dần, FIX46),
// kế tiếp là giọng SAPI thực tế của máy.
func (h *Hybrid) ListVoices(neuralLinked bool) []Voice {
	out := make([]Voice, 0, len(NeuralCatalog())+8)

	neuralOK := neuralLinked && h.NeuralReady()
	for i, v := range NeuralCatalog() {
		v.Available = neuralOK
		v.Rank = i
		out = append(out, v)
	}
	if sv, err := h.sapiDriver().ListVoices(); err == nil {
		for j := range sv {
			sv[j].Rank = 1000 + j
			out = append(out, sv[j])
		}
	}
	return out
}

// Resolve quyết định engine + voiceID thực thi cho một request.
func (h *Hybrid) Resolve(pref string, voiceID string, neuralLinked bool) (Driver, string, VoiceEngine, error) {
	// PATCH FIX46: map bí danh voices json (vd "Minh Quân" → "Minh Quân
	// Pro") về ID chuẩn trước khi chọn engine.
	if resolved, ok := IsNeuralAlias(voiceID); ok {
		voiceID = resolved
	}
	wantSapi := pref == "sapi"
	wantNeural := pref == "neural"

	neuralUsable := neuralLinked && h.NeuralReady()

	if !wantSapi && (wantNeural || pref == "auto") && neuralUsable && IsNeuralVoice(voiceID) {
		return NewNeuralDriver(), voiceID, EngineNeural, nil
	}

	if wantNeural && !neuralUsable {
		if !neuralLinked {
			return nil, "", "", ErrNeuralNotLinked
		}
		return nil, "", "", ErrNeuralNoAssets
	}

	// SAPI path.
	sd := h.sapiDriver()
	sapiID := voiceID
	if wantNeural || (!wantSapi && IsNeuralVoice(voiceID)) {
		// Người dùng đang chọn giọng neural nhưng fallback SAPI → đổi sang
		// giọng hệ thống phù hợp nhất.
		sapiID = ""
		if vs, err := sd.ListVoices(); err == nil && len(vs) > 0 {
			for _, v := range vs { // ưu tiên vi-VN nếu label gợi ý
				if containsAny(v.Name, "Viet", "An", "vi-VN", "Vietnamese") {
					sapiID = v.ID
					break
				}
			}
			if sapiID == "" {
				sapiID = vs[0].ID
			}
		}
	}
	return sd, sapiID, EngineSAPI, nil
}

func containsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		if sub != "" && contains(s, sub) {
			return true
		}
	}
	return false
}

func contains(s, sub string) bool {
	return len(sub) > 0 && len(s) >= len(sub) && indexOf(s, sub) >= 0
}

func indexOf(s, sub string) int {
	n, m := len(s), len(sub)
	if m == 0 || n < m {
		return -1
	}
	for i := 0; i+m <= n; i++ {
		match := true
		for j := 0; j < m; j++ {
			lc := lowerByte(s[i+j])
			ls := lowerByte(sub[j])
			if lc != ls {
				match = false
				break
			}
		}
		if match {
			return i
		}
	}
	return -1
}

func lowerByte(b byte) byte {
	if b >= 'A' && b <= 'Z' {
		return b + 32
	}
	return b
}
