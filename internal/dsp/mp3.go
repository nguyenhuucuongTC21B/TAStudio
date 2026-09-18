package dsp

import (
	"fmt"
	"os"

	shinemp3 "github.com/braheezy/shine-mp3/pkg/mp3"
)

// ExportMP3 encode PCM float32 mono xuống file MP3 dùng SHINE fixed-point
// thuần Go — không cgo, không DLL ngoài, giữ nguyên ràng buộc single-exe.
//
// SHINE làm việc ở MPEG-1 Layer III 128 kbps; nếu sample rate không thuộc
// bảng MPEG-1 (32/44.1/48 kHz) sẽ tự resample về 44100 để đảm bảo hợp lệ.
func ExportMP3(path string, samples []float32, sampleRate int) error {
	sr := sampleRate
	if _, cerr := shinemp3.CheckConfig(sr, 128); cerr != nil {
		sr = 44100
		samples = ConvertSampleRate(samples, sampleRate, sr)
	}

	pcm := FloatToPCM16Interleaved(samples)
	enc := shinemp3.NewEncoder(sr, 1)

	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("không tạo được file mp3: %w", err)
	}
	defer f.Close()

	if err := enc.Write(f, pcm); err != nil {
		return fmt.Errorf("encode mp3 thất bại: %w", err)
	}
	return nil
}
