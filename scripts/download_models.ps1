[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$modelsRoot = Join-Path $ProjectRoot 'models'
$qwenDir = Join-Path $modelsRoot 'Qwen3-8b-ov-npu'
$translationDir = Join-Path $modelsRoot 'HY-MT1.5-1.8B-int4-ov'
$sourceCache = Join-Path $modelsRoot '.source-cache'
$hyMtSourceDir = Join-Path $sourceCache 'HY-MT1.5-1.8B'

$qwenModelScopeRepo = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_QWEN_MS_REPO)) {
    'OpenVINO/Qwen3-8B-int4-cw-ov'
} else {
    $env:PAPERAGENT_QWEN_MS_REPO.Trim()
}
$qwenHuggingFaceRepo = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_QWEN_HF_REPO)) {
    'OpenVINO/Qwen3-8B-int4-ov'
} else {
    $env:PAPERAGENT_QWEN_HF_REPO.Trim()
}
$hyMtModelScopeRepo = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_HYMT_MS_REPO)) {
    'Tencent-Hunyuan/HY-MT1.5-1.8B'
} else {
    $env:PAPERAGENT_HYMT_MS_REPO.Trim()
}
$hyMtHuggingFaceRepo = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_HYMT_HF_REPO)) {
    'tencent/HY-MT1.5-1.8B'
} else {
    $env:PAPERAGENT_HYMT_HF_REPO.Trim()
}
$preferredSource = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_MODEL_SOURCE)) {
    'modelscope'
} else {
    $env:PAPERAGENT_MODEL_SOURCE.Trim().ToLowerInvariant()
}

if ($preferredSource -notin @('modelscope', 'huggingface')) {
    throw 'PAPERAGENT_MODEL_SOURCE must be modelscope or huggingface.'
}

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Refresh-ProcessPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Get-CommandOrNull([string]$Name) {
    return Get-Command $Name -ErrorAction SilentlyContinue
}

function Ensure-Uv {
    $uv = Get-CommandOrNull 'uv'
    if ($uv) { return $uv }

    Write-Host 'uv is not installed. Preparing uv for model download...'
    $winget = Get-CommandOrNull 'winget'
    if ($winget) {
        & $winget.Source install --id astral-sh.uv -e --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to install uv with winget.'
        }
        Refresh-ProcessPath
    } else {
        Invoke-Expression ((Invoke-RestMethod 'https://astral.sh/uv/install.ps1'))
        Refresh-ProcessPath
    }

    $uv = Get-CommandOrNull 'uv'
    if (-not $uv) {
        $candidate = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $uv = [pscustomobject]@{ Source = $candidate }
        }
    }
    if (-not $uv) { throw 'uv installation completed but uv.exe was not found.' }
    return $uv
}

function Test-OpenVinoModel([string]$ModelDir) {
    return (
        (Test-Path -LiteralPath $ModelDir -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $ModelDir 'openvino_model.xml') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $ModelDir 'openvino_model.bin') -PathType Leaf)
    )
}

function Remove-DirectoryIfExists([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Download-ModelScopeSnapshot(
    [object]$Uv,
    [string]$RepoId,
    [string]$Destination,
    [string]$DisplayName
) {
    Remove-DirectoryIfExists $Destination
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Write-Host "Downloading $DisplayName from ModelScope: $RepoId"
    $code = @"
from modelscope import snapshot_download
snapshot_download(
    model_id=r'''$RepoId''',
    local_dir=r'''$Destination'''
)
"@
    & $Uv.Source run --python 3.11 --with modelscope python -c $code
    return ($LASTEXITCODE -eq 0)
}

function Download-HuggingFaceSnapshot(
    [object]$Uv,
    [string]$RepoId,
    [string]$Destination,
    [string]$DisplayName
) {
    Remove-DirectoryIfExists $Destination
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Write-Host "Downloading $DisplayName from Hugging Face fallback: $RepoId"
    $code = @"
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id=r'''$RepoId''',
    local_dir=r'''$Destination'''
)
"@
    & $Uv.Source run --python 3.11 --with huggingface_hub --with hf_xet python -c $code
    return ($LASTEXITCODE -eq 0)
}

function Download-WithFallback(
    [object]$Uv,
    [string]$ModelScopeRepo,
    [string]$HuggingFaceRepo,
    [string]$Destination,
    [string]$DisplayName
) {
    if ($preferredSource -eq 'huggingface') {
        if (-not (Download-HuggingFaceSnapshot $Uv $HuggingFaceRepo $Destination $DisplayName)) {
            throw "Failed to download $DisplayName from Hugging Face: $HuggingFaceRepo"
        }
        return
    }

    if (Download-ModelScopeSnapshot $Uv $ModelScopeRepo $Destination $DisplayName) {
        Write-Host "[OK] $DisplayName downloaded from ModelScope." -ForegroundColor Green
        return
    }

    Write-Host "[WARN] ModelScope download failed for $DisplayName. Trying Hugging Face fallback..." -ForegroundColor Yellow
    if (-not (Download-HuggingFaceSnapshot $Uv $HuggingFaceRepo $Destination $DisplayName)) {
        throw "Failed to download $DisplayName from both ModelScope and Hugging Face."
    }
}

function Export-HYMTToOpenVinoInt4(
    [object]$Uv,
    [string]$SourceDir,
    [string]$Destination
) {
    Remove-DirectoryIfExists $Destination
    Write-Host 'Converting HY-MT1.5-1.8B to OpenVINO INT4 for the PaperAgent CPU translation runtime...'
    & $Uv.Source run `
        --python 3.11 `
        --with 'optimum-intel[openvino]' `
        --with 'transformers>=4.56,<5.0' `
        --with torch `
        --with accelerate `
        optimum-cli export openvino `
        --model $SourceDir `
        --task text-generation-with-past `
        --weight-format int4 `
        --trust-remote-code `
        $Destination
    if ($LASTEXITCODE -ne 0) {
        throw 'HY-MT OpenVINO INT4 conversion failed.'
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'The complete PaperAgent edge model preparation currently targets Windows 10/11 x64.'
}

Write-Host 'PaperAgent model preparation' -ForegroundColor Green
Write-Host "Project: $ProjectRoot"
Write-Host "Preferred source: $preferredSource"

New-Item -ItemType Directory -Force -Path $modelsRoot | Out-Null
$uv = Ensure-Uv
Write-Host "[OK] uv: $($uv.Source)" -ForegroundColor Green

Write-Step 'Model 1/2 - Qwen3 8B INT4 OpenVINO for Intel NPU'
if ($Force -or -not (Test-OpenVinoModel $qwenDir)) {
    Download-WithFallback `
        $uv `
        $qwenModelScopeRepo `
        $qwenHuggingFaceRepo `
        $qwenDir `
        'Qwen3 8B INT4 OpenVINO'
}
if (-not (Test-OpenVinoModel $qwenDir)) {
    throw "Qwen3 model is incomplete after download: $qwenDir"
}
Write-Host '[OK] Qwen3 OpenVINO model ready.' -ForegroundColor Green

Write-Step 'Model 2/2 - HY-MT1.5 1.8B INT4 OpenVINO for CPU translation'
if ($Force -or -not (Test-OpenVinoModel $translationDir)) {
    New-Item -ItemType Directory -Force -Path $sourceCache | Out-Null
    Download-WithFallback `
        $uv `
        $hyMtModelScopeRepo `
        $hyMtHuggingFaceRepo `
        $hyMtSourceDir `
        'HY-MT1.5-1.8B source model'
    Export-HYMTToOpenVinoInt4 $uv $hyMtSourceDir $translationDir
}
if (-not (Test-OpenVinoModel $translationDir)) {
    throw "HY-MT OpenVINO model is incomplete after conversion: $translationDir"
}
Write-Host '[OK] HY-MT OpenVINO model ready.' -ForegroundColor Green

if (Test-Path -LiteralPath $sourceCache) {
    Write-Host 'Cleaning temporary source-model cache...'
    Remove-Item -LiteralPath $sourceCache -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host 'Required PaperAgent models are ready.' -ForegroundColor Green
Write-Host "Qwen3: $qwenDir"
Write-Host "HY-MT:  $translationDir"
Write-Host '=======================================================' -ForegroundColor Green
