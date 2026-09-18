# HCStudio v5.0 — Kiến trúc hệ thống

> Ứng dụng TTS offline hoàn toàn cho Windows · Go + Wails v2 · Hybrid Engine
> (VieNeu-TTS v3 Turbo Neural + SAPI5 Ultra-Lite) · Single .exe · Zero-port

## 1. Tổng quan

HCStudio v5.0 là ứng dụng desktop chuyển văn bản thành giọng nói tiếng Việt,
chạy 100% offline trên CPU, đóng gói thành **một tệp `.exe` duy nhất**.
Giao tiếp giữa frontend (WebView2) và backend (Go) sử dụng cơ chế **Bind/Bridge
trực tiếp qua bộ nhớ** của Wails v2 — không mở bất kỳ cổng mạng nào, không sinh
cửa sổ CMD (binary biên dịch với `-H windowsgui`).

Đặc thù bài toán: chất lượng giọng "tự nhiên như người thật" đòi hỏi mô hình
neural hàng trăm MB, trong khi nhị phân app phải gọn để khởi động nhanh.
Kiến trúc vì vậy tách bạch **LOGIC (biên dịch trong exe)** và **DỮ LIỆU TRỌNG SỐ
(model assets)**: toàn bộ engine suy luận được link tĩnh vào binary; trọng số mô
hình được ứng dụng tự tải về một lần duy nhất vào `%LOCALAPPDATA%\HCStudio`
(có wizard tiến trình trong UI, có resume), sau đó không bao giờ cần Internet.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        HCStudio.exe (single file)                        │
│                                                                          │
│  ┌───────────────────────────── Wails v2 Runtime ─────────────────────┐ │
│  │  WebView2 (HTML/CSS/JS embed) ⇄ Bind/Bridge qua bộ nhớ (IPC thuần) │ │
│  └───────────────▲─────────────────────────────────────────────────────┘ │
│                  │ EventsOn / window.go.backend.App.*()                   │
│  ┌───────────────┴──────────────── Backend Go ────────────────────────┐ │
│  │                        Bridge API (app.go)                         │ │
│  │   GetAppState · ListVoices · Synthesize · ExportAudio · Player …   │ │
│  ├──────────────────────────── Job Orchestrator ──────────────────────┤ │
│  │  Smart Splitter → per-chunk synth → DSP chain → Session Store      │ │
│  ├────────────── Hybrid Engine Dispatcher (engine/hybrid.go) ─────────┤ │
│  │                                                                    │ │
│  │  ┌── Tầng 1: VieNeu Neural ─────────────────────────────────────┐  │ │
│  │  │ cgo ⇄ C ABI vieneu_tts.h (vieneu-tts-core.lib link tĩnh)     │  │ │
│  │  │  ├ llama.cpp/ggml  — Qwen3 semantic backbone                 │  │ │
│  │  │  ├ ONNX Runtime    — acoustic decoder + MOSS codec 48 kHz    │  │ │
│  │  │  └ voices_v3_turbo.json — 20 giọng preset gốc                │  │ │
│  │  └──────────────────────────────────────────────────────────────┘  │ │
│  │  ┌── Tầng 2: SAPI5 Ultra-Lite ──────────────────────────────────┐  │ │
│  │  │ COM IDispatch (go-ole) ⇄ ISpVoice hệ thống — zero model      │  │ │
│  │  └──────────────────────────────────────────────────────────────┘  │ │
│  ├──────────────────── DSP Suite (thuần Go, không cgo) ───────────────┤ │
│  │  WSOLA time-stretch · Pitch shifter · Gain+soft limiter            │ │
│  │  Smart splitter tiếng Việt · WAV RIFF writer · MP3 SHINE encoder   │ │
│  ├──────────── Audio Playback (winmm waveOut syscall thuần) ──────────┤ │
│  │  Streaming buffer ring · Pause/Resume/Stop · position events       │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
                     │ (tải 1 lần duy nhất lúc cài đặt)
                     ▼
   %LOCALAPPDATA%\HCStudio\
     ├── settings.json                (thiết lập người dùng)
     ├── models\vieneu-v3-turbo\      (trọng số neural, ~1 GB)
     └── exports\                     (mặc định xuất audio)
```

## 2. Nguyên tắc bất biến (Invariants)

| # | Nguyên tắc | Biện pháp đảm bảo |
|---|-----------|-------------------|
| 1 | Một file .exe duy nhất | Engine link tĩnh; frontend embed bằng `go:embed`; build.ps1 chỉ phát ra `dist\HCStudio.exe` |
| 2 | Không port/tường lửa | Wails Bind/Bridge IPC in-process; không dùng http server |
| 3 | Không cửa sổ CMD | `-ldflags "-H windowsgui -s -w"` |
| 4 | Offline tuyệt đối sau cài đặt | Downloader chỉ chạy khi người dùng bấm nút Tải mô hình |
| 5 | Máy cấu hình thấp vẫn chạy được | Tầng SAPI5 luôn sẵn sàng; tầng neural int8 RTF<1 CPU |
| 6 | Phát = Xuất file (WYSIWYH) | Cùng một pipeline DSP cho playback lẫn export |

## 3. Luồng dữ liệu tổng hợp (Synthesis Pipeline)

```
Text từ UI
  │ Synthesize(SynthRequest)
  ▼
JobMgr.CreateJob ──evt:job {state:splitting}
  ▼
SmartSplitter.SplitVietnamese(text, maxChars=384)
  · cắt tại ranh giới câu (. ! ? … \n), gộp câu ngắn, giữ nguyên [cười]…
  ▼
┌─ vòng lặp từng chunk (có thể hủy giữa chừng) ─────────────────────────┐
│ HybridDispatcher.Synthesize(chunk, voiceID)                           │
│   voice.Engine == neural ? VieneuDriver : SapiDriver                  │
│   evt:job {pct = chunksDone/N + subPct(1/N)}                          │
│   (neural: progress callback C ABI → channel → throttle ≥50 ms)       │
└───────────────────────────────────────────────────────────────────────┘
  ▼  concat float32 PCM @ 48 kHz (+ insert ~120 ms im lặng giữa câu)
DSP chain (pitch ≠ 0 → PitchShift; speed ≠ 1 → WSOLA; volume → Gain+Limiter)
  ▼
SessionStore.Put(jobID, PCM) ──evt:job {state:done}
  ├── AutoPlay → WinmmPlayer.Play(pcm) ──evt:play {pct, cursorMs}
  └── ExportAudio(jobID, format, path)
        wav  → dsp.WriteWav(path, pcm, sr)
        mp3  → shine-mp3 Encode → path  (float32→int16 trước khi encode)
```

## 4. Giao thức Bridge frontend ↔ backend

Toàn bộ phương thức trên struct `App` được Wails bind thành
`window.go.backend.App.<Method>` — lời gọi hàm trực tiếp trong bộ nhớ, kiểu dữ
liệu JSON-serialize, không socket nào được tạo.

### Methods (frontend gọi)

| Method | Dữ liệu vào | Kết quả | Ghi chú |
|--------|-------------|---------|---------|
| `GetAppState` | – | `{IsDarkWin, NeuralLinked, NeuralReady, MissingFiles, ModelDir, Version}` | hydrate lần đầu |
| `ListVoices` | – | `Voice[]` | catalog 20 giọng neural + giọng SAPI máy thật |
| `Synthesize(req)` | `{Text,VoiceID,EngineOverride,Speed,Pitch,Volume,AutoPlay}` | jobID string | chạy async nền |
| `PlayJob` / `PauseToggle` / `StopAll` | jobID | error/null | điều khiển transport |
| `ExportAudio(jobID, format, path)` | path từ `PickSavePath` | error/null | wav hoặc mp3 |
| `PickSavePath(defaultName)` | tên mặc định | đường dẫn | wails SaveFileDialog |
| `CancelJob(jobID)` | jobID | – | dừng synth an toàn |
| `DownloadNeuralAssets()` | – | – | wizard tải model + resume |
| `CancelModelDownload()` | – | – | |
| `SaveSettings(settings)` | đối tượng settings | – | ghi %APPDATA% |
| `OpenModelsFolder` / `OpenExportsFolder` | – | – | explorer.exe |
| `WindowAction(cmd)` | min/max/close | – | frameless traffic-lights |

### Events (backend phát)

| Event | Payload | Ý nghĩa |
|-------|---------|---------|
| `hcstudio:job` | `{id,state,pct,stage,msg,etaSec,durationSec}` | mỗi bước synthesis |
| `hcstudio:play` | `{jobID,pct,cursorMs,totalMs,playing}` | vị trí phát thanh |
| `hcstudio:modeldl` | `{pct,currentFile,fileIdx,totalFiles,bytesDone,bytesTotal,state}` | tải model |
| `hcstudio:toast` | `{level,title,message}` | thông báo hệ thống |

Preview trình duyệt (mở thẳng `frontend/dist/index.html`) dùng **MockBackend**
trong `bridge.js`: cùng hợp đồng Promise/event, mô phỏng synthesis + WebAudio
beep, để thiết kế/chốt UI không cần compile Go.

## 5. Hai tầng engine chi tiết

### Tầng 1 — VieNeu v3 Turbo (chất lượng chủ lực)

- Nguồn logic: **pnnbao97/VieNeu-TTS.cpp** (MIT) — snapshot pinned commit, link
  tĩnh (`VIENEU_STATIC`) vào binary Go qua lớp cgo mỏng
  (`internal/engine/vienneu/driver_cgo.go`, tag build `vieneu`).
- Trọng số: pack chuẩn profile `vieneu-v3-onnx` gồm 12 tệp nằm rải trên
  HuggingFace (`config/tokenizer`, prefill/decode_step/acoustic int8, MOSS codec
  decode+encode, `voices_v3_turbo.json`) — manifest cố định ngay trong mã nguồn
  (`assets_manifest.go`) kèm URL gốc và thư mục đích.
- Tham số suy luận khớp khuyến nghị tác giả: `temperature=0.8, top_k=25,
  top_p=0.95, max_chars=384/chunk, threads=số nhân lý`.
- 20 giọng preset nguyên bản: id đúng chuỗi tiếng Việt trong
  `voices_v3_turbo.json` (`Adam, Phạm Tuyên, Minh Đức, Thanh Bình… Kim Thanh`),
  metadata hiển thị (giới tính/miền/phong cách) nhúng tĩnh trong catalog.
- Âm lượng/Pitch do DSP xử phía Go; Speed native của engine cố định nên được
  nắn lại bằng WSOLA ở tầng chung — một công thức cho cả hai tầng engine.

### Tầng 2 — SAPI5 Ultra-Lite (bảo hiểm cấu hình thấp)

- Enumerate `ISpVoice::GetVoices` (ưu tiên vi-VN), tổng hợp tuần tự tối giản.
- Rate native map từ slider Speed; Volume do DSP; hoạt động dù máy không có
  bundle model — chính là "Ultra-Lite mode" trong dropdown engine.
- Chỉ dùng Pure-COM automation (go-ole IDispatch): không DLL thứ ba nào.

## 6. Chiến lược single-exe & build matrix

| Kịch bản build | Lệnh | Nội dung exe | Thời gian |
|----------------|------|--------------|-----------|
| Lite | `.\scripts\build.ps1` | SAPI5-only + UI đầy đủ (~18–25 MB) | < 2 phút |
| Full | `.\scripts\build.ps1 -Full` | + static core VieNeu + ONNX Runtime static (~60–90 MB) | 30–60 phút lần đầu (build ORT từ nguồn), sau đó cache |

Cả hai đều ra **đúng một tệp HCStudio.exe** (ngoài WebView2 vốn là runtime hệ
thống của Windows). Trọng số model KHÔNG nằm trong exe — đây là dữ liệu, được
app quản lý theo luồng Downloader riêng.

## 7. Mô hình luồng & an toàn đồng thời

- Mỗi job một goroutine; hủy qua `context.Context` kiểm tra giữa các chunk.
- Engine neural bị serialize bởi một `sync.Mutex` (model não + KV cache dùng
  chung); jobs xếp hàng FIFO nhỏ.
- WinmmPlayer sở hữu lock riêng; Stop reset toàn buffer trước khi thoát job.
- Progress events đi qua 1 goroutine publisher duy nhất chống race và throttle.

## 8. Ma trận rủi ro đã phản biện

| Rủi ro | Giảm thiểu |
|--------|-----------|
| MinGW không hỗ trợ delayload onnxruntime.dll | `-Full` build ORT **static lib** trước rồi mới link exe — loại hoàn toàn runtime DLL khỏi phân phối |
| Thiếu WebView2 trên máy cũ | Windows 10/11 hiện hành đã cặp kè; flag `-webview2 embed` nhúng bootstrapper dự phòng |
| Model download đứt giữa chừng | Resume HTTP Range từng file + verify Content-Length + xác thực zip npz nhẹ |
| Tràn RAM khi văn bản cực dài | Xử lý theo chunk, session chỉ lưu PCM kết quả, giới hạn mềm 200k ký tự có cảnh báo UI |
| Người dùng clone giọng phi phép | App chỉ bật preset voice official; tính năng clone đặt chế độ trách nhiệm rõ ràng (roadmap) |
