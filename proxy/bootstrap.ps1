$ErrorActionPreference = 'Stop'

$appDir = $PSScriptRoot
$root = Split-Path $appDir -Parent
$log = Join-Path $appDir 'app.log'

function Log([string]$m) {
    ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -LiteralPath $log -Append -Encoding UTF8
}

# --- xray (нужен для туннеля)
$xrayExe = Join-Path $root 'bin\xray.exe'
if (-not (Test-Path $xrayExe)) {
    Log 'bootstrap: скачиваю xray…'
    Write-Host 'Скачиваю Xray-core…'
    try {
        $rel = & curl.exe -s --max-time 30 -H 'User-Agent: claude-split' 'https://api.github.com/repos/XTLS/Xray-core/releases/latest' | ConvertFrom-Json
        $asset = $rel.assets | Where-Object { $_.name -like 'Xray-windows-64.zip' } | Select-Object -First 1
        if (-not $asset) { throw 'asset Xray-windows-64.zip не найден' }
        $tmp = Join-Path $env:TEMP ('xray_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $zip = Join-Path $tmp 'xray.zip'
        & curl.exe -sL --max-time 180 -o $zip $asset.browser_download_url
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $found = Get-ChildItem -LiteralPath $tmp -Filter 'xray.exe' -Recurse | Select-Object -First 1
        if (-not $found) { throw 'xray.exe не найден в архиве' }
        New-Item -ItemType Directory -Path (Join-Path $root 'bin') -Force | Out-Null
        Copy-Item $found.FullName $xrayExe -Force
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Log 'bootstrap: xray установлен'
    }
    catch {
        Log ('bootstrap: xray не скачан — ' + $_.Exception.Message)
        Write-Host ('Не удалось скачать xray: ' + $_.Exception.Message) -ForegroundColor Red
    }
}

# --- zapret (для YouTube/Discord напрямую)
$zdir = Join-Path $root 'zapret'
if (-not (Test-Path (Join-Path $zdir 'bin\winws.exe'))) {
    Log 'bootstrap: скачиваю zapret…'
    Write-Host 'Скачиваю zapret…'
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $appDir 'update-zapret.ps1') | Out-Null
        Log 'bootstrap: zapret установлен'
    }
    catch {
        Log ('bootstrap: zapret не скачан — ' + $_.Exception.Message)
    }
}
