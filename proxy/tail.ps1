$base = $PSScriptRoot

$host.UI.RawUI.WindowTitle = 'Claude VPN — лог'
try { chcp 65001 > $null } catch { }

$log = Join-Path $base 'app.log'
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' Claude VPN — живой лог (Ctrl+C или закрыть окно)' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-Path $log)) { 'событий пока нет' | Out-File -LiteralPath $log -Encoding UTF8 }
Get-Content -LiteralPath $log -Tail 40 -Wait
