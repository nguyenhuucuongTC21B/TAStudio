package dsp

import (
	"math"
	"os"
	"path/filepath"
	"testing"
)

func TestSplitVietnameseBasic(t *testing.T) {
	text := "Xin chào! Tôi là HCStudio. Đây là câu thứ ba…\n\nĐoạn mới bắt đầu từ đây."
	chunks := SplitVietnamese(text, 45) // maxChars nhỏ để buộc tách nhiều chunk
	if len(chunks) < 2 {
		t.Fatalf("kỳ vọng ≥2 chunks, nhận %d", len(chunks))
	}
	joined := ""
	for _, c := range chunks {
		joined += c.Text + " "
	}
	for _, want := range []string{"Xin chào!", "HCStudio", "Đoạn mới"} {
		if !contains(joined, want) {
			t.Fatalf("thiếu nội dung %q trong %q", want, joined)
		}
	}
}

func TestSplitLongSentenceHardCut(t *testing.T) {
	long := ""
	for i := 0; i < 200; i++ {
		long += "từdàikhôngcách "
	}
	chunks := SplitVietnamese(long, 100)
	if len(chunks) <= 1 {
		t.Fatalf("câu dài phải bị cắt cứng thành nhiều phần")
	}
	for i, c := range chunks {
		r := len([]rune(c.Text))
		if r > 130 { // cho phép lệch nhỏ do word-wrap
			t.Fatalf("chunk %d vượt hạn mức (%d ký tự)", i, r)
		}
	}
}

func TestTimeStretchDuration(t *testing.T) {
	sr := 48000
	in := make([]float32, sr*2) // 2 giây
	for i := range in {
		in[i] = float32(math.Sin(float64(i) / 22))
	}
	fast := TimeStretch(in, sr, 1.5)
	want := float64(sr*2) / 1.5
	tolerance := want * 0.15 // ±15% — WSOLA khó khớp tuyệt đối
	if math.Abs(float64(len(fast))-want) > tolerance {
		t.Fatalf("độ dài sai: got %d muốn ~%.0f", len(fast), want)
	}
	slow := TimeStretch(in, sr, 0.75)
	wantSlow := float64(len(in)) / 0.75
	if math.Abs(float64(len(slow))-wantSlow) > wantSlow*0.15 {
		t.Fatalf("độ dài chậm sai: got %d want ~%.0f", len(slow), wantSlow)
	}
}

func TestPitchShiftKeepsDuration(t *testing.T) {
	sr := 44100
	in := make([]float32, sr)
	for i := range in {
		in[i] = float32(math.Sin(2*math.Pi*220*float64(i)/float64(sr))) * .5
	}
	out := PitchShift(in, sr, -3.5)
	if math.Abs(float64(len(out)-len(in))) > float64(sr)*0.08 {
		t.Fatalf("pitch shift phải giữ thời lượng ±8%%: got %d", len(out))
	}
	if peakAbs(out) > 1.001 || peakAbs(out) < 0.01 {
		t.Fatalf("biên độ đầu ra bất thường: %f", peakAbs(out))
	}
}

func TestWavRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "t.wav")
	pcm := []float32{0, .25, -.5, .9, -1}
	if err := WriteWav(path, pcm, 24000, 1); err != nil {
		t.Fatal(err)
	}
	back, sr, ch, err := ReadWav(path)
	if err != nil {
		t.Fatal(err)
	}
	if sr != 24000 || ch != 1 || len(back) != len(pcm) {
		t.Fatalf("round trip lệch: sr=%d ch=%d n=%d", sr, ch, len(back))
	}
	os.Remove(path)
}

func TestVolumeClippingSafe(t *testing.T) {
	in := []float32{1, -1, .5, -.5}
	out := ApplyVolume(in, 1.0)
	for i, v := range out {
		if v > 1 || v < -1 {
			t.Fatalf("mẫu %d vượt phạm vi: %f", i, v)
		}
	}
}

func peakAbs(buf []float32) float64 {
	m := 0.0
	for _, v := range buf {
		if v < 0 {
			v = -v
		}
		if float64(v) > m {
			m = float64(v)
		}
	}
	return m
}

func contains(s, sub string) bool {
	return len(sub) > 0 && indexOfStr(s, sub) >= 0
}

func indexOfStr(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
