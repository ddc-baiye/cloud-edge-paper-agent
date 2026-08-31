[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$SkipPortCheck
)

$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$python = Join-Path $root '.venv\Scripts\python.exe'
$frontend = Join-Path $root 'EDGE\aithesis'
$qwenModel = Join-Path $root 'models\Qwen3-8b-ov-npu'
$translationModel = Join-Path $root 'models\HY-MT1.5-1.8B-int4-ov'
$failures = [System.Collections.Generic.List[string]]::new()

function Write-Check {
    param([bool]$Passed, [string]$Message)
    if ($Passed) {
        Write-Host "[OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Message" -ForegroundColor Red
        $failures.Add($Message)
    }
}

Write-Host 'PaperAgent environment check' -ForegroundColor Cyan
Write-Host "Project: $root"

Write-Check ([Environment]::Is64BitOperatingSystem) 'Windows is 64-bit'
Write-Check (Test-Path -LiteralPath $python) 'Python virtual environment exists'
Write-Check (Test-Path -LiteralPath (Join-Path $frontend 'node_modules')) 'Frontend dependencies exist'
Write-Check (Test-Path -LiteralPath (Join-Path $qwenModel 'openvino_model.xml')) 'Qwen3 OpenVINO XML exists'
Write-Check (Test-Path -LiteralPath (Join-Path $qwenModel 'openvino_model.bin')) 'Qwen3 OpenVINO BIN exists'
Write-Check (Test-Path -LiteralPath (Join-Path $translationModel 'openvino_model.xml')) 'HY-MT OpenVINO XML exists'
Write-Check (Test-Path -LiteralPath (Join-Path $translationModel 'openvino_model.bin')) 'HY-MT OpenVINO BIN exists'
Write-Check (Test-Path -LiteralPath (Join-Path $root 'nginx_install\nginx-1.30.1\nginx.exe')) 'Bundled Nginx exists'

if (Test-Path -LiteralPath $python) {
    $version = & $python -c "import sys; print('.'.join(map(str, sys.version_info[:3])))" 2>$null
    Write-Check ($LASTEXITCODE -eq 0 -and $version -like '3.11.*') "Python 3.11 is active ($version)"

    $packageCheck = & $python -c "import flask, gradio, openvino, openvino_genai, torch; print('imports-ok')" 2>$null
    Write-Check ($LASTEXITCODE -eq 0 -and $packageCheck -eq 'imports-ok') 'Python dependencies import successfully'

    $devices = & $python -c "import openvino as ov; print(','.join(ov.Core().available_devices))" 2>$null
    Write-Check ($LASTEXITCODE -eq 0) "OpenVINO device query succeeded ($devices)"
    Write-Check (($devices -split ',') -contains 'NPU') 'Intel NPU is available to OpenVINO'
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$npmCommand = Get-Command npm -ErrorAction SilentlyContinue
Write-Check ($null -ne $nodeCommand) 'Node.js is installed'
Write-Check ($null -ne $npmCommand) 'npm is installed'

if ($nodeCommand) {
    $nodeVersion = (& node --version 2>$null).TrimStart('v')
    $nodeParts = $nodeVersion.Split('.')
    $nodeSupported = [int]$nodeParts[0] -gt 20 -or (
        [int]$nodeParts[0] -eq 20 -and [int]$nodeParts[1] -ge 19
    )
    Write-Check $nodeSupported "Node.js meets Vite requirement ($nodeVersion)"
}

if (-not $SkipPortCheck) {
    foreach ($port in 5000, 5001, 5173, 7007) {
        $listeners = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
        if ($listeners.Count -eq 0) {
            Write-Host "[OK] Port $port is available" -ForegroundColor Green
        } else {
            Write-Host "[INFO] Port $port is currently in use by PID $($listeners.OwningProcess -join ',')" -ForegroundColor Yellow
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "`nEnvironment check failed with $($failures.Count) issue(s)." -ForegroundColor Red
    exit 1
}

Write-Host "`nEnvironment check passed." -ForegroundColor Green
