$ErrorActionPreference = 'Stop'

$appDir = $PSScriptRoot
$root = Split-Path $PSScriptRoot -Parent
$zdir = Join-Path $root 'zapret'
$resultFile = Join-Path $appDir 'update-result.json'

function Log([string]$m) {
    ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -LiteralPath (Join-Path $appDir 'app.log') -Append -Encoding UTF8
}

function Save-Result($status, $tag, $message) {
    [ordered]@{ status = $status; tag = $tag; message = $message; at = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding UTF8
}

try {
    $rel = & curl.exe -s --max-time 25 -H 'User-Agent: claude-split' 'https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/latest' | ConvertFrom-Json
    $tag = $rel.tag_name
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'в релизе нет zip' }

    $current = ''
    $verFile = Join-Path $zdir 'version.json'
    if (Test-Path $verFile) { try { $current = (Get-Content $verFile -Raw | ConvertFrom-Json).tag } catch { } }

    if ($current -eq $tag) {
        Save-Result 'uptodate' $tag ('Установлена актуальная версия ' + $tag)
        Log ('zapret check: уже актуально ' + $tag)
        exit 0
    }

    $tmp = Join-Path $env:TEMP ('zapret_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'zapret.zip'
    & curl.exe -sL --max-time 180 -H 'User-Agent: claude-split' -o $zip $asset.browser_download_url
    if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) { throw 'скачивание не удалось' }

    $ex = Join-Path $tmp 'x'
    Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force
    $src = $ex
    $dirs = @(Get-ChildItem -LiteralPath $ex -Directory)
    if ($dirs.Count -eq 1 -and -not (Get-ChildItem -LiteralPath $ex -File)) { $src = $dirs[0].FullName }

    if (Test-Path $zdir) { Remove-Item -LiteralPath $zdir -Recurse -Force }
    New-Item -ItemType Directory -Path $zdir -Force | Out-Null
    Copy-Item -Path (Join-Path $src '*') -Destination $zdir -Recurse -Force

    # домены Claude исключаем из обработки zapret, чтобы он не трогал трафик внутри туннеля
    $lists = Join-Path $zdir 'lists'
    if (Test-Path $lists) {
        $listEx = Join-Path $lists 'list-exclude-user.txt'
        $domains = @('claude.ai', 'claude.com', 'anthropic.com', 'claudeusercontent.com')
        $have = @(Get-Content $listEx -ErrorAction SilentlyContinue)
        foreach ($d in $domains) {
            if ($have -notcontains $d) { Add-Content -LiteralPath $listEx -Value $d -Encoding Ascii }
        }
        # при необходимости добавьте сюда домены/IP своего VPN-сервера,
        # чтобы zapret не трогал зашифрованное соединение туннеля.
    }

    [ordered]@{ tag = $tag; updatedAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $verFile -Encoding UTF8
    Log ('zapret updated -> ' + $tag)
    Save-Result 'updated' $tag ('Обновлено до ' + $tag)
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Save-Result 'error' '' $_.Exception.Message
    Log ('update error: ' + $_.Exception.Message)
}
