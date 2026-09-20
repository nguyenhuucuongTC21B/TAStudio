//go:build !windows

// Package player — stub cho hệ điều hành khác (chỉ để build/vet vượt qua).
// Bản phát hành thật chạy Windows với bản winmm đầy đủ.
package player

import "sync"

type Player struct {
	mu         sync.Mutex
	playing    bool
	paused     bool
	OnProgress func(cursorMs, totalMs int)
	OnEnded    func()
}

func New() *Player { return &Player{} }

func (p *Player) IsPlaying() bool { p.mu.Lock(); defer p.mu.Unlock(); return p.playing }
func (p *Player) IsPaused() bool  { p.mu.Lock(); defer p.mu.Unlock(); return p.paused }
func (p *Player) TogglePause() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.playing {
		p.paused = !p.paused
	}
	return p.paused
}
func (p *Player) Stop()                                { p.mu.Lock(); p.playing = false; p.mu.Unlock() }
func (p *Player) CursorMs() int                        { return 0 }
func (p *Player) Play(samples []float32, sr int) error { return nil }

// PATCH FIX52: stub streaming cho nền tảng khác (chỉ để go vet vượt qua).
func (p *Player) PlayStream(samples []float32, sr int) error { return nil }
func (p *Player) AppendStream(samples []float32)             {}
func (p *Player) EndStream()                                 {}
