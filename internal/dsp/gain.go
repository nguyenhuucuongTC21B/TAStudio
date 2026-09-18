package dsp

import "math"

// ApplyVolume nhân biên độ tuyến tính rồi qua soft-limiter để không vỡ loa
// khi người dùng đẩy âm lượng gần mức tối đa trên đoạn âm có peak cao.
// volume ∈ [0..1] ánh xạ hệ số: 0 → im lặng, 1 → gain 1.25 (headroom nhá).
func ApplyVolume(in []float32, volume float64) []float32 {
	if len(in) == 0 {
		return in
	}
	gain := math.Pow(volume, 1.6) * 1.25 // đường cong cảm nhận "đầy" hơn
	if math.Abs(gain-1.0) < 0.02 {
		return in // gần như không đổi, bỏ qua xử lý
	}
	out := make([]float32, len(in))
	const knee = 0.90
	const headroom = 1.0 - knee // 0.10
	for i, v := range in {
		x := v * float32(gain)
		ax := x
		if ax < 0 {
			ax = -ax
		}
		if ax > knee {
			excess := float64(ax - knee)
			// Đường cong nén mềm: excess chảy dần về headroom, max = 1.0.
			compressed := headroom * excess / (excess + headroom)
			yy := knee + compressed
			if yy > 1 {
				yy = 1
			}
			if x < 0 {
				x = -float32(yy)
			} else {
				x = float32(yy)
			}
		}
		out[i] = x
	}
	return out
}

// Silence sinh đoạn im lặng (dùng chèn giữa các câu).
func Silence(seconds float64, sr int) []float32 {
	n := int(seconds * float64(sr))
	if n <= 0 {
		return nil
	}
	return make([]float32, n)
}
