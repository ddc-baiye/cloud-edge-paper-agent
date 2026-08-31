[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$SkipRagQuery
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$opeaDir = Join-Path $root 'CLOUD\opea'
$envFile = Join-Path $opeaDir '.env'

function Write-Ok([string]$Text) {
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Fail([string]$Text) {
    Write-Host "[FAIL] $Text" -ForegroundColor Red
}

function Test-Url([string]$Url) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)
    } catch {
        return $false
    }
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' PaperAgent OPEA Verification' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Fail 'Docker command not found.'
    exit 1
}
& $docker.Source compose version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Fail 'Docker Compose plugin is unavailable.'
    exit 1
}
& $docker.Source version --format '{{.Server.Version}}' *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Fail 'Docker daemon is not ready.'
    exit 1
}
Write-Ok 'Docker and Docker Compose are ready.'

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    Write-Fail 'CLOUD/opea/.env is missing. Run deploy.bat -OPEAOnly first.'
    exit 1
}
Write-Ok 'Local OPEA configuration exists and is git-ignored.'

$checks = [ordered]@{
    'Retriever :7011' = 'http://127.0.0.1:7011/health'
    'Prompt :7012' = 'http://127.0.0.1:7012/health'
    'OPEA LLM :9000' = 'http://127.0.0.1:9000/health'
    'MegaService :7008' = 'http://127.0.0.1:7008/health'
}

$failed = $false
foreach ($name in $checks.Keys) {
    if (Test-Url $checks[$name]) {
        Write-Ok $name
    } else {
        Write-Fail $name
        $failed = $true
    }
}
if ($failed) { exit 1 }

try {
    $topology = Invoke-RestMethod -Uri 'http://127.0.0.1:7008/v1/topology' -Method Get -TimeoutSec 10
    $expected = @('paperagent-retriever', 'paperagent-prompt', 'opea-service@llm')
    $actual = @($topology.flow)
    if ($topology.framework -ne 'OPEA' -or (($actual -join '|') -ne ($expected -join '|'))) {
        throw "Unexpected topology: $($actual -join ' -> ')"
    }
    Write-Ok "OPEA topology: $($actual -join ' -> ')"
} catch {
    Write-Fail "Topology verification failed: $($_.Exception.Message)"
    exit 1
}

if (-not $SkipRagQuery) {
    try {
        $body = @{ text = 'Summarize the privacy-aware edge-cloud design of PaperAgent.' } | ConvertTo-Json
        $result = Invoke-RestMethod `
            -Uri 'http://127.0.0.1:7008/v1/paperagent' `
            -Method Post `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec 180
        if ($result.framework -ne 'OPEA' -or [string]::IsNullOrWhiteSpace([string]$result.answer)) {
            throw 'MegaService returned an invalid OPEA response.'
        }
        Write-Ok 'OPEA RAG query completed successfully.'
    } catch {
        Write-Fail "OPEA RAG query failed: $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "`nOPEA verification passed." -ForegroundColor Green
exit 0
