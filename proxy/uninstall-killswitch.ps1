#Requires -Version 5.1
<#
  Removes firewall rules created by install-killswitch.ps1.
  Run as Administrator.
#>
[CmdletBinding()]
param(
    [string]$Tag = 'ClaudeSplitGuard'
)

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: run as Administrator.' -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot 'lib.ps1')
$rules = @(Get-NetFirewallRule -DisplayName "$Tag*" -ErrorAction SilentlyContinue)
$rules += @(Get-ClaudeBlockRules)
$rules = @($rules | Sort-Object Name -Unique)
if ($rules.Count -eq 0) {
    Write-Host "Nothing to remove (no rules with prefix '$Tag')."
    exit 0
}

$rules | ForEach-Object { Write-Host "   - $($_.DisplayName)" }
$rules | Remove-NetFirewallRule
Write-Host "Removed $($rules.Count) rule(s)." -ForegroundColor Green
