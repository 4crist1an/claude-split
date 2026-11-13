param([string]$StartTab = '', [switch]$Minimized)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# прячем консоль, если процесс случайно запущен с ней
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHide {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@
    $ch = [ConsoleHide]::GetConsoleWindow()
    if ($ch -ne [IntPtr]::Zero) { [ConsoleHide]::ShowWindow($ch, 0) | Out-Null }
} catch { }

# глобальный перехват: не показываем стандартный .NET-диалог
try {
    $script:uiExceptionHandler = {
        param($s, $e)
        $msg = $e.Exception.Message
        try { ('{0}  UI exception: {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg) | Out-File -LiteralPath (Join-Path $PSScriptRoot 'app.log') -Append -Encoding UTF8 } catch { }
        try {
            if ($msg -match 'canceled by the user|cancelled by the user|отменено пользователем') {
                [void][System.Windows.Forms.MessageBox]::Show("Действие отменено: не подтверждены права администратора.`n`nБез них нельзя запустить или остановить zapret и менять правила фаервола.", 'Claude VPN', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            else {
                [void][System.Windows.Forms.MessageBox]::Show("Ошибка: $msg`n`nПодробности — в «Логи / Терминал».", 'Claude VPN', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        } catch { }
    }.GetNewClosure()
    [System.Windows.Forms.Application]::add_ThreadException([System.Threading.ThreadExceptionEventHandler]$script:uiExceptionHandler)
} catch { }

$script:singleMutex = New-Object System.Threading.Mutex($false, 'Global\ClaudeVPN_SingleInstance')
if (-not $script:singleMutex.WaitOne(0)) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ExistingWindow {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
    $h = [ExistingWindow]::FindWindow($null, 'Claude VPN')
    if ($h -ne [IntPtr]::Zero) {
        [ExistingWindow]::ShowWindow($h, 9) | Out-Null
        [ExistingWindow]::SetForegroundWindow($h) | Out-Null
    }
    exit
}
$appDir = $PSScriptRoot
. (Join-Path $appDir 'lib.ps1')
. (Join-Path $appDir 'zapret-lib.ps1')

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Claude VPN'
$form.Size = New-Object System.Drawing.Size(640, 820)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 32)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(8, 8)
$tabs.Size = New-Object System.Drawing.Size(608, 760)
$form.Controls.Add($tabs)

$pageVpn = New-Object System.Windows.Forms.TabPage
$pageVpn.Text = 'VPN'
$pageVpn.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 32)
$pageVpn.ForeColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($pageVpn)

$pageClaude = New-Object System.Windows.Forms.TabPage
$pageClaude.Text = 'Claude'
$pageClaude.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 32)
$pageClaude.ForeColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($pageClaude)

$pageSet = New-Object System.Windows.Forms.TabPage
$pageSet.Text = 'Настройки'
$pageSet.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 32)
$pageSet.ForeColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($pageSet)

function New-Label($parent, $text, $x, $y, $w, $size = 9, $color = $null, $h = 20) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $size)
    if ($color) { $l.ForeColor = $color }
    $parent.Controls.Add($l)
    return $l
}

function New-Button($parent, $text, $x, $y, $w, $h = 28, $accent = $false) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.BackColor = if ($accent) { [System.Drawing.Color]::FromArgb(30, 110, 160) } else { [System.Drawing.Color]::FromArgb(40, 44, 54) }
    $b.ForeColor = [System.Drawing.Color]::White
    $parent.Controls.Add($b)
    return $b
}

function New-Text($parent, $x, $y, $w, $h = 24, $multi = $false) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, $h)
    $t.Multiline = $multi
    if ($multi) { $t.ScrollBars = 'Vertical' }
    $t.BackColor = [System.Drawing.Color]::FromArgb(34, 37, 45)
    $t.ForeColor = [System.Drawing.Color]::White
    $parent.Controls.Add($t)
    return $t
}

# ---------------- VPN page ----------------
$title = New-Label $pageVpn 'Claude VPN' 12 8 300 15 ([System.Drawing.Color]::FromArgb(90, 200, 250))
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)

[void](New-Label $pageVpn 'Подписки' 12 42 200 9 ([System.Drawing.Color]::FromArgb(160, 170, 190)))

$cmbSub = New-Object System.Windows.Forms.ComboBox
$cmbSub.Location = New-Object System.Drawing.Point(12, 62)
$cmbSub.Size = New-Object System.Drawing.Size(240, 24)
$cmbSub.DropDownStyle = 'DropDownList'
$pageVpn.Controls.Add($cmbSub)

$btnRefresh = New-Button $pageVpn 'Обновить' 256 60 100
$btnDel = New-Button $pageVpn 'Удалить' 362 60 90
$btnAdd = New-Button $pageVpn 'Добавить' 430 92 138

$cmbAddType = New-Object System.Windows.Forms.ComboBox
$cmbAddType.Location = New-Object System.Drawing.Point(12, 94)
$cmbAddType.Size = New-Object System.Drawing.Size(110, 24)
$cmbAddType.DropDownStyle = 'DropDownList'
foreach ($it in @('Подписка','VLESS','SOCKS5','HTTP')) { [void]$cmbAddType.Items.Add($it) }
$cmbAddType.SelectedIndex = 0
$pageVpn.Controls.Add($cmbAddType)
$txtSub = New-Text $pageVpn 126 94 300
$lblSubHint = New-Label $pageVpn 'выбери тип, вставь ссылку и нажми «Добавить»' 12 120 540 8 ([System.Drawing.Color]::FromArgb(140, 150, 170))

[void](New-Label $pageVpn 'Сервер   (• — вручную, удаляются кнопкой «Удалить»)' 12 146 260 9 ([System.Drawing.Color]::FromArgb(160, 170, 190)))

$cmbNode = New-Object System.Windows.Forms.ComboBox
$cmbNode.Location = New-Object System.Drawing.Point(12, 166)
$cmbNode.Size = New-Object System.Drawing.Size(230, 24)
$cmbNode.DropDownStyle = 'DropDownList'
$pageVpn.Controls.Add($cmbNode)

$script:skipNodeSel = $false
$script:lastNodeIdx = -1
$script:nodeMap = New-Object System.Collections.ArrayList

$cmbNode.Add_SelectedIndexChanged({
    if ($script:skipNodeSel) { return }
    $i = $cmbNode.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:nodeMap.Count -or -not $script:nodeMap[$i]) {
        $script:skipNodeSel = $true
        if ($script:lastNodeIdx -ge 0 -and $script:lastNodeIdx -lt $cmbNode.Items.Count) { $cmbNode.SelectedIndex = $script:lastNodeIdx }
        $script:skipNodeSel = $false
        return
    }
    $script:lastNodeIdx = $i
})

$nodeMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miDelNode = New-Object System.Windows.Forms.ToolStripMenuItem('Удалить сервер (вручную)')
[void]$nodeMenu.Items.Add($miDelNode)
$cmbNode.ContextMenuStrip = $nodeMenu
$miDelNode.Add_Click({ Remove-SelectedNode })

$btnConnect = New-Button $pageVpn 'Подключить' 246 164 118 28 $true
$btnTestAll = New-Button $pageVpn 'Пинг' 368 164 92
$btnDelNode = New-Button $pageVpn 'Удалить' 464 164 104
$btnDelNode.Add_Click({ Remove-SelectedNode })
$lblClaude = New-Label $pageVpn 'Claude: —' 12 200 560 10
$lblYt = New-Label $pageVpn 'YouTube: —' 12 224 560 9
$lblDc = New-Label $pageVpn 'Discord: —' 12 246 560 9
$lblInfo = New-Label $pageVpn 'Готово' 12 270 560 9 ([System.Drawing.Color]::FromArgb(150, 160, 180))

[void](New-Label $pageVpn 'Сайты через VPN (по одному в строке; пусто = только Claude)' 12 296 560 9 ([System.Drawing.Color]::FromArgb(160, 170, 190)))

$txtSites = New-Text $pageVpn 12 316 556 110 $true
$btnSaveSites = New-Button $pageVpn 'Сохранить сайты' 12 434 160
$lblSitesHint = New-Label $pageVpn 'сохраняется автоматически' 180 440 380 8 ([System.Drawing.Color]::FromArgb(140, 150, 170))

$btnCheck = New-Button $pageVpn 'Проверить связь' 12 472 178 30
$btnMode = New-Button $pageVpn 'YouTube: напрямую' 198 472 178 30
$btnStop = New-Button $pageVpn 'Остановить туннель' 384 472 184 30
$btnHide = New-Button $pageVpn 'Свернуть в трей' 12 510 178 30
$btnLogs = New-Button $pageVpn 'Логи / Терминал' 198 510 178 30

$lblZapret = New-Label $pageVpn 'проверяю…' 12 548 560 10

$cmbPreset = New-Object System.Windows.Forms.ComboBox
$cmbPreset.Location = New-Object System.Drawing.Point(12, 572)
$cmbPreset.Size = New-Object System.Drawing.Size(400, 24)
$cmbPreset.DropDownStyle = 'DropDownList'
$pageVpn.Controls.Add($cmbPreset)

$btnApplyPreset = New-Button $pageVpn 'Применить' 420 570 148

$btnZapUpd = New-Button $pageVpn 'Проверить обновление zapret' 12 608 270
$btnZapBench = New-Button $pageVpn 'Подобрать пресет' 290 608 278

# ---------------- Claude page ----------------
$ctitle = New-Label $pageClaude 'Claude' 12 10 300 14 ([System.Drawing.Color]::FromArgb(90, 200, 250))
$ctitle.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)

[void](New-Label $pageClaude 'Kill-switch: Claude работает только через VPN-прокси. Если прокси выключен — у Claude нет доступа в интернет и он не может «засветить» российский IP.' 12 44 556 9 ([System.Drawing.Color]::FromArgb(170, 180, 200)) 40)

$lblKill = New-Label $pageClaude 'проверяю…' 12 92 556 11 $null 26
$btnKill = New-Button $pageClaude 'Проверить' 12 140 240 34
$btnKillCheck = New-Button $pageClaude 'Проверить защиту' 264 140 240 34

[void](New-Label $pageClaude 'Как это работает: правила Windows Firewall блокируют claude.exe на всех физических адаптерах (Ethernet, Wi-Fi и т.п.). Разрешено только локальное соединение с прокси 127.0.0.1.' 12 186 556 8 ([System.Drawing.Color]::FromArgb(150, 160, 180)) 52)

[void](New-Label $pageClaude 'Правила:' 12 260 200 9 ([System.Drawing.Color]::FromArgb(160, 170, 190)))
$txtKillRules = New-Text $pageClaude 12 280 556 150 $true
$txtKillRules.ReadOnly = $true

# ---------------- Settings page ----------------
$st = New-Label $pageSet 'Настройки' 12 10 300 14 ([System.Drawing.Color]::FromArgb(90, 200, 250))
$st.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)

$chkAutostart = New-Object System.Windows.Forms.CheckBox
$chkAutostart.Text = 'Запускать при входе в Windows'
$chkAutostart.Location = New-Object System.Drawing.Point(12, 50)
$chkAutostart.Size = New-Object System.Drawing.Size(400, 24)
$chkAutostart.ForeColor = [System.Drawing.Color]::White
$pageSet.Controls.Add($chkAutostart)

$chkZapretAuto = New-Object System.Windows.Forms.CheckBox
$chkZapretAuto.Text = 'Запускать zapret вместе с приложением'
$chkZapretAuto.Location = New-Object System.Drawing.Point(12, 80)
$chkZapretAuto.Size = New-Object System.Drawing.Size(400, 24)
$chkZapretAuto.ForeColor = [System.Drawing.Color]::White
$pageSet.Controls.Add($chkZapretAuto)

$chkUpdateOnStart = New-Object System.Windows.Forms.CheckBox
$chkUpdateOnStart.Text = 'Проверять обновление zapret при старте'
$chkUpdateOnStart.Location = New-Object System.Drawing.Point(12, 110)
$chkUpdateOnStart.Size = New-Object System.Drawing.Size(400, 24)
$chkUpdateOnStart.ForeColor = [System.Drawing.Color]::White
$pageSet.Controls.Add($chkUpdateOnStart)

$btnSaveSettings = New-Button $pageSet 'Сохранить настройки' 12 150 200

$lblPaths = New-Label $pageSet '' 12 200 560 8 ([System.Drawing.Color]::FromArgb(150, 160, 180)) 300
$lblPaths.AutoSize = $false

$txtSettingsInfo = New-Text $pageSet 12 500 556 120 $true
$txtSettingsInfo.ReadOnly = $true
$txtSettingsInfo.Text = ''

# ================= логика =================
$script:nodes = @()
$script:loadingSites = $false
$script:loadingUi = $false
$script:benchProc = $null
$script:benchPrev = ''

function Refresh-Subs {
    $cfg = Get-Config
    $cmbSub.Items.Clear()
    foreach ($s in $cfg.subscriptions) { [void]$cmbSub.Items.Add($s.name) }
    if ($cmbSub.Items.Count -gt 0) {
        $act = Get-ActiveSub
        $idx = $cmbSub.Items.IndexOf($act)
        $cmbSub.SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
    }
}

function Refresh-Nodes([switch]$Reload) {
    if ($Reload) { $script:nodes = @(Update-Subscriptions); $script:nodes = @(Get-AllNodes) } else { $script:nodes = @(Get-AllNodes) }

    # чистим битые ручные записи (пустой хост/порт)
    $cfg0 = Get-Config
    $bad = @($cfg0.manual | Where-Object { -not $_.host -or [int]$_.port -le 0 })
    if ($bad.Count -gt 0) {
        $cfg0.manual = @($cfg0.manual | Where-Object { $_.host -and [int]$_.port -gt 0 })
        Save-Config $cfg0
        $script:nodes = @(Get-AllNodes)
    }

    $script:skipNodeSel = $true
    $cmbNode.Items.Clear()
    $script:nodeMap = New-Object System.Collections.ArrayList

    # группы: ручные по типу, затем подписки
    $groups = @()
    foreach ($kind in @('vless', 'socks', 'http')) {
        $arr = @($script:nodes | Where-Object { $_.sub -eq 'вручную' -and $_.kind -eq $kind })
        if ($arr.Count -gt 0) {
            $title = switch ($kind) { 'vless' { 'VLESS' } 'socks' { 'SOCKS5' } 'http' { 'HTTP' } }
            $groups += , @($title, $arr)
        }
    }
    foreach ($g in @($script:nodes | Where-Object { $_.sub -ne 'вручную' } | Group-Object sub)) {
        $groups += , @($g.Name, @($g.Group))
    }

    foreach ($grp in $groups) {
        [void]$cmbNode.Items.Add("── $($grp[0]) ──")
        [void]$script:nodeMap.Add($null)
        foreach ($n in $grp[1]) {
            $mark = if ($n.sub -eq 'вручную') { '• ' } else { '   ' }
            [void]$cmbNode.Items.Add("$mark$($n.name)  [$($n.host)]")
            [void]$script:nodeMap.Add($n)
        }
    }

    $cfg = Get-Config
    $idxSel = -1
    for ($i = 0; $i -lt $script:nodeMap.Count; $i++) {
        $n = $script:nodeMap[$i]
        if ($n -and $cfg.selectedNode -and ("$($n.host):$($n.port)" -eq $cfg.selectedNode)) { $idxSel = $i; break }
    }
    if ($idxSel -lt 0) {
        for ($i = 0; $i -lt $script:nodeMap.Count; $i++) { if ($script:nodeMap[$i]) { $idxSel = $i; break } }
    }
    if ($idxSel -ge 0) { $cmbNode.SelectedIndex = $idxSel }
    $script:lastNodeIdx = $idxSel
    $script:skipNodeSel = $false
}

function Get-SelectedNode {
    $i = $cmbNode.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:nodeMap.Count) { return $null }
    return $script:nodeMap[$i]
}

function Remove-SelectedNode {
    $n = Get-SelectedNode
    if (-not $n) { return }
    if ($n.sub -ne 'вручную') {
        [void][System.Windows.Forms.MessageBox]::Show('Этот сервер принадлежит подписке — удалить его отдельно нельзя. Удаляется вместе с подпиской (кнопка «Удалить» сверху).', 'Claude VPN', 'OK', 'Information')
        return
    }
    $cfg = Get-Config
    $cfg.manual = @($cfg.manual | Where-Object { -not ("$($_.host):$($_.port)" -eq "$($n.host):$($n.port)") })
    if ("$($n.host):$($n.port)" -eq $cfg.selectedNode) {
        Stop-Xray
        $cfg | Add-Member -NotePropertyName selectedNode -NotePropertyValue '' -Force
        $lblClaude.Text = 'Claude: туннель остановлен'
    }
    Save-Config $cfg
    Write-Log ('manual node removed: ' + $n.name)
    Refresh-Nodes
    $lblInfo.Text = "Сервер удалён: $($n.name)"
}

function Update-PresetList {
    $cmbPreset.Items.Clear()
    foreach ($p in (Get-ZapretPresets)) { [void]$cmbPreset.Items.Add($p) }
    $cfg = Get-Config
    $want = if ($cfg.zapretPreset) { $cfg.zapretPreset } else { 'general (ALT).bat' }
    $idx = $cmbPreset.Items.IndexOf($want)
    if ($idx -ge 0) { $cmbPreset.SelectedIndex = $idx }
    elseif ($cmbPreset.Items.Count -gt 0) { $cmbPreset.SelectedIndex = 0 }
}

function Save-SitesFromBox {
    $list = @($txtSites.Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $cfg = Get-Config
    $cfg | Add-Member -NotePropertyName sites -NotePropertyValue $list -Force
    Save-Config $cfg
    Set-SystemPac
    Write-Log ("sites saved: " + $list.Count + " [" + ($list -join ', ') + "]")
    $lblSitesHint.Text = "Сохранено доменов: $($list.Count)"
}

function Update-ZapretLabel {
    $v = Get-ZapretVersion
    $stt = Get-ZapretStatus
    $cfgZ = Get-Config
    $preset = if ($cfgZ.zapretPreset) { $cfgZ.zapretPreset } else { 'не выбран' }
    if ($stt.running) { $runText = 'работает' }
    elseif ($stt.foreign) { $runText = 'ЗАПУЩЕН ДРУГОЙ КОПИЕЙ' }
    else { $runText = 'ОСТАНОВЛЕН' }
    $lblZapret.Text = "zapret: $runText · пресет: $preset · версия: $v"
    $lblZapret.ForeColor = if ($stt.running) { [System.Drawing.Color]::FromArgb(110, 220, 140) } elseif ($stt.foreign) { [System.Drawing.Color]::FromArgb(240, 200, 110) } else { [System.Drawing.Color]::FromArgb(240, 150, 110) }
    if ($btnApplyPreset) {
        $selPreset = if ($cmbPreset.SelectedIndex -ge 0) { [string]$cmbPreset.SelectedItem } else { '' }
        if ($stt.running -and $selPreset -eq $preset) { $btnApplyPreset.Text = 'Завершить' }
        else { $btnApplyPreset.Text = 'Применить' }
    }
}

function Do-Status {
    $xray = (Get-Process xray -ErrorAction SilentlyContinue | Measure-Object).Count
    $pac = [bool](Get-NetTCPConnection -LocalPort 18080 -State Listen -ErrorAction SilentlyContinue)
    $ownX = Test-OwnXray
    $pacOwner = Get-PacOwner
    $foreignX = (($xray -gt 0) -and (-not $ownX))

    if ($foreignX) {
        $lblClaude.Text = 'Claude: туннель запущен ДРУГОЙ копией приложения, не этой'
        $lblClaude.ForeColor = [System.Drawing.Color]::FromArgb(240, 200, 110)
    }
    elseif (-not $ownX) {
        $lblClaude.Text = "Claude: туннель не запущен  (xray=$xray, pac=$pac)"
        $lblClaude.ForeColor = [System.Drawing.Color]::FromArgb(240, 150, 110)
    }
    else {
        $lblClaude.Text = 'Claude: проверяю соединение…'
        $lblClaude.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    }

    $m = Get-Mode
    $lblInfo.Text = if ($m -eq 'vpn-all') { 'Режим: YouTube и Discord через VPN' } else { 'Режим: YouTube и Discord напрямую (zapret)' }
    if ($pacOwner -and $pacOwner -ne $appDir) { $lblInfo.Text = $lblInfo.Text + '  ⚠ PAC обслуживает другая копия' }
    $btnMode.Text = if ($m -eq 'vpn-all') { 'YouTube: через VPN' } else { 'YouTube: напрямую' }
    Update-ZapretLabel

    if ($ownX) { Set-TrayState 'connecting'; Start-Probe } else { Set-TrayState 'disconnected'; $lblYt.Text = 'YouTube: —'; $lblDc.Text = 'Discord: —'; if ($script:startHidden) { $script:startHidden = $false; Show-MainWindow } }
}

# Проверки сети — в фоновом job, чтобы окно не замирало
function Start-Probe {
    if ($script:probeJob) {
        try { Stop-Job $script:probeJob -ErrorAction SilentlyContinue; Remove-Job $script:probeJob -Force -ErrorAction SilentlyContinue } catch { }
        $script:probeJob = $null
    }
    $lblYt.Text = 'YouTube: …'
    $lblDc.Text = 'Discord: …'
    $script:probeJob = Start-Job -ScriptBlock {
        param($port)
        $c = & curl.exe -s --max-time 5 --proxy ("http://127.0.0.1:" + $port) 'https://claude.ai/cdn-cgi/trace' 2>$null
        $yt = & curl.exe -s -o NUL -w '%{http_code}' --max-time 5 'https://www.youtube.com/' 2>$null
        $dc = & curl.exe -s -o NUL -w '%{http_code}' --max-time 5 'https://discord.com/' 2>$null
        $ip = (($c | Select-String '^ip=') -replace '^ip=', '').Trim()
        $loc = (($c | Select-String '^loc=') -replace '^loc=', '').Trim()
        [pscustomobject]@{ ip = $ip; loc = $loc; yt = [string]$yt; dc = [string]$dc }
    } -ArgumentList 10809
    $script:probTimer.Start()
}

function Start-Bench {
    $cfg = Get-Config
    $script:benchPrev = if ($cfg.zapretPreset) { $cfg.zapretPreset } else { '' }
    $lblZapret.Text = 'Подбираю пресет… (3-4 мин) Кнопка ниже — завершить'
    $btnZapBench.Text = 'Завершить подбор'
    $form.Refresh()
    $script:benchProc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $appDir 'bench.ps1')) -PassThru
    $script:benchTimer.Start()
}

function Finish-Bench([bool]$cancelled) {
    $script:benchTimer.Stop()
    if ($script:benchProc -and -not $script:benchProc.HasExited) {
        try { $script:benchProc | Stop-Process -Force } catch { }
    }
    $script:benchProc = $null
    $btnZapBench.Text = 'Подобрать пресет'
    $best = ''
    $bf = Join-Path $appDir 'zapret-bench.json'
    if (Test-Path $bf) {
        try {
            $r = Get-Content $bf -Raw | ConvertFrom-Json
            if ($r.best) { $best = $r.best }
        } catch { }
    }
    if (-not $best) { $best = $script:benchPrev }
    if ($best) {
        $cfg = Get-Config
        $cfg | Add-Member -NotePropertyName zapretPreset -NotePropertyValue $best -Force
        Save-Config $cfg
        [void](Start-ZapretPreset $best)
        $idx = $cmbPreset.Items.IndexOf($best)
        if ($idx -ge 0) { $cmbPreset.SelectedIndex = $idx }
        $lblInfo.Text = ($(if ($cancelled) { 'Подбор прерван. ' } else { 'Подбор завершён. ' }) + "Пресет: $best")
    }
    else {
        $lblInfo.Text = 'Подбор прерван, рабочих пресетов не найдено'
    }
    Update-ZapretLabel
}

$script:benchTimer = New-Object System.Windows.Forms.Timer
$script:benchTimer.Interval = 2000
$script:benchTimer.Add_Tick({
    $bf = Join-Path $appDir 'zapret-bench.json'
    $done = $false
    if (Test-Path $bf) {
        try { $done = [bool]((Get-Content $bf -Raw | ConvertFrom-Json).done) } catch { }
    }
    $exited = ($script:benchProc -eq $null) -or $script:benchProc.HasExited
    if ($done -or $exited) { Finish-Bench $false }
})

# ---------- обработчики ----------
$btnRefresh.Add_Click({
    $lblInfo.Text = 'Обновляю подписки…'
    $form.Refresh()
    try { Refresh-Nodes -Reload; $lblInfo.Text = "Загружено серверов: $($script:nodes.Count)" }
    catch { $lblInfo.Text = "Ошибка: $($_.Exception.Message)" }
})

$btnAdd.Add_Click({
    $u = $txtSub.Text.Trim()
    if (-not $u) { return }
    $type = [string]$cmbAddType.SelectedItem
    $cfg = Get-Config
    try {
        if ($type -eq 'Подписка') {
            $name = 'Подписка ' + (([guid]::NewGuid().ToString('N')).Substring(0, 4))
            $cfg.subscriptions = @($cfg.subscriptions) + [pscustomobject]@{ name = $name; url = $u }
            if (-not $cfg.activeSub) { $cfg.activeSub = $name }
            Save-Config $cfg
            Refresh-Subs
            Refresh-Nodes -Reload
            $lblInfo.Text = 'Подписка добавлена'
        }
        else {
            $kind = switch ($type) { 'VLESS' { 'vless' } 'SOCKS5' { 'socks' } 'HTTP' { 'http' } default { 'vless' } }
            $node = New-ManualNode $kind $u
            $cfg.manual = @($cfg.manual) + $node
            Save-Config $cfg
            Refresh-Nodes
            $lblInfo.Text = "Добавлено вручную: $($node.name)"
        }
        $txtSub.Text = ''
    }
    catch {
        $lblInfo.Text = 'Ошибка разбора: ' + $_.Exception.Message
        $msg = 'Не удалось добавить:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message
        [void][System.Windows.Forms.MessageBox]::Show($msg, 'Claude VPN', 'OK', 'Warning')
    }
})

$btnDel.Add_Click({
    $name = [string]$cmbSub.SelectedItem
    if (-not $name) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show("Удалить подписку «$name»?`n`nСерверы этой подписки пропадут из списка.", 'Claude VPN', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $cfg = Get-Config
    $cfg.subscriptions = @($cfg.subscriptions | Where-Object { $_.name -ne $name })
    if ($cfg.activeSub -eq $name) { $cfg.activeSub = '' }
    Save-Config $cfg
    $script:nodes = @(Update-Subscriptions)
    Refresh-Subs
    Refresh-Nodes

    # если выбранный сервер исчез вместе с подпиской — гасим туннель
    $cfgNow = Get-Config
    $stillThere = $script:nodes | Where-Object { "$($_.host):$($_.port)" -eq $cfgNow.selectedNode } | Select-Object -First 1
    if (-not $stillThere) {
        Stop-Xray
        $cfgNow | Add-Member -NotePropertyName selectedNode -NotePropertyValue '' -Force
        Save-Config $cfgNow
        Write-Log 'subscription deleted: chosen server gone, tunnel stopped'
        $lblInfo.Text = "Подписка удалена: $name — туннель остановлен"
    }
    else {
        $lblInfo.Text = "Подписка удалена: $name"
    }
})

$cmbSub.Add_SelectedIndexChanged({
    if ($script:loadingUi) { return }
    $name = [string]$cmbSub.SelectedItem
    if (-not $name) { return }
    $cfg = Get-Config
    $cfg.activeSub = $name
    Save-Config $cfg
    Refresh-Nodes
    $lblInfo.Text = "Активная подписка: $name"
})

$btnConnect.Add_Click({
    $node = Get-SelectedNode
    if (-not $node) { return }
    $lblInfo.Text = "Подключаюсь к $($node.name)…"
    $form.Refresh()
    Write-Log ('user: connect ' + $node.name)
    Start-XrayNode $node
    Ensure-PacServer
    Set-SystemPac
    $cfg = Get-Config
    $cfg.selectedNode = "$($node.host):$($node.port)"
    Save-Config $cfg
    Do-Status
})

$btnTestAll.Add_Click({
    $lblInfo.Text = 'Измеряю пинг по всем серверам…'
    $form.Refresh()
    $i = 0
    foreach ($n in $script:nodes) {
        $i++
        $lblInfo.Text = "Пинг $i / $($script:nodes.Count): $($n.name)"
        $form.Refresh()
        $ms = Test-TcpPing $n.host $n.port 2000
        $n | Add-Member -NotePropertyName pingMs -NotePropertyValue $ms -Force
    }

    # обновляем подписи прямо в сгруппированном списке
    $script:skipNodeSel = $true
    for ($k = 0; $k -lt $script:nodeMap.Count; $k++) {
        $n = $script:nodeMap[$k]
        if (-not $n) { continue }
        $ms = if ($n.pingMs -ge 0) { "$($n.pingMs) мс" } else { 'н/д' }
        $mark = if ($n.sub -eq 'вручную') { '• ' } else { '   ' }
        $cmbNode.Items[$k] = "$mark$($n.name)  [$($n.host)]  $ms"
    }
    $script:skipNodeSel = $false
    if ($script:lastNodeIdx -ge 0) { $cmbNode.SelectedIndex = $script:lastNodeIdx }

    $fastest = $script:nodes | Where-Object { $_.pingMs -ge 0 } | Sort-Object pingMs | Select-Object -First 1
    if ($fastest) { $lblInfo.Text = "Пинг готов. Быстрее всех: $($fastest.name) — $($fastest.pingMs) мс (сервер не менялся)" }
    else { $lblInfo.Text = 'Пинг: ни один сервер не ответил (сервер не менялся)' }
    Do-Status
})

$btnApplyPreset.Add_Click({
    if ($cmbPreset.SelectedIndex -lt 0) { return }
    $p = [string]$cmbPreset.SelectedItem
    $cfg = Get-Config
    $running = (Get-ZapretStatus).running
    $current = [string]$cfg.zapretPreset

    # если работает ровно этот пресет — кнопка выключает
    if ($running -and $current -eq $p) {
        Start-ZapretAction 'stop'
        return
    }

    # иначе — применяем выбранный (в т.ч. смена пресета)
    $cfg | Add-Member -NotePropertyName zapretPreset -NotePropertyValue $p -Force
    Save-Config $cfg
    $lblInfo.Text = "Запускаю пресет $p…"
    Start-ZapretAction 'start'
})

$cmbPreset.Add_SelectedIndexChanged({ try { Update-ZapretLabel } catch { } })

$btnZapUpd.Add_Click({
    if ($script:benchProc) { return }
    $lblZapret.Text = 'Проверяю обновление…'
    $form.Refresh()
    $resFile = Join-Path $appDir 'update-result.json'
    if (Test-Path $resFile) { Remove-Item $resFile -Force }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $appDir 'update-zapret.ps1')) -Wait
    $status = ''
    $msg = ''
    if (Test-Path $resFile) {
        try { $r = Get-Content $resFile -Raw | ConvertFrom-Json; $status = $r.status; $msg = $r.message } catch { }
    }
    if ($status -eq 'uptodate') {
        $lblInfo.Text = $msg
        Update-ZapretLabel
    }
    elseif ($status -eq 'updated') {
        $lblInfo.Text = $msg + ' — подбираю лучший пресет'
        Update-PresetList
        Start-Bench
    }
    else {
        $lblInfo.Text = 'Обновление: ' + $(if ($msg) { $msg } else { 'ошибка' })
        Update-ZapretLabel
    }
})

$btnZapBench.Add_Click({
    if ($script:benchProc) { Finish-Bench $true } else { Start-Bench }
})

$btnSaveSites.Add_Click({ Save-SitesFromBox })

$btnCheck.Add_Click({ Do-Status })

$btnMode.Add_Click({
    if ((Get-Mode) -eq 'vpn-all') { Set-Mode 'zapret' } else { Set-Mode 'vpn-all' }
    Do-Status
})

$btnStop.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Остановить туннель?`n`nClaude потеряет доступ к Anthropic, пока туннель выключен.`nYouTube и Discord продолжат работать напрямую.",
        'Claude VPN',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Write-Log 'user: tunnel stop'
    Stop-Xray
    Clear-SystemPac
    $lblClaude.Text = 'Claude: туннель остановлен'
    $lblClaude.ForeColor = [System.Drawing.Color]::FromArgb(240, 180, 100)
    $lblInfo.Text = 'Туннель выключен. YouTube/Discord работают напрямую.'
})

$btnLogs.Add_Click({
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File',(Join-Path $appDir 'tail.ps1'))
})

$btnHide.Add_Click({ $form.WindowState = 'Minimized' })

$txtSites.Add_TextChanged({
    if ($script:loadingSites) { return }
    $script:saveTimer.Stop()
    $script:saveTimer.Start()
})

$script:saveTimer = New-Object System.Windows.Forms.Timer
$script:saveTimer.Interval = 1200
$script:saveTimer.Add_Tick({ $script:saveTimer.Stop(); Save-SitesFromBox })

# ---------- настройки ----------
function Get-StartupPath { Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeVPN.vbs' }

function Test-AutostartTask {
    & schtasks.exe /query /tn 'ClaudeSplit Autostart' *> $null
    return ($LASTEXITCODE -eq 0)
}

# Автозапуск через планировщик с правами администратора:
# при входе в Windows приложение стартует сразу elevated, поэтому zapret
# поднимается сам, без запроса UAC.
function Set-Autostart([bool]$on) {
    $setup = Join-Path $appDir 'autostart-task.ps1'
    if (-not (Test-Path $setup)) { return }
    try {
        if ($on) {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $setup) -Wait -ErrorAction Stop
            Remove-Item -LiteralPath (Get-StartupPath) -Force -ErrorAction SilentlyContinue
        }
        else {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $setup, '-Remove') -Wait -ErrorAction Stop
        }
    }
    catch { }
}
$btnSaveSettings.Add_Click({
    $cfg = Get-Config
    $cfg | Add-Member -NotePropertyName autoZapret -NotePropertyValue ([bool]$chkZapretAuto.Checked) -Force
    $cfg | Add-Member -NotePropertyName checkUpdates -NotePropertyValue ([bool]$chkUpdateOnStart.Checked) -Force
    Save-Config $cfg
    Set-Autostart ([bool]$chkAutostart.Checked)
    $txtSettingsInfo.Text = "Сохранено. Автозапуск: " + $(if ($chkAutostart.Checked) { 'включён' } else { 'выключен' })
})

# ---------- kill-switch ----------
function Get-KillRules { return @(Get-ClaudeBlockRules) }

function Update-KillState {
    $rules = Get-KillRules
    $blocks = @($rules | Where-Object { "$($_.Action)" -eq 'Block' })
    if ($rules.Count -eq 0) { $txtKillRules.Text = 'правил нет' }
    else { $txtKillRules.Text = (($rules | ForEach-Object { "$($_.DisplayName)  ·  $($_.Action)  ·  enabled=$($_.Enabled)" }) -join "`r`n") }
    if ($blocks.Count -gt 0) {
        $lblKill.Text = "Kill-switch: ВКЛЮЧЁН  ($($blocks.Count) блокирующих правил)"
        $lblKill.ForeColor = [System.Drawing.Color]::FromArgb(110, 220, 140)
        $btnKill.Text = 'Выключить защиту'
        $btnKill.BackColor = [System.Drawing.Color]::FromArgb(120, 50, 50)
    }
    else {
        $lblKill.Text = 'Kill-switch: ВЫКЛЮЧЕН — Claude может выйти в интернет напрямую'
        $lblKill.ForeColor = [System.Drawing.Color]::FromArgb(240, 130, 110)
        $btnKill.Text = 'Включить защиту'
        $btnKill.BackColor = [System.Drawing.Color]::FromArgb(30, 110, 160)
    }
}

$btnKill.Add_Click({
    $rules = Get-KillRules
    $on = @($rules | Where-Object { "$($_.Action)" -eq 'Block' }).Count -gt 0
    if ($on) {
        $msg = "Выключить kill-switch?`n`nClaude сможет подключаться к интернету напрямую, в обход VPN. Если VPN/прокси выключен, Anthropic увидит российский IP — аккаунт может быть заблокирован."
        $ans = [System.Windows.Forms.MessageBox]::Show($msg, 'Claude VPN', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $scriptName = 'uninstall-killswitch.ps1'
    }
    else {
        $msg = "Включить kill-switch?`n`nClaude будет работать ТОЛЬКО через VPN-прокси. Без туннеля доступ в интернет у него пропадёт — это ожидаемое поведение.`n`nПотребуется подтверждение администратора Windows."
        $ans = [System.Windows.Forms.MessageBox]::Show($msg, 'Claude VPN', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $scriptName = 'install-killswitch.ps1'
    }
    $path = Join-Path $appDir $scriptName
    if (-not (Test-Path $path)) { $lblKill.Text = 'Не найден скрипт: ' + $path; return }
    $lblKill.Text = 'Применяю правила…'
    $form.Refresh()
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$path) -Wait -ErrorAction Stop
        Write-Log ('kill-switch toggled -> ' + $scriptName)
    }
    catch {
        $lblKill.Text = 'Отменено или ошибка: ' + $_.Exception.Message
        return
    }
    Start-Sleep -Milliseconds 600
    Update-KillState
})

$btnKillCheck.Add_Click({
    $lblKill.Text = 'Проверяю защиту…'
    $form.Refresh()
    try {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $appDir 'kill-audit.ps1') 2>&1 | Out-String
        $txtKillRules.Text = $out.Trim()
        if ($out -match 'ВЕРДИКТ: Защита работает') {
            $lblKill.Text = 'Проверка: защита работает'
            $lblKill.ForeColor = [System.Drawing.Color]::FromArgb(110, 220, 140)
        }
        elseif ($out -match 'ВЕРДИКТ: Работает, но есть замечания') {
            $lblKill.Text = 'Проверка: работает, но есть замечания'
            $lblKill.ForeColor = [System.Drawing.Color]::FromArgb(240, 200, 110)
        }
        else {
            $lblKill.Text = 'Проверка: защита НЕ работает — смотри детали ниже'
            $lblKill.ForeColor = [System.Drawing.Color]::FromArgb(240, 120, 120)
        }
        Write-Log 'kill-switch audit executed'
    }
    catch {
        $txtKillRules.Text = 'Ошибка проверки: ' + $_.Exception.Message
    }
})

# клик по надписи отключён: управление кнопкой справа

function Start-ZapretAction([string]$act) {
    if ($script:zapActProc) {
        $alive = $false
        try { $alive = -not $script:zapActProc.HasExited } catch { $alive = $false }
        if ($alive) { return }
        $script:zapActProc = $null
    }
    $res = Join-Path $appDir 'zapret-action.json'
    Remove-Item $res -Force -ErrorAction SilentlyContinue
    $cfgZ = Get-Config
    $pz = if ($cfgZ.zapretPreset) { $cfgZ.zapretPreset } else { 'general (ALT).bat' }
    $lblZapret.Text = if ($act -eq 'start' -or $act -eq 'toggle') { 'zapret: запускаю… подтвердите UAC' } else { 'zapret: останавливаю…' }
    $lblZapret.ForeColor = [System.Drawing.Color]::FromArgb(240, 200, 110)
    $script:zapActProc = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', (Join-Path $appDir 'zapret-action.ps1'), '-Action', $act, '-Preset', ('"' + $pz + '"')
    ) -PassThru -WindowStyle Hidden
    $script:zapActTimer.Start()
}

# автообновление статуса zapret (чтобы клик всегда попадал в реальное состояние)
$script:tmrZapret = New-Object System.Windows.Forms.Timer
$script:tmrZapret.Interval = 3000
$script:tmrZapret.Add_Tick({ try { Update-ZapretLabel } catch { } })
$script:tmrZapret.Start()

# таймер, который забирает результат фоновых проверок
$script:probTimer = New-Object System.Windows.Forms.Timer
$script:probTimer.Interval = 400
$script:probTimer.Add_Tick({
    if (-not $script:probeJob) { $script:probTimer.Stop(); return }
    if ($script:probeJob.State -ne 'Completed' -and $script:probeJob.State -ne 'Failed') { return }
    $res = $null
    try { $res = Receive-Job $script:probeJob -ErrorAction SilentlyContinue | Select-Object -Last 1 } catch { }
    try { Remove-Job $script:probeJob -Force -ErrorAction SilentlyContinue } catch { }
    $script:probeJob = $null
    $script:probTimer.Stop()
    if ($res) {
        if ($res.ip) {
            $lblClaude.Text = "Claude: VPN, выход $($res.ip) ($($res.loc))"
            $lblClaude.ForeColor = [System.Drawing.Color]::FromArgb(110, 220, 140)
        }
        else {
            $lblClaude.Text = 'Claude: прокси запущен, но соединения нет'
            $lblClaude.ForeColor = [System.Drawing.Color]::FromArgb(240, 120, 120)
        }
        $lblYt.Text = "YouTube: $($res.yt)"
        $lblDc.Text = "Discord: $($res.dc)"
        if ($res.ip) { Set-TrayState 'connected' }
        else {
            Set-TrayState 'disconnected'
            if ($script:startHidden) { $script:startHidden = $false; Show-MainWindow }
        }
    }
})

# таймер завершения фоновой операции с zapret
$script:zapActTimer = New-Object System.Windows.Forms.Timer
$script:zapActTimer.Interval = 500
$script:zapActTimer.Add_Tick({
    $res = Join-Path $appDir 'zapret-action.json'
    if ($script:zapActProc -and -not $script:zapActProc.HasExited) { return }
    if (-not (Test-Path $res)) {
        if ($script:zapActProc -and $script:zapActProc.HasExited) {
            $script:zapActTimer.Stop()
            $script:zapActProc = $null
            Write-Log 'user: zapret action finished without result'
            Update-ZapretLabel
        }
        return
    }
    $r = $null
    try { $r = Get-Content $res -Raw | ConvertFrom-Json } catch { }
    Remove-Item $res -Force -ErrorAction SilentlyContinue
    $script:zapActTimer.Stop()
    $script:zapActProc = $null
    if ($r) {
        $info = 'user: zapret ' + $r.action + ' -> ok=' + $r.ok + ' running=' + $r.running
        if ($r.error) { $info = $info + ' err=' + $r.error }
        Write-Log $info
        if (-not $r.ok) {
            $lblInfo.Text = 'zapret не запустился: подтвердите запрос администратора (UAC)'
        }
        else {
            $lblInfo.Text = if ($r.running) { 'zapret запущен' } else { 'zapret остановлен' }
        }
    }
    Update-ZapretLabel
})

$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $pageClaude) { Update-KillState }
})

# ---------- трей ----------
$script:reallyExit = $false
$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.SystemIcons]::Shield
$ni.Text = 'Claude VPN'
$ni.Visible = $true

$tmenu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = New-Object System.Windows.Forms.ToolStripMenuItem('Открыть окно')
$miCheckT = New-Object System.Windows.Forms.ToolStripMenuItem('Проверить связь')
$miExitT = New-Object System.Windows.Forms.ToolStripMenuItem('Остановить всё и выйти')
[void]$tmenu.Items.Add($miOpen)
[void]$tmenu.Items.Add($miCheckT)
[void]$tmenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$tmenu.Items.Add($miExitT)
$ni.ContextMenuStrip = $tmenu

# статус в трее + цветная иконка
$miStatus = New-Object System.Windows.Forms.ToolStripMenuItem('Статус: проверяю…')
$miStatus.Enabled = $false
[void]$tmenu.Items.Insert(0, $miStatus)

function New-StatusIcon([System.Drawing.Color]$c) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $br = New-Object System.Drawing.SolidBrush $c
    $g.FillEllipse($br, 1, 1, 13, 13)
    $g.Dispose(); $br.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$script:icoGreen = New-StatusIcon ([System.Drawing.Color]::FromArgb(60, 200, 110))
$script:icoYellow = New-StatusIcon ([System.Drawing.Color]::FromArgb(240, 200, 60))
$script:icoRed = New-StatusIcon ([System.Drawing.Color]::FromArgb(230, 80, 80))

function Set-TrayState([string]$state) {
    switch ($state) {
        'connected' {
            $miStatus.Text = 'Статус: подключено'
            $miStatus.ForeColor = [System.Drawing.Color]::FromArgb(60, 170, 90)
            $ni.Icon = $script:icoGreen
            $ni.Text = 'Claude VPN — подключено'
        }
        'connecting' {
            $miStatus.Text = 'Статус: подключение…'
            $miStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 140, 0)
            $ni.Icon = $script:icoYellow
            $ni.Text = 'Claude VPN — подключение…'
        }
        default {
            $miStatus.Text = 'Статус: нет соединения'
            $miStatus.ForeColor = [System.Drawing.Color]::FromArgb(200, 60, 60)
            $ni.Icon = $script:icoRed
            $ni.Text = 'Claude VPN — нет соединения'
        }
    }
}

function Show-MainWindow { $form.Show(); $form.WindowState = 'Normal'; $form.Activate() }
$miOpen.Add_Click({ Show-MainWindow })
$miCheckT.Add_Click({ Show-MainWindow })
$miExitT.Add_Click({
    $script:reallyExit = $true
    Stop-Xray
    Stop-ZapretDaemon
    Stop-PacServer
    Clear-SystemPac
    Write-Log 'user: exit — tunnel and zapret stopped'
    $ni.Visible = $false
    $ni.Dispose()
    $form.Close()
})
$ni.Add_DoubleClick({ Show-MainWindow })

$form.Add_Resize({ if ($form.WindowState -eq 'Minimized') { $form.Hide(); $ni.Visible = $true } })

$form.Add_FormClosing({
    param($s, $e)
    Save-SitesFromBox
    if ($script:reallyExit) {
        Stop-Xray
        Stop-ZapretDaemon
        Stop-PacServer
        Clear-SystemPac
    }
    if (-not $script:reallyExit) {
        $e.Cancel = $true
        $form.Hide()
        $ni.Visible = $true
        $ni.ShowBalloonTip(4000, 'Claude VPN', 'Свёрнуто в трей. Туннель работает. Двойной клик — открыть окно.', [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

# ---------- старт ----------
$form.Add_Shown({
    $script:startHidden = [bool]$Minimized
    $tabs.SelectedIndex = 0
    if ($StartTab -eq 'claude') { $tabs.SelectedIndex = 1 }
    if ($StartTab -eq 'settings') { $tabs.SelectedIndex = 2 }
    Update-KillState
    if (-not (Test-Path (Join-Path (Split-Path $appDir -Parent) 'bin\xray.exe'))) { & (Join-Path $appDir 'bootstrap.ps1') }
    $script:loadingUi = $true
    $script:loadingSites = $true
    Refresh-Subs
    Refresh-Nodes
    if ($script:nodes.Count -eq 0) { Refresh-Nodes -Reload }
    $conf = Get-Config
    if ($conf.sites) { $txtSites.Text = (@($conf.sites) -join "`r`n") }
    $script:loadingSites = $false
    $script:loadingUi = $false

    Update-PresetList
    if ($script:startHidden) { $form.Hide() }
    $chkAutostart.Checked = ((Test-AutostartTask) -or (Test-Path (Get-StartupPath)))
    $chkZapretAuto.Checked = if ($null -ne $conf.autoZapret) { [bool]$conf.autoZapret } else { $false }
    $chkUpdateOnStart.Checked = if ($null -ne $conf.checkUpdates) { [bool]$conf.checkUpdates } else { $false }
    $txtSettingsInfo.Text = ("Папка приложения: " + $appDir + "`r`n" + "zapret: " + (Get-ZapretVersion) + "`r`n" + "Пресетов: " + (Get-ZapretPresets).Count)

    Write-Log 'app started'
    if ($chkZapretAuto.Checked -and -not (Get-ZapretStatus).running -and (Test-ZapretDaemon)) {
        $pz = if ($conf.zapretPreset) { $conf.zapretPreset } else { 'general (ALT).bat' }
        $ok = Start-ZapretPreset $pz
        Write-Log ('user: zapret start -> ok=' + $ok)
    }
    elseif ($chkZapretAuto.Checked -and -not (Get-ZapretStatus).running) {
        $lblZapret.Text = 'zapret: ОСТАНОВЛЕН — кликните по строке, чтобы запустить (нужен UAC)'
        $lblZapret.ForeColor = [System.Drawing.Color]::FromArgb(240, 200, 110)
    }
    if ($chkUpdateOnStart.Checked) {
        $lblZapret.Text = 'Проверяю обновление zapret…'
        $form.Refresh()
        $rf = Join-Path $appDir 'update-result.json'
        if (Test-Path $rf) { Remove-Item $rf -Force }
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $appDir 'update-zapret.ps1')) -Wait
        $st = ''
        if (Test-Path $rf) { try { $st = (Get-Content $rf -Raw | ConvertFrom-Json).status } catch { } }
        if ($st -eq 'updated') {
            Update-PresetList
            Start-Bench
        }
    }
    Update-ZapretLabel
    Do-Status
})

[System.Windows.Forms.Application]::Run($form)
