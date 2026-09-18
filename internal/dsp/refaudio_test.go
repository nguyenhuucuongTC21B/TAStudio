package dsp

import (
	"os"
	"path/filepath"
	"testing"
)

// PATCH FIX47: kiem tra PrepareRefAudio - trim 8s + khong doi file ngan.
func TestPrepareRefAudioShort(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "ref.wav")
	samples := make([]float32, 16000*3) // 3 giay @16k
	for i := range samples {
		samples[i] = 0.1
	}
	if err := WriteWav(src, samples, 16000, 1); err != nil {
		t.Fatal(err)
	}
	got, dur, trimmed, err := PrepareRefAudio(src, dir, 8.0)
	if err != nil {
		t.Fatal(err)
	}
	if trimmed {
		t.Fatalf("file 3s khong duoc trim")
	}
	if got != src {
		t.Fatalf("path giu nguyen, got %s", got)
	}
	if dur < 2.99 || dur > 3.01 {
		t.Fatalf("duration = %f, mong ~3.0", dur)
	}
}

func TestPrepareRefAudioLongTrim(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "ref-long.wav")
	samples := make([]float32, 16000*20) // 20 giay
	for i := range samples {
		samples[i] = 0.05
	}
	if err := WriteWav(src, samples, 16000, 1); err != nil {
		t.Fatal(err)
	}
	got, dur, trimmed, err := PrepareRefAudio(src, dir, 8.0)
	if err != nil {
		t.Fatal(err)
	}
	if !trimmed {
		t.Fatalf("file 20s phai duoc trim")
	}
	if got == src {
		t.Fatalf("path phai doi sang file da cat")
	}
	if _, err := os.Stat(got); err != nil {
		t.Fatalf("file da cat khong ton tai: %v", err)
	}
	if dur < 7.99 || dur > 8.01 {
		t.Fatalf("duration sau cat = %f, mong ~8.0", dur)
	}
}

func TestPrepareRefAudioInvalid(t *testing.T) {
	dir := t.TempDir()
	bad := filepath.Join(dir, "not-wav.txt")
	os.WriteFile(bad, []byte("khong phai wav"), 0o644)
	_, _, _, err := PrepareRefAudio(bad, dir, 8.0)
	if err == nil {
		t.Fatalf("file loi phai bao loi de caller dung file goc")
	}
}
