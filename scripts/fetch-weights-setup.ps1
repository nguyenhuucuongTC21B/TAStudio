#Requires -Version 5.1
<#
.SYNOPSIS
    HCStudio v5.0 - FIX51: tai 14 file trong so (pin commit) lam payload
    cho make-setup.ps1 (Phuong an B - Setup 1 file).

.DESCRIPTION
    URL pin Y NHAT manifest cua app (assets_manifest.go):
      - VieNeu v3  : HF @8b7e9cff  (onnx_update/ + goc repo)
      - MOSS codec : HF @ceff0d07
      - Voices     : GitHub @fa2b1afa
    Skip file da co dung size. Sai size = tai lai. Xong chay checksum size.

.EXAMPLE
    powershell -File scripts\fetch-weights-setup.ps1 -Dest build\setup-payload\weights
#>
param(
    [string]$Dest = "build\setup-payload\weights"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$hfV3Commit  = "8b7e9cffb4b41918cb638b9f62f0a751184d14a6"
$hfV3Base    = "https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/$hfV3Commit"
$hfV3Update  = "$hfV3Base/onnx_update"
$mossCommit  = "ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae"
$hfMoss      = "https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX/resolve/$mossCommit"
$voicesUrl   = "https://raw.githubusercontent.com/pnnbao97/VieNeu-TTS/fa2b1afa1ed7657ca47987b6b799ec20d645047e/src/vieneu/assets/voices_v3_turbo.json"

# (Url, RelPath, SizeHint) - 14 file, khop manifest cua app FIX50/51
$files = @(
    @("$voicesUrl",                          "voices_v3_turbo.json",                    180240),
    @("$hfV3Update/config.json",             "update/config.json",                       2152),
    @("$hfV3Update/tokenizer.json",          "update/tokenizer.json",                   22320),
    @("$hfV3Update/vieneu_prefill.onnx",     "update/vieneu_prefill.onnx",             324499),
    @("$hfV3Update/vieneu_decode_step.onnx", "update/vieneu_decode_step.onnx",         306134),
    @("$hfV3Update/vieneu_v3_heads.npz",     "update/vieneu_v3_heads.npz",           52219622),
    @("$hfV3Update/vieneu_acoustic_cached.onnx", "update/vieneu_acoustic_cached.onnx", 7207223),
    @("$hfV3Update/vieneu_backbone_shared.data", "update/vieneu_backbone_shared.data", 415319040),
    @("$hfMoss/moss_audio_tokenizer_encode.onnx",       "codec/moss_audio_tokenizer_encode.onnx",       815775),
    @("$hfMoss/moss_audio_tokenizer_encode.data",       "codec/moss_audio_tokenizer_encode.data",     44507136),
    @("$hfMoss/moss_audio_tokenizer_decode_full.onnx",  "codec/moss_audio_tokenizer_decode_full.onnx",  681902),
    @("$hfMoss/moss_audio_tokenizer_decode_shared.data","codec/moss_audio_tokenizer_decode_shared.data", 44198912),
    @("$hfV3Base/denoiser.onnx",             "denoiser.onnx",                         42661414),
    @("$hfV3Base/speaker_encoder.onnx",      "speaker_encoder.onnx",                  28303423)
)

Write-Host "Payload: $Dest"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

$idx = 0
foreach ($f in $files) {
    $idx++
    $url  = $f[0]
    $rel  = $f[1]
    $size = [int64]$f[2]
    $out  = Join-Path $Dest ($rel -replace "/", "\")
    $dir  = Split-Path $out -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    if (Test-Path $out) {
        $got = (Get-Item $out).Length
        if ($got -eq $size) {
            Write-Host ("[{0,2}/14] OK (da co)  {1}" -f $idx, $rel)
            continue
        }
        Write-Host ("[{0,2}/14] SAI size ({1} <> {2}) - tai lai: {3}" -f $idx, $got, $size, $rel)
        Remove-Item $out -Force
    }
    Write-Host ("[{0,2}/14] TAI {1} ({2} MB)" -f $idx, $rel, [math]::Round($size / 1MB, 1))
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    $got = (Get-Item $out).Length
    if ($got -ne $size) {
        Write-Host "LOI: $rel size $got <> $size" -ForegroundColor Red
        exit 1
    }
}

# Tong ket
$total = 0L
foreach ($f in $files) { $total += [int64]$f[2] }
Write-Host ""
Write-Host "THANH CONG: 14/14 file, tong $total bytes (~$([math]::Round($total / 1MB, 1)) MB) tai $Dest"
Write-Host "Buoc tiep: powershell -File scripts\make-setup.ps1 -DistDir dist -WeightsDir $Dest"
