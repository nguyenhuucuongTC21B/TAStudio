# FIX51 — Nhẹ RAM int8 + Giao diện Navy·Gold + Setup 1 file (Phương án B) + dọn dist

> Phạm vi chốt với chủ app: **(1)** nâng UI theo thiết kế tự chuẩn bị (bảng màu
> Navy·Gold·Red, logo riêng, footer trang trọng) **(2)** chế độ **"Nhẹ RAM (int8)"**
> tùy chọn — nhẹ RAM ~4 lần, f32 vẫn là mặc định **(3)** kịch bản đóng gói
> **HCStudio-Setup.exe 1 file duy nhất** chứa app + dll + 14 file trọng số
> **(4)** dọn dist: mặc định chỉ còn `HCStudio.exe`.

---

## 1. Giao diện mới (Navy·Gold) — giữ 100% thiết kế của chủ app

File `frontend/dist/index.html` được thay bằng bản chủ app chuẩn bị, đã qua
quy trình soát headless (browser thật + mock bridge) và vá 9 điểm:

| Vấn đề phát hiện | Đã xử lý |
|---|---|
| Nút Play hiện cả icon phát lẫn tạm dừng (svg[hidden] không được ẩn) | thêm `[hidden]{display:none !important}` |
| Chế độ TỐI chết (JS bật class `.dark`, CSS chờ attribute khác) | chuyển 8 selector sang `.dark` |
| Thiếu ~60 selector (danh sách giọng, toast, pill trạng thái, icon...) | bổ sung đầy đủ, chuyển thể Navy·Gold |
| Wizard ghi "20 giọng"/"520 MB · 12 file" (lỗi cũ từ FIX49) | sửa thành **25 giọng · 607 MB · 14 file** |
| `assets/logo.png` không tồn tại | tạo logo: sóng âm vàng trên nền navy |
| Khối chẩn đoán thiếu `ImportOfflinePackage` | bổ sung |
| Footer "Developt" | "Developed" |
| 3 nút không icon từ FIX50 (paste/clear/models) | có icon (clipboard/thùng rác/thư mục) |
| Cấu trúc | **53/53 ID bắt buộc đều khớp** — không đụng JS |

Ảnh duyệt: thư mục `ui-preview` trên trang tải (sáng / tối / danh sách giọng / wizard).

## 2. Nhẹ RAM (int8) — tùy chọn, KHÔNG bắt buộc

- Nguồn: `onnx_int8/` @ pin **8b7e9cff** — **7 file, tên TRÙNG KHỚP `update/`**,
  tổng **165.496.148 B ≈ 158 MB** (backbone 415 MB → 104 MB = nhẹ đúng ~4 lần).
- Manifest: 7 entry **`Mandatory: false`** → không bao giờ chặn wizard/readiness,
  không tính vào "thiếu" khi nhập gói ZIP 14/14.
- Dùng:
  1. Bấm **"Tải gói int8 (~158 MB)"** trong khối Giọng đọc (lần duy nhất), hoặc
     nhập `HCStudio-v5-FIX51-weights-int8-light.zip` bằng nút **Nhập gói ZIP (offline)**.
  2. Bật gạt **"Nhẹ RAM (int8)"** → app lưu setting → **khởi động lại app**.
- Cơ chế an toàn: engine chỉ đọc `int8/` khi **ĐỦ 7 file đúng kích thước byte**
  (`Int8AssetsReady`) — thiếu/sai 1 file là tự chạy `update/` (f32). Không bao giờ
  nửa vời. A/B chất lượng: gạt bật/tắt + restart, cùng câutext so sánh.
- Luồng tải int8 tách riêng (`RunInt8`) — thanh tiến độ đếm đúng 7/7 file,
  mirror + resume .part giữ nguyên cơ chế FIX48.

## 3. Setup 1 file (Phương án B) — cho máy KHÔNG có internet

Trên máy build (GitHub `windows-latest` đã có sẵn Inno Setup 6):

```powershell
powershell -File scripts\fetch-weights-setup.ps1     # tải 14 file weights (pin commit, skip-if-exists)
powershell -File scripts\build.ps1 -Full             # build dist như thường lệ
powershell -File scripts\make-setup.ps1 -DistDir dist # => build\setup\HCStudio-Setup.exe
```

- Output: **`HCStudio-Setup.exe` (~450–500 MB)** — copy 1 file sang máy không mạng,
  cài 1 lần: app vào `%LOCALAPPDATA%\HCStudio`, weights vào
  `%APPDATA%\HCStudio\models\vieneu-v3-turbo` (đúng chỗ app đọc), shortcut Start
  Menu + tùy chọn desktop. Gỡ cài đặt KHÔNG xóa weights (cài lại khỏi tải lại).
- Script tự sinh `setup.iss` (ASCII thuần), tự tìm ISCC, in SHA256 khi xong.
- Cài per-user **không cần quyền admin** — hợp máy cơ quan khóa quyền.

## 4. Dọn dist

- `HCStudio-debug.exe`: chỉ build khi thêm cờ **`-DebugExe`**
  (`build.ps1 -Full -DebugExe`) — vẫn có khi cần bắt lỗi crash.
- `HCStudio-Lite.exe`: mặc định không build khi `-Full`; build Full sẽ **tự dọn**
  Lite/debug sót trong dist. Cần Lite dự phòng: chạy `build.ps1` không `-Full`
  (vẫn < 2 phút, không đổi gì).

---

## Bảng thay đổi

| File | Nội dung |
|---|---|
| `frontend/dist/index.html` | UI Navy·Gold (bản chủ app + 9 vá + toggle int8) |
| `frontend/dist/assets/logo.png` | logo mới (mới) |
| `frontend/dist/assets/js/ui.js` | +`wireLightRam`, els int8, auto-refresh trạng thái |
| `frontend/dist/assets/js/state.js` | +`lightRam` (defaults/hydrate/save/emit) |
| `frontend/dist/assets/js/bridge.js` | +`GetInt8Status`, `DownloadInt8Assets` (thật + mock) |
| `internal/engine/assets_manifest.go` | +7 entry int8 optional, `PreferInt8Dir`, `Int8AssetsReady`, `ResolveModelPaths` chọn `int8/` |
| `internal/engine/vienneu/downloader.go` | refactor `runFiltered`: `Run` (mandatory 14) + `RunInt8` (7) |
| `internal/appstate/settings.go` | +`LightRam` (persist settings.json) |
| `app.go` | startup gắn flag TRƯỚC NewHybrid; SaveSettings; `GetInt8Status`; `DownloadInt8Assets`; import optional-safe |
| `scripts/build.ps1` | +`-DebugExe`; dọn dist; (0 backtick, ASCII 100%) |
| `scripts/make-setup.ps1` | **mới** — Inno Setup 1-file |
| `scripts/fetch-weights-setup.ps1` | **mới** — payload weights cho Setup |

Kiểm chứng đã chạy: `gofmt` sạch · `go vet ./internal/... .` EXIT=0 ·
`go test` dsp+textnorm PASS · RIG51 cgo type-check với header thật @cc037cf EXIT=0 ·
`node --check` 5/5 file JS · 4 file ps1 ASCII 100% / 0 backtick ·
ID cross-check 51/51 khớp · headless test UI (sáng/tối/wizard/dropdown) 6/6 chỉ số.

## Nghiệm thu trên máy thật (sau CI)

1. Build -Full → dist **chỉ có** `HCStudio.exe` + runtime files.
2. `build.ps1 -Full -DebugExe` → có thêm debug exe (test xong bỏ cờ).
3. UI: sáng/tối chuyển OK; danh sách giọng có badge NEURAL; toast có màu viền.
4. Wizard: đúng "25 giọng" + "≈ 607 MB · 14 file".
5. Bấm "Tải gói int8" → thanh tiến độ chạy 7/7 → toast thành công.
6. Bật "Nhẹ RAM (int8)" → toast lưu → restart → log có
   `startup: LightRam=ON — nạp weights int8`; Task Manager thấy RAM giảm rõ.
7. Tắt gạt + restart → về f32; so chất lượng giọng (A/B) cùng câu chữ.
8. Nhập gói 14/14 (không có int8) → vẫn báo THÀNH CÔNG (int8 không tính thiếu).
9. Xóa 1 file int8 → bật gạt → restart → app vẫn chạy (tự rơi f32) + log cảnh báo.
10. CI chạy `fetch-weights-setup.ps1` + `make-setup.ps1` → HCStudio-Setup.exe;
    cài thử máy sạch không mạng → synth + clone chạy được ngay.

## Rollback

Ghi đè repo bằng zip FIX50 (UI + int8 + setup scripts là add-on thuần, không đụng
C++ core — rollback không cần build lại toolchain).
