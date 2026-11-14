param([switch]$Minimized)

$ErrorActionPreference = 'Stop'

$appDir = $PSScriptRoot
. (Join-Path $appDir 'lib.ps1')
. (Join-Path $appDir 'zapret-lib.ps1')

& (Join-Path $appDir 'bootstrap.ps1')
Ensure-PacServer
Set-SystemPac

$cfg = Get-Config
$nodes = @(Get-Nodes)
if ($nodes.Count -eq 0) { $nodes = @(Update-Subscriptions) }

$node = $nodes | Where-Object { "$($_.host):$($_.port)" -eq $cfg.selectedNode } | Select-Object -First 1
if (-not $node) { $node = $nodes | Select-Object -First 1 }

if ($node) {
    Start-XrayNode $node
    if ((Test-Claude).ok) {
        Write-Log ('autostart: connected ' + $node.name + ' (fixed, без перебора)')
    }
    else {
        Write-Log ('autostart: сервер ' + $node.name + ' не ответил, остаёмся на нём (без автопереключения)')
    }
}


$already = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'Claude VPN' }
if (-not $already) {
    $appArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $appDir 'app.ps1'))
    if ($Minimized) { $appArgs += '-Minimized' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $appArgs -WindowStyle Hidden
}
