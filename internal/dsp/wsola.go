package dsp

import (
	"math"
)

// TimeStretch WSOLA (Waveform Similarity Overlap-Add) thuần Go.
//
// Kéo dài/nén thời lượng âm thanh giữ nguyên cao độ:
//
//	speed > 1 ⇒ ngắn hơn (nhanh hơn), speed < 1 ⇒ dài hơn (chậm hơn).
//
// Tham số hiệu chỉnh cho giọng nói 44–48 kHz:
//   - Cửa sổ ~40 ms (lũy thừa 2 gần nhất), hop tổng hợp = W/2. Hai nửa cửa sổ
//     Hann chồng nhau cộng đúng bằng 1 ⇒ biên độ trung thực, không "bọt".
//   - Vùng tìm kiếm tương quan ±6 ms: quét thô bước 4 rồi tinh chỉnh ±4 mẫu.
//   - Khung yên tĩnh thì bỏ qua tìm kiếm để tiết kiệm CPU máy yếu.
func TimeStretch(in []float32, sr int, speed float64) []float32 {
	n := len(in)
	if speed <= 0 {
		speed = 1
	}
	if math.Abs(speed-1.0) < 0.005 || n < 4096 || sr <= 0 {
		return in
	}

	W := pow2Window(sr)
	Hs := W / 2
	searchMax := sr * 6 / 1000 // ±6 ms
	hann := hannTable(W)

	estOut := int(float64(n)/speed) + 2*W
	out := make([]float32, estOut)

	tail := make([]float64, Hs) // phần đuôi đã ghi, chuẩn hóa cosin
	haveTail := false

	srcPos := 0     // con trỏ phân tích (int)
	srcFract := 0.0 // bù phần lẻ của hop phân tích
	dstPos := 0     // con trỏ ghi đầu ra

	for srcPos+W+searchMax < n && dstPos+W < estOut {
		idealF := float64(srcPos) + srcFract*float64(Hs)
		lo := int(idealF) - searchMax
		if lo < 0 {
			lo = 0
		}
		hi := int(idealF) + searchMax
		if maxHi := n - W - 1; hi > maxHi {
			hi = maxHi
		}
		if hi < lo {
			break
		}

		candOff := pickBestOffset(in, lo, hi, Hs, tail, haveTail)
		frame := in[candOff : candOff+W]

		for k := 0; k < W; k++ {
			out[dstPos+k] += frame[k] * hann[k]
		}

		// Cập nhật tail = đoạn đuôi mới ghi phục vụ khung kế tiếp.
		tailSeg := out[dstPos+Hs : dstPos+W]
		for ti, tv := range tailSeg {
			tail[ti] = float64(tv)
		}
		if !frameSilent(tail) {
			normalizeInPlace(tail)
		}
		haveTail = true

		dstPos += Hs

		// Hop phân tích: Ha = Hs × speed.
		// speed>1 (nén) ⇒ tiêu thụ input NHANH hơn hop phát ra; <1 thì ngược lại.
		// Định nghĩa chuẩn WSOLA ⇒ out_len ≈ in_len / speed một cách tự nhiên,
		// không phụ thuộc cap mảng đích.
		advance := float64(Hs) * speed
		iadv := math.Floor(advance)
		srcFract += advance - iadv
		move := int(iadv)
		if srcFract >= 1 {
			move++
			srcFract--
		} else if srcFract <= -1 { // phòng hờ số thực
			move--
			srcFract++
		}
		srcPos += move
	}

	finalLen := dstPos + Hs
	if finalLen > estOut {
		finalLen = estOut
	}
	result := make([]float32, finalLen)
	copy(result, out[:finalLen])
	fadeEdges(result, sr/100) // fade 10 ms hai đầu chống click
	return result
}

// pickBestOffset tối đa hóa tương quan cosin giữa đầu khung ứng viên và đuôi.
func pickBestOffset(in []float32, lo, hi, Hs int, tail []float64, haveTail bool) int {
	if !haveTail {
		return (lo + hi) / 2
	}
	bestScore := math.Inf(-1)
	best := (lo + hi) / 2

	scoreAt := func(off int) float64 {
		limit := off + Hs
		if limit > len(in) {
			limit = len(in)
		}
		dot := 0.0
		energy := 0.0
		j := 0
		for i := off; i < limit && j < len(tail); i++ {
			sv := float64(in[i])
			energy += sv * sv
			dot += sv * tail[j]
			j++
		}
		if energy < 1e-9 {
			return math.Inf(-1)
		}
		return dot / math.Sqrt(energy)
	}

	const step = 4
	for off := lo; off <= hi; off += step {
		if s := scoreAt(off); s > bestScore {
			bestScore = s
			best = off
		}
	}
	for off := best - step; off <= best+step; off++ {
		if off < lo || off > hi || off == best {
			continue
		}
		if s := scoreAt(off); s > bestScore {
			bestScore = s
			best = off
		}
	}
	return best
}

func frameSilent(v []float64) bool {
	e := 0.0
	for _, x := range v {
		e += x * x
	}
	return e < 1e-8
}

func normalizeInPlace(v []float64) {
	sum := 0.0
	for _, x := range v {
		sum += x * x
	}
	if sum < 1e-9 {
		return
	}
	inv := 1 / math.Sqrt(sum)
	for i := range v {
		v[i] *= inv
	}
}

func pow2Window(sr int) int {
	w := 40 * sr / 1000 // ~40 ms
	p := 1024
	for p < w {
		p <<= 1
	}
	return p
}

func hannTable(n int) []float32 {
	t := make([]float32, n)
	for i := 0; i < n; i++ {
		t[i] = float32(0.5 - 0.5*math.Cos(2*math.Pi*float64(i)/float64(n)))
	}
	return t
}

func fadeEdges(buf []float32, edge int) {
	if edge*2 > len(buf) {
		edge = len(buf) / 2
	}
	for k := 0; k < edge; k++ {
		f := float32(k+1) / float32(edge)
		buf[k] *= f
		buf[len(buf)-1-k] *= f
	}
}

// PitchShift dịch cao độ theo bán cung (semitone), GIỮ nguyên thời lượng.
// Công thức: resamplePlayback(x, ratio) đổi tông ×ratio rồi TimeStretch với
// speed = 1/ratio để hoàn lại đúng thời lượng gốc (WSOLA giữ nguyên cao độ).
//
//	semis > 0: cao hơn (nữ hóa), semis < 0: trầm xuống (nam hóa sâu).
func PitchShift(in []float32, sr int, semis float64) []float32 {
	if math.Abs(semis) < 0.05 {
		return in
	}
	ratio := math.Pow(2, semis/12)
	up := ResamplePlayback(in, ratio) // playback nhanh/chậm hơn ⇒ đổi tông
	return TimeStretch(up, sr, 1/ratio)
}
