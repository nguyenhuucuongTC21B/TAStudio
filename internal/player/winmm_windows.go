//go:build windows

// Package player — phát PCM float32 qua Windows Multimedia API (winmm.dll).
//
// Vì sao winmm chứ không WASAPI/PortAudio:
//   - syscall thuần qua NewLazyDLL: KHÔNG cgo, KHÔNG DLL bổ sung (winmm là
//     thành phần hệ thống từ Windows XP), giữ trọn vẹn single-exe.
//   - Có sẵn Pause/Resume/Reset đủ cho transport bar của HCStudio.
//
// Chiến lược streaming: chia buffer ~120 ms, 6 WAVEHDR xoay vòng; scheduler
// goroutine tự nạp slot mới khi slot cũ đánh dấu WHDR_DONE.
//
// ⚠ Hai bẫy layout đã gây "im lặng hoàn toàn" ở bản trước — đã sửa:
//  1. WAVEHDR x64 KHÔNG có padding giữa dwBufferLength/dwBytesRecorded
//     (hai DWORD kề nhau @8/@12, rồi DWORD_PTR dwUser @16, dwFlags @24,
//     dwLoops @28, lpNext @32, dwReserved @40 → sizeof = 48). Bản cũ chèn
//     pad sai → sizeof 64, dwFlags lệch 8 byte → WHDR_DONE không bao giờ
//     thấy được → chỉ 6 buffer đầu (~0,72 s) được đổ rồi engine đói dữ
//     liệu: nghe vài tick rồi câm lặng, đồng hồ kẹt, OnEnded không bắn.
//  2. handle waveOutOpen phải lưu vào p.handle ngay sau khi mở — không thì
//     Pause/Resume không thao tác được với thiết bị nào cả.
package player

import (
	"fmt"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"hcstudio/internal/dsp"
)

var (
	winmm              = syscall.NewLazyDLL("winmm.dll")
	procWaveOutOpen    = winmm.NewProc("waveOutOpen")
	procWaveOutPrepare = winmm.NewProc("waveOutPrepareHeader")
	procWaveOutWrite   = winmm.NewProc("waveOutWrite")
	procWaveOutUnprep  = winmm.NewProc("waveOutUnprepareHeader")
	procWaveOutPause   = winmm.NewProc("waveOutPause")
	procWaveOutRestart = winmm.NewProc("waveOutRestart")
	procWaveOutReset   = winmm.NewProc("waveOutReset")
	procWaveOutClose   = winmm.NewProc("waveOutClose")
)

const (
	waveMapper  = 0xFFFFFFFF // WAVE_MAPPER: chọn thiết bị mặc định của hệ thống
	waveHdrDone = 0x00000001 // WHDR_DONE
	numBuffers  = 6
)

// waveFormatEx cấu trúc 18 byte chuẩn truyền xuống winmm.
type waveFormatEx struct {
	FormatTag      uint16
	Channels       uint16
	SamplesPerSec  uint32
	AvgBytesPerSec uint32
	BlockAlign     uint16
	BitsPerSample  uint16
	ExtraSize      uint16
}

// waveHdr phản chiếu CHÍNH XÁC layout WAVEHDR của mmreg.h.
//
//	x64: lpData@0(8) dwBufferLength@8(4) dwBytesRecorded@12(4)
//	     dwUser@16(8) dwFlags@24(4) dwLoops@28(4) lpNext@32(8)
//	     dwReserved@40(8)                    → sizeof = 48
//	x86: các trường uintptr co lại 4 byte  → sizeof = 32 (đúng chuẩn 32-bit)
//
// Go tự thêm padding đúng quy tắc C: uintptr cần align 8 (x64) nên sau
// BytesRecorded@12, User rơi đúng @16 — KHÔNG cần field pad thủ công.
type waveHdr struct {
	LpData        uintptr
	BufferLength  uint32
	BytesRecorded uint32
	User          uintptr
	Flags         uint32
	Loops         uint32
	Next          uintptr
	Reserved      uintptr
}

// Player trạng thái phát toàn app (chỉ một instance).
type Player struct {
	mu       sync.Mutex
	handle   uintptr
	sr       int
	totalMs  int
	cursorMs int

	// PATCH FIX52: kênh dữ liệu cho chế độ streaming
	feed        chan []byte   // PCM16 chunk đến dần từ tầng synth
	feedOpen    chan struct{} // đóng = hết dữ liệu (EndStream)
	streamAbort chan struct{} // đóng khi Stop giữa chừng (chống treo Append)

	paused   bool
	stopping bool
	playID   uint64 // đếm phiên Play để Stop cũ không giết phiên mới

	OnProgress func(cursorMs, totalMs int)
	OnEnded    func()
}

// New tạo player rảnh.
func New() *Player { return &Player{} }

// IsPlaying có phiên phát đang sống.
func (p *Player) IsPlaying() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.handle != 0
}

// IsPaused trạng thái tạm dừng.
func (p *Player) IsPaused() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.paused
}

// TogglePause đổi giữa pause/resume. Trả true nếu sau lệnh là paused.
func (p *Player) TogglePause() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.handle == 0 {
		return false
	}
	if !p.paused {
		procWaveOutPause.Call(p.handle)
		p.paused = true
	} else {
		procWaveOutRestart.Call(p.handle)
		p.paused = false
	}
	return p.paused
}

// Stop dừng phiên hiện tại (reset thiết bị → scheduler thoát sạch sẽ).
func (p *Player) Stop() {
	p.mu.Lock()
	p.stopping = true
	h := p.handle
	// PATCH FIX52: mở khoá mọi AppendStream đang chờ nạp dữ liệu.
	if p.streamAbort != nil {
		select {
		case <-p.streamAbort:
		default:
			close(p.streamAbort)
		}
	}
	p.mu.Unlock()

	if h != 0 {
		procWaveOutReset.Call(h)
	}
}

// Play phát PCM mono float32 tại sampleRate chỉ định, async.
func (p *Player) Play(samples []float32, sr int) error {
	if len(samples) == 0 || sr <= 0 {
		return fmt.Errorf("PCM rỗng hoặc sample rate sai")
	}
	pcmBytes := byteSliceOfInt16(dsp.FloatToPCM16Interleaved(samples))

	p.mu.Lock()
	// Vô hiệu hoá phiên cũ TRƯỚC TIÊN: scheduler cũ thấy playID đổi sẽ
	// tự thoát, unprepare + close handle của nó (không double-close).
	p.playID++
	id := p.playID
	old := p.handle
	p.handle = 0
	p.sr = sr
	p.totalMs = len(pcmBytes) * 1000 / (sr * 2) // PCM16 mono: 2 byte/sample
	p.cursorMs = 0
	p.paused = false
	p.stopping = false
	p.mu.Unlock()

	if old != 0 {
		procWaveOutReset.Call(old) // gieo WHDR_DONE cho mọi buffer cũ
	}

	go p.runSession(id, pcmBytes, sr)
	return nil
}

// PATCH FIX52 — STREAMING: phát ngay chunk đầu tiên rồi đợi dữ liệu mới
// qua AppendStream tới EndStream. Dùng cho chế độ "Nghe ngay khi tổng hợp".
func (p *Player) PlayStream(first []float32, sr int) error {
	if len(first) == 0 || sr <= 0 {
		return fmt.Errorf("PCM rỗng hoặc sample rate sai")
	}
	pcmBytes := byteSliceOfInt16(dsp.FloatToPCM16Interleaved(first))

	p.mu.Lock()
	p.playID++
	id := p.playID
	old := p.handle
	p.handle = 0
	p.sr = sr
	p.totalMs = 0 // tổng chạy dần theo dữ liệu nạp thêm
	p.cursorMs = 0
	p.paused = false
	p.stopping = false
	p.feed = make(chan []byte, 64)
	p.feedOpen = make(chan struct{})
	p.streamAbort = make(chan struct{})
	p.mu.Unlock()

	if old != 0 {
		procWaveOutReset.Call(old)
	}
	go p.runStreamSession(id, pcmBytes, sr)
	return nil
}

// AppendStream nạp thêm một chunk audio vào phiên streaming đang chạy.
// An toàn khi gọi sau khi phiên kết thúc (bỏ qua im lặng); không bao giờ
// treo vô hạn vì select cùng streamAbort.
func (p *Player) AppendStream(samples []float32) {
	p.mu.Lock()
	feed := p.feed
	abort := p.streamAbort
	stopping := p.stopping
	p.mu.Unlock()
	if feed == nil || stopping || abort == nil || len(samples) == 0 {
		return
	}
	data := byteSliceOfInt16(dsp.FloatToPCM16Interleaved(samples))
	select {
	case feed <- data:
	case <-abort:
	}
}

// EndStream báo hết dữ liệu: scheduler phát nốt phần tồn đọng rồi kết thúc.
func (p *Player) EndStream() {
	p.mu.Lock()
	open := p.feedOpen
	p.mu.Unlock()
	if open != nil {
		select {
		case <-open:
		default:
			close(open)
		}
	}
}

func (p *Player) runSession(id uint64, pcm []byte, sr int) {
	format := waveFormatEx{
		FormatTag:      1,
		Channels:       1,
		SamplesPerSec:  uint32(sr),
		BlockAlign:     2,
		BitsPerSample:  16,
		AvgBytesPerSec: uint32(sr) * 2,
	}

	var h uintptr
	rc, _, _ := procWaveOutOpen.Call(
		uintptr(unsafe.Pointer(&h)),
		uintptr(waveMapper),
		uintptr(unsafe.Pointer(&format)),
		0, 0, 0 /*CALLBACK_NULL*/)
	if rc != 0 || h == 0 {
		p.emitEnded(id)
		return
	}

	// LƯU HANDLE ngay lập tức → Pause/Resume/Stop tác động được thiết bị.
	p.mu.Lock()
	if p.playID == id {
		p.handle = h
	}
	p.mu.Unlock()

	bytesTotal := len(pcm)
	cursor := 0
	slots := make([]waveHdr, numBuffers)
	data := make([][]byte, numBuffers)
	const hdrSize = unsafe.Sizeof(waveHdr{}) // 48 trên x64 — khớp winmm

	submit := func(slotIdx int) bool {
		chunk := 120 * sr / 1000 * 2 // 120 ms tính theo byte PCM16 mono
		end := cursor + chunk
		if end > bytesTotal {
			end = bytesTotal
		}
		if cursor >= end {
			return false
		}
		buf := make([]byte, end-cursor)
		copy(buf, pcm[cursor:end])
		data[slotIdx] = buf

		hdr := &slots[slotIdx]
		*hdr = waveHdr{LpData: uintptr(unsafe.Pointer(&buf[0])), BufferLength: uint32(len(buf))}
		if rc, _, _ := procWaveOutPrepare.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize); rc != 0 {
			return false
		}
		if rc, _, _ := procWaveOutWrite.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize); rc != 0 {
			procWaveOutUnprep.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize)
			return false
		}
		cursor = end
		return true
	}

	freeSlot := func(slotIdx int) {
		hdr := &slots[slotIdx]
		if hdr.LpData != 0 {
			procWaveOutUnprep.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize)
			hdr.LpData = 0
			hdr.Flags = 0
		}
		data[slotIdx] = nil
	}

	// Đổ đầy hàng đợi ban đầu.
	nextSlot := 0
	for i := 0; i < numBuffers && cursor < bytesTotal; i++ {
		if submit(i) {
			nextSlot = (i + 1) % numBuffers
		}
	}

	for {
		p.mu.Lock()
		localStop := p.stopping || p.playID != id
		p.cursorMs = playedMs(cursor, sr)
		progressFn := p.OnProgress
		totalMs := p.totalMs
		curMs := p.cursorMs
		p.mu.Unlock()

		if progressFn != nil && !localStop {
			progressFn(curMs, totalMs)
		}
		if localStop {
			break
		}

		hdr := &slots[nextSlot]
		if hdr.Flags&waveHdrDone != 0 || hdr.LpData == 0 {
			freeSlot(nextSlot)
			if cursor < bytesTotal {
				if !submit(nextSlot) {
					break
				}
				nextSlot = (nextSlot + 1) % numBuffers
				continue
			}
			// Hết dữ liệu: chờ các slot còn lại phát xong.
			allDone := true
			for i := 0; i < numBuffers; i++ {
				if slots[i].LpData != 0 && slots[i].Flags&waveHdrDone == 0 {
					allDone = false
					break
				}
			}
			if allDone {
				break
			}
		}
		time.Sleep(20 * time.Millisecond)
	}

	for i := 0; i < numBuffers; i++ {
		freeSlot(i)
	}
	procWaveOutClose.Call(h)

	// Dọn trạng thái: chỉ phiên còn "đương nhiệm" mới được sửa.
	p.mu.Lock()
	if p.playID == id {
		p.stopping = false
		if p.handle == h {
			p.handle = 0
		}
	}
	p.mu.Unlock()

	p.emitEnded(id)
}

// PATCH FIX52 — scheduler phiên streaming: giống runSession nhưng dữ liệu
// đến dần từ kênh feed; kết thúc khi feedOpen đóng VÀ hết dữ liệu tồn.
func (p *Player) runStreamSession(id uint64, first []byte, sr int) {
	format := waveFormatEx{
		FormatTag:      1,
		Channels:       1,
		SamplesPerSec:  uint32(sr),
		BlockAlign:     2,
		BitsPerSample:  16,
		AvgBytesPerSec: uint32(sr) * 2,
	}

	var h uintptr
	rc, _, _ := procWaveOutOpen.Call(
		uintptr(unsafe.Pointer(&h)),
		uintptr(waveMapper),
		uintptr(unsafe.Pointer(&format)),
		0, 0, 0 /*CALLBACK_NULL*/)
	if rc != 0 || h == 0 {
		p.emitEnded(id)
		return
	}

	p.mu.Lock()
	if p.playID == id {
		p.handle = h
	}
	p.mu.Unlock()

	const hdrSize = unsafe.Sizeof(waveHdr{})
	slots := make([]waveHdr, numBuffers)
	data := make([][]byte, numBuffers)

	pending := first    // dữ liệu đã nhận nhưng chưa submit
	total := len(first) // tổng byte đã nhận (totalMs chạy dần)
	submitted := 0      // tổng byte đã đổ vào waveOut (cursorMs)

	submit := func(slotIdx int) bool {
		chunk := 120 * sr / 1000 * 2 // 120 ms theo byte PCM16 mono
		end := chunk
		if end > len(pending) {
			end = len(pending)
		}
		if end == 0 {
			return false
		}
		buf := make([]byte, end)
		copy(buf, pending[:end])
		pending = pending[end:]
		data[slotIdx] = buf

		hdr := &slots[slotIdx]
		*hdr = waveHdr{LpData: uintptr(unsafe.Pointer(&buf[0])), BufferLength: uint32(len(buf))}
		if rc, _, _ := procWaveOutPrepare.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize); rc != 0 {
			return false
		}
		if rc, _, _ := procWaveOutWrite.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize); rc != 0 {
			procWaveOutUnprep.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize)
			return false
		}
		submitted += end
		return true
	}
	freeSlot := func(slotIdx int) {
		hdr := &slots[slotIdx]
		if hdr.LpData != 0 {
			procWaveOutUnprep.Call(h, uintptr(unsafe.Pointer(hdr)), hdrSize)
			hdr.LpData = 0
			hdr.Flags = 0
		}
		data[slotIdx] = nil
	}

	p.mu.Lock()
	feed := p.feed
	open := p.feedOpen
	p.mu.Unlock()

	nextSlot := 0
	for {
		// Gom mọi chunk vừa tới (không chặn).
	drain:
		for {
			select {
			case b, ok := <-feed:
				if !ok {
					break drain
				}
				pending = append(pending, b...)
				total += len(b)
			default:
				break drain
			}
		}
		closed := false
		if open != nil {
			select {
			case <-open:
				closed = true
			default:
			}
		}

		p.mu.Lock()
		localStop := p.stopping || p.playID != id
		p.cursorMs = playedMs(submitted, sr)
		p.totalMs = playedMs(total, sr)
		progressFn := p.OnProgress
		totalMs := p.totalMs
		curMs := p.cursorMs
		p.mu.Unlock()

		if progressFn != nil && !localStop {
			progressFn(curMs, totalMs)
		}
		if localStop {
			break
		}

		hdr := &slots[nextSlot]
		if hdr.Flags&waveHdrDone != 0 || hdr.LpData == 0 {
			freeSlot(nextSlot)
			if len(pending) > 0 {
				if !submit(nextSlot) {
					break
				}
				nextSlot = (nextSlot + 1) % numBuffers
				continue
			}
			if closed {
				// Hết dữ liệu + hết nguồn cấp: chờ slot còn lại phát xong.
				allDone := true
				for i := 0; i < numBuffers; i++ {
					if slots[i].LpData != 0 && slots[i].Flags&waveHdrDone == 0 {
						allDone = false
						break
					}
				}
				if allDone {
					break
				}
			}
		}
		time.Sleep(15 * time.Millisecond)
	}

	for i := 0; i < numBuffers; i++ {
		freeSlot(i)
	}
	procWaveOutClose.Call(h)

	// Dọn kênh + trạng thái phiên (chỉ phiên đương nhiệm).
	p.mu.Lock()
	if p.playID == id {
		p.stopping = false
		if p.handle == h {
			p.handle = 0
		}
		p.feed = nil
		p.feedOpen = nil
		p.streamAbort = nil
	}
	p.mu.Unlock()

	p.emitEnded(id)
}

func (p *Player) emitEnded(id uint64) {
	p.mu.Lock()
	fn := p.OnEnded
	current := p.playID == id
	p.mu.Unlock()
	if fn != nil && current {
		fn()
	}
}

func playedMs(writtenBytes int, sr int) int {
	if sr <= 0 {
		return 0
	}
	// writtenBytes = số byte đã SUBMIT (gần realtime phía trước); nước rút chấp nhận.
	return writtenBytes * 1000 / (sr * 2)
}

// byteSliceOfInt16 view dữ liệu int16 thành byte slice (little-endian).
func byteSliceOfInt16(in []int16) []byte {
	out := make([]byte, len(in)*2)
	for i, v := range in {
		out[i*2] = byte(v)
		out[i*2+1] = byte(v >> 8)
	}
	return out
}

// CursorMs vị trí phát hiện tại.
func (p *Player) CursorMs() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.cursorMs
}
