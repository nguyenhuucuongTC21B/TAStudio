# CHANGES RUN #32 - Fix CI: CMake generator Visual Studio khong ton tai tren runner

## Trieu chung (log CI user gui)

    ==> Xac dinh compiler
    CMake: C:\Program Files\CMake\bin\cmake.exe
    ==> Bien dich vieneu-tts-core (static)
    CMake Error at CMakeLists.txt:2 (project):
      Generator
        Visual Studio 17 2022
      could not find any instance of Visual Studio.
    [XX] CMake configure that bai.

## Nguyen nhan goc

1. scripts/prepare-vieneu.ps1 (ban cu) hardcode `-G "Visual Studio 17 2022"`
   cho CMake. Runner CI khong co instance Visual Studio nao dung duoc
   (vswhere tra ve rong) => configure chet ngay tu dong 1 cua CMakeLists.

2. Sau sicung khong the di theo huong MSVC: buoc link cgo cua Go dung ld
   cua MinGW (CC = gcc - xem build.ps1 PATCH run #11), ma ld khong doc
   duoc archive MSVC (.lib) => 82 undefined references (bai hoc run #11).
   build.ps1 v29 cung DA YEU CAU artifact `native-build\vieneu-tts-core.a`
   (GNU .a) va truyen `-Gcc <gcc.exe>` vao prepare. Ban prepare trong repo
   chua tuan thu contract nay.

## Fix (1 file duy nhat: scripts/prepare-vieneu.ps1)

- Chap nhan tham so `-Gcc` ma build.ps1 truyen vao (tu resolve giong
  Resolve-MingwCc neu chay doc lap). Bat buoc co g++.exe canh gcc.
- CMake configure bang generator Ninja (co san tren GitHub runner);
  du phong "MinGW Makefiles" voi mingw32-make/gmake/make.
- `-DCMAKE_C_COMPILER/-DCMAKE_CXX_COMPILER` tro vao GCC/g++ do build.ps1
  chon => ABI dong nhat voi CC cua cgo o buoc go build.
- Build target `vieneu-tts-core` (ggml/llama duoc build nhu dependency).
- Thu thap TOAN BO archive .a trong build tree (ggml/ggml-base/ggml-cpu/
  llama... tuy phien ban CMake, khong phu thuoc ten/vi tri cu the),
  loai tru CMakeFiles va .dll.a; copy core sang
  `native-build\vieneu-tts-core.a` (ten chinh xac ma build.ps1 doi).
- Import lib cho ONNX Runtime: objdump -p quet export -> onnxruntime.def
  -> dlltool ra `native-build\libonnxruntime.a`. Fallback 3 tang:
  objdump -> PE parser thuan PowerShell -> dung lai onnxruntime.lib
  (ld doc duoc short import lib; CGO_LDFLAGS_ALLOW cua build.ps1 da cho
  phep .lib).
- link-libs.txt (dinh dang build.ps1 v29 parse duoc): moi dong la 1 duong
  dan .a, sau do cac flag: -fopenmp -lstdc++ -ladvapi32 -lole32
  -loleaut32 -luser32 -lws2_32 -lbcrypt. Toan bo duoc boc trong
  -Wl,--start-group/--end-group boi build.ps1 (run #12).
- Copy onnxruntime.dll -> native-build\ (build.ps1 ship vao dist\).
- Tu dong chat-luan an toan cua du an: 0 backtick (byte 0x60), 0 ky tu
  non-ASCII (kiem tra bang script truoc khi dong goi).

## Khong doi gi khac

- build.ps1 (v29), driver_cgo.go, workflow, frontend: GIU NGUYEN 100%.
- Commit pinned VieNeu-TTS.cpp cc037cf + submodule khong doi.
- ONNX Runtime 1.20.1 khong doi.

## Cach ap dung tren may user (khong the sai thut le)

Chi thay 1 file: scripts\prepare-vieneu.ps1 (lay noi dung day du tu
message chat hoac tu goi zip FIX32). Khong file nao khac can sua.

## Kiem dinh ma user nen lam sau khi CI chay lai

1. Log CI phai thay: "Generator : Ninja (...)" hoac "MinGW Makefiles",
   "GCC: C:\...\gcc.exe", roi cmake configure + build thanh cong.
2. Log thay "Thu thap cac archive .a" voi danh sach ggml/llama.
3. Log thay "[OK] dlltool -> ...libonnxruntime.a" HOAC dong CANH BAO dung
   onnxruntime.lib (ca hai deu hop le).
4. Neu rot o buoc khac (C++ compile llama.cpp, link cgo, wails): gui log,
   KHONG doan doan.
