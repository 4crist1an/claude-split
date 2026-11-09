param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$Preset = ''
)

$ErrorActionPreference = 'Stop'
$appDir = $PSScriptRoot

. (Join-Path $appDir 'lib.ps1')
. (Join-Path $appDir 'zapret-lib.ps1')

$result = [ordered]@{ action = $Action; ok = $false; running = $false; error = '' }

try {
    if ($Action -eq 'start') {
        if (-not $Preset) { $Preset = 'general (ALT).bat' }
        $result.ok = [bool](Start-ZapretPreset $Preset)
        if ($script:ZUsedFallback) {
            $cfg = Get-Config
            $cfg | Add-Member -NotePropertyName zapretPreset -NotePropertyValue $script:ZUsedFallback -Force
            Save-Config $cfg
        }
    }
    elseif ($Action -eq 'stop') {
        Stop-Zapret
        $result.ok = -not [bool](Get-ZapretStatus).running
    }
    elseif ($Action -eq 'toggle') {
        if ((Get-ZapretStatus).running) { Stop-Zapret; $result.ok = -not [bool](Get-ZapretStatus).running }
        else { $result.ok = [bool](Start-ZapretPreset $Preset) }
    }
}
catch {
    $result.error = $_.Exception.Message
}

$st = Get-ZapretStatus
$result.running = [bool]$st.running
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appDir 'zapret-action.json') -Encoding UTF8
