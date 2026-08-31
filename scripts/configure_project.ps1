[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$rootForNginx = $root.Replace('\', '/')
$nginxDir = Join-Path $root 'nginx_install\nginx-1.30.1'
$nginxConf = Join-Path $nginxDir 'conf\nginx.conf'
$proxyConf = Join-Path $root 'nginx\paperagents.conf'
$logsDir = Join-Path $root 'logs'
$qwenModel = Join-Path $root 'models\Qwen3-8b-ov-npu'
$translationModel = Join-Path $root 'models\HY-MT1.5-1.8B-int4-ov'

$requiredPaths = @(
    (Join-Path $root 'EDGE\main_npu.py'),
    (Join-Path $root 'EDGE\aithesis\package.json'),
    (Join-Path $root 'CLOUD\src\app.py'),
    (Join-Path $qwenModel 'openvino_model.xml'),
    (Join-Path $qwenModel 'openvino_model.bin'),
    (Join-Path $translationModel 'openvino_model.xml'),
    (Join-Path $translationModel 'openvino_model.bin'),
    (Join-Path $nginxDir 'nginx.exe'),
    $proxyConf
)

$missingPaths = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missingPaths.Count -gt 0) {
    Write-Host '[ERROR] Required project files are missing:' -ForegroundColor Red
    $missingPaths | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

if ($CheckOnly) {
    Write-Host "[OK] Required project layout is complete: $root" -ForegroundColor Green
    Write-Host '[OK] Qwen3 and HY-MT OpenVINO models are both present.' -ForegroundColor Green
    exit 0
}

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$nginxConfig = @"
worker_processes  1;

error_log  "$rootForNginx/logs/nginx_error.log";

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout  65;

    access_log "$rootForNginx/logs/nginx_access.log";

    include "$rootForNginx/nginx/paperagents.conf";
}
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($nginxConf, $nginxConfig, $utf8NoBom)
Write-Host "[OK] Nginx paths updated for: $root" -ForegroundColor Green
