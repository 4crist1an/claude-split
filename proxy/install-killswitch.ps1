#Requires -Version 5.1
<#
  Kill-switch for Claude: Claude may reach the internet only through the local
  proxy (127.0.0.1). All direct connections from Claude executables are blocked.

  Windows Firewall does not filter loopback traffic, so the local proxy keeps
  working while any direct (non-proxy) connection from Claude is dropped.
  Run as Administrator. Safe to re-run.
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

Write-Host '== 1/3 Locating Claude executables' -ForegroundColor Cyan

$roots = New-Object System.Collections.Generic.List[string]
$packageFamily = $null
try {
    foreach ($p in (Get-AppxPackage -Name 'Claude*' -ErrorAction Stop)) {
        if ($p.InstallLocation) { $roots.Add($p.InstallLocation) }
        if ($p.PackageFamilyName) { $packageFamily = $p.PackageFamilyName }
    }
} catch { }

if ($roots.Count -eq 0) {
    foreach ($d in (Get-ChildItem 'C:\Program Files\WindowsApps' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
        $roots.Add($d.FullName)
        $fam = $d.Name -replace '^(Claude)_[^_]+_[^_]+__([a-z0-9]+)$', '$1_$2'
        if ($fam -ne $d.Name) { $packageFamily = $fam }
    }
}

$exes = New-Object System.Collections.Generic.List[string]
foreach ($r in $roots) {
    Get-ChildItem -LiteralPath $r -Filter '*.exe' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'claude|anthropic' } |
        ForEach-Object { $exes.Add($_.FullName) }
}
foreach ($p in @("$env:LOCALAPPDATA\AnthropicClaude", "$env:LOCALAPPDATA\Programs\Claude")) {
    if (Test-Path -LiteralPath $p) {
        Get-ChildItem -LiteralPath $p -Filter '*.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'claude' } |
            ForEach-Object { $exes.Add($_.FullName) }
    }
}
$exes = @($exes | Sort-Object -Unique)
if ($exes.Count -eq 0) {
    Write-Host 'ERROR: Claude executables not found. Start Claude once, then re-run.' -ForegroundColor Red
    exit 1
}
$exes | ForEach-Object { Write-Host "   $_" }

Write-Host '== 2/3 Recreating firewall rules' -ForegroundColor Cyan
Get-NetFirewallRule -DisplayName "$Tag*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

# убираем ЛЮБЫЕ прежние правила, блокирующие эти же файлы (в т.ч. от старых версий)
$removedOld = 0
foreach ($r in @(Get-NetFirewallRule -Direction Outbound -Action Block -ErrorAction SilentlyContinue)) {
    $app = $r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    if (-not $app) { continue }
    $prog = [string]$app.Program
    if ($prog -and ($exes -contains $prog)) {
        Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
        $removedOld++
    }
}
if ($removedOld -gt 0) { Write-Host "   (removed $removedOld old rules)" }
Get-NetFirewallRule -DisplayName "$Tag*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

$i = 0
foreach ($exe in $exes) {
    $i++
    New-NetFirewallRule -DisplayName "$Tag block $i" `
        -Description "Claude: no direct internet, proxy only ($exe)" `
        -Direction Outbound -Action Block -Program $exe -Profile Any -Enabled True | Out-Null
    Write-Host "   + block: $exe"
}

if ($packageFamily) {
    try {
        New-NetFirewallRule -DisplayName "$Tag block package" `
            -Description 'Claude package: no direct internet' `
            -Direction Outbound -Action Block -Package $packageFamily -Profile Any -Enabled True | Out-Null
        Write-Host "   + block package: $packageFamily"
    } catch {
        Write-Host "   (package rule skipped: $($_.Exception.Message))"
    }
}

Write-Host '== 3/3 Done' -ForegroundColor Green
Get-NetFirewallRule -DisplayName "$Tag*" | Select-Object DisplayName, Enabled, Direction, Action | Format-Table -AutoSize
Write-Host 'Check it in the app: tab "Claude" -> "Проверить защиту".'
Write-Host 'Rollback: uninstall-killswitch.ps1'
