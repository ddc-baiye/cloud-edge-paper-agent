[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$TrackedSourceOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path

$excludedPrefixes = @(
    '.git\', '.venv\', 'EDGE\aithesis\node_modules\', 'models\',
    'nginx_install\', 'logs\', 'uploads\', 'CLOUD\out\', 'CLOUD\input\',
    'CLOUD\extra_input\', 'CLOUD\extra_chunks\'
)
$excludedRelativeFiles = @('CLOUD\config.yaml')

$patterns = @(
    @{ Name = 'API key'; Regex = '(?i)\bsk-[A-Za-z0-9_\-]{12,}' },
    @{ Name = 'JWT/token'; Regex = '\beyJ[A-Za-z0-9_\-]{12,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b' },
    @{ Name = 'hard-coded credential'; Regex = '(?i)\b(?:api[_-]?key|api[_-]?token|authtoken|access[_-]?token|secret[_-]?key|client[_-]?secret)\b\s*[:=]\s*["'']?[A-Za-z0-9._\-]{12,}' },
    @{ Name = 'private IPv4 address'; Regex = '\b(?:10\.(?:\d{1,3}\.){2}\d{1,3}|192\.168\.(?:\d{1,3}\.)\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.(?:\d{1,3}\.)\d{1,3})\b' },
    @{ Name = 'intranet backup marker'; Regex = '(?i)(?:bak[_-]?intranet|_intranet_)' }
)

function Get-Relative([string]$Path) {
    return ([IO.Path]::GetFullPath($Path).Substring($root.Length).TrimStart('\', '/').Replace('/', '\'))
}

function Is-Excluded([string]$Path) {
    $relative = Get-Relative $Path
    foreach ($file in $excludedRelativeFiles) {
        if ($relative.Equals($file, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    foreach ($prefix in $excludedPrefixes) {
        if ($relative.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$files = @()
if ($TrackedSourceOnly -and (Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $root '.git'))) {
    Push-Location $root
    try {
        $tracked = & git ls-files
        if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
        $files = @($tracked | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    } finally {
        Pop-Location
    }
} else {
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Select-Object -ExpandProperty FullName)
}

$findings = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    if (Is-Excluded $file) { continue }
    try {
        $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop
        if ($null -eq $text) { $text = '' }
    } catch {
        continue
    }
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches([string]$text, $pattern.Regex)) {
            $before = $text.Substring(0, $match.Index)
            $line = ($before -split "`n").Count
            $relative = (Get-Relative $file).Replace('\', '/')
            $findings.Add([pscustomobject]@{ Type = $pattern.Name; File = $relative; Line = $line })
        }
    }
}

$unique = @($findings | Sort-Object File, Line, Type -Unique)
if ($unique.Count -gt 0) {
    Write-Host "[FAIL] Sensitive-data scan found $($unique.Count) potential issue(s):" -ForegroundColor Red
    $unique | Format-Table -AutoSize
    Write-Host 'Review the files above before publishing. Secret values are intentionally not printed.' -ForegroundColor Yellow
    exit 1
}

Write-Host '[OK] No high-risk credential, private-IP, or intranet-backup patterns found in publishable source files.' -ForegroundColor Green
exit 0
