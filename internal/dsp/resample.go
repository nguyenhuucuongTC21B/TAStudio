package dsp

import "math"

// ResamplePlayback đổi tốc độ phát thô bằng nội suy tuyến tính.
// ratio > 1 ⇒ nhanh hơn VÀ cao độ lên theo cùng tỉ lệ (kiểu băng ghi tua).
// Được dùng làm bước trung gian của PitchShift, không dùng trực tiếp cho Speed.
func ResamplePlayback(in []float32, ratio float64) []float32 {
	if math.Abs(ratio-1) < 1e-9 || len(in) == 0 {
		return in
	}
	outLen := int(math.Ceil(float64(len(in)) / ratio))
	if outLen < 1 {
		outLen = 1
	}
	out := make([]float32, outLen)
	srcMax := float64(len(in) - 1)
	for i := 0; i < outLen; i++ {
		pos := float64(i) * ratio
		if pos > srcMax {
			pos = srcMax
		}
		i0 := int(pos)
		i1 := i0 + 1
		if i1 >= len(in) {
			i1 = len(in) - 1
		}
		frac := pos - float64(i0)
		out[i] = in[i0]*(1-float32(frac)) + in[i1]*float32(frac)
	}
	return out
}

// ConvertSampleRate chuyển số sample-per-second giữa hai tần số lấy mẫu
// bằng nội suy tuyến tính (đủ dùng cho giọng nói; chất lượng > impulse).
// Trả về nil nếu tham số vô lý.
func ConvertSampleRate(in []float32, srIn, srOut int) []float32 {
	if srIn <= 0 || srOut <= 0 || len(in) == 0 || srIn == srOut {
		return in
	}
	ratio := float64(srIn) / float64(srOut)
	return ResamplePlayback(in, ratio)
}
