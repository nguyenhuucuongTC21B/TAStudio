package vienneu

// diag.go — PATCH FIX41: logger mức package cho driver neural VieNeu.
//
// Bối cảnh: người dùng báo app "tự thoát" ngay sau khi bấm tạo giọng đọc
// (engine neural). hcstudio.log của package main chỉ dừng lại ở dòng
// "resolve -> engine=neural ..." vì driver gọi native C/C++ ngay sau đó —
// crash xảy ra BÊN TRONG vieneu_init_v2 / vieneu_synthesize_v2 thì package
// main không hề biết. exe là GUI subsystem (windowsgui) nên toàn bộ stderr
// — kể cả stack trace "fatal error" của Go runtime khi lỗi trong code cgo —
// đi vào hư vô.
//
// Giải pháp: driver tự ghi từng bước vào log RIÊNG
// %LOCALAPPDATA%\HCStudio\logs\vieneu.log:
//
//	[vtieneu] init: bắt đầu vieneu_init_v2 ...
//	[vtieneu] tts: gọi vieneu_synthesize_v2 ...
//
// Dòng cuối cùng của vieneu.log = lệnh gọi native chính xác đang chạy khi
// tiến trình tắt ngóm -> khoanh vùng nguyên nhân không cần build lại.
//
// File không build-tag: cả driver_cgo.go lẫn stub.go đều dùng được.
// Nguyên tắc: ghi log phải rẻ và vô hại — KHÔNG BAO GIỜ panic, KHÔNG BAO
// GIỜ trả lỗi, ghi hỏng thì bỏ qua lặng lẽ.

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

var (
	vlogMu   sync.Mutex
	vlogFile *os.File
	vlogOnce sync.Once
)

// vlogOpen mở vieneu.log (append). Chạy đúng một lần, best effort.
func vlogOpen() {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		if c, err := os.UserCacheDir(); err == nil {
			base = c
		}
	}
	if base == "" {
		return
	}
	dir := filepath.Join(base, "HCStudio", "logs")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	if f, err := os.OpenFile(filepath.Join(dir, "vieneu.log"),
		os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err == nil {
		vlogFile = f
	}
}

// vlogf ghi 1 dòng timestamped vào vieneu.log. An toàn tuyệt đối:
// không panic, không blocking lâu, không phụ thuộc package main.
func vlogf(format string, args ...interface{}) {
	vlogOnce.Do(vlogOpen)
	msg := fmt.Sprintf(format, args...)
	line := time.Now().Format("2006-01-02 15:04:05.000") + " [vieneu] " + msg + "\r\n"
	vlogMu.Lock()
	defer vlogMu.Unlock()
	if vlogFile != nil {
		_, _ = vlogFile.WriteString(line)
	}
}
