[CmdletBinding()]
param(
    [switch]$SkipModelDownload,
    [switch]$SkipStart,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$nginxVersion = '1.30.1'
$nginxDir = Join-Path $root "nginx_install\nginx-$nginxVersion"
$modelsRoot = Join-Path $root 'models'
$hfCache = Join-Path $modelsRoot '.hf-cache'
$qwenDir = Join-Path $modelsRoot 'Qwen3-8b-ov-npu'
$translationDir = Join-Path $modelsRoot 'HY-MT1.5-1.8B-int4-ov'
$configExample = Join-Path $root 'CLOUD\config.example.yaml'
$configPath = Join-Path $root 'CLOUD\config.yaml'

$qwenOvRepo = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_QWEN_OV_REPO)) {
    'OpenVINO/Qwen3-8B-int4-ov'
} else {
    $env:PAPERAGENT_QWEN_OV_REPO.Trim()
}
$hyMtSourceRepo = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_HYMT_SOURCE_REPO)) {
    'tencent/HY-MT1.5-1.8B'
} else {
    $env:PAPERAGENT_HYMT_SOURCE_REPO.Trim()
}
$hyMtOvRepo = if ([string]::IsNullOrWhiteSpace($env:PAPERAGENT_HYMT_OV_REPO)) {
    ''
} else {
    $env:PAPERAGENT_HYMT_OV_REPO.Trim()
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

function Install-WithWinget([string]$Id, [string]$DisplayName) {
    $winget = Get-CommandOrNull 'winget'
    if (-not $winget) {
        throw "$DisplayName is missing and winget is unavailable. Install $DisplayName manually, then rerun deploy.bat."
    }
    Write-Host "Installing $DisplayName..."
    & $winget.Source install --id $Id -e --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install $DisplayName with winget."
    }
    Refresh-ProcessPath
}

function Escape-YamlDoubleQuoted([string]$Value) {
    if ($null -eq $Value) { return '' }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Read-SecretText([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Test-OpenVinoModel([string]$ModelDir) {
    return (
        (Test-Path -LiteralPath $ModelDir -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $ModelDir 'openvino_model.xml') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $ModelDir 'openvino_model.bin') -PathType Leaf)
    )
}

function Download-HuggingFaceSnapshot(
    [string]$RepoId,
    [string]$Destination,
    [string]$DisplayName
) {
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    New-Item -ItemType Directory -Force -Path $hfCache | Out-Null

    Write-Host "Downloading $DisplayName from Hugging Face: $RepoId"
    $downloadCode = @"
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id=r'''$RepoId''',
    local_dir=r'''$Destination''',
    cache_dir=r'''$hfCache'''
)
"@
    & $uv.Source run --with huggingface_hub --with hf_xet python -c $downloadCode
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download $DisplayName from $RepoId."
    }
}

function Export-HuggingFaceModelToOpenVinoInt4(
    [string]$RepoId,
    [string]$Destination,
    [string]$DisplayName
) {
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $hfCache | Out-Null

    Write-Host "Downloading and converting $DisplayName to INT4 OpenVINO IR..."
    Write-Host "Source model: $RepoId"
    Write-Host 'This conversion is performed locally and may use substantial CPU/RAM/disk during first deployment.' -ForegroundColor Yellow

    $oldHfHome = $env:HF_HOME
    try {
        $env:HF_HOME = $hfCache
        & $uv.Source run `
            --with 'optimum-intel[openvino]' `
            --with 'transformers>=4.56,<5.0' `
            --with torch `
            --with accelerate `
            optimum-cli export openvino `
            --model $RepoId `
            --task text-generation-with-past `
            --weight-format int4 `
            --trust-remote-code `
            $Destination
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to export $DisplayName to OpenVINO INT4."
        }
    } finally {
        if ($null -eq $oldHfHome) {
            Remove-Item Env:HF_HOME -ErrorAction SilentlyContinue
        } else {
            $env:HF_HOME = $oldHfHome
        }
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'Competition one-click deployment currently targets Windows 10/11 x64 with Intel NPU.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw '64-bit Windows is required.'
}

Write-Host 'PaperAgent Competition Edition deployment' -ForegroundColor Green
Write-Host "Project: $root"

Write-Step '1/7 Preparing uv'
$uv = Get-CommandOrNull 'uv'
if (-not $uv) {
    $winget = Get-CommandOrNull 'winget'
    if ($winget) {
        Install-WithWinget 'astral-sh.uv' 'uv'
    } else {
        Write-Host 'winget is unavailable; installing uv with the official installer.'
        Invoke-Expression ((Invoke-RestMethod 'https://astral.sh/uv/install.ps1'))
        Refresh-ProcessPath
    }
    $uv = Get-CommandOrNull 'uv'
    if (-not $uv) {
        $candidate = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
        if (Test-Path $candidate) {
            $uv = [pscustomobject]@{ Source = $candidate }
        }
    }
}
if (-not $uv) { throw 'uv installation completed but uv.exe was not found.' }
Write-Host "[OK] uv: $($uv.Source)" -ForegroundColor Green

Write-Step '2/7 Preparing Node.js'
if (-not (Get-CommandOrNull 'node') -or -not (Get-CommandOrNull 'npm')) {
    Install-WithWinget 'OpenJS.NodeJS.LTS' 'Node.js LTS'
}
$node = Get-CommandOrNull 'node'
$npm = Get-CommandOrNull 'npm'
if (-not $node -or -not $npm) { throw 'Node.js/npm is still unavailable after installation.' }
Write-Host "[OK] Node.js: $(& $node.Source --version)" -ForegroundColor Green

Write-Step '3/7 Preparing Nginx'
if (-not (Test-Path (Join-Path $nginxDir 'nginx.exe'))) {
    $tmpZip = Join-Path $env:TEMP "paperagent-nginx-$nginxVersion.zip"
    $installRoot = Join-Path $root 'nginx_install'
    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
    Write-Host "Downloading Nginx $nginxVersion..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://nginx.org/download/nginx-$nginxVersion.zip" -OutFile $tmpZip
    Expand-Archive -Path $tmpZip -DestinationPath $installRoot -Force
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path (Join-Path $nginxDir 'nginx.exe'))) { throw 'Nginx preparation failed.' }
Write-Host '[OK] Nginx ready.' -ForegroundColor Green

Write-Step '4/7 Preparing required OpenVINO models (2/2)'
New-Item -ItemType Directory -Force -Path $modelsRoot | Out-Null

Write-Host '[Model 1/2] Qwen3 8B INT4 OpenVINO (grammar + polishing, NPU)'
if (-not (Test-OpenVinoModel $qwenDir)) {
    if ($SkipModelDownload) {
        throw "Required Qwen OpenVINO model is missing: $qwenDir"
    }
    Download-HuggingFaceSnapshot $qwenOvRepo $qwenDir 'Qwen3 8B INT4 OpenVINO'
}
if (-not (Test-OpenVinoModel $qwenDir)) {
    throw "Qwen download finished but required OpenVINO IR files are missing: $qwenDir"
}
Write-Host '[OK] Model 1/2 ready: Qwen3 8B OpenVINO.' -ForegroundColor Green

Write-Host "`n[Model 2/2] HY-MT1.5 1.8B INT4 OpenVINO (translation, CPU)"
if (-not (Test-OpenVinoModel $translationDir)) {
    if ($SkipModelDownload) {
        throw "Required HY-MT OpenVINO model is missing: $translationDir"
    }

    if (-not [string]::IsNullOrWhiteSpace($hyMtOvRepo)) {
        Write-Host "Using pre-converted HY-MT OpenVINO repository override: $hyMtOvRepo"
        Download-HuggingFaceSnapshot $hyMtOvRepo $translationDir 'HY-MT1.5 1.8B INT4 OpenVINO'
    } else {
        Export-HuggingFaceModelToOpenVinoInt4 $hyMtSourceRepo $translationDir 'HY-MT1.5 1.8B'
    }
}
if (-not (Test-OpenVinoModel $translationDir)) {
    throw "HY-MT preparation finished but required OpenVINO IR files are missing: $translationDir"
}
Write-Host '[OK] Model 2/2 ready: HY-MT1.5 1.8B INT4 OpenVINO.' -ForegroundColor Green

if (Test-Path -LiteralPath $hfCache) {
    Write-Host 'Cleaning temporary Hugging Face deployment cache...'
    Remove-Item -LiteralPath $hfCache -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step '5/7 Creating local configuration'
if (-not (Test-Path $configExample)) { throw "Missing configuration template: $configExample" }
if (-not (Test-Path $configPath)) {
    Copy-Item $configExample $configPath
}

$llmKey = $env:PAPERAGENT_LLM_API_KEY
if ([string]::IsNullOrWhiteSpace($llmKey)) { $llmKey = $env:DEEPSEEK_API_KEY }
$mineruToken = $env:MINERU_API_TOKEN

if (-not $NonInteractive -and [string]::IsNullOrWhiteSpace($llmKey)) {
    $llmKey = Read-SecretText 'Optional: enter LLM API Key for cloud retrieval (press Enter to skip)'
}
if (-not $NonInteractive -and [string]::IsNullOrWhiteSpace($mineruToken)) {
    $mineruToken = Read-SecretText 'Optional: enter MinerU API Token for PDF parsing (press Enter to skip)'
}

$configText = Get-Content -LiteralPath $configExample -Raw -Encoding UTF8
if (-not [string]::IsNullOrWhiteSpace($llmKey)) {
    $safe = Escape-YamlDoubleQuoted $llmKey
    $replacement = "  api_key: `"$safe`""
    $configText = [regex]::Replace(
        $configText,
        '(?m)^  api_key:\s*""\s*$',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement }
    )
} else {
    Write-Host '[WARN] LLM API Key is empty. Local edge functions can run, but cloud LLM requests require a key.' -ForegroundColor Yellow
}
if (-not [string]::IsNullOrWhiteSpace($mineruToken)) {
    $safeMineru = Escape-YamlDoubleQuoted $mineruToken
    $mineruReplacement = "  api_token: `"$safeMineru`""
    $configText = [regex]::Replace(
        $configText,
        '(?m)^  api_token:\s*""\s*$',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $mineruReplacement }
    )
}
[IO.File]::WriteAllText($configPath, $configText, (New-Object Text.UTF8Encoding($false)))
Write-Host '[OK] Local config created. CLOUD/config.yaml is git-ignored.' -ForegroundColor Green

Write-Step '6/7 Installing project dependencies and validating hardware'
& (Join-Path $PSScriptRoot 'setup_environment.ps1') -ProjectRoot $root
if ($LASTEXITCODE -ne 0) { throw 'Environment setup or verification failed.' }

Write-Step '7/7 Running sensitive-data scan'
& (Join-Path $PSScriptRoot 'scan_sensitive.ps1') -ProjectRoot $root -TrackedSourceOnly
if ($LASTEXITCODE -ne 0) { throw 'Sensitive-data scan failed. Do not publish this checkout until the findings are resolved.' }

if (-not $SkipStart) {
    Write-Step 'Starting PaperAgent'
    & (Join-Path $root 'start_all_services.bat')
} else {
    Write-Host "`nDeployment is ready. Start later with start_all_services.bat" -ForegroundColor Green
}

Write-Host "`nPaperAgent deployment completed." -ForegroundColor Green
Write-Host 'Open: http://localhost:5000/'
