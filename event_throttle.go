package main

import (
	"context"
	"sync"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// EventThrottle gộp các event tần suất cao (tiến trình) để UI không nghẽn
// — tối đa ~20 event/giây cho mỗi loại, event cuối cùng luôn được gửi (trailing).
type EventThrottle struct {
	ctx    context.Context
	mu     sync.Mutex
	latest map[string]pendingEvent
	lastAt map[string]time.Time
	stop   chan struct{}
}

type pendingEvent struct {
	payload any
	pending bool
}

// NewEventThrottle khởi động worker gom event nền.
func NewEventThrottle(ctx context.Context) *EventThrottle {
	t := &EventThrottle{
		ctx:    ctx,
		latest: map[string]pendingEvent{},
		lastAt: map[string]time.Time{},
		stop:   make(chan struct{}),
	}
	go t.loop()
	return t
}

// Send đẩy event qua throttle; trả ngay lập tức.
func (t *EventThrottle) Send(name string, payload any) {
	t.mu.Lock()
	// PATCH FIX52 — BUG NGHIÊM TRỌNG: trước đây thiếu pending:true nên
	// vòng loop bên dưới (`if !pe.pending { continue }`) bỏ qua TOÀN BỘ
	// event => thanh tiến trình %, đồng hồ phát, toast... chết lặng;
	// người dùng thấy app "đứng im" trong lúc tổng hợp. Đây là thủ
	// phạm chính của phản hồi "timeline % không chạy".
	t.latest[name] = pendingEvent{payload: payload, pending: true}
	t.mu.Unlock()
}

const throttleInterval = 45 * time.Millisecond

func (t *EventThrottle) loop() {
	ticker := time.NewTicker(throttleInterval)
	defer ticker.Stop()
	for {
		select {
		case <-t.stop:
			return
		case <-ticker.C:
			t.mu.Lock()
			for name, pe := range t.latest {
				if !pe.pending {
					continue
				}
				runtime.EventsEmit(t.ctx, name, pe.payload)
				delete(t.latest, name)
				t.lastAt[name] = time.Now()
			}
			t.mu.Unlock()
		}
	}
}
