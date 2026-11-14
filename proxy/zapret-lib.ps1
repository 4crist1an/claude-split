function Enter-ZapretLock([int]$timeoutMs = 90000) {
    if (-not $script:ZLock) { $script:ZLock = New-Object System.Threading.Mutex($false, 'Global\ClaudeSplitZapretLock') }
    try { return $script:ZLock.WaitOne($timeoutMs) } catch { return $false }
}

function Exit-ZapretLock() {
    if ($script:ZLock) { try { $script:ZLock.ReleaseMutex() } catch { } }
}

$ErrorActionPreference = 'Stop'

$script:ZAppDir = $PSScriptRoot
$script:ZRoot = Split-Path $PSScriptRoot -Parent
$script:ZDir = Join-Path $script:ZRoot 'zapret'
$script:ZJob = Join-Path $script:ZAppDir 'zapret-job.json'
$script:ZDaemonPid = Join-Path $script:ZAppDir 'zapret-daemon.pid'
$script:ZRunLog = Join-Path $script:ZAppDir 'zapret-run.log'
$script:ZBench = Join-Path $script:ZAppDir 'zapret-bench.json'
$script:ZAppLog = Join-Path $script:ZAppDir 'app.log'
$script:ZSeq = $null

function ZLog([string]$m) {
    ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -LiteralPath $script:ZAppLog -Append -Encoding UTF8
}

function Get-ZapretVersion {
    $f = Join-Path $script:ZDir 'version.json'
    if (Test-Path $f) { try { return (Get-Content $f -Raw | ConvertFrom-Json).tag } catch { } }
    return ''
}

function Get-ZapretLatest {
    $api = & curl.exe -s --max-time 25 -H 'User-Agent: ClaudeVPN' 'https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/latest'
    $rel = $api | ConvertFrom-Json
    return [pscustomobject]@{ tag = $rel.tag_name; url = ($rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1).browser_download_url }
}

function Get-ZapretPresets {
    return @(Get-ChildItem -LiteralPath $script:ZDir -Filter '*.bat' | Where-Object { $_.Name -ne 'service.bat' -and $_.Name -notlike '_run_*' } | Select-Object -ExpandProperty Name | Sort-Object)
}

function Test-ZapretDaemon {
    if (-not (Test-Path $script:ZDaemonPid)) { return $false }
    try {
        $parts = ((Get-Content $script:ZDaemonPid -Raw).Trim()) -split '\|'
        $p = [int]$parts[0]
        $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
        if (-not $proc) { return $false }
        if ($parts.Count -ge 2) {
            $want = [long]$parts[1]
            if ([Math]::Abs($proc.StartTime.Ticks - $want) -gt 20000000) { return $false }
        }
        if ($parts.Count -ge 3 -and $parts[2] -eq '0') {
            # демон без прав администратора — WinDivert не откроется
            try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch { }
            Remove-Item $script:ZDaemonPid -Force -ErrorAction SilentlyContinue
            return $false
        }
        return $true
    } catch { }
    return $false
}

function Ensure-ZapretDaemon {
    if (Test-ZapretDaemon) { return $true }
    Remove-Item $script:ZDaemonPid -Force -ErrorAction SilentlyContinue

    ZLog 'запускаю zapret-демон (нужно подтвердить UAC)'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $script:ZAppDir 'zapret-daemon.ps1')) -ErrorAction Stop
    } catch {
        ZLog ('демон не запущен: ' + $_.Exception.Message)
        return $false
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-ZapretDaemon) { return $true }
    }
    return $false
}

function Get-NextSeq {
    if ($null -eq $script:ZSeq) {
        $script:ZSeq = 0
        if (Test-Path $script:ZJob) { try { $script:ZSeq = [int](Get-Content $script:ZJob -Raw | ConvertFrom-Json).seq } catch { } }
    }
    $script:ZSeq++
    return $script:ZSeq
}

function Send-ZapretJob([string]$action, [string]$bat) {
    $job = [ordered]@{ seq = (Get-NextSeq); action = $action; bat = $bat }
    [System.IO.File]::WriteAllText($script:ZJob, ($job | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
}

function Stop-Zapret {
    $got = Enter-ZapretLock 30000
    try {
        Stop-ZapretLocked
    }
    finally { if ($got) { Exit-ZapretLock } }
}

function Stop-ZapretLocked {
    $kill = Join-Path $script:ZAppDir 'zapret-kill.ps1'
    if (Test-Path $kill) {
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $kill) -Wait -ErrorAction Stop
        }
        catch { ZLog ('stop: UAC отменён — ' + $_.Exception.Message) }
    }
    Remove-Item (Join-Path $script:ZAppDir 'zapret-last.txt') -Force -ErrorAction SilentlyContinue
    ZLog 'zapret остановлен'
}
function Start-ZapretPreset([string]$batName) {
    $got = Enter-ZapretLock 90000
    try {
        return Start-ZapretPresetLocked $batName
    }
    finally { if ($got) { Exit-ZapretLock } }
}

function Start-ZapretPresetLocked([string]$batName) {
    $lastFile = Join-Path $script:ZAppDir 'zapret-last.txt'
    if ((Get-ZapretStatus).running -and (Test-Path $lastFile)) {
        $last = (Get-Content $lastFile -Raw).Trim()
        if ($last -eq $batName) { ZLog ('zapret уже запущен: ' + $batName); return $true }
    }

    $uac = Join-Path $script:ZAppDir 'zapret-uac.ps1'
    if (-not (Test-Path $uac)) { ZLog 'нет zapret-uac.ps1'; return $false }
    ZLog ('запускаю zapret через UAC: ' + $batName)
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $uac, '-Preset', ('"' + $batName + '"')) -ErrorAction Stop
    }
    catch { ZLog ('UAC отменён: ' + $_.Exception.Message); return $false }

    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 700
        if (Get-Process winws -ErrorAction SilentlyContinue) {
            Set-Content -LiteralPath $lastFile -Value $batName -Encoding UTF8
            ZLog ('zapret started: ' + $batName)
            return $true
        }
    }
    ZLog ('zapret FAILED: ' + $batName)
    return $false
}

function Get-ZapretStatus {
    $p = Get-Process winws -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return [pscustomobject]@{ running = $true; pid = $p.Id } }
    return [pscustomobject]@{ running = $false; pid = 0 }
}

function Test-Endpoint([string]$url, [int]$timeoutSec = 8) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time $timeoutSec $url 2>$null
    $sw.Stop()
    return [pscustomobject]@{ code = "$code"; ms = [int]$sw.ElapsedMilliseconds }
}

function Save-BenchResult($results, [bool]$done) {
    $best = $results | Where-Object { $_.score -gt 0 } | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = 'avgMs'; Descending = $false } | Select-Object -First 1
    [ordered]@{
        at   = (Get-Date).ToString('o')
        done = $done
        best = if ($best) { $best.preset } else { '' }
        data = $results
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:ZBench -Encoding UTF8
    return $best
}

function Test-ZapretPresets([string[]]$Only) {
    $presets = if ($Only) { $Only } else { Get-ZapretPresets }
    $total = $presets.Count
    $results = @()
    $i = 0
    foreach ($p in $presets) {
        $i++
        Write-Progress -Activity 'Подбор пресета zapret' -Status "$i / $total : $p" -PercentComplete (($i / $total) * 100)
        $started = Start-ZapretPreset $p
        if ($started) {
            Start-Sleep -Milliseconds 800
            $yt = Test-Endpoint 'https://www.youtube.com/' 8
            $dc = Test-Endpoint 'https://discord.com/' 8
            $okYt = ($yt.code -eq '200') -or ($yt.code -eq '301') -or ($yt.code -eq '302')
            $okDc = ($dc.code -eq '200') -or ($dc.code -eq '301') -or ($dc.code -eq '302')
            $score = 0
            if ($okYt) { $score += 2 }
            if ($okDc) { $score += 2 }
            if ($score -eq 4) { $score += 1 }
            $avg = [int](($yt.ms + $dc.ms) / 2)
            $results += [pscustomobject]@{ preset = $p; score = $score; yt = $yt.code; dc = $dc.code; avgMs = $avg }
            ZLog ("preset test: {0} score={1} yt={2} dc={3} avg={4}ms" -f $p, $score, $yt.code, $dc.code, $avg)
        }
        else {
            $results += [pscustomobject]@{ preset = $p; score = 0; yt = '0'; dc = '0'; avgMs = 99999 }
        }
        [void](Save-BenchResult $results $false)
    }
    Write-Progress -Activity 'Подбор пресета zapret' -Completed
    Stop-Zapret
    $best = Save-BenchResult $results $true
    return [pscustomobject]@{ all = $results; best = $best }
}
function Stop-ZapretDaemon {
    Stop-Zapret
    Remove-Item (Join-Path $script:ZAppDir 'zapret-winws.pid') -Force -ErrorAction SilentlyContinue
    ZLog 'zapret daemon left idle (stop requested)'
}
