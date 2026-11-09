$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$zdir = Join-Path $root 'zapret'
$jobFile = Join-Path $root 'proxy\zapret-job.json'
$outLog = Join-Path $root 'proxy\zapret-run.log'
$log = Join-Path $root 'proxy\app.log'
$pidFile = Join-Path $root 'proxy\zapret-daemon.pid'

function Log([string]$m) {
    ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -LiteralPath $log -Append -Encoding UTF8
}

$PID | Out-File -LiteralPath $pidFile -Encoding ASCII
Log ('zapret daemon started pid=' + $PID)

$lastSeq = -1
$lastAction = ''

while ($true) {
    try {
        if (Test-Path $jobFile) {
            $job = $null
            try { $job = Get-Content -LiteralPath $jobFile -Raw | ConvertFrom-Json } catch { }
            if ($job -and $job.seq -ne $lastSeq) {
                $lastSeq = $job.seq
                if ($job.action -eq 'stop') {
                    Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force
                    Log 'zapret stopped (daemon)'
                }
                elseif ($job.action -eq 'start') {
                    Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force
                    Start-Sleep -Milliseconds 700
                    $bat = Join-Path $zdir $job.bat
                    if (Test-Path $bat) {
                        $text = Get-Content -LiteralPath $bat -Raw
                        $modified = $text -replace 'start\s+"[^"]*"\s*/min\s+', ''
                        $tmpBat = Join-Path $zdir '_run_current.bat'
                        [System.IO.File]::WriteAllText($tmpBat, $modified, [System.Text.Encoding]::Default)
                        $runLog = $outLog
                        for ($k = 0; $k -lt 6; $k++) {
                            try {
                                if (Test-Path $runLog) { Remove-Item $runLog -Force -ErrorAction Stop }
                                break
                            }
                            catch { Start-Sleep -Milliseconds 500 }
                        }
                        if (Test-Path $runLog) {
                            $runLog = Join-Path $root 'proxy\zapret-run-alt.log'
                            Remove-Item $runLog -Force -ErrorAction SilentlyContinue
                        }
                        $full = '/c "' + $tmpBat + ' > "' + $runLog + '" 2>&1"'
                        $full = '/c "' + $tmpBat + ' > "' + $runLog + '" 2>&1"'
                        Start-Process -FilePath 'cmd.exe' -ArgumentList $full -WorkingDirectory $zdir -WindowStyle Hidden
                        Log ('zapret start requested: ' + $job.bat)
                        Log ('zapret start requested: ' + $job.bat)
                    }
                    else {
                        Log ('zapret daemon: нет файла ' + $job.bat)
                    }
                }
            }
        }
    }
    catch {
        Log ('daemon ERROR: ' + $_.Exception.Message)
    }
    Start-Sleep -Milliseconds 400
}
