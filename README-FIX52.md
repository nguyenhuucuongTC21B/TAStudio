# FIX52 — Sửa "app đứng im" + Nút Chuyển đổi + Streaming + Hàng đợi + Chuẩn hoá nâng cao

> Phạm vi chốt với chủ app: **(1)** kiểm tra thuật toán tăng tốc — không giảm
> chất lượng giọng **(2)** rà soát TOÀN BỘ nút nhấn: xuất WAV/MP3 đúng thư mục,
> timeline % không chạy, thiếu báo thời gian chờ, nút Chuyển đổi 1-lần, nút
> PHÁT vàng chỉ nghe trước **(3)** Streaming: nghe ngay khi đang tổng hợp
> **(4)** Chuẩn hoá văn bản nâng cao **(5)** Hàng đợi tổng hợp + danh sách
> phát **(6)** Catalog 25 giọng chuẩn **(7)** Clone đạt chuẩn → bỏ
> "(thử nghiệm)".

---

## 0. THỦ PHẠM CHÍNH — vì sao timeline % "không chạy" (đã sửa)

`event_throttle.go` tạo event bằng `pendingEvent{payload: ...}` **thiếu
`pending: true`**, mà vòng phát lại có lệnh `if !pe.pending { continue }` →
**100% event bị bỏ qua vĩnh viễn**:

| Event bị chết | Hậu quả người dùng thấy |
|---|---|
| `hcstudio:job` | Thanh % đứng im 0% trong cả quá trình tổng hợp |
| `hcstudio:play` | Đồng hồ phát không nhảy |
| `hcstudio:toast` | Không có thông báo nào (thành công/lỗi) |
| `hcstudio:transport` | Nút dừng/tạm dừng không phản ánh trạng thái |

Chỉ `hcstudio:modeldl` còn sống vì đi đường emit trực tiếp — đúng bằng lý do
**wizard tải mô hình vẫn chạy bình thường** trong khi phần còn lại "đứng im",
để lại dấu hỏi suốt từ FIX45. Đã vá: `pendingEvent{payload, pending: true}`.

## 1. Nút nhấn — phân vai mới rõ ràng

| Nút | Vai trò mới |
|---|---|
| **Chuyển đổi** (vàng, cạnh ô văn bản) | Tạo giọng nói. **Chỉ bấm 1 lần** — nút tự khoá khi đang chạy, mở lại khi có kết quả/lỗi/huỷ. Ctrl+Enter = chuyển đổi. |
| **PHÁT** (vàng, dock dưới) | **Chỉ nghe KẾT QUẢ** đã tổng hợp (nghe trước khi xuất file). Không còn kiêm tạo giọng nói. Không có kết quả → hiện gợi ý bấm Chuyển đổi. |
| **Nghe thử** (`ui.previewVoice()`) | Đọc câu mẫu ngắn bằng giọng đang chọn — nghe trước khi tổng hợp cả bài. |
| **WAV / MP3** | Hộp thoại lưu **mở ngay tại thư mục đã xuất lần trước** (settings.OutDir) và app **tự nhớ** thư mục người dùng chọn. Thêm nút 📁 mở thư mục exports. |
| **Dừng** | Dừng phát + huỷ tổng hợp (cả streaming) như cũ. |

Thanh tiến trình có thêm **đồng hồ chờ**: `Đã chờ 0:12 · còn ~0:45` — hết cảnh
"không biết máy đang làm gì".

## 2. Streaming — nghe ngay khi đang tổng hợp

- Công tắc **"Nghe ngay"** cạnh nút Chuyển đổi (mặc định BẬT, lưu settings).
- Chunk đầu tiên tổng hợp xong là phát ngay; các câu sau vừa sinh vừa nạp vào
  phiên phát (player mới: `PlayStream/AppendStream/EndStream` + scheduler
  streaming 6×120 ms, chống treo bằng streamAbort khi bấm Dừng).
- **Nguyên tắc không giảm chất lượng**: streaming CHỈ bật khi Speed = 1× và
  Pitch = 0 và engine neural (âm lượng là biến đổi pointwise) → mẫu audio
  sinh ra **TRÙNG HỆ** đường đệm-đầy. Đổi tốc độ/cao độ → app tự dùng đường
  đệm-đầy như cũ. Xuất file vẫn byte-khớp playback.
- Tối ưu khác (không đụng model): bỏ bước chuẩn hoá văn bản lặp 2 lần
  (textnorm idempotent — tiết kiệm một vòng regex mỗi câu).

## 3. Hàng đợi tổng hợp + Danh sách phát

- Dán nhiều đoạn (cách nhau bởi dòng trống) → bấm **"Xếp hàng từ văn bản"** →
  các đoạn tổng hợp lần lượt, hiện trạng thái Đang chờ/Đang tổng hợp/Xong/Lỗi.
- **Danh sách phát**: metadata 20 phiên gần nhất (giọng, thời lượng, đoạm văn
  bản) — nghe lại hoặc xuất MP3 nhanh từng mục. Ring phiên 5 → 20.
- API mới: `ListSessions()` (không kèm PCM — nhẹ và an toàn).

## 4. Chuẩn hoá văn bản nâng cao (chạy trước bộ đọc số)

| Ngữ cảnh | Ví dụ | Đọc thành |
|---|---|---|
| Ngày đủ | 05/03/2026 | ngày năm tháng ba năm hai nghìn không trăm hai mươi sáu |
| Giờ | 9h30 · 20:00 | chín giờ ba mươi · hai mươi giờ không |
| Điện thoại | 0905666624 | không chín không năm sáu sáu ... (rời từng số) |
| Phạm vi | 2020-2025 | từ 2020 đến 2025 |
| Đơn vị | 5 km, 3 kg, 60 km/h, 128 GB, 12 m², 5 W | ki lô mét, ki lô gam, ki lô mét một giờ, gi ga byte, mét vuông, oát |

Kỹ thuật: boundary `[^\\p{L}0-9]` tường minh — KHÔNG dùng `\b` của Go RE2
(vì `\b` chỉ tính ASCII, "mét" có `é` khiến `m\b` khớp sai thành "métét").
Hook chạy TRƯỚC `reMath2` để "05/03/2026" không bị đọc thành phép chia
("năm bằng ba"). go test PASS đủ bộ cũ + 2 bộ mới.

## 5. Catalog 25 giọng + Clone "tốt nghiệp"

- **AuditVoiceCatalog**: lúc startup, đối chiếu catalog Go 25 giọng với file
  `voices_v3_turbo.json` thật trên máy — lệch tên/bị bỏ sót sẽ WARNING ngay
  trong `hcstudio.log` thay vì im lặng rơi về default voice khi synth.
- **Clone**: pipeline đã qua preflight 2/2 assets, numpy-parity 1e-13 và
  RIG cgo PASS từ FIX50 → giao diện bỏ dòng "(thử nghiệm)", chỉ còn nhãn
  "zero-shot". Nếu thật thao tác lỗi, log + toast vẫn báo như cũ.

## Bảng thay đổi

| File | Nội dung |
|---|---|
| `event_throttle.go` | **FIX THỦ PHẠM**: `pending: true` — mọi event sống lại |
| `internal/bridge/types.go` | +`ElapsedSec`, +`Streaming`, +`Stream` request, +`SessionInfo` |
| `internal/appstate/settings.go` | +`StreamLive` (mặc định true) |
| `internal/player/winmm_windows.go` | +`PlayStream/AppendStream/EndStream` + `runStreamSession` + Stop an toàn |
| `internal/player/winmm_other.go` | stub 3 method mới |
| `app.go` | luồng streaming trong `runSynthesis`, `pushJobElapsed` (ETA+đã chờ), `ListSessions`, ring 20, `PickSavePath` nhớ thư mục + persist `OutDir`, skip double-textnorm, catalog audit |
| `internal/engine/voices.go` | +`AuditVoiceCatalog` |
| `internal/textnorm/textnorm.go` | +ngày/giờ/điện thoại/phạm vi/đơn vị (boundary tường minh) |
| `internal/textnorm/textnorm_test.go` | cập nhật 1 expectation + 2 bộ test FIX52 |
| `frontend/dist/index.html` | nút Chuyển đổi + "Nghe ngay" + wait-label + card Hàng đợi/Danh sách phát + CSS Navy·Gold đồng bộ + bỏ "(thử nghiệm)" |
| `frontend/dist/assets/js/ui.js` | renderTransport mới, `convertRequested/previewVoice`, hàng đợi + playlist, Ctrl+Enter → chuyển đổi |
| `frontend/dist/assets/js/state.js` | +`streamLive/streaming/queue/sessions/elapsedSec` |
| `frontend/dist/assets/js/bridge.js` | +`ListSessions` (thật + mock) |
| `frontend/dist/assets/js/icons.js` | +icon "convert" (sóng âm) |

## Kiểm chứng đã chạy

- `gofmt` sạch · `go vet ./internal/... .` EXIT=0
- `go test` dsp + textnorm PASS (có 2 bộ test FIX52 mới)
- `node --check` 5/5 file JS
- ID cross-check 60/60 khớp, không id trùng
- Headless test (browser thật + mock bridge): Chuyển đổi khoá/mở đúng pha ·
  đồng hồ chờ + ETA hiện đúng · hàng đợi 3 đoạn chạy tuần tự Xong→Xong→Xong ·
  nút PHÁT đổi title đúng · badge "(thử nghiệm)" đã bỏ · light/dark OK ·
  0 lỗi console.

## Nghiệm thu trên máy thật (sau CI)

1. Tổng hợp đoạn văn dài → thanh % chạy liên tục, có "Đã chờ … còn ~…".
2. Toast thông báo hiện lại (thành công/lỗi) — nhờ fix throttle.
3. Bấm "Chuyển đổi" 2 lần liên tiếp → lần 2 bị chặn khi đang chạy.
4. Sau khi có kết quả → bấm PHÁT (vàng) → nghe kết quả; không có kết quả →
   toast hướng dẫn.
5. Bật "Nghe ngay" (mặc định bật, tốc độ 1×) → nghe được ngay khi câu đầu
   xong; Task Manager thấy app hoạt động mượt; Task Manager RAM không tăng.
6. Xuất WAV → hộp thoại mở đúng thư mục đã xuất lần trước; nút 📁 mở được
   thư mục exports.
7. Dán 3 đoạn (dòng trống ngăn cách) → Xếp hàng → lần lượt xong, danh sách
   phát hiện 3 mục, nghe lại + xuất MP3 từng mục OK.
8. Đoạn văn có "05/03/2026", "9h30", "0905666624", "5 km", "128 GB" → đọc
   đúng ngữ cảnh (xem log `hcstudio.log` để đối chiếu text đã chuẩn hoá).
9. Nhân bản giọng: không còn chữ "(thử nghiệm)"; thao tác như FIX50.
10. A/B streaming so với đệm-đầy (cùng text, tốc độ 1×, pitch 0): chất lượng
    nghe như nhau; xuất file 2 lần vẫn khớp nhau.

## Rollback

Ghi đè repo bằng zip FIX51 — toàn bộ FIX52 là add-on tầng Go/JS/player,
không đụng C++ core, không cần build lại toolchain.
