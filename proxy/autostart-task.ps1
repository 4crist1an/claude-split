param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$TaskName = 'ClaudeSplit Autostart'
$appDir = $PSScriptRoot
$startAll = Join-Path $appDir 'start-all.ps1'

if ($Remove) {
    & schtasks.exe /delete /tn $TaskName /f 2>&1 | Out-Null
    Write-Host "Autostart task removed."
    exit 0
}

$action = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $startAll + '" -Minimized'
$out = & schtasks.exe /create /tn $TaskName /tr $action /sc onlogon /rl HIGHEST /f 2>&1
$out | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Autostart task created (runs as administrator at logon)." -ForegroundColor Green
