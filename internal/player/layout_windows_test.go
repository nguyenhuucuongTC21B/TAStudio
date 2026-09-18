//go:build windows

// layout_windows_test.go — khoá cứng layout WAVEHDR theo mmreg.h.
//
// Bản trước từng chèn pad sai làm sizeof lệch 8 byte → WHDR_DONE không bao
// giờ thấy → player phát ~0,72 s rồi câm lặng vĩnh viễn. Test này chạy trong
// `go test ./internal/player/` trên máy Windows để chặn bug hồi quy.
package player

import (
	"testing"
	"unsafe"
)

func TestWaveHdrLayout(t *testing.T) {
	// sizeof(WAVEHDR): 48 trên x64, 32 trên x86.
	wantSize := uintptr(8 * 6) // 6 pointer-size slotalign: 48/32 tuỳ arch
	if wantSize != 32 && wantSize != 48 {
		t.Fatalf("arch không hỗ trợ: %d", wantSize)
	}
	got := unsafe.Sizeof(waveHdr{})
	if got != wantSize {
		t.Fatalf("sizeof(waveHdr) = %d, mong đợi %d (layout lệch mmreg.h!)",
			got, wantSize)
	}

	type off struct {
		name string
		got  uintptr
		want uintptr
	}
	ptrSz := unsafe.Sizeof(uintptr(0))
	checks := []off{
		{"LpData", unsafe.Offsetof(waveHdr{}.LpData), 0},
		{"BufferLength", unsafe.Offsetof(waveHdr{}.BufferLength), ptrSz},
		{"BytesRecorded", unsafe.Offsetof(waveHdr{}.BytesRecorded), ptrSz + 4},
		{"User", unsafe.Offsetof(waveHdr{}.User), ptrSz + 8},
		{"Flags", unsafe.Offsetof(waveHdr{}.Flags), ptrSz*2 + 8},
		{"Loops", unsafe.Offsetof(waveHdr{}.Loops), ptrSz*2 + 12},
		{"Next", unsafe.Offsetof(waveHdr{}.Next), ptrSz*3 + 12},
		{"Reserved", unsafe.Offsetof(waveHdr{}.Reserved), ptrSz*4 + 12},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("offset %s = %d, mong đợi %d", c.name, c.got, c.want)
		}
	}
}
