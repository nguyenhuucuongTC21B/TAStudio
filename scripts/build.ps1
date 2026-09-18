#Requires -Version 5.1
<#
.SYNOPSIS
    HCStudio v5.0 - Mot lenh build ra file HCStudio.exe duy nhat.

.DESCRIPTION
    Kich ban Lite (mac dinh):
        Go thuan + frontend embed + SAPI5 -> dist\HCStudio-Lite.exe, <2 phut.
        Chay tren moi may Windows chi can Go + WebView2 (co san Win10/11).

    Kich ban Full (-Full):
        Them tang Neural VieNeu v3 Turbo: clone VieNeu-TTS.cpp @commit pinned,
        build static lib bang GCC MinGW/Ninja + ONNX Runtime, sau do
        go build -tags vieneu -> binary ~60-90 MB chua tron engine neural.
        Trong so model KHONG nam trong exe - app tu tai khi nguoi dung chay.

    PATCH run #11 (link stage - toan bo toolchain MinGW):
        - Go linker LUON link cgo bang ld mingw (-lmingwex -lmingw32), va
          ld khong doc duoc symbol index cua mot so archive VS2026 =>
          undefined references. Giai phap: C++ cung build bang GCC =>
          moi archive la .a GNU, ld doc 100%. Chi con onnxruntime.dll la
          binary MSVC (C API), import lib da duoc chuyen sang dlltool.
        - DLL runtime: libgcc_s_seh-1.dll, libwinpthread-1.dll,
          libstdc++-6.dll, libgomp-1.dll (tu thu muc bin cua gcc) +
          onnxruntime.dll -> dist\.

    PATCH run #12/#13:
        - prepare-vieneu.ps1 khong dung dumpbin nua (doc export cua
          onnxruntime.dll bang PE parser thuan PowerShell + du phong
          objdump / dung lai onnxruntime.lib).
        - Toan bo archive (.a) boc trong -Wl,--start-group ...
          -Wl,--end-group. GNU ld quet nhom den khi het symbol chua
          resolve => KHONG con rui ro sai thu tu archive (nguyen nhan
          82 undefined ref C++ o run #11). Hai flag nay nam SAN trong
          safelist cua go (security.go: -Wl,--start-group L227,
          -Wl,--end-group L212). *.a khop "direct linker inputs" (L237).
          Chi .lib (du phong) phai CGO_LDFLAGS_ALLOW.
        - PATCH run #13: BO HOAN TOAN ky tu backtick (byte 0x60) trong
          file nay. Ban chay #13 bi hong khi copy qua chat: backtick-quote
          bi mat ky tu => loi parse. Moi chuoi giu nguyen quote duoc viet
          lai bang bien $q. Kiem tra file khong con backtick: trong Python
          chay  open('scripts/build.ps1','rb').read().count(chr(96).encode())
          => ket qua phai bang 0.

    PATCH run #23 (quet import DLL - het bao "not found" mo loa):
        - Run #22 da chua xong artifact (workflow upload nguyen dist) nhung
          exe khi chay tren may that bao lan luot: libgomp-1.dll (da ship
          tu truoc) roi... libdl.dll - DLL cua tang dlfcn (dlopen/dlsym)
          trong toolchain MinGW cua runner, KHONG phai DLL chuan Windows,
          khong the doan truoc tu ben ngoai.
        - Nguyen nhan: mot member trong cac archive C/C++ co tham chieu
          ham dlopen*; khi link, ld tim thay import lib ten "libdl" trong
          cay thu muc toolchain => ghi "libdl.dll" vao import table cua
          exe. May nguoi dung khong co file nay => "was not found".
        - Fix (cham dut ca loai loi nay): ngay sau go build, dung objdump
          -x (chinh toolchain da link) quet TOAN BO "DLL Name:" ma exe
          can. Moi DLL KHONG phai DLL he thong ma chua co trong dist\
          se duoc tu dong tim trong cac thu muc toolchain (bin cua gcc,
          lib, PATH...) va copy vao dist. Van thieu => DIE som voi danh
          sach ro rang de log CI de phan tich - khong bao gio giao
          artifact khong chay duoc cho nguoi dung.

    PATCH run #24 (dl shim - cat thuoc tan goc phu thuoc libdl.dll):
        - Run #23 cho thay runner CHI co import lib "libdl.dll.a" (goi
          dlfcn trong toolchain Strawberry Perl), KHONG co file
          libdl.dll that => khong the copy de ship. Exe van bao
          "libdl.dll was not found" tren may nguoi dung.
        - Nguyen nhan san sang con: vai member trong cac archive C/C++
          tham chieu ham dlfcn (dlopen/dlsym/...). Khi link, ld nhat
          import lib libdl trong cay thu muc => exe doi 1 DLL ma khong
          noi tren runner co de copy.
        - Fix tan goc: DINH NGHIA lai toan bo API dl bang shim C
          (vieneu_dl_shim.c - wrapper LoadLibraryA/GetProcAddress/
          FreeLibrary cua Windows), compile thanh .o bang chinh gcc,
          dat O DAU link group => ld resolve dlopen* noi bo, khong con
          tra cuu libdl.dll.a => import table exe khong con libdl.dll.
          Khong phu thuoc runner co dll hay khong. CGO_LDFLAGS_ALLOW
          them moi .o (escape hatch chinh thuc cua go).
        - Buoc quet import cua run #23 giu nguyen: gio la buoc XAC
          NHAN - danh sach DLL cua exe phai khong con libdl.dll.

    PATCH run #25 (shim goi thanh ARCHIVE - het loi multiple definition):
        - Run #24 rot o BUOC LINK: ld bao "multiple definition of
          dlerror/dlclose/dlopen/dlsym/dladdr" cho vieneu_dl_shim.o.
        - Nguyen nhan: go build dua noi dung CGO_LDFLAGS cua env len
          dong lenh host linker 2 LAN (mot lan qua chi thi //go:cgo_ldflag
          ma cgo nhung vao object cua package, mot lan qua duong
          -extldflags cua buoc link ngoai - xem cmd/go internal/work/
          exec.go L3221 va L3394-3399). Group xuat hien troi deu 2 lan
          trong lenh gcc. Day la hanh vi co huu cua toolchain, ton tai
          tu run #21: truyen .a 2 lan VO HAI (ld chi pull member theo
          nhu cau, member da nap se khong nap lai) - nen run #21..#23
          deu xanh. Nhung truyen file .o 2 lan = ld noi toan bo symbol
          cua no 2 lan = "multiple definition" = chet o buoc link.
        - Fix: sau khi compile shim.c -> .o, dong goi thanh archive
          vieneu-dl-shim.a bang "ar rcs" (ar cung bo binutils voi gcc),
          roi dua ARCHIVE vao group thay cho .o. Archive bi lap lai la
          an toan tuyet doi - dung co che da chinh minh tu run #21.
        - Them luoi an toan: -Wl,--allow-multiple-definition (co san
          trong safelist cua go, security.go L200): neu van con symbol
          trung tu nguon khac, ld lay dinh nghia dau tien thay vi bao
          loi. Khong thay doi hanh vi khi khong co symbol trung.

    PATCH run #26 (shim ve CUOI group + exe tu khai minh danh tinh):
        - Bao cao nguoi dung: dialog "libdl.dll was not found" VAN xuat
          hien tren may that. Neu run #25 XANH thi dieu nay VO LY: buoc
          quet import se DIE som neu exe con can libdl.dll (runner khong
          co file that nay - chung minh o run #23), con run DO thi khong
          sinh duoc exe moi. Ket luan: exe dang chay gan nhu chac chan
          LA EXE CU, vi ten artifact moi run GIONG HET NHAU (rat de tai
          nham artifact cua run #22/23) hoac run #25 do chua tao duoc
          exe moi. Buoc 2 (giai nen vao thu muc moi) khong giup gi khi
          thung chua artifact ban dau da la cua run cu.
        - Van de ky thuat con sot trong v25: shim dat O DAU nhom; luc
          ld quet den shim thi chua co member nao tham chieu dl* (cac
          archive tham chieu dl* nam SAU shim) - shim chi duoc nap neu
          ld co quet lai nhom them vong. v26 dua shim ve CUOI nhom:
          trong chinh luot quet dau, cac archive da keo member tham
          chieu dl* vao (dl* thanh undefined), den shim cuoi nhom la
          chap ngay => chac chan duoc nap trong mot luot quet duy nhat,
          khong phu thuoc vong quet lai cua --start-group.
        - Exe tu khai minh danh tinh: ghi BUILD-INFO.txt (dat canh exe
          trong dist, ghi che do build, thoi gian UTC, so run CI, va
          SHA256 cua exe) dong thoi in SHA256 vao log CI. Nguoi dung
          chi can chay Get-FileHash tren may minh va so voi log: hash
          khac nhau = dang chay exe cu, khong can doan doan.
        - Chan cuoi khong can objdump: doc toan bo byte cua exe, neu
          van con chuoi "libdl.dll" trong body exe thi Die ngay - khong
          bao gio giao ra artifact co exe keo libdl.dll.

        PATCH run #27 (ship libdl.dll RIENG + quet TAT CA PE trong dist):
        - Run v26 XANH, exe da SACH libdl (chan byte pass) - nhung tren
          may nguoi dung van xuat hien "libdl.dll was not found". Giai
          thich duy nhat con lai: mot DLL trong dist\ (nghi van so 1:
          libgomp-1.dll, OpenMP runtime cua toolchain) TU KEO import
          libdl.dll. Loader Windows luon ghi ten EXE goc tren hop thoai
          loi, du nguon goc la DLL con - nen tro nhu exe bi loi.
        - Lo hong that: buoc quet import (run #23) chi quet app exe,
          KHONG quet DLL - nen ke keo libdl.dll khong bao gio bi phat
          hien tren runner.
        - Hai hanh dong cua v27:
          (1) Tu bien dich shim thanh libdl.dll THAT (gcc -shared,
              dllexport dlopen/dlsym/dlclose/dlerror/dladdr) va ship
              vao dist\. Ke nao import libdl.dll cung tim thay ngay
              canh exe => het dialog "was not found" MOI truong hop,
              khong phai biet ke la ai moi chua duoc.
          (2) Quet import mo rong cho TAT CA file .exe/.dll trong
              dist\, in day du danh sach import tung file => log CI
              se chi danh ro DLL nao dang keo libdl.dll (hoac DLL nao
              khac thieu) ngay tren runner, khong doan doan nua.

        PATCH run #28 (them build tags Wails: desktop,production):
        - Chung minh thu cong cua nguoi dung: tu copy libdl.dll (goi
          dlfcn cua MSYS2) canh exe => loader DA PASS, het dialog
          "libdl.dll was not found". Exe chay den runtime Wails va lo
          MOI xuat hien: "Wails applications will not build without
          the correct build tags. Please use 'wails build' or press
          'OK' to open the documentation on how to use 'go build'"
          (OK mo wails.io/docs/guides/manual-builds).
        - Nguyen nhan: wails CLI khi build luon them 2 build tags
          "desktop,production" (build dev la "desktop,dev"). Build
          bang go build thuan ma thieu tags => runtime Wails coi day
          la dev build, khong mo assets embed ma doi frontend dev
          server => hien message box nay roi thoat. Cac run truoc
          khong bao gio thay loi nay vi exe chet o tang loader (thieu
          DLL) TRUOC khi kip den runtime Wails.
        - Fix: them tags vao MOI lenh go build:
            Lite: -tags desktop,production
            Full: -tags desktop,production,vieneu
          Khong doi cho nao khac. v27 giu nguyen (ship libdl.dll +
          quet TAT CA PE trong dist) vi khong co libdl.dll thi loader
          lai chet ngay tren may khong co goi MSYS2 dlfcn.

        PATCH run #29 (app TU CHAN DOAN - het canh mu thong tin):
        - Nguoi dung bao: exe DA KHOI DONG DUOC (moc lich su 28 run) nhung
          (a) khong xuat duoc giong doc, (b) khong thay nut tai mo hinh /
          nghe thu, (c) khong biet log loi nam o dau. Ta dang MUY hoan toan
          phia may nguoi dung: khong console, khong log gi ca.
        - Fix 3 lop trong chinh source app (build script chi them buoc
          kiem tra input o duoi):
            + diaglog.go (MOI, goc repo): logger ghi append vao
              %LOCALAPPDATA%\HCStudio\logs\hcstudio.log va hcstudio.log
              canh exe; method WriteLog duoc Wails bind cho JS goi vao.
            + app.go/main.go: ghi snapshot startup (neuralLinked, file
              model con thieu, danh sach giong SAPI that), log resolve/
              synth/play/export/modeldl, va FIX bug that: loi PlayJob
              khi autoplay TRUOC DAY bi bo quen am tham (tong hop xong
              100% ma khong co tieng nao, khong bao loi).
            + frontend/dist/index.html: khoi chan doan ES5 dat DAU <head>:
              bat moi loi JS => banner DO tren man hinh + ghi log; bao
              dong neu bridge.js chet (nut Phat keet disabled vinh vien)
              hoac app chay o che do MOCK (window.go khong co mat).
        - Buoc "Kiem tra file chan doan run #29" o duoi DIE som neu repo
          chua duoc cap nhat day du 3 file (bai hoc run #26: khong kiem
          tra thi file thieu/cu lan nhau den khong biet).

        PATCH run #36 (SOT cua run #35: build.ps1 van truyen ORT 1.20.1):
        - Symptom run sau #35: log van hien -isystem ort_sdk/onnxruntime-
          win-x64-1.20.1/include va loi cu quay lai dung tai file duy nhat
          vieneu_v3_onnx_engine.cpp:117 "'CUDAProviderOptions' is not a
          member of 'Ort'" (neucodec_onnx.cpp + vieneu.cpp van OK).
        - Root cause: run #35 doi default OnnxRuntimeVersion trong
          prepare-vieneu.ps1 (1.20.1 -> 1.24.4) NHUNG sot build.ps1:
          tham so $OnnxRuntimeVersion cua build.ps1 van la "1.20.1" va
          build.ps1 LUON truyen -OnnxRuntimeVersion xuong khi goi
          prepare-vieneu.ps1. Tham so tuyen minh tu build.ps1 DE DAY
          default moi cua script con -> runner van nhan 1.20.1. Workflow
          build.yml khong truyen tham so nay -> gia tri sai den tu chinh
          default build.ps1 (bang chung: rg 'OnnxRuntimeVersion'
          .github/workflows/build.yml = 0 ket qua).
        - Fix: doi default $OnnxRuntimeVersion cua build.ps1 thanh
          "1.24.4". prepare-vieneu.ps1 giu nguyen tu FIX35 (default cua
          no da la 1.24.4). Hai default nay PHAI KHOP nhau luon - neu
          doi thi doi ca hai.

        PATCH run #39 (link cgo static: -DVIENEU_STATIC trong CGO_CFLAGS):
        - Symptom run #38: link cgo chet voi 8 undefined reference dang
          "__imp_vieneu_*" (C API trong vieneu_tts.h ma driver_cgo.go
          goi).
        - Root cause: CGO_CFLAGS thieu -DVIENEU_STATIC => vieneu_tts.h
          khai bao VIENEU_API dang dllimport (stub __imp_vieneu_* chi
          ton tai khi link voi DLL). Dong thoi target static
          vieneu-tts-core KHONG chua vienneu_tts.cpp (thuoc target DLL)
          nen plain vieneu_* cung khong co defined nao.
        - Fix: them -DVIENEU_STATIC vao CGO_CFLAGS. LUU Y QUAN TRONG
          (bai hoc run #40): -DVIENEU_STATIC phai la MOT FIELD RIENG
          trong CGO_CFLAGS - KHONG gop chung voi -I trong CUNG 1 ngoac
          kep vi Go tach CGO_CFLAGS theo field co quote: gop chung se
          tao 1 token "-DVIENEU_STATIC -I..." ma gcc hieu sai giong
          het loi argv cua run #40. Phan dinh nghia plain vieneu_* do
          native-build\vieneu-tts-api.a cung cap (run #39 cua
          prepare-vieneu.ps1, dong dau tien cua link-libs.txt, nam
          trong nhom --start-group/--end-group o duoi).

    LUU Y: File nay CHI DUNG KY TU ASCII (khong dau tieng Viet) de tranh
    loi encoding khi chay bang Windows PowerShell 5.1 (powershell.exe).
    Dung sua thanh tieng Viet co dau trong file nay.

.EXAMPLE
    .\scripts\build.ps1              # Lite
    .\scripts\build.ps1 -Full        # Full neural
    .\scripts\build.ps1 -Full -Clean # don native cache truoc khi build
#>
param(
    [switch]$Full,
    [switch]$DebugExe, # PATCH FIX51: chi build HCStudio-debug.exe khi co co nay
    
    [switch]$Clean,
    # run #44: quay lai 1.20.1 - PHAI khop voi default trong
    # prepare-vieneu.ps1. ORT 1.24.4 crash 100% trong vieneu_init_v2
    # ("signal arrived during external code execution" - console-out.txt
    # run #43) tren may user CPU-only; 1.20.1 (run #30) on dinh. Core duoc
    # patch bo khoi CUDA EP (run #44 cua prepare-vieneu.ps1) de compile
    # xanh voi header 1.20.1.
    [string]$OnnxRuntimeVersion = "1.20.1",
    [string]$VieneuCommit       = "cc037cf4475cad9b68f16cd9de9c76473cc3640b"
)

 $ErrorActionPreference = "Stop"
 $ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

 $RepoRoot = Split-Path -Parent $PSScriptRoot
 $DistDir  = Join-Path $RepoRoot "dist"

# PATCH run #13: khong dung backtick trong toan bo file. Can quote mot path
# (co khoang trang) thi dung bien $q (ky tu double-quote) thay cho chuoi
# escape backtick-quote da bi mat ky tu khi copy qua chat.
 $q = '"'

function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Die($msg)  { Write-Host ""; Write-Host "[XX] $msg" -ForegroundColor Red;  exit 1 }

Write-Host "HCStudio build.ps1 v30 - run #44: ORT 1.20.1 + patch bo CUDA EP (crash fix run #41/#43)"

# PATCH run #23: danh sach DLL he thong Windows / API set cua Microsoft -
# luon co san tren moi Win10/11, KHONG can (va KHONG duoc) ship theo exe.
$sysDlls = @(
    "kernel32.dll","user32.dll","gdi32.dll","shell32.dll","advapi32.dll",
    "ole32.dll","oleaut32.dll","ws2_32.dll","wsock32.dll","ntdll.dll",
    "msvcrt.dll","ucrtbase.dll","vcruntime140.dll","msvcp140.dll",
    "comctl32.dll","comdlg32.dll","shlwapi.dll","winmm.dll","imm32.dll",
    "iphlpapi.dll","psapi.dll","userenv.dll","dbghelp.dll","version.dll",
    "bcrypt.dll","bcryptprimitives.dll","crypt32.dll","secur32.dll",
    "dnsapi.dll","powrprof.dll","setupapi.dll","cfgmgr32.dll","rpcrt4.dll",
    "wintrust.dll","msimg32.dll","opengl32.dll","glu32.dll","normaliz.dll",
    "dwmapi.dll","uxtheme.dll","oleacc.dll","ntmarta.dll","win32u.dll",
    "gdiplus.dll","windowscodecs.dll","propsys.dll","apphelp.dll"
)

# Doc toan bo ten DLL trong bang import cua 1 file PE bang objdump -x.
# Chi dung output cua objdump (khong can PE parser day du o day): moi entry
# import cua PE deu in 1 dong "DLL Name: ten.dll".
function Get-ExeImportDlls($exePath, $objdumpPath) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $od = & $objdumpPath -x $exePath 2>$null
    $ErrorActionPreference = $oldEap
    $out = @()
    foreach ($ln in @($od)) {
        if ($ln -match 'DLL Name: (.+)$') { $out += $Matches[1].Trim() }
    }
    return @($out | Sort-Object -Unique)
}

# PATCH run #11: tim gcc MinGW (bat buoc cho C++ build + link cgo Windows).
# Uu tien: env HCSTUDIO_CC > MSYS2 ucrt64 > MSYS2 mingw64 >
# choco mingw > Strawberry Perl > gcc trong PATH > tu cai bang choco.
function Resolve-MingwCc {
    if ($env:HCSTUDIO_CC) {
        $c = (Get-Command $env:HCSTUDIO_CC -ErrorAction SilentlyContinue).Source
        if ($c) { return $c }
    }
    $known = @(
        "C:\msys64\ucrt64\bin\gcc.exe",
        "C:\msys64\mingw64\bin\gcc.exe",
        "C:\ProgramData\mingw64\bin\gcc.exe",
        "C:\Strawberry\c\bin\gcc.exe"
    )
    foreach ($k in $known) {
        if (Test-Path $k) { return $k }
    }
    $c = (Get-Command gcc -ErrorAction SilentlyContinue).Source
    if ($c) { return $c }
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Host "Khong thay gcc MinGW co san - tu dong 'choco install mingw' (2-3 phut)..."
        & choco install mingw -y --no-progress
        if ($LASTEXITCODE -eq 0 -and (Test-Path "C:\ProgramData\mingw64\bin\gcc.exe")) {
            return "C:\ProgramData\mingw64\bin\gcc.exe"
        }
    }
    return ""
}

Step "Kiem tra cong cu"
 $go = Get-Command go -ErrorAction SilentlyContinue
if (!$go) { Die "Chua co Go (>=1.23). Tai tu https://go.dev/dl/ hoac 'winget install GoLang.Go'." }
Write-Host "Go: $(& go version)"

if ($env:PROCESSOR_ARCHITECTURE -notin @("AMD64")) {
    Write-Warning "Kien truc khac x64 chua duoc kiem thu - tiep tuc nhung tu chiu rui ro."
}

# ---------------------------------------------------------------- PATCH run #29
# Kiem tra INPUT chuan doan da co du trong repo CHUA, truoc khi bat dau build
# bat ky che do nao. Bai hoc run #26: khong kiem tra thi file thieu / file cu
# lan nhau den khong biet, mat ca ngay moi tim ra thu tuc dang chay la cua run cu.
Step "Kiem tra file chan doan run #29 trong repo"

$diagGoPath = Join-Path $RepoRoot "diaglog.go"
if (!(Test-Path $diagGoPath)) {
    Die "Thieu diaglog.go tai GOC repo. Copy diaglog.go tu goi run #29 vao cung cap voi main.go (package main)."
}

$appGoPath = Join-Path $RepoRoot "app.go"
if (!(Test-Path $appGoPath)) {
    Die "Thieu app.go tai goc repo - repo khong dung cau truc du an HCStudio v5."
}
$appGoText = [System.IO.File]::ReadAllText($appGoPath)
if (!$appGoText.Contains("diagf")) {
    Die "app.go CHUA co phien ban run #29 (khong thay loi goi diagf). Copy app.go moi tu goi run #29 de thay the."
}

$mainGoPath = Join-Path $RepoRoot "main.go"
if (!(Test-Path $mainGoPath)) {
    Die "Thieu main.go tai goc repo."
}
$mainGoText = [System.IO.File]::ReadAllText($mainGoPath)
if (!$mainGoText.Contains("diagInit")) {
    Die "main.go CHUA co phien ban run #29 (khong thay loi goi diagInit). Copy main.go moi tu goi run #29 de thay the."
}

$idxHtmlPath = Join-Path $RepoRoot "frontend\dist\index.html"
if (!(Test-Path $idxHtmlPath)) {
    Die "Thieu frontend\dist\index.html - go:embed se chet khi build. Repo thieu thu muc frontend."
}
$idxText = [System.IO.File]::ReadAllText($idxHtmlPath)
if (!$idxText.Contains("hcstudio-diag")) {
    Die "frontend\dist\index.html CHUA co khoi chan doan run #29 (chuoi 'hcstudio-diag' khong ton tai). Copy index.html moi tu goi run #29 vao frontend\dist\."
}

Write-Host "OK: diaglog.go + app.go(run29) + main.go(run29) + index.html(khoi chan doan) deu co mat."

# ---------------------------------------------------------------- CLEAN
if ($Clean) {
    Step "Don cac thu muc sinh tu dong"
    foreach ($d in @("native-build", "third_party", "ort_sdk", "dist", "native-build\cache")) {
        $p = Join-Path $RepoRoot $d
        if (Test-Path $p) { Remove-Item -Recurse -Force $p; Write-Host "rm $d" }
    }
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# ---------------------------------------------------------------- FULL pipeline
 $vieneuCoreLib = ""

if ($Full) {
    # ---- run #11 (A): resolve gcc MinGW TRUOC, truan cho prepare ----
    $mingwCc = Resolve-MingwCc
    if (!$mingwCc) {
        Die "Khong co gcc MinGW. Chay 'choco install mingw -y' hoac cai MSYS2 voi gcc (ucrt64), roi build lai."
    }
    Write-Host "GCC MinGW: $mingwCc"

    Step "CHUAN BI TANG NEURAL - goi scripts/prepare-vieneu.ps1"
    & (Join-Path $PSScriptRoot "prepare-vieneu.ps1") -OnnxRuntimeVersion $OnnxRuntimeVersion -VieneuCommit $VieneuCommit -Gcc $mingwCc
    if ($LASTEXITCODE -ne 0) { Die "prepare-vieneu that bai - xem log phia tren." }

    $nb            = Join-Path $RepoRoot "native-build"
    $vieneuCoreLib = Join-Path $nb "vieneu-tts-core.a"
    if (!(Test-Path $vieneuCoreLib)) { Die "Khong thay vieneu-tts-core.a trong native-build\" }

    $libsTxt = Get-Content (Join-Path $nb "link-libs.txt") -Raw

    # ---- PATCH run #24: dl shim - dinh nghia API dlfcn tren Windows ----
    # Vai member archive tham chieu dlopen* => ld nhat import lib "libdl"
    # cua toolchain => exe doi libdl.dll ma khong noi co file that. Shim
    # duoi day DINH NGHIA cac ham dl (wrapper LoadLibrary/GetProcAddress/
    # FreeLibrary) => ld resolve noi bo, khong con nhin den libdl.dll.a.
    $dlShimC   = Join-Path $nb "vieneu_dl_shim.c"
    $dlShimObj = Join-Path $nb "vieneu_dl_shim.o"
    $dlShimText = @'
/* vieneu_dl_shim.c - PATCH run #24 cua HCStudio build.
 * Mot vai thu vien C/C++ tham chieu API dlfcn (dlopen...) theo kieu
 * POSIX. Tren Windows ld bat import lib ten "libdl" cua toolchain
 * => exe phu thuoc libdl.dll - DLL khong ton tai de ship. Shim nay
 * DINH NGHIA cac ham dl bang wrapper Windows API de cat thuoc goc. */
#include <windows.h>

static char dl_err_buf[512];
static int  dl_err_live = 0;

static void dl_set_err(DWORD code) {
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                   NULL, code, 0, dl_err_buf, (DWORD)sizeof(dl_err_buf) - 1, NULL);
    dl_err_buf[sizeof(dl_err_buf) - 1] = 0;
    dl_err_live = 1;
}

const char *dlerror(void) {
    if (!dl_err_live) { return 0; }
    dl_err_live = 0;
    return dl_err_buf;
}

int dlclose(void *handle) {
    if (handle) { FreeLibrary((HMODULE)handle); }
    return 0;
}

void *dlopen(const char *path, int mode) {
    HMODULE h;
    (void)mode;
    dl_err_live = 0;
    if (!path) { h = GetModuleHandleA(0); } else { h = LoadLibraryA(path); }
    if (!h) { dl_set_err(GetLastError()); }
    return (void *)h;
}

void *dlsym(void *handle, const char *name) {
    FARPROC p;
    dl_err_live = 0;
    if (!name) { dl_set_err(0); return 0; }
    if (!handle || handle == (void *)-1) { handle = (void *)GetModuleHandleA(0); }
    p = GetProcAddress((HMODULE)handle, name);
    if (!p) { dl_set_err(GetLastError()); }
    return (void *)p;
}

int dladdr(const void *addr, void *info) {
    (void)addr;
    (void)info;
    return 0;
}
'@
    [System.IO.File]::WriteAllText($dlShimC, $dlShimText)
    Write-Host "Viet dl shim: $dlShimC"
    & $mingwCc -O2 -c $dlShimC -o $dlShimObj
    if ($LASTEXITCODE -ne 0) { Die "Khong compile duoc dl shim (vieneu_dl_shim.c)." }
    Write-Host ("Da compile dl shim: " + $dlShimObj)

    # ---- PATCH run #25: dong goi shim thanh ARCHIVE, KHONG dua file .o
    # truc tiep vao CGO_LDFLAGS. go build dua CGO_LDFLAGS len dong lenh
    # linker 2 LAN; .o lap 2 lan => multiple definition (run #24 rot).
    # .a lap 2 lan thi an toan => ar rcs mot lan, dung archive trong group.
    $arExe = Join-Path (Split-Path -Parent $mingwCc) "ar.exe"
    if (!(Test-Path $arExe)) {
        $arCmd = Get-Command ar -ErrorAction SilentlyContinue
        if ($arCmd) { $arExe = $arCmd.Source }
    }
    if (!(Test-Path $arExe)) {
        Die "Khong thay ar.exe canh gcc va trong PATH - khong the dong goi dl shim."
    }
    $dlShimLib = Join-Path $nb "vieneu-dl-shim.a"
    if (Test-Path $dlShimLib) { Remove-Item $dlShimLib -Force }
    & $arExe rcs $dlShimLib $dlShimObj
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $dlShimLib)) {
        Die "Khong dong goi duoc dl shim thanh archive (ar rcs that bai)."
    }
    Write-Host ("Da dong goi dl shim thanh archive: " + $dlShimLib)

    # ---- PATCH run #27: bien shim thanh libdl.dll THAT va ship vao dist\
    # Exe da sach libdl (chan byte v26 chot), nhung cac DLL runtime cua
    # toolchain trong dist\ van co the tu keo import libdl.dll, va loader
    # Windows bao loi voi TEN EXE goc nen tro nhu exe hong. Thay vi phai
    # biet chinh xac ke nao, ta cung cap luon libdl.dll (cung bo wrapper
    # LoadLibraryA/GetProcAddress/FreeLibrary) dat canh exe: bat ky module
    # nao import libdl.dll deu nap duoc - het dialog "was not found".
    $dlShimDllC = Join-Path $nb "vieneu_dl_shim_dll.c"
    $dlShimDll  = Join-Path $nb "libdl.dll"
    $dlShimDllText = @'
/* vieneu_dl_shim_dll.c - PATCH run #27 cua HCStudio build.
 * Ban DLL cua dl shim: cap cap libdl.dll that su cho moi module (exe
 * hoac DLL runtime cua toolchain) da import libdl.dll. Giao dien giong
 * dlfcn-win32: dlopen/dlsym/dlclose/dlerror/dladdr map sang
 * LoadLibraryA/GetProcAddress/FreeLibrary/GetModuleHandleA/FormatMessageA. */
#include <windows.h>

static char dl_err_buf[512];
static int  dl_err_live = 0;

static void dl_set_err(DWORD code) {
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                   NULL, code, 0, dl_err_buf, (DWORD)sizeof(dl_err_buf) - 1, NULL);
    dl_err_buf[sizeof(dl_err_buf) - 1] = 0;
    dl_err_live = 1;
}

__declspec(dllexport)
const char *dlerror(void) {
    if (!dl_err_live) { return 0; }
    dl_err_live = 0;
    return dl_err_buf;
}

__declspec(dllexport)
int dlclose(void *handle) {
    if (handle) { FreeLibrary((HMODULE)handle); }
    return 0;
}

__declspec(dllexport)
void *dlopen(const char *path, int mode) {
    HMODULE h;
    (void)mode;
    dl_err_live = 0;
    if (!path) { h = GetModuleHandleA(0); } else { h = LoadLibraryA(path); }
    if (!h) { dl_set_err(GetLastError()); }
    return (void *)h;
}

__declspec(dllexport)
void *dlsym(void *handle, const char *name) {
    FARPROC p;
    dl_err_live = 0;
    if (!name) { dl_set_err(0); return 0; }
    if (!handle || handle == (void *)-1) { handle = (void *)GetModuleHandleA(0); }
    p = GetProcAddress((HMODULE)handle, name);
    if (!p) { dl_set_err(GetLastError()); }
    return (void *)p;
}

__declspec(dllexport)
int dladdr(const void *addr, void *info) {
    (void)addr;
    (void)info;
    return 0;
}
'@
    [System.IO.File]::WriteAllText($dlShimDllC, $dlShimDllText)
    Write-Host "Viet nguon libdl.dll: $dlShimDllC"
    & $mingwCc -O2 -shared -static-libgcc -o $dlShimDll $dlShimDllC
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $dlShimDll)) {
        Die "Khong bien dich duoc libdl.dll tu dl shim."
    }
    Write-Host ("Da bien dich libdl.dll: " + $dlShimDll)
    Copy-Item $dlShimDll (Join-Path $DistDir "libdl.dll") -Force
    Write-Host "Da ship libdl.dll -> dist\ (bat ky module nao can libdl deu thay no)"

    # == CGO: BAT BUOC cho driver_cgo.go (build tag: windows && cgo && vieneu) ==
    # Thieu khoi nay thi go build -tags vieneu se:
    #   - hoac loi bien dich/link,
    #   - hoac WORSE HON: driver_cgo.go bi bo qua, stub.go duoc dung thay
    #     => exe van build XANH nhung "Full" Au DEN - KHONG co giong neural!
    $env:CGO_ENABLED = "1"

    # run #11: CC = gcc MinGW cung ban voi C++ build => moi archive deu la
    # .a GNU, ld cua mingw doc 100%. CC co khoang trang thi boc trong quote.
    $env:CC = $mingwCc
    if ($mingwCc -match '\s') { $env:CC = $q + $mingwCc + $q }

    # run #39: -DVIENEU_STATIC la MOT FIELD RIENG (dung boc cung -I trong
    # 1 ngoac kep - Go tach CGO_CFLAGS theo field co quote, gop chung se
    # tao 1 token sai giong loi argv run #40). Khi co define nay,
    # vieneu_tts.h de VIENEU_API RONG (hop dong static-link) thay vi
    # dllimport => het 8 undefined reference "__imp_vieneu_*". Phan
    # dinh nghia plain vieneu_* do vieneu-tts-api.a (run #39 cua
    # prepare-vieneu.ps1, dong dau tien link-libs.txt) cung cap trong
    # nhom group ben duoi.
    $env:CGO_CFLAGS = "-DVIENEU_STATIC " + $q + "-I" + (Join-Path $RepoRoot "third_party\VieNeu-TTS.cpp\src") + $q

    # ---- run #12/#13 (B): ghep CGO_LDFLAGS tu link-libs.txt + GROUP ----
    # Dinh dang link-libs.txt: dong duong dan -> archive .a/.lib; dong bat
    # dau bang "-" -> flag -l/-fopenmp truyen nguyen ven; ten tran .lib ->
    # chuyen -l (du phong).
    #
    # Tat ca archive boc trong -Wl,--start-group ... -Wl,--end-group. ld
    # quet lai nhom nhieu vong cho den khi khong con symbol nao unresolved
    # => thu tu trong nhom KHONG con quan trong (ggml/ggml-base/ggml-cpu/
    # llama/vieneu-core tu goi lan nhau). Hai flag nam san safelist cua go
    # (security.go L212/L227), khong can CGO_LDFLAGS_ALLOW.
    $archives = @($vieneuCoreLib)
    $libFlags = @()
    foreach ($ln in ($libsTxt -split '\r?\n')) {
        $t = $ln.Trim().Trim('"')
        if (!$t) { continue }
        if ($t -match '^[A-Za-z]:\\') {
            $archives += $t
        }
        elseif ($t -match '^-') {
            $libFlags += $t
            Write-Host "  flag: $t"
        }
        else {
            Write-Host "  $t -> chuyen sang -l" -ForegroundColor Yellow
            $libFlags += ("-l" + ($t -replace '\.lib$', ''))
        }
    }
    Write-Host ("  archive (" + $archives.Count + "):")
    foreach ($a in $archives) { Write-Host "    $a" }

    # PATCH run #26: shim (vieneu-dl-shim.a) dat O CUOI nhom, SAU tat
    # ca cac archive vieneu. Ly do: ld quet archive theo thu tu dong
    # lenh - neu shim nam O DAU nhom thi luc quet den shim, chua co
    # member nao tham chieu dl* (cac archive tham chieu dl* quet SAU
    # shim) nen shim CHUA duoc nap; shim chi duoc keo vao o vong quet
    # lai cua --start-group. Dua shim ve CUOI: trong chinh luot quet
    # dau, cac archive da keo member tham chieu dl* vao (dl* thanh
    # undefined), den shim cuoi nhom la chap ngay => chac chan duoc
    # nap trong mot luot quet duy nhat, khong phu thuoc vong quet
    # lai. Member archive da nap se khong nap lai khi group duoc lap
    # 2 lan (go dua CGO_LDFLAGS vao dong lenh 2 lan) => khong lo
    # multiple definition; -Wl,--allow-multiple-definition o duoi van
    # giu lam luoi an toan thu hai. KHONG dua .o truc tiep vao day.
    $ldflagsArr = @("-Wl,--start-group")
    foreach ($a in $archives) { $ldflagsArr += ($q + $a + $q) }
    $ldflagsArr += ($q + $dlShimLib + $q)
    $ldflagsArr += "-Wl,--end-group"
    $ldflagsArr += $libFlags
    # Luoi an toan run #25: neu con symbol trung tu nguon khac, ld lay
    # dinh nghia dau tien thay vi chet voi "multiple definition". Flag
    # nay co san trong safelist cua go (security.go L200).
    $ldflagsArr += "-Wl,--allow-multiple-definition"
    $env:CGO_LDFLAGS = ($ldflagsArr -join " ")

    # run #5: Go kiem tra an toan moi flag linker cua cgo truoc khi truyen
    # cho linker (src/cmd/go/internal/work/security.go - check go:cgo_ldflag).
    # Safelist da chua: *.a (direct linker inputs), -l<ten>, -fopenmp,
    # -Wl,--start-group/--end-group (L212/L227) VA
    # -Wl,--allow-multiple-definition (L200). Chi .lib (du phong cua prepare khi
    # dlltool that bai) phai ALLOW them:
    #   "runtime/cgo: invalid flag in go:cgo_ldflag: ...onnxruntime.lib"
    # Escape hatch chinh thuc theo go.dev/wiki/InvalidFlag.
    $env:CGO_LDFLAGS_ALLOW = ".*\.a|.*\.lib|.*\.o|-fopenmp"

    Write-Host "CGO da bat: CGO_ENABLED=1, CC=$env:CC"
    Write-Host "CGO_CFLAGS : $env:CGO_CFLAGS"
    Write-Host "CGO_LDFLAGS: $env:CGO_LDFLAGS"
    Write-Host "CGO_LDFLAGS_ALLOW: $env:CGO_LDFLAGS_ALLOW"
}

# Full: onnxruntime la import lib -> exe can onnxruntime.dll canh exe khi
# chay. Copy vao dist\ ngay buoc build de artifact luon chay duoc.
if ($Full) {
    $ortDllLocal = Join-Path $RepoRoot "native-build\onnxruntime.dll"
    if (Test-Path $ortDllLocal) {
        Copy-Item $ortDllLocal (Join-Path $DistDir "onnxruntime.dll") -Force
        Write-Host "Da copy onnxruntime.dll -> dist\"
    }
    # ---- run #47: ship sea-g2p phonemizer runtime + dict canh exe ----
    # Exe import sea_g2p_rs.dll (link qua import lib o link-libs.txt);
    # loader Windows tim DLL cung thu muc exe -> phai nam dist\.
    # sea_g2p.bin: resolve_sea_g2p_dict_path quet exe_dir dau tien.
    # Thieu 1 trong 2 file -> core tu roi ve phonemizer fallback (kem
    # chat luong) nen PHAI canh bao ro trong log.
    foreach ($seaFile in @("sea_g2p_rs.dll", "sea_g2p.bin")) {
        $seaSrc = Join-Path $RepoRoot ("native-build\" + $seaFile)
        if (Test-Path $seaSrc) {
            Copy-Item $seaSrc (Join-Path $DistDir $seaFile) -Force
            Write-Host "Da copy $seaFile -> dist\"
        } else {
            Write-Host "CANH BAO: thieu $seaFile trong native-build - giong doc se roi ve phonemizer fallback (KEM chat luong so voi Space)." -ForegroundColor Yellow
        }
    }
}

# ---- run #11 (C): ship MinGW runtime DLLs canh exe ----
# Exe link dong voi libgcc/libstdc++/winpthread/libgomp cua mingw.
if ($Full) {
    $gccBinDir = ""
    if ($env:CC) {
        $gccPath = $env:CC.Trim('"')
        if (Test-Path $gccPath) { $gccBinDir = Split-Path -Parent $gccPath }
    }
    foreach ($dll in @("libgcc_s_seh-1.dll", "libwinpthread-1.dll", "libstdc++-6.dll", "libgomp-1.dll")) {
        $f = Join-Path $gccBinDir $dll
        if ($gccBinDir -and (Test-Path $f)) {
            Copy-Item $f (Join-Path $DistDir $dll) -Force
            Write-Host "Da copy $dll -> dist\"
        }
        else {
            Write-Host "CANH BAO: khong thay $dll canh gcc - exe co the can PATH mingw khi chay." -ForegroundColor Yellow
        }
    }
}

# Lite: don CGO env de shell da tung chay build -Full khong anh huong
if (!$Full) {
    foreach ($v in @("CGO_ENABLED","CGO_CFLAGS","CGO_LDFLAGS","CGO_LDFLAGS_ALLOW","CC")) {
        Remove-Item Env:$v -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- go build
Step "Bien dich HCStudio.exe"

 $ldflags = "-H windowsgui -s -w"      # KHONG cua so CMD + strip symbol

# PATCH run #28: Wails BAT BUOC 2 build tags nay cho build production
# (wails CLI luon tu them). Thieu chung => runtime Wails coi la dev
# build, doi frontend dev server, hien message box "Wails applications
# will not build without the correct build tags" roi thoat. Full them
# tag vieneu cua du an vao sau.
 $wailsTags = "desktop,production"

 $exeName = if ($Full) { "HCStudio.exe" } else { "HCStudio-Lite.exe" }

Push-Location $RepoRoot
try {
    if ($Full) {
        & go build -trimpath -tags ($wailsTags + ",vieneu") -ldflags "$ldflags" -o (Join-Path $DistDir $exeName) .
    }
    else {
        & go build -trimpath -tags $wailsTags -ldflags "$ldflags" -o (Join-Path $DistDir $exeName) .
    }
    if ($LASTEXITCODE -ne 0) { Die "go build that bai (exit $LASTEXITCODE)." }

    # ------------------- PATCH FIX41: build kem HCStudio-debug.exe ----------
    # Cung mot code nhung KHONG co -H=windowsgui (subsystem console):
    # khi chay se mo them cua so CMD de TOAN BO stderr cua Go runtime
    # (panic, fatal error, SIGSEGV ben trong code cgo) hien ra mat nguoi
    # dung. Exe GUI binh thuong khong bao gio hien duoc cac dong nay -
    # do la ly do app "tu thoat" ma khong ro nguyen nhan. Khi ban loi:
    #   1) chay HCStudio-debug.exe, bam tao giong doc de reproduce;
    #   2) copy/screenshot dong cuoi trong cua so console;
    #   3) gui nguoc lai - dong do chi dinh dung cho crash nam o dau.
    if ($Full -and $DebugExe) { # PATCH FIX51: mac dinh KHONG build debug exe - dist chi con HCStudio.exe
        $dbgLdflags = "-s -w"   # khong -H windowsgui => subsystem console
        & go build -trimpath -tags ($wailsTags + ",vieneu") -ldflags "$dbgLdflags" -o (Join-Path $DistDir "HCStudio-debug.exe") .
        if ($LASTEXITCODE -ne 0) {
            Write-Host "CANH BAO: build HCStudio-debug.exe that bai (exit $LASTEXITCODE) - bo qua, khong chan quy trinh." -ForegroundColor Yellow
        }
    }
}
finally {
    Pop-Location
}

    # PATCH FIX51: dist SACH - ban Full chi ship dung HCStudio.exe.
    # Lite/debug sot tu lan build truoc duoc don de kho tai khong lan
    # artifact cu (Lite van san sang: bo -Full la build lai trong 2 phut).
    if ($Full) {
        foreach ($stale in @("HCStudio-Lite.exe", "HCStudio-debug.exe")) {
            $stalePath = Join-Path $DistDir $stale
            if (Test-Path $stalePath) { Remove-Item $stalePath -Force; Write-Host "Don file cu: $stale" }
        }
    }

# ---------------------------------------------------------------- summary
 $appExe = Join-Path $DistDir $exeName
 $sizeMb = [math]::Round((Get-Item $appExe).Length / 1MB, 1)

# ------------------- PATCH run #23: quet import DLL + tu dong ship con thieu
# Quet bang import cua exe vua build, so voi cac file trong dist\:
#   - DLL he thong Windows (sysDlls / api-ms-* / ext-ms-*): bo qua.
#   - DLL con thieu: tim trong thu muc bin cua gcc, cac thu muc lib gan no
#     va moi thu muc trong PATH -> copy vao dist\.
#   - Van khong co: DIE voi danh sach ro rang => log CI cho thay ngay.
# Nho buoc nay, moi DLL "ma" kieu libdl.dll se duoc tu dong ship hoac bi
# bao loi som - khong bao gio den tay nguoi dung roi moi "was not found".
Step "Quet import DLL cua TAT CA .exe/.dll trong dist (run #23 + #27)"
$objdumpExe = ""
if ($gccBinDir -and (Test-Path (Join-Path $gccBinDir "objdump.exe"))) {
    $objdumpExe = Join-Path $gccBinDir "objdump.exe"
} else {
    $odCmd = Get-Command objdump -ErrorAction SilentlyContinue
    if ($odCmd) { $objdumpExe = $odCmd.Source }
    elseif (Test-Path "C:\Strawberry\c\bin\objdump.exe") { $objdumpExe = "C:\Strawberry\c\bin\objdump.exe" }
}
if (!$objdumpExe) {
    Write-Host "CANH BAO: khong tim thay objdump - bo qua buoc quet import DLL." -ForegroundColor Yellow
} else {
    # PATCH run #27: TRUOC DAY chi quet app exe. Nhung loader Windows kiem
    # tra TOAN BO chuoi phu thuoc tinh: exe cung nhu MOI DLL no keo theo.
    # Nguoi dung van gap "libdl.dll was not found" voi exe da sach (chan
    # byte chung minh) => ke keo libdl.dll la mot DLL trong dist\. Vi do:
    # quet moi file PE trong dist, in day du import cua tung file (log CI
    # se chi danh ro ke da keo DLL nao), va bao dam moi DLL ngoai he thong
    # deu co mat trong dist\ hoac tu dong copy tu toolchain.
    $peFiles = @(Get-ChildItem -File $DistDir |
        Where-Object { $_.Extension -ieq ".exe" -or $_.Extension -ieq ".dll" })
    $missingDlls = @()
    foreach ($pe in $peFiles) {
        $imports = Get-ExeImportDlls $pe.FullName $objdumpExe
        Write-Host ""
        Write-Host ($pe.Name + " can " + $imports.Count + " DLL:")
        foreach ($d in $imports) { Write-Host ("   " + $d) }
        foreach ($d in $imports) {
            $dl = $d.ToLowerInvariant()
            $isSys = ($dl -match '^(api-ms-|ext-ms-)') -or ($sysDlls -contains $dl)
            if ($isSys) { continue }
            if (Test-Path (Join-Path $DistDir $d)) { continue }
            $searchDirs = @()
            if ($gccBinDir) {
                $searchDirs += $gccBinDir
                $searchDirs += (Join-Path $gccBinDir "..\lib")
                $searchDirs += (Join-Path $gccBinDir "..\x86_64-w64-mingw32\lib")
            }
            $searchDirs += @(
                "C:\Strawberry\c\bin",
                "C:\Strawberry\c\lib",
                "C:\Strawberry\c\x86_64-w64-mingw32\lib",
                "C:\msys64\ucrt64\bin",
                "C:\msys64\mingw64\bin",
                "C:\ProgramData\mingw64\bin"
            )
            foreach ($p in ($env:Path -split ';')) {
                if ($p -and (Test-Path $p)) { $searchDirs += $p }
            }
            $found = ""
            foreach ($dir in $searchDirs) {
                if (!$dir) { continue }
                $cand = Join-Path $dir $d
                if (Test-Path $cand) { $found = $cand; break }
            }
            if ($found) {
                Copy-Item $found (Join-Path $DistDir $d) -Force
                Write-Host ("Da tu dong copy " + $d + " -> dist\ (tu " + $found + ", de phuc vu " + $pe.Name + ")") -ForegroundColor Green
            } else {
                $missingDlls += ($pe.Name + " -> " + $d)
            }
        }
    }
    if ($missingDlls.Count -gt 0) {
        Die ("Co PE can DLL ma khong tim thay trong toolchain: " + ($missingDlls -join "; ") +
             " - gui log nay cho developer de xu ly tan goc.")
    }
    Write-Host ""
    Write-Host "Quet OK: moi DLL ngoai he thong cua tung PE deu co mat trong dist\."
}

# ---- PATCH run #26: exe tu khai minh danh tinh ----
# (1) SHA256 cua exe: in vao log CI + ghi vao BUILD-INFO.txt dat canh
# exe. Nguoi dung chi can lay hash file exe tren may va so voi log:
# hash giong = dung exe cua run nay; hash khac = dang chay exe cu.
$sha256 = (Get-FileHash -Path $appExe -Algorithm SHA256).Hash
Write-Host ("Exe SHA256: " + $sha256)

# (2) Chan cuoi khong can objdump: doc toan bo byte exe, neu van con
# chuoi libdl.dll trong body exe nghia la shim chua duoc nap vao link.
if ($Full) {
    $hay = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($appExe))
    if ($hay.Contains("libdl.dll")) {
        Die "Chan cuoi byte: exe van con tham chieu libdl.dll - shim chua duoc nap. Gui log CI cho developer."
    }
    Write-Host "Kiem tra byte exe: SACH - khong con libdl.dll trong body."
}

# (3) BUILD-INFO.txt dat canh exe trong dist: mo artifact la biet ngay
# no sinh tu run nao, che do nao, hash la bao nhieu - het nham exe.
$ciRun = "local"
if ($env:GITHUB_RUN_NUMBER) {
    $ciRun = "run #" + $env:GITHUB_RUN_NUMBER + " (id " + $env:GITHUB_RUN_ID + ")"
}
$info = @("HCStudio build info (v30)")
$info += "Mode       : " + $(if ($Full) { "FULL neural (VieNeu v3 Turbo)" } else { "LITE (SAPI5)" })
$info += "Built (UTC): " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss") + "Z"
$info += "CI run     : " + $ciRun
$info += "Exe        : " + $exeName
$info += "Exe SHA256 : " + $sha256
# run #47: trang thai phonemizer sea-g2p (chat luong giong doc). Hai file
# nay phai co trong dist - thieu se roi ve fallback G2P kem chat luong.
$seaOk = (Test-Path (Join-Path $DistDir "sea_g2p_rs.dll")) -and (Test-Path (Join-Path $DistDir "sea_g2p.bin"))
$info += "Sea-g2p    : " + $(if ($seaOk) { "ON (sea_g2p_rs.dll + sea_g2p.bin)" } else { "FALLBACK G2P (thieu dll/dict - xem log CI)" })
$info += "Dist files :"
foreach ($f in (Get-ChildItem -File $DistDir | Sort-Object Name)) {
    $info += "  " + $f.Name + " (" + [math]::Round($f.Length / 1KB, 0) + " KB)"
}
$nl = [string][char]13 + [string][char]10
[System.IO.File]::WriteAllText((Join-Path $DistDir "BUILD-INFO.txt"), (($info -join $nl) + $nl))
Write-Host ("Da ghi BUILD-INFO.txt -> dist (CI run: " + $ciRun + ")")

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "  HOAN TAT | $exeName | $sizeMb MB"                   -ForegroundColor Green
Write-Host ("  Che do  : " + $(if ($Full) {"FULL neural (VieNeu v3 Turbo)"} else {"LITE (SAPI5)" }))
Write-Host "  Duong dan:"
Write-Host "    $appExe"
Write-Host ""
if (!$Full) {
    Write-Host "  Luu y: ban Lite CHUA co giong neural." -ForegroundColor Yellow
    Write-Host "  Khi chay lan dau, app goi y build -Full hoac dung Ultra-Lite."
}
else {
    Write-Host "  Lan chay dau: app hoi tai trong so model (~1 GB) mot lan duy nhat," -ForegroundColor Yellow
    Write-Host "  sau do offline tuyet doi."
    Write-Host "  Cac DLL runtime + libdl.dll (tu dl shim) da ship vao dist (quet #23 + #27)." -ForegroundColor Yellow
}
Write-Host "======================================================" -ForegroundColor Green
