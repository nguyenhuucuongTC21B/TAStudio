#Requires -Version 5.1
<#
.SYNOPSIS
    HCStudio v5.0 - Chuan bi tang neural: clone + build static lib
    vieneu-tts-core tu repo pnnbao97/VieNeu-TTS.cpp (MIT).

.DESCRIPTION
    San pham ma script nay sinh ra cho buoc "go build -tags vieneu":
        native-build\vieneu-tts-core.a   - static runtime GNU .a (gom llama.cpp/ggml)
        native-build\link-libs.txt       - link manifest cho build.ps1 (CGO_LDFLAGS)
        native-build\onnxruntime.dll     - runtime ORT (build.ps1 copy vao dist)
        native-build\libonnxruntime.a    - import lib GNU cho ORT (dlltool tu .def)
        native-build\vieneu-tts-api.a    - C API wrapper (vieneu_tts.cpp) cho
                                           cgo - run #39 + #40

    CONTRACT VOI build.ps1 v29 (bat buoc):
        - build.ps1 goi:  prepare-vieneu.ps1 -Gcc <path\gcc.exe> ...
        - build.ps1 doi:  native-build\vieneu-tts-core.a PHAI ton tai (khong
          chap .lib MSVC) vi buoc link cgo dung ld cua MinGW.

    PATCH run #32 (cham dut loi generator Visual Studio):
        - Symptom run truoc: CMake bao "Generator Visual Studio 17 2022
          could not find any instance of Visual Studio" tren runner CI.
        - Root cause: script cu hardcode -G "Visual Studio 17 2022" cho khi
          runner khong co VS. Ngoai ra MSVC .lib cung KHONG tuong thich voi
          ld mingw o buoc link cgo (bai hoc run #11: 82 undefined references).
        - Fix: build 100% bang GCC MinGW (tham so -Gcc do build.ps1 resolve
          va truyen vao) + generator Ninja (du phong MinGW Makefiles).
          Ket qua: moi archive la .a GNU, ld doc 100%, ABI dong nhat voi CC
          cua cgo. => RUN #32 CONFIRMED: configure OK, 10/215 target OK.

    PATCH run #33 (cham dut loi compile ggml-cpu.c tren header MinGW cu):
        - Symptom run #32: Ninja + GCC configure OK, build den file 8/215
          ggml-cpu.c thi bao:
            "unknown type name 'THREAD_POWER_THROTTLING_STATE'"
            "'THREAD_POWER_THROTTLING_CURRENT_VERSION' undeclared"
            "'THREAD_POWER_THROTTLING_EXECUTION_SPEED' undeclared"
        - Root cause: llama.cpp @ ebd048f dung API Power Throttling cua
          Windows SDK 10.0.17763+ trong ggml_thread_apply_priority().
          Header mingw-w64 di kem Strawberry gcc (va cac ban mingw-w64 cu)
          CHUA dinh nghia type + 2 const THREAD_POWER_THROTTLING_*.
          Bang chung: gcc bao loi nhung GOI Y "did you mean
          PROCESS_POWER_THROTTLING_..." -> ban PROCESS_* CO san trong cung
          header va GIONG HET ve layout (Version/ControlMask/StateMask,
          DWORD/ULONG 32-bit) va gia tri (CURRENT_VERSION=1,
          EXECUTION_SPEED=0x1) -> alias 100% tuong duong, khong mat chuc nang.
        - Fix: truyen 3 define anh xa THREAD_* -> PROCESS_* cho TOAN BO
          build tree qua CMAKE_C_FLAGS + CMAKE_CXX_FLAGS. Khong sua file
          nguon llama.cpp, khong phu thuoc phien ban header (neu header moi
          da co THREAD_* thi alias van hop le vi 2 ban identical).
          => RUN #33 CONFIRMED: ggml-cpu.c (8/215) compile OK.

    PATCH run #34 (cham dut loi SAL annotation trong header ONNX Runtime):
        - Symptom run #33: 3 file .cpp cua vieneu (neucodec_onnx,
          vieneu_v3_onnx_engine, vieneu) chet khi include
          onnxruntime_c_api.h:
            "'_Frees_ptr_opt_' has not been declared" (87 lan)
          + hang loat loi phu: "expected ',' or '...'",
            "invalid conversion from 'OrtX*' to 'int'",
            "redeclaration of 'int* OrtCustomOp::output_index'".
        - Root cause: _Frees_ptr_opt_ la SAL annotation cua MSVC (sal.h
          Windows SDK 2015+). Header mingw-w64 di kem Strawberry cu khong
          dinh nghia macro nay. Khi macro chua co, gcc suy dien tham so
          dang sau thanh 'int' -> struct OrtApi/OrtCustomOp sai type ->
          dong loi phu tron log. Bang chung: 100% loi "has not been
          declared" trong log deu la DUY NHAT _Frees_ptr_opt_ (khong co
          SAL macro nao khac thieu) -> tat ca loi khac chi la he qua.
        - Fix: define _Frees_ptr_opt_ RONG (no-op) qua CMAKE_C_FLAGS +
          CMAKE_CXX_FLAGS. Dung dung ban chat: SAL annotation chi la ghi
          chu cho MSVC code analysis, khong co y nghia runtime, nen
          dinh nghia rong la chinh xac 100%. Khong sua file header trong
          ORT SDK (giu SDK nguyen ven, khong phu thuoc phien ban).
          => RUN #34 CONFIRMED: 214/215 target OK, chi con 1 file.

    PATCH run #35 (nang ONNX Runtime SDK 1.20.1 -> 1.24.4 theo CI tac gia):
        - Symptom run #34: DUY NHAT con 1 file loi:
            vieneu_v3_onnx_engine.cpp:117
            "error: 'CUDAProviderOptions' is not a member of 'Ort'"
          (neucodec_onnx.cpp + vieneu.cpp DA compile OK voi fix #34).
        - Root cause: KHONG phai loi MinGW. Source Vieneu @ cc037cf dung
          Ort::CUDAProviderOptions (co .Update() + AppendExecutionProvider_
          CUDA_V2) - struct nay KHONG ton tai trong onnxruntime_cxx_api.h
          cua 1.18.1/1.19.2/1.20.1 (da kiem tra ca 3). Nhung CI chinh thuc
          cua tac gia (.github/workflows/release.yml) dinh
          ORT_VERSION: "1.24.4" va build XANH voi chinh SDK do: header
          v1.24.4 co "struct CUDAProviderOptions : detail::Base<OrtCUDA
          ProviderOptionsV2>" (dong 876). Vieneu duoc viet va kiem thu
          voi ORT 1.24.4 -> ta phai dung dung phien ban do.
        - Fix: doi mac dinh OnnxRuntimeVersion 1.20.1 -> 1.24.4. Layout
          zip giong het (ort_sdk\onnxruntime-win-x64-1.24.4\lib\onnxruntime
          .lib) - CI tac gia cung extract dung nhu vay. SAL token cua
          1.24.4 giong 1.20.1 (chi _Frees_ptr_opt_ thieu - da co define
          run #34). Nhanh CUDA chi chay khi env VIENEU_ORT_EP=cuda - app
          HCStudio dung CPU nen khong bao gio cham den, nhung phai compile
          duoc day du.

    PATCH run #37 (shim <cstdint> cho GCC 13.2 - MinGW libstdc++ chat hon MSVC):
        - Symptom run sau #36 (ORT da dung 1.24.4 - engine CUDA OK o
          [194/215], 201/215 target xanh): DUY NHAT con 1 file loi moi:
            src/vieneu/v3_native/v3_native_assets.cpp
            v3_native_assets.h:10 "'int64_t' was not declared in this
            scope" tai "std::vector<int64_t> shape;" + hang loat loi phu
            (push_back/size/[..] "non-class type int" = GCC error
            recovery khi template argument invalid).
        - Root cause: v3_native_assets.h @ cc037cf chi include
          <string>/<vector>/<unordered_map>/v3_native_config.h NHUNG
          dung int64_t ma KHONG #include <cstdint>; file .cpp dung ca
          uint8_t/uint16_t/uint32_t (cung thuoc <cstdint>). MSVC STL cua
          tac gia keo khai bao nay gian tiep nen build XANH; libstdc++
          cua GCC 13.2 MinGW KHONG keo - va chinh gcc chi dung remedy:
          "note: 'int64_t' is defined in header '<cstdint>'".
        - Fix: force-include mot shim header chuan (chi chua
          #include <cstdint> + <cstddef>) vao MOI C++ TU qua
          "-include <shim>" trong CMAKE_CXX_FLAGS - cung co che voi
          define run #33/#34. Khong sua file nguon thu 3. Shim chi THEM
          khai bao chuan ma header dung le phai tu co: file hop le
          khong anh huong, file thieu include duoc chua. Toan bo C++ TU
          con lai cua build tree (205-215) cung duoc an toan truoc loi
          cung loai. C flags giu nguyen (file .c khong cham vao).

    PATCH run #39 (C API cho cgo: -DVIENEU_STATIC + vieneu-tts-api.a):
        - Symptom run #38: link cgo chet voi 8 undefined reference dang
          "__imp_vieneu_*" (cac ham C API khai bao trong vieneu_tts.h ma
          driver_cgo.go goi: init/list_voices/synthesize/...).
        - Root cause (2 lop):
          (1) CGO_CFLAGS thieu -DVIENEU_STATIC => khi driver_cgo.go
              include vieneu_tts.h, VIENEU_API khai bao dang dllimport
              => moi cuoc goi tro qua stub __imp_vieneu_* chi ton tai
              khi link voi DLL, khong ton tai trong static link.
          (2) Target static vieneu-tts-core cua repo @cc037cf KHONG gom
              vienneu_tts.cpp (file nay thuoc target DLL) => plain
              vieneu_* cung khong co dinh nghia nao trong core.a.
        - Fix: (a) build.ps1 them -DVIENEU_STATIC vao CGO_CFLAGS (hop
          dong static-link cua vieneu_tts.h: VIENEU_API rong);
          (b) script nay tu bien dich src\vieneu\vieneu_tts.cpp thanh
          archive rieng native-build\vieneu-tts-api.a va ghi vao dong
          DAU TIEN cua link-libs.txt (build.ps1 doc toan bo link-libs
          vao nhom -Wl,--start-group/--end-group khi link cgo).

    PATCH run #40 (argv quoting cho lenh g++ thu cong - sua run #39):
        - Symptom run #39: "<command-line>: fatal error: ./ D:/a/.../
          vieneu_mingw_std_shim.h: Invalid argument" ngay buoc bien dich
          vieneu_tts.cpp (core build 215/215 da XANH het).
        - Root cause: PowerShell 5.1 truyen chuoi CO KHOANG TRANG cho
          exe ngoai thanh DUY NHAT 1 argv token trong dau ngoac kep.
          Khi token "-include D:/path/vieneu_mingw_std_shim.h" (co
          khoang) den gcc, driver MinGW forward nguyen ven sang cc1 va
          tu them tien to "./" => "./ D:/..." bi coi la duong dan
          tuong doi chua dau hai cham => Windows fopen bao "Invalid
          argument". Loi thu hai an trong cung co che: token
          "-DFOO=1 -DBAR=2" bi gcc hieu la DFOO co gia tri "1 -DBAR=2"
          va MAT hang -DBAR (kiem chung bang gcc -dM -E).
        - Fix: TACH MOI flag thanh 1 phan tu argv rieng trong mang
          $apiArgs roi goi "& $Gpp @apiArgs" - PowerShell tu boc ngoac
          kep phan tu co khoang trang, gcc nhan dung so argv token nhu
          khi goi tu cmd. Flag -include dung dang GAN "-include<path>"
          (khong khoang trang): van la cu phap hop le cua cpp va mien
          dich ca truong hop bi quote. Cac chuoi flag cho CMake
          (CMAKE_C_FLAGS / CMAKE_CXX_FLAGS) GIU NGUYEN dang chuoi vi
          CMake tu tach theo khoang trang - chi lenh goi g++ TRUC TIEP
          moi bat buoc dung argv array.

    PATCH run #44 (quay lai ORT 1.20.1 + bo khoi CUDA EP - CRASH FIX):
        - Symptom: run #41 va #43 (ORT 1.24.4) crash 100% khi bam tao
          giong doc; HCStudio-debug.exe in ra:
          "signal arrived during external code execution" ngay trong
          vieneu_init_v2 (driver_cgo.go:162) - Go runtime fatal, UEF
          khong bao gio duoc goi (minidump FIX41 khong sinh ra).
        - Bang chung: run #30 (ORT 1.20.1, dll 11299 KB) chay on dinh
          nhieu ngay tren cung may, cung model dir; run #41/#43 (dll
          13871 KB = 1.24.4) chet lap lai 3/3 lan thu (08:23, 08:24,
          08:53 ngay 10-09).
        - Root cause: ONNX Runtime 1.24.x crash khi khoi tao ben trong
          vieneu_init_v2 tren moi truong CPU cua user (Win10 x64, khong
          co CUDA). Khong the pin 1.20.1 truc tiep vi core @cc037cf
          dung Ort::CUDAProviderOptions - symbol chi co trong header
          ORT moi (loi 'CUDAProviderOptions' is not a member of 'Ort'
          tai vieneu_v3_onnx_engine.cpp:117 da kiem chung voi header
          1.18.1/1.19.2/1.20.1 trong qua khu).
        - Fix 2 buoc: (1) patch sau checkout - thay 5 dong CUDA EP
          trong src/vieneu/v3_onnx/vieneu_v3_onnx_engine.cpp bang
          error + return false (kieu patch tuong duong da chay thanh
          cong thoi ky v4/run #29-#30); (2) pin $OnnxRuntimeVersion
          = "1.20.1" (khop voi build.ps1). CPU-only khong mat gi:
          VIENEU_ORT_EP mac dinh rong/cpu, khoi CUDA chua bao gio
          duoc thuc thi tren cau hinh nay.

    PATCH run #45 (shim _stdcall cho ORT 1.20.1 + MinGW GCC - sua run #44):
        - Symptom run #44: core build XANH (patch CUDA EP + pin ORT
          1.20.1 nhu ke hoach), nhung ngay buoc bien dich rieng
          vieneu_tts.cpp (run #39) chet 355 error, deu khoi phat tu
          onnxruntime_c_api.h:
            "error: expected ')' before '*' token" tai dong 323/324/325/
            331/334/677/683/692/719/748/755/762...
            -> hang loat loi phu: "'const OrtApi' has no member named
            'Release...'" (onnxruntime_cxx_api.h/inline.h),
            "'OrtLoggingFunction' has not been declared",
            "'OrtGetApiBase' was not declared in this scope".
        - Root cause: onnxruntime_c_api.h cua ORT 1.20.1, dong 86:
            #define ORT_API_CALL _stdcall
          (1 gach duoi). GCC tren MinGW KHONG cong nhan "_stdcall" la
          keyword (form 1 gach duoi chi MSVC/clang-cl nhan; gcc can
          -fms-extensions) -> token con lai la IDENTIFIER -> khai bao
          con tro ham "void*(ORT_API_CALL* Alloc)(...)" bi parser doc
          nhu bieu thuc nhan "(ORT_API_CALL * Alloc)" -> "expected ')'
          before '*'" -> CA STRUCT OrtApi/OrtApiBase vo sinh -> moi
          member API mat -> 355 loi deu la he qua cua DUY NHAT 1 token.
          Bang chung doi chieu: header ORT v1.24.4 cung vi tri da doi
          thanh "__stdcall" (2 gach duoi, dong 90 cua v1.24.4) - day
          chinh la ly do run #35-#43 build XANH voi SDK moi. Bang chung
          trong log: khong co bat cu loi nao khac ngoai he qua cua
          ORT_API_CALL (sal annotation da duoc run #34 che truoc).
        - Fix: shim force-include (co che run #37) them anh xa:
            #define _stdcall __stdcall
          (guard __MINGW32__/__MINGW64__). Macro expansion xay ra
          TRUOC khi compiler tra cuu keyword nen an toan tuyet doi:
          neu gcc co nhan "_stdcall" thi macro van chi mo rong thanh
          dung keyword do; neu khong nhan thi macro bien token la
          keyword. Trong x64, __stdcall chi la ghi nhan (x64 co 1
          calling convention duy nhat) nen khong anh huong ABI/link.
          ORT >= 1.21 khong con tham chieu "_stdcall" nen macro tro
          nen trung tinh - script van switch OnnxRuntimeVersion
          1.20.1 <-> 1.24.4 duoc cho A/B test nhu cu.

    PATCH run #47 (bat sea-g2p chinh thuc - dong bo phonemizer voi Space HF):
        - Chat luong: user bao giong doc kem ro ret so voi HF Space
          doremon102/VieNeu-TTS-v3-Turbo. Doi chieu nguon Space (app.py)
          + wheel vieneu 3.6.3 tu PyPI: pipeline chuan phonemize text
          bang sea-g2p TRUOC khi tokenize (model duoc train tren chuoi
          phoneme, KHONG phai text tho). Ca duong ONNX CPU cua thu vien
          cung phonemize nhu nhau.
        - Root cause: CMake option VIENEU_SEA_G2P mac dinh OFF va script
          cu khong bat -> VieneuProfile::phonemize roi vao fallback
          rule-based tu viet (bang onset/rime/tone, khong dict, khong
          chuan hoa so/dau cau) -> phat am sai lech phan lon tu ->
          "doc nghe rat do".
        - Fix: -DVIENEU_SEA_G2P=ON. CMake tu dong: cargo build --release
          (Rust cdylib) -> sea_g2p_rs.dll + import lib; them define
          VIENEU_USE_SEA_G2P cho core target; dict sea_g2p.bin (50MB,
          commit trong submodule sea-g2p) copy canh exe (resolve path
          quet exe_dir dau tien). CI: tu dong cai rustup stable msvc
          (profile minimal) neu runner thieu cargo; VS Build Tools co
          san tren runner nen linker MSVC cua Rust chay duoc.
        - Ship: sea_g2p_rs.dll + sea_g2p.bin -> dist\ (build.ps1 run #47
          copy tu native-build\; BUILD-INFO.txt tu liet ke 2 file nay
          de user kiem tra). Link: uu tien dlltool (objdump exports ->
          .def -> import lib GNU, dung lai co che ORT); fallback:
          sea_g2p_rs.dll.lib MSVC cua cargo (ld doc duoc short import
          lib - bang chung onnxruntime.lib da chay).
        - Khong doi model weights (van pin onnx/ fp32); upgrade weights
          onnx_update/ thuoc goi tiep theo (FIX48).

    QUY trinh:
        1. Clone VieNeu-TTS.cpp @commit pinned + submodules (llama.cpp, sea-g2p)
        2. Tai ONNX Runtime SDK (win-x64) vao ort_sdk\
        3. Cau hinh + build bang GCC + Ninja -> thu thap TOAN BO .a trong
           build tree (ggml/ggml-base/ggml-cpu/llama/vieneu-tts-core tuy
           phien ban CMake - khong phu thuoc ten/vi tri cu the)
        3b. Bien dich rieng vienneu_tts.cpp -> native-build\vieneu-tts-api.a
           (C API wrapper cho cgo; run #39 + #40)
        4. Sinh import lib GNU cho onnxruntime.dll: objdump -p quet export
           -> ort.def -> dlltool. Fallback: PE parser thuan PowerShell.
           Fallback cuoi: dung lai onnxruntime.lib (ld doc duoc short import
           lib; CGO_LDFLAGS_ALLOW cua build.ps1 da cho phep .lib)
        5. Ghi link-libs.txt: duong dan .a (moi dong 1 file) + flags
           -fopenmp -lstdc++ -ladvapi32 -lole32 -loleaut32 -luser32
           -lws2_32 -lbcrypt
        6. run #47: cai Rust neu thieu + build sea-g2p (cargo) + thu
           thap sea_g2p_rs.dll / sea_g2p.bin / import lib + ghi vao
           link-libs.txt (build.ps1 ship 2 file dau vao dist)

    LUU Y: File nay CHI DUNG KY TU ASCII (khong dau tieng Viet) de tranh
    loi encoding khi chay bang Windows PowerShell 5.1 (powershell.exe).
    VA: KHONG DUNG KY TU BACKTICK (byte 0x60) trong file nay - bai hoc
    run #13 (backtick bi mat khi copy qua chat, lam hong chuoi escape).
#>
param(
    # run #44: quay lai 1.20.1. ORT 1.24.4 crash 100% trong vieneu_init_v2
    # tren may user (run #41/#43); 1.20.1 = phien ban da chung minh on dinh
    # (run #30). Kem theo patch bo khoi CUDA EP (run #44, sau buoc clone)
    # de core compile duoc voi header 1.20.1. PHAI khop voi build.ps1.
    [string]$OnnxRuntimeVersion = "1.20.1",
    [string]$VieneuCommit       = "cc037cf4475cad9b68f16cd9de9c76473cc3640b",
    # PATCH FIX48 - CHU QUYEN NGUON (build-time): 2 tuy chon mirror de
    # khong phu thuoc GitHub cua ben thu ba khi build:
    #   $VieneuRepoUrl - repo core (fork cua ban). Mac dinh upstream.
    #     Vi du: https://github.com/<ban>/VieNeu-TTS.cpp.git
    #   $OrtZipMirror  - URL DAY DU file zip onnxruntime-win-x64 tren
    #     mirror cua ban (GitHub Release rieng/NAS). De rong = tai tu
    #     release chinh thuc microsoft. Mirror loi se tu fallback ve
    #     microsoft. File mirror PHAI giong nguyen ban goc (mo rong
    #     duoc check thu muc lib\onnxruntime.lib).
    # Submodules (llama.cpp, sea-g2p) keo qua git submodule cua repo
    # tren - fork repo cha roi doi .gitmodules trong fork de lam chu.
    [string]$VieneuRepoUrl      = "https://github.com/pnnbao97/VieNeu-TTS.cpp.git",
    [string]$OrtZipMirror       = "",
    [string]$Gcc                = "",
    [switch]$StaticOnnxRuntime
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$ThirdDir  = Join-Path $RepoRoot "third_party"
$VnRepoDir = Join-Path $ThirdDir "VieNeu-TTS.cpp"
$NbDir     = Join-Path $RepoRoot "native-build"
$OrtSdkDir = Join-Path $RepoRoot "ort_sdk"

Write-Host "HCStudio prepare-vieneu v41 - GCC MinGW + Ninja (run #39: vieneu-tts-api.a cho cgo; run #40: argv quoting manual g++)"

# KHONG backtick trong toan bo file (bai hoc run #13): xuong dong bang Write-Host ""
function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Die($msg)  { Write-Host ""; Write-Host "[XX] $msg" -ForegroundColor Red;  exit 1 }

New-Item -ItemType Directory -Force -Path $ThirdDir, $NbDir | Out-Null

# --------------------------------------------------------------- clone source
Step "Lay ma nguon VieNeu-TTS.cpp @ $VieneuCommit"
if (!(Test-Path (Join-Path $VnRepoDir ".git"))) {
    # EAP=Continue trong luc chay git: stderr cua git khong duoc coi la loi (quirk PS5.1)
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git clone $VieneuRepoUrl $VnRepoDir
    $ErrorActionPreference = $oldEap
    if ($LASTEXITCODE -ne 0) { Die "git clone that bai - kiem tra ket noi mang." }
}
Push-Location $VnRepoDir
try {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git fetch origin $VieneuCommit 2>$null | Out-Null
    git checkout -q --detach $VieneuCommit
    # submodules: llama.cpp + sea-g2p
    git submodule update --init --recursive --depth 1
    $ErrorActionPreference = $oldEap
    if ($LASTEXITCODE -ne 0) { Die "submodule update that bai." }
}
finally { Pop-Location }

# ------------------ PATCH run #44: bo khoi CUDA EP (CPU-only + ORT 1.20.1)
# Ort::CUDAProviderOptions chi co trong header ORT moi; 1.20.1 (on dinh
# tren may user) thieu symbol nay -> thay 5 dong CUDA bang error+return
# false. Luong thuc thi CPU khong bao gio cham vao khoi nay (VIENEU_ORT_EP
# mac dinh rong/cpu). Neu upstream doi cau truc khoi -> Die (fail loudly).
Step "Patch: bo khoi CUDA EP trong vieneu_v3_onnx_engine.cpp (run #44)"
$engineFile = Join-Path $VnRepoDir "src\vieneu\v3_onnx\vieneu_v3_onnx_engine.cpp"
if (!(Test-Path $engineFile)) { Die "Khong thay vieneu_v3_onnx_engine.cpp sau khi clone." }
$srcLines = [System.IO.File]::ReadAllLines($engineFile)
$idx = -1
for ($i = 0; $i -lt $srcLines.Count; $i++) {
    if ($srcLines[$i] -like "*Ort::CUDAProviderOptions cuda_options;*") { $idx = $i; break }
}
if ($idx -lt 1) { Die "Khong tim thay khoi CUDA trong engine.cpp - repo da thay doi?" }
$okOpen  = $srcLines[$idx - 1] -like '*requested == "cuda"*'
$okClose = $srcLines[$idx + 4] -like '*return true;*'
if (!$okOpen -or !$okClose) { Die "Cau truc khoi CUDA khong nhu du bao - khong patch mau hieu." }
$replacement = @(
    '            error = "CUDA EP is not available in this build (HCStudio is CPU-only).";',
    '            return false;'
)
$head = $srcLines[0..($idx - 1)]
$tail = @()
if ($idx + 5 -lt $srcLines.Count) { $tail = $srcLines[($idx + 5)..($srcLines.Count - 1)] }
[System.IO.File]::WriteAllLines($engineFile, (@($head) + $replacement + $tail))
Write-Host ("Da thay khoi CUDA (gan dong " + ($idx + 1) + ") bang CPU-only guard.")

# ------------------ PATCH FIX49: weights onnx_update/ (vieneu_v3 arch)
# Nang weights onnx/ -> onnx_update/ can 3 thay doi trong core @cc037cf:
#   (1) acoustic_frame_onnx parameterize KV theo local_num_hidden_layers
#       (turbo=2 -> 6in/5out; update+int8=1 -> 4in/3out);
#   (2) speaker anchor: xvec Linear+LayerNorm tu heads.npz, cong vao MOI row
#       cua backbone (preset speaker_emb 192-d trong voices JSON);
#   (3) head token = default_style_token_id (tu_nhien) khi config co.
# 5 file da patch duoc nhung base64 o duoi (nguon pin @cc037cf la bat
#   bien nen thay toan bo file la an toan hon sua tung choi). Patch GIU
#   tuong thich nguoc: weights cu onnx/ van chay (L=2, khong xvec, khong style).
Step "Patch FIX49: nap 5 file core parameterized (acoustic KV + speaker anchor + style head)"
$fix49Map = @{
    'src\vieneu\vieneu_v3_onnx.h' = 'I2lmbmRlZiBWSUVORVVfVjNfT05OWF9ICiNkZWZpbmUgVklFTkVVX1YzX09OTlhfSAoKI2luY2x1ZGUgPG1lbW9yeT4KI2luY2x1ZGUgPG11dGV4PgojaW5jbHVkZSA8cmFuZG9tPgojaW5jbHVkZSA8c3RyaW5nPgojaW5jbHVkZSA8dW5vcmRlcmVkX21hcD4KI2luY2x1ZGUgPHV0aWxpdHk+CiNpbmNsdWRlIDx2ZWN0b3I+CgojaW5jbHVkZSAib25ueHJ1bnRpbWVfY3h4X2FwaS5oIgojaW5jbHVkZSAidjNfY29tbW9uL3YzX3JlcGV0aXRpb25faGlzdG9yeS5oIgojaW5jbHVkZSAidmllbmV1X3Byb2dyZXNzLmgiCgpzdHJ1Y3QgVmllbmV1VjNPbm54SW5pdCB7CiAgICBzdGQ6OnN0cmluZyBtb2RlbF9kaXI7CiAgICBzdGQ6OnN0cmluZyBvbm54X2RpcjsKICAgIHN0ZDo6c3RyaW5nIGNvZGVjX2RpcjsKICAgIHN0ZDo6c3RyaW5nIGNvbmZpZ19wYXRoOwogICAgc3RkOjpzdHJpbmcgdG9rZW5pemVyX3BhdGg7CiAgICBzdGQ6OnN0cmluZyB2b2ljZXNfanNvbl9wYXRoOwogICAgaW50IG5fdGhyZWFkcyA9IDI7Cn07CgpzdHJ1Y3QgVmllbmV1VjNPbm54UGFyYW1zIHsKICAgIHN0ZDo6c3RyaW5nIHRleHQ7CiAgICBzdGQ6OnN0cmluZyB2b2ljZV9pZDsKICAgIHN0ZDo6c3RyaW5nIHJlZl9hdWRpb19wYXRoOwogICAgZmxvYXQgdGVtcGVyYXR1cmUgPSAwLjhmOwogICAgaW50IHRvcF9rID0gMjU7CiAgICBmbG9hdCB0b3BfcCA9IDAuOTVmOwogICAgaW50IG1heF9uZXdfZnJhbWVzID0gMzAwOwogICAgZmxvYXQgcmVwZXRpdGlvbl9wZW5hbHR5ID0gMS4yZjsKICAgIGludCBtYXhfY2hhcnMgPSAzODQ7CiAgICBib29sIGFwcGx5X3dhdGVybWFyayA9IHRydWU7CiAgICBWaWVuZXVQcm9ncmVzc0ZuIHByb2dyZXNzOwogICAgZmxvYXQgcHJvZ3Jlc3NfYmFzZSA9IDAuMGY7CiAgICBmbG9hdCBwcm9ncmVzc19zcGFuID0gMS4wZjsKfTsKCmNsYXNzIFZpZW5ldVYzT25ueEVuZ2luZSB7CnB1YmxpYzoKICAgIGJvb2wgaW5pdGlhbGl6ZShjb25zdCBWaWVuZXVWM09ubnhJbml0JiBpbml0LCBzdGQ6OnN0cmluZyYgZXJyb3IpOwogICAgYm9vbCBzeW50aGVzaXplKGNvbnN0IFZpZW5ldVYzT25ueFBhcmFtcyYgcGFyYW1zLCBzdGQ6OnZlY3RvcjxmbG9hdD4mIG91dF9hdWRpbywgc3RkOjpzdHJpbmcmIGVycm9yKTsKCiAgICBjb25zdCBzdGQ6OnN0cmluZyYgdm9pY2VzX2pzb24oKSBjb25zdCB7IHJldHVybiB2b2ljZXNfanNvbl87IH0KICAgIGludCBzYW1wbGVfcmF0ZSgpIGNvbnN0IHsgcmV0dXJuIDQ4MDAwOyB9Cgpwcml2YXRlOgogICAgc3RydWN0IFRlbnNvcjJEIHsKICAgICAgICBpbnQ2NF90IHJvd3MgPSAwOwogICAgICAgIGludDY0X3QgY29scyA9IDA7CiAgICAgICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGRhdGE7CiAgICB9OwoKICAgIHN0cnVjdCBUZW5zb3IzRCB7CiAgICAgICAgaW50NjRfdCBkaW0wID0gMDsKICAgICAgICBpbnQ2NF90IGRpbTEgPSAwOwogICAgICAgIGludDY0X3QgZGltMiA9IDA7CiAgICAgICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGRhdGE7CiAgICB9OwoKICAgIHN0cnVjdCBDb25maWcgewogICAgICAgIGludCBuX3ZxID0gMTY7CiAgICAgICAgaW50IGhpZGRlbl9zaXplID0gNzY4OwogICAgICAgIGludCBudW1faGlkZGVuX2xheWVycyA9IDEyOwogICAgICAgIGludCBhdWRpb19wYWRfdG9rZW5faWQgPSAxMDI0OwogICAgICAgIGludCB0ZXh0X3Byb21wdF9zdGFydF90b2tlbl9pZCA9IDM7CiAgICAgICAgaW50IHRleHRfcHJvbXB0X2VuZF90b2tlbl9pZCA9IDQ7CiAgICAgICAgaW50IHNwZWVjaF9nZW5lcmF0aW9uX3N0YXJ0X3Rva2VuX2lkID0gNTsKICAgICAgICBpbnQgc3BlZWNoX2dlbmVyYXRpb25fZW5kX3Rva2VuX2lkID0gNjsKICAgICAgICBpbnQgYXVkaW9fcmVmX3Nsb3RfdG9rZW5faWQgPSA3OwogICAgICAgIGludCBlbW90aW9uXzBfdG9rZW5faWQgPSA4OwogICAgICAgIGludCBlbW90aW9uXzRfdG9rZW5faWQgPSAxMjsKICAgICAgICBpbnQgdGV4dF92b2NhYl9zaXplID0gNDE5OwogICAgICAgIGludCBhdWRpb192b2NhYl9zaXplID0gMTAyNDsKICAgICAgICBpbnQgbG9jYWxfbnVtX2F0dGVudGlvbl9oZWFkcyA9IDg7CiAgICAgICAgaW50IGxvY2FsX251bV9oaWRkZW5fbGF5ZXJzID0gMjsKICAgICAgICBpbnQgbG9jYWxfaW50ZXJtZWRpYXRlX3NpemUgPSAyMDQ4OwogICAgICAgIGZsb2F0IHJtc19ub3JtX2VwcyA9IDFlLTZmOwogICAgICAgIC8vIFBBVENIIEZJWDQ5OiB1cGRhdGUgYXJjaCAodmllbmV1X3YzKSBhZGRpdGlvbnMgLSB0dXJibyBjb25maWcKICAgICAgICAvLyBsYWNrcyB0aGVzZSBrZXlzIHNvIGMudmFsdWUoKSBrZWVwcyB0aGUgc2FmZSBkZWZhdWx0cyBoZXJlLgogICAgICAgIGludCBkZWZhdWx0X3N0eWxlX3Rva2VuX2lkID0gLTE7CiAgICAgICAgYm9vbCB1c2Vfc3BlYWtlcl9lbWJlZGRpbmcgPSBmYWxzZTsKICAgICAgICBpbnQgc3BlYWtlcl9lbWJlZGRpbmdfZGltID0gMTkyOwogICAgfTsKCiAgICBzdHJ1Y3QgQWNvdXN0aWNMYXllcldlaWdodHMgewogICAgICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBub3JtMTsKICAgICAgICBzdGQ6OnZlY3RvcjxmbG9hdD4gcWt2OwogICAgICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBxX25vcm07CiAgICAgICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGtfbm9ybTsKICAgICAgICBzdGQ6OnZlY3RvcjxmbG9hdD4gb19wcm9qOwogICAgICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBub3JtMjsKICAgICAgICBzdGQ6OnZlY3RvcjxmbG9hdD4gZmZfdXA7CiAgICAgICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGZmX2dhdGU7CiAgICAgICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGZmX2Rvd247CiAgICB9OwoKICAgIHN0cnVjdCBBY291c3RpY1dlaWdodHMgewogICAgICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBzbG90X3Bvc19lbWI7CiAgICAgICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGZpbmFsX25vcm07CiAgICAgICAgc3RkOjp2ZWN0b3I8QWNvdXN0aWNMYXllcldlaWdodHM+IGxheWVyczsKICAgICAgICBib29sIGxvYWRlZCA9IGZhbHNlOwogICAgfTsKCiAgICBzdHJ1Y3QgUHJvbXB0Um93cyB7CiAgICAgICAgaW50NjRfdCByb3dzID0gMDsKICAgICAgICBpbnQ2NF90IGNvbHMgPSAwOwogICAgICAgIHN0ZDo6dmVjdG9yPGludDY0X3Q+IGRhdGE7CiAgICB9OwoKICAgIHN0cnVjdCBXYXZEYXRhIHsKICAgICAgICBpbnQgc2FtcGxlX3JhdGUgPSAwOwogICAgICAgIGludCBjaGFubmVscyA9IDA7CiAgICAgICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IHNhbXBsZXM7IC8vIGludGVybGVhdmVkCiAgICB9OwoKICAgIHN0cnVjdCBWb2ljZVByZXNldCB7CiAgICAgICAgYm9vbCBmb3VuZCA9IGZhbHNlOwogICAgICAgIGJvb2wgaGFzX3Jlc2VydmVkX2lkID0gZmFsc2U7CiAgICAgICAgaW50IHJlc2VydmVkX2lkID0gMDsKICAgICAgICBzdGQ6OnZlY3RvcjxpbnQ2NF90PiBjb2RlczsKICAgICAgICAvLyBQQVRDSCBGSVg0OTogMTkyLWQgeC12ZWN0b3IgZnJvbSB2b2ljZXMgSlNPTiAodXBkYXRlIGFyY2gpLgogICAgICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBzcGVha2VyX2VtYjsKICAgIH07CgogICAgc3RydWN0IFNlc3Npb25JbyB7CiAgICAgICAgc3RkOjp2ZWN0b3I8c3RkOjpzdHJpbmc+IGlucHV0X25hbWVzOwogICAgICAgIHN0ZDo6dmVjdG9yPHN0ZDo6c3RyaW5nPiBvdXRwdXRfbmFtZXM7CiAgICAgICAgc3RkOjp2ZWN0b3I8Y29uc3QgY2hhcio+IGlucHV0X3B0cnM7CiAgICAgICAgc3RkOjp2ZWN0b3I8Y29uc3QgY2hhcio+IG91dHB1dF9wdHJzOwogICAgfTsKCiAgICBzdHJ1Y3QgQmVuY2htYXJrU3RhdHMgewogICAgICAgIGRvdWJsZSBwcmVmaWxsX21zID0gMC4wOwogICAgICAgIGRvdWJsZSBkZWNvZGVfc3RlcF9tcyA9IDAuMDsKICAgICAgICBkb3VibGUgYWNvdXN0aWNfZnJhbWVfbXMgPSAwLjA7CiAgICAgICAgZG91YmxlIGNvZGVjX2RlY29kZV9tcyA9IDAuMDsKICAgICAgICBpbnQ2NF90IHByZWZpbGxfY2FsbHMgPSAwOwogICAgICAgIGludDY0X3QgZGVjb2RlX3N0ZXBfY2FsbHMgPSAwOwogICAgICAgIGludDY0X3QgYWNvdXN0aWNfZnJhbWVfY2FsbHMgPSAwOwogICAgICAgIGludDY0X3QgY29kZWNfZGVjb2RlX2NhbGxzID0gMDsKICAgIH07CgogICAgc3RydWN0IEJ5dGVCcGVUb2tlbml6ZXIgewogICAgICAgIGJvb2wgbG9hZChjb25zdCBzdGQ6OnN0cmluZyYgcGF0aCwgc3RkOjpzdHJpbmcmIGVycm9yKTsKICAgICAgICBzdGQ6OnZlY3RvcjxpbnQ2NF90PiBlbmNvZGUoY29uc3Qgc3RkOjpzdHJpbmcmIHRleHQpIGNvbnN0OwoKICAgICAgICBzdGQ6OnVub3JkZXJlZF9tYXA8c3RkOjpzdHJpbmcsIGludDY0X3Q+IHZvY2FiOwogICAgICAgIHN0ZDo6dW5vcmRlcmVkX21hcDxzdGQ6OnN0cmluZywgaW50PiBtZXJnZV9yYW5rczsKICAgICAgICBpbnQ2NF90IHVua19pZCA9IDQzOwogICAgfTsKCiAgICBjbGFzcyBBY291c3RpY0V4ZWN1dG9yIHsKICAgIHB1YmxpYzoKICAgICAgICB2aXJ0dWFsIH5BY291c3RpY0V4ZWN1dG9yKCkgPSBkZWZhdWx0OwogICAgICAgIHZpcnR1YWwgY29uc3QgY2hhciogYmFja2VuZF9uYW1lKCkgY29uc3QgPSAwOwogICAgICAgIHZpcnR1YWwgYm9vbCBnZW5lcmF0ZV9mcmFtZShjb25zdCBzdGQ6OnZlY3RvcjxmbG9hdD4mIGgsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZsb2F0IHRlbXBlcmF0dXJlLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpbnQgdG9wX2ssCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZsb2F0IHRvcF9wLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmbG9hdCByZXBldGl0aW9uX3BlbmFsdHksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0ZDo6dmVjdG9yPFYzUmVwZXRpdGlvbkhpc3Rvcnk+JiBoaXN0b3J5LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdGQ6OnZlY3RvcjxpbnQ2NF90PiYgY29kZXMsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGJvb2wmIGVvcywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgc3RkOjpzdHJpbmcmIGVycm9yKSA9IDA7CiAgICB9OwoKICAgIGNsYXNzIE9ubnhBY291c3RpY0V4ZWN1dG9yOwogICAgY2xhc3MgTmF0aXZlQWNvdXN0aWNFeGVjdXRvcjsKCiAgICBzdGF0aWMgc3RkOjpzdHJpbmcgam9pbl9wYXRoKGNvbnN0IHN0ZDo6c3RyaW5nJiBkaXIsIGNvbnN0IHN0ZDo6c3RyaW5nJiBuYW1lKTsKICAgIHN0YXRpYyBib29sIGZpbGVfZXhpc3RzKGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoKTsKICAgIHN0YXRpYyBib29sIHJlYWRfdGV4dF9maWxlKGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoLCBzdGQ6OnN0cmluZyYgb3V0KTsKCiAgICBib29sIGxvYWRfc2Vzc2lvbihjb25zdCBzdGQ6OnN0cmluZyYgcGF0aCwgc3RkOjp1bmlxdWVfcHRyPE9ydDo6U2Vzc2lvbj4mIHNlc3Npb24sIHN0ZDo6c3RyaW5nJiBlcnJvcik7CiAgICB2b2lkIGNhY2hlX3Nlc3Npb25faW8oT3J0OjpTZXNzaW9uJiBzZXNzaW9uLCBTZXNzaW9uSW8mIGlvKTsKICAgIGJvb2wgdmFsaWRhdGVfYXNzZXRzKGNvbnN0IFZpZW5ldVYzT25ueEluaXQmIGluaXQsIHN0ZDo6c3RyaW5nJiBlcnJvcik7CiAgICBib29sIGxvYWRfdm9pY2VzKGNvbnN0IHN0ZDo6c3RyaW5nJiB2b2ljZXNfcGF0aCwgc3RkOjpzdHJpbmcmIGVycm9yKTsKICAgIGJvb2wgbG9hZF9jb25maWcoY29uc3Qgc3RkOjpzdHJpbmcmIHBhdGgsIHN0ZDo6c3RyaW5nJiBlcnJvcik7CiAgICBib29sIGxvYWRfaGVhZHNfbnB6KGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoLCBzdGQ6OnN0cmluZyYgZXJyb3IpOwogICAgYm9vbCBsb2FkX2Fjb3VzdGljX3dlaWdodHMoY29uc3Qgc3RkOjpzdHJpbmcmIHBhdGgsIHN0ZDo6c3RyaW5nJiBlcnJvcik7CiAgICBib29sIHBhcnNlX3ZvaWNlX3Jlc2VydmVkX2lkKGNvbnN0IHN0ZDo6c3RyaW5nJiB2b2ljZV9pZCwgaW50JiByZXNlcnZlZF9pZCkgY29uc3Q7CiAgICBib29sIHJlc29sdmVfdm9pY2VfcHJlc2V0KGNvbnN0IHN0ZDo6c3RyaW5nJiB2b2ljZV9pZCwgVm9pY2VQcmVzZXQmIHByZXNldCwgc3RkOjpzdHJpbmcmIGVycm9yKSBjb25zdDsKICAgIGJvb2wgcmVhZF93YXZfZmlsZShjb25zdCBzdGQ6OnN0cmluZyYgcGF0aCwgV2F2RGF0YSYgd2F2LCBzdGQ6OnN0cmluZyYgZXJyb3IpIGNvbnN0OwogICAgYm9vbCBlbmNvZGVfcmVmZXJlbmNlX2F1ZGlvKGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoLCBzdGQ6OnZlY3RvcjxpbnQ2NF90PiYgb3V0X2NvZGVzLCBzdGQ6OnN0cmluZyYgZXJyb3IpOwoKICAgIFByb21wdFJvd3MgYnVpbGRfcm93cyhjb25zdCBzdGQ6OnN0cmluZyYgcGhvbmVtZXMsIGNvbnN0IHN0ZDo6dmVjdG9yPGludDY0X3Q+KiByZWZfY29kZXMsIGludCBsZWFkaW5nX3Rva2VuKSBjb25zdDsKICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBlbWJlZF9yb3dzKGNvbnN0IFByb21wdFJvd3MmIHJvd3MsIGNvbnN0IHN0ZDo6dmVjdG9yPGZsb2F0PiogYW5jaG9yKSBjb25zdDsKICAgIHZvaWQgY29tcHV0ZV9zcGVha2VyX2FuY2hvcihjb25zdCBzdGQ6OnZlY3RvcjxmbG9hdD4mIHNwZWFrZXJfZW1iKTsKICAgIGJvb2wgc3ludGhlc2l6ZV9waG9uZW1lcyhjb25zdCBzdGQ6OnN0cmluZyYgcGhvbmVtZXMsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29uc3Qgc3RkOjp2ZWN0b3I8aW50NjRfdD4qIHJlZl9jb2RlcywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpbnQgbGVhZGluZ190b2tlbiwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBWaWVuZXVWM09ubnhQYXJhbXMmIHBhcmFtcywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdGQ6OnZlY3RvcjxmbG9hdD4mIG91dF9hdWRpbywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdGQ6OnN0cmluZyYgZXJyb3IpOwogICAgYm9vbCBpbml0aWFsaXplX2Fjb3VzdGljX2V4ZWN1dG9yKHN0ZDo6c3RyaW5nJiBlcnJvcik7CiAgICBib29sIGluaXRpYWxpemVfbmF0aXZlX2Fjb3VzdGljX2V4ZWN1dG9yKHN0ZDo6c3RyaW5nJiBlcnJvcik7CiAgICBib29sIGFjb3VzdGljX2ZyYW1lKGNvbnN0IHN0ZDo6dmVjdG9yPGZsb2F0PiYgaCwKICAgICAgICAgICAgICAgICAgICAgICAgZmxvYXQgdGVtcGVyYXR1cmUsCiAgICAgICAgICAgICAgICAgICAgICAgIGludCB0b3BfaywKICAgICAgICAgICAgICAgICAgICAgICAgZmxvYXQgdG9wX3AsCiAgICAgICAgICAgICAgICAgICAgICAgIGZsb2F0IHJlcGV0aXRpb25fcGVuYWx0eSwKICAgICAgICAgICAgICAgICAgICAgICAgc3RkOjp2ZWN0b3I8VjNSZXBldGl0aW9uSGlzdG9yeT4mIGhpc3RvcnksCiAgICAgICAgICAgICAgICAgICAgICAgIHN0ZDo6dmVjdG9yPGludDY0X3Q+JiBjb2RlcywKICAgICAgICAgICAgICAgICAgICAgICAgYm9vbCYgZW9zLAogICAgICAgICAgICAgICAgICAgICAgICBzdGQ6OnN0cmluZyYgZXJyb3IpOwogICAgYm9vbCBhY291c3RpY19mcmFtZV9vbm54KGNvbnN0IHN0ZDo6dmVjdG9yPGZsb2F0PiYgaCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmbG9hdCB0ZW1wZXJhdHVyZSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBpbnQgdG9wX2ssCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZmxvYXQgdG9wX3AsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZmxvYXQgcmVwZXRpdGlvbl9wZW5hbHR5LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0ZDo6dmVjdG9yPFYzUmVwZXRpdGlvbkhpc3Rvcnk+JiBoaXN0b3J5LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0ZDo6dmVjdG9yPGludDY0X3Q+JiBjb2RlcywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICBib29sJiBlb3MsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgc3RkOjpzdHJpbmcmIGVycm9yKTsKICAgIGludDY0X3Qgc2FtcGxlX2xvZ2l0cyhzdGQ6OnZlY3RvcjxmbG9hdD4mIGxvZ2l0cywKICAgICAgICAgICAgICAgICAgICAgICAgICBmbG9hdCB0ZW1wZXJhdHVyZSwKICAgICAgICAgICAgICAgICAgICAgICAgICBpbnQgdG9wX2ssCiAgICAgICAgICAgICAgICAgICAgICAgICAgZmxvYXQgdG9wX3AsCiAgICAgICAgICAgICAgICAgICAgICAgICAgZmxvYXQgcmVwZXRpdGlvbl9wZW5hbHR5LAogICAgICAgICAgICAgICAgICAgICAgICAgIGNvbnN0IFYzUmVwZXRpdGlvbkhpc3RvcnkqIHByZXZpb3VzKTsKICAgIGJvb2wgZGVjb2RlX2NvZGVzKGNvbnN0IHN0ZDo6dmVjdG9yPGludDMyX3Q+JiBmcmFtZXMsIGludDY0X3QgZnJhbWVfY291bnQsIHN0ZDo6dmVjdG9yPGZsb2F0PiYgb3V0X2F1ZGlvLCBzdGQ6OnN0cmluZyYgZXJyb3IpOwogICAgc3RkOjpzdHJpbmcgcGhvbmVtaXplX2Zvcl92Myhjb25zdCBzdGQ6OnN0cmluZyYgdGV4dCkgY29uc3Q7CiAgICB2b2lkIHJlc2V0X2JlbmNobWFya19zdGF0cygpOwogICAgdm9pZCBwcmludF9iZW5jaG1hcmtfc3RhdHMoKSBjb25zdDsKICAgIE9ydDo6TWVtb3J5SW5mbyYgY3B1X21lbW9yeV9pbmZvKCk7CgogICAgc3RkOjpzaGFyZWRfcHRyPE9ydDo6RW52PiBlbnZfOwogICAgc3RkOjp1bmlxdWVfcHRyPE9ydDo6U2Vzc2lvbk9wdGlvbnM+IHNlc3Npb25fb3B0aW9uc187CiAgICBzdGQ6OnVuaXF1ZV9wdHI8T3J0OjpTZXNzaW9uPiBwcmVmaWxsX3Nlc3Npb25fOwogICAgc3RkOjp1bmlxdWVfcHRyPE9ydDo6U2Vzc2lvbj4gZGVjb2RlX3Nlc3Npb25fOwogICAgc3RkOjp1bmlxdWVfcHRyPE9ydDo6U2Vzc2lvbj4gYWNvdXN0aWNfc2Vzc2lvbl87CiAgICBzdGQ6OnVuaXF1ZV9wdHI8T3J0OjpTZXNzaW9uPiBjb2RlY19kZWNvZGVfc2Vzc2lvbl87CiAgICBzdGQ6OnVuaXF1ZV9wdHI8T3J0OjpTZXNzaW9uPiBjb2RlY19lbmNvZGVfc2Vzc2lvbl87CiAgICBzdGQ6OnVuaXF1ZV9wdHI8QWNvdXN0aWNFeGVjdXRvcj4gYWNvdXN0aWNfZXhlY3V0b3JfOwogICAgc3RkOjp1bmlxdWVfcHRyPE9ydDo6TWVtb3J5SW5mbz4gY3B1X21lbW9yeV9pbmZvXzsKICAgIFNlc3Npb25JbyBwcmVmaWxsX2lvXzsKICAgIFNlc3Npb25JbyBkZWNvZGVfaW9fOwogICAgU2Vzc2lvbklvIGFjb3VzdGljX2lvXzsKICAgIFNlc3Npb25JbyBjb2RlY19kZWNvZGVfaW9fOwogICAgU2Vzc2lvbklvIGNvZGVjX2VuY29kZV9pb187CiAgICBzdGQ6OnN0cmluZyBjb2RlY19lbmNvZGVfcGF0aF87CiAgICBzdGQ6OnN0cmluZyB2b2ljZXNfanNvbl87CiAgICBzdGQ6OnN0cmluZyBkZWZhdWx0X3ZvaWNlX2lkXzsKICAgIHN0ZDo6dW5vcmRlcmVkX21hcDxzdGQ6OnN0cmluZywgVm9pY2VQcmVzZXQ+IHZvaWNlX3ByZXNldHNfOwogICAgQ29uZmlnIGNvbmZpZ187CiAgICBUZW5zb3IyRCB0ZXh0X2VtYl87CiAgICBUZW5zb3IyRCB0ZXh0X2VtYl90XzsKICAgIFRlbnNvcjNEIGF1ZGlvX2VtYl87CiAgICBUZW5zb3IzRCBhdWRpb19lbWJfdF87CiAgICAvLyBQQVRDSCBGSVg0OTogeHZlYyBwcm9qZWN0aW9uIChMaW5lYXIrTGF5ZXJOb3JtKSArIGNhY2hlZCBhbmNob3IuCiAgICBib29sIGhhc194dmVjX3Byb2pfID0gZmFsc2U7CiAgICBzdGQ6OnZlY3RvcjxmbG9hdD4geHZlY193XzsgICAgICAgICAgLy8gKEgsIHNwa19kaW0pIHJvdy1tYWpvcgogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IHh2ZWNfYl87ICAgICAgICAgIC8vIChILCkKICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiB4dmVjX2xuX3dfOyAgICAgICAvLyAoSCwpCiAgICBzdGQ6OnZlY3RvcjxmbG9hdD4geHZlY19sbl9iXzsgICAgICAgLy8gKEgsKQogICAgZmxvYXQgeHZlY19sbl9lcHNfID0gMWUtNWY7CiAgICBzdGQ6OnZlY3RvcjxmbG9hdD4gc3BlYWtlcl9hbmNob3JfOyAgLy8gKEgsKSBlbXB0eSA9IG9mZgogICAgc3RkOjp2ZWN0b3I8T3J0OjpWYWx1ZT4gYWNvdXN0aWNfcGtfOwogICAgc3RkOjp2ZWN0b3I8T3J0OjpWYWx1ZT4gYWNvdXN0aWNfcHZfOwogICAgQWNvdXN0aWNXZWlnaHRzIGFjb3VzdGljX3dlaWdodHNfOwogICAgQnl0ZUJwZVRva2VuaXplciB0b2tlbml6ZXJfOwogICAgc3RkOjpzdHJpbmcgbW9kZWxfZGlyXzsKICAgIHN0ZDo6c3RyaW5nIG9ubnhfZGlyXzsKICAgIHN0ZDo6c3RyaW5nIGNvZGVjX2Rpcl87CiAgICBpbnQgdGhyZWFkc190b191c2VfID0gNDsKICAgIHN0ZDo6bXV0ZXggcnVuX211dGV4XzsKICAgIHN0ZDo6bXQxOTkzNyBybmdfOwogICAgYm9vbCBpbml0aWFsaXplZF8gPSBmYWxzZTsKICAgIGJvb2wgYmVuY2htYXJrX2VuYWJsZWRfID0gZmFsc2U7CiAgICBCZW5jaG1hcmtTdGF0cyBiZW5jaG1hcmtfc3RhdHNfOwoKICAgIC8vIFNjcmF0Y2ggYnVmZmVycyBmb3Igc2FtcGxpbmcgdG8gYXZvaWQgYWxsb2NhdGlvbiBvdmVyaGVhZAogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IHNhbXBsaW5nX3RtcF87CiAgICBzdGQ6OnZlY3RvcjxzdGQ6OnBhaXI8ZmxvYXQsIHNpemVfdD4+IHNhbXBsaW5nX3BhaXJzXzsKICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBzYW1wbGluZ19wcm9ic187CgogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IHN5bnRoX2hfOwogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IHN5bnRoX3NlXzsKICAgIHN0ZDo6dmVjdG9yPE9ydDo6VmFsdWU+IHN5bnRoX2RlY29kZV9pbnB1dHNfOwogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGFjb3VzdGljX3Rva2VuXzsKICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBhY291c3RpY19lbXB0eV87CiAgICBzdGQ6OnZlY3RvcjxmbG9hdD4gYWNvdXN0aWNfc2xvdDBfOwogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGFjb3VzdGljX2xvZ2l0c187CiAgICBzdGQ6OnZlY3RvcjxmbG9hdD4gYWNvdXN0aWNfdGV4dF9sb2dpdHNfOwogICAgc3RkOjp2ZWN0b3I8T3J0OjpWYWx1ZT4gYWNvdXN0aWNfaW5wdXRzXzsKICAgIHN0ZDo6dmVjdG9yPE9ydDo6VmFsdWU+IGFjb3VzdGljX3N0ZXBfaW5wdXRzXzsKfTsKCiNlbmRpZiAvLyBWSUVORVVfVjNfT05OWF9ICg=='
    'src\vieneu\v3_onnx\vieneu_v3_onnx_inference.cpp' = 'I2luY2x1ZGUgIi4uL3ZpZW5ldV92M19vbm54LmgiCiNpbmNsdWRlICJ2aWVuZXVfdjNfb25ueF9pbnRlcm5hbC5oIgoKI2luY2x1ZGUgPGFsZ29yaXRobT4KI2luY2x1ZGUgPGFycmF5PgojaW5jbHVkZSA8Y2hyb25vPgojaW5jbHVkZSA8Y2N0eXBlPgojaW5jbHVkZSA8Y3N0ZGxpYj4KI2luY2x1ZGUgPHN0cmluZz4KI2luY2x1ZGUgPHZlY3Rvcj4KI2luY2x1ZGUgPHN0ZGV4Y2VwdD4KCi8vIC0tLSBWaWVuZXVWM09ubnhFbmdpbmUgSW5mZXJlbmNlIE1lbWJlciBGdW5jdGlvbnMgLS0tCgpuYW1lc3BhY2UgewoKc3RkOjpzdHJpbmcgYWNvdXN0aWNfYmFja2VuZF9mcm9tX2VudigpIHsKICAgIGNvbnN0IGNoYXIqIHZhbHVlID0gc3RkOjpnZXRlbnYoIlZJRU5FVV9BQ09VU1RJQ19CQUNLRU5EIik7CiAgICBzdGQ6OnN0cmluZyBiYWNrZW5kID0gdmFsdWUgPyBzdGQ6OnN0cmluZyh2YWx1ZSkgOiBzdGQ6OnN0cmluZygib25ueCIpOwogICAgc3RkOjp0cmFuc2Zvcm0oYmFja2VuZC5iZWdpbigpLCBiYWNrZW5kLmVuZCgpLCBiYWNrZW5kLmJlZ2luKCksIFtdKHVuc2lnbmVkIGNoYXIgYykgewogICAgICAgIHJldHVybiBzdGF0aWNfY2FzdDxjaGFyPihzdGQ6OnRvbG93ZXIoYykpOwogICAgfSk7CiAgICByZXR1cm4gYmFja2VuZDsKfQoKfSAvLyBuYW1lc3BhY2UKCmNsYXNzIFZpZW5ldVYzT25ueEVuZ2luZTo6T25ueEFjb3VzdGljRXhlY3V0b3IgZmluYWwgOiBwdWJsaWMgVmllbmV1VjNPbm54RW5naW5lOjpBY291c3RpY0V4ZWN1dG9yIHsKcHVibGljOgogICAgZXhwbGljaXQgT25ueEFjb3VzdGljRXhlY3V0b3IoVmllbmV1VjNPbm54RW5naW5lJiBlbmdpbmUpIDogZW5naW5lXyhlbmdpbmUpIHt9CgogICAgY29uc3QgY2hhciogYmFja2VuZF9uYW1lKCkgY29uc3Qgb3ZlcnJpZGUgewogICAgICAgIHJldHVybiAib25ueCI7CiAgICB9CgogICAgYm9vbCBnZW5lcmF0ZV9mcmFtZShjb25zdCBzdGQ6OnZlY3RvcjxmbG9hdD4mIGgsCiAgICAgICAgICAgICAgICAgICAgICAgIGZsb2F0IHRlbXBlcmF0dXJlLAogICAgICAgICAgICAgICAgICAgICAgICBpbnQgdG9wX2ssCiAgICAgICAgICAgICAgICAgICAgICAgIGZsb2F0IHRvcF9wLAogICAgICAgICAgICAgICAgICAgICAgICBmbG9hdCByZXBldGl0aW9uX3BlbmFsdHksCiAgICAgICAgICAgICAgICAgICAgICAgIHN0ZDo6dmVjdG9yPFYzUmVwZXRpdGlvbkhpc3Rvcnk+JiBoaXN0b3J5LAogICAgICAgICAgICAgICAgICAgICAgICBzdGQ6OnZlY3RvcjxpbnQ2NF90PiYgY29kZXMsCiAgICAgICAgICAgICAgICAgICAgICAgIGJvb2wmIGVvcywKICAgICAgICAgICAgICAgICAgICAgICAgc3RkOjpzdHJpbmcmIGVycm9yKSBvdmVycmlkZSB7CiAgICAgICAgcmV0dXJuIGVuZ2luZV8uYWNvdXN0aWNfZnJhbWVfb25ueCgKICAgICAgICAgICAgaCwKICAgICAgICAgICAgdGVtcGVyYXR1cmUsCiAgICAgICAgICAgIHRvcF9rLAogICAgICAgICAgICB0b3BfcCwKICAgICAgICAgICAgcmVwZXRpdGlvbl9wZW5hbHR5LAogICAgICAgICAgICBoaXN0b3J5LAogICAgICAgICAgICBjb2RlcywKICAgICAgICAgICAgZW9zLAogICAgICAgICAgICBlcnJvcik7CiAgICB9Cgpwcml2YXRlOgogICAgVmllbmV1VjNPbm54RW5naW5lJiBlbmdpbmVfOwp9OwoKYm9vbCBWaWVuZXVWM09ubnhFbmdpbmU6OmluaXRpYWxpemVfYWNvdXN0aWNfZXhlY3V0b3Ioc3RkOjpzdHJpbmcmIGVycm9yKSB7CiAgICBjb25zdCBzdGQ6OnN0cmluZyBiYWNrZW5kID0gYWNvdXN0aWNfYmFja2VuZF9mcm9tX2VudigpOwogICAgaWYgKGJhY2tlbmQgPT0gImdnbWwiKSB7CiAgICAgICAgcmV0dXJuIGluaXRpYWxpemVfbmF0aXZlX2Fjb3VzdGljX2V4ZWN1dG9yKGVycm9yKTsKICAgIH0KICAgIGlmIChiYWNrZW5kICE9ICJvbm54IikgewogICAgICAgIGVycm9yID0gIlVuc3VwcG9ydGVkIFZJRU5FVV9BQ09VU1RJQ19CQUNLRU5EIHZhbHVlOiAiICsgYmFja2VuZCArICIgKHN1cHBvcnRlZDogb25ueCwgZ2dtbCkuIjsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CiAgICBpZiAoIWFjb3VzdGljX3Nlc3Npb25fKSB7CiAgICAgICAgZXJyb3IgPSAiVmllTmV1IHYzIGFjb3VzdGljIE9OTlggc2Vzc2lvbiBpcyBub3QgaW5pdGlhbGl6ZWQuIjsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CiAgICBhY291c3RpY19leGVjdXRvcl8gPSBzdGQ6Om1ha2VfdW5pcXVlPE9ubnhBY291c3RpY0V4ZWN1dG9yPigqdGhpcyk7CiAgICByZXR1cm4gdHJ1ZTsKfQoKVmllbmV1VjNPbm54RW5naW5lOjpQcm9tcHRSb3dzIFZpZW5ldVYzT25ueEVuZ2luZTo6YnVpbGRfcm93cygKICAgIGNvbnN0IHN0ZDo6c3RyaW5nJiBwaG9uZW1lcywKICAgIGNvbnN0IHN0ZDo6dmVjdG9yPGludDY0X3Q+KiByZWZfY29kZXMsCiAgICBpbnQgbGVhZGluZ190b2tlbikgY29uc3QgewogICAgY29uc3Qgc3RkOjp2ZWN0b3I8aW50NjRfdD4gcGhvbmVfaWRzID0gdG9rZW5pemVyXy5lbmNvZGUocGhvbmVtZXMpOwogICAgY29uc3QgaW50NjRfdCBjb2xzID0gY29uZmlnXy5uX3ZxICsgMTsKICAgIGNvbnN0IGludDY0X3QgdGV4dF9yb3dzID0gc3RhdGljX2Nhc3Q8aW50NjRfdD4ocGhvbmVfaWRzLnNpemUoKSkgKyAzOwogICAgY29uc3QgaW50NjRfdCByZWZfcm93cyA9IHJlZl9jb2RlcyA/IHN0YXRpY19jYXN0PGludDY0X3Q+KHJlZl9jb2Rlcy0+c2l6ZSgpIC8gY29uZmlnXy5uX3ZxKSA6IDA7CiAgICBQcm9tcHRSb3dzIHJvd3M7CiAgICByb3dzLnJvd3MgPSB0ZXh0X3Jvd3MgKyByZWZfcm93czsKICAgIHJvd3MuY29scyA9IGNvbHM7CiAgICByb3dzLmRhdGEuYXNzaWduKHN0YXRpY19jYXN0PHNpemVfdD4ocm93cy5yb3dzICogcm93cy5jb2xzKSwgY29uZmlnXy5hdWRpb19wYWRfdG9rZW5faWQpOwogICAgcm93cy5kYXRhWzBdID0gbGVhZGluZ190b2tlbjsKICAgIHJvd3MuZGF0YVtjb2xzXSA9IGNvbmZpZ18udGV4dF9wcm9tcHRfc3RhcnRfdG9rZW5faWQ7CiAgICBmb3IgKHNpemVfdCBpID0gMDsgaSA8IHBob25lX2lkcy5zaXplKCk7ICsraSkgewogICAgICAgIHJvd3MuZGF0YVtzdGF0aWNfY2FzdDxzaXplX3Q+KChzdGF0aWNfY2FzdDxpbnQ2NF90PihpKSArIDIpICogY29scyldID0gcGhvbmVfaWRzW2ldOwogICAgfQogICAgcm93cy5kYXRhW3N0YXRpY19jYXN0PHNpemVfdD4oKHRleHRfcm93cyAtIDEpICogY29scyldID0gY29uZmlnXy50ZXh0X3Byb21wdF9lbmRfdG9rZW5faWQ7CiAgICBpZiAocmVmX2NvZGVzKSB7CiAgICAgICAgZm9yIChpbnQ2NF90IHIgPSAwOyByIDwgcmVmX3Jvd3M7ICsrcikgewogICAgICAgICAgICBjb25zdCBpbnQ2NF90IGRzdF9yb3cgPSB0ZXh0X3Jvd3MgKyByOwogICAgICAgICAgICByb3dzLmRhdGFbc3RhdGljX2Nhc3Q8c2l6ZV90Pihkc3Rfcm93ICogY29scyldID0gY29uZmlnXy5hdWRpb19yZWZfc2xvdF90b2tlbl9pZDsKICAgICAgICAgICAgZm9yIChpbnQgY2ggPSAwOyBjaCA8IGNvbmZpZ18ubl92cTsgKytjaCkgewogICAgICAgICAgICAgICAgcm93cy5kYXRhW3N0YXRpY19jYXN0PHNpemVfdD4oZHN0X3JvdyAqIGNvbHMgKyBjaCArIDEpXSA9CiAgICAgICAgICAgICAgICAgICAgKCpyZWZfY29kZXMpW3N0YXRpY19jYXN0PHNpemVfdD4ociAqIGNvbmZpZ18ubl92cSArIGNoKV07CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gcm93czsKfQoKc3RkOjp2ZWN0b3I8ZmxvYXQ+IFZpZW5ldVYzT25ueEVuZ2luZTo6ZW1iZWRfcm93cyhjb25zdCBQcm9tcHRSb3dzJiByb3dzLCBjb25zdCBzdGQ6OnZlY3RvcjxmbG9hdD4qIGFuY2hvcikgY29uc3QgewogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGVtYmVkcyhzdGF0aWNfY2FzdDxzaXplX3Q+KHJvd3Mucm93cyAqIGNvbmZpZ18uaGlkZGVuX3NpemUpLCAwLjBmKTsKICAgIGZvciAoaW50NjRfdCByID0gMDsgciA8IHJvd3Mucm93czsgKytyKSB7CiAgICAgICAgZmxvYXQqIGRzdCA9IGVtYmVkcy5kYXRhKCkgKyByICogY29uZmlnXy5oaWRkZW5fc2l6ZTsKICAgICAgICBjb25zdCBpbnQ2NF90IHRleHRfaWQgPSByb3dzLmRhdGFbc3RhdGljX2Nhc3Q8c2l6ZV90PihyICogcm93cy5jb2xzKV07CiAgICAgICAgaWYgKHRleHRfaWQgPj0gMCAmJiB0ZXh0X2lkIDwgdGV4dF9lbWJfLnJvd3MpIHsKICAgICAgICAgICAgY29uc3QgZmxvYXQqIHNyYyA9IHRleHRfZW1iXy5kYXRhLmRhdGEoKSArIHRleHRfaWQgKiB0ZXh0X2VtYl8uY29sczsKICAgICAgICAgICAgc3RkOjpjb3B5KHNyYywgc3JjICsgY29uZmlnXy5oaWRkZW5fc2l6ZSwgZHN0KTsKICAgICAgICB9CiAgICAgICAgZm9yIChpbnQgY2ggPSAwOyBjaCA8IGNvbmZpZ18ubl92cTsgKytjaCkgewogICAgICAgICAgICBjb25zdCBpbnQ2NF90IGlkID0gcm93cy5kYXRhW3N0YXRpY19jYXN0PHNpemVfdD4ociAqIHJvd3MuY29scyArIGNoICsgMSldOwogICAgICAgICAgICBpZiAoaWQgPT0gY29uZmlnXy5hdWRpb19wYWRfdG9rZW5faWQgfHwgaWQgPCAwIHx8IGlkID49IGF1ZGlvX2VtYl8uZGltMSkgewogICAgICAgICAgICAgICAgY29udGludWU7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgY29uc3QgZmxvYXQqIHNyYyA9IGF1ZGlvX2VtYl8uZGF0YS5kYXRhKCkgKwogICAgICAgICAgICAgICAgKHN0YXRpY19jYXN0PGludDY0X3Q+KGNoKSAqIGF1ZGlvX2VtYl8uZGltMSArIGlkKSAqIGF1ZGlvX2VtYl8uZGltMjsKICAgICAgICAgICAgZm9yIChpbnQgaCA9IDA7IGggPCBjb25maWdfLmhpZGRlbl9zaXplOyArK2gpIHsKICAgICAgICAgICAgICAgIGRzdFtoXSArPSBzcmNbaF07CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgLy8gUEFUQ0ggRklYNDk6IHNwZWFrZXIgYW5jaG9yIGlzIGFkZGVkIHRvIEVWRVJZIHJvdyAobWlycm9yCiAgICAgICAgLy8gX2VtYmVkX3Jvd3Mocm93cywgYW5jaG9yKSBpbiBvbm54X3J1bnRpbWVfbGl0ZS5weSkuCiAgICAgICAgaWYgKGFuY2hvciAmJiBhbmNob3ItPnNpemUoKSA9PSBzdGF0aWNfY2FzdDxzaXplX3Q+KGNvbmZpZ18uaGlkZGVuX3NpemUpKSB7CiAgICAgICAgICAgIGZvciAoaW50IGggPSAwOyBoIDwgY29uZmlnXy5oaWRkZW5fc2l6ZTsgKytoKSB7CiAgICAgICAgICAgICAgICBkc3RbaF0gKz0gKCphbmNob3IpW3N0YXRpY19jYXN0PHNpemVfdD4oaCldOwogICAgICAgICAgICB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuIGVtYmVkczsKfQoKYm9vbCBWaWVuZXVWM09ubnhFbmdpbmU6OmFjb3VzdGljX2ZyYW1lKAogICAgY29uc3Qgc3RkOjp2ZWN0b3I8ZmxvYXQ+JiBoLAogICAgZmxvYXQgdGVtcGVyYXR1cmUsCiAgICBpbnQgdG9wX2ssCiAgICBmbG9hdCB0b3BfcCwKICAgIGZsb2F0IHJlcGV0aXRpb25fcGVuYWx0eSwKICAgIHN0ZDo6dmVjdG9yPFYzUmVwZXRpdGlvbkhpc3Rvcnk+JiBoaXN0b3J5LAogICAgc3RkOjp2ZWN0b3I8aW50NjRfdD4mIGNvZGVzLAogICAgYm9vbCYgZW9zLAogICAgc3RkOjpzdHJpbmcmIGVycm9yKSB7CiAgICBpZiAoIWFjb3VzdGljX2V4ZWN1dG9yXykgewogICAgICAgIGVycm9yID0gIlZpZU5ldSB2MyBhY291c3RpYyBleGVjdXRvciBpcyBub3QgaW5pdGlhbGl6ZWQuIjsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CiAgICByZXR1cm4gYWNvdXN0aWNfZXhlY3V0b3JfLT5nZW5lcmF0ZV9mcmFtZSgKICAgICAgICBoLAogICAgICAgIHRlbXBlcmF0dXJlLAogICAgICAgIHRvcF9rLAogICAgICAgIHRvcF9wLAogICAgICAgIHJlcGV0aXRpb25fcGVuYWx0eSwKICAgICAgICBoaXN0b3J5LAogICAgICAgIGNvZGVzLAogICAgICAgIGVvcywKICAgICAgICBlcnJvcik7Cn0KCmJvb2wgVmllbmV1VjNPbm54RW5naW5lOjphY291c3RpY19mcmFtZV9vbm54KAogICAgY29uc3Qgc3RkOjp2ZWN0b3I8ZmxvYXQ+JiBoLAogICAgZmxvYXQgdGVtcGVyYXR1cmUsCiAgICBpbnQgdG9wX2ssCiAgICBmbG9hdCB0b3BfcCwKICAgIGZsb2F0IHJlcGV0aXRpb25fcGVuYWx0eSwKICAgIHN0ZDo6dmVjdG9yPFYzUmVwZXRpdGlvbkhpc3Rvcnk+JiBoaXN0b3J5LAogICAgc3RkOjp2ZWN0b3I8aW50NjRfdD4mIGNvZGVzLAogICAgYm9vbCYgZW9zLAogICAgc3RkOjpzdHJpbmcmIGVycm9yKSB7CiAgICBjb25zdCBhdXRvIGZyYW1lX3N0YXJ0ID0gYmVuY2htYXJrX2VuYWJsZWRfID8gc3RkOjpjaHJvbm86OnN0ZWFkeV9jbG9jazo6bm93KCkgOiBzdGQ6OmNocm9ubzo6c3RlYWR5X2Nsb2NrOjp0aW1lX3BvaW50e307CiAgICB0cnkgewogICAgICAgIGNvbnN0IGludCBIID0gY29uZmlnXy5oaWRkZW5fc2l6ZTsKICAgICAgICBjb25zdCBpbnQgbkggPSBjb25maWdfLmxvY2FsX251bV9hdHRlbnRpb25faGVhZHM7CiAgICAgICAgY29uc3QgaW50IGhkID0gSCAvIG5IOwogICAgICAgIGFjb3VzdGljX3Rva2VuXy5yZXNpemUoc3RhdGljX2Nhc3Q8c2l6ZV90PigyICogSCkpOwogICAgICAgIHN0ZDo6Y29weShoLmJlZ2luKCksIGguYmVnaW4oKSArIEgsIGFjb3VzdGljX3Rva2VuXy5iZWdpbigpKTsKICAgICAgICBjb25zdCBmbG9hdCogc2dzID0gdGV4dF9lbWJfLmRhdGEuZGF0YSgpICsgY29uZmlnXy5zcGVlY2hfZ2VuZXJhdGlvbl9zdGFydF90b2tlbl9pZCAqIHRleHRfZW1iXy5jb2xzOwogICAgICAgIHN0ZDo6Y29weShzZ3MsIHNncyArIEgsIGFjb3VzdGljX3Rva2VuXy5iZWdpbigpICsgSCk7CiAgICAgICAgc3RkOjphcnJheTxpbnQ2NF90LCAyPiBwb3MgPSB7MCwgMX07CiAgICAgICAgYWNvdXN0aWNfZW1wdHlfLmNsZWFyKCk7CiAgICAgICAgc3RkOjphcnJheTxpbnQ2NF90LCA0PiBlbXB0eV9zaGFwZSA9IHsxLCBuSCwgMCwgaGR9OwogICAgICAgIHN0ZDo6YXJyYXk8aW50NjRfdCwgMz4gdG9rZW5fc2hhcGUgPSB7MSwgMiwgSH07CiAgICAgICAgc3RkOjphcnJheTxpbnQ2NF90LCAyPiBwb3Nfc2hhcGUgPSB7MSwgMn07CgogICAgICAgIE9ydDo6TWVtb3J5SW5mbyYgbWVtID0gY3B1X21lbW9yeV9pbmZvKCk7CiAgICAgICAgLy8gUEFUQ0ggRklYNDk6IHBhcmFtZXRlcml6ZSBLViBkZXB0aCBieSBsb2NhbF9udW1faGlkZGVuX2xheWVycwogICAgICAgIC8vICh0dXJibyA9IDIgLT4gNiBpbi81IG91dDsgdXBkYXRlICsgaW50OCA9IDEgLT4gNCBpbi8zIG91dCkuCiAgICAgICAgY29uc3QgaW50IGxfbG9jID0gY29uZmlnXy5sb2NhbF9udW1faGlkZGVuX2xheWVycyA+IDAgPyBjb25maWdfLmxvY2FsX251bV9oaWRkZW5fbGF5ZXJzIDogMTsKICAgICAgICBjb25zdCBzaXplX3QgZXhwZWN0ZWRfaW4gPSAyICsgMiAqIHN0YXRpY19jYXN0PHNpemVfdD4obF9sb2MpOwogICAgICAgIGNvbnN0IHNpemVfdCBleHBlY3RlZF9vdXQgPSAxICsgMiAqIHN0YXRpY19jYXN0PHNpemVfdD4obF9sb2MpOwogICAgICAgIGlmIChhY291c3RpY19pb18uaW5wdXRfbmFtZXMuc2l6ZSgpICE9IGV4cGVjdGVkX2luIHx8IGFjb3VzdGljX2lvXy5vdXRwdXRfbmFtZXMuc2l6ZSgpICE9IGV4cGVjdGVkX291dCkgewogICAgICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgYWNvdXN0aWMgT05OWCBzaWduYXR1cmUgbWlzbWF0Y2g6IGV4cGVjdGVkICIgKyBzdGQ6OnRvX3N0cmluZyhleHBlY3RlZF9pbikgKwogICAgICAgICAgICAgICAgICAgICIgaW5wdXRzIGFuZCAiICsgc3RkOjp0b19zdHJpbmcoZXhwZWN0ZWRfb3V0KSArICIgb3V0cHV0cy4iOwogICAgICAgICAgICByZXR1cm4gZmFsc2U7CiAgICAgICAgfQogICAgICAgIGFjb3VzdGljX2lucHV0c18uY2xlYXIoKTsKICAgICAgICBhY291c3RpY19pbnB1dHNfLnJlc2VydmUoZXhwZWN0ZWRfaW4pOwogICAgICAgIGFjb3VzdGljX2lucHV0c18uZW1wbGFjZV9iYWNrKE9ydDo6VmFsdWU6OkNyZWF0ZVRlbnNvcjxmbG9hdD4obWVtLCBhY291c3RpY190b2tlbl8uZGF0YSgpLCBhY291c3RpY190b2tlbl8uc2l6ZSgpLCB0b2tlbl9zaGFwZS5kYXRhKCksIHRva2VuX3NoYXBlLnNpemUoKSkpOwogICAgICAgIGFjb3VzdGljX2lucHV0c18uZW1wbGFjZV9iYWNrKE9ydDo6VmFsdWU6OkNyZWF0ZVRlbnNvcjxpbnQ2NF90PihtZW0sIHBvcy5kYXRhKCksIHBvcy5zaXplKCksIHBvc19zaGFwZS5kYXRhKCksIHBvc19zaGFwZS5zaXplKCkpKTsKICAgICAgICBmb3IgKHNpemVfdCBpID0gMDsgaSA8IDIgKiBzdGF0aWNfY2FzdDxzaXplX3Q+KGxfbG9jKTsgKytpKSB7CiAgICAgICAgICAgIGFjb3VzdGljX2lucHV0c18uZW1wbGFjZV9iYWNrKE9ydDo6VmFsdWU6OkNyZWF0ZVRlbnNvcjxmbG9hdD4obWVtLCBhY291c3RpY19lbXB0eV8uZGF0YSgpLCAwLCBlbXB0eV9zaGFwZS5kYXRhKCksIGVtcHR5X3NoYXBlLnNpemUoKSkpOwogICAgICAgIH0KICAgICAgICBjb25zdCBPcnQ6OlJ1bk9wdGlvbnMgcnVuX29wdGlvbnN7bnVsbHB0cn07CiAgICAgICAgYXV0byBvdXQgPSBhY291c3RpY19zZXNzaW9uXy0+UnVuKAogICAgICAgICAgICBydW5fb3B0aW9ucywKICAgICAgICAgICAgYWNvdXN0aWNfaW9fLmlucHV0X3B0cnMuZGF0YSgpLAogICAgICAgICAgICBhY291c3RpY19pbnB1dHNfLmRhdGEoKSwKICAgICAgICAgICAgYWNvdXN0aWNfaW5wdXRzXy5zaXplKCksCiAgICAgICAgICAgIGFjb3VzdGljX2lvXy5vdXRwdXRfcHRycy5kYXRhKCksCiAgICAgICAgICAgIGFjb3VzdGljX2lvXy5vdXRwdXRfcHRycy5zaXplKCkpOwogICAgICAgIE9ydDo6VmFsdWUgaGlkZGVuX3ZhbCA9IHN0ZDo6bW92ZShvdXRbMF0pOwogICAgICAgIGFjb3VzdGljX3BrXy5jbGVhcigpOwogICAgICAgIGFjb3VzdGljX3B2Xy5jbGVhcigpOwogICAgICAgIGZvciAoc2l6ZV90IGkgPSAwOyBpIDwgc3RhdGljX2Nhc3Q8c2l6ZV90PihsX2xvYyk7ICsraSkgewogICAgICAgICAgICBhY291c3RpY19wa18uZW1wbGFjZV9iYWNrKG51bGxwdHIpOwogICAgICAgICAgICBhY291c3RpY19wdl8uZW1wbGFjZV9iYWNrKG51bGxwdHIpOwogICAgICAgIH0KICAgICAgICBmb3IgKHNpemVfdCBpID0gMDsgaSA8IHN0YXRpY19jYXN0PHNpemVfdD4obF9sb2MpOyArK2kpIHsKICAgICAgICAgICAgYWNvdXN0aWNfcGtfW2ldID0gc3RkOjptb3ZlKG91dFsxICsgaV0pOwogICAgICAgIH0KICAgICAgICBmb3IgKHNpemVfdCBpID0gMDsgaSA8IHN0YXRpY19jYXN0PHNpemVfdD4obF9sb2MpOyArK2kpIHsKICAgICAgICAgICAgYWNvdXN0aWNfcHZfW2ldID0gc3RkOjptb3ZlKG91dFsxICsgc3RhdGljX2Nhc3Q8c2l6ZV90PihsX2xvYykgKyBpXSk7CiAgICAgICAgfQoKICAgICAgICBjb25zdCBmbG9hdCogaGlkZGVuX3B0ciA9IGhpZGRlbl92YWwuR2V0VGVuc29yRGF0YTxmbG9hdD4oKTsKICAgICAgICBhY291c3RpY19zbG90MF8uYXNzaWduKGhpZGRlbl9wdHIsIGhpZGRlbl9wdHIgKyBIKTsKCiAgICAgICAgYXV0byBzYW1wbGVfY2hhbm5lbCA9IFsmXShpbnQgY2gsIGNvbnN0IGZsb2F0KiB2ZWMpIHsKICAgICAgICAgICAgY29uc3QgZmxvYXQqIGhlYWQgPSBhdWRpb19lbWJfdF8uZGF0YS5kYXRhKCkgKyBzdGF0aWNfY2FzdDxpbnQ2NF90PihjaCkgKiBhdWRpb19lbWJfdF8uZGltMSAqIGF1ZGlvX2VtYl90Xy5kaW0yOwogICAgICAgICAgICBtYXR2ZWNfdHJhbnNwb3NlZCh2ZWMsIGhlYWQsIGF1ZGlvX2VtYl90Xy5kaW0xLCBhdWRpb19lbWJfdF8uZGltMiwgYWNvdXN0aWNfbG9naXRzXyk7CiAgICAgICAgICAgIFYzUmVwZXRpdGlvbkhpc3RvcnkqIHByZXYgPSBoaXN0b3J5LmVtcHR5KCkgPyBudWxscHRyIDogJmhpc3Rvcnlbc3RhdGljX2Nhc3Q8c2l6ZV90PihjaCldOwogICAgICAgICAgICBpbnQ2NF90IGNvZGUgPSBzYW1wbGVfbG9naXRzKGFjb3VzdGljX2xvZ2l0c18sIHRlbXBlcmF0dXJlLCB0b3BfaywgdG9wX3AsIHJlcGV0aXRpb25fcGVuYWx0eSwgcHJldik7CiAgICAgICAgICAgIGlmIChwcmV2KSBwcmV2LT5hZGQoc3RhdGljX2Nhc3Q8aW50MzJfdD4oY29kZSkpOwogICAgICAgICAgICByZXR1cm4gY29kZTsKICAgICAgICB9OwoKICAgICAgICBjb2Rlcy5jbGVhcigpOwogICAgICAgIGNvZGVzLnJlc2VydmUoc3RhdGljX2Nhc3Q8c2l6ZV90Pihjb25maWdfLm5fdnEpKTsKICAgICAgICBjb2Rlcy5wdXNoX2JhY2soc2FtcGxlX2NoYW5uZWwoMCwgaGlkZGVuX3B0ciArIEgpKTsKICAgICAgICBmb3IgKGludCBjaCA9IDE7IGNoIDwgY29uZmlnXy5uX3ZxOyArK2NoKSB7CiAgICAgICAgICAgIGNvbnN0IGZsb2F0KiBlbWIgPSBhdWRpb19lbWJfLmRhdGEuZGF0YSgpICsKICAgICAgICAgICAgICAgIChzdGF0aWNfY2FzdDxpbnQ2NF90PihjaCAtIDEpICogYXVkaW9fZW1iXy5kaW0xICsgY29kZXMuYmFjaygpKSAqIGF1ZGlvX2VtYl8uZGltMjsKICAgICAgICAgICAgaW50NjRfdCBzdGVwX3BvcyA9IGNoICsgMTsKICAgICAgICAgICAgc3RkOjphcnJheTxpbnQ2NF90LCAzPiBzdGVwX3Rva2VuX3NoYXBlID0gezEsIDEsIEh9OwogICAgICAgICAgICBzdGQ6OmFycmF5PGludDY0X3QsIDI+IHN0ZXBfcG9zX3NoYXBlID0gezEsIDF9OwogICAgICAgICAgICBhY291c3RpY19zdGVwX2lucHV0c18uY2xlYXIoKTsKICAgICAgICAgICAgYWNvdXN0aWNfc3RlcF9pbnB1dHNfLnJlc2VydmUoZXhwZWN0ZWRfaW4pOwogICAgICAgICAgICBhY291c3RpY19zdGVwX2lucHV0c18uZW1wbGFjZV9iYWNrKE9ydDo6VmFsdWU6OkNyZWF0ZVRlbnNvcjxmbG9hdD4obWVtLCBjb25zdF9jYXN0PGZsb2F0Kj4oZW1iKSwgc3RhdGljX2Nhc3Q8c2l6ZV90PihIKSwgc3RlcF90b2tlbl9zaGFwZS5kYXRhKCksIHN0ZXBfdG9rZW5fc2hhcGUuc2l6ZSgpKSk7CiAgICAgICAgICAgIGFjb3VzdGljX3N0ZXBfaW5wdXRzXy5lbXBsYWNlX2JhY2soT3J0OjpWYWx1ZTo6Q3JlYXRlVGVuc29yPGludDY0X3Q+KG1lbSwgJnN0ZXBfcG9zLCAxLCBzdGVwX3Bvc19zaGFwZS5kYXRhKCksIHN0ZXBfcG9zX3NoYXBlLnNpemUoKSkpOwogICAgICAgICAgICBmb3IgKHNpemVfdCBpID0gMDsgaSA8IHN0YXRpY19jYXN0PHNpemVfdD4obF9sb2MpOyArK2kpIHsKICAgICAgICAgICAgICAgIGFjb3VzdGljX3N0ZXBfaW5wdXRzXy5wdXNoX2JhY2soc3RkOjptb3ZlKGFjb3VzdGljX3BrX1tpXSkpOwogICAgICAgICAgICB9CiAgICAgICAgICAgIGZvciAoc2l6ZV90IGkgPSAwOyBpIDwgc3RhdGljX2Nhc3Q8c2l6ZV90PihsX2xvYyk7ICsraSkgewogICAgICAgICAgICAgICAgYWNvdXN0aWNfc3RlcF9pbnB1dHNfLnB1c2hfYmFjayhzdGQ6Om1vdmUoYWNvdXN0aWNfcHZfW2ldKSk7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgYXV0byBzdGVwX291dCA9IGFjb3VzdGljX3Nlc3Npb25fLT5SdW4oCiAgICAgICAgICAgICAgICBydW5fb3B0aW9ucywKICAgICAgICAgICAgICAgIGFjb3VzdGljX2lvXy5pbnB1dF9wdHJzLmRhdGEoKSwKICAgICAgICAgICAgICAgIGFjb3VzdGljX3N0ZXBfaW5wdXRzXy5kYXRhKCksCiAgICAgICAgICAgICAgICBhY291c3RpY19zdGVwX2lucHV0c18uc2l6ZSgpLAogICAgICAgICAgICAgICAgYWNvdXN0aWNfaW9fLm91dHB1dF9wdHJzLmRhdGEoKSwKICAgICAgICAgICAgICAgIGFjb3VzdGljX2lvXy5vdXRwdXRfcHRycy5zaXplKCkpOwogICAgICAgICAgICBoaWRkZW5fdmFsID0gc3RkOjptb3ZlKHN0ZXBfb3V0WzBdKTsKICAgICAgICAgICAgZm9yIChzaXplX3QgaSA9IDA7IGkgPCBzdGF0aWNfY2FzdDxzaXplX3Q+KGxfbG9jKTsgKytpKSB7CiAgICAgICAgICAgICAgICBhY291c3RpY19wa19baV0gPSBzdGQ6Om1vdmUoc3RlcF9vdXRbMSArIGldKTsKICAgICAgICAgICAgfQogICAgICAgICAgICBmb3IgKHNpemVfdCBpID0gMDsgaSA8IHN0YXRpY19jYXN0PHNpemVfdD4obF9sb2MpOyArK2kpIHsKICAgICAgICAgICAgICAgIGFjb3VzdGljX3B2X1tpXSA9IHN0ZDo6bW92ZShzdGVwX291dFsxICsgc3RhdGljX2Nhc3Q8c2l6ZV90PihsX2xvYykgKyBpXSk7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgCiAgICAgICAgICAgIGNvbnN0IGZsb2F0KiBzdGVwX2hpZGRlbl9wdHIgPSBoaWRkZW5fdmFsLkdldFRlbnNvckRhdGE8ZmxvYXQ+KCk7CiAgICAgICAgICAgIGNvZGVzLnB1c2hfYmFjayhzYW1wbGVfY2hhbm5lbChjaCwgc3RlcF9oaWRkZW5fcHRyKSk7CiAgICAgICAgfQoKICAgICAgICBtYXR2ZWNfdHJhbnNwb3NlZChhY291c3RpY19zbG90MF8uZGF0YSgpLCB0ZXh0X2VtYl90Xy5kYXRhLmRhdGEoKSwgdGV4dF9lbWJfdF8ucm93cywgdGV4dF9lbWJfdF8uY29scywgYWNvdXN0aWNfdGV4dF9sb2dpdHNfKTsKICAgICAgICBlb3MgPSBzdGF0aWNfY2FzdDxpbnQ+KHN0ZDo6ZGlzdGFuY2UoYWNvdXN0aWNfdGV4dF9sb2dpdHNfLmJlZ2luKCksIHN0ZDo6bWF4X2VsZW1lbnQoYWNvdXN0aWNfdGV4dF9sb2dpdHNfLmJlZ2luKCksIGFjb3VzdGljX3RleHRfbG9naXRzXy5lbmQoKSkpKSA9PQogICAgICAgICAgICAgIGNvbmZpZ18uc3BlZWNoX2dlbmVyYXRpb25fZW5kX3Rva2VuX2lkOwogICAgICAgIGlmIChiZW5jaG1hcmtfZW5hYmxlZF8pIHsKICAgICAgICAgICAgY29uc3QgYXV0byBmcmFtZV9lbmQgPSBzdGQ6OmNocm9ubzo6c3RlYWR5X2Nsb2NrOjpub3coKTsKICAgICAgICAgICAgYmVuY2htYXJrX3N0YXRzXy5hY291c3RpY19mcmFtZV9tcyArPSBzdGQ6OmNocm9ubzo6ZHVyYXRpb248ZG91YmxlLCBzdGQ6Om1pbGxpPihmcmFtZV9lbmQgLSBmcmFtZV9zdGFydCkuY291bnQoKTsKICAgICAgICAgICAgYmVuY2htYXJrX3N0YXRzXy5hY291c3RpY19mcmFtZV9jYWxscyArPSAxOwogICAgICAgIH0KICAgICAgICByZXR1cm4gdHJ1ZTsKICAgIH0gY2F0Y2ggKGNvbnN0IHN0ZDo6ZXhjZXB0aW9uJiBlKSB7CiAgICAgICAgaWYgKGJlbmNobWFya19lbmFibGVkXykgewogICAgICAgICAgICBjb25zdCBhdXRvIGZyYW1lX2VuZCA9IHN0ZDo6Y2hyb25vOjpzdGVhZHlfY2xvY2s6Om5vdygpOwogICAgICAgICAgICBiZW5jaG1hcmtfc3RhdHNfLmFjb3VzdGljX2ZyYW1lX21zICs9IHN0ZDo6Y2hyb25vOjpkdXJhdGlvbjxkb3VibGUsIHN0ZDo6bWlsbGk+KGZyYW1lX2VuZCAtIGZyYW1lX3N0YXJ0KS5jb3VudCgpOwogICAgICAgICAgICBiZW5jaG1hcmtfc3RhdHNfLmFjb3VzdGljX2ZyYW1lX2NhbGxzICs9IDE7CiAgICAgICAgfQogICAgICAgIGVycm9yID0gc3RkOjpzdHJpbmcoIlZpZU5ldSB2MyBhY291c3RpYyBmcmFtZSBmYWlsZWQ6ICIpICsgZS53aGF0KCk7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQp9Cg=='
    'src\vieneu\v3_onnx\vieneu_v3_onnx_engine.cpp' = 'I2luY2x1ZGUgIi4uL3ZpZW5ldV92M19vbm54LmgiCiNpbmNsdWRlICJ2aWVuZXVfdjNfb25ueF9pbnRlcm5hbC5oIgojaW5jbHVkZSAiLi4vdmllbmV1LmgiCgojaW5jbHVkZSA8YWxnb3JpdGhtPgojaW5jbHVkZSA8YXJyYXk+CiNpbmNsdWRlIDxjY3R5cGU+CiNpbmNsdWRlIDxjc3RkbGliPgojaW5jbHVkZSA8Y21hdGg+CiNpbmNsdWRlIDxjaHJvbm8+CiNpbmNsdWRlIDxpb3N0cmVhbT4KI2luY2x1ZGUgPGxpbWl0cz4KI2luY2x1ZGUgPG11dGV4PgojaW5jbHVkZSA8cmFuZG9tPgojaW5jbHVkZSA8c3RkZXhjZXB0PgojaW5jbHVkZSA8c3RyaW5nPgojaW5jbHVkZSA8dW5vcmRlcmVkX21hcD4KI2luY2x1ZGUgPHZlY3Rvcj4KI2luY2x1ZGUgPHRocmVhZD4KCiNpZiBkZWZpbmVkKF9XSU4zMikgJiYgZGVmaW5lZChfX2hhc19pbmNsdWRlKQojaWYgX19oYXNfaW5jbHVkZSgiZG1sX3Byb3ZpZGVyX2ZhY3RvcnkuaCIpCiNpbmNsdWRlICJkbWxfcHJvdmlkZXJfZmFjdG9yeS5oIgojZGVmaW5lIFZJRU5FVV9IQVNfT1JUX0RJUkVDVE1MIDEKI2VuZGlmCiNlbmRpZgoKbmFtZXNwYWNlIHsKCnN0ZDo6c3RyaW5nIGdldGVudl9zdHJpbmcoY29uc3QgY2hhciogbmFtZSkgewogICAgY29uc3QgY2hhciogdmFsdWUgPSBzdGQ6OmdldGVudihuYW1lKTsKICAgIHJldHVybiB2YWx1ZSA/IHN0ZDo6c3RyaW5nKHZhbHVlKSA6IHN0ZDo6c3RyaW5nKCk7Cn0KCnN0ZDo6c3RyaW5nIGxvd2VyY2FzZShzdGQ6OnN0cmluZyB2YWx1ZSkgewogICAgc3RkOjp0cmFuc2Zvcm0odmFsdWUuYmVnaW4oKSwgdmFsdWUuZW5kKCksIHZhbHVlLmJlZ2luKCksIFtdKHVuc2lnbmVkIGNoYXIgYykgewogICAgICAgIHJldHVybiBzdGF0aWNfY2FzdDxjaGFyPihzdGQ6OnRvbG93ZXIoYykpOwogICAgfSk7CiAgICByZXR1cm4gdmFsdWU7Cn0KCmJvb2wgZW52X2VuYWJsZWQoY29uc3QgY2hhciogbmFtZSkgewogICAgY29uc3Qgc3RkOjpzdHJpbmcgdmFsdWUgPSBsb3dlcmNhc2UoZ2V0ZW52X3N0cmluZyhuYW1lKSk7CiAgICByZXR1cm4gIXZhbHVlLmVtcHR5KCkgJiYgdmFsdWUgIT0gIjAiICYmIHZhbHVlICE9ICJmYWxzZSIgJiYgdmFsdWUgIT0gIm9mZiIgJiYgdmFsdWUgIT0gIm5vIjsKfQoKaW50IGVudl9pbnQoY29uc3QgY2hhciogbmFtZSwgaW50IGZhbGxiYWNrKSB7CiAgICBjb25zdCBzdGQ6OnN0cmluZyB2YWx1ZSA9IGdldGVudl9zdHJpbmcobmFtZSk7CiAgICBpZiAodmFsdWUuZW1wdHkoKSkgewogICAgICAgIHJldHVybiBmYWxsYmFjazsKICAgIH0KICAgIHRyeSB7CiAgICAgICAgcmV0dXJuIHN0ZDo6c3RvaSh2YWx1ZSk7CiAgICB9IGNhdGNoICguLi4pIHsKICAgICAgICByZXR1cm4gZmFsbGJhY2s7CiAgICB9Cn0KCkdyYXBoT3B0aW1pemF0aW9uTGV2ZWwgZW52X2dyYXBoX29wdGltaXphdGlvbl9sZXZlbChHcmFwaE9wdGltaXphdGlvbkxldmVsIGZhbGxiYWNrKSB7CiAgICBjb25zdCBzdGQ6OnN0cmluZyB2YWx1ZSA9IGxvd2VyY2FzZShnZXRlbnZfc3RyaW5nKCJWSUVORVVfT1JUX0dSQVBIX09QVF9MRVZFTCIpKTsKICAgIGlmICh2YWx1ZS5lbXB0eSgpKSB7CiAgICAgICAgcmV0dXJuIGZhbGxiYWNrOwogICAgfQogICAgaWYgKHZhbHVlID09ICJkaXNhYmxlIiB8fCB2YWx1ZSA9PSAiZGlzYWJsZWQiIHx8IHZhbHVlID09ICJvZmYiIHx8IHZhbHVlID09ICIwIikgewogICAgICAgIHJldHVybiBHcmFwaE9wdGltaXphdGlvbkxldmVsOjpPUlRfRElTQUJMRV9BTEw7CiAgICB9CiAgICBpZiAodmFsdWUgPT0gImJhc2ljIiB8fCB2YWx1ZSA9PSAiMSIpIHsKICAgICAgICByZXR1cm4gR3JhcGhPcHRpbWl6YXRpb25MZXZlbDo6T1JUX0VOQUJMRV9CQVNJQzsKICAgIH0KICAgIGlmICh2YWx1ZSA9PSAiZXh0ZW5kZWQiIHx8IHZhbHVlID09ICIyIikgewogICAgICAgIHJldHVybiBHcmFwaE9wdGltaXphdGlvbkxldmVsOjpPUlRfRU5BQkxFX0VYVEVOREVEOwogICAgfQogICAgaWYgKHZhbHVlID09ICJhbGwiIHx8IHZhbHVlID09ICIzIikgewogICAgICAgIHJldHVybiBHcmFwaE9wdGltaXphdGlvbkxldmVsOjpPUlRfRU5BQkxFX0FMTDsKICAgIH0KICAgIHJldHVybiBmYWxsYmFjazsKfQoKdm9pZCBhcHBlbmRfb3BlbnZpbm9fZXhlY3V0aW9uX3Byb3ZpZGVyKE9ydDo6U2Vzc2lvbk9wdGlvbnMmIG9wdGlvbnMsIGNvbnN0IHN0ZDo6c3RyaW5nJiBkZXZpY2VfdHlwZSkgewogICAgc3RkOjp1bm9yZGVyZWRfbWFwPHN0ZDo6c3RyaW5nLCBzdGQ6OnN0cmluZz4gb3Zfb3B0aW9ucyA9IHt7ImRldmljZV90eXBlIiwgZGV2aWNlX3R5cGV9fTsKICAgIGNvbnN0IGludCBudW1fdGhyZWFkcyA9IGVudl9pbnQoIlZJRU5FVV9PUlRfT1BFTlZJTk9fTlVNX1RIUkVBRFMiLCAwKTsKICAgIGlmIChudW1fdGhyZWFkcyA+IDApIHsKICAgICAgICBvdl9vcHRpb25zWyJudW1fb2ZfdGhyZWFkcyJdID0gc3RkOjp0b19zdHJpbmcobnVtX3RocmVhZHMpOwogICAgfQogICAgY29uc3QgaW50IG51bV9zdHJlYW1zID0gZW52X2ludCgiVklFTkVVX09SVF9PUEVOVklOT19OVU1fU1RSRUFNUyIsIDApOwogICAgaWYgKG51bV9zdHJlYW1zID4gMCkgewogICAgICAgIG92X29wdGlvbnNbIm51bV9zdHJlYW1zIl0gPSBzdGQ6OnRvX3N0cmluZyhudW1fc3RyZWFtcyk7CiAgICB9CiAgICBjb25zdCBzdGQ6OnN0cmluZyBjYWNoZV9kaXIgPSBnZXRlbnZfc3RyaW5nKCJWSUVORVVfT1JUX09QRU5WSU5PX0NBQ0hFX0RJUiIpOwogICAgaWYgKCFjYWNoZV9kaXIuZW1wdHkoKSkgewogICAgICAgIG92X29wdGlvbnNbImNhY2hlX2RpciJdID0gY2FjaGVfZGlyOwogICAgfQogICAgaWYgKGVudl9lbmFibGVkKCJWSUVORVVfT1JUX09QRU5WSU5PX0RJU0FCTEVfRFlOQU1JQ19TSEFQRVMiKSkgewogICAgICAgIG92X29wdGlvbnNbImRpc2FibGVfZHluYW1pY19zaGFwZXMiXSA9ICJ0cnVlIjsKICAgIH0KICAgIG9wdGlvbnMuQXBwZW5kRXhlY3V0aW9uUHJvdmlkZXJfT3BlblZJTk9fVjIob3Zfb3B0aW9ucyk7Cn0KCnZvaWQgYXBwZW5kX2RpcmVjdG1sX2V4ZWN1dGlvbl9wcm92aWRlcihPcnQ6OlNlc3Npb25PcHRpb25zJiBvcHRpb25zLCBpbnQgZGV2aWNlX2lkKSB7CiNpZiBkZWZpbmVkKFZJRU5FVV9IQVNfT1JUX0RJUkVDVE1MKQogICAgT3J0OjpUaHJvd09uRXJyb3IoT3J0U2Vzc2lvbk9wdGlvbnNBcHBlbmRFeGVjdXRpb25Qcm92aWRlcl9ETUwob3B0aW9ucywgKHN0ZDo6bWF4KSgwLCBkZXZpY2VfaWQpKSk7CiNlbHNlCiAgICAodm9pZClvcHRpb25zOwogICAgKHZvaWQpZGV2aWNlX2lkOwogICAgdGhyb3cgc3RkOjpydW50aW1lX2Vycm9yKCJEaXJlY3RNTCBFUCBpcyBub3QgYXZhaWxhYmxlIGluIHRoaXMgT05OWCBSdW50aW1lIFNESy9idWlsZC4iKTsKI2VuZGlmCn0KCmJvb2wgYXBwZW5kX3JlcXVlc3RlZF9leGVjdXRpb25fcHJvdmlkZXIoT3J0OjpTZXNzaW9uT3B0aW9ucyYgb3B0aW9ucywgc3RkOjpzdHJpbmcmIGVycm9yKSB7CiAgICBjb25zdCBzdGQ6OnN0cmluZyByZXF1ZXN0ZWQgPSBsb3dlcmNhc2UoZ2V0ZW52X3N0cmluZygiVklFTkVVX09SVF9FUCIpKTsKICAgIGlmIChyZXF1ZXN0ZWQuZW1wdHkoKSB8fCByZXF1ZXN0ZWQgPT0gImNwdSIpIHsKICAgICAgICByZXR1cm4gdHJ1ZTsKICAgIH0KCiAgICB0cnkgewogICAgICAgIGlmIChyZXF1ZXN0ZWQgPT0gImN1ZGEiKSB7CiAgICAgICAgICAgIGVycm9yID0gIkNVREEgRVAgaXMgbm90IGF2YWlsYWJsZSBpbiB0aGlzIGJ1aWxkIChIQ1N0dWRpbyBpcyBDUFUtb25seSkuIjsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KCiAgICAgICAgaWYgKHJlcXVlc3RlZCA9PSAib3BlbnZpbm9fY3B1IiB8fCByZXF1ZXN0ZWQgPT0gIm92X2NwdSIpIHsKICAgICAgICAgICAgYXBwZW5kX29wZW52aW5vX2V4ZWN1dGlvbl9wcm92aWRlcihvcHRpb25zLCAiQ1BVIik7CiAgICAgICAgICAgIHJldHVybiB0cnVlOwogICAgICAgIH0KCiAgICAgICAgaWYgKHJlcXVlc3RlZCA9PSAib3BlbnZpbm9fZ3B1IiB8fCByZXF1ZXN0ZWQgPT0gIm92X2dwdSIpIHsKICAgICAgICAgICAgYXBwZW5kX29wZW52aW5vX2V4ZWN1dGlvbl9wcm92aWRlcihvcHRpb25zLCAiR1BVIik7CiAgICAgICAgICAgIHJldHVybiB0cnVlOwogICAgICAgIH0KCiAgICAgICAgaWYgKHJlcXVlc3RlZCA9PSAib3BlbnZpbm8iIHx8IHJlcXVlc3RlZCA9PSAib3YiKSB7CiAgICAgICAgICAgIHN0ZDo6c3RyaW5nIGRldmljZV90eXBlID0gZ2V0ZW52X3N0cmluZygiVklFTkVVX09SVF9PUEVOVklOT19ERVZJQ0VfVFlQRSIpOwogICAgICAgICAgICBpZiAoZGV2aWNlX3R5cGUuZW1wdHkoKSkgewogICAgICAgICAgICAgICAgZGV2aWNlX3R5cGUgPSAiQ1BVIjsKICAgICAgICAgICAgfQogICAgICAgICAgICBhcHBlbmRfb3BlbnZpbm9fZXhlY3V0aW9uX3Byb3ZpZGVyKG9wdGlvbnMsIGRldmljZV90eXBlKTsKICAgICAgICAgICAgcmV0dXJuIHRydWU7CiAgICAgICAgfQoKICAgICAgICBpZiAocmVxdWVzdGVkID09ICJkaXJlY3RtbCIgfHwgcmVxdWVzdGVkID09ICJkbWwiKSB7CiAgICAgICAgICAgIGNvbnN0IGludCBkZXZpY2VfaWQgPSBlbnZfaW50KCJWSUVORVVfT1JUX0RJUkVDVE1MX0RFVklDRV9JRCIsIGVudl9pbnQoIlZJRU5FVV9PUlRfRE1MX0RFVklDRV9JRCIsIDApKTsKICAgICAgICAgICAgYXBwZW5kX2RpcmVjdG1sX2V4ZWN1dGlvbl9wcm92aWRlcihvcHRpb25zLCBkZXZpY2VfaWQpOwogICAgICAgICAgICByZXR1cm4gdHJ1ZTsKICAgICAgICB9CgogICAgICAgIGVycm9yID0gIlVuc3VwcG9ydGVkIFZJRU5FVV9PUlRfRVAgdmFsdWU6ICIgKyByZXF1ZXN0ZWQgKyAiIChzdXBwb3J0ZWQ6IGNwdSwgY3VkYSwgb3BlbnZpbm9fY3B1LCBvcGVudmlub19ncHUsIGRpcmVjdG1sKS4iOwogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0gY2F0Y2ggKGNvbnN0IHN0ZDo6ZXhjZXB0aW9uJiBlKSB7CiAgICAgICAgaWYgKGVudl9lbmFibGVkKCJWSUVORVVfT1JUX0VQX1JFUVVJUkVEIikpIHsKICAgICAgICAgICAgZXJyb3IgPSAiRmFpbGVkIHRvIGVuYWJsZSByZXF1ZXN0ZWQgT05OWCBSdW50aW1lIEVQICciICsgcmVxdWVzdGVkICsgIic6ICIgKyBlLndoYXQoKTsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KICAgICAgICBzdGQ6OmNlcnIgPDwgIltWaWVOZXUgdjNdIEZhaWxlZCB0byBlbmFibGUgT05OWCBSdW50aW1lIEVQICciIDw8IHJlcXVlc3RlZAogICAgICAgICAgICAgICAgICA8PCAiJywgZmFsbGluZyBiYWNrIHRvIENQVTogIiA8PCBlLndoYXQoKSA8PCBzdGQ6OmVuZGw7CiAgICAgICAgcmV0dXJuIHRydWU7CiAgICB9Cn0KCn0gLy8gbmFtZXNwYWNlCgovLyAtLS0gVmllbmV1VjNPbm54RW5naW5lIE9yY2hlc3RyYXRvciBNZW1iZXIgRnVuY3Rpb25zIC0tLQoKdm9pZCBWaWVuZXVWM09ubnhFbmdpbmU6OnJlc2V0X2JlbmNobWFya19zdGF0cygpIHsKICAgIGJlbmNobWFya19zdGF0c18gPSBCZW5jaG1hcmtTdGF0c3t9Owp9Cgp2b2lkIFZpZW5ldVYzT25ueEVuZ2luZTo6cHJpbnRfYmVuY2htYXJrX3N0YXRzKCkgY29uc3QgewogICAgaWYgKCFiZW5jaG1hcmtfZW5hYmxlZF8pIHsKICAgICAgICByZXR1cm47CiAgICB9CgogICAgY29uc3QgYXV0byBhdmcgPSBbXShkb3VibGUgdG90YWxfbXMsIGludDY0X3QgY2FsbHMpIC0+IGRvdWJsZSB7CiAgICAgICAgcmV0dXJuIGNhbGxzID4gMCA/IHRvdGFsX21zIC8gc3RhdGljX2Nhc3Q8ZG91YmxlPihjYWxscykgOiAwLjA7CiAgICB9OwoKICAgIHN0ZDo6Y2VyciA8PCAiW1ZpZU5ldSB2M10gQmVuY2htYXJrIHN1bW1hcnlcbiIKICAgICAgICAgICAgICA8PCAiICBwcmVmaWxsOiB0b3RhbD0iIDw8IGJlbmNobWFya19zdGF0c18ucHJlZmlsbF9tcyA8PCAiIG1zIgogICAgICAgICAgICAgIDw8ICIsIGNhbGxzPSIgPDwgYmVuY2htYXJrX3N0YXRzXy5wcmVmaWxsX2NhbGxzCiAgICAgICAgICAgICAgPDwgIiwgYXZnPSIgPDwgYXZnKGJlbmNobWFya19zdGF0c18ucHJlZmlsbF9tcywgYmVuY2htYXJrX3N0YXRzXy5wcmVmaWxsX2NhbGxzKSA8PCAiIG1zXG4iCiAgICAgICAgICAgICAgPDwgIiAgZGVjb2RlX3N0ZXA6IHRvdGFsPSIgPDwgYmVuY2htYXJrX3N0YXRzXy5kZWNvZGVfc3RlcF9tcyA8PCAiIG1zIgogICAgICAgICAgICAgIDw8ICIsIGNhbGxzPSIgPDwgYmVuY2htYXJrX3N0YXRzXy5kZWNvZGVfc3RlcF9jYWxscwogICAgICAgICAgICAgIDw8ICIsIGF2Zz0iIDw8IGF2ZyhiZW5jaG1hcmtfc3RhdHNfLmRlY29kZV9zdGVwX21zLCBiZW5jaG1hcmtfc3RhdHNfLmRlY29kZV9zdGVwX2NhbGxzKSA8PCAiIG1zXG4iCiAgICAgICAgICAgICAgPDwgIiAgYWNvdXN0aWNfZnJhbWU6IHRvdGFsPSIgPDwgYmVuY2htYXJrX3N0YXRzXy5hY291c3RpY19mcmFtZV9tcyA8PCAiIG1zIgogICAgICAgICAgICAgIDw8ICIsIGNhbGxzPSIgPDwgYmVuY2htYXJrX3N0YXRzXy5hY291c3RpY19mcmFtZV9jYWxscwogICAgICAgICAgICAgIDw8ICIsIGF2Zz0iIDw8IGF2ZyhiZW5jaG1hcmtfc3RhdHNfLmFjb3VzdGljX2ZyYW1lX21zLCBiZW5jaG1hcmtfc3RhdHNfLmFjb3VzdGljX2ZyYW1lX2NhbGxzKSA8PCAiIG1zXG4iCiAgICAgICAgICAgICAgPDwgIiAgY29kZWNfZGVjb2RlOiB0b3RhbD0iIDw8IGJlbmNobWFya19zdGF0c18uY29kZWNfZGVjb2RlX21zIDw8ICIgbXMiCiAgICAgICAgICAgICAgPDwgIiwgY2FsbHM9IiA8PCBiZW5jaG1hcmtfc3RhdHNfLmNvZGVjX2RlY29kZV9jYWxscwogICAgICAgICAgICAgIDw8ICIsIGF2Zz0iIDw8IGF2ZyhiZW5jaG1hcmtfc3RhdHNfLmNvZGVjX2RlY29kZV9tcywgYmVuY2htYXJrX3N0YXRzXy5jb2RlY19kZWNvZGVfY2FsbHMpIDw8ICIgbXNcbiI7Cn0KCmJvb2wgVmllbmV1VjNPbm54RW5naW5lOjppbml0aWFsaXplKGNvbnN0IFZpZW5ldVYzT25ueEluaXQmIGluaXQsIHN0ZDo6c3RyaW5nJiBlcnJvcikgewogICAgaW5pdGlhbGl6ZWRfID0gZmFsc2U7CiAgICBlbnZfLnJlc2V0KCk7CiAgICBwcmVmaWxsX3Nlc3Npb25fLnJlc2V0KCk7CiAgICBkZWNvZGVfc2Vzc2lvbl8ucmVzZXQoKTsKICAgIGFjb3VzdGljX3Nlc3Npb25fLnJlc2V0KCk7CiAgICBjb2RlY19kZWNvZGVfc2Vzc2lvbl8ucmVzZXQoKTsKICAgIGNvZGVjX2VuY29kZV9zZXNzaW9uXy5yZXNldCgpOwogICAgYWNvdXN0aWNfZXhlY3V0b3JfLnJlc2V0KCk7CiAgICBjcHVfbWVtb3J5X2luZm9fLnJlc2V0KCk7CiAgICBzZXNzaW9uX29wdGlvbnNfLnJlc2V0KCk7CiAgICBwcmVmaWxsX2lvXyA9IFNlc3Npb25Jb3t9OwogICAgZGVjb2RlX2lvXyA9IFNlc3Npb25Jb3t9OwogICAgYWNvdXN0aWNfaW9fID0gU2Vzc2lvbklve307CiAgICBjb2RlY19kZWNvZGVfaW9fID0gU2Vzc2lvbklve307CiAgICBjb2RlY19lbmNvZGVfaW9fID0gU2Vzc2lvbklve307CiAgICBjb2RlY19lbmNvZGVfcGF0aF8uY2xlYXIoKTsKICAgIHZvaWNlc19qc29uXy5jbGVhcigpOwogICAgZGVmYXVsdF92b2ljZV9pZF8uY2xlYXIoKTsKICAgIHZvaWNlX3ByZXNldHNfLmNsZWFyKCk7CiAgICBiZW5jaG1hcmtfZW5hYmxlZF8gPSBlbnZfZW5hYmxlZCgiVklFTkVVX0JFTkNITUFSSyIpOwogICAgcm5nXy5zZWVkKHN0ZDo6cmFuZG9tX2RldmljZXt9KCkpOwoKICAgIGlmIChpbml0Lm1vZGVsX2Rpci5lbXB0eSgpICYmIGluaXQub25ueF9kaXIuZW1wdHkoKSkgewogICAgICAgIGVycm9yID0gIlZpZU5ldSB2MyByZXF1aXJlcyBtb2RlbF9kaXIgb3Igb25ueF9kaXIuIjsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CiAgICBpZiAoaW5pdC5jb2RlY19kaXIuZW1wdHkoKSkgewogICAgICAgIGVycm9yID0gIlZpZU5ldSB2MyByZXF1aXJlcyBjb2RlY19kaXIgd2l0aCBNT1NTIE9OTlggY29kZWMgZmlsZXMuIjsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CiAgICBpZiAoIXZhbGlkYXRlX2Fzc2V0cyhpbml0LCBlcnJvcikpIHsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CgogICAgY29uc3Qgc3RkOjpzdHJpbmcgY29uZmlnX3BhdGggPSBpbml0LmNvbmZpZ19wYXRoLmVtcHR5KCkgPyBqb2luX3BhdGgobW9kZWxfZGlyXywgImNvbmZpZy5qc29uIikgOiBpbml0LmNvbmZpZ19wYXRoOwogICAgY29uc3Qgc3RkOjpzdHJpbmcgdG9rZW5pemVyX3BhdGggPSBpbml0LnRva2VuaXplcl9wYXRoLmVtcHR5KCkgPyBqb2luX3BhdGgobW9kZWxfZGlyXywgInRva2VuaXplci5qc29uIikgOiBpbml0LnRva2VuaXplcl9wYXRoOwogICAgaWYgKCFsb2FkX2NvbmZpZyhjb25maWdfcGF0aCwgZXJyb3IpIHx8CiAgICAgICAgIWxvYWRfaGVhZHNfbnB6KGpvaW5fcGF0aChvbm54X2Rpcl8sICJ2aWVuZXVfdjNfaGVhZHMubnB6IiksIGVycm9yKSB8fAogICAgICAgICF0b2tlbml6ZXJfLmxvYWQodG9rZW5pemVyX3BhdGgsIGVycm9yKSkgewogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0KCiAgICBlbnZfID0gc3RkOjptYWtlX3NoYXJlZDxPcnQ6OkVudj4oT1JUX0xPR0dJTkdfTEVWRUxfV0FSTklORywgIlZpZW5ldVYzT25ueCIpOwogICAgc2Vzc2lvbl9vcHRpb25zXyA9IHN0ZDo6bWFrZV91bmlxdWU8T3J0OjpTZXNzaW9uT3B0aW9ucz4oKTsKICAgIHRocmVhZHNfdG9fdXNlXyA9IGVudl9pbnQoIlZJRU5FVV9PUlRfVEhSRUFEUyIsIGluaXQubl90aHJlYWRzKTsKICAgIGlmICh0aHJlYWRzX3RvX3VzZV8gPD0gMCkgewogICAgICAgIHVuc2lnbmVkIGludCBoYXJkd2FyZV90aHJlYWRzID0gc3RkOjp0aHJlYWQ6OmhhcmR3YXJlX2NvbmN1cnJlbmN5KCk7CiAgICAgICAgdGhyZWFkc190b191c2VfID0gaGFyZHdhcmVfdGhyZWFkcyA+IDAgPyAoc3RkOjptYXgpKDEsIHN0YXRpY19jYXN0PGludD4oKHN0ZDo6bWluKShoYXJkd2FyZV90aHJlYWRzIC8gMiwgNHUpKSkgOiA0OwogICAgfQogICAgc2Vzc2lvbl9vcHRpb25zXy0+U2V0SW50cmFPcE51bVRocmVhZHModGhyZWFkc190b191c2VfKTsKICAgIGNvbnN0IGludCBpbnRlcl9vcF90aHJlYWRzID0gZW52X2ludCgiVklFTkVVX09SVF9JTlRFUl9PUF9USFJFQURTIiwgMSk7CiAgICBzZXNzaW9uX29wdGlvbnNfLT5TZXRJbnRlck9wTnVtVGhyZWFkcygoc3RkOjptYXgpKDEsIGludGVyX29wX3RocmVhZHMpKTsKICAgIGNvbnN0IHN0ZDo6c3RyaW5nIGV4ZWN1dGlvbl9tb2RlID0gbG93ZXJjYXNlKGdldGVudl9zdHJpbmcoIlZJRU5FVV9PUlRfRVhFQ1VUSU9OX01PREUiKSk7CiAgICBpZiAoZXhlY3V0aW9uX21vZGUgPT0gInBhcmFsbGVsIikgewogICAgICAgIHNlc3Npb25fb3B0aW9uc18tPlNldEV4ZWN1dGlvbk1vZGUoT1JUX1BBUkFMTEVMKTsKICAgIH0gZWxzZSB7CiAgICAgICAgc2Vzc2lvbl9vcHRpb25zXy0+U2V0RXhlY3V0aW9uTW9kZShPUlRfU0VRVUVOVElBTCk7CiAgICB9CiAgICBzZXNzaW9uX29wdGlvbnNfLT5TZXRHcmFwaE9wdGltaXphdGlvbkxldmVsKGVudl9ncmFwaF9vcHRpbWl6YXRpb25fbGV2ZWwoR3JhcGhPcHRpbWl6YXRpb25MZXZlbDo6T1JUX0VOQUJMRV9BTEwpKTsKICAgIHNlc3Npb25fb3B0aW9uc18tPkVuYWJsZUNwdU1lbUFyZW5hKCk7CiAgICBpZiAoZW52X2VuYWJsZWQoIlZJRU5FVV9PUlRfRElTQUJMRV9TUElOIikpIHsKICAgICAgICBzZXNzaW9uX29wdGlvbnNfLT5BZGRDb25maWdFbnRyeSgic2Vzc2lvbi5pbnRyYV9vcC5hbGxvd19zcGlubmluZyIsICIwIik7CiAgICAgICAgc2Vzc2lvbl9vcHRpb25zXy0+QWRkQ29uZmlnRW50cnkoInNlc3Npb24uaW50ZXJfb3AuYWxsb3dfc3Bpbm5pbmciLCAiMCIpOwogICAgfQoKICAgIGlmICghYXBwZW5kX3JlcXVlc3RlZF9leGVjdXRpb25fcHJvdmlkZXIoKnNlc3Npb25fb3B0aW9uc18sIGVycm9yKSkgewogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0KICAgIGNwdV9tZW1vcnlfaW5mb18gPSBzdGQ6Om1ha2VfdW5pcXVlPE9ydDo6TWVtb3J5SW5mbz4oCiAgICAgICAgT3J0OjpNZW1vcnlJbmZvOjpDcmVhdGVDcHUoT3J0QXJlbmFBbGxvY2F0b3IsIE9ydE1lbVR5cGVEZWZhdWx0KSk7CgogICAgaWYgKGVudl9lbmFibGVkKCJWSUVORVVfT1JUX1BST0ZJTElORyIpKSB7CiAgICAgICAgc3RkOjpzdHJpbmcgcHJvZmlsZV9wcmVmaXggPSBnZXRlbnZfc3RyaW5nKCJWSUVORVVfT1JUX1BST0ZJTEVfUFJFRklYIik7CiAgICAgICAgaWYgKHByb2ZpbGVfcHJlZml4LmVtcHR5KCkpIHsKICAgICAgICAgICAgcHJvZmlsZV9wcmVmaXggPSAidmllbmV1X3Byb2ZpbGUiOwogICAgICAgIH0KI2lmZGVmIF9XSU4zMgogICAgICAgIGNvbnN0IHN0ZDo6d3N0cmluZyB3aWRlX3Byb2ZpbGVfcHJlZml4KHByb2ZpbGVfcHJlZml4LmJlZ2luKCksIHByb2ZpbGVfcHJlZml4LmVuZCgpKTsKICAgICAgICBzZXNzaW9uX29wdGlvbnNfLT5FbmFibGVQcm9maWxpbmcod2lkZV9wcm9maWxlX3ByZWZpeC5jX3N0cigpKTsKI2Vsc2UKICAgICAgICBzZXNzaW9uX29wdGlvbnNfLT5FbmFibGVQcm9maWxpbmcocHJvZmlsZV9wcmVmaXguY19zdHIoKSk7CiNlbmRpZgogICAgfQoKICAgIGlmICghbG9hZF9zZXNzaW9uKGpvaW5fcGF0aChvbm54X2Rpcl8sICJ2aWVuZXVfcHJlZmlsbC5vbm54IiksIHByZWZpbGxfc2Vzc2lvbl8sIGVycm9yKSB8fAogICAgICAgICFsb2FkX3Nlc3Npb24oam9pbl9wYXRoKG9ubnhfZGlyXywgInZpZW5ldV9kZWNvZGVfc3RlcC5vbm54IiksIGRlY29kZV9zZXNzaW9uXywgZXJyb3IpIHx8CiAgICAgICAgIWxvYWRfc2Vzc2lvbihqb2luX3BhdGgob25ueF9kaXJfLCAidmllbmV1X2Fjb3VzdGljX2NhY2hlZC5vbm54IiksIGFjb3VzdGljX3Nlc3Npb25fLCBlcnJvcikgfHwKICAgICAgICAhbG9hZF9zZXNzaW9uKGpvaW5fcGF0aChjb2RlY19kaXJfLCAibW9zc19hdWRpb190b2tlbml6ZXJfZGVjb2RlX2Z1bGwub25ueCIpLCBjb2RlY19kZWNvZGVfc2Vzc2lvbl8sIGVycm9yKSkgewogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0KICAgIGNhY2hlX3Nlc3Npb25faW8oKnByZWZpbGxfc2Vzc2lvbl8sIHByZWZpbGxfaW9fKTsKICAgIGNhY2hlX3Nlc3Npb25faW8oKmRlY29kZV9zZXNzaW9uXywgZGVjb2RlX2lvXyk7CiAgICBjYWNoZV9zZXNzaW9uX2lvKCphY291c3RpY19zZXNzaW9uXywgYWNvdXN0aWNfaW9fKTsKICAgIGNhY2hlX3Nlc3Npb25faW8oKmNvZGVjX2RlY29kZV9zZXNzaW9uXywgY29kZWNfZGVjb2RlX2lvXyk7CiAgICBpZiAoIWluaXRpYWxpemVfYWNvdXN0aWNfZXhlY3V0b3IoZXJyb3IpKSB7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQoKICAgIGlmICghbG9hZF92b2ljZXMoaW5pdC52b2ljZXNfanNvbl9wYXRoLCBlcnJvcikpIHsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CgogICAgaW5pdGlhbGl6ZWRfID0gdHJ1ZTsKICAgIHJldHVybiB0cnVlOwp9CgpzdGQ6OnN0cmluZyBWaWVuZXVWM09ubnhFbmdpbmU6OnBob25lbWl6ZV9mb3JfdjMoY29uc3Qgc3RkOjpzdHJpbmcmIHRleHQpIGNvbnN0IHsKICAgIHJldHVybiBWaWVuZXVQcm9maWxlOjpwaG9uZW1pemUodGV4dCk7Cn0KCk9ydDo6TWVtb3J5SW5mbyYgVmllbmV1VjNPbm54RW5naW5lOjpjcHVfbWVtb3J5X2luZm8oKSB7CiAgICBpZiAoIWNwdV9tZW1vcnlfaW5mb18pIHsKICAgICAgICBjcHVfbWVtb3J5X2luZm9fID0gc3RkOjptYWtlX3VuaXF1ZTxPcnQ6Ok1lbW9yeUluZm8+KAogICAgICAgICAgICBPcnQ6Ok1lbW9yeUluZm86OkNyZWF0ZUNwdShPcnRBcmVuYUFsbG9jYXRvciwgT3J0TWVtVHlwZURlZmF1bHQpKTsKICAgIH0KICAgIHJldHVybiAqY3B1X21lbW9yeV9pbmZvXzsKfQoKYm9vbCBWaWVuZXVWM09ubnhFbmdpbmU6OnN5bnRoZXNpemVfcGhvbmVtZXMoCiAgICBjb25zdCBzdGQ6OnN0cmluZyYgcGhvbmVtZXMsCiAgICBjb25zdCBzdGQ6OnZlY3RvcjxpbnQ2NF90PiogcmVmX2NvZGVzLAogICAgaW50IGxlYWRpbmdfdG9rZW4sCiAgICBjb25zdCBWaWVuZXVWM09ubnhQYXJhbXMmIHBhcmFtcywKICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiYgb3V0X2F1ZGlvLAogICAgc3RkOjpzdHJpbmcmIGVycm9yKSB7CiAgICBvdXRfYXVkaW8uY2xlYXIoKTsKICAgIHJlc2V0X2JlbmNobWFya19zdGF0cygpOwogICAgYXV0byBzY2FsZWRfcHJvZ3Jlc3MgPSBbJnBhcmFtc10oZmxvYXQgbG9jYWwpIHsKICAgICAgICByZXR1cm4gcGFyYW1zLnByb2dyZXNzX2Jhc2UgKyBsb2NhbCAqIHBhcmFtcy5wcm9ncmVzc19zcGFuOwogICAgfTsKICAgIHZpZW5ldV9yZXBvcnRfcHJvZ3Jlc3MocGFyYW1zLnByb2dyZXNzLCAicHJlZmlsbCIsIDAsIDEsIHNjYWxlZF9wcm9ncmVzcygwLjEwZiksICJSdW5uaW5nIHYzIE9OTlggcHJvbXB0IHByZWZpbGwuIik7CiAgICBjb25zdCBQcm9tcHRSb3dzIHJvd3MgPSBidWlsZF9yb3dzKHBob25lbWVzLCByZWZfY29kZXMsIGxlYWRpbmdfdG9rZW4pOwogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IHByb21wdF9lbWJlZHMgPSBlbWJlZF9yb3dzKHJvd3MsIHNwZWFrZXJfYW5jaG9yXy5lbXB0eSgpID8gbnVsbHB0ciA6ICZzcGVha2VyX2FuY2hvcl8pOwogICAgc3RkOjp2ZWN0b3I8aW50NjRfdD4gcHJvbXB0X3NoYXBlID0gezEsIHJvd3Mucm93cywgY29uZmlnXy5oaWRkZW5fc2l6ZX07CiAgICBPcnQ6Ok1lbW9yeUluZm8mIG1lbSA9IGNwdV9tZW1vcnlfaW5mbygpOwoKICAgIHN0ZDo6bG9ja19ndWFyZDxzdGQ6Om11dGV4PiBsb2NrKHJ1bl9tdXRleF8pOwogICAgdHJ5IHsKICAgICAgICBjb25zdCBzaXplX3QgZXhwZWN0ZWRfbG1fb3V0cHV0cyA9IHN0YXRpY19jYXN0PHNpemVfdD4oMSArIGNvbmZpZ18ubnVtX2hpZGRlbl9sYXllcnMgKiAyKTsKICAgICAgICBpZiAocHJlZmlsbF9pb18uaW5wdXRfbmFtZXMuc2l6ZSgpICE9IDEgfHwgcHJlZmlsbF9pb18ub3V0cHV0X25hbWVzLnNpemUoKSAhPSBleHBlY3RlZF9sbV9vdXRwdXRzKSB7CiAgICAgICAgICAgIGVycm9yID0gIlZpZU5ldSB2MyBwcmVmaWxsIE9OTlggc2lnbmF0dXJlIG1pc21hdGNoLiI7CiAgICAgICAgICAgIHJldHVybiBmYWxzZTsKICAgICAgICB9CiAgICAgICAgT3J0OjpWYWx1ZSBwcm9tcHRfdGVuc29yID0gT3J0OjpWYWx1ZTo6Q3JlYXRlVGVuc29yPGZsb2F0PihtZW0sIHByb21wdF9lbWJlZHMuZGF0YSgpLCBwcm9tcHRfZW1iZWRzLnNpemUoKSwgcHJvbXB0X3NoYXBlLmRhdGEoKSwgcHJvbXB0X3NoYXBlLnNpemUoKSk7CiAgICAgICAgY29uc3QgT3J0OjpSdW5PcHRpb25zIHJ1bl9vcHRpb25ze251bGxwdHJ9OwogICAgICAgIGNvbnN0IGF1dG8gcHJlZmlsbF9zdGFydCA9IGJlbmNobWFya19lbmFibGVkXyA/IHN0ZDo6Y2hyb25vOjpzdGVhZHlfY2xvY2s6Om5vdygpIDogc3RkOjpjaHJvbm86OnN0ZWFkeV9jbG9jazo6dGltZV9wb2ludHt9OwogICAgICAgIGF1dG8gcHJlID0gcHJlZmlsbF9zZXNzaW9uXy0+UnVuKAogICAgICAgICAgICBydW5fb3B0aW9ucywKICAgICAgICAgICAgcHJlZmlsbF9pb18uaW5wdXRfcHRycy5kYXRhKCksCiAgICAgICAgICAgICZwcm9tcHRfdGVuc29yLAogICAgICAgICAgICAxLAogICAgICAgICAgICBwcmVmaWxsX2lvXy5vdXRwdXRfcHRycy5kYXRhKCksCiAgICAgICAgICAgIHByZWZpbGxfaW9fLm91dHB1dF9wdHJzLnNpemUoKSk7CiAgICAgICAgaWYgKGJlbmNobWFya19lbmFibGVkXykgewogICAgICAgICAgICBjb25zdCBhdXRvIHByZWZpbGxfZW5kID0gc3RkOjpjaHJvbm86OnN0ZWFkeV9jbG9jazo6bm93KCk7CiAgICAgICAgICAgIGJlbmNobWFya19zdGF0c18ucHJlZmlsbF9tcyArPSBzdGQ6OmNocm9ubzo6ZHVyYXRpb248ZG91YmxlLCBzdGQ6Om1pbGxpPihwcmVmaWxsX2VuZCAtIHByZWZpbGxfc3RhcnQpLmNvdW50KCk7CiAgICAgICAgICAgIGJlbmNobWFya19zdGF0c18ucHJlZmlsbF9jYWxscyArPSAxOwogICAgICAgIH0KICAgICAgICB2aWVuZXVfcmVwb3J0X3Byb2dyZXNzKHBhcmFtcy5wcm9ncmVzcywgInByZWZpbGwiLCAxLCAxLCBzY2FsZWRfcHJvZ3Jlc3MoMC4xOGYpLCAiVjMgT05OWCBwcm9tcHQgcHJlZmlsbCBjb21wbGV0ZS4iKTsKICAgICAgICBjb25zdCBmbG9hdCogaGlkZGVuX2RhdGEgPSBwcmVbMF0uR2V0VGVuc29yRGF0YTxmbG9hdD4oKTsKICAgICAgICBzdGQ6OnZlY3RvcjxPcnQ6OlZhbHVlPiBwYXN0X2s7CiAgICAgICAgc3RkOjp2ZWN0b3I8T3J0OjpWYWx1ZT4gcGFzdF92OwogICAgICAgIHBhc3Rfay5yZXNlcnZlKHN0YXRpY19jYXN0PHNpemVfdD4oY29uZmlnXy5udW1faGlkZGVuX2xheWVycykpOwogICAgICAgIHBhc3Rfdi5yZXNlcnZlKHN0YXRpY19jYXN0PHNpemVfdD4oY29uZmlnXy5udW1faGlkZGVuX2xheWVycykpOwogICAgICAgIGZvciAoaW50IGkgPSAwOyBpIDwgY29uZmlnXy5udW1faGlkZGVuX2xheWVyczsgKytpKSB7CiAgICAgICAgICAgIHBhc3Rfay5wdXNoX2JhY2soc3RkOjptb3ZlKHByZVsxICsgaV0pKTsKICAgICAgICB9CiAgICAgICAgZm9yIChpbnQgaSA9IDA7IGkgPCBjb25maWdfLm51bV9oaWRkZW5fbGF5ZXJzOyArK2kpIHsKICAgICAgICAgICAgcGFzdF92LnB1c2hfYmFjayhzdGQ6Om1vdmUocHJlWzEgKyBjb25maWdfLm51bV9oaWRkZW5fbGF5ZXJzICsgaV0pKTsKICAgICAgICB9CgogICAgICAgIHN5bnRoX2hfLnJlc2l6ZShzdGF0aWNfY2FzdDxzaXplX3Q+KGNvbmZpZ18uaGlkZGVuX3NpemUpKTsKICAgICAgICBjb25zdCBpbnQ2NF90IGxhc3Rfb2Zmc2V0ID0gKHJvd3Mucm93cyAtIDEpICogY29uZmlnXy5oaWRkZW5fc2l6ZTsKICAgICAgICBzdGQ6OmNvcHkoaGlkZGVuX2RhdGEgKyBsYXN0X29mZnNldCwgaGlkZGVuX2RhdGEgKyBsYXN0X29mZnNldCArIGNvbmZpZ18uaGlkZGVuX3NpemUsIHN5bnRoX2hfLmJlZ2luKCkpOwoKICAgICAgICBjb25zdCBzaXplX3QgZXhwZWN0ZWRfZGVjb2RlX2lucHV0cyA9IHN0YXRpY19jYXN0PHNpemVfdD4oMiArIGNvbmZpZ18ubnVtX2hpZGRlbl9sYXllcnMgKiAyKTsKICAgICAgICBpZiAoZGVjb2RlX2lvXy5pbnB1dF9uYW1lcy5zaXplKCkgIT0gZXhwZWN0ZWRfZGVjb2RlX2lucHV0cyB8fCBkZWNvZGVfaW9fLm91dHB1dF9uYW1lcy5zaXplKCkgIT0gZXhwZWN0ZWRfbG1fb3V0cHV0cykgewogICAgICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgZGVjb2RlLXN0ZXAgT05OWCBzaWduYXR1cmUgbWlzbWF0Y2guIjsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KCiAgICAgICAgc3RkOjp2ZWN0b3I8VjNSZXBldGl0aW9uSGlzdG9yeT4gaGlzdG9yeTsKICAgICAgICBpZiAoc3RkOjpmYWJzKHBhcmFtcy5yZXBldGl0aW9uX3BlbmFsdHkgLSAxLjBmKSA+IDFlLTZmKSB7CiAgICAgICAgICAgIGhpc3RvcnkucmVzaXplKHN0YXRpY19jYXN0PHNpemVfdD4oY29uZmlnXy5uX3ZxKSk7CiAgICAgICAgICAgIGZvciAoYXV0byYgaXRlbSA6IGhpc3RvcnkpIHsKICAgICAgICAgICAgICAgIGl0ZW0uaW5pdGlhbGl6ZShzdGF0aWNfY2FzdDxzaXplX3Q+KGNvbmZpZ18uYXVkaW9fdm9jYWJfc2l6ZSkpOwogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIHN0ZDo6dmVjdG9yPGludDMyX3Q+IGZyYW1lczsKICAgICAgICBjb25zdCBpbnQgbWF4X2ZyYW1lcyA9IChzdGQ6Om1heCkoMSwgcGFyYW1zLm1heF9uZXdfZnJhbWVzKTsKICAgICAgICBmcmFtZXMucmVzZXJ2ZShzdGF0aWNfY2FzdDxzaXplX3Q+KG1heF9mcmFtZXMgKiBjb25maWdfLm5fdnEpKTsKICAgICAgICBzdGQ6OnZlY3RvcjxpbnQ2NF90PiBjb2RlczsKICAgICAgICBjb2Rlcy5yZXNlcnZlKHN0YXRpY19jYXN0PHNpemVfdD4oY29uZmlnXy5uX3ZxKSk7CiAgICAgICAgc3ludGhfc2VfLnJlc2l6ZShzdGF0aWNfY2FzdDxzaXplX3Q+KGNvbmZpZ18uaGlkZGVuX3NpemUpKTsKICAgICAgICBzdGQ6OmFycmF5PGludDY0X3QsIDM+IHNlX3NoYXBlID0gezEsIDEsIGNvbmZpZ18uaGlkZGVuX3NpemV9OwogICAgICAgIHN0ZDo6YXJyYXk8aW50NjRfdCwgMj4gcG9zX3NoYXBlID0gezEsIDF9OwogICAgICAgIHN5bnRoX2RlY29kZV9pbnB1dHNfLnJlc2VydmUoc3RhdGljX2Nhc3Q8c2l6ZV90PihleHBlY3RlZF9kZWNvZGVfaW5wdXRzKSk7CiAgICAgICAgZm9yIChpbnQgdCA9IDA7IHQgPCBtYXhfZnJhbWVzOyArK3QpIHsKICAgICAgICAgICAgYm9vbCBlb3MgPSBmYWxzZTsKICAgICAgICAgICAgaWYgKCFhY291c3RpY19mcmFtZShzeW50aF9oXywgcGFyYW1zLnRlbXBlcmF0dXJlLCBwYXJhbXMudG9wX2ssIHBhcmFtcy50b3BfcCwgcGFyYW1zLnJlcGV0aXRpb25fcGVuYWx0eSwgaGlzdG9yeSwgY29kZXMsIGVvcywgZXJyb3IpKSB7CiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgZm9yIChpbnQ2NF90IGNvZGUgOiBjb2RlcykgewogICAgICAgICAgICAgICAgZnJhbWVzLnB1c2hfYmFjayhzdGF0aWNfY2FzdDxpbnQzMl90Pihjb2RlKSk7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgdmllbmV1X3JlcG9ydF9wcm9ncmVzcygKICAgICAgICAgICAgICAgIHBhcmFtcy5wcm9ncmVzcywKICAgICAgICAgICAgICAgICJnZW5lcmF0ZV9mcmFtZXMiLAogICAgICAgICAgICAgICAgdCArIDEsCiAgICAgICAgICAgICAgICBtYXhfZnJhbWVzLAogICAgICAgICAgICAgICAgc2NhbGVkX3Byb2dyZXNzKDAuMThmICsgKHN0YXRpY19jYXN0PGZsb2F0Pih0ICsgMSkgLyBzdGF0aWNfY2FzdDxmbG9hdD4obWF4X2ZyYW1lcykpICogMC42OGYpLAogICAgICAgICAgICAgICAgIkdlbmVyYXRpbmcgdjMgT05OWCBhY291c3RpYyBmcmFtZXMuIik7CiAgICAgICAgICAgIGlmIChlb3MpIHsKICAgICAgICAgICAgICAgIGJyZWFrOwogICAgICAgICAgICB9CgogICAgICAgICAgICBjb25zdCBmbG9hdCogc2dzID0gdGV4dF9lbWJfLmRhdGEuZGF0YSgpICsgY29uZmlnXy5zcGVlY2hfZ2VuZXJhdGlvbl9zdGFydF90b2tlbl9pZCAqIHRleHRfZW1iXy5jb2xzOwogICAgICAgICAgICBzdGQ6OmNvcHkoc2dzLCBzZ3MgKyBjb25maWdfLmhpZGRlbl9zaXplLCBzeW50aF9zZV8uYmVnaW4oKSk7CiAgICAgICAgICAgIGZvciAoaW50IGNoID0gMDsgY2ggPCBjb25maWdfLm5fdnE7ICsrY2gpIHsKICAgICAgICAgICAgICAgIGNvbnN0IGludDY0X3QgaWQgPSBjb2Rlc1tzdGF0aWNfY2FzdDxzaXplX3Q+KGNoKV07CiAgICAgICAgICAgICAgICBpZiAoaWQgPT0gY29uZmlnXy5hdWRpb19wYWRfdG9rZW5faWQgfHwgaWQgPCAwIHx8IGlkID49IGF1ZGlvX2VtYl8uZGltMSkgewogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgY29uc3QgZmxvYXQqIHNyYyA9IGF1ZGlvX2VtYl8uZGF0YS5kYXRhKCkgKwogICAgICAgICAgICAgICAgICAgIChzdGF0aWNfY2FzdDxpbnQ2NF90PihjaCkgKiBhdWRpb19lbWJfLmRpbTEgKyBpZCkgKiBhdWRpb19lbWJfLmRpbTI7CiAgICAgICAgICAgICAgICBmb3IgKGludCBoX2lkeCA9IDA7IGhfaWR4IDwgY29uZmlnXy5oaWRkZW5fc2l6ZTsgKytoX2lkeCkgewogICAgICAgICAgICAgICAgICAgIHN5bnRoX3NlX1tzdGF0aWNfY2FzdDxzaXplX3Q+KGhfaWR4KV0gKz0gc3JjW2hfaWR4XTsKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgICAgICAvLyBQQVRDSCBGSVg0OTogYW5jaG9yIGlzIGFkZGVkIHRvIEVWRVJZIGJhY2tib25lIHJvdyAobWlycm9yCiAgICAgICAgICAgIC8vIF9lbWJlZF9yb3dzKHNsb3QsIGFuY2hvcikgaW4gb25ueF9ydW50aW1lX2xpdGUucHkpLgogICAgICAgICAgICBpZiAoIXNwZWFrZXJfYW5jaG9yXy5lbXB0eSgpKSB7CiAgICAgICAgICAgICAgICBmb3IgKGludCBoX2lkeCA9IDA7IGhfaWR4IDwgY29uZmlnXy5oaWRkZW5fc2l6ZTsgKytoX2lkeCkgewogICAgICAgICAgICAgICAgICAgIHN5bnRoX3NlX1tzdGF0aWNfY2FzdDxzaXplX3Q+KGhfaWR4KV0gKz0gc3BlYWtlcl9hbmNob3JfW3N0YXRpY19jYXN0PHNpemVfdD4oaF9pZHgpXTsKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgICAgICBpbnQ2NF90IHBvcyA9IHJvd3Mucm93cyArIHQ7CgogICAgICAgICAgICBzeW50aF9kZWNvZGVfaW5wdXRzXy5jbGVhcigpOwogICAgICAgICAgICBzeW50aF9kZWNvZGVfaW5wdXRzXy5lbXBsYWNlX2JhY2soT3J0OjpWYWx1ZTo6Q3JlYXRlVGVuc29yPGZsb2F0PihtZW0sIHN5bnRoX3NlXy5kYXRhKCksIHN5bnRoX3NlXy5zaXplKCksIHNlX3NoYXBlLmRhdGEoKSwgc2Vfc2hhcGUuc2l6ZSgpKSk7CiAgICAgICAgICAgIHN5bnRoX2RlY29kZV9pbnB1dHNfLmVtcGxhY2VfYmFjayhPcnQ6OlZhbHVlOjpDcmVhdGVUZW5zb3I8aW50NjRfdD4obWVtLCAmcG9zLCAxLCBwb3Nfc2hhcGUuZGF0YSgpLCBwb3Nfc2hhcGUuc2l6ZSgpKSk7CiAgICAgICAgICAgIGZvciAoYXV0byYgcGsgOiBwYXN0X2spIHN5bnRoX2RlY29kZV9pbnB1dHNfLmVtcGxhY2VfYmFjayhzdGQ6Om1vdmUocGspKTsKICAgICAgICAgICAgZm9yIChhdXRvJiBwdiA6IHBhc3Rfdikgc3ludGhfZGVjb2RlX2lucHV0c18uZW1wbGFjZV9iYWNrKHN0ZDo6bW92ZShwdikpOwogICAgICAgICAgICBjb25zdCBhdXRvIGRlY29kZV9zdGFydCA9IGJlbmNobWFya19lbmFibGVkXyA/IHN0ZDo6Y2hyb25vOjpzdGVhZHlfY2xvY2s6Om5vdygpIDogc3RkOjpjaHJvbm86OnN0ZWFkeV9jbG9jazo6dGltZV9wb2ludHt9OwogICAgICAgICAgICBhdXRvIGRlYyA9IGRlY29kZV9zZXNzaW9uXy0+UnVuKAogICAgICAgICAgICAgICAgcnVuX29wdGlvbnMsCiAgICAgICAgICAgICAgICBkZWNvZGVfaW9fLmlucHV0X3B0cnMuZGF0YSgpLAogICAgICAgICAgICAgICAgc3ludGhfZGVjb2RlX2lucHV0c18uZGF0YSgpLAogICAgICAgICAgICAgICAgc3ludGhfZGVjb2RlX2lucHV0c18uc2l6ZSgpLAogICAgICAgICAgICAgICAgZGVjb2RlX2lvXy5vdXRwdXRfcHRycy5kYXRhKCksCiAgICAgICAgICAgICAgICBkZWNvZGVfaW9fLm91dHB1dF9wdHJzLnNpemUoKSk7CiAgICAgICAgICAgIGlmIChiZW5jaG1hcmtfZW5hYmxlZF8pIHsKICAgICAgICAgICAgICAgIGNvbnN0IGF1dG8gZGVjb2RlX2VuZCA9IHN0ZDo6Y2hyb25vOjpzdGVhZHlfY2xvY2s6Om5vdygpOwogICAgICAgICAgICAgICAgYmVuY2htYXJrX3N0YXRzXy5kZWNvZGVfc3RlcF9tcyArPSBzdGQ6OmNocm9ubzo6ZHVyYXRpb248ZG91YmxlLCBzdGQ6Om1pbGxpPihkZWNvZGVfZW5kIC0gZGVjb2RlX3N0YXJ0KS5jb3VudCgpOwogICAgICAgICAgICAgICAgYmVuY2htYXJrX3N0YXRzXy5kZWNvZGVfc3RlcF9jYWxscyArPSAxOwogICAgICAgICAgICB9CiAgICAgICAgICAgIGNvbnN0IGZsb2F0KiBkZWNfaGlkZGVuID0gZGVjWzBdLkdldFRlbnNvckRhdGE8ZmxvYXQ+KCk7CiAgICAgICAgICAgIHN0ZDo6Y29weShkZWNfaGlkZGVuLCBkZWNfaGlkZGVuICsgY29uZmlnXy5oaWRkZW5fc2l6ZSwgc3ludGhfaF8uYmVnaW4oKSk7CiAgICAgICAgICAgIGZvciAoaW50IGkgPSAwOyBpIDwgY29uZmlnXy5udW1faGlkZGVuX2xheWVyczsgKytpKSB7CiAgICAgICAgICAgICAgICBwYXN0X2tbc3RhdGljX2Nhc3Q8c2l6ZV90PihpKV0gPSBzdGQ6Om1vdmUoZGVjWzEgKyBpXSk7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgZm9yIChpbnQgaSA9IDA7IGkgPCBjb25maWdfLm51bV9oaWRkZW5fbGF5ZXJzOyArK2kpIHsKICAgICAgICAgICAgICAgIHBhc3RfdltzdGF0aWNfY2FzdDxzaXplX3Q+KGkpXSA9IHN0ZDo6bW92ZShkZWNbMSArIGNvbmZpZ18ubnVtX2hpZGRlbl9sYXllcnMgKyBpXSk7CiAgICAgICAgICAgIH0KICAgICAgICB9CgogICAgICAgIGlmIChmcmFtZXMuZW1wdHkoKSkgewogICAgICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgc3ludGhlc2lzIHByb2R1Y2VkIG5vIGFjb3VzdGljIGZyYW1lcy4iOwogICAgICAgICAgICBwcmludF9iZW5jaG1hcmtfc3RhdHMoKTsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KICAgICAgICB2aWVuZXVfcmVwb3J0X3Byb2dyZXNzKHBhcmFtcy5wcm9ncmVzcywgImRlY29kZV9hdWRpbyIsIDAsIDEsIHNjYWxlZF9wcm9ncmVzcygwLjkwZiksICJEZWNvZGluZyB2MyBPTk5YIGZyYW1lcyB0byBhdWRpby4iKTsKICAgICAgICBjb25zdCBib29sIG9rID0gZGVjb2RlX2NvZGVzKGZyYW1lcywgc3RhdGljX2Nhc3Q8aW50NjRfdD4oZnJhbWVzLnNpemUoKSAvIGNvbmZpZ18ubl92cSksIG91dF9hdWRpbywgZXJyb3IpOwogICAgICAgIGlmIChvaykgewogICAgICAgICAgICB2aWVuZXVfcmVwb3J0X3Byb2dyZXNzKHBhcmFtcy5wcm9ncmVzcywgImRlY29kZV9hdWRpbyIsIDEsIDEsIHNjYWxlZF9wcm9ncmVzcygwLjk2ZiksICJWMyBPTk5YIGF1ZGlvIGRlY29kZSBjb21wbGV0ZS4iKTsKICAgICAgICB9CiAgICAgICAgcHJpbnRfYmVuY2htYXJrX3N0YXRzKCk7CiAgICAgICAgcmV0dXJuIG9rOwogICAgfSBjYXRjaCAoY29uc3Qgc3RkOjpleGNlcHRpb24mIGUpIHsKICAgICAgICBwcmludF9iZW5jaG1hcmtfc3RhdHMoKTsKICAgICAgICBlcnJvciA9IHN0ZDo6c3RyaW5nKCJWaWVOZXUgdjMgc3ludGhlc2lzIGZhaWxlZDogIikgKyBlLndoYXQoKTsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9Cn0KCi8vIFBBVENIIEZJWDQ5OiBtaXJyb3IgT25ueFYzTGl0ZUVuZ2luZS5fc3BlYWtlcl9hbmNob3IgLSBMaW5lYXIgKyBMYXllck5vcm0uCi8vIHh2ZWNfdyBpcyAoSCwgc3BrX2RpbSkgcm93LW1ham9yOiB2ID0gc3BrIEAgV15UICsgYiwgdGhlbiBMTiBvdmVyIEguCi8vIG5wLnZhciB1c2VzIHBvcHVsYXRpb24gdmFyaWFuY2UgKGRkb2Y9MCkgLSBtaXJyb3JlZCBleGFjdGx5IGhlcmUuCnZvaWQgVmllbmV1VjNPbm54RW5naW5lOjpjb21wdXRlX3NwZWFrZXJfYW5jaG9yKGNvbnN0IHN0ZDo6dmVjdG9yPGZsb2F0PiYgc3BlYWtlcl9lbWIpIHsKICAgIHNwZWFrZXJfYW5jaG9yXy5jbGVhcigpOwogICAgaWYgKCFoYXNfeHZlY19wcm9qXyB8fCBzcGVha2VyX2VtYi5lbXB0eSgpKSB7CiAgICAgICAgcmV0dXJuOwogICAgfQogICAgY29uc3QgaW50IEggPSBjb25maWdfLmhpZGRlbl9zaXplOwogICAgY29uc3QgaW50IFMgPSBjb25maWdfLnNwZWFrZXJfZW1iZWRkaW5nX2RpbTsKICAgIGlmIChTIDw9IDAgfHwgeHZlY193Xy5zaXplKCkgIT0gc3RhdGljX2Nhc3Q8c2l6ZV90PihIKSAqIHN0YXRpY19jYXN0PHNpemVfdD4oUykgfHwKICAgICAgICB4dmVjX2JfLnNpemUoKSAhPSBzdGF0aWNfY2FzdDxzaXplX3Q+KEgpIHx8IHh2ZWNfbG5fd18uc2l6ZSgpICE9IHN0YXRpY19jYXN0PHNpemVfdD4oSCkgfHwKICAgICAgICB4dmVjX2xuX2JfLnNpemUoKSAhPSBzdGF0aWNfY2FzdDxzaXplX3Q+KEgpKSB7CiAgICAgICAgcmV0dXJuOwogICAgfQogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IHYoc3RhdGljX2Nhc3Q8c2l6ZV90PihIKSwgMC4wZik7CiAgICBmb3IgKGludCBoID0gMDsgaCA8IEg7ICsraCkgewogICAgICAgIGNvbnN0IGZsb2F0KiByb3cgPSB4dmVjX3dfLmRhdGEoKSArIHN0YXRpY19jYXN0PHNpemVfdD4oaCkgKiBTOwogICAgICAgIGZsb2F0IGFjYyA9IHh2ZWNfYl9bc3RhdGljX2Nhc3Q8c2l6ZV90PihoKV07CiAgICAgICAgZm9yIChpbnQgcyA9IDA7IHMgPCBTOyArK3MpIHsKICAgICAgICAgICAgYWNjICs9IHJvd1tzXSAqIHNwZWFrZXJfZW1iW3N0YXRpY19jYXN0PHNpemVfdD4ocyldOwogICAgICAgIH0KICAgICAgICB2W3N0YXRpY19jYXN0PHNpemVfdD4oaCldID0gYWNjOwogICAgfQogICAgZmxvYXQgbWVhbiA9IDAuMGY7CiAgICBmb3IgKGludCBoID0gMDsgaCA8IEg7ICsraCkgewogICAgICAgIG1lYW4gKz0gdltzdGF0aWNfY2FzdDxzaXplX3Q+KGgpXTsKICAgIH0KICAgIG1lYW4gLz0gc3RhdGljX2Nhc3Q8ZmxvYXQ+KEgpOwogICAgZmxvYXQgdmFyID0gMC4wZjsKICAgIGZvciAoaW50IGggPSAwOyBoIDwgSDsgKytoKSB7CiAgICAgICAgY29uc3QgZmxvYXQgZCA9IHZbc3RhdGljX2Nhc3Q8c2l6ZV90PihoKV0gLSBtZWFuOwogICAgICAgIHZhciArPSBkICogZDsKICAgIH0KICAgIHZhciAvPSBzdGF0aWNfY2FzdDxmbG9hdD4oSCk7CiAgICBjb25zdCBmbG9hdCBkZW5vbSA9IDEuMGYgLyBzdGQ6OnNxcnQodmFyICsgeHZlY19sbl9lcHNfKTsKICAgIHNwZWFrZXJfYW5jaG9yXy5yZXNpemUoc3RhdGljX2Nhc3Q8c2l6ZV90PihIKSk7CiAgICBmb3IgKGludCBoID0gMDsgaCA8IEg7ICsraCkgewogICAgICAgIGNvbnN0IGZsb2F0IG4gPSAodltzdGF0aWNfY2FzdDxzaXplX3Q+KGgpXSAtIG1lYW4pICogZGVub207CiAgICAgICAgc3BlYWtlcl9hbmNob3JfW3N0YXRpY19jYXN0PHNpemVfdD4oaCldID0gbiAqIHh2ZWNfbG5fd19bc3RhdGljX2Nhc3Q8c2l6ZV90PihoKV0gKyB4dmVjX2xuX2JfW3N0YXRpY19jYXN0PHNpemVfdD4oaCldOwogICAgfQp9Cgpib29sIFZpZW5ldVYzT25ueEVuZ2luZTo6c3ludGhlc2l6ZShjb25zdCBWaWVuZXVWM09ubnhQYXJhbXMmIHBhcmFtcywgc3RkOjp2ZWN0b3I8ZmxvYXQ+JiBvdXRfYXVkaW8sIHN0ZDo6c3RyaW5nJiBlcnJvcikgewogICAgb3V0X2F1ZGlvLmNsZWFyKCk7CiAgICB2aWVuZXVfcmVwb3J0X3Byb2dyZXNzKHBhcmFtcy5wcm9ncmVzcywgInByZXBhcmUiLCAwLCAwLCAwLjBmLCAiUHJlcGFyaW5nIHYzIE9OTlggc3ludGhlc2lzLiIpOwogICAgaWYgKCFpbml0aWFsaXplZF8pIHsKICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgT05OWCBlbmdpbmUgaXMgbm90IGluaXRpYWxpemVkLiI7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQogICAgaWYgKHBhcmFtcy50ZXh0LmVtcHR5KCkpIHsKICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgc3ludGhlc2lzIHJlcXVpcmVzIG5vbi1lbXB0eSB0ZXh0LiI7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQoKICAgIC8vIFBBVENIIEZJWDQ5OiB1cGRhdGUgYXJjaCAtIGhlYWQgdG9rZW4gPSBzdHlsZSB0b2tlbiAodHVfbmhpZW4pIGZyb20KICAgIC8vIGNvbmZpZyB1bmxlc3MgdGhlIHByZXNldCBjYXJyaWVzIGFuIGV4cGxpY2l0IHJlc2VydmVkX2lkOyB0dXJibwogICAgLy8gY29uZmlnIGtlZXBzIGRlZmF1bHRfc3R5bGVfdG9rZW5faWQgPSAtMSAtPiBlbW90aW9uXzAgKHVuY2hhbmdlZCkuCiAgICAvLyBTcGVha2VyIGFuY2hvciBjb21lcyBmcm9tIHRoZSBwcmVzZXQgc3BlYWtlcl9lbWIgKHVwZGF0ZSB2b2ljZXMKICAgIC8vIEpTT04gY2FycmllcyAxOTItZCB4LXZlY3RvcnMpOyBjbG9uZSBwYXRoIGtlZXBzIGFuY2hvciBvZmYuCiAgICBzcGVha2VyX2FuY2hvcl8uY2xlYXIoKTsKICAgIGludCBsZWFkaW5nX3Rva2VuID0gY29uZmlnXy5kZWZhdWx0X3N0eWxlX3Rva2VuX2lkID49IDAKICAgICAgICAgICAgICAgICAgICAgICAgICAgID8gY29uZmlnXy5kZWZhdWx0X3N0eWxlX3Rva2VuX2lkCiAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IGNvbmZpZ18uZW1vdGlvbl8wX3Rva2VuX2lkOwogICAgc3RkOjp2ZWN0b3I8aW50NjRfdD4gcmVmX2NvZGVzOwogICAgaWYgKCFwYXJhbXMucmVmX2F1ZGlvX3BhdGguZW1wdHkoKSkgewogICAgICAgIGlmICghZW5jb2RlX3JlZmVyZW5jZV9hdWRpbyhwYXJhbXMucmVmX2F1ZGlvX3BhdGgsIHJlZl9jb2RlcywgZXJyb3IpKSB7CiAgICAgICAgICAgIHJldHVybiBmYWxzZTsKICAgICAgICB9CiAgICB9IGVsc2UgewogICAgICAgIFZvaWNlUHJlc2V0IHByZXNldDsKICAgICAgICBpZiAoIXJlc29sdmVfdm9pY2VfcHJlc2V0KHBhcmFtcy52b2ljZV9pZCwgcHJlc2V0LCBlcnJvcikpIHsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KICAgICAgICBpZiAocHJlc2V0Lmhhc19yZXNlcnZlZF9pZCkgewogICAgICAgICAgICBsZWFkaW5nX3Rva2VuID0gcHJlc2V0LnJlc2VydmVkX2lkOwogICAgICAgIH0KICAgICAgICBpZiAoIXByZXNldC5jb2Rlcy5lbXB0eSgpKSB7CiAgICAgICAgICAgIHJlZl9jb2RlcyA9IHN0ZDo6bW92ZShwcmVzZXQuY29kZXMpOwogICAgICAgIH0KICAgICAgICBpZiAoIXByZXNldC5zcGVha2VyX2VtYi5lbXB0eSgpKSB7CiAgICAgICAgICAgIGNvbXB1dGVfc3BlYWtlcl9hbmNob3IocHJlc2V0LnNwZWFrZXJfZW1iKTsKICAgICAgICB9CiAgICB9CgogICAgaWYgKCFyZWZfY29kZXMuZW1wdHkoKSAmJiByZWZfY29kZXMuc2l6ZSgpICUgc3RhdGljX2Nhc3Q8c2l6ZV90Pihjb25maWdfLm5fdnEpICE9IDApIHsKICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgcmVmZXJlbmNlIGNvZGVzIGFyZSBub3QgZGl2aXNpYmxlIGJ5IG5fdnEuIjsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CgogICAgY29uc3Qgc3RkOjp2ZWN0b3I8c3RkOjpzdHJpbmc+IGNodW5rcyA9IHNwbGl0X3RleHRfZm9yX3YzX2NodW5rcyhwYXJhbXMudGV4dCwgcGFyYW1zLm1heF9jaGFycyk7CiAgICBpZiAoY2h1bmtzLmVtcHR5KCkpIHsKICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgc3ludGhlc2lzIHByb2R1Y2VkIG5vIHRleHQgY2h1bmtzLiI7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQoKICAgIGNvbnN0IGludCBzaWxlbmNlX3NhbXBsZXMgPSBzdGF0aWNfY2FzdDxpbnQ+KHN0ZDo6bHJvdW5kKHN0YXRpY19jYXN0PGRvdWJsZT4oc2FtcGxlX3JhdGUoKSkgKiAwLjE1KSk7CiAgICBmb3IgKHNpemVfdCBpID0gMDsgaSA8IGNodW5rcy5zaXplKCk7ICsraSkgewogICAgICAgIHZpZW5ldV9yZXBvcnRfcHJvZ3Jlc3MoCiAgICAgICAgICAgIHBhcmFtcy5wcm9ncmVzcywKICAgICAgICAgICAgImNodW5rIiwKICAgICAgICAgICAgc3RhdGljX2Nhc3Q8aW50PihpKSwKICAgICAgICAgICAgc3RhdGljX2Nhc3Q8aW50PihjaHVua3Muc2l6ZSgpKSwKICAgICAgICAgICAgY2h1bmtzLmVtcHR5KCkgPyAwLjBmIDogc3RhdGljX2Nhc3Q8ZmxvYXQ+KGkpIC8gc3RhdGljX2Nhc3Q8ZmxvYXQ+KGNodW5rcy5zaXplKCkpLAogICAgICAgICAgICAiU3RhcnRpbmcgdjMgT05OWCB0ZXh0IGNodW5rLiIpOwogICAgICAgIGNvbnN0IHN0ZDo6c3RyaW5nIHBob25lbWVzID0gcGhvbmVtaXplX2Zvcl92MyhjaHVua3NbaV0pOwogICAgICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBjaHVua19hdWRpbzsKICAgICAgICBWaWVuZXVWM09ubnhQYXJhbXMgY2h1bmtfcGFyYW1zID0gcGFyYW1zOwogICAgICAgIGNodW5rX3BhcmFtcy5wcm9ncmVzc19iYXNlID0gc3RhdGljX2Nhc3Q8ZmxvYXQ+KGkpIC8gc3RhdGljX2Nhc3Q8ZmxvYXQ+KGNodW5rcy5zaXplKCkpOwogICAgICAgIGNodW5rX3BhcmFtcy5wcm9ncmVzc19zcGFuID0gMS4wZiAvIHN0YXRpY19jYXN0PGZsb2F0PihjaHVua3Muc2l6ZSgpKTsKICAgICAgICBpZiAoIXN5bnRoZXNpemVfcGhvbmVtZXMoCiAgICAgICAgICAgICAgICBwaG9uZW1lcywKICAgICAgICAgICAgICAgIHJlZl9jb2Rlcy5lbXB0eSgpID8gbnVsbHB0ciA6ICZyZWZfY29kZXMsCiAgICAgICAgICAgICAgICBsZWFkaW5nX3Rva2VuLAogICAgICAgICAgICAgICAgY2h1bmtfcGFyYW1zLAogICAgICAgICAgICAgICAgY2h1bmtfYXVkaW8sCiAgICAgICAgICAgICAgICBlcnJvcikpIHsKICAgICAgICAgICAgaWYgKGNodW5rcy5zaXplKCkgPiAxKSB7CiAgICAgICAgICAgICAgICBlcnJvciArPSAiIChjaHVuayAiICsgc3RkOjp0b19zdHJpbmcoaSArIDEpICsgIi8iICsgc3RkOjp0b19zdHJpbmcoY2h1bmtzLnNpemUoKSkgKyAiKSI7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KICAgICAgICBpZiAoY2h1bmtfYXVkaW8uZW1wdHkoKSkgewogICAgICAgICAgICBjb250aW51ZTsKICAgICAgICB9CiAgICAgICAgaWYgKCFvdXRfYXVkaW8uZW1wdHkoKSAmJiBzaWxlbmNlX3NhbXBsZXMgPiAwKSB7CiAgICAgICAgICAgIG91dF9hdWRpby5pbnNlcnQob3V0X2F1ZGlvLmVuZCgpLCBzdGF0aWNfY2FzdDxzaXplX3Q+KHNpbGVuY2Vfc2FtcGxlcyksIDAuMGYpOwogICAgICAgIH0KICAgICAgICBvdXRfYXVkaW8uaW5zZXJ0KG91dF9hdWRpby5lbmQoKSwgY2h1bmtfYXVkaW8uYmVnaW4oKSwgY2h1bmtfYXVkaW8uZW5kKCkpOwogICAgICAgIHZpZW5ldV9yZXBvcnRfcHJvZ3Jlc3MoCiAgICAgICAgICAgIHBhcmFtcy5wcm9ncmVzcywKICAgICAgICAgICAgImNodW5rIiwKICAgICAgICAgICAgc3RhdGljX2Nhc3Q8aW50PihpICsgMSksCiAgICAgICAgICAgIHN0YXRpY19jYXN0PGludD4oY2h1bmtzLnNpemUoKSksCiAgICAgICAgICAgIHN0YXRpY19jYXN0PGZsb2F0PihpICsgMSkgLyBzdGF0aWNfY2FzdDxmbG9hdD4oY2h1bmtzLnNpemUoKSksCiAgICAgICAgICAgICJGaW5pc2hlZCB2MyBPTk5YIHRleHQgY2h1bmsuIik7CiAgICB9CiAgICBpZiAob3V0X2F1ZGlvLmVtcHR5KCkpIHsKICAgICAgICBlcnJvciA9ICJWaWVOZXUgdjMgc3ludGhlc2lzIHByb2R1Y2VkIGVtcHR5IGF1ZGlvLiI7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQogICAgdmllbmV1X3JlcG9ydF9wcm9ncmVzcyhwYXJhbXMucHJvZ3Jlc3MsICJjb21wbGV0ZSIsIDEsIDEsIDEuMGYsICJWMyBPTk5YIHN5bnRoZXNpcyBjb21wbGV0ZS4iKTsKICAgIHJldHVybiB0cnVlOwp9Cg=='
    'src\vieneu\v3_onnx\vieneu_v3_onnx_assets.cpp' = 'I2luY2x1ZGUgIi4uL3ZpZW5ldV92M19vbm54LmgiCiNpbmNsdWRlICJ2aWVuZXVfdjNfb25ueF9pbnRlcm5hbC5oIgoKI2luY2x1ZGUgPGFsZ29yaXRobT4KI2luY2x1ZGUgPGNjdHlwZT4KI2luY2x1ZGUgPGNzdHJpbmc+CiNpbmNsdWRlIDxsaW1pdHM+CiNpbmNsdWRlIDxzdGRleGNlcHQ+CiNpbmNsdWRlIDxzdHJpbmc+CiNpbmNsdWRlIDx1bm9yZGVyZWRfbWFwPgojaW5jbHVkZSA8dmVjdG9yPgojaW5jbHVkZSA8bmxvaG1hbm4vanNvbi5ocHA+CgovLyAtLS0gSGVscGVyIHRyYW5zcG9zZXMgLS0tCgpzdGQ6OnZlY3RvcjxmbG9hdD4gdHJhbnNwb3NlXzJkKGNvbnN0IHN0ZDo6dmVjdG9yPGZsb2F0PiYgc3JjLCBpbnQ2NF90IHJvd3MsIGludDY0X3QgY29scykgewogICAgc3RkOjp2ZWN0b3I8ZmxvYXQ+IGRzdChzdGF0aWNfY2FzdDxzaXplX3Q+KHJvd3MgKiBjb2xzKSk7CiAgICBmb3IgKGludDY0X3QgciA9IDA7IHIgPCByb3dzOyArK3IpIHsKICAgICAgICBjb25zdCBmbG9hdCogcm93ID0gc3JjLmRhdGEoKSArIHIgKiBjb2xzOwogICAgICAgIGZvciAoaW50NjRfdCBjID0gMDsgYyA8IGNvbHM7ICsrYykgewogICAgICAgICAgICBkc3Rbc3RhdGljX2Nhc3Q8c2l6ZV90PihjICogcm93cyArIHIpXSA9IHJvd1tjXTsKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gZHN0Owp9CgpzdGQ6OnZlY3RvcjxmbG9hdD4gdHJhbnNwb3NlX2F1ZGlvX2VtYihjb25zdCBzdGQ6OnZlY3RvcjxmbG9hdD4mIHNyYywgaW50NjRfdCBjaGFubmVscywgaW50NjRfdCB2b2NhYiwgaW50NjRfdCBoaWRkZW4pIHsKICAgIHN0ZDo6dmVjdG9yPGZsb2F0PiBkc3Qoc3RhdGljX2Nhc3Q8c2l6ZV90PihjaGFubmVscyAqIGhpZGRlbiAqIHZvY2FiKSk7CiAgICBmb3IgKGludDY0X3QgY2ggPSAwOyBjaCA8IGNoYW5uZWxzOyArK2NoKSB7CiAgICAgICAgZm9yIChpbnQ2NF90IHYgPSAwOyB2IDwgdm9jYWI7ICsrdikgewogICAgICAgICAgICBjb25zdCBmbG9hdCogZW1iID0gc3JjLmRhdGEoKSArIChjaCAqIHZvY2FiICsgdikgKiBoaWRkZW47CiAgICAgICAgICAgIGZvciAoaW50NjRfdCBoID0gMDsgaCA8IGhpZGRlbjsgKytoKSB7CiAgICAgICAgICAgICAgICBkc3Rbc3RhdGljX2Nhc3Q8c2l6ZV90PigoY2ggKiBoaWRkZW4gKyBoKSAqIHZvY2FiICsgdildID0gZW1iW2hdOwogICAgICAgICAgICB9CiAgICAgICAgfQogICAgfQogICAgcmV0dXJuIGRzdDsKfQoKLy8gLS0tIE5QWiAvIE5QWSBMb2FkZXIgSGVscGVycyAtLS0KCnN0ZDo6dmVjdG9yPHN0ZDo6c3RyaW5nPiBwYXJzZV9zaGFwZV9pdGVtcyhjb25zdCBzdGQ6OnN0cmluZyYgc2hhcGVfdGV4dCkgewogICAgc3RkOjp2ZWN0b3I8c3RkOjpzdHJpbmc+IG91dDsKICAgIHN0ZDo6c3RyaW5nIGN1cjsKICAgIGZvciAoY2hhciBjIDogc2hhcGVfdGV4dCkgewogICAgICAgIGlmIChjID09ICcsJykgewogICAgICAgICAgICBpZiAoIWN1ci5lbXB0eSgpKSB7CiAgICAgICAgICAgICAgICBvdXQucHVzaF9iYWNrKGN1cik7CiAgICAgICAgICAgICAgICBjdXIuY2xlYXIoKTsKICAgICAgICAgICAgfQogICAgICAgIH0gZWxzZSBpZiAoIXN0ZDo6aXNzcGFjZShzdGF0aWNfY2FzdDx1bnNpZ25lZCBjaGFyPihjKSkgJiYgYyAhPSAnKCcgJiYgYyAhPSAnKScpIHsKICAgICAgICAgICAgY3VyLnB1c2hfYmFjayhjKTsKICAgICAgICB9CiAgICB9CiAgICBpZiAoIWN1ci5lbXB0eSgpKSB7CiAgICAgICAgb3V0LnB1c2hfYmFjayhjdXIpOwogICAgfQogICAgcmV0dXJuIG91dDsKfQoKTmFtZWRBcnJheSBwYXJzZV9ucHkoY29uc3QgdWludDhfdCogZGF0YSwgc2l6ZV90IHNpemUsIGNvbnN0IHN0ZDo6c3RyaW5nJiBuYW1lKSB7CiAgICBpZiAoc2l6ZSA8IDE2IHx8IHN0ZDo6bWVtY21wKGRhdGEsICJceDkzTlVNUFkiLCA2KSAhPSAwKSB7CiAgICAgICAgdGhyb3cgc3RkOjpydW50aW1lX2Vycm9yKCJpbnZhbGlkIG5weSBoZWFkZXIgZm9yICIgKyBuYW1lKTsKICAgIH0KICAgIGNvbnN0IHVpbnQ4X3QgbWFqb3IgPSBkYXRhWzZdOwogICAgc2l6ZV90IGhlYWRlcl9sZW4gPSAwOwogICAgc2l6ZV90IGhlYWRlcl9vZmZzZXQgPSAwOwogICAgaWYgKG1ham9yID09IDEpIHsKICAgICAgICBoZWFkZXJfbGVuID0gcmVhZF91MTZfbGUoZGF0YSArIDgpOwogICAgICAgIGhlYWRlcl9vZmZzZXQgPSAxMDsKICAgIH0gZWxzZSBpZiAobWFqb3IgPT0gMiB8fCBtYWpvciA9PSAzKSB7CiAgICAgICAgaGVhZGVyX2xlbiA9IHJlYWRfdTMyX2xlKGRhdGEgKyA4KTsKICAgICAgICBoZWFkZXJfb2Zmc2V0ID0gMTI7CiAgICB9IGVsc2UgewogICAgICAgIHRocm93IHN0ZDo6cnVudGltZV9lcnJvcigidW5zdXBwb3J0ZWQgbnB5IHZlcnNpb24gZm9yICIgKyBuYW1lKTsKICAgIH0KICAgIGlmIChoZWFkZXJfb2Zmc2V0ICsgaGVhZGVyX2xlbiA+IHNpemUpIHsKICAgICAgICB0aHJvdyBzdGQ6OnJ1bnRpbWVfZXJyb3IoInRydW5jYXRlZCBucHkgaGVhZGVyIGZvciAiICsgbmFtZSk7CiAgICB9CiAgICBjb25zdCBzdGQ6OnN0cmluZyBoZWFkZXIocmVpbnRlcnByZXRfY2FzdDxjb25zdCBjaGFyKj4oZGF0YSArIGhlYWRlcl9vZmZzZXQpLCBoZWFkZXJfbGVuKTsKICAgIGNvbnN0IGJvb2wgaXNfZjE2ID0gaGVhZGVyLmZpbmQoIidkZXNjcic6ICc8ZjInIikgIT0gc3RkOjpzdHJpbmc6Om5wb3MgfHwgaGVhZGVyLmZpbmQoIlwiZGVzY3JcIjogXCI8ZjJcIiIpICE9IHN0ZDo6c3RyaW5nOjpucG9zOwogICAgY29uc3QgYm9vbCBpc19mMzIgPSBoZWFkZXIuZmluZCgiJ2Rlc2NyJzogJzxmNCciKSAhPSBzdGQ6OnN0cmluZzo6bnBvcyB8fCBoZWFkZXIuZmluZCgiXCJkZXNjclwiOiBcIjxmNFwiIikgIT0gc3RkOjpzdHJpbmc6Om5wb3M7CiAgICBpZiAoIWlzX2YxNiAmJiAhaXNfZjMyKSB7CiAgICAgICAgdGhyb3cgc3RkOjpydW50aW1lX2Vycm9yKCJ1bnN1cHBvcnRlZCBucHkgZHR5cGUgZm9yICIgKyBuYW1lICsgIiAoZXhwZWN0ZWQgZmxvYXQxNiBvciBmbG9hdDMyKSIpOwogICAgfQogICAgaWYgKGhlYWRlci5maW5kKCJUcnVlIikgIT0gc3RkOjpzdHJpbmc6Om5wb3MpIHsKICAgICAgICB0aHJvdyBzdGQ6OnJ1bnRpbWVfZXJyb3IoImZvcnRyYW4tb3JkZXIgbnB5IGFycmF5cyBhcmUgbm90IHN1cHBvcnRlZCBmb3IgIiArIG5hbWUpOwogICAgfQogICAgY29uc3Qgc2l6ZV90IHNoYXBlX3BvcyA9IGhlYWRlci5maW5kKCInc2hhcGUnOiIpOwogICAgY29uc3Qgc2l6ZV90IHBhcmVuX3N0YXJ0ID0gaGVhZGVyLmZpbmQoJygnLCBzaGFwZV9wb3MpOwogICAgY29uc3Qgc2l6ZV90IHBhcmVuX2VuZCA9IGhlYWRlci5maW5kKCcpJywgcGFyZW5fc3RhcnQpOwogICAgaWYgKHNoYXBlX3BvcyA9PSBzdGQ6OnN0cmluZzo6bnBvcyB8fCBwYXJlbl9zdGFydCA9PSBzdGQ6OnN0cmluZzo6bnBvcyB8fCBwYXJlbl9lbmQgPT0gc3RkOjpzdHJpbmc6Om5wb3MpIHsKICAgICAgICB0aHJvdyBzdGQ6OnJ1bnRpbWVfZXJyb3IoIm1pc3NpbmcgbnB5IHNoYXBlIGZvciAiICsgbmFtZSk7CiAgICB9CgogICAgTmFtZWRBcnJheSBhcnI7CiAgICBjb25zdCBhdXRvIGl0ZW1zID0gcGFyc2Vfc2hhcGVfaXRlbXMoaGVhZGVyLnN1YnN0cihwYXJlbl9zdGFydCwgcGFyZW5fZW5kIC0gcGFyZW5fc3RhcnQgKyAxKSk7CiAgICBpbnQ2NF90IGNvdW50ID0gMTsKICAgIGZvciAoY29uc3Qgc3RkOjpzdHJpbmcmIGl0ZW0gOiBpdGVtcykgewogICAgICAgIGNvbnN0IGludDY0X3QgZGltID0gc3RkOjpzdG9sbChpdGVtKTsKICAgICAgICBhcnIuc2hhcGUucHVzaF9iYWNrKGRpbSk7CiAgICAgICAgY291bnQgKj0gZGltOwogICAgfQoKICAgIGNvbnN0IHNpemVfdCBwYXlsb2FkX29mZnNldCA9IGhlYWRlcl9vZmZzZXQgKyBoZWFkZXJfbGVuOwogICAgY29uc3Qgc2l6ZV90IGVsZW1lbnRfYnl0ZXMgPSBpc19mMTYgPyBzaXplb2YodWludDE2X3QpIDogc2l6ZW9mKGZsb2F0KTsKICAgIGNvbnN0IHNpemVfdCBwYXlsb2FkX2J5dGVzID0gc3RhdGljX2Nhc3Q8c2l6ZV90Pihjb3VudCkgKiBlbGVtZW50X2J5dGVzOwogICAgaWYgKHBheWxvYWRfb2Zmc2V0ICsgcGF5bG9hZF9ieXRlcyA+IHNpemUpIHsKICAgICAgICB0aHJvdyBzdGQ6OnJ1bnRpbWVfZXJyb3IoInRydW5jYXRlZCBucHkgcGF5bG9hZCBmb3IgIiArIG5hbWUpOwogICAgfQogICAgYXJyLmRhdGEucmVzaXplKHN0YXRpY19jYXN0PHNpemVfdD4oY291bnQpKTsKICAgIGNvbnN0IHVpbnQ4X3QqIHAgPSBkYXRhICsgcGF5bG9hZF9vZmZzZXQ7CiAgICBpZiAoaXNfZjE2KSB7CiAgICAgICAgZm9yIChpbnQ2NF90IGkgPSAwOyBpIDwgY291bnQ7ICsraSkgewogICAgICAgICAgICBhcnIuZGF0YVtzdGF0aWNfY2FzdDxzaXplX3Q+KGkpXSA9IGhhbGZfdG9fZmxvYXQocmVhZF91MTZfbGUocCArIGkgKiAyKSk7CiAgICAgICAgfQogICAgfSBlbHNlIHsKICAgICAgICBmb3IgKGludDY0X3QgaSA9IDA7IGkgPCBjb3VudDsgKytpKSB7CiAgICAgICAgICAgIGZsb2F0IHYgPSAwLjBmOwogICAgICAgICAgICBzdGQ6Om1lbWNweSgmdiwgcCArIHN0YXRpY19jYXN0PHNpemVfdD4oaSkgKiBzaXplb2YoZmxvYXQpLCBzaXplb2YoZmxvYXQpKTsKICAgICAgICAgICAgYXJyLmRhdGFbc3RhdGljX2Nhc3Q8c2l6ZV90PihpKV0gPSB2OwogICAgICAgIH0KICAgIH0KICAgIHJldHVybiBhcnI7Cn0KCnN0ZDo6dW5vcmRlcmVkX21hcDxzdGQ6OnN0cmluZywgTmFtZWRBcnJheT4gbG9hZF9ucHpfc3RvcmVkKGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoKSB7CiAgICBjb25zdCBzdGQ6OnN0cmluZyBieXRlcyA9IHJlYWRfZmlsZV9ieXRlcyhwYXRoKTsKICAgIGNvbnN0IGF1dG8qIGRhdGEgPSByZWludGVycHJldF9jYXN0PGNvbnN0IHVpbnQ4X3QqPihieXRlcy5kYXRhKCkpOwogICAgY29uc3Qgc2l6ZV90IHNpemUgPSBieXRlcy5zaXplKCk7CiAgICBzaXplX3Qgb2ZmID0gMDsKICAgIHN0ZDo6dW5vcmRlcmVkX21hcDxzdGQ6OnN0cmluZywgTmFtZWRBcnJheT4gYXJyYXlzOwoKICAgIHdoaWxlIChvZmYgKyAzMCA8PSBzaXplKSB7CiAgICAgICAgY29uc3QgdWludDMyX3Qgc2lnID0gcmVhZF91MzJfbGUoZGF0YSArIG9mZik7CiAgICAgICAgaWYgKHNpZyAhPSAweDA0MDM0YjUwdSkgewogICAgICAgICAgICBicmVhazsKICAgICAgICB9CiAgICAgICAgY29uc3QgdWludDE2X3QgbWV0aG9kID0gcmVhZF91MTZfbGUoZGF0YSArIG9mZiArIDgpOwogICAgICAgIGNvbnN0IHVpbnQzMl90IGNvbXByZXNzZWRfc2l6ZTMyID0gcmVhZF91MzJfbGUoZGF0YSArIG9mZiArIDE4KTsKICAgICAgICBjb25zdCB1aW50MzJfdCB1bmNvbXByZXNzZWRfc2l6ZTMyID0gcmVhZF91MzJfbGUoZGF0YSArIG9mZiArIDIyKTsKICAgICAgICBjb25zdCB1aW50MTZfdCBuYW1lX2xlbiA9IHJlYWRfdTE2X2xlKGRhdGEgKyBvZmYgKyAyNik7CiAgICAgICAgY29uc3QgdWludDE2X3QgZXh0cmFfbGVuID0gcmVhZF91MTZfbGUoZGF0YSArIG9mZiArIDI4KTsKICAgICAgICBjb25zdCBzaXplX3QgbmFtZV9vZmYgPSBvZmYgKyAzMDsKICAgICAgICBjb25zdCBzaXplX3QgcGF5bG9hZF9vZmYgPSBuYW1lX29mZiArIG5hbWVfbGVuICsgZXh0cmFfbGVuOwogICAgICAgIHVpbnQ2NF90IGNvbXByZXNzZWRfc2l6ZTY0ID0gY29tcHJlc3NlZF9zaXplMzI7CiAgICAgICAgdWludDY0X3QgdW5jb21wcmVzc2VkX3NpemU2NCA9IHVuY29tcHJlc3NlZF9zaXplMzI7CiAgICAgICAgaWYgKGNvbXByZXNzZWRfc2l6ZTMyID09IDB4RkZGRkZGRkZ1IHx8IHVuY29tcHJlc3NlZF9zaXplMzIgPT0gMHhGRkZGRkZGRnUpIHsKICAgICAgICAgICAgYm9vbCBmb3VuZF96aXA2NCA9IGZhbHNlOwogICAgICAgICAgICBzaXplX3QgZXh0cmFfb2ZmID0gbmFtZV9vZmYgKyBuYW1lX2xlbjsKICAgICAgICAgICAgY29uc3Qgc2l6ZV90IGV4dHJhX2VuZCA9IGV4dHJhX29mZiArIGV4dHJhX2xlbjsKICAgICAgICAgICAgd2hpbGUgKGV4dHJhX29mZiArIDQgPD0gZXh0cmFfZW5kKSB7CiAgICAgICAgICAgICAgICBjb25zdCB1aW50MTZfdCBmaWVsZF9pZCA9IHJlYWRfdTE2X2xlKGRhdGEgKyBleHRyYV9vZmYpOwogICAgICAgICAgICAgICAgY29uc3QgdWludDE2X3QgZmllbGRfc2l6ZSA9IHJlYWRfdTE2X2xlKGRhdGEgKyBleHRyYV9vZmYgKyAyKTsKICAgICAgICAgICAgICAgIGNvbnN0IHNpemVfdCBmaWVsZF9wYXlsb2FkID0gZXh0cmFfb2ZmICsgNDsKICAgICAgICAgICAgICAgIGlmIChmaWVsZF9wYXlsb2FkICsgZmllbGRfc2l6ZSA+IGV4dHJhX2VuZCkgewogICAgICAgICAgICAgICAgICAgIHRocm93IHN0ZDo6cnVudGltZV9lcnJvcigidHJ1bmNhdGVkIHppcCBleHRyYSBmaWVsZCBpbiAiICsgcGF0aCk7CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICBpZiAoZmllbGRfaWQgPT0gMHgwMDAxdSkgewogICAgICAgICAgICAgICAgICAgIGZvdW5kX3ppcDY0ID0gdHJ1ZTsKICAgICAgICAgICAgICAgICAgICBzaXplX3QgemlwNjRfb2ZmID0gZmllbGRfcGF5bG9hZDsKICAgICAgICAgICAgICAgICAgICBpZiAodW5jb21wcmVzc2VkX3NpemUzMiA9PSAweEZGRkZGRkZGdSkgewogICAgICAgICAgICAgICAgICAgICAgICBpZiAoemlwNjRfb2ZmICsgOCA+IGZpZWxkX3BheWxvYWQgKyBmaWVsZF9zaXplKSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICB0aHJvdyBzdGQ6OnJ1bnRpbWVfZXJyb3IoInRydW5jYXRlZCB6aXA2NCB1bmNvbXByZXNzZWQgc2l6ZSBpbiAiICsgcGF0aCk7CiAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgICAgdW5jb21wcmVzc2VkX3NpemU2NCA9IHJlYWRfdTY0X2xlKGRhdGEgKyB6aXA2NF9vZmYpOwogICAgICAgICAgICAgICAgICAgICAgICB6aXA2NF9vZmYgKz0gODsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgaWYgKGNvbXByZXNzZWRfc2l6ZTMyID09IDB4RkZGRkZGRkZ1KSB7CiAgICAgICAgICAgICAgICAgICAgICAgIGlmICh6aXA2NF9vZmYgKyA4ID4gZmllbGRfcGF5bG9hZCArIGZpZWxkX3NpemUpIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRocm93IHN0ZDo6cnVudGltZV9lcnJvcigidHJ1bmNhdGVkIHppcDY0IGNvbXByZXNzZWQgc2l6ZSBpbiAiICsgcGF0aCk7CiAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgICAgY29tcHJlc3NlZF9zaXplNjQgPSByZWFkX3U2NF9sZShkYXRhICsgemlwNjRfb2ZmKTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgYnJlYWs7CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICBleHRyYV9vZmYgPSBmaWVsZF9wYXlsb2FkICsgZmllbGRfc2l6ZTsKICAgICAgICAgICAgfQogICAgICAgICAgICBpZiAoIWZvdW5kX3ppcDY0KSB7CiAgICAgICAgICAgICAgICB0aHJvdyBzdGQ6OnJ1bnRpbWVfZXJyb3IoIm1pc3NpbmcgemlwNjQgc2l6ZSBleHRyYSBmaWVsZCBpbiAiICsgcGF0aCk7CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgaWYgKGNvbXByZXNzZWRfc2l6ZTY0ID4gc3RhdGljX2Nhc3Q8dWludDY0X3Q+KHN0ZDo6bnVtZXJpY19saW1pdHM8c2l6ZV90Pjo6bWF4KCkpIHx8CiAgICAgICAgICAgIHVuY29tcHJlc3NlZF9zaXplNjQgPiBzdGF0aWNfY2FzdDx1aW50NjRfdD4oc3RkOjpudW1lcmljX2xpbWl0czxzaXplX3Q+OjptYXgoKSkpIHsKICAgICAgICAgICAgdGhyb3cgc3RkOjpydW50aW1lX2Vycm9yKCJucHogZW50cnkgaXMgdG9vIGxhcmdlIGluICIgKyBwYXRoKTsKICAgICAgICB9CiAgICAgICAgY29uc3Qgc2l6ZV90IGNvbXByZXNzZWRfc2l6ZSA9IHN0YXRpY19jYXN0PHNpemVfdD4oY29tcHJlc3NlZF9zaXplNjQpOwogICAgICAgIGNvbnN0IHNpemVfdCB1bmNvbXByZXNzZWRfc2l6ZSA9IHN0YXRpY19jYXN0PHNpemVfdD4odW5jb21wcmVzc2VkX3NpemU2NCk7CiAgICAgICAgaWYgKHBheWxvYWRfb2ZmID4gc2l6ZSB8fCBwYXlsb2FkX29mZiArIGNvbXByZXNzZWRfc2l6ZSA+IHNpemUpIHsKICAgICAgICAgICAgdGhyb3cgc3RkOjpydW50aW1lX2Vycm9yKCJ0cnVuY2F0ZWQgbnB6IGVudHJ5IGluICIgKyBwYXRoKTsKICAgICAgICB9CiAgICAgICAgc3RkOjpzdHJpbmcgbmFtZShyZWludGVycHJldF9jYXN0PGNvbnN0IGNoYXIqPihkYXRhICsgbmFtZV9vZmYpLCBuYW1lX2xlbik7CiAgICAgICAgaWYgKG1ldGhvZCAhPSAwKSB7CiAgICAgICAgICAgIHRocm93IHN0ZDo6cnVudGltZV9lcnJvcigiY29tcHJlc3NlZCBucHogZW50cmllcyBhcmUgbm90IHN1cHBvcnRlZDogIiArIG5hbWUpOwogICAgICAgIH0KICAgICAgICBpZiAoY29tcHJlc3NlZF9zaXplICE9IHVuY29tcHJlc3NlZF9zaXplKSB7CiAgICAgICAgICAgIHRocm93IHN0ZDo6cnVudGltZV9lcnJvcigiaW52YWxpZCBzdG9yZWQgbnB6IHNpemUgZm9yICIgKyBuYW1lKTsKICAgICAgICB9CiAgICAgICAgYXJyYXlzW25hbWVdID0gcGFyc2VfbnB5KGRhdGEgKyBwYXlsb2FkX29mZiwgdW5jb21wcmVzc2VkX3NpemUsIG5hbWUpOwogICAgICAgIG9mZiA9IHBheWxvYWRfb2ZmICsgY29tcHJlc3NlZF9zaXplOwogICAgfQogICAgcmV0dXJuIGFycmF5czsKfQoKLy8gLS0tIFZpZW5ldVYzT25ueEVuZ2luZSBNZW1iZXIgRnVuY3Rpb25zIC0tLQoKYm9vbCBWaWVuZXVWM09ubnhFbmdpbmU6OmxvYWRfc2Vzc2lvbihjb25zdCBzdGQ6OnN0cmluZyYgcGF0aCwgc3RkOjp1bmlxdWVfcHRyPE9ydDo6U2Vzc2lvbj4mIHNlc3Npb24sIHN0ZDo6c3RyaW5nJiBlcnJvcikgewogICAgdHJ5IHsKI2lmZGVmIF9XSU4zMgogICAgICAgIHN0ZDo6d3N0cmluZyB3X3BhdGgocGF0aC5iZWdpbigpLCBwYXRoLmVuZCgpKTsKICAgICAgICBzZXNzaW9uID0gc3RkOjptYWtlX3VuaXF1ZTxPcnQ6OlNlc3Npb24+KCplbnZfLCB3X3BhdGguY19zdHIoKSwgKnNlc3Npb25fb3B0aW9uc18pOwojZWxzZQogICAgICAgIHNlc3Npb24gPSBzdGQ6Om1ha2VfdW5pcXVlPE9ydDo6U2Vzc2lvbj4oKmVudl8sIHBhdGguY19zdHIoKSwgKnNlc3Npb25fb3B0aW9uc18pOwojZW5kaWYKICAgICAgICByZXR1cm4gdHJ1ZTsKICAgIH0gY2F0Y2ggKGNvbnN0IHN0ZDo6ZXhjZXB0aW9uJiBlKSB7CiAgICAgICAgZXJyb3IgPSAiRmFpbGVkIHRvIGxvYWQgT05OWCBzZXNzaW9uICIgKyBwYXRoICsgIjogIiArIGUud2hhdCgpOwogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0KfQoKdm9pZCBWaWVuZXVWM09ubnhFbmdpbmU6OmNhY2hlX3Nlc3Npb25faW8oT3J0OjpTZXNzaW9uJiBzZXNzaW9uLCBTZXNzaW9uSW8mIGlvKSB7CiAgICBpby5pbnB1dF9uYW1lcyA9IHNlc3Npb25faW5wdXRfbmFtZXMoc2Vzc2lvbik7CiAgICBpby5vdXRwdXRfbmFtZXMgPSBzZXNzaW9uX291dHB1dF9uYW1lcyhzZXNzaW9uKTsKICAgIGlvLmlucHV0X3B0cnMgPSBuYW1lX3B0cnMoaW8uaW5wdXRfbmFtZXMpOwogICAgaW8ub3V0cHV0X3B0cnMgPSBuYW1lX3B0cnMoaW8ub3V0cHV0X25hbWVzKTsKfQoKYm9vbCBWaWVuZXVWM09ubnhFbmdpbmU6OnZhbGlkYXRlX2Fzc2V0cyhjb25zdCBWaWVuZXVWM09ubnhJbml0JiBpbml0LCBzdGQ6OnN0cmluZyYgZXJyb3IpIHsKICAgIG9ubnhfZGlyXyA9IGluaXQub25ueF9kaXIuZW1wdHkoKSA/IGluaXQubW9kZWxfZGlyIDogaW5pdC5vbm54X2RpcjsKICAgIG1vZGVsX2Rpcl8gPSBpbml0Lm1vZGVsX2Rpci5lbXB0eSgpID8gb25ueF9kaXJfIDogaW5pdC5tb2RlbF9kaXI7CiAgICBjb2RlY19kaXJfID0gaW5pdC5jb2RlY19kaXI7CiAgICBjb25zdCBzdGQ6OnN0cmluZyBjb25maWdfcGF0aCA9IGluaXQuY29uZmlnX3BhdGguZW1wdHkoKSA/IGpvaW5fcGF0aChtb2RlbF9kaXJfLCAiY29uZmlnLmpzb24iKSA6IGluaXQuY29uZmlnX3BhdGg7CiAgICBjb25zdCBzdGQ6OnN0cmluZyB0b2tlbml6ZXJfcGF0aCA9IGluaXQudG9rZW5pemVyX3BhdGguZW1wdHkoKSA/IGpvaW5fcGF0aChtb2RlbF9kaXJfLCAidG9rZW5pemVyLmpzb24iKSA6IGluaXQudG9rZW5pemVyX3BhdGg7CgogICAgY29uc3Qgc3RkOjp2ZWN0b3I8c3RkOjpzdHJpbmc+IHJlcXVpcmVkID0gewogICAgICAgIGpvaW5fcGF0aChvbm54X2Rpcl8sICJ2aWVuZXVfcHJlZmlsbC5vbm54IiksCiAgICAgICAgam9pbl9wYXRoKG9ubnhfZGlyXywgInZpZW5ldV9kZWNvZGVfc3RlcC5vbm54IiksCiAgICAgICAgam9pbl9wYXRoKG9ubnhfZGlyXywgInZpZW5ldV9hY291c3RpY19jYWNoZWQub25ueCIpLAogICAgICAgIGpvaW5fcGF0aChvbm54X2Rpcl8sICJ2aWVuZXVfdjNfaGVhZHMubnB6IiksCiAgICAgICAgY29uZmlnX3BhdGgsCiAgICAgICAgdG9rZW5pemVyX3BhdGgsCiAgICAgICAgam9pbl9wYXRoKGNvZGVjX2Rpcl8sICJtb3NzX2F1ZGlvX3Rva2VuaXplcl9kZWNvZGVfZnVsbC5vbm54IiksCiAgICAgICAgam9pbl9wYXRoKGNvZGVjX2Rpcl8sICJtb3NzX2F1ZGlvX3Rva2VuaXplcl9lbmNvZGUub25ueCIpLAogICAgfTsKCiAgICBmb3IgKGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoIDogcmVxdWlyZWQpIHsKICAgICAgICBpZiAoIWZpbGVfZXhpc3RzKHBhdGgpKSB7CiAgICAgICAgICAgIGVycm9yID0gIk1pc3NpbmcgcmVxdWlyZWQgVmllTmV1IHYzIE9OTlggYXNzZXQ6ICIgKyBwYXRoOwogICAgICAgICAgICByZXR1cm4gZmFsc2U7CiAgICAgICAgfQogICAgfQogICAgY29kZWNfZW5jb2RlX3BhdGhfID0gam9pbl9wYXRoKGNvZGVjX2Rpcl8sICJtb3NzX2F1ZGlvX3Rva2VuaXplcl9lbmNvZGUub25ueCIpOwogICAgcmV0dXJuIHRydWU7Cn0KCmJvb2wgVmllbmV1VjNPbm54RW5naW5lOjpsb2FkX2NvbmZpZyhjb25zdCBzdGQ6OnN0cmluZyYgcGF0aCwgc3RkOjpzdHJpbmcmIGVycm9yKSB7CiAgICB0cnkgewogICAgICAgIGNvbnN0IGF1dG8gYyA9IG5sb2htYW5uOjpqc29uOjpwYXJzZShyZWFkX2ZpbGVfYnl0ZXMocGF0aCkpOwogICAgICAgIGNvbmZpZ18ubl92cSA9IGMudmFsdWUoIm5fdnEiLCBjb25maWdfLm5fdnEpOwogICAgICAgIGNvbmZpZ18uaGlkZGVuX3NpemUgPSBjLnZhbHVlKCJoaWRkZW5fc2l6ZSIsIGNvbmZpZ18uaGlkZGVuX3NpemUpOwogICAgICAgIGNvbmZpZ18ubnVtX2hpZGRlbl9sYXllcnMgPSBjLnZhbHVlKCJudW1faGlkZGVuX2xheWVycyIsIGNvbmZpZ18ubnVtX2hpZGRlbl9sYXllcnMpOwogICAgICAgIGNvbmZpZ18uYXVkaW9fcGFkX3Rva2VuX2lkID0gYy52YWx1ZSgiYXVkaW9fcGFkX3Rva2VuX2lkIiwgY29uZmlnXy5hdWRpb19wYWRfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18udGV4dF9wcm9tcHRfc3RhcnRfdG9rZW5faWQgPSBjLnZhbHVlKCJ0ZXh0X3Byb21wdF9zdGFydF90b2tlbl9pZCIsIGNvbmZpZ18udGV4dF9wcm9tcHRfc3RhcnRfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18udGV4dF9wcm9tcHRfZW5kX3Rva2VuX2lkID0gYy52YWx1ZSgidGV4dF9wcm9tcHRfZW5kX3Rva2VuX2lkIiwgY29uZmlnXy50ZXh0X3Byb21wdF9lbmRfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18uc3BlZWNoX2dlbmVyYXRpb25fc3RhcnRfdG9rZW5faWQgPSBjLnZhbHVlKCJzcGVlY2hfZ2VuZXJhdGlvbl9zdGFydF90b2tlbl9pZCIsIGNvbmZpZ18uc3BlZWNoX2dlbmVyYXRpb25fc3RhcnRfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18uc3BlZWNoX2dlbmVyYXRpb25fZW5kX3Rva2VuX2lkID0gYy52YWx1ZSgic3BlZWNoX2dlbmVyYXRpb25fZW5kX3Rva2VuX2lkIiwgY29uZmlnXy5zcGVlY2hfZ2VuZXJhdGlvbl9lbmRfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18uYXVkaW9fcmVmX3Nsb3RfdG9rZW5faWQgPSBjLnZhbHVlKCJhdWRpb19yZWZfc2xvdF90b2tlbl9pZCIsIGNvbmZpZ18uYXVkaW9fcmVmX3Nsb3RfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18uZW1vdGlvbl8wX3Rva2VuX2lkID0gYy52YWx1ZSgiZW1vdGlvbl8wX3Rva2VuX2lkIiwgY29uZmlnXy5lbW90aW9uXzBfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18uZW1vdGlvbl80X3Rva2VuX2lkID0gYy52YWx1ZSgiZW1vdGlvbl80X3Rva2VuX2lkIiwgY29uZmlnXy5lbW90aW9uXzRfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18udGV4dF92b2NhYl9zaXplID0gYy52YWx1ZSgidGV4dF92b2NhYl9zaXplIiwgY29uZmlnXy50ZXh0X3ZvY2FiX3NpemUpOwogICAgICAgIGNvbmZpZ18uYXVkaW9fdm9jYWJfc2l6ZSA9IGMudmFsdWUoImF1ZGlvX3ZvY2FiX3NpemUiLCBjb25maWdfLmF1ZGlvX3ZvY2FiX3NpemUpOwogICAgICAgIGNvbmZpZ18ubG9jYWxfbnVtX2F0dGVudGlvbl9oZWFkcyA9IGMudmFsdWUoImxvY2FsX251bV9hdHRlbnRpb25faGVhZHMiLCBjb25maWdfLmxvY2FsX251bV9hdHRlbnRpb25faGVhZHMpOwogICAgICAgIGNvbmZpZ18ubG9jYWxfbnVtX2hpZGRlbl9sYXllcnMgPSBjLnZhbHVlKCJsb2NhbF9udW1faGlkZGVuX2xheWVycyIsIGNvbmZpZ18ubG9jYWxfbnVtX2hpZGRlbl9sYXllcnMpOwogICAgICAgIGNvbmZpZ18ubG9jYWxfaW50ZXJtZWRpYXRlX3NpemUgPSBjLnZhbHVlKCJsb2NhbF9pbnRlcm1lZGlhdGVfc2l6ZSIsIGNvbmZpZ18ubG9jYWxfaW50ZXJtZWRpYXRlX3NpemUpOwogICAgICAgIGNvbmZpZ18ucm1zX25vcm1fZXBzID0gYy52YWx1ZSgicm1zX25vcm1fZXBzIiwgY29uZmlnXy5ybXNfbm9ybV9lcHMpOwogICAgICAgIC8vIFBBVENIIEZJWDQ5OiB1cGRhdGUtYXJjaCBhZGRpdGlvbnMgKGFic2VudCBpbiB0dXJibyBjb25maWcpLgogICAgICAgIGNvbmZpZ18uZGVmYXVsdF9zdHlsZV90b2tlbl9pZCA9IGMudmFsdWUoImRlZmF1bHRfc3R5bGVfdG9rZW5faWQiLCBjb25maWdfLmRlZmF1bHRfc3R5bGVfdG9rZW5faWQpOwogICAgICAgIGNvbmZpZ18udXNlX3NwZWFrZXJfZW1iZWRkaW5nID0gYy52YWx1ZSgidXNlX3NwZWFrZXJfZW1iZWRkaW5nIiwgY29uZmlnXy51c2Vfc3BlYWtlcl9lbWJlZGRpbmcpOwogICAgICAgIGNvbmZpZ18uc3BlYWtlcl9lbWJlZGRpbmdfZGltID0gYy52YWx1ZSgic3BlYWtlcl9lbWJlZGRpbmdfZGltIiwgY29uZmlnXy5zcGVha2VyX2VtYmVkZGluZ19kaW0pOwogICAgICAgIHJldHVybiB0cnVlOwogICAgfSBjYXRjaCAoY29uc3Qgc3RkOjpleGNlcHRpb24mIGUpIHsKICAgICAgICBlcnJvciA9IHN0ZDo6c3RyaW5nKCJGYWlsZWQgdG8gbG9hZCBWaWVOZXUgdjMgY29uZmlnOiAiKSArIGUud2hhdCgpOwogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0KfQoKYm9vbCBWaWVuZXVWM09ubnhFbmdpbmU6OmxvYWRfaGVhZHNfbnB6KGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoLCBzdGQ6OnN0cmluZyYgZXJyb3IpIHsKICAgIHRyeSB7CiAgICAgICAgYXV0byBhcnJheXMgPSBsb2FkX25wel9zdG9yZWQocGF0aCk7CiAgICAgICAgYXV0byB0ZXh0X2l0ID0gYXJyYXlzLmZpbmQoInRleHRfZW1iLm5weSIpOwogICAgICAgIGF1dG8gYXVkaW9faXQgPSBhcnJheXMuZmluZCgiYXVkaW9fZW1iLm5weSIpOwogICAgICAgIGlmICh0ZXh0X2l0ID09IGFycmF5cy5lbmQoKSB8fCBhdWRpb19pdCA9PSBhcnJheXMuZW5kKCkpIHsKICAgICAgICAgICAgZXJyb3IgPSAidmllbmV1X3YzX2hlYWRzLm5weiBpcyBtaXNzaW5nIHRleHRfZW1iLm5weSBvciBhdWRpb19lbWIubnB5IjsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KICAgICAgICBjb25zdCBhdXRvJiB0ZXh0ID0gdGV4dF9pdC0+c2Vjb25kOwogICAgICAgIGNvbnN0IGF1dG8mIGF1ZGlvID0gYXVkaW9faXQtPnNlY29uZDsKICAgICAgICBpZiAodGV4dC5zaGFwZS5zaXplKCkgIT0gMiB8fCBhdWRpby5zaGFwZS5zaXplKCkgIT0gMykgewogICAgICAgICAgICBlcnJvciA9ICJVbmV4cGVjdGVkIGVtYmVkZGluZyByYW5rIGluIHZpZW5ldV92M19oZWFkcy5ucHoiOwogICAgICAgICAgICByZXR1cm4gZmFsc2U7CiAgICAgICAgfQogICAgICAgIHRleHRfZW1iXy5yb3dzID0gdGV4dC5zaGFwZVswXTsKICAgICAgICB0ZXh0X2VtYl8uY29scyA9IHRleHQuc2hhcGVbMV07CiAgICAgICAgdGV4dF9lbWJfLmRhdGEgPSB0ZXh0LmRhdGE7CiAgICAgICAgdGV4dF9lbWJfdF8ucm93cyA9IHRleHRfZW1iXy5jb2xzOwogICAgICAgIHRleHRfZW1iX3RfLmNvbHMgPSB0ZXh0X2VtYl8ucm93czsKICAgICAgICB0ZXh0X2VtYl90Xy5kYXRhID0gdHJhbnNwb3NlXzJkKHRleHRfZW1iXy5kYXRhLCB0ZXh0X2VtYl8ucm93cywgdGV4dF9lbWJfLmNvbHMpOwogICAgICAgIGF1ZGlvX2VtYl8uZGltMCA9IGF1ZGlvLnNoYXBlWzBdOwogICAgICAgIGF1ZGlvX2VtYl8uZGltMSA9IGF1ZGlvLnNoYXBlWzFdOwogICAgICAgIGF1ZGlvX2VtYl8uZGltMiA9IGF1ZGlvLnNoYXBlWzJdOwogICAgICAgIGF1ZGlvX2VtYl8uZGF0YSA9IGF1ZGlvLmRhdGE7CiAgICAgICAgYXVkaW9fZW1iX3RfLmRpbTAgPSBhdWRpb19lbWJfLmRpbTA7CiAgICAgICAgYXVkaW9fZW1iX3RfLmRpbTEgPSBhdWRpb19lbWJfLmRpbTI7CiAgICAgICAgYXVkaW9fZW1iX3RfLmRpbTIgPSBhdWRpb19lbWJfLmRpbTE7CiAgICAgICAgYXVkaW9fZW1iX3RfLmRhdGEgPSB0cmFuc3Bvc2VfYXVkaW9fZW1iKGF1ZGlvX2VtYl8uZGF0YSwgYXVkaW9fZW1iXy5kaW0wLCBhdWRpb19lbWJfLmRpbTEsIGF1ZGlvX2VtYl8uZGltMik7CiAgICAgICAgaWYgKHRleHRfZW1iXy5jb2xzICE9IGNvbmZpZ18uaGlkZGVuX3NpemUgfHwgYXVkaW9fZW1iXy5kaW0yICE9IGNvbmZpZ18uaGlkZGVuX3NpemUpIHsKICAgICAgICAgICAgZXJyb3IgPSAiRW1iZWRkaW5nIGhpZGRlbiBzaXplIGRvZXMgbm90IG1hdGNoIGNvbmZpZy5qc29uIjsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KICAgICAgICAvLyBQQVRDSCBGSVg0OTogb3B0aW9uYWwgeHZlYyBwcm9qZWN0aW9uIHdlaWdodHMgKHVwZGF0ZSBhcmNoIHNoaXBzCiAgICAgICAgLy8gdGhlbTsgdHVyYm8gbnB6IGxhY2tzIHRoZSBrZXlzIC0+IGtlZXAgaGFzX3h2ZWNfcHJval8gPSBmYWxzZSkuCiAgICAgICAgYXV0byB4dyA9IGFycmF5cy5maW5kKCJ4dmVjX3cubnB5Iik7CiAgICAgICAgYXV0byB4YiA9IGFycmF5cy5maW5kKCJ4dmVjX2IubnB5Iik7CiAgICAgICAgYXV0byB4bHcgPSBhcnJheXMuZmluZCgieHZlY19sbl93Lm5weSIpOwogICAgICAgIGF1dG8geGxiID0gYXJyYXlzLmZpbmQoInh2ZWNfbG5fYi5ucHkiKTsKICAgICAgICBhdXRvIHhlcHMgPSBhcnJheXMuZmluZCgieHZlY19sbl9lcHMubnB5Iik7CiAgICAgICAgaWYgKHh3ICE9IGFycmF5cy5lbmQoKSAmJiB4YiAhPSBhcnJheXMuZW5kKCkgJiYgeGx3ICE9IGFycmF5cy5lbmQoKSAmJgogICAgICAgICAgICB4bGIgIT0gYXJyYXlzLmVuZCgpICYmIHhlcHMgIT0gYXJyYXlzLmVuZCgpKSB7CiAgICAgICAgICAgIGlmICh4dy0+c2Vjb25kLnNoYXBlLnNpemUoKSA9PSAyICYmCiAgICAgICAgICAgICAgICB4dy0+c2Vjb25kLnNoYXBlWzBdID09IGNvbmZpZ18uaGlkZGVuX3NpemUgJiYKICAgICAgICAgICAgICAgIHhiLT5zZWNvbmQuZGF0YS5zaXplKCkgPT0gc3RhdGljX2Nhc3Q8c2l6ZV90Pihjb25maWdfLmhpZGRlbl9zaXplKSAmJgogICAgICAgICAgICAgICAgeGx3LT5zZWNvbmQuZGF0YS5zaXplKCkgPT0gc3RhdGljX2Nhc3Q8c2l6ZV90Pihjb25maWdfLmhpZGRlbl9zaXplKSAmJgogICAgICAgICAgICAgICAgeGxiLT5zZWNvbmQuZGF0YS5zaXplKCkgPT0gc3RhdGljX2Nhc3Q8c2l6ZV90Pihjb25maWdfLmhpZGRlbl9zaXplKSkgewogICAgICAgICAgICAgICAgaGFzX3h2ZWNfcHJval8gPSB0cnVlOwogICAgICAgICAgICAgICAgeHZlY193XyA9IHh3LT5zZWNvbmQuZGF0YTsKICAgICAgICAgICAgICAgIHh2ZWNfYl8gPSB4Yi0+c2Vjb25kLmRhdGE7CiAgICAgICAgICAgICAgICB4dmVjX2xuX3dfID0geGx3LT5zZWNvbmQuZGF0YTsKICAgICAgICAgICAgICAgIHh2ZWNfbG5fYl8gPSB4bGItPnNlY29uZC5kYXRhOwogICAgICAgICAgICAgICAgaWYgKCF4ZXBzLT5zZWNvbmQuZGF0YS5lbXB0eSgpKSB7CiAgICAgICAgICAgICAgICAgICAgeHZlY19sbl9lcHNfID0geGVwcy0+c2Vjb25kLmRhdGFbMF07CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgcmV0dXJuIHRydWU7CiAgICB9IGNhdGNoIChjb25zdCBzdGQ6OmV4Y2VwdGlvbiYgZSkgewogICAgICAgIGVycm9yID0gc3RkOjpzdHJpbmcoIkZhaWxlZCB0byBsb2FkIHZpZW5ldV92M19oZWFkcy5ucHo6ICIpICsgZS53aGF0KCk7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQp9Cgpib29sIFZpZW5ldVYzT25ueEVuZ2luZTo6bG9hZF9hY291c3RpY193ZWlnaHRzKGNvbnN0IHN0ZDo6c3RyaW5nJiBwYXRoLCBzdGQ6OnN0cmluZyYgZXJyb3IpIHsKICAgIHRyeSB7CiAgICAgICAgaWYgKCFmaWxlX2V4aXN0cyhwYXRoKSkgewogICAgICAgICAgICBlcnJvciA9ICJNaXNzaW5nIFZpZU5ldSB2MyBhY291c3RpYyB3ZWlnaHRzOiAiICsgcGF0aDsKICAgICAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgICAgIH0KICAgICAgICBhdXRvIGFycmF5cyA9IGxvYWRfbnB6X3N0b3JlZChwYXRoKTsKICAgICAgICBjb25zdCBpbnQgSCA9IGNvbmZpZ18uaGlkZGVuX3NpemU7CiAgICAgICAgY29uc3QgaW50IEkgPSBjb25maWdfLmxvY2FsX2ludGVybWVkaWF0ZV9zaXplOwogICAgICAgIGNvbnN0IGludCBMID0gY29uZmlnXy5sb2NhbF9udW1faGlkZGVuX2xheWVyczsKICAgICAgICBjb25zdCBpbnQgbkggPSBjb25maWdfLmxvY2FsX251bV9hdHRlbnRpb25faGVhZHM7CiAgICAgICAgY29uc3QgaW50IGhkID0gSCAvIG5IOwogICAgICAgIGlmIChIIDw9IDAgfHwgSSA8PSAwIHx8IEwgPD0gMCB8fCBuSCA8PSAwIHx8IEggJSBuSCAhPSAwKSB7CiAgICAgICAgICAgIGVycm9yID0gIkludmFsaWQgYWNvdXN0aWMgZGVjb2RlciBkaW1lbnNpb25zIGluIGNvbmZpZy5qc29uLiI7CiAgICAgICAgICAgIHJldHVybiBmYWxzZTsKICAgICAgICB9CgogICAgICAgIGF1dG8gdGFrZSA9IFsmXShjb25zdCBzdGQ6OnN0cmluZyYgbmFtZSwgc3RkOjppbml0aWFsaXplcl9saXN0PGludDY0X3Q+IHNoYXBlLCBzdGQ6OnZlY3RvcjxmbG9hdD4mIGRzdCkgLT4gYm9vbCB7CiAgICAgICAgICAgIGNvbnN0IHN0ZDo6c3RyaW5nIG5weV9uYW1lID0gbmFtZSArICIubnB5IjsKICAgICAgICAgICAgYXV0byBpdCA9IGFycmF5cy5maW5kKG5weV9uYW1lKTsKICAgICAgICAgICAgaWYgKGl0ID09IGFycmF5cy5lbmQoKSkgewogICAgICAgICAgICAgICAgaXQgPSBhcnJheXMuZmluZChuYW1lKTsKICAgICAgICAgICAgfQogICAgICAgICAgICBpZiAoaXQgPT0gYXJyYXlzLmVuZCgpKSB7CiAgICAgICAgICAgICAgICBlcnJvciA9ICJBY291c3RpYyB3ZWlnaHRzIGFyZSBtaXNzaW5nIHRlbnNvcjogIiArIG5hbWU7CiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgY29uc3Qgc3RkOjp2ZWN0b3I8aW50NjRfdD4gZXhwZWN0ZWQoc2hhcGUpOwogICAgICAgICAgICBpZiAoaXQtPnNlY29uZC5zaGFwZSAhPSBleHBlY3RlZCkgewogICAgICAgICAgICAgICAgZXJyb3IgPSAiQWNvdXN0aWMgdGVuc29yIHNoYXBlIG1pc21hdGNoIGZvciAiICsgbmFtZSArICIuIjsKICAgICAgICAgICAgICAgIHJldHVybiBmYWxzZTsKICAgICAgICAgICAgfQogICAgICAgICAgICBkc3QgPSBzdGQ6Om1vdmUoaXQtPnNlY29uZC5kYXRhKTsKICAgICAgICAgICAgcmV0dXJuIHRydWU7CiAgICAgICAgfTsKCiAgICAgICAgQWNvdXN0aWNXZWlnaHRzIHdlaWdodHM7CiAgICAgICAgaWYgKCF0YWtlKCJzbG90X3Bvc19lbWIiLCB7Y29uZmlnXy5uX3ZxICsgMSwgSH0sIHdlaWdodHMuc2xvdF9wb3NfZW1iKSB8fAogICAgICAgICAgICAhdGFrZSgibm9ybSIsIHtIfSwgd2VpZ2h0cy5maW5hbF9ub3JtKSkgewogICAgICAgICAgICByZXR1cm4gZmFsc2U7CiAgICAgICAgfQoKICAgICAgICB3ZWlnaHRzLmxheWVycy5yZXNpemUoc3RhdGljX2Nhc3Q8c2l6ZV90PihMKSk7CiAgICAgICAgZm9yIChpbnQgbGF5ZXIgPSAwOyBsYXllciA8IEw7ICsrbGF5ZXIpIHsKICAgICAgICAgICAgQWNvdXN0aWNMYXllcldlaWdodHMmIHcgPSB3ZWlnaHRzLmxheWVyc1tzdGF0aWNfY2FzdDxzaXplX3Q+KGxheWVyKV07CiAgICAgICAgICAgIGNvbnN0IHN0ZDo6c3RyaW5nIHByZWZpeCA9ICJsYXllcnMuIiArIHN0ZDo6dG9fc3RyaW5nKGxheWVyKSArICIuIjsKICAgICAgICAgICAgaWYgKCF0YWtlKHByZWZpeCArICJub3JtMSIsIHtIfSwgdy5ub3JtMSkgfHwKICAgICAgICAgICAgICAgICF0YWtlKHByZWZpeCArICJhdHRuLnFrdiIsIHszICogSCwgSH0sIHcucWt2KSB8fAogICAgICAgICAgICAgICAgIXRha2UocHJlZml4ICsgImF0dG4ucV9ub3JtIiwge2hkfSwgdy5xX25vcm0pIHx8CiAgICAgICAgICAgICAgICAhdGFrZShwcmVmaXggKyAiYXR0bi5rX25vcm0iLCB7aGR9LCB3Lmtfbm9ybSkgfHwKICAgICAgICAgICAgICAgICF0YWtlKHByZWZpeCArICJhdHRuLm9fcHJvaiIsIHtILCBIfSwgdy5vX3Byb2opIHx8CiAgICAgICAgICAgICAgICAhdGFrZShwcmVmaXggKyAibm9ybTIiLCB7SH0sIHcubm9ybTIpIHx8CiAgICAgICAgICAgICAgICAhdGFrZShwcmVmaXggKyAiZmZfdXAiLCB7SSwgSH0sIHcuZmZfdXApIHx8CiAgICAgICAgICAgICAgICAhdGFrZShwcmVmaXggKyAiZmZfZ2F0ZSIsIHtJLCBIfSwgdy5mZl9nYXRlKSB8fAogICAgICAgICAgICAgICAgIXRha2UocHJlZml4ICsgImZmX2Rvd24iLCB7SCwgSX0sIHcuZmZfZG93bikpIHsKICAgICAgICAgICAgICAgIHJldHVybiBmYWxzZTsKICAgICAgICAgICAgfQogICAgICAgIH0KCiAgICAgICAgd2VpZ2h0cy5sb2FkZWQgPSB0cnVlOwogICAgICAgIGFjb3VzdGljX3dlaWdodHNfID0gc3RkOjptb3ZlKHdlaWdodHMpOwogICAgICAgIHJldHVybiB0cnVlOwogICAgfSBjYXRjaCAoY29uc3Qgc3RkOjpleGNlcHRpb24mIGUpIHsKICAgICAgICBlcnJvciA9IHN0ZDo6c3RyaW5nKCJGYWlsZWQgdG8gbG9hZCBWaWVOZXUgdjMgYWNvdXN0aWMgd2VpZ2h0czogIikgKyBlLndoYXQoKTsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9Cn0K'
    'src\vieneu\v3_onnx\vieneu_v3_onnx_voice.cpp' = 'I2luY2x1ZGUgIi4uL3ZpZW5ldV92M19vbm54LmgiCiNpbmNsdWRlICJ2aWVuZXVfdjNfb25ueF9pbnRlcm5hbC5oIgoKI2luY2x1ZGUgPGFsZ29yaXRobT4KI2luY2x1ZGUgPHN0cmluZz4KI2luY2x1ZGUgPHVub3JkZXJlZF9tYXA+CiNpbmNsdWRlIDx2ZWN0b3I+CiNpbmNsdWRlIDxzdGRleGNlcHQ+CiNpbmNsdWRlIDxubG9obWFubi9qc29uLmhwcD4KCi8vIC0tLSBWaWVuZXVWM09ubnhFbmdpbmUgVm9pY2UgTWVtYmVyIEZ1bmN0aW9ucyAtLS0KCmJvb2wgVmllbmV1VjNPbm54RW5naW5lOjpsb2FkX3ZvaWNlcyhjb25zdCBzdGQ6OnN0cmluZyYgdm9pY2VzX3BhdGgsIHN0ZDo6c3RyaW5nJiBlcnJvcikgewogICAgdm9pY2VzX2pzb25fLmNsZWFyKCk7CiAgICBkZWZhdWx0X3ZvaWNlX2lkXy5jbGVhcigpOwogICAgdm9pY2VfcHJlc2V0c18uY2xlYXIoKTsKICAgIGlmICh2b2ljZXNfcGF0aC5lbXB0eSgpKSB7CiAgICAgICAgcmV0dXJuIHRydWU7CiAgICB9CiAgICBpZiAoIXJlYWRfdGV4dF9maWxlKHZvaWNlc19wYXRoLCB2b2ljZXNfanNvbl8pKSB7CiAgICAgICAgZXJyb3IgPSAiRmFpbGVkIHRvIHJlYWQgVmllTmV1IHYzIHZvaWNlcyBKU09OOiAiICsgdm9pY2VzX3BhdGg7CiAgICAgICAgcmV0dXJuIGZhbHNlOwogICAgfQogICAgdHJ5IHsKICAgICAgICBjb25zdCBhdXRvIHJvb3QgPSBubG9obWFubjo6anNvbjo6cGFyc2Uodm9pY2VzX2pzb25fKTsKICAgICAgICBpZiAocm9vdC5jb250YWlucygiZGVmYXVsdF92b2ljZSIpICYmIHJvb3QuYXQoImRlZmF1bHRfdm9pY2UiKS5pc19zdHJpbmcoKSkgewogICAgICAgICAgICBkZWZhdWx0X3ZvaWNlX2lkXyA9IHJvb3QuYXQoImRlZmF1bHRfdm9pY2UiKS5nZXQ8c3RkOjpzdHJpbmc+KCk7CiAgICAgICAgfQogICAgICAgIGlmICghcm9vdC5jb250YWlucygicHJlc2V0cyIpIHx8ICFyb290LmF0KCJwcmVzZXRzIikuaXNfb2JqZWN0KCkpIHsKICAgICAgICAgICAgcmV0dXJuIHRydWU7CiAgICAgICAgfQoKICAgICAgICBjb25zdCBhdXRvJiBwcmVzZXRzID0gcm9vdC5hdCgicHJlc2V0cyIpOwogICAgICAgIGZvciAoYXV0byBpdCA9IHByZXNldHMuYmVnaW4oKTsgaXQgIT0gcHJlc2V0cy5lbmQoKTsgKytpdCkgewogICAgICAgICAgICBjb25zdCBzdGQ6OnN0cmluZyBpZCA9IGl0LmtleSgpOwogICAgICAgICAgICBjb25zdCBhdXRvJiBpdGVtID0gaXQudmFsdWUoKTsKICAgICAgICAgICAgVm9pY2VQcmVzZXQgcHJlc2V0OwogICAgICAgICAgICBwcmVzZXQuZm91bmQgPSB0cnVlOwogICAgICAgICAgICBpZiAoaXRlbS5jb250YWlucygicmVzZXJ2ZWRfaWQiKSAmJiAhaXRlbS5hdCgicmVzZXJ2ZWRfaWQiKS5pc19udWxsKCkpIHsKICAgICAgICAgICAgICAgIHByZXNldC5oYXNfcmVzZXJ2ZWRfaWQgPSB0cnVlOwogICAgICAgICAgICAgICAgcHJlc2V0LnJlc2VydmVkX2lkID0gaXRlbS5hdCgicmVzZXJ2ZWRfaWQiKS5nZXQ8aW50PigpOwogICAgICAgICAgICB9CiAgICAgICAgICAgIGlmIChpdGVtLmNvbnRhaW5zKCJjb2RlcyIpICYmIGl0ZW0uYXQoImNvZGVzIikuaXNfYXJyYXkoKSkgewogICAgICAgICAgICAgICAgY29uc3QgYXV0byYgY29kZXMgPSBpdGVtLmF0KCJjb2RlcyIpOwogICAgICAgICAgICAgICAgZm9yIChjb25zdCBhdXRvJiByb3cgOiBjb2RlcykgewogICAgICAgICAgICAgICAgICAgIGlmICghcm93LmlzX2FycmF5KCkgfHwgc3RhdGljX2Nhc3Q8aW50Pihyb3cuc2l6ZSgpKSAhPSBjb25maWdfLm5fdnEpIHsKICAgICAgICAgICAgICAgICAgICAgICAgZXJyb3IgPSAiVmllTmV1IHYzIHByZXNldCB2b2ljZSBoYXMgaW52YWxpZCBjb2RlcyBzaGFwZTogIiArIGlkOwogICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7CiAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgIGZvciAoY29uc3QgYXV0byYgdiA6IHJvdykgewogICAgICAgICAgICAgICAgICAgICAgICBwcmVzZXQuY29kZXMucHVzaF9iYWNrKHYuZ2V0PGludDY0X3Q+KCkpOwogICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgICAgICAvLyBQQVRDSCBGSVg0OTogMTkyLWQgc3BlYWtlciBlbWJlZGRpbmcgcGVyIHByZXNldCAodXBkYXRlIGFyY2gKICAgICAgICAgICAgLy8gcmVxdWlyZXMgaXQgdG8gYnVpbGQgdGhlIGFuY2hvcjsgdHVyYm8gSlNPTiBsYWNrcyB0aGUga2V5KS4KICAgICAgICAgICAgaWYgKGl0ZW0uY29udGFpbnMoInNwZWFrZXJfZW1iIikgJiYgaXRlbS5hdCgic3BlYWtlcl9lbWIiKS5pc19hcnJheSgpKSB7CiAgICAgICAgICAgICAgICBjb25zdCBhdXRvJiBzZW1iID0gaXRlbS5hdCgic3BlYWtlcl9lbWIiKTsKICAgICAgICAgICAgICAgIHByZXNldC5zcGVha2VyX2VtYi5yZXNlcnZlKHNlbWIuc2l6ZSgpKTsKICAgICAgICAgICAgICAgIGZvciAoY29uc3QgYXV0byYgdiA6IHNlbWIpIHsKICAgICAgICAgICAgICAgICAgICBpZiAodi5pc19udW1iZXIoKSkgewogICAgICAgICAgICAgICAgICAgICAgICBwcmVzZXQuc3BlYWtlcl9lbWIucHVzaF9iYWNrKHYuZ2V0PGZsb2F0PigpKTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgdm9pY2VfcHJlc2V0c19baWRdID0gc3RkOjptb3ZlKHByZXNldCk7CiAgICAgICAgfQogICAgfSBjYXRjaCAoY29uc3Qgc3RkOjpleGNlcHRpb24mIGUpIHsKICAgICAgICBlcnJvciA9IHN0ZDo6c3RyaW5nKCJGYWlsZWQgdG8gcGFyc2UgVmllTmV1IHYzIHZvaWNlcyBKU09OOiAiKSArIGUud2hhdCgpOwogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0KICAgIHJldHVybiB0cnVlOwp9Cgpib29sIFZpZW5ldVYzT25ueEVuZ2luZTo6cGFyc2Vfdm9pY2VfcmVzZXJ2ZWRfaWQoY29uc3Qgc3RkOjpzdHJpbmcmIHZvaWNlX2lkLCBpbnQmIHJlc2VydmVkX2lkKSBjb25zdCB7CiAgICBzdGF0aWMgY29uc3Qgc3RkOjp1bm9yZGVyZWRfbWFwPHN0ZDo6c3RyaW5nLCBpbnQ+IGZhbGxiYWNrID0gewogICAgICAgIHsiTmfhu41jIExhbiIsIDEzfSwgeyJOZ+G7jWMgTGluaCIsIDE0fSwgeyJUcsO6YyBMeSIsIDE1fSwgeyJN4bu5IER1ecOqbiIsIDE2fSwKICAgICAgICB7Ilh1w6JuIFbEqW5oIiwgMTd9LCB7IlRow6FpIFPGoW4iLCAxOH0sIHsiR2lhIELhuqNvIiwgMTl9LCB7IsSQ4bupYyBUcsOtIiwgMjB9LAogICAgICAgIHsiVHLhu41uZyBI4buvdSIsIDIxfSwgeyJCw6xuaCBBbiIsIDIyfQogICAgfTsKICAgIGlmICghdm9pY2VfaWQuZW1wdHkoKSkgewogICAgICAgIGF1dG8gaXQgPSBmYWxsYmFjay5maW5kKHZvaWNlX2lkKTsKICAgICAgICBpZiAoaXQgIT0gZmFsbGJhY2suZW5kKCkpIHsKICAgICAgICAgICAgcmVzZXJ2ZWRfaWQgPSBpdC0+c2Vjb25kOwogICAgICAgICAgICByZXR1cm4gdHJ1ZTsKICAgICAgICB9CiAgICB9CiAgICBpZiAodm9pY2VfaWQuZW1wdHkoKSkgewogICAgICAgIHJldHVybiBmYWxzZTsKICAgIH0KICAgIGF1dG8gaXQgPSB2b2ljZV9wcmVzZXRzXy5maW5kKHZvaWNlX2lkKTsKICAgIGlmIChpdCAhPSB2b2ljZV9wcmVzZXRzXy5lbmQoKSAmJiBpdC0+c2Vjb25kLmhhc19yZXNlcnZlZF9pZCkgewogICAgICAgIHJlc2VydmVkX2lkID0gaXQtPnNlY29uZC5yZXNlcnZlZF9pZDsKICAgICAgICByZXR1cm4gdHJ1ZTsKICAgIH0KICAgIHJldHVybiBmYWxzZTsKfQoKYm9vbCBWaWVuZXVWM09ubnhFbmdpbmU6OnJlc29sdmVfdm9pY2VfcHJlc2V0KAogICAgY29uc3Qgc3RkOjpzdHJpbmcmIHZvaWNlX2lkLAogICAgVm9pY2VQcmVzZXQmIHByZXNldCwKICAgIHN0ZDo6c3RyaW5nJiBlcnJvcikgY29uc3QgewogICAgcHJlc2V0ID0gVm9pY2VQcmVzZXR7fTsKICAgIGlmICh2b2ljZV9wcmVzZXRzXy5lbXB0eSgpKSB7CiAgICAgICAgcmV0dXJuIHRydWU7CiAgICB9CgogICAgY29uc3Qgc3RkOjpzdHJpbmcgc2VsZWN0ZWQgPSB2b2ljZV9pZC5lbXB0eSgpID8gZGVmYXVsdF92b2ljZV9pZF8gOiB2b2ljZV9pZDsKICAgIGlmIChzZWxlY3RlZC5lbXB0eSgpKSB7CiAgICAgICAgcmV0dXJuIHRydWU7CiAgICB9CgogICAgYXV0byBpdCA9IHZvaWNlX3ByZXNldHNfLmZpbmQoc2VsZWN0ZWQpOwogICAgaWYgKGl0ID09IHZvaWNlX3ByZXNldHNfLmVuZCgpKSB7CiAgICAgICAgZXJyb3IgPSAiVmllTmV1IHYzIHZvaWNlIHByZXNldCBub3QgZm91bmQ6ICIgKyBzZWxlY3RlZDsKICAgICAgICByZXR1cm4gZmFsc2U7CiAgICB9CiAgICBwcmVzZXQgPSBpdC0+c2Vjb25kOwogICAgcmV0dXJuIHRydWU7Cn0K'
}
foreach ($k in $fix49Map.Keys) {
    $dst49 = Join-Path $VnRepoDir $k
    $bytes49 = [Convert]::FromBase64String($fix49Map[$k])
    [System.IO.File]::WriteAllBytes($dst49, $bytes49)
    Write-Host ("Da nap patch FIX49: " + $k + " (" + $bytes49.Length + " B)")
}
foreach ($k in $fix49Map.Keys) {
    $txt49 = [System.IO.File]::ReadAllText((Join-Path $VnRepoDir $k))
    if (!$txt49.Contains("PATCH FIX49")) { Die ("Patch FIX49 that bai: thieu marker trong " + $k) }
}
Write-Host "Patch FIX49 OK: acoustic parameterized + speaker anchor + style head."

# --------------------------------------------------------------- ORT SDK
Step "ONNX Runtime SDK v$OnnxRuntimeVersion"
$ortPkgName = "onnxruntime-win-x64-$OnnxRuntimeVersion"
$ortRoot    = Join-Path $OrtSdkDir $ortPkgName
$ortLib     = Join-Path $ortRoot "lib\onnxruntime.lib"
$ortDll     = Join-Path $ortRoot "lib\onnxruntime.dll"

if (!(Test-Path $ortLib)) {
    New-Item -ItemType Directory -Force -Path $OrtSdkDir | Out-Null
    $zipDst = Join-Path $OrtSdkDir "$ortPkgName.zip"
    # PATCH FIX48: mirror truoc (neu cau hinh), fallback microsoft.
    $ortUrls = @()
    if ($OrtZipMirror -ne "") { $ortUrls += $OrtZipMirror }
    $ortUrls += "https://github.com/microsoft/onnxruntime/releases/download/v$OnnxRuntimeVersion/$ortPkgName.zip"
    $ortOk = $false
    foreach ($u in $ortUrls) {
        Write-Host "Tai ORT SDK: $u"
        try {
            Invoke-WebRequest -Uri $u -OutFile $zipDst -UseBasicParsing
            if ((Test-Path $zipDst) -and ((Get-Item $zipDst).Length -gt 1MB)) { $ortOk = $true; break }
            Write-Host "Canh bao: file tai ve bat thuong (duoi 1MB) - bo qua nguon nay."
        } catch {
            Write-Host "Canh bao: tai tu nguon nay that bai - $($_.Exception.Message)"
        }
    }
    if (!$ortOk) { Die "Khong tai duoc ORT SDK tu bat ky nguon nao (mirror + microsoft)." }
    Expand-Archive -Path $zipDst -DestinationPath $OrtSdkDir -Force
    Remove-Item $zipDst
}
if (!(Test-Path $ortDll)) { Die "Khong thay onnxruntime.dll trong ORT SDK." }

# --------------------------------------------------------------- toolchain
Step "Xac dinh compiler (GCC MinGW - bat buoc theo contract build.ps1 v29)"

if (!$Gcc) {
    # Chay doc lap (khong qua build.ps1): resolve gcc giong Resolve-MingwCc
    if ($env:HCSTUDIO_CC) { $Gcc = $env:HCSTUDIO_CC }
    else {
        $known = @(
            "C:\msys64\ucrt64\bin\gcc.exe",
            "C:\msys64\mingw64\bin\gcc.exe",
            "C:\ProgramData\mingw64\bin\gcc.exe",
            "C:\Strawberry\c\bin\gcc.exe"
        )
        foreach ($k in $known) { if (Test-Path $k) { $Gcc = $k; break } }
        if (!$Gcc) {
            $c = Get-Command gcc -ErrorAction SilentlyContinue
            if ($c) { $Gcc = $c.Source }
        }
        if (!$Gcc) {
            $choco = Get-Command choco -ErrorAction SilentlyContinue
            if ($choco) {
                Write-Host "Khong thay gcc - tu dong 'choco install mingw' (2-3 phut)..."
                & choco install mingw -y --no-progress
                if ($LASTEXITCODE -eq 0 -and (Test-Path "C:\ProgramData\mingw64\bin\gcc.exe")) {
                    $Gcc = "C:\ProgramData\mingw64\bin\gcc.exe"
                }
            }
        }
    }
}
if (!$Gcc -or !(Test-Path $Gcc)) {
    Die "Khong co gcc MinGW hop le (-Gcc='$Gcc'). Chay 'choco install mingw -y' hoac cai MSYS2 (ucrt64) roi build lai."
}
$Gcc    = (Get-Item $Gcc).FullName
$GccBin = Split-Path -Parent $Gcc
$Gpp    = Join-Path $GccBin "g++.exe"
if (!(Test-Path $Gpp)) { Die "Khong thay g++.exe canh gcc ($GccBin) - toolchain MinGW khong day du." }

Write-Host "GCC: $Gcc"
$oldEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Gcc -dumpversion 2>$null | ForEach-Object { Write-Host "GCC version: $_" }
$ErrorActionPreference = $oldEap

# Cho toolchain vao dau PATH: cmake goi gcc/g++/ar/ranlib tu do
$env:Path = $GccBin + ";" + $env:Path

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (!$cmake) {
    $vsCmake = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    if (Test-Path $vsCmake) { $cmake = @{ Source = $vsCmake } }
    else { Die "Thieu CMake - cai 'Visual Studio Build Tools' hoac 'winget install Kitware.CMake'." }
}
Write-Host "CMake: $($cmake.Source)"

# Chon generator: Ninja la uu tien (co san tren GitHub runner + MSYS2).
# Du phong: MinGW Makefiles voi make tim duoc canh toolchain.
$genArgs = @()
$ninjaCmd = Get-Command ninja -ErrorAction SilentlyContinue
if ($ninjaCmd) {
    Write-Host "Generator : Ninja ($($ninjaCmd.Source))"
    $genArgs = @("-G", "Ninja")
}
else {
    $makeProg = ""
    foreach ($mk in @(
        (Join-Path $GccBin "mingw32-make.exe"),
        (Join-Path $GccBin "gmake.exe"),
        "C:\Strawberry\c\bin\gmake.exe",
        (Get-Command mingw32-make -ErrorAction SilentlyContinue).Source,
        (Get-Command make -ErrorAction SilentlyContinue).Source
    )) {
        if ($mk -and (Test-Path $mk)) { $makeProg = $mk; break }
    }
    if (!$makeProg) {
        Die "Khong co Ninja va khong co make (mingw32-make/gmake/make). Cai 'choco install ninja -y' roi build lai."
    }
    Write-Host "Generator : MinGW Makefiles ($makeProg)"
    $genArgs = @("-G", "MinGW Makefiles", "-DCMAKE_MAKE_PROGRAM=$makeProg")
}

# --------------------------------------------------------------- std shim (run #37)
Step "Ghi shim <cstdint> + _stdcall MinGW (run #37 + #45)"
# MinGW libstdc++ 13.2 khong khai bao int64_t/uint8_t/size_t cho TU khi
# chi include <string>/<vector>/<unordered_map> (MSVC STL keo gian tiep
# nen tac gia khong bao gio gap loi nay). Chi tiet: PATCH run #37 dau file.
$stdShimPath = Join-Path $NbDir "vieneu_mingw_std_shim.h"
$stdShimText = @'
// vieneu_mingw_std_shim.h -- HCStudio build (run #37 + #45)
//
// Why this file exists:
//   GCC 13.2 (libstdc++) is stricter than the MSVC STL about transitive
//   includes: <string>/<vector>/<unordered_map> do NOT pull in
//   <cstdint> or <cstddef>. Third-party headers of VieNeu-TTS.cpp use
//   int64_t/uint8_t (declared in <cstdint>) and size_t (<cstddef>)
//   without including those headers. MSVC builds fine because its STL
//   drags the declarations in indirectly; MinGW GCC 13.2 fails with
//   "'int64_t' was not declared in this scope".
//   Evidence: CI run after FIX36, v3_native_assets.h:10
//   "std::vector<int64_t> shape;" + gcc hint "is defined in header
//   '<cstdint>'".
//
// This shim is force-included into EVERY C++ TU via
// "-include <this file>" (CMAKE_CXX_FLAGS), declaring the standard
// integer and size types before any project header is parsed. It only
// ADDS standard declarations that proper headers would provide, so it
// is a no-op for well-formed files and fixes ill-formed ones.
// The -D defines from runs #33/#34 stay unchanged. C files
// (CMAKE_C_FLAGS) are untouched on purpose.
//
// run #45 addition: ONNX Runtime 1.20.x headers use the
// single-underscore MS keyword "_stdcall" for ORT_API_CALL
// (onnxruntime_c_api.h line 86: #define ORT_API_CALL _stdcall).
// MinGW GCC does not recognize the single-underscore form as a
// keyword, so the token stays an identifier and every function
// pointer member of OrtApi/OrtApiBase fails to parse
// ("expected ')' before '*' token" at line 323 -> 355 errors,
// CI run #44). ORT >= 1.21 headers switched to "__stdcall"
// (line 90 of v1.24.4) - that is why 1.24.4 built clean.
// Map the single-underscore form onto the real keyword:
// macro expansion happens BEFORE keyword lookup, so this is safe
// whether or not GCC also knows the bare form. On x64 __stdcall is
// accepted and ignored (single calling convention), so there is no
// ABI or link impact. Guarded to MinGW only; inert for ORT >= 1.21
// (they never reference _stdcall anymore).

#pragma once

#include <cstdint>
#include <cstddef>

#if defined(__MINGW32__) || defined(__MINGW64__)
#define _stdcall __stdcall
#endif
'@
[System.IO.File]::WriteAllText($stdShimPath, $stdShimText)
if (!(Test-Path $stdShimPath)) { Die "Khong ghi duoc shim <cstdint> (vieneu_mingw_std_shim.h)." }
Write-Host "Std shim: $stdShimPath"

# run #33/#34: alias THREAD_POWER_THROTTLING_* + _Frees_ptr_opt_ rong
# (chi tiet o PATCH run #33/#34 dau file).
$mingwDefines = "-DTHREAD_POWER_THROTTLING_STATE=PROCESS_POWER_THROTTLING_STATE -DTHREAD_POWER_THROTTLING_CURRENT_VERSION=PROCESS_POWER_THROTTLING_CURRENT_VERSION -DTHREAD_POWER_THROTTLING_EXECUTION_SPEED=PROCESS_POWER_THROTTLING_EXECUTION_SPEED -D_Frees_ptr_opt_="
# run #37 + #45: force-include shim khai bao kieu chuan + anh xa
# _stdcall (ORT 1.20.x) cho MOI C++ TU.
# Path dung forward slash de an toan khi di qua CMake -> Ninja -> gcc.
$stdShimFlag = "-include " + ($stdShimPath -replace "\\", "/")

# run #40: BAN FLAG DANG ARGV ARRAY cho lenh g++ thu cong (buoc api.a ben
# duoi). Cung gia tri voi $mingwDefines/$stdShimFlag o tren nhung da TACH
# tung flag thanh 1 phan tu rieng - chi tiet o PATCH run #40 dau file.
$mingwDefineArr = @(
    "-DTHREAD_POWER_THROTTLING_STATE=PROCESS_POWER_THROTTLING_STATE",
    "-DTHREAD_POWER_THROTTLING_CURRENT_VERSION=PROCESS_POWER_THROTTLING_CURRENT_VERSION",
    "-DTHREAD_POWER_THROTTLING_EXECUTION_SPEED=PROCESS_POWER_THROTTLING_EXECUTION_SPEED",
    "-D_Frees_ptr_opt_="
)
# Dang GAN (khong khoang trang giua -include va path): quote-proof, hop le
# voi gcc cpp. Path dung forward slash nhu $stdShimFlag.
$stdShimFlagForGcc = "-include" + ($stdShimPath -replace "\\", "/")

# --------------------------------------------------------------- cmake build
# ---------------- run #47: Rust toolchain cho sea-g2p (phonemizer chuan)
# Space HF + wheel vieneu deu phonemize bang sea-g2p truoc khi tokenize.
# Core chi dung sea-g2p khi VIENEU_USE_SEA_G2P duoc define (CMake bat khi
# -DVIENEU_SEA_G2P=ON) va dict sea_g2p.bin nam canh exe luc chay.
# CMake se goi "cargo build --release" (custom target vieneu-sea-g2p-rust)
# nen cargo PHAI co mat trong PATH truoc khi configure. Runner CI khong co
# Rust san -> tu cai rustup stable-msvc profile minimal (VS Build Tools co
# san tren runner nen linker MSVC cua Rust chay binh thuong).
Step "Rust/cargo cho sea-g2p (run #47)"
$cargoExe = ""
$cmdCargo = Get-Command cargo -ErrorAction SilentlyContinue
if ($cmdCargo) { $cargoExe = $cmdCargo.Source }
if (!$cargoExe) {
    $cargoHomeExe = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
    if (Test-Path $cargoHomeExe) { $cargoExe = $cargoHomeExe }
}
if (!$cargoExe) {
    Write-Host "Khong thay cargo - cai dat rustup (stable msvc, profile minimal)..."
    $rustupInit = Join-Path $NbDir "rustup-init.exe"
    $oldSec = [Net.ServicePointManager]::SecurityProtocol
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -OutFile $rustupInit -UseBasicParsing
    [Net.ServicePointManager]::SecurityProtocol = $oldSec
    if (!(Test-Path $rustupInit)) { Die "Tai rustup-init.exe that bai (run #47)." }
    & $rustupInit -y --default-toolchain stable-x86_64-pc-windows-msvc --profile minimal --no-modify-path
    if ($LASTEXITCODE -ne 0) { Die "rustup-init that bai (run #47)." }
    $cargoExe = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
    if (!(Test-Path $cargoExe)) { Die "cargo.exe khong ton tai sau khi cai rustup (run #47)." }
}
$cargoBinDir = Split-Path -Parent $cargoExe
if (($env:PATH -split ";") -notcontains $cargoBinDir) {
    $env:PATH = $cargoBinDir + ";" + $env:PATH
}
Write-Host ("cargo: " + $cargoExe)

Step "Bien dich vieneu-tts-core (static, GCC MinGW)"
$BuildDir = Join-Path $NbDir "vnbuild"

$cfgArgs = @(
    "-S", $VnRepoDir,
    "-B", $BuildDir
) + $genArgs + @(
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_C_COMPILER=$Gcc",
    "-DCMAKE_CXX_COMPILER=$Gpp",
    "-DCMAKE_MAKE_PROGRAM=$(if ($ninjaCmd) { $ninjaCmd.Source } else { $makeProg })",
    "-DONNXRUNTIME_ROOT=$ortRoot",
    "-DVIENEU_LLAMA_DIR=$(Join-Path $VnRepoDir 'third_party\llama.cpp')",
    "-DVIENEU_BUILD_STATIC_ONLY=ON",
    "-DVIENEU_BUILD_CLI=OFF",
    "-DVIENEU_BUILD_TESTS=OFF",
    # run #47: bat phonemizer sea-g2p chuan (Rust) - bang chung chat luong
    # Space: model an PHONEME, khong an text tho. CMake tu build cargo +
    # define VIENEU_USE_SEA_G2P cho core + link import lib. Dict bin ship
    # canh exe o buoc thu thap ben duoi.
    "-DVIENEU_SEA_G2P=ON",
    # run #33: alias THREAD_POWER_THROTTLING_* -> PROCESS_POWER_THROTTLING_*
    # (header mingw-w64 cu thieu ban THREAD_; 2 ban identical ve layout+gia tri).
    # run #34: _Frees_ptr_opt_ = SAL annotation MSVC chi co trong sal.h cua
    # Windows SDK 2015+; header mingw cu khong co -> define RONG (no-op).
    # run #37: CXX them "-include <shim>" khai bao <cstdint>/<cstddef>
    # cho GCC 13.2 (chi tiet o PATCH run #37 dau file). C flags giu nguyen.
    # 1 argv duy nhat co khoang trang: PS quote thanh 1 tham so, CMake lay
    # toan bo phan sau '=' lam gia tri CMAKE_C_FLAGS.
    "-DCMAKE_C_FLAGS=$mingwDefines",
    "-DCMAKE_CXX_FLAGS=$mingwDefines $stdShimFlag"
)

& $cmake.Source @cfgArgs
if ($LASTEXITCODE -ne 0) { Die "CMake configure that bai (GCC + generator da chon). Gui log nay cho developer." }

& $cmake.Source --build $BuildDir --target vieneu-tts-core
if ($LASTEXITCODE -ne 0) { Die "CMake build that bai. Gui log nay cho developer." }

# --------------------------------------------------------------- thu thap .a
Step "Thu thap cac archive .a tu build tree"
$coreDst = Join-Path $NbDir "vieneu-tts-core.a"
if (Test-Path $coreDst) { Remove-Item $coreDst -Force }

$allArchives = @()
Get-ChildItem -Path $BuildDir -Recurse -Filter "*.a" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_.FullName
    if ($p -match '\\CMakeFiles\\') { return }
    if ($p -match '\.dll\.a$') { return }
    if ($p -match 'vieneu[-_]?tts[-_]?core') { return }   # them duoi ten moi o duoi
    # run #47: staticlib/rlib cua rust (libsea_g2p_rs.a neu cargo gnu hoac
    # .rlib) KHONG link truc tiep vao nhom - chi link qua import lib cua
    # sea_g2p_rs.dll o buoc thu thap ben duoi (tranh symbol trung/dung CRT
    # khac gach giua MinGW va Rust).
    if ($p -match 'sea_g2p') { return }
    $allArchives += $p
}

$coreSrc = Get-ChildItem -Path $BuildDir -Recurse -Filter "*.a" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\CMakeFiles\\' -and $_.Name -match 'vieneu[-_]?tts[-_]?core' } |
    Select-Object -First 1
if (!$coreSrc) {
    Die "Khong thay archive vieneu-tts-core (.a) trong build tree. Co the CMake chua build target nay - gui log CMake build cho developer."
}
Copy-Item $coreSrc.FullName $coreDst -Force
Write-Host "Core : $coreDst ($([math]::Round((Get-Item $coreDst).Length / 1MB, 1)) MB)"
Write-Host "Memb : $($allArchives.Count) archive .a khac (ggml/llama/...)"
foreach ($a in $allArchives) { Write-Host "  - $a" }

# ---------------- PATCH run #39 + #40: C API wrapper cho cgo
Step "Bien dich vieneu_tts.cpp -> vieneu-tts-api.a (run #39)"
$apiSrc = Join-Path $VnRepoDir "src\vieneu\vieneu_tts.cpp"
if (!(Test-Path $apiSrc)) { Die "Khong thay $apiSrc trong repo vieneu (@cc037cf)." }
$apiObj     = Join-Path $NbDir "vieneu_tts_api.o"
$apiArchive = Join-Path $NbDir "vieneu-tts-api.a"
$ortIncDir  = Join-Path $ortRoot "include"
$llamaDir   = Join-Path $VnRepoDir "third_party\llama.cpp"
if (!(Test-Path $ortIncDir)) { Die "Khong thay include dir cua ORT SDK ($ortIncDir)." }

# run #40: MOI flag 1 phan tu argv - KHONG gop cac flag co khoang trang
# thanh 1 chuoi. Chi tiet o PATCH run #40 dau file.
$apiArgs = @(
    "-std=c++17", "-O2", "-DVIENEU_STATIC", "-fopenmp"
) + $mingwDefineArr + @(
    $stdShimFlagForGcc,
    "-I" + (Join-Path $VnRepoDir "src"),
    "-I" + $VnRepoDir,
    "-I" + (Join-Path $llamaDir "include"),
    "-I" + (Join-Path $llamaDir "ggml\include"),
    "-I" + (Join-Path $llamaDir "vendor"),
    "-I" + $ortIncDir,
    "-I" + (Join-Path $VnRepoDir "third_party\sea-g2p\include"),
    "-c", $apiSrc, "-o", $apiObj
)
$q = '"'
$cmdEcho = ($apiArgs | ForEach-Object { if ("$_" -match " ") { $q + $_ + $q } else { $_ } }) -join " "
Write-Host ("CMD : " + $Gpp + " " + $cmdEcho)
& $Gpp @apiArgs
if ($LASTEXITCODE -ne 0) { Die "Khong bien dich duoc vieneu_tts.cpp (run #39)." }

$arExeApi = Join-Path $GccBin "ar.exe"
if (!(Test-Path $arExeApi)) { Die "Khong thay ar.exe canh g++ ($GccBin)." }
if (Test-Path $apiArchive) { Remove-Item $apiArchive -Force }
& $arExeApi rcs $apiArchive $apiObj
if ($LASTEXITCODE -ne 0 -or !(Test-Path $apiArchive)) { Die "Khong dong goi duoc vieneu-tts-api.a (ar rcs that bai)." }
Write-Host ("API : " + $apiArchive + " (" + [math]::Round((Get-Item $apiArchive).Length / 1KB, 1) + " KB)")

# --------------------------------------------------------------- import lib ORT
Step "Sinh import lib GNU cho onnxruntime (objdump -> .def -> dlltool)"

$objdumpExe = ""
if (Test-Path (Join-Path $GccBin "objdump.exe")) { $objdumpExe = Join-Path $GccBin "objdump.exe" }
elseif (Test-Path "C:\Strawberry\c\bin\objdump.exe") { $objdumpExe = "C:\Strawberry\c\bin\objdump.exe" }
else {
    $od = Get-Command objdump -ErrorAction SilentlyContinue
    if ($od) { $objdumpExe = $od.Source }
}

function Get-PeExportNames([string]$dllPath) {
    # PE parser thuan PowerShell (du phong khi khong co objdump). PE32+ only.
    $b = [System.IO.File]::ReadAllBytes($dllPath)
    if ($b.Length -lt 264) { return @() }
    $peOff = [BitConverter]::ToInt32($b, 0x3C)
    if ($peOff -le 0 -or ($peOff + 264) -ge $b.Length) { return @() }
    if ([BitConverter]::ToUInt16($b, $peOff) -ne 0x4550) { return @() }
    $coff    = $peOff + 4
    $numSec  = [BitConverter]::ToUInt16($b, $coff + 2)
    $optSize = [BitConverter]::ToUInt16($b, $coff + 16)
    $opt     = $coff + 20
    if ([BitConverter]::ToUInt16($b, $opt) -ne 0x20B) { return @() }
    $expRva = [BitConverter]::ToUInt32($b, $opt + 112)
    if ($expRva -eq 0) { return @() }
    $secTab = $opt + $optSize
    $sVa = 0; $sRo = 0; $found = $false
    for ($i = 0; $i -lt $numSec; $i++) {
        $s  = $secTab + 40 * $i
        $va = [BitConverter]::ToUInt32($b, $s + 12)
        $vz = [BitConverter]::ToUInt32($b, $s + 8)
        $rs = [BitConverter]::ToUInt32($b, $s + 16)
        $ro = [BitConverter]::ToUInt32($b, $s + 20)
        if ($expRva -ge $va -and $expRva -lt ($va + [Math]::Max($vz, $rs))) {
            $sVa = $va; $sRo = $ro; $found = $true; break
        }
    }
    if (!$found) { return @() }
    $eo = ($expRva - $sVa) + $sRo
    $numNames = [BitConverter]::ToUInt32($b, $eo + 24)
    if ($numNames -le 0 -or $numNames -gt 100000) { return @() }
    $namesRva = [BitConverter]::ToUInt32($b, $eo + 32)
    $no = ($namesRva - $sVa) + $sRo
    $names = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $numNames; $i++) {
        $nrva = [BitConverter]::ToUInt32($b, $no + 4 * $i)
        if ($nrva -le 0) { continue }
        $p = ($nrva - $sVa) + $sRo
        if ($p -lt 0 -or $p -ge $b.Length) { continue }
        $end = $p
        while ($end -lt $b.Length -and $b[$end] -ne 0) { $end++ }
        $names.Add([System.Text.Encoding]::ASCII.GetString($b, $p, $end - $p))
    }
    return $names.ToArray()
}

$exportNames = @()
if ($objdumpExe) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $odOut = & $objdumpExe -p $ortDll 2>$null
    $ErrorActionPreference = $oldEap
    $inNames = $false
    foreach ($ln in @($odOut)) {
        if ($ln -match '\[Ordinal/Name Pointer\] Table') { $inNames = $true; continue }
        if ($inNames) {
            if ($ln -match '^\s*\[\s*\d+\]\s+(\S+)\s*$') { $exportNames += $Matches[1] }
            else { $inNames = $false }
        }
    }
    Write-Host "objdump: $($exportNames.Count) export tu $objdumpExe"
}
if ($exportNames.Count -eq 0) {
    $exportNames = @(Get-PeExportNames $ortDll)
    Write-Host "PE parser (du phong): $($exportNames.Count) export"
}

$ortImportGnu = Join-Path $NbDir "libonnxruntime.a"
$dlltoolExe   = ""
if (Test-Path (Join-Path $GccBin "dlltool.exe")) { $dlltoolExe = Join-Path $GccBin "dlltool.exe" }
else {
    $dt = Get-Command dlltool -ErrorAction SilentlyContinue
    if ($dt) { $dlltoolExe = $dt.Source }
}

$ortLinkLine = ""
if ($exportNames.Count -gt 0 -and $dlltoolExe) {
    $defFile = Join-Path $NbDir "onnxruntime.def"
    $defLines = @("LIBRARY onnxruntime.dll", "EXPORTS")
    foreach ($n in $exportNames) { $defLines += $n }
    $defLines | Set-Content $defFile -Encoding ASCII
    & $dlltoolExe -d $defFile -D $ortDll -l $ortImportGnu -m i386:x86-64
    if ($LASTEXITCODE -eq 0 -and (Test-Path $ortImportGnu)) {
        $ortLinkLine = $ortImportGnu
        Write-Host "[OK] dlltool -> $ortImportGnu"
    }
}
if (!$ortLinkLine) {
    # Fallback cuoi: ld doc duoc short import lib MSVC; CGO_LDFLAGS_ALLOW
    # cua build.ps1 da cho phep .lib (tinh huong du phong chinh thuc).
    $ortLinkLine = $ortLib
    Write-Host "CANH BAO: dung lai onnxruntime.lib (dlltool/objdump khong kha dung)." -ForegroundColor Yellow
}

# ---------------- run #47: sea-g2p runtime (DLL + dict) cho phonemizer chuan
# CMake custom target da build cargo --release ra sea_g2p_rs.dll trong
# vnbuild\sea-g2p\release. Thu thap: DLL + dict bin -> native-build\ de
# build.ps1 ship vao dist\; sinh import lib GNU tu exports (dung lai co
# che objdump -> .def -> dlltool cua ORT).
Step "Thu thap sea-g2p runtime (run #47)"
$seaReleaseDir = Join-Path $BuildDir "sea-g2p\release"
$seaDll = Join-Path $seaReleaseDir "sea_g2p_rs.dll"
if (!(Test-Path $seaDll)) { Die "Khong thay sea_g2p_rs.dll ($seaReleaseDir) - cargo build that bai hoac CMake chua bat VIENEU_SEA_G2P. Gui log." }
$seaDictSrc = Join-Path $VnRepoDir "third_party\sea-g2p\python\sea_g2p\sea_g2p.bin"
if (!(Test-Path $seaDictSrc)) { Die "Khong thay sea_g2p.bin trong submodule sea-g2p ($seaDictSrc) - submodule chua duoc init?" }
Copy-Item $seaDll (Join-Path $NbDir "sea_g2p_rs.dll") -Force
$seaDictDst = Join-Path $NbDir "sea_g2p.bin"
Copy-Item $seaDictSrc $seaDictDst -Force
Write-Host ("DLL : " + [Math]::Round((Get-Item $seaDll).Length / 1MB, 1) + " MB")
Write-Host ("DICT: " + [Math]::Round((Get-Item $seaDictDst).Length / 1MB, 1) + " MB")

# Sinh import lib GNU cho sea_g2p_rs.dll: objdump quet exports -> .def ->
# dlltool (giong dung flow onnxruntime o tren). Fallback: import lib MSVC
# cua cargo (sea_g2p_rs.dll.lib) - ld doc duoc short import lib (ORT lib
# da chung minh); CGO_LDFLAGS_ALLOW cua build.ps1 cho phep .lib.
$seaExports = @()
if ($objdumpExe) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $odSea = & $objdumpExe -p $seaDll 2>$null
    $ErrorActionPreference = $oldEap
    $inSea = $false
    foreach ($ln in @($odSea)) {
        if ($ln -match '\[Ordinal/Name Pointer\] Table') { $inSea = $true; continue }
        if ($inSea) {
            if ($ln -match '^\s*\[\s*\d+\]\s+(\S+)\s*$') { $seaExports += $Matches[1] }
            else { $inSea = $false }
        }
    }
    Write-Host "objdump: $($seaExports.Count) export tu sea_g2p_rs.dll"
}
$seaLinkLine = ""
$seaImportGnu = Join-Path $NbDir "libsea_g2p_rs.a"
if ($seaExports.Count -gt 0 -and $dlltoolExe) {
    $seaDefFile = Join-Path $NbDir "sea_g2p_rs.def"
    $seaDefLines = @("LIBRARY sea_g2p_rs.dll", "EXPORTS")
    foreach ($n in $seaExports) { $seaDefLines += $n }
    $seaDefLines | Set-Content $seaDefFile -Encoding ASCII
    & $dlltoolExe -d $seaDefFile -D $seaDll -l $seaImportGnu -m i386:x86-64
    if ($LASTEXITCODE -eq 0 -and (Test-Path $seaImportGnu)) {
        $seaLinkLine = $seaImportGnu
        Write-Host "[OK] dlltool -> $seaImportGnu"
    }
}
if (!$seaLinkLine) {
    $seaMsvcLib = Join-Path $seaReleaseDir "sea_g2p_rs.dll.lib"
    if (Test-Path $seaMsvcLib) {
        Copy-Item $seaMsvcLib (Join-Path $NbDir "sea_g2p_rs.dll.lib") -Force
        $seaLinkLine = Join-Path $NbDir "sea_g2p_rs.dll.lib"
        Write-Host "CANH BAO: dung sea_g2p_rs.dll.lib (MSVC) - dlltool/objdump khong kha dung." -ForegroundColor Yellow
    } else {
        Die "Khong sinh duoc import lib cho sea_g2p_rs.dll (run #47)."
    }
}

# --------------------------------------------------------------- linker manifest
Step "Sinh native-build\link-libs.txt"
# run #39: vieneu-tts-api.a ghi o DONG DAU TIEN. Nhom link cua build.ps1
# quet lai nhieu vong (--start-group/--end-group) nen thu tu khong quan
# trong, nhung dat truoc de log doc de hieu.
$lines = @($apiArchive)
foreach ($a in $allArchives) { $lines += $a }
$lines += $ortLinkLine
# run #47: import lib cua sea_g2p_rs.dll (phonemizer chuan). Nhom link
# quet lai nhieu vong nen vi tri khong quan trong; dat sau ORT cho de doc.
$lines += $seaLinkLine
$lines += "-fopenmp"
$lines += "-lstdc++"
$lines += "-ladvapi32"
$lines += "-lole32"
$lines += "-loleaut32"
$lines += "-luser32"
$lines += "-lws2_32"
$lines += "-lbcrypt"
$lines | Set-Content (Join-Path $NbDir "link-libs.txt") -Encoding ASCII

# copy ORT dll ra native-build de build.ps1 ship vao dist\
Copy-Item $ortDll (Join-Path $NbDir "onnxruntime.dll") -Force

Write-Host ""
Write-Host "[OK] prepare-vieneu hoan tat:" -ForegroundColor Green
Write-Host ("     " + $coreDst)
Write-Host ("     " + $apiArchive)
Write-Host ("     " + (Join-Path $NbDir "link-libs.txt"))
Write-Host ("     " + $ortLinkLine)
Write-Host ("     " + (Join-Path $NbDir "onnxruntime.dll"))
Write-Host ("     " + $seaLinkLine)
Write-Host ("     " + (Join-Path $NbDir "sea_g2p_rs.dll"))
Write-Host ("     " + (Join-Path $NbDir "sea_g2p.bin"))
