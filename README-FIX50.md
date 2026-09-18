# FIX50 — CLONE GIỌNG ĐẲNG CẤP SPACE + GÓI TRỌNG SỐ TRỰC TIẾP 14/14

Hai mục tiêu theo góp ý của người chủ:

1. **Đường clone giọng đủ 3 lớp như Space demo HF** — thêm `denoiser.onnx`
   + `speaker_encoder.onnx` (trước FIX50 clone chỉ có MOSS ref-codes, thiếu
   denoise và thiếu speaker embedding → giọng nhân bản sai màu, hay bỏ chạy
   EOS khi audio mẫu ồn).
2. **Gói trọng số trực tiếp 14/14** — không bắt người dùng tải từng file từ
   HF: 1 file ZIP duy nhất (kèm bản FIX50 này) nhập một lần là máy offline
   vĩnh viễn. 12/12 gói cũ + 2 gói mới của clone = **14/14, 636.749.792 byte
   ≈ 607 MB**.

## 1. Bằng chứng kiểm chứng trước khi vá (2026-09-18)

| Kiểm chứng | Kết quả |
|---|---|
| `denoiser.onnx` @pin 8b7e9cff | 42.661.414 B, sha256 `b7621953…` == LFS oid HF |
| `speaker_encoder.onnx` @pin 8b7e9cff | 28.303.423 B, sha256 `a6ac6a63…` == LFS oid HF |
| Graph denoiser (parse wire ONNX) | in `mag/cos/sin` (b,841,t) → out `sep_mag/sep_cos/sep_sin` (b,841,t); 841 = 1680/2+1 |
| Graph speaker encoder | in `input` (b,T,80) → out `output` (b,192); `xvector.dense.linear.weight = [192,1024,1]` → **xuất thẳng 192-d** |
| `heads.npz` update | `xvec_w (768,192)` f32 STORED + `xvec_b/ln_w/ln_b/ln_eps` — khớp máy anchor FIX49 (Linear 192→768 + LN) |
| `config.json` update tải về | byte-identical với `config_update.json` lưu từ Task 61 (sha256 `17d89d41…`) |
| backbone `onnx_update/` | LFS oid `c7c07219…` ≠ `onnx/` cũ `6f28d660…` — xác nhận x-linked-etag @pin |
| Pipeline Python (vieneu 3.6.3) | `_load_mono` mean-downmix → trim 8s → `denoiser.denoise` (@44.1k) → `speaker_encoder.embed` (fbank 80 @16k mean-norm) → `_encode_ref_wav` resample 48k dup-stereo → MOSS |

## 2. Thay đổi trong core C++ @cc037cf (nhúng base64 vào prepare-vieneu.ps1)

**File mới `vieneu_v3_onnx_clone.cpp`** (~25 KB) — khối DSP thuần đã được
verify số học bằng harness độc lập (so numpy):

- FFT radix-2 + **Bluestein chirp-z** cho N=1680 (không phải lũy thừa 2):
  rfft/irfft sai số 9.4e-13 so với `numpy.fft`.
- **STFT 1680/420** hann-periodic, center reflect-pad, drop last frame — sai
  số 3.2e-08 so với mirror numpy của `_stft`.
- **iSTFT** WOLA window² + replicate last frame — full-range parity 2.7e-08
  với simulation numpy của `_istft` (kể cả vùng đuôi mà bản Python cũng
  corrupt — giữ nguyên parity, không "sửa hơn" bản tham chiếu).
- **Resampler sinc** Hann-window 24 zero-crossings (thay soxr): tone giữ
  nguyên biên độ/tần số, tone 10 kHz trên cutoff bị loại hoàn toàn
  (anti-alias đúng).
- **Kaldi fbank 80-d @16k**: povey (symmetric), snip_edges, dither 0,
  remove_dc, preemph 0.97, mel 80 bins (low 20 Hz, high = nyquist,
  scale 1127·ln(1+f/700)), log(max(·, FLT_EPSILON)), mean-norm per column —
  diff 0.0000 với reimplementation numpy độc lập.

**Engine methods**: `load_clone_assets` (auto-discover
`<model_dir>/denoiser.onnx|speaker_encoder.onnx`, fallback `<onnx_dir>/`),
`clone_denoise` (chuẩn hoá abs_max → pad 441 → STFT → ONNX → iSTFT), 
`clone_speaker_embedding` (resample 16k → fbank → ONNX → 192-d).

**`encode_reference_audio` viết lại** (audio.cpp): mean-downmix mono trước →
trim 8s → denoise (best-effort, lỗi thì giữ clip gốc — sàn FIX46) → speaker
embedding → `compute_speaker_anchor` (máy FIX49) → resample 48k + dup stereo
→ MOSS codes. **Không đổi ABI** — `vieneu_tts.h` nguyên vẹn.

**Tính lỗi thời an toàn**: thiếu/broken 2 file weights → engine khởi động
vẫn OK, clone rơi về codes-only (đúng hành vi FIX46); preset synthesis không
bị ảnh hưởng.

## 3. Go / app

- `assets_manifest.go`: +2 entries (`denoiser.onnx`, `speaker_encoder.onnx`
  ở root model dir, pin `hfV3Base`, SizeHint chuẩn) — tổng manifest **14
  file / 636.749.792 B**. Downloader + ImportOfflinePackage tự ăn theo
  (manifest-driven).
- Texts 12→14 (dialog import, wizard size "≈ 607 MB · 14 file").
- `driver_cgo.go` **không đổi** (auto-discovery trong core).

## 4. Gói trọng số trực tiếp 14/14

File kèm: `HCStudio-v5-FIX50-weights-full-14of14.zip` (366 MB nén;
bên trong 636.749.792 byte đúng chuẩn manifest, kèm `MANIFEST.txt` liệt kê
size + sha256 từng file). 2 cách nạp:

1. **Một cú nhấp**: app → wizard → **"Nhập gói ZIP (offline)"** → chọn ZIP
   (FIX48 import: khớp tên base 14 file + kiểm tra SizeHint byte-level,
   TỪ CHỐI file sai dữ liệu).
2. **Gỡ tay**: giải nén nội dung ZIP vào
   `%AppData%\HCStudio\models\vieneu-v3-turbo\` (giữ cấu trúc thư mục).

Sau khi nạp xong, app **không còn cần bất kỳ lượt tải nào** — chủ quyền
nguồn theo chuẩn FIX48 (mirror `HCSTUDIO_ASSET_MIRROR` vẫn hoạt động nếu
muốn tự dựng nguồn phát).

## 5. Cách cài FIX50 (code)

1. Giải nén `HCStudio-v5-FIX50-clone-preclean-weights14.zip` đè lên repo.
2. `git add -A && git commit && git push` → CI build (~2 phút thêm cho clone.cpp).
3. Tải app mới về, chạy — lần đầu có thể nhập gói 14/14 (mục 4) hoặc để app
   tự tải thêm ~71 MB (2 file mới; 12 file cũ nếu có rồi sẽ skip).

## 6. Ca nghiệm thu

1. Build CI xanh; BUILD-INFO không đổi toolchain.
2. Trỏ speaker encoder/denoiser vào model dir → wizard hiện đủ trạng thái
   sẵn sàng (14 file).
3. Clone với audio mẫu sạch 3-5 s → giọng ra **gần Space demo hơn rõ rệt**
   (anchor 192-d đúng người + ref codes sạch).
4. Clone với audio mẫu ồn (quạt/fan) → giọng ra ổn định, KHÔNG bỏ chạy EOS
   (denoiser đưa x-vector về miền distribution huấn luyện).
5. Đổi audio mẫu stereo → vẫn hoạt động (mono mean-downmix như Space).
6. Audio mẫu > 8 s → tự cắt còn 8 s.
7. Đổi tên/xoá `denoiser.onnx` → app vẫn chạy; clone codes-only; không crash.
8. Nhập gói ZIP 14/14 → report `imported=14, assetsReady=true`.
9. Nhập ZIP thiếu file / sai size → bị từ chối đúng file, weights tốt giữ nguyên.
10. Synthesis preset (25 giọng) → bất biến so với FIX49 (A/B như cũ).

## 7. Rollback

Đè lại cây bằng `HCStudio-v5-FIX49-weights-update-speaker.zip`. Weights đã
tải không cần xoá: manifest FIX50 chỉ THÊM file, FIX49 đọc đủ bộ cũ.
