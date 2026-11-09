param([int]$Port = 18080)

$ErrorActionPreference = 'Stop'

$base = $PSScriptRoot
$log = Join-Path $base 'pac.log'

function Get-Condition([string[]]$domains) {
    $parts = @()
    foreach ($d in $domains) {
        $d = $d.Trim().TrimStart('.').ToLower()
        if (-not $d) { continue }
        $parts += ('dnsDomainIs(host,".' + $d + '")||host=="' + $d + '"')
    }
    return ($parts -join '||')
}

function Get-Pac {
    $cfg = $null
    $cfgPath = Join-Path $base 'config.json'
    if (Test-Path $cfgPath) {
        try { $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json } catch { }
    }

    $claude = @('claude.ai','claude.com','anthropic.com','claudeusercontent.com')
    $mode = 'zapret'
    $sites = @()
    if ($cfg) {
        if ($cfg.mode) { $mode = $cfg.mode }
        if ($cfg.sites) { $sites = @($cfg.sites) }
    }

    $cond = Get-Condition ($claude + $sites)

    if ($mode -eq 'vpn-all') {
        $media = @('youtube.com','googlevideo.com','ytimg.com','ggpht.com','youtu.be','youtube-nocookie.com','discord.com','discord.gg','discordapp.com','discordapp.net','discord.media')
        $cond = Get-Condition ($claude + $sites + $media)
    }

    return "function FindProxyForURL(url,host){ if($cond){ return `"PROXY 127.0.0.1:10809; SOCKS5 127.0.0.1:10808; DIRECT`"; } return `"DIRECT`"; }"
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
"pac tcp server on $Port $(Get-Date -Format o)" | Out-File -LiteralPath $log -Encoding UTF8

while ($true) {
    try {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 3000
        $reader = New-Object System.IO.StreamReader($stream)
        $requestLine = [string]$reader.ReadLine()
        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line -or $line -eq '') { break }
        }
        if ($requestLine -match '^GET /id') { $body = $base } else { $body = Get-Pac }
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($body)
        $header = "HTTP/1.1 200 OK`r`nContent-Type: application/x-ns-proxy-autoconfig`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
        $hb = [System.Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($hb, 0, $hb.Length)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $client.Close()
    }
    catch {
        "err: $($_.Exception.Message)" | Out-File -LiteralPath $log -Append -Encoding UTF8
    }
}
