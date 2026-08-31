[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$NonInteractive,
    [switch]$SkipStart,
    [string]$LlmEndpoint,
    [string]$LlmModelId,
    [string]$LlmApiKey
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$opeaDir = Join-Path $root 'CLOUD\opea'
$composeFile = Join-Path $opeaDir 'docker-compose.yml'
$envExample = Join-Path $opeaDir '.env.example'
$envFile = Join-Path $opeaDir '.env'

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
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

function Resolve-FirstNonEmpty([string[]]$Values) {
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }
    return ''
}

function Normalize-OpeaEndpoint([string]$Endpoint) {
    $value = $Endpoint.Trim().TrimEnd('/')
    if ($value.EndsWith('/v1', [StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 3).TrimEnd('/')
    }
    return $value
}

function Escape-DotEnv([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value.Contains("`r") -or $Value.Contains("`n")) {
        throw 'Environment values must not contain newlines.'
    }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Test-DockerReady {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) { return $false }

    & $docker.Source compose version *> $null
    if ($LASTEXITCODE -ne 0) { return $false }

    & $docker.Source version --format '{{.Server.Version}}' *> $null
    return ($LASTEXITCODE -eq 0)
}

function Wait-HttpReady([string]$Url, [int]$Attempts = 60) {
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return $true
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $composeFile -PathType Leaf)) {
    throw "Missing OPEA compose file: $composeFile"
}
if (-not (Test-Path -LiteralPath $envExample -PathType Leaf)) {
    throw "Missing OPEA environment template: $envExample"
}
if (-not (Test-DockerReady)) {
    throw @'
Docker with the Compose plugin is not ready.
Install/start Docker Desktop, confirm `docker version` and `docker compose version` work,
then rerun `deploy.bat -OPEAOnly` or the full deployment.
'@
}

$endpoint = Resolve-FirstNonEmpty @(
    $LlmEndpoint,
    $env:PAPERAGENT_LLM_ENDPOINT,
    $env:LLM_ENDPOINT
)
$model = Resolve-FirstNonEmpty @(
    $LlmModelId,
    $env:PAPERAGENT_LLM_MODEL_ID,
    $env:LLM_MODEL_ID
)
$key = Resolve-FirstNonEmpty @(
    $LlmApiKey,
    $env:PAPERAGENT_LLM_API_KEY,
    $env:OPENAI_API_KEY
)

if (-not $NonInteractive) {
    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        $endpoint = (Read-Host 'Enter your OpenAI-compatible LLM endpoint (for example, provider root URL)').Trim()
    }
    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = (Read-Host 'Enter your cloud LLM model ID').Trim()
    }
    if ([string]::IsNullOrWhiteSpace($key)) {
        $key = Read-SecretText 'Enter your cloud LLM API Key'
    }
}

if ([string]::IsNullOrWhiteSpace($endpoint)) {
    throw 'LLM endpoint is required for OPEA cloud deployment. Set PAPERAGENT_LLM_ENDPOINT or enter it interactively.'
}
if ([string]::IsNullOrWhiteSpace($model)) {
    throw 'LLM model ID is required for OPEA cloud deployment. Set PAPERAGENT_LLM_MODEL_ID or enter it interactively.'
}
if ([string]::IsNullOrWhiteSpace($key)) {
    throw 'LLM API Key is required for OPEA cloud deployment. Set PAPERAGENT_LLM_API_KEY or enter it interactively.'
}

$opeaEndpoint = Normalize-OpeaEndpoint $endpoint
if ([string]::IsNullOrWhiteSpace($opeaEndpoint)) {
    throw 'The supplied LLM endpoint is invalid.'
}

Write-Step 'Preparing local OPEA configuration'
$template = Get-Content -LiteralPath $envExample -Raw -Encoding UTF8
$template = [regex]::Replace($template, '(?m)^LLM_ENDPOINT=.*$', 'LLM_ENDPOINT=' + (Escape-DotEnv $opeaEndpoint))
$template = [regex]::Replace($template, '(?m)^LLM_MODEL_ID=.*$', 'LLM_MODEL_ID=' + (Escape-DotEnv $model))
$template = [regex]::Replace($template, '(?m)^OPENAI_API_KEY=.*$', 'OPENAI_API_KEY=' + (Escape-DotEnv $key))
[IO.File]::WriteAllText($envFile, $template, (New-Object Text.UTF8Encoding($false)))
Write-Host '[OK] CLOUD/opea/.env created. The file is git-ignored.' -ForegroundColor Green
Write-Host "[OK] OPEA LLM endpoint: $opeaEndpoint" -ForegroundColor Green
Write-Host "[OK] OPEA model ID: $model" -ForegroundColor Green

$docker = Get-Command docker -ErrorAction Stop
Write-Step 'Validating OPEA Docker Compose configuration'
Push-Location $opeaDir
try {
    & $docker.Source compose --env-file $envFile -f $composeFile config | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'docker compose config validation failed.'
    }

    if ($SkipStart) {
        Write-Host '[OK] OPEA configuration is ready. Container start was skipped.' -ForegroundColor Green
        return
    }

    Write-Step 'Starting OPEA MicroServices and MegaService'
    & $docker.Source compose --env-file $envFile -f $composeFile up -d --build
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to start the OPEA cloud stack.'
    }
} finally {
    Pop-Location
}

Write-Step 'Waiting for OPEA service health checks'
$healthUrls = @(
    'http://127.0.0.1:7011/health',
    'http://127.0.0.1:7012/health',
    'http://127.0.0.1:9000/health',
    'http://127.0.0.1:7008/health'
)
foreach ($url in $healthUrls) {
    if (-not (Wait-HttpReady $url)) {
        throw "OPEA service did not become healthy: $url"
    }
    Write-Host "[OK] $url" -ForegroundColor Green
}

Write-Step 'Verifying OPEA topology'
$topology = Invoke-RestMethod -Uri 'http://127.0.0.1:7008/v1/topology' -Method Get -TimeoutSec 10
if ($topology.framework -ne 'OPEA') {
    throw 'OPEA topology endpoint returned an unexpected framework marker.'
}
$expectedFlow = @('paperagent-retriever', 'paperagent-prompt', 'opea-service@llm')
$actualFlow = @($topology.flow)
if (($actualFlow -join '|') -ne ($expectedFlow -join '|')) {
    throw "Unexpected OPEA flow: $($actualFlow -join ' -> ')"
}
Write-Host "[OK] OPEA flow: $($actualFlow -join ' -> ')" -ForegroundColor Green

Write-Step 'Running OPEA RAG smoke test'
$payload = @{ text = 'Explain how PaperAgent combines edge privacy with cloud literature intelligence.' } | ConvertTo-Json
$response = Invoke-RestMethod `
    -Uri 'http://127.0.0.1:7008/v1/paperagent' `
    -Method Post `
    -ContentType 'application/json' `
    -Body $payload `
    -TimeoutSec 180

if ($response.framework -ne 'OPEA') {
    throw 'OPEA smoke test returned an unexpected framework marker.'
}
if ([string]::IsNullOrWhiteSpace([string]$response.answer)) {
    throw 'OPEA smoke test returned an empty answer.'
}
Write-Host '[OK] OPEA RAG smoke test passed.' -ForegroundColor Green
Write-Host "`nOPEA cloud deployment completed." -ForegroundColor Green
Write-Host 'MegaService: http://localhost:7008/v1/paperagent'
Write-Host 'Topology:    http://localhost:7008/v1/topology'
