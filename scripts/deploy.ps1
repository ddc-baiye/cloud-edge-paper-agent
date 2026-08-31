[CmdletBinding()]
param(
    [switch]$SkipModelDownload,
    [switch]$SkipStart,
    [switch]$NonInteractive,
    [switch]$EdgeOnly,
    [switch]$OPEAOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($EdgeOnly -and $OPEAOnly) {
    throw '-EdgeOnly and -OPEAOnly cannot be used together.'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$nginxVersion = '1.30.1'
$nginxDir = Join-Path $root "nginx_install\nginx-$nginxVersion"
$modelsRoot = Join-Path $root 'models'
$hfCache = Join-Path $modelsRoot '.hf-cache'
$qwenDir = Join-Path $modelsRoot 'Qwen3-8b-ov-npu'
$translationDir = Join-Path $modelsRoot 'HY-MT1.5-1.8B-int4-ov'
$configExample = Join-Path $root 'CLOUD\config.example.yaml'
$configPath = Join-Path $root 'CLOUD\config.yaml'
$opeaDeployScript = Join-Path $PSScriptRoot 'deploy_opea.ps1'

$deployEdge = -not $OPEAOnly
$deployOpea = -not $EdgeOnly
$opeaSkipped = $false

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

function Resolve-FirstNonEmpty([string[]]$Values) {
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }
    return ''
}

function Test-DockerReady {
    $docker = Get-CommandOrNull 'docker'
    if (-not $docker) { return $false }
    & $docker.Source compose version *> $null
    if ($LASTEXITCODE -ne 0) { return $false }
    & $docker.Source version --format '{{.Server.Version}}' *> $null
    return ($LASTEXITCODE -eq 0)
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
    throw 'The root competition deployment entry currently targets Windows 10/11 x64. OPEA itself runs in Docker containers.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw '64-bit Windows is required.'
}

Write-Host 'PaperAgent AI for Good OPEA Competition deployment' -ForegroundColor Green
Write-Host "Project: $root"
Write-Host "Mode: $(if ($EdgeOnly) { 'Edge only' } elseif ($OPEAOnly) { 'OPEA cloud only' } else { 'Edge + OPEA cloud' })"

if ($deployOpea -and -not (Test-DockerReady)) {
    if ($OPEAOnly) {
        throw @'
Docker with the Compose plugin is not ready.
Install/start Docker Desktop and confirm both commands work:
  docker version
  docker compose version
Then rerun deploy.bat -OPEAOnly.
'@
    }
    Write-Host '[WARN] Docker/Compose is not ready. The Edge deployment will continue, but OPEA cloud deployment will be skipped.' -ForegroundColor Yellow
    Write-Host '       Install/start Docker Desktop, then run: deploy.bat -OPEAOnly' -ForegroundColor Yellow
    $deployOpea = $false
    $opeaSkipped = $true
}

$llmEndpoint = Resolve-FirstNonEmpty @($env:PAPERAGENT_LLM_ENDPOINT, $env:LLM_ENDPOINT)
$llmModelId = Resolve-FirstNonEmpty @($env:PAPERAGENT_LLM_MODEL_ID, $env:LLM_MODEL_ID)
$llmKey = Resolve-FirstNonEmpty @($env:PAPERAGENT_LLM_API_KEY, $env:OPENAI_API_KEY)
$mineruToken = Resolve-FirstNonEmpty @($env:MINERU_API_TOKEN)

if ($deployOpea) {
    if (-not $NonInteractive) {
        if ([string]::IsNullOrWhiteSpace($llmEndpoint)) {
            $llmEndpoint = (Read-Host 'Enter your OpenAI-compatible LLM endpoint').Trim()
        }
        if ([string]::IsNullOrWhiteSpace($llmModelId)) {
            $llmModelId = (Read-Host 'Enter your cloud LLM model ID').Trim()
        }
        if ([string]::IsNullOrWhiteSpace($llmKey)) {
            $llmKey = Read-SecretText 'Enter your cloud LLM API Key'
        }
    }
    if ([string]::IsNullOrWhiteSpace($llmEndpoint)) {
        throw 'OPEA cloud requires a user-supplied endpoint. Set PAPERAGENT_LLM_ENDPOINT or enter it interactively.'
    }
    if ([string]::IsNullOrWhiteSpace($llmModelId)) {
        throw 'OPEA cloud requires a user-supplied model ID. Set PAPERAGENT_LLM_MODEL_ID or enter it interactively.'
    }
    if ([string]::IsNullOrWhiteSpace($llmKey)) {
        throw 'OPEA cloud requires a user-supplied API Key. Set PAPERAGENT_LLM_API_KEY or enter it interactively.'
    }
}

if ($deployEdge) {
    Write-Step 'Edge 1/7 - Preparing uv'
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

    Write-Step 'Edge 2/7 - Preparing Node.js'
    if (-not (Get-CommandOrNull 'node') -or -not (Get-CommandOrNull 'npm')) {
        Install-WithWinget 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    }
    $node = Get-CommandOrNull 'node'
    $npm = Get-CommandOrNull 'npm'
    if (-not $node -or -not $npm) { throw 'Node.js/npm is still unavailable after installation.' }
    Write-Host "[OK] Node.js: $(& $node.Source --version)" -ForegroundColor Green

    Write-Step 'Edge 3/7 - Preparing Nginx'
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

    Write-Step 'Edge 4/7 - Preparing required OpenVINO models (2/2)'
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

    Write-Step 'Edge 5/7 - Creating local cloud configuration'
    if (-not (Test-Path $configExample)) { throw "Missing configuration template: $configExample" }
    $configText = Get-Content -LiteralPath $configExample -Raw -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($llmEndpoint)) {
        $safeEndpoint = Escape-YamlDoubleQuoted $llmEndpoint
        $configText = [regex]::Replace($configText, '(?m)^  base_url:\s*""\s*$', "  base_url: `"$safeEndpoint`"")
    }
    if (-not [string]::IsNullOrWhiteSpace($llmModelId)) {
        $safeModel = Escape-YamlDoubleQuoted $llmModelId
        $configText = [regex]::Replace($configText, '(?m)^  model:\s*""\s*$', "  model: `"$safeModel`"")
    }
    if (-not [string]::IsNullOrWhiteSpace($llmKey)) {
        $safeKey = Escape-YamlDoubleQuoted $llmKey
        $configText = [regex]::Replace($configText, '(?m)^  api_key:\s*""\s*$', "  api_key: `"$safeKey`"")
    } else {
        Write-Host '[WARN] Cloud LLM API Key is empty. OPEA is disabled or skipped; the local cloud UI will use its offline retrieval fallback.' -ForegroundColor Yellow
    }

    if (-not $NonInteractive -and [string]::IsNullOrWhiteSpace($mineruToken)) {
        $mineruToken = Read-SecretText 'Optional: enter MinerU API Token for PDF parsing (press Enter to skip)'
    }
    if (-not [string]::IsNullOrWhiteSpace($mineruToken)) {
        $safeMineru = Escape-YamlDoubleQuoted $mineruToken
        $configText = [regex]::Replace($configText, '(?m)^  api_token:\s*""\s*$', "  api_token: `"$safeMineru`"")
    }
    [IO.File]::WriteAllText($configPath, $configText, (New-Object Text.UTF8Encoding($false)))
    Write-Host '[OK] CLOUD/config.yaml created. The file is git-ignored.' -ForegroundColor Green

    Write-Step 'Edge 6/7 - Installing dependencies and validating hardware'
    & (Join-Path $PSScriptRoot 'setup_environment.ps1') -ProjectRoot $root
    if ($LASTEXITCODE -ne 0) { throw 'Environment setup or verification failed.' }

    Write-Step 'Edge 7/7 - Edge preparation complete'
}

if ($deployOpea) {
    Write-Step 'OPEA Cloud - Deploying MicroServices and MegaService'
    if (-not (Test-Path -LiteralPath $opeaDeployScript -PathType Leaf)) {
        throw "Missing OPEA deployment script: $opeaDeployScript"
    }

    $oldEndpoint = $env:PAPERAGENT_LLM_ENDPOINT
    $oldModel = $env:PAPERAGENT_LLM_MODEL_ID
    $oldKey = $env:PAPERAGENT_LLM_API_KEY
    try {
        $env:PAPERAGENT_LLM_ENDPOINT = $llmEndpoint
        $env:PAPERAGENT_LLM_MODEL_ID = $llmModelId
        $env:PAPERAGENT_LLM_API_KEY = $llmKey
        if ($SkipStart) {
            & $opeaDeployScript -ProjectRoot $root -NonInteractive -SkipStart
        } else {
            & $opeaDeployScript -ProjectRoot $root -NonInteractive
        }
        if ($LASTEXITCODE -ne 0) {
            throw 'OPEA cloud deployment failed.'
        }
    } finally {
        if ($null -eq $oldEndpoint) { Remove-Item Env:PAPERAGENT_LLM_ENDPOINT -ErrorAction SilentlyContinue } else { $env:PAPERAGENT_LLM_ENDPOINT = $oldEndpoint }
        if ($null -eq $oldModel) { Remove-Item Env:PAPERAGENT_LLM_MODEL_ID -ErrorAction SilentlyContinue } else { $env:PAPERAGENT_LLM_MODEL_ID = $oldModel }
        if ($null -eq $oldKey) { Remove-Item Env:PAPERAGENT_LLM_API_KEY -ErrorAction SilentlyContinue } else { $env:PAPERAGENT_LLM_API_KEY = $oldKey }
    }
}

Write-Step 'Running repository sensitive-data scan'
& (Join-Path $PSScriptRoot 'scan_sensitive.ps1') -ProjectRoot $root -TrackedSourceOnly
if ($LASTEXITCODE -ne 0) {
    throw 'Sensitive-data scan failed. Do not publish this checkout until the findings are resolved.'
}

if (-not $SkipStart -and $deployEdge) {
    Write-Step 'Starting local PaperAgent UI and edge services'
    & (Join-Path $root 'start_all_services.bat')
    if ($LASTEXITCODE -ne 0) {
        throw 'Local PaperAgent service startup failed.'
    }
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host 'PaperAgent deployment completed.' -ForegroundColor Green
Write-Host '=======================================================' -ForegroundColor Green
if ($deployEdge) {
    Write-Host '[OK] Edge / AI PC runtime prepared.' -ForegroundColor Green
    if (-not $SkipStart) { Write-Host '     UI: http://localhost:5000/' }
}
if ($deployOpea) {
    Write-Host '[OK] OPEA cloud runtime prepared.' -ForegroundColor Green
    if (-not $SkipStart) {
        Write-Host '     MegaService: http://localhost:7008/v1/paperagent'
        Write-Host '     Topology:    http://localhost:7008/v1/topology'
    }
} elseif ($opeaSkipped) {
    Write-Host '[WARN] OPEA cloud was skipped because Docker/Compose was not ready.' -ForegroundColor Yellow
    Write-Host '       After Docker is ready, run: deploy.bat -OPEAOnly' -ForegroundColor Yellow
}
