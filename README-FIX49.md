# FIX49 — NÂNG WEIGHTS `onnx_update/` (kiến trúc vieneu_v3 + speaker embedding 192)

Mục tiêu: thu hẹp **khoảng cách #2** với Space demo HF (đã chẩn đoán ở Task 62):
app đang chạy weights `onnx/` (arch cũ `vieneu_v3_turbo`, acoustic 2 layer, KHÔNG
speaker embedding). Space demo chạy `onnx_update/` (arch `vieneu_v3`, acoustic
1 layer, **speaker_embedding_dim 192**, 8 emotion tokens + 10 style tokens).

## 1. Bằng chứng kiểm chứng trước khi vá (2026-09-18)

| Kiểm chứng | Kết quả |
|---|---|
| Tree API `onnx_update/` @pin 8b7e9cff | Đủ 7 file: config 2.152 B, tokenizer 22.320 B, prefill 324.499 B, decode 306.134 B, acoustic 7.207.223 B, heads.npz 52.219.622 B, backbone_shared.data 415.319.040 B |
| HEAD Content-Length từng file | KHỚP 100% SizeHint điền vào manifest |
| `config.json` update vs bằng chứng đã lưu (fix46_build) | byte-identical (sha256 trùng) |
| prefill + decode_step | LFS oid TRÙNG `onnx/` — graph backbone KHÔNG đổi |
| acoustic + heads.npz + backbone_shared.data | oid KHÁC — weights mới thật |
| heads.npz update | 7 entry, TOÀN BỘ STORED (loader C++ đọc được), đủ `xvec_w (768×192)`, `xvec_b`, `xvec_ln_w/b`, `xvec_ln_eps` |
| acoustic update IO | 4in/3out = `token_emb, position_ids, past_k_0, past_v_0` → `hidden, present_k_0, present_v_0` (đúng pattern, ít KV hơn turbo) |
| Voices JSON @fa2b1afa (25 giọng) | MỖI preset CÓ `speaker_emb` 192 float — điều kiện sống còn của arch update: ĐÁP ỨNG |
| Tham chiếu triển khai | `onnx_runtime_lite.py` trong wheel vieneu 3.6.3 (Space chạy đường này) — mặc định `onnx_subfolder="onnx_update"` |

## 2. Ba thay đổi trong core C++ @cc037cf (file nhúng base64 vào prepare-vieneu.ps1)

### 2.1 Parameterize acoustic theo `local_num_hidden_layers` (trước đây hard-code 6in/5out)
`acoustic_frame_onnx`: expected IO = `2 + 2·L` in / `1 + 2·L` out với
`L = config_.local_num_hidden_layers` (turbo L=2 → như cũ; update L=1 → 4in/3out).
KV cache dùng vector động (member `acoustic_pk_/acoustic_pv_`), hết array cố định.

### 2.2 Speaker anchor (Linear + LayerNorm) — mirror `_speaker_anchor()` của wheel
- `heads.npz`: nạp thêm `xvec_w/xvec_b/xvec_ln_w/xvec_ln_b/xvec_ln_eps` (optional —
  turbo npz thiếu key → `has_xvec_proj_=false`, hành vi cũ giữ nguyên).
- `voices JSON`: parse `speaker_emb` (192 float) vào `VoicePreset`.
- `compute_speaker_anchor()`: `v = spk·Wᵀ + b` → LayerNorm (population var, ddof=0
  đúng như np.var) → `v·ln_w + ln_b`.
- Áp vào **MỌI row** của backbone: cả prompt (`embed_rows`) lẫn từng frame decode
  (slot embedding) — khớp `_embed_rows(rows, anchor)` của wheel.

### 2.3 Head token = style token
Update arch mở đầu prompt bằng `default_style_token_id` (16 = *tự nhiên*, theo
`_resolve_style_id()` của wheel — luôn tự nhiên, bỏ qua emotion). Turbo config
không có key này → fallback `emotion_0` như cũ. Preset có `reserved_id` vẫn ưu tiên.

### Tương thích ngược
Cả 3 thay đổi đều vô hại với weights `onnx/` cũ (L=2, không xvec, không style):
nếu cuộn weights về, engine vẫn chạy đúng như FIX48.

## 3. Thay đổi phía Go app

1. `assets_manifest.go`: 6 file VieNeu đổi URL sang `onnx_update/` + SizeHint mới;
   **DestRel chuyển sang thư mục MỚI `update/`** — LÝ DO: `backbone_shared.data`
   CÙNG size 415.319.040 B nhưng KHÁC nội dung (LFS oid `6f28d660…` ≠ `c7c07219…`);
   nếu giữ path `onnx/`, skip-theo-size của downloader sẽ GIỮ NHẦM weights cũ.
   Voices + codec giữ nguyên (FIX46/FIX48).
2. `ResolveModelPaths`: `OnnxDir/Config/Tokenize` trỏ vào `update/`; codec + voices
   không đổi. Thư mục `onnx/` cũ còn lại trên disk làm rollback offline.
3. Tổng tải cho máy đã cài cũ: ≈ **475 MB** (backbone 415 + heads 52.2 + acoustic
   7.2 + 0.6 graph + config/tokenizer).

## 4. Kiểm định đã chạy (mạnh hơn mọi FIX trước)

| Kiểm định | Kết quả |
|---|---|
| 12 replacement C++ — mỗi cái count==1 trên nguồn pin | PASS |
| **g++ -fsyntax-only THẬT** với ORT 1.20.1 headers + nlohmann + llama.h trên 4 file .cpp đã vá (+2 file phụ thuộc chưa vá) | 6/6 SYNTAX-OK |
| Bắt được 2 bug compile-thật TRƯỚC CI: `vector.assign` trên move-only `Ort::Value` (đổi sang `emplace_back(nullptr)`), và FIX49 đè mất patch CUDA run#44 (tiền-applied CUDA removal vào file nhúng) | ĐÃ SỬA |
| Round-trip ps1: giải base64 từ chính prepare-vieneu.ps1 cuối = byte-identical patched_core, marker `PATCH FIX49` đủ 5/5 | IDENTICAL |
| prepare-vieneu.ps1 ASCII-only, 0 backtick | PASS (147.261 B) |
| gofmt + go vet (engine, vienneu, root) + go test (dsp, textnorm) | PASS |

## 5. Nghiệm thu trên máy bạn (sau khi CI xanh)

1. BUILD-INFO.txt: như FIX47 (Sea-g2p : ON) — không có dòng mới.
2. Bấm "Tải mô hình": tải ≈ 475 MB vào `...\HCStudio\models\vieneu-v3-turbo\update\`.
3. Đọc thử từng giọng: **giống Space demo hơn rõ rệt** (weights mới + speaker
   anchor + style token tự nhiên) — đây là cặp so sánh công bằng đầu tiên vì
   FIX47 đã đồng bộ lớp phonemizer (sea-g2p).
4. Nhân bản giọng: ref 3–5s → giọng giống hơn (anchor chỉ dùng cho preset;
   clone-path vẫn dùng ref codes — nâng cấp denoiser/speaker-encoder cho clone
   là FIX50).
5. Vẫn crash/khác thường → hcstudio.log + BUILD-INFO như thường lệ.
6. Rollback weights: nạp FIX48 zip (manifest trỏ về `onnx/` cũ vẫn còn trên disk).

## 6. Còn lại sau FIX49 (lộ trình chất lượng)

- Khoảng cách #3 (clone): denoiser.onnx + speaker_encoder.onnx cho đường clone → FIX50.
- Khoảng cách #4 (nhỏ): frame_cap theo phonemes + babble guard + gap phân loại
  câu/đoạn (đã có trong wheel) → gộp FIX50 hoặc FIX51.
- int8 (`onnx_int8/`): cùng arch với update (L=1) — sau khi FIX49 xanh chỉ còn
  A/B chất lượng, không cần patch core nữa.
