package main

// diaglog.go — PATCH run #29: nhật ký chẩn đoán của HCStudio.
//
// Bối cảnh: exe đã khởi động được trên Windows nhưng ta MÙ hoàn toàn về phía
// máy người dùng (không console, không log) — không biết SAPI liệt kê được
// bao nhiêu giọng, model neural thiếu file nào, JS giao diện có chết lúc
// hydrate không. File này dựng một logger chẩn đoán siêu gọn:
//
//   - Ghi APPEND vào 2 nơi độc lập (hỏng nơi này còn nơi kia):
//       1) %LOCALAPPDATA%\HCStudio\logs\hcstudio.log   (chính, luôn ghi được)
//       2) hcstudio.log nằm cạnh file exe (best effort — Program Files sẽ
//          chặn ghi, không sao, còn nơi số 1)
//   - Method WriteLog được Wails bind thành window.go.backend.App.WriteLog
//     để PHÍA JS cũng ghi được vào cùng một file — kể cả khi bridge.js/ui.js
//     của app đã chết, vì bindings do Wails inject độc lập với script app.
//   - An toàn tuyệt đối với app: mọi lỗi ghi log đều nuốt lặng lẽ, KHÔNG
//     bao giờ làm app crash vì chuyện log.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

var (
	diagMu      sync.Mutex
	diagFiles   []*os.File
	diagDirOnce sync.Once
	diagDirPath string
)

// DiagLogDir trả thư mục log chính (để OpenFolder("logs") mở explorer).
func DiagLogDir() string { return diagDirPath }

// diagInit mở các file log. Gọi đúng 1 lần từ main() trước wails.Run.
func diagInit() {
	diagDirOnce.Do(func() {
		// (1) %LOCALAPPDATA%\HCStudio\logs\hcstudio.log
		base := os.Getenv("LOCALAPPDATA")
		if base == "" {
			if c, err := os.UserCacheDir(); err == nil {
				base = c
			}
		}
		if base != "" {
			dir := filepath.Join(base, "HCStudio", "logs")
			if err := os.MkdirAll(dir, 0o755); err == nil {
				diagDirPath = dir
				if f, ferr := os.OpenFile(
					filepath.Join(dir, "hcstudio.log"),
					os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); ferr == nil {
					diagFiles = append(diagFiles, f)
				}
			}
		}

		// (2) hcstudio.log cạnh exe — best effort.
		exeNote := "(không xác định)"
		if exe, err := os.Executable(); err == nil {
			exeNote = exe
			adj := filepath.Join(filepath.Dir(exe), "hcstudio.log")
			if f, ferr := os.OpenFile(adj,
				os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); ferr == nil {
				diagFiles = append(diagFiles, f)
			}
		}

		diagf("======== HCStudio session · exe=%s ========", exeNote)
		diagf("log ghi tại: %s (và hcstudio.log cạnh exe nếu ghi được)", diagDirPath)
	})
}

// diagf ghi 1 dòng timestamped vào mọi file log đang mở. Không bao giờ panic.
func diagf(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	line := time.Now().Format("2006-01-02 15:04:05.000") + " " + msg + "\r\n"
	diagMu.Lock()
	defer diagMu.Unlock()
	for _, f := range diagFiles {
		_, _ = f.WriteString(line)
	}
}

// WriteLog — Wails binding cho phía JS gọi vào (window.go.backend.App.WriteLog).
// level: info | warn | error. Message nhiều dòng được gọp lại cho gọn log.
func (a *App) WriteLog(level, message string) {
	level = strings.TrimSpace(level)
	if level == "" {
		level = "info"
	}
	message = strings.ReplaceAll(message, "\r", " ")
	message = strings.ReplaceAll(message, "\n", " | ")
	if len(message) > 2000 {
		message = message[:2000]
	}
	diagf("[%s] %s", level, message)
}
