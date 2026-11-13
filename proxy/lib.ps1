$ErrorActionPreference = 'Stop'

$script:AppDir = $PSScriptRoot
$script:Root = Split-Path $PSScriptRoot -Parent
$script:XrayExe = Join-Path $script:Root 'bin\xray.exe'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-Path([string]$name) { Join-Path $script:AppDir $name }

function Read-Json([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
}

function Write-Json([string]$path, $obj) {
    [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $obj -Depth 12), $script:Utf8)
}

function Get-Config {
    $c = Read-Json (Get-Path 'config.json')
    if (-not $c) { $c = [pscustomobject]@{ subscriptions = @(); manual = @(); activeSub = ''; selectedNode = ''; mode = 'zapret' } }
    if (-not $c.PSObject.Properties['subscriptions']) { $c | Add-Member -NotePropertyName subscriptions -NotePropertyValue @() }
    if (-not $c.PSObject.Properties['manual']) { $c | Add-Member -NotePropertyName manual -NotePropertyValue @() }
    return $c
}

function Save-Config($c) { Write-Json (Get-Path 'config.json') $c }

function ConvertFrom-SubBase64([string]$text) {
    $b64 = ($text.Trim() -replace '\s', '').Replace('-', '+').Replace('_', '/')
    switch ($b64.Length % 4) { 2 { $b64 += '==' } 3 { $b64 += '=' } }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

function Parse-VlessNodes([string]$decoded, [string]$subName) {
    $nodes = @()
    foreach ($line in ($decoded -split "`n")) {
        if ($line -notmatch '^vless://') { continue }
        try { $u = [uri]$line } catch { continue }
        $name = [uri]::UnescapeDataString($u.Fragment.TrimStart('#')).Trim()
        if ($name -match 'deprecated|t\.me|shuka\.site|Приложение|Перейдите') { continue }
        $q = @{}
        foreach ($pair in ($u.Query.TrimStart('?') -split '&')) {
            $kv = $pair -split '=', 2
            if ($kv.Count -eq 2) { $q[$kv[0]] = [uri]::UnescapeDataString($kv[1]) }
        }
        if ($q['security'] -eq 'reality' -and -not $q['pbk']) { continue }
        $nodes += [pscustomobject]@{
            name = $name; host = $u.Host; port = [int]$u.Port; id = $u.UserInfo
            flow = $q['flow']; sni = $q['sni']; pbk = $q['pbk']; sid = $q['sid']; fp = $q['fp']
            type = $q['type']; security = $q['security']; path = $q['path']; hostHeader = $q['host']; alpn = $q['alpn']
            sub = $subName
        }
    }
    return $nodes
}

function Update-Subscriptions {
    $cfg = Get-Config
    $all = @()
    foreach ($s in $cfg.subscriptions) {
        try {
            $tmp = Join-Path $env:TEMP ('sub_' + [guid]::NewGuid().ToString('N') + '.txt')
            & curl.exe -s --max-time 25 -A 'v2rayN/6.31' -o $tmp $s.url
            if (-not (Test-Path $tmp)) { continue }
            $raw = Get-Content -LiteralPath $tmp -Raw
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            $all += Parse-VlessNodes (ConvertFrom-SubBase64 $raw) $s.name
        }
        catch { }
    }
    $uniq = @{}
    foreach ($n in $all) { $uniq["$($n.name)|$($n.host):$($n.port)"] = $n }
    $list = @($uniq.Values | Sort-Object name)
    Write-Json (Get-Path 'nodes.json') $list
    return $list
}

function Get-Nodes {
    $n = Read-Json (Get-Path 'nodes.json')
    if (-not $n) { return @() }
    return @($n)
}

function Get-ActiveSub {
    $c = Get-Config
    if ($c.activeSub) { return $c.activeSub }
    if (@($c.subscriptions).Count -gt 0) { return $c.subscriptions[0].name }
    return ''
}

function Get-AllNodes {
    $c = Get-Config
    $list = @()
    if ($c.manual) { $list += @($c.manual) }
    $sub = Get-ActiveSub
    $all = @(Get-Nodes)
    if ($sub) { $list += @($all | Where-Object { $_.sub -eq $sub }) }
    return $list
}

function New-ManualNode([string]$type, [string]$text) {
    $text = $text.Trim()
    if ($type -eq 'vless') {
        $n = @(Parse-VlessNodes $text 'вручную')
        if ($n.Count -eq 0) { throw 'не удалось разобрать VLESS-ссылку' }
        $node = $n[0]
        $node | Add-Member -NotePropertyName kind -NotePropertyValue 'vless' -Force
        return $node
    }
    if ($text -notmatch '^[a-zA-Z0-9]+://') {
        if ($type -eq 'socks') { throw 'нужен формат: socks5://логин:пароль@хост:порт' }
        else { throw 'нужен формат: http://логин:пароль@хост:порт' }
    }
    try { $u = [uri]$text } catch { throw 'не удалось разобрать ссылку — проверьте формат' }
    if (-not $u.Host) { throw 'в ссылке нет адреса сервера' }
    if ($u.Port -le 0) { throw 'в ссылке нет порта' }
    $kind = if ($type -eq 'socks') { 'socks' } else { 'http' }
    $user = ''
    $pass = ''
    if ($u.UserInfo) {
        $parts = $u.UserInfo -split ':', 2
        $user = [uri]::UnescapeDataString($parts[0])
        if ($parts.Count -gt 1) { $pass = [uri]::UnescapeDataString($parts[1]) }
    }
    $name = if ($u.Fragment) { [uri]::UnescapeDataString($u.Fragment.TrimStart('#')) } else { "$($u.Host):$($u.Port)" }
    $node = [pscustomobject]@{
        name = $name; host = $u.Host; port = [int]$u.Port; kind = $kind
        user = $user; pass = $pass; sub = 'вручную'
        id = ''; flow = ''; sni = ''; pbk = ''; sid = ''; fp = ''
    }
    return $node
}
function Build-XrayConfig($node) {
    $kind = if ($node.PSObject.Properties['kind'] -and $node.kind) { $node.kind } else { 'vless' }
    $outbound = $null
    if ($kind -eq 'vless') {
        $transport = if ($node.PSObject.Properties['type'] -and $node.type) { $node.type } else { 'tcp' }
        $sec = if ($node.PSObject.Properties['security'] -and $node.security) { $node.security } else { 'reality' }
        $net = switch ($transport) { 'xhttp' { 'splithttp' } 'ws' { 'ws' } 'grpc' { 'grpc' } default { 'tcp' } }
        $stream = @{ network = $net; security = $sec }
        if ($sec -eq 'reality') {
            $stream['realitySettings'] = @{ serverName = $node.sni; fingerprint = $node.fp; publicKey = $node.pbk; shortId = $node.sid }
        }
        elseif ($sec -eq 'tls') {
            $tls = @{ serverName = $node.sni; fingerprint = $node.fp }
            if ($node.alpn) { $tls['alpn'] = @($node.alpn) }
            $stream['tlsSettings'] = $tls
        }
        if ($net -eq 'ws') {
            $stream['wsSettings'] = @{ path = $node.path; headers = @{ Host = $node.hostHeader } }
        }
        elseif ($net -eq 'splithttp') {
            $stream['splithttpSettings'] = @{ path = $node.path; host = $node.hostHeader }
        }
        $outbound = @{ tag = 'proxy'; protocol = 'vless'
            settings = @{ vnext = @(@{ address = $node.host; port = [int]$node.port; users = @(@{ id = $node.id; encryption = 'none'; flow = $node.flow }) }) }
            streamSettings = $stream }
    }
    else {
        $userObj = $null
        if ($node.user) { $userObj = @(@{ user = $node.user; pass = $node.pass }) }
        $server = @{ address = $node.host; port = [int]$node.port }
        if ($userObj) { $server['users'] = $userObj }
        $outbound = @{ tag = 'proxy'; protocol = $kind; settings = @{ servers = @($server) } }
    }
    $cfg = [ordered]@{
        log = @{ loglevel = 'warning' }
        inbounds = @(
            @{ tag = 'socks'; port = 10808; listen = '127.0.0.1'; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $true } },
            @{ tag = 'http'; port = 10809; listen = '127.0.0.1'; protocol = 'http'; settings = @{} }
        )
        outbounds = @($outbound)
    }
    Write-Json (Get-Path 'xray.json') $cfg
}

function Write-Log([string]$msg) {
    ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg) | Out-File -LiteralPath (Get-Path 'app.log') -Append -Encoding UTF8
}

function Stop-Xray {
    $p = Get-Process xray -ErrorAction SilentlyContinue
    if ($p) { $p | Stop-Process -Force; Start-Sleep -Milliseconds 400 }
    Write-Log 'xray stopped'
}

function Start-XrayNode($node) {
    Stop-Xray
    Build-XrayConfig $node
    Start-BackgroundProcess -Exe $script:XrayExe -Arguments ('run -c "' + (Get-Path 'xray.json') + '"')
    Start-Sleep -Seconds 2
    Write-Log ('xray started -> ' + $node.name + ' ' + $node.host + ':' + $node.port)
}

function Test-Claude {
    $tr = & curl.exe -s --max-time 10 --proxy 'http://127.0.0.1:10809' 'https://claude.ai/cdn-cgi/trace' 2>$null
    $ip = ($tr | Select-String '^ip=') -replace '^ip=', ''
    $loc = ($tr | Select-String '^loc=') -replace '^loc=', ''
    if ($ip) { return [pscustomobject]@{ ok = $true; ip = $ip.Trim(); loc = $loc.Trim() } }
    return [pscustomobject]@{ ok = $false; ip = ''; loc = '' }
}

function Test-Node($node, [int]$TimeoutSec = 8) {
    Start-XrayNode $node
    $tr = & curl.exe -s --max-time $TimeoutSec --proxy 'http://127.0.0.1:10809' 'https://claude.ai/cdn-cgi/trace' 2>$null
    $ip = ($tr | Select-String '^ip=') -replace '^ip=', ''
    return [bool]$ip
}

function Set-SystemPac {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $v = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Set-ItemProperty -Path $key -Name 'ProxyEnable' -Value 0 -Type DWord
    Set-ItemProperty -Path $key -Name 'AutoConfigURL' -Value ("http://127.0.0.1:18080/proxy.pac?v=" + $v)
    try {
        Add-Type -Namespace WV -Name Inet -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(System.IntPtr hInternet, int dwOption, System.IntPtr lpBuffer, int dwBufferLength);
"@ -ErrorAction SilentlyContinue
        [WV.Inet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [WV.Inet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    } catch { }
    Write-Log ('pac refreshed v=' + $v)
}

function Clear-SystemPac {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    Remove-ItemProperty -Path $key -Name 'AutoConfigURL' -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $key -Name 'ProxyEnable' -Value 0 -Type DWord
}

function Ensure-PacServer {
    $ok = [bool](Get-NetTCPConnection -LocalPort 18080 -State Listen -ErrorAction SilentlyContinue)
    if (-not $ok) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Get-Path 'pac.ps1')) -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }
}

function Get-Mode { $cfg = Get-Config; if ($cfg.mode) { return $cfg.mode } return 'zapret' }
function Set-Mode([string]$m) { $cfg = Get-Config; $cfg.mode = $m; Save-Config $cfg; [System.IO.File]::WriteAllText((Get-Path 'mode.txt'), $m, $script:Utf8); Set-SystemPac }
function Test-TcpPing([string]$hostName, [int]$port, [int]$timeoutMs = 2000) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $task = $client.ConnectAsync($hostName, $port)
        if (-not $task.Wait($timeoutMs)) { return -1 }
        $sw.Stop()
        if ($client.Connected) { return [int]$sw.ElapsedMilliseconds }
        return -1
    }
    catch { return -1 }
    finally { try { $client.Close() } catch { } }
}
function Test-OwnXray {
    $want = Join-Path $script:Root 'bin\xray.exe'
    foreach ($p in (Get-Process xray -ErrorAction SilentlyContinue)) {
        try { if ($p.Path -and ($p.Path -eq $want)) { return $true } } catch { }
    }
    return $false
}

function Get-PacOwner {
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:18080/id' -UseBasicParsing -TimeoutSec 3
        $txt = if ($r.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
        $first = ($txt -split "`r?`n")[0].Trim()
        if ($first -match '^[A-Za-z]:\\') { return $first }
        return 'другая копия'
    } catch { return '' }
}
function Get-ClaudeExePaths {
    $paths = @()
    try {
        foreach ($p in (Get-AppxPackage -Name 'Claude*' -ErrorAction SilentlyContinue)) {
            if ($p.InstallLocation) {
                $cand = Join-Path $p.InstallLocation 'app\claude.exe'
                if (Test-Path $cand) { $paths += $cand }
                Get-ChildItem -LiteralPath $p.InstallLocation -Filter '*.exe' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match 'claude' } | ForEach-Object { $paths += $_.FullName }
            }
        }
    } catch { }
    foreach ($d in (Get-ChildItem 'C:\Program Files\WindowsApps' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
        $cand = Join-Path $d.FullName 'app\claude.exe'
        if (Test-Path $cand) { $paths += $cand }
    }
    # реально запущенные процессы Claude (на случай отката версии — папка другая)
    foreach ($proc in (Get-Process claude -ErrorAction SilentlyContinue)) {
        try { if ($proc.Path) { $paths += $proc.Path } } catch { }
    }
    foreach ($p in @("$env:LOCALAPPDATA\AnthropicClaude", "$env:LOCALAPPDATA\Programs\Claude")) {
        if (Test-Path $p) {
            Get-ChildItem -LiteralPath $p -Filter '*.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'claude' } | ForEach-Object { $paths += $_.FullName }
        }
    }
    return @($paths | Sort-Object -Unique)
}

# Возвращает ВСЕ правила, блокирующие Claude, независимо от их названия
function Get-ClaudeBlockRules {
    $exes = @(Get-ClaudeExePaths)
    if ($exes.Count -eq 0) { return @() }
    $result = @()
    $rules = @(Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue)
    foreach ($r in $rules) {
        if ("$($r.Enabled)" -ne 'True') { continue }
        $app = $r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if (-not $app) { continue }
        $prog = [string]$app.Program
        if (-not $prog -or $prog -eq 'Any') { continue }
        foreach ($e in $exes) { if ($prog -eq $e) { $result += $r; break } }
    }
    return $result
}
function Stop-PacServer {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$($script:AppDir)*pac.ps1*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
}
# Запуск без ShellExecute: иначе PowerShell 5.1 дергает ассоциации/SmartScreen,
# и xray падает с "operation was canceled by the user".
function Start-BackgroundProcess([string]$Exe, [string]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    [System.Diagnostics.Process]::Start($psi) | Out-Null
}
# Проверяет, покрывают ли текущие правила все актуальные exe Claude.
# Нужно после обновления/отката Claude: путь к файлу меняется вместе с версией.
function Sync-KillSwitch {
    $exes = @(Get-ClaudeExePaths)
    if ($exes.Count -eq 0) { return $false }
    $covered = @(Get-ClaudeBlockRules | ForEach-Object {
        $a = $_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if ($a) { [string]$a.Program }
    })
    foreach ($e in $exes) {
        if ($covered -notcontains $e) { return $false }
    }
    return $true
}