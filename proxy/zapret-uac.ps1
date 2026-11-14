param([string]$Preset = 'general (ALT).bat')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$zdir = Join-Path $root 'zapret'
$log = Join-Path $PSScriptRoot 'app.log'

function Log([string]$m) {
    ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -LiteralPath $log -Append -Encoding UTF8
}

Get-Process winws -ErrorAction SilentlyContinue | ForEach-Object { & taskkill.exe /PID $_.Id /T /F *> $null }
Start-Sleep -Milliseconds 1500

$bat = Join-Path $zdir $Preset
if (-not (Test-Path $bat)) { Log ('uac-run: нет пресета ' + $Preset); exit 1 }

$text = Get-Content -LiteralPath $bat -Raw
$text = $text -replace 'start\s+"[^"]*"\s*/min\s+', ''
$tmp = Join-Path $zdir '_run_current.bat'
[System.IO.File]::WriteAllText($tmp, $text, [System.Text.Encoding]::Default)

$runLog = Join-Path $PSScriptRoot 'zapret-run.log'
try { if (Test-Path $runLog) { Remove-Item $runLog -Force -ErrorAction Stop } } catch { $runLog = Join-Path $PSScriptRoot 'zapret-run-alt.log' }

Log ('uac-run: запускаю ' + $Preset)
# foreground: процесс живёт, пока работает winws
& cmd.exe /c ('"' + $tmp + '" > "' + $runLog + '" 2>&1')
Log 'uac-run: winws завершился'
