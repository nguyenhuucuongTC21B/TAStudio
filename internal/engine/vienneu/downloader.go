package vienneu

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"

	"hcstudio/internal/engine"
)

// DownloadEvent phát về UI qua Wails event (backend wrapper chuyển tiếp).
type DownloadEvent struct {
	State       string  `json:"state"` // running | done | cancelled | error
	Pct         float64 `json:"pct"`
	CurrentFile string  `json:"currentFile"`
	FileIdx     int     `json:"fileIdx"`
	TotalFiles  int     `json:"totalFiles"`
	BytesDone   int64   `json:"bytesDone"`
	BytesTotal  int64   `json:"bytesTotal"`
	Message     string  `json:"message,omitempty"`
}

// Downloader tải AssetManifest theo tuần tự, resume từng file bằng HTTP Range.
type Downloader struct {
	sink    func(DownloadEvent)
	cancel  context.CancelFunc
	running atomic.Bool
}

// NewDownloader nhận hàm đẩy event (đã throttle phía caller nếu cần).
func NewDownloader(sink func(DownloadEvent)) *Downloader {
	return &Downloader{sink: sink}
}

// Cancel dừng tiến trình đang chạy một cách an toàn (giữ .part để lần sau nối).
func (d *Downloader) Cancel() {
	if d.cancel != nil {
		d.cancel()
	}
}

// Running trạng thái hiện tại.
func (d *Downloader) Running() bool { return d.running.Load() }

// Run bắt đầu tải các file BẮT BUỘC của manifest vào modelDir.
// PATCH FIX51: các file int8 (Mandatory:false) KHÔNG nằm trong luồng
// chuẩn — người dùng chủ động bấm "Tải gói int8" mới lấy (RunInt8).
// Thread-safe: chặn re-entry.
func (d *Downloader) Run(parent context.Context, modelDir string) error {
	return d.runFiltered(parent, modelDir, func(a engine.AssetSpec) bool {
		return a.Mandatory
	}, "Đã tải đủ toàn bộ trọng số")
}

// RunInt8 tải RIÊNG bộ 7 file int8 (tùy chọn nhẹ RAM). Nếu máy đã đủ
// (skip-theo-size) thì chạy xong gần như ngay lập tức.
func (d *Downloader) RunInt8(parent context.Context, modelDir string) error {
	return d.runFiltered(parent, modelDir, func(a engine.AssetSpec) bool {
		return strings.HasPrefix(filepath.ToSlash(a.DestRel), "int8/")
	}, "Đã tải đủ bộ int8 (nhẹ RAM ~4 lần)")
}

// runFiltered: phần thân chung — tải đúng các entry thoả pick().
func (d *Downloader) runFiltered(parent context.Context, modelDir string, pick func(engine.AssetSpec) bool, doneMsg string) error {
	if !d.running.CompareAndSwap(false, true) {
		return fmt.Errorf("tiến trình tải model đang chạy")
	}
	defer d.running.Store(false)

	ctx, cancel := context.WithCancel(parent)
	d.cancel = cancel
	defer cancel()

	// Lọc TRƯỚC để TotalFiles/BytesTotal/FileIdx khớp đúng tập đang tải.
	var entries []engine.AssetSpec
	for _, a := range engine.AssetManifest {
		if pick != nil && !pick(a) {
			continue
		}
		entries = append(entries, a)
	}

	total := int64(0)
	for _, a := range entries {
		if a.SizeHint > 0 {
			total += a.SizeHint
		}
	}
	done := int64(0)

	d.emit(ctx, DownloadEvent{
		State: "running", Pct: 0, TotalFiles: len(entries), BytesTotal: total,
	})

	client := &http.Client{Timeout: 0} // streaming; kiểm soát timeout ở per-request ctx

	for i, a := range entries {
		if err := ctx.Err(); err != nil {
			d.emit(ctx, DownloadEvent{State: "cancelled", Message: "Đã huỷ theo yêu cầu", FileIdx: i})
			return ctx.Err()
		}
		destAbs := filepath.Join(modelDir, a.DestRel)
		_ = os.MkdirAll(filepath.Dir(destAbs), 0o755)

		// Đã có file hoàn chỉnh rồi thì bỏ qua.
		if st, err := os.Stat(destAbs); err == nil && st.Size() > 0 && a.SizeHint > 0 && st.Size() == a.SizeHint {
			done += st.Size()
			continue
		}
		partPath := destAbs + ".part"
		var existing int64
		if st, err := os.Stat(partPath); err == nil {
			existing = st.Size()
		}
		doneBase := done // tiến độ trước khi cộng phần .part cũ
		done = doneBase + existing

		// PATCH FIX48: mỗi file thử lần lượt AssetURLs(a) — mirror của chủ
		// app (HCSTUDIO_ASSET_MIRROR) trước, URL gốc đã pin sau. Chỉ khi
		// CẢ HAI nguồn đều lỗi mới báo lỗi cho UI.
		//
		// Quy tắc .part: chỉ resume ở ứng viên ĐẦU TIÊN. Ứng viên sau
		// (fallback) luôn tải lại từ đầu (O_TRUNC) — vì .part cũ có thể
		// sinh từ nguồn khác, nối tiếp xuyên nguồn sẽ hỏng weights âm thầm
		// (giả định mirror byte-identical nhưng không mạo hiểm).
		var lastErr error
		for j, url := range engine.AssetURLs(a) {
			if err := ctx.Err(); err != nil {
				d.emit(ctx, DownloadEvent{State: "cancelled", Message: "Đã huỷ theo yêu cầu", FileIdx: i})
				return ctx.Err()
			}
			have := existing
			pre := existing // phần có sẵn cộng vào done cho lần thử này
			if j > 0 {
				have = 0 // nguồn khác .part cũ → tải lại từ đầu
				pre = 0
			}
			var streamed int64
			lastErr = d.fetchOne(ctx, client, url, partPath, have, func(delta int64) {
				streamed += delta
				done = doneBase + pre + streamed
				// PATCH run #31: kẹp pct trong [0,100] — phòng trường hợp
				// server trả 200 (bỏ qua Range) làm đếm dôi done.
				pct := float64(done) / float64(maxI64(total, 1)) * 100
				if pct < 0 {
					pct = 0
				} else if pct > 100 {
					pct = 100
				}
				d.emit(ctx, DownloadEvent{
					State: "running", Pct: pct, CurrentFile: filepath.Base(a.DestRel),
					FileIdx: i + 1, TotalFiles: len(entries),
					BytesDone: maxI64(done, 0), BytesTotal: maxI64(total, done, 1),
				})
			})
			if lastErr == nil {
				break
			}
			if ctx.Err() != nil {
				d.emit(ctx, DownloadEvent{State: "cancelled", Message: "Đã huỷ theo yêu cầu", FileIdx: i})
				return ctx.Err()
			}
		}
		if lastErr != nil {
			d.emit(ctx, DownloadEvent{State: "error",
				Message: fmt.Sprintf("Lỗi tải %s (đã thử %d nguồn): %v", filepath.Base(a.DestRel), len(engine.AssetURLs(a)), lastErr), FileIdx: i})
			return lastErr
		}
		// PATCH run #31: Windows không cho Rename đè file có sẵn —
		// file dest cỡ sai (HF cập nhật weights) phải xoá trước.
		_ = os.Remove(destAbs)
		if rerr := os.Rename(partPath, destAbs); rerr != nil {
			d.emit(ctx, DownloadEvent{State: "error",
				Message: fmt.Sprintf("Không ghi được %s: %v", filepath.Base(a.DestRel), rerr), FileIdx: i})
			return rerr
		}
	}

	// PATCH FIX42: event "done" phải mang đủ số liệu — tính trên tập ĐÃ
	// LỌC (14 file luồng chuẩn / 7 file int8), không phải toàn manifest.
	d.emit(ctx, DownloadEvent{
		State: "done", Pct: 100, BytesTotal: done, BytesDone: done,
		FileIdx: len(entries), TotalFiles: len(entries),
		Message: doneMsg,
	})
	return nil
}

func (d *Downloader) fetchOne(ctx context.Context, client *http.Client, url, dest string, haveBytes int64, onDelta func(int64)) error {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if haveBytes > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", haveBytes))
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
		// PATCH run #31: server bỏ qua Range → tải lại từ đầu. Trước đây
		// phần .part cũ vẫn nằm trong "done" → đếm dôi → pct > 100.
		if haveBytes > 0 {
			onDelta(-haveBytes)
		}
		haveBytes = 0
	case http.StatusPartialContent:
		// đúng ý, nối tiếp
	default:
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	// PATCH run #31: 206 (Range hoạt động) → nối tiếp .part (O_APPEND).
	// 200 (server bỏ qua Range) → PHẢI ghi đè từ đầu (O_TRUNC), không thì
	// dữ liệu mới nối vào đuôi .part cũ → file trọng số hỏng âm thầm.
	flags := os.O_CREATE | os.O_WRONLY
	if resp.StatusCode == http.StatusPartialContent {
		flags |= os.O_APPEND
	} else {
		flags |= os.O_TRUNC
	}
	f, err := os.OpenFile(dest, flags, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()

	buf := make([]byte, 256<<10)
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			if _, werr := f.Write(buf[:n]); werr != nil {
				return werr
			}
			onDelta(int64(n))
		}
		if rerr == io.EOF {
			return nil
		}
		if rerr != nil {
			return rerr
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
	}
}

func (d *Downloader) emit(ctx context.Context, e DownloadEvent) {
	if d.sink != nil {
		d.sink(e)
	}
}

func maxI64(nums ...int64) int64 {
	m := nums[0]
	for _, n := range nums[1:] {
		if n > m {
			m = n
		}
	}
	return m
}
