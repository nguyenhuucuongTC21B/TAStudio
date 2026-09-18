# Hướng dẫn build HCStudio v5.0

## Yêu cầu chung

| Công cụ | Bản tối thiểu | Ghi chú |
|---|---|---|
| Windows | 10 21H2+ / 11 x64 | WebView2 Runtime mặc định có sẵn |
| Go | 1.23 | `winget install GoLang.Go` |
| Git | bất kỳ | để clone submodule |

## 🟢 Build Lite (SAPI5-only) — ~2 phút

```powershell
cd HCStudio-v5
.\scripts\build.ps1
```

Kết quả: `dist\HCStudio-Lite.exe`. Chạy được ngay, dùng giọng hệ thống
(Microsoft An…). Phù hợp máy rất yếu hoặc cần test UI nhanh.

## 🔵 Build Full (thêm tầng Neural VieNeu) — lần đầu 30–60 phút

### Bước 0. Toolchain native (chỉ cần khi `-Full`)

Cài **Visual Studio 2022 Build Tools** kèm workload "Desktop development
with C++" (có MSVC + CMake):

```powershell
winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive"
```

### Bước 1. Chạy script

```powershell
.\scripts\build.ps1 -Full          # thêm -Clean nếu muốn rebuild sạch
```

Script tự động:

1. Clone `pnnbao97/VieNeu-TTS.cpp` @commit pinned + submodule `llama.cpp`.
2. Tải ONNX Runtime SDK win-x64 release.
3. `cmake` build **static lib** `vieneu-tts-core.lib` (MSVC x64 Release).
4. Sinh `native-build/link-libs.txt` rồi gọi `go build -tags vieneu`
   với `CGO_*FLAGS` trỏ đúng tới các lib — tất cả link **tĩnh** vào exe.
5. Xuất `dist\HCStudio.exe` với `-H windowsgui -s -w`.

Sau lần đầu, các bước 1–3 được cache trong `third_party/` + `native-build/`,
các lần build sau chỉ mất ~30 giây.

### Lỗi thường gặp

| Hiện tượng | Xử lý |
|---|---|
| `clang: command not found` / CGO lỗi | Truyền `-CC "path\to\clang.exe"`? (tạm: cài LLVM: `winget install LLVM.LLVM`) hoặc dùng bản Lite rồi vá env `CC=clang-cl` theo môi trường thực tế |
| CMake không thấy ORT | Kiểm tra `ort_sdk\onnxruntime-win-x64-*\lib\onnxruntime.lib` tồn tại; xoá `ort_sdk` để tải lại |
| Submodule llama.cpp rỗng | `cd third_party\VieNeu-TTS.cpp && git submodule update --init --recursive` |
| Antivirus chặn exe unsigned | Thêm trust folder `dist\` |

## 📦 Sau khi build — phân phối gì?

Chỉ cần **một tệp `dist\HCStudio.exe`**. Người dùng cuối:

- chạy exe → lần đầu có wizard tải trọng số neural (~1 GB) về
  `%LOCALAPPDATA%\HCStudio\models\vieneu-v3-turbo\` (có resume);
- hoặc bỏ qua, dùng Ultra-Lite ngay.

Trọng số là **dữ liệu** chứ không phải logic, nên tách khỏi binary: giữ exe
nhỏ, cập nhật model độc lập, không phải ký lại exe khi model đổi phiên bản.

## 🧪 Kiểm tra hàng loạt (dev)

```powershell
go vet ./...                # cả linux host lẫn windows target
$env:GOOS="windows"; go vet ./...
go test ./internal/dsp/     # unit test WSOLA/splitter/WAV
```

Preview giao diện **không cần compile**: mở thẳng
`frontend/dist/index.html` bằng trình duyệt — chế độ mock-bridge sẽ mô phỏng
toàn bộ pipeline (kèm âm beep minh hoạ playback).
