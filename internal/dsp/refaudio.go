package dsp

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// PATCH FIX47 — vệ sinh audio mẫu cho nhân bản giọng.
//
// Bằng chứng từ Space chính thức của tác giả (doremon102/VieNeu-TTS-v3-Turbo,
// app.py) và wheel vieneu 3.6.3:
//   - inference_v3_turbo.py: _MAX_REF_SECONDS = 8.0 — prepare_reference
//     TRIM ref audio còn 8 giây trước khi encode.
//   - Space hiện cảnh báo khi ref > 5.5s và khuyến nghị 3–5 giây
//     ("audio quá dài thường cho kết quả kém hơn").
//
// Core C++ của app (encode_reference_audio) KHÔNG trim — ref dài làm chuỗi
// ref codes phình theo độ dài file, prompt dài hơn mỗi chunk synth và chất
// lượng clone giảm (đúng như cảnh báo của tác giả). Nên trim ở tầng Go.
//
// PrepareRefAudio đọc WAV (dùng parser ReadWav sẵn có), trả về:
//   - path:      đường dẫn nên dùng khi synth (file gốc, hoặc file đã cắt
//     còn maxSeconds ghi ra outDir nếu vượt ngưỡng)
//   - duration:  thời lượng tính được (giây); 0 nếu đọc lỗi
//   - trimmed:   true nếu đã cắt và ghi file mới
//   - err:       lỗi đọc/ghi — caller nên dùng nguyên file gốc khi lỗi
//
// Không đổi sample-rate/kênh: core tự resample về 48 kHz và tự trộn stereo.
func PrepareRefAudio(path, outDir string, maxSeconds float64) (string, float64, bool, error) {
	samples, sr, _, err := ReadWav(path)
	if err != nil {
		return path, 0, false, err
	}
	if sr <= 0 {
		return path, 0, false, fmt.Errorf("WAV mẫu có sample-rate không hợp lệ")
	}
	duration := float64(len(samples)) / float64(sr)
	if duration <= maxSeconds {
		return path, duration, false, nil
	}

	// Cắt giữ nguyên đầu clip (một câu mẫu thường nằm ở đầu; giữ đầu cũng
	// khớp hành vi trim của SDK: wav[: max_seconds * sr]).
	maxFrames := int(maxSeconds * float64(sr))
	if maxFrames > len(samples) {
		maxFrames = len(samples)
	}
	cut := samples[:maxFrames]

	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return path, duration, false, err
	}
	outPath := filepath.Join(outDir, "ref-sample-trimmed.wav")
	if err := WriteWav(outPath, cut, sr, 1); err != nil {
		return path, duration, false, err
	}
	// Tránh đụng tên file người dùng từng chọn trùng khớp (hiếm nhưng rẻ).
	if strings.EqualFold(outPath, path) {
		return path, duration, false, fmt.Errorf("file mẫu trùng đường dẫn file tạm")
	}
	return outPath, float64(maxFrames) / float64(sr), true, nil
}
