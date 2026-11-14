param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$appDir = $PSScriptRoot
$startAll = Join-Path $appDir 'start-all.ps1'
$daemon = Join-Path $appDir 'zapret-daemon.ps1'

$AppTask = 'ClaudeSplit Autostart'
$DaemonTask = 'ClaudeSplit Zapret Daemon'

$appAction = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $startAll + '" -Minimized'
$daemonAction = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $daemon + '"'

if ($Remove) {
    & schtasks.exe /delete /tn $AppTask /f 2>&1 | Out-Null
    & schtasks.exe /delete /tn $DaemonTask /f 2>&1 | Out-Null
    Write-Host "Autostart tasks removed."
    exit 0
}

$out1 = & schtasks.exe /create /tn $AppTask /tr $appAction /sc onlogon /rl HIGHEST /f 2>&1
$out1 | Out-String | Write-Host

# демон zapret должен работать с правами админа: иначе WinDivert -> Access is denied
$out2 = & schtasks.exe /create /tn $DaemonTask /tr $daemonAction /sc onlogon /rl HIGHEST /f 2>&1
$out2 | Out-String | Write-Host

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Tasks created: app + zapret daemon (both elevated at logon)." -ForegroundColor Green
