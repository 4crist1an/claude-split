$ErrorActionPreference = 'Stop'

$appDir = $PSScriptRoot
. (Join-Path $appDir 'lib.ps1')

$lines = New-Object System.Collections.Generic.List[string]
$fail = 0
$warn = 0

function Add-Line([string]$status, [string]$text) {
    $script:lines.Add(('[{0}] {1}' -f $status, $text))
}

# 1. правила, блокирующие Claude (любые, независимо от названия)
$rules = @(Get-ClaudeBlockRules)
if ($rules.Count -eq 0) {
    Add-Line 'FAIL' 'Нет ни одного правила, блокирующего Claude — kill-switch выключен'
    $script:fail++
}
else {
    $tags = @($rules | ForEach-Object { ($_.DisplayName -split ' ')[0] } | Sort-Object -Unique)
    Add-Line 'OK' ("Блокирующих правил: " + $rules.Count + " (" + ($tags -join ', ') + ")")
}

# 2. актуальность пути к exe
$exes = @(Get-ClaudeExePaths)
if ($exes.Count -eq 0) {
    Add-Line 'WARN' 'Не удалось найти claude.exe (приложение не установлено?)'
    $script:warn++
}
else {
    Add-Line 'OK' ('Найден Claude: ' + $exes[0])
    if ($rules.Count -eq 0) {
        Add-Line 'FAIL' 'Правила не покрывают этот файл'
        $script:fail++
    }
}

# 3. активные соединения Claude
$pids = @((Get-Process claude -ErrorAction SilentlyContinue).Id)
if ($pids.Count -eq 0) {
    Add-Line 'INFO' 'Claude сейчас не запущен — активных соединений нет'
}
else {
    $conns = @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $pids -contains $_.OwningProcess -and $_.State -eq 'Established' })
    $direct = @($conns | Where-Object { $_.RemoteAddress -notin @('127.0.0.1', '::1', '0.0.0.0', '::') })
    if ($direct.Count -gt 0) {
        Add-Line 'FAIL' ("Есть прямые соединения Claude вне прокси: " + (($direct | Select-Object -ExpandProperty RemoteAddress -Unique) -join ', ') + ' — если Claude был запущен до включения защиты, закройте и откройте его: правила не рвут уже установленные соединения')
        $script:fail++
    }
    else {
        Add-Line 'OK' ("Соединений вне прокси нет (всего соединений: " + $conns.Count + ")")
    }
}

# 4. прокси
$ownXray = Test-OwnXray
$proxyOk = [bool](Get-NetTCPConnection -LocalPort 10809 -State Listen -ErrorAction SilentlyContinue)
if ($proxyOk -and $ownXray) { Add-Line 'OK' 'Локальный прокси 127.0.0.1:10809 слушает, xray этой копии запущен' }
elseif ($proxyOk) { Add-Line 'WARN' 'Порт 10809 слушает другая копия приложения'; $script:warn++ }
else { Add-Line 'WARN' 'Прокси не поднят — при включённом kill-switch Claude будет без интернета'; $script:warn++ }

# 0. сам Windows Firewall
$profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
$off = @($profiles | Where-Object { -not $_.Enabled })
if ($off.Count -gt 0) {
    Add-Line 'FAIL' ('Windows Firewall выключен для профилей: ' + (($off | Select-Object -ExpandProperty Name) -join ', ') + ' — правила не применяются')
    $script:fail++
} else {
    Add-Line 'OK' 'Windows Firewall включён (все профили)'
}

$verdict = if ($fail -gt 0) { 'Защита НЕ работает' } elseif ($warn -gt 0) { 'Работает, но есть замечания' } else { 'Защита работает' }
$lines.Insert(0, ('ВЕРДИКТ: ' + $verdict))
$lines.Insert(1, '')
$lines -join "`r`n"
