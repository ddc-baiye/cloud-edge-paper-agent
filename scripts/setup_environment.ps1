[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$Python = '3.11',
    [switch]$RecreateVenv,
    [switch]$SkipFrontend
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$venv = Join-Path $root '.venv'
$venvPython = Join-Path $venv 'Scripts\python.exe'
$lockFile = Join-Path $root 'requirements-lock.txt'
$frontend = Join-Path $root 'EDGE\aithesis'
$frontendPackage = Join-Path $frontend 'package.json'

Write-Host 'PaperAgent competition environment setup' -ForegroundColor Cyan
Write-Host "Project: $root"

$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
    throw @'
uv is not installed.
Install it first with one of these commands:
  winget install --id=astral-sh.uv -e
  powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"
Then reopen PowerShell and rerun deploy.bat.
'@
}

if (-not (Test-Path -LiteralPath $lockFile)) {
    throw "Dependency lock file is missing: $lockFile"
}

if ($RecreateVenv -and (Test-Path -LiteralPath $venv)) {
    $resolvedVenv = (Resolve-Path -LiteralPath $venv).Path
    if (-not $resolvedVenv.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a virtual environment outside the project: $resolvedVenv"
    }
    Remove-Item -LiteralPath $resolvedVenv -Recurse -Force
}

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host '[1/4] Creating Python 3.11 virtual environment...'
    & $uv.Source venv $venv --python $Python
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the Python virtual environment.' }
} else {
    Write-Host '[1/4] Existing virtual environment found.'
}

Write-Host '[2/4] Installing locked Python dependencies...'
& $uv.Source pip sync $lockFile --python $venvPython
if ($LASTEXITCODE -ne 0) { throw 'Failed to install Python dependencies.' }

if (-not $SkipFrontend) {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        throw 'npm is not installed. Install Node.js 20.19 or newer, then run this script again.'
    }
    if (-not (Test-Path -LiteralPath $frontendPackage)) {
        throw "Frontend package.json is missing: $frontendPackage"
    }

    Write-Host '[3/4] Installing competition frontend dependencies...'
    Push-Location $frontend
    try {
        $packageLock = Join-Path $frontend 'package-lock.json'
        if (Test-Path -LiteralPath $packageLock) {
            Write-Host 'Using package-lock.json with npm ci.'
            & $npm.Source ci
        } else {
            Write-Host 'No package-lock.json is bundled; using npm install for the sanitized competition UI.'
            & $npm.Source install --no-audit --no-fund
        }
        if ($LASTEXITCODE -ne 0) { throw 'Frontend dependency installation failed.' }
    } finally {
        Pop-Location
    }
} else {
    Write-Host '[3/4] Frontend installation skipped.'
}

Write-Host '[4/4] Configuring paths and checking the environment...'
& (Join-Path $PSScriptRoot 'configure_project.ps1') -ProjectRoot $root
if ($LASTEXITCODE -ne 0) { throw 'Project path configuration failed.' }

& (Join-Path $PSScriptRoot 'verify_environment.ps1') -ProjectRoot $root
if ($LASTEXITCODE -ne 0) { throw 'Environment verification failed. Review the failed checks above.' }

Write-Host "`nSetup completed. Start the project with start_all_services.bat." -ForegroundColor Green
