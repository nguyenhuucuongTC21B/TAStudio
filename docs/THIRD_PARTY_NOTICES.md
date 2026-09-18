# Thông báo thành phần bên thứ ba (Third-Party Notices)

HCStudio v5.0 xây dựng trên vai của những người khổng lồ mở. Khi phân phối
lại binary hoặc fork dự án, VUI LÒNG giữ nguyên tệp này.

## 1. VieNeu-TTS v3 Turbo — mô hình & assets giọng đọc

- Nguồn: https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo
- Giấy phép: **Apache License 2.0**
- Tác giả: Phạm Nguyễn Ngọc Bảo (pnnbao97)
- Phạm vi: trọng số mô hình, tokenizer, cấu hình, và *bundled preset-voice
  assets* (`voices_v3_turbo.json` gồm speaker embeddings + reference codes).
  Audio sinh ra từ 20 giọng preset này **được phép dùng thương mại**, theo FAQ
  chính thức trên model card.

## 2. VieNeu-TTS.cpp — engine suy luận C++

- Nguồn: https://github.com/pnnbao97/VieNeu-TTS.cpp
- Giấy phép: **MIT License**
- Chức năng trong HCStudio: `vieneu-tts-core` static lib chứa toàn bộ pipeline
  chữ→âm (G2P, backbone llama.cpp, acoustic, MOSS codec) gọi qua C ABI.

## 3. VieNeu-TTS (tham chiếu Python)

- Nguồn: https://github.com/pnnbao97/VieNeu-TTS
- Giấy phép: xem repository gốc; HCStudio chỉ tham chiếu kiến trúc pipeline và
  dùng file dữ liệu `voices_v3_turbo.json` được phân phối cùng model (mục 1).

## 4. Thành phần đi kèm engine (giữ nguyên license khi redistribute)

| Thành phần | License |
|---|---|
| llama.cpp / ggml | MIT |
| ONNX Runtime | MIT |
| MOSS-Audio-Tokenizer-Nano (+ONNX export) | Apache-2.0 |
| sea-g2p (phonemizer) | xem repo tác giả |

## 5. Thư viện Go

| Thư viện | License |
|---|---|
| github.com/wailsapp/wails/v2 | MIT |
| github.com/go-ole/go-ole | MIT |
| github.com/braheezy/shine-mp3 (SHINE port) | LGPL-2.1 ghi nhận tác giả shine gốc Gabriel Bouvigne / toots |
| golang.org/x/sys | BSD-3 |

## 6. Frontend

Toàn bộ CSS/JS trong `frontend/dist` do dự án tự viết, không CDN nào tham gia.
Tailwind-style utility classes là tên lớp tự khai bảo trong `app.css`.

---

HCStudio v5.0 mã nguồn ứng dụng phát hành theo **Apache-2.0** trừ khi quy định
riêng ở mục trên. Attribution "VieNeu-TTS by pnnbao97" vui lòng được giữ trong:
About page, README, và bản phân phối nhị phân (file này là đủ).
