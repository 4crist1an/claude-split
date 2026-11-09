$ErrorActionPreference = 'Stop'

$base = $PSScriptRoot
. (Join-Path $base 'zapret-lib.ps1')

$res = Test-ZapretPresets
$out = [ordered]@{
    at   = (Get-Date).ToString('o')
    best = if ($res.best) { $res.best.preset } else { '' }
    data = $res.all
}
$out | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $base 'zapret-bench.json') -Encoding UTF8

if ($res.best) {
    Start-ZapretPreset $res.best.preset | Out-Null
    $cfgPath = Join-Path $base 'config.json'
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $cfg | Add-Member -NotePropertyName zapretPreset -NotePropertyValue $res.best.preset -Force
    [System.IO.File]::WriteAllText($cfgPath, (ConvertTo-Json -InputObject $cfg -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    ZLog ('best preset: ' + $res.best.preset + ' (score ' + $res.best.score + ', avg ' + $res.best.avgMs + 'ms)')
}
else {
    ZLog 'preset test: ни один пресет не заработал'
}
