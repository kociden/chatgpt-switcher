#Requires -Version 5.1
<#
.SYNOPSIS
  ChatGPT アカウント切替ランチャー（Windows / 新ChatGPTデスクトップアプリ用）

.DESCRIPTION
  アカウントごとに独立したデータ領域（Electron の user-data と CODEX_HOME）を用意し、
  ChatGPTデスクトップアプリを別プロセスとして起動します。複数アカウントの同時起動も可能。
  既存のログイン（メイン）はそのまま残ります。

  使い方:
    ChatGPT-Switcher.ps1                  … 切替ウィンドウ（ピッカー）を表示
    ChatGPT-Switcher.ps1 -Launch 仕事用    … 指定アカウントで起動（起動中なら前面に）
    ChatGPT-Switcher.ps1 -Add 仕事用       … アカウント追加（デスクトップにショートカットも作成）
    ChatGPT-Switcher.ps1 -Remove 仕事用    … アカウント削除（ローカルデータも削除）
    ChatGPT-Switcher.ps1 -List            … アカウント一覧
    ChatGPT-Switcher.ps1 -Setup           … ピッカーのショートカットをデスクトップ/スタートメニューに作成
    ChatGPT-Switcher.ps1 -Tray            … タスクトレイに常駐（左クリック=ピッカー、右クリック=一覧）
    ChatGPT-Switcher.ps1 -AutoStartTray   … トレイ常駐をWindows起動時に自動開始
    ChatGPT-Switcher.ps1 -Diagnose        … 環境診断（アプリ検出・パス・起動状況）

  データ保存先: %USERPROFILE%\ChatGPT-Accounts\<アカウントID>\{electron,codex}
#>
param(
  [string]$Launch,
  [string]$Add,
  [string]$Remove,
  [switch]$List,
  [switch]$Setup,
  [switch]$Tray,
  [switch]$AutoStartTray,
  [switch]$Diagnose,
  [switch]$NoShortcut,
  [switch]$Version,
  [switch]$Shared,
  [string]$SaveAuth,
  [ValidateSet('ja', 'en')]
  [string]$Language
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:AppVersion = '1.2.0'
$script:AppId      = 'Alyawmu.ChatGPTSwitcher'   # taskbar grouping + jump list identity
$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:Root       = Join-Path $env:USERPROFILE 'ChatGPT-Accounts'
$script:ConfigPath = Join-Path $script:Root 'accounts.json'
$script:LogPath    = Join-Path $script:Root 'switcher.log'
$script:MainId     = '__main__'
$script:MainLabel  = ''
$script:Palette    = @('#4285F4','#34A853','#EA4335','#F9AB00','#A142F4','#F538A0','#12B5CB','#FF6D01')
$script:AppCache   = $null
$script:Gui        = $false


# Embedded translations preserve the dependency-free, single-script distribution.
$script:UiLanguage = 'ja'
$script:Translations = ConvertFrom-Json @'
{
  "MainLabel": {
    "ja": "メイン（元々ログインしているアカウント）",
    "en": "Main (original signed-in account)"
  },
  "AppTitle": {
    "ja": "ChatGPT アカウント切替",
    "en": "ChatGPT Account Switcher"
  },
  "Cancel": {
    "ja": "キャンセル",
    "en": "Cancel"
  },
  "EmptyAccount": {
    "ja": "アカウント名が空です。",
    "en": "Account name is empty."
  },
  "DuplicateAccount": {
    "ja": "「{0}」は既に登録されています。",
    "en": "“{0}” is already registered."
  },
  "AccountNotFound": {
    "ja": "アカウント「{0}」が見つかりません。",
    "en": "Account “{0}” was not found."
  },
  "AccountRunning": {
    "ja": "「{0}」のChatGPTが起動中です。先に終了してください。",
    "en": "ChatGPT is running for “{0}”. Close it first."
  },
  "InstallApp": {
    "ja": "ChatGPTデスクトップアプリが見つかりません。Microsoft Store から「ChatGPT」をインストールしてください。",
    "en": "ChatGPT desktop app was not found. Install ChatGPT from Microsoft Store."
  },
  "AccountNotRegistered": {
    "ja": "アカウント「{0}」が登録されていません。",
    "en": "Account “{0}” is not registered."
  },
  "ExeNotFound": {
    "ja": "ChatGPT.exe が見つかりません（{0}）。",
    "en": "ChatGPT.exe was not found ({0})."
  },
  "LoginFirst": {
    "ja": "現在の ~/.codex\\auth.json が見つかりません。先にChatGPTで一度ログインしてください。",
    "en": "Cannot find ~/.codex/auth.json. Sign in to ChatGPT first."
  },
  "AppNotFound": {
    "ja": "ChatGPTデスクトップアプリが見つかりません。",
    "en": "ChatGPT desktop app was not found."
  },
  "SharedAlreadyRunning": {
    "ja": "完全共有アカウントは1つずつです。今開いているChatGPTのウィンドウを閉じてから、もう一度切り替えてください。",
    "en": "Only one shared account can run at a time. Close the open ChatGPT windows and try again."
  },
  "Main": {
    "ja": "メイン",
    "en": "Main"
  },
  "Accounts": {
    "ja": "アカウント",
    "en": "Accounts"
  },
  "OpenAs": {
    "ja": "ChatGPT を「{0}」で開く",
    "en": "Open ChatGPT as “{0}”"
  },
  "OpenPicker": {
    "ja": "切替ウィンドウを開く",
    "en": "Open account picker"
  },
  "LaunchAs": {
    "ja": "ChatGPT を「{0}」で起動",
    "en": "Launch ChatGPT as “{0}”"
  },
  "PickerShortcut": {
    "ja": "ChatGPT アカウント切替.lnk",
    "en": "ChatGPT Account Switcher.lnk"
  },
  "ChooseAccount": {
    "ja": "ChatGPT のアカウントを選んで起動",
    "en": "Choose an account and launch ChatGPT"
  },
  "TrayShortcut": {
    "ja": "ChatGPT 切替（トレイ常駐）.lnk",
    "en": "ChatGPT Switcher (Tray).lnk"
  },
  "TrayDescription": {
    "ja": "タスクトレイに常駐して右クリックで切替",
    "en": "Run in the system tray; right-click to switch accounts"
  },
  "TrayTitle": {
    "ja": "ChatGPT アカウント切替（トレイ常駐）",
    "en": "ChatGPT Account Switcher (Tray)"
  },
  "AccountNamePrompt": {
    "ja": "アカウントの表示名を入力してください（例: 仕事用 / 個人 / 副業）",
    "en": "Enter an account display name (e.g. Work / Personal)"
  },
  "AddAccount": {
    "ja": "アカウントを追加",
    "en": "Add account"
  },
  "ModePrompt": {
    "ja": "「{0}」のモードを選んでください。\n\n[はい] 完全共有モード:\n  Codexのプロジェクト/チャットを全アカウントで共有（公式風）。ただし1アカウントずつ（同時起動不可）。\n\n[いいえ] 分離モード:\n  アカウントごとに独立。同時起動OK。プロジェクトは別々。",
    "en": "Choose a mode for “{0}”.\n\n[Yes] Shared mode:\nShare Codex projects and chats across accounts. Only one account can run at a time.\n\n[No] Isolated mode:\nSeparate projects and logins. Multiple accounts can run together."
  },
  "SharedModeQuestion": {
    "ja": "完全共有モードにしますか？",
    "en": "Use shared mode?"
  },
  "Error": {
    "ja": "エラー",
    "en": "Error"
  },
  "SharedAdded": {
    "ja": "「{0}」を完全共有で追加しました。\n\n今から起動してこのアカウントでログインしますか？\n（ログイン後、一覧の右クリック→「現在のログインをこのアカウントとして保存」を実行してください）",
    "en": "Added “{0}” in shared mode.\n\nLaunch and sign in now?\nAfter signing in, right-click this account and choose “Save current login to this account”."
  },
  "IsolatedAdded": {
    "ja": "「{0}」を追加しました。デスクトップにショートカットも作りました。\n\n今すぐ起動してログインしますか？",
    "en": "Added “{0}” and created a desktop shortcut.\n\nLaunch and sign in now?"
  },
  "PickerHeading": {
    "ja": "どのアカウントで開く？",
    "en": "Which account would you like to open?"
  },
  "AddAccountButton": {
    "ja": "＋ アカウントを追加",
    "en": "＋ Add account"
  },
  "Settings": {
    "ja": "設定 ▾",
    "en": "Settings ▾"
  },
  "CreatePickerShortcuts": {
    "ja": "この切替ウィンドウのショートカットを作る（デスクトップ/スタート）",
    "en": "Create picker shortcuts (Desktop / Start)"
  },
  "ShortcutsCreated": {
    "ja": "ショートカットを作成しました。",
    "en": "Shortcuts created."
  },
  "StartTray": {
    "ja": "タスクトレイに常駐して使う（今すぐ開始）",
    "en": "Start system tray mode now"
  },
  "AutoStartTray": {
    "ja": "トレイ常駐をWindows起動時に自動開始する",
    "en": "Start tray mode when Windows starts"
  },
  "StartupRegistered": {
    "ja": "スタートアップに登録しました。",
    "en": "Added to Windows startup."
  },
  "OpenDataFolder": {
    "ja": "データフォルダを開く",
    "en": "Open data folder"
  },
  "Diagnostics": {
    "ja": "環境診断を表示",
    "en": "Show diagnostics"
  },
  "SharedBadge": {
    "ja": "  〔共有〕",
    "en": "  [Shared]"
  },
  "RunningBadge": {
    "ja": "   ● 起動中",
    "en": "   ● Running"
  },
  "SaveLogin": {
    "ja": "現在のログインをこのアカウントとして保存",
    "en": "Save current login to this account"
  },
  "SaveLoginQuestion": {
    "ja": "今 ~/.codex にログイン中のアカウントを「{0}」として保存します。よろしいですか？",
    "en": "Save the current ~/.codex login as “{0}”?"
  },
  "LoginSaved": {
    "ja": "「{0}」として現在のログインを保存しました。",
    "en": "Saved the current login as “{0}”."
  },
  "CreateDesktopShortcut": {
    "ja": "デスクトップにショートカットを作る",
    "en": "Create desktop shortcut"
  },
  "DesktopShortcutCreated": {
    "ja": "デスクトップにショートカットを作成しました。",
    "en": "Desktop shortcut created."
  },
  "Rename": {
    "ja": "名前を変更",
    "en": "Rename"
  },
  "RenamePrompt": {
    "ja": "新しい表示名を入力してください",
    "en": "Enter a new display name"
  },
  "RemoveAccount": {
    "ja": "このアカウントを削除…",
    "en": "Remove this account…"
  },
  "RemoveAccountQuestion": {
    "ja": "「{0}」を削除しますか？\nこのPC上のログイン情報とキャッシュが消えます（ChatGPT側のアカウントや履歴は消えません）。",
    "en": "Remove “{0}”?\nThis deletes this PC’s login data and cache. Your ChatGPT account and history will remain."
  },
  "PickerHint": {
    "ja": "右クリックで各種操作。〔共有〕=プロジェクト共有(1つずつ)。それ以外は分離(同時起動可)。",
    "en": "Right-click for actions. [Shared]: shared projects, one account at a time. Other accounts run independently."
  },
  "OpenChatGPT": {
    "ja": "ChatGPT を開く:",
    "en": "Open ChatGPT:"
  },
  "TrayRunning": {
    "ja": "  ● 起動中",
    "en": "  ● Running"
  },
  "ExitTray": {
    "ja": "常駐を終了",
    "en": "Exit tray mode"
  },
  "DiagnosticHeading": {
    "ja": "=== ChatGPT アカウント切替 環境診断 ===",
    "en": "=== ChatGPT Switcher Diagnostics ==="
  },
  "Version": {
    "ja": "バージョン   : {0}",
    "en": "Version     : {0}"
  },
  "Script": {
    "ja": "スクリプト   : {0}",
    "en": "Script      : {0}"
  },
  "DataFolder": {
    "ja": "データ保存先 : {0}",
    "en": "Data folder : {0}"
  },
  "AppNotFoundDiagnostic": {
    "ja": "ChatGPTデスクトップアプリ: 見つかりません（Store の OpenAI.Codex / 通常インストール版のどちらも）",
    "en": "ChatGPT desktop app: not found (Store or installer version)"
  },
  "DesktopApp": {
    "ja": "ChatGPTデスクトップアプリ:",
    "en": "ChatGPT desktop app:"
  },
  "AppKind": {
    "ja": "  種別      : {0}",
    "en": "  Type     : {0}"
  },
  "AppVersion": {
    "ja": "  バージョン: {0}",
    "en": "  Version  : {0}"
  },
  "AppLocation": {
    "ja": "  場所      : {0}",
    "en": "  Location : {0}"
  },
  "NotFound": {
    "ja": "(見つからず)",
    "en": "(not found)"
  },
  "ExeReadable": {
    "ja": "  EXE 読み取り: OK",
    "en": "  EXE readable: OK"
  },
  "ExeReadFailed": {
    "ja": "  EXE 読み取り: NG ({0})",
    "en": "  EXE read failed: {0}"
  },
  "DefaultCodexHome": {
    "ja": "標準の CODEX_HOME  : {0}  (存在: {1})",
    "en": "Default CODEX_HOME: {0} (exists: {1})"
  },
  "DefaultElectronData": {
    "ja": "標準の Electron data: {0}  (存在: {1})",
    "en": "Default Electron data: {0} (exists: {1})"
  },
  "AccountSummary": {
    "ja": "登録アカウント: {0} 件   完全共有アクティブ: {1}",
    "en": "Registered accounts: {0}   Active shared account: {1}"
  },
  "None": {
    "ja": "(なし)",
    "en": "(none)"
  },
  "SharedAuth": {
    "ja": "      shared-auth: {0}  (保存済: {1})",
    "en": "      shared-auth: {0} (saved: {1})"
  },
  "Processes": {
    "ja": "ChatGPT.exe プロセス:",
    "en": "ChatGPT.exe processes:"
  },
  "ProcessQueryFailed": {
    "ja": "  (取得失敗: {0})",
    "en": "  (query failed: {0})"
  },
  "Log": {
    "ja": "ログ: {0}",
    "en": "Log: {0}"
  },
  "Running": {
    "ja": "  (起動中)",
    "en": "  (running)"
  },
  "Added": {
    "ja": "追加しました: [{0}] {1}{2}",
    "en": "Added: [{0}] {1}{2}"
  },
  "Shared": {
    "ja": " (完全共有)",
    "en": " (shared)"
  },
  "LaunchCommand": {
    "ja": "起動: ChatGPT-Switcher.ps1 -Launch {0}",
    "en": "Launch: ChatGPT-Switcher.ps1 -Launch {0}"
  },
  "SaveLoginInstructions": {
    "ja": "完全共有: 初回はこのアカウントでログイン後、次を実行して現在のログインを保存してください:",
    "en": "Shared mode: after your first sign-in, run the following to save the current login:"
  },
  "SaveAccountNotFound": {
    "ja": "アカウント「{0}」が見つかりません。",
    "en": "Account “{0}” was not found."
  },
  "NotShared": {
    "ja": "「{0}」は完全共有アカウントではありません。",
    "en": "“{0}” is not a shared account."
  },
  "CurrentLoginSaved": {
    "ja": "現在のログインを「{0}」として保存しました。",
    "en": "Saved the current login as “{0}”."
  },
  "Removed": {
    "ja": "削除しました: {0}",
    "en": "Removed: {0}"
  },
  "Created": {
    "ja": "作成: {0}",
    "en": "Created: {0}"
  },
  "ShortcutsCreatedPrefix": {
    "ja": "ショートカットを作成しました:\n",
    "en": "Shortcuts created:\n"
  },
  "PinInstructions": {
    "ja": "\n\nタスクバーに固定するには:\nスタートメニューの「ChatGPT アカウント切替」を右クリック →「タスクバーにピン留めする」。\nピン留め後、そのアイコンを右クリックすると各アカウントが並びます（ジャンプリスト）。",
    "en": "\n\nTo pin to the taskbar:\nRight-click the switcher shortcut in Start and choose “Pin to taskbar”.\nRight-click the pinned icon to see accounts in its jump list."
  },
  "StartupPath": {
    "ja": "スタートアップに登録: {0}",
    "en": "Added to startup: {0}"
  },
  "ErrorPrefix": {
    "ja": "エラー: {0}",
    "en": "Error: {0}"
  },
  "ErrorDetails": {
    "ja": "エラー: {0}\n\n詳細ログ: {1}",
    "en": "Error: {0}\n\nDetails log: {1}"
  },
  "Yes": {
    "ja": "はい",
    "en": "Yes"
  },
  "No": {
    "ja": "いいえ",
    "en": "No"
  },
  "OK": {
    "ja": "OK",
    "en": "OK"
  },
  "SelectLanguage": {
    "ja": "表示言語を選択してください",
    "en": "Choose the interface language"
  },
  "Continue": {
    "ja": "続行",
    "en": "Continue"
  },
  "Language": {
    "ja": "言語",
    "en": "Language"
  }
}
'@

function Get-Text {
  param([string]$Key)
  $message = $script:Translations.$Key.($script:UiLanguage)
  if ($null -eq $message) { throw "Missing translation: $Key" }
  if ($args.Count) { return ($message -f $args) }
  return $message
}

function Set-InterfaceLanguage {
  param([ValidateSet('ja', 'en')][string]$Code)
  $script:UiLanguage = $Code
  $script:MainLabel = Get-Text 'MainLabel'
}

function Show-LanguageSelector {
  Ensure-Gui
  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = '日本語 / English'
  $dialog.StartPosition = 'CenterScreen'
  $dialog.FormBorderStyle = 'FixedDialog'
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false
  $dialog.ClientSize = New-Object System.Drawing.Size(420, 160)
  $dialog.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)
  $label = New-Object System.Windows.Forms.Label
  $label.Text = Get-Text 'SelectLanguage'
  $label.SetBounds(15, 15, 390, 30)
  $choices = New-Object System.Windows.Forms.ComboBox
  $choices.DropDownStyle = 'DropDownList'
  $choices.SetBounds(15, 50, 390, 30)
  [void]$choices.Items.AddRange(@('日本語', 'English'))
  $codes = @('ja', 'en')
  $choices.SelectedIndex = [Array]::IndexOf($codes, $script:UiLanguage)
  $continue = New-Object System.Windows.Forms.Button
  $continue.SetBounds(285, 105, 120, 35)
  $continue.Text = Get-Text 'Continue'
  $continue.DialogResult = 'OK'
  $dialog.Controls.AddRange(@($label, $choices, $continue))
  $dialog.AcceptButton = $continue
  $choices.add_SelectedIndexChanged({
    $code = @('ja','en')[$this.SelectedIndex]
    $label.Text = $script:Translations.SelectLanguage.$code
    $continue.Text = $script:Translations.Continue.$code
  })
  $owner = Get-DialogOwner
  try {
    $result = if ($owner) { $dialog.ShowDialog($owner) } else { $dialog.ShowDialog() }
    if ($result -ne 'OK') { return $false }
    $code = $codes[$choices.SelectedIndex]
    $cfg = Get-Config
    $cfg | Add-Member -NotePropertyName language -NotePropertyValue $code -Force
    Save-Config $cfg
    Set-InterfaceLanguage $code
    return $true
  } finally { $dialog.Dispose() }
}

# ------------------------------------------------------------------ 共通

function Write-Log {
  param([string]$Message)
  try {
    New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
    Add-Content -Path $script:LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
  } catch {}
}

function Ensure-Gui {
  if ($script:Gui) { return }
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  [System.Windows.Forms.Application]::EnableVisualStyles()
  $script:Gui = $true
  Set-ProcessAppId   # taskbar button groups under the pinned switcher icon
}

function Get-DialogOwner {
  # ピッカーが表示中ならそれを親にする（ダイアログが背面に隠れるのを防ぐ）
  $f = $script:PickerForm
  if ($f -and -not $f.IsDisposed -and $f.Visible) { return $f }
  return $null
}

function Show-LocalizedDialog {
  param([string]$Text, [string]$Title, [string]$Icon = 'Information', [switch]$Question)
  Ensure-Gui
  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = $Title
  $dialog.StartPosition = 'CenterScreen'
  $dialog.FormBorderStyle = 'FixedDialog'
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false
  $dialog.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)
  $dialog.ClientSize = New-Object System.Drawing.Size(560, 330)
  $dialog.Icon = if ($Question) { [System.Drawing.SystemIcons]::Question } elseif ($Icon -eq 'Error') { [System.Drawing.SystemIcons]::Error } else { [System.Drawing.SystemIcons]::Information }
  $body = New-Object System.Windows.Forms.TextBox
  $body.Multiline = $true
  $body.ReadOnly = $true
  $body.BorderStyle = 'None'
  $body.ScrollBars = 'Vertical'
  $body.Text = $Text -replace "`r?`n", "`r`n"
  $body.SetBounds(15, 15, 530, 255)
  $yes = New-Object System.Windows.Forms.Button
  $yes.SetBounds(315, 285, 110, 32)
  $yes.Text = if ($Question) { Get-Text 'Yes' } else { Get-Text 'OK' }
  $yes.DialogResult = 'OK'
  $dialog.Controls.AddRange(@($body, $yes))
  $dialog.AcceptButton = $yes
  $dialog.CancelButton = $yes
  if ($Question) {
    $no = New-Object System.Windows.Forms.Button
    $no.SetBounds(435, 285, 110, 32)
    $no.Text = Get-Text 'No'
    $no.DialogResult = 'Cancel'
    $dialog.Controls.Add($no)
    $dialog.CancelButton = $no
    $dialog.AcceptButton = $no
  }
  $owner = Get-DialogOwner
  try {
    $result = if ($owner) { $dialog.ShowDialog($owner) } else { $dialog.ShowDialog() }
    return ($result -eq 'OK')
  } finally { $dialog.Dispose() }
}

function Show-Message {
  param([string]$Text, [string]$Title = (Get-Text 'AppTitle'), [string]$Icon = 'Information')
  [void](Show-LocalizedDialog -Text $Text -Title $Title -Icon $Icon)
}

function Ask-YesNo {
  param([string]$Text, [string]$Title = (Get-Text 'AppTitle'))
  return (Show-LocalizedDialog -Text $Text -Title $Title -Question)
}

function Show-InputDialog {
  # 自前の入力ダイアログ（VisualBasic の InputBox は親を持てず背面に隠れるため）
  param([string]$Prompt, [string]$Title = (Get-Text 'AppTitle'), [string]$Default = '')
  Ensure-Gui
  $owner = Get-DialogOwner

  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = $Title
  $dlg.FormBorderStyle = 'FixedDialog'
  $dlg.MaximizeBox = $false
  $dlg.MinimizeBox = $false
  $dlg.ShowInTaskbar = $false
  $dlg.TopMost = $true
  $dlg.StartPosition = $(if ($owner) { 'CenterParent' } else { 'CenterScreen' })
  $dlg.ClientSize = New-Object System.Drawing.Size(420, 130)
  $dlg.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)

  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Text = $Prompt
  $lbl.AutoSize = $false
  $lbl.Location = New-Object System.Drawing.Point(14, 12)
  $lbl.Size = New-Object System.Drawing.Size(392, 40)

  $tb = New-Object System.Windows.Forms.TextBox
  $tb.Location = New-Object System.Drawing.Point(14, 56)
  $tb.Size = New-Object System.Drawing.Size(392, 28)
  $tb.Text = $Default

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = Get-Text 'OK'
  $ok.Size = New-Object System.Drawing.Size(90, 30)
  $ok.Location = New-Object System.Drawing.Point(216, 92)
  $ok.DialogResult = 'OK'

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = (Get-Text 'Cancel')
  $cancel.Size = New-Object System.Drawing.Size(90, 30)
  $cancel.Location = New-Object System.Drawing.Point(316, 92)
  $cancel.DialogResult = 'Cancel'

  $dlg.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
  $dlg.AcceptButton = $ok
  $dlg.CancelButton = $cancel
  $dlg.add_Shown({ $this.Activate(); $tb.Focus(); $tb.SelectAll() })

  $result = $(if ($owner) { $dlg.ShowDialog($owner) } else { $dlg.ShowDialog() })
  $text = $tb.Text
  $dlg.Dispose()
  if ($result -eq 'OK') { return $text }
  return $null
}

function Get-SafeName {
  param([string]$Name)
  $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
  $re = '[{0}]' -f [regex]::Escape($invalid)
  $s = ($Name -replace $re, '_').Trim()
  $s = $s -replace '\s+', '_'
  if ([string]::IsNullOrWhiteSpace($s)) { $s = 'account' }
  return $s
}

# ------------------------------------------------------------------ アプリ検出

function Get-ChatGptApp {
  if ($script:AppCache) { return $script:AppCache }

  # Microsoft Store (MSIX) 版: OpenAI.Codex_2p2nqsd0c76g0  ※現在の「ChatGPT」デスクトップアプリ
  $pkg = $null
  try {
    if ($PSVersionTable.PSEdition -eq 'Core') { Import-Module Appx -UseWindowsPowerShell -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
      Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
  } catch {}

  if ($pkg) {
    $loc = $pkg.InstallLocation
    $exe = $null
    foreach ($cand in @((Join-Path $loc 'ChatGPT.exe'), (Join-Path $loc 'app\ChatGPT.exe'), (Join-Path $loc 'Codex.exe'))) {
      if (Test-Path -LiteralPath $cand) { $exe = $cand; break }
    }
    if (-not $exe) {
      $found = Get-ChildItem -LiteralPath $loc -Filter 'ChatGPT.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) { $exe = $found.FullName }
    }
    $appId = $null
    try {
      $manifest = Get-AppxPackageManifest -Package $pkg
      $appId = @($manifest.Package.Applications.Application)[0].Id
    } catch {}
    $script:AppCache = [pscustomobject]@{
      Kind              = 'Store'
      Exe               = $exe
      PackageFamilyName = $pkg.PackageFamilyName
      AppId             = $appId
      Version           = $pkg.Version
      InstallLocation   = $loc
    }
    return $script:AppCache
  }

  # 通常インストーラー版（念のため）
  foreach ($c in @(
      (Join-Path $env:LOCALAPPDATA 'Programs\ChatGPT\ChatGPT.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
      (Join-Path $env:ProgramFiles 'ChatGPT\ChatGPT.exe'))) {
    if (Test-Path -LiteralPath $c) {
      $script:AppCache = [pscustomobject]@{
        Kind = 'Installer'; Exe = $c; PackageFamilyName = $null; AppId = $null
        Version = (Get-Item -LiteralPath $c).VersionInfo.ProductVersion
        InstallLocation = (Split-Path -Parent $c)
      }
      return $script:AppCache
    }
  }
  return $null
}

# ------------------------------------------------------------------ 設定

function Get-Config {
  $cfg = $null
  if (Test-Path -LiteralPath $script:ConfigPath) {
    try {
      $raw = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
      $cfg = $raw | ConvertFrom-Json
    } catch { Write-Log "config read error: $_" }
  }
  if (-not $cfg) { $cfg = [pscustomobject]@{ accounts = @() } }
  if (-not ($cfg.PSObject.Properties.Name -contains 'accounts')) {
    $cfg | Add-Member -NotePropertyName accounts -NotePropertyValue @() -Force
  }
  $cfg.accounts = @($cfg.accounts | Where-Object { $_ -ne $null })
  return $cfg
}

function Save-Config {
  param($Config)
  New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
  $Config.accounts = @($Config.accounts)
  $json = ConvertTo-Json -InputObject $Config -Depth 5
  [System.IO.File]::WriteAllText($script:ConfigPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-AccountPaths {
  param([string]$Id)
  $base = Join-Path $script:Root $Id
  return [pscustomobject]@{
    Base     = $base
    Electron = (Join-Path $base 'electron')
    Codex    = (Join-Path $base 'codex')
  }
}

function Find-Account {
  param([string]$Key)   # ID でも表示名でもOK
  $cfg = Get-Config
  $acc = $cfg.accounts | Where-Object { $_.id -eq $Key } | Select-Object -First 1
  if (-not $acc) { $acc = $cfg.accounts | Where-Object { $_.display -eq $Key } | Select-Object -First 1 }
  if (-not $acc) { $acc = $cfg.accounts | Where-Object { $_.id -eq (Get-SafeName $Key) } | Select-Object -First 1 }
  return $acc
}

function Add-Account {
  param([string]$Display, [switch]$SkipShortcut, [switch]$Shared)
  $Display = $Display.Trim()
  if ([string]::IsNullOrWhiteSpace($Display)) { throw (Get-Text 'EmptyAccount') }
  $cfg = Get-Config
  if ($cfg.accounts | Where-Object { $_.display -eq $Display }) { throw (Get-Text 'DuplicateAccount' ($Display)) }
  $id = Get-SafeName $Display
  $n = 2
  while ($cfg.accounts | Where-Object { $_.id -eq $id }) { $id = (Get-SafeName $Display) + "_$n"; $n++ }
  $color = $script:Palette[ $cfg.accounts.Count % $script:Palette.Count ]
  $acc = [pscustomobject]@{
    id      = $id
    display = $Display
    color   = $color
    created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    mode    = $(if ($Shared) { 'shared' } else { 'isolated' })
  }
  $cfg.accounts = @($cfg.accounts) + @($acc)
  Save-Config $cfg
  $p = Get-AccountPaths $id
  New-Item -ItemType Directory -Force -Path $p.Electron, $p.Codex | Out-Null
  Write-Log "account added: $id ($Display)"
  if (-not $SkipShortcut) { New-AccountShortcut -Account $acc | Out-Null }
  Set-JumpList
  return $acc
}

function Remove-Account {
  param([string]$Key)
  $acc = Find-Account $Key
  if (-not $acc) { throw (Get-Text 'AccountNotFound' ($Key)) }
  if ((Get-RunningAccountIds) -contains $acc.id) { throw (Get-Text 'AccountRunning' ($($acc.display))) }
  $p = Get-AccountPaths $acc.id
  if (Test-Path -LiteralPath $p.Base) { Remove-Item -LiteralPath $p.Base -Recurse -Force }
  $cfg = Get-Config
  $cfg.accounts = @($cfg.accounts | Where-Object { $_.id -ne $acc.id })
  Save-Config $cfg
  $lnk = Get-AccountShortcutPath $acc
  if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
  Write-Log "account removed: $($acc.id)"
  Set-JumpList
}

function Rename-Account {
  param([string]$Key, [string]$NewDisplay)
  $acc = Find-Account $Key
  if (-not $acc) { throw (Get-Text 'AccountNotFound' ($Key)) }
  $NewDisplay = $NewDisplay.Trim()
  if ([string]::IsNullOrWhiteSpace($NewDisplay)) { return }
  $old = Get-AccountShortcutPath $acc
  $cfg = Get-Config
  foreach ($a in $cfg.accounts) { if ($a.id -eq $acc.id) { $a.display = $NewDisplay } }
  Save-Config $cfg
  if (Test-Path -LiteralPath $old) {
    Remove-Item -LiteralPath $old -Force
    New-AccountShortcut -Account (Find-Account $acc.id) | Out-Null
  }
  Set-JumpList
}

# ------------------------------------------------------------------ 起動

function Get-RunningAccountIds {
  $ids = @()
  $procs = @()
  try { $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" -ErrorAction SilentlyContinue) } catch {}
  if ($procs.Count -eq 0) { return $ids }
  $cfg = Get-Config
  foreach ($acc in $cfg.accounts) {
    $p = Get-AccountPaths $acc.id
    $hit = $procs | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($p.Electron, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1
    if ($hit) { $ids += $acc.id }
  }
  $mainHit = $procs | Where-Object {
    $_.CommandLine -and ($_.CommandLine -notmatch '--user-data-dir=') -and ($_.CommandLine -notmatch '--type=')
  } | Select-Object -First 1
  if ($mainHit) { $ids += $script:MainId }
  return $ids
}

function Start-Account {
  param([string]$Id)
  $app = Get-ChatGptApp
  if (-not $app) { throw (Get-Text 'InstallApp') }

  if ($Id -eq $script:MainId) {
    if ($app.Kind -eq 'Store' -and $app.AppId) {
      Start-Process -FilePath 'explorer.exe' -ArgumentList ("shell:AppsFolder\{0}!{1}" -f $app.PackageFamilyName, $app.AppId)
    } else {
      Start-Process -FilePath $app.Exe
    }
    Write-Log 'launched: main'
    return
  }

  $acc = Find-Account $Id
  if (-not $acc) { throw (Get-Text 'AccountNotRegistered' ($Id)) }

  # 完全共有モード: 実の ~/.codex を使い、auth.json だけ差し替える（1アカウントずつ）
  if ($acc.mode -eq 'shared') { Start-SharedAccount -Account $acc; return }

  if (-not $app.Exe) { throw (Get-Text 'ExeNotFound' ($($app.InstallLocation))) }

  $p = Get-AccountPaths $acc.id
  New-Item -ItemType Directory -Force -Path $p.Electron, $p.Codex | Out-Null

  # アカウント分離の要: Electron のユーザーデータ (Cookie/ログイン) と Codex のホーム
  $env:CODEX_HOME = $p.Codex
  $env:CODEX_ELECTRON_USER_DATA_PATH = $p.Electron
  $arg = '--user-data-dir="' + $p.Electron + '"'

  try {
    Start-Process -FilePath $app.Exe -ArgumentList $arg -WorkingDirectory $p.Base
    Write-Log "launched: $($acc.id) via direct exe"
  } catch {
    Write-Log "direct launch failed: $_"
    if ($app.Kind -eq 'Store' -and $app.AppId -and (Get-Command Invoke-CommandInDesktopPackage -ErrorAction SilentlyContinue)) {
      Invoke-CommandInDesktopPackage -PackageFamilyName $app.PackageFamilyName -AppId $app.AppId -Command $app.Exe -Args $arg -PreventBreakaway
      Write-Log "launched: $($acc.id) via Invoke-CommandInDesktopPackage"
    } else { throw }
  }
}

# ------------------------------------------------------------------ 完全共有モード（実 ~/.codex + auth.json 差し替え）

function Get-RealCodexHome { return (Join-Path $env:USERPROFILE '.codex') }

function Get-SharedAuthStore { param($Account) return (Join-Path (Get-AccountPaths $Account.id).Base 'shared-auth.json') }

# 実ホーム(~/.codex)を使う ChatGPT.exe が動いているか（= --user-data-dir なし・--type= なし）
function Test-RealHomeInstanceRunning {
  try { $procs = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue) } catch { return $false }
  foreach ($pr in $procs) {
    if ($pr.CommandLine -and ($pr.CommandLine -notmatch '--user-data-dir=') -and ($pr.CommandLine -notmatch '--type=')) { return $true }
  }
  return $false
}

function Get-ActiveShared {
  $cfg = Get-Config
  if ($cfg.PSObject.Properties.Name -contains 'activeShared') { return $cfg.activeShared }
  return $null
}
function Set-ActiveShared {
  param([string]$Id)
  $cfg = Get-Config
  $cfg | Add-Member -NotePropertyName activeShared -NotePropertyValue $Id -Force
  Save-Config $cfg
}

# 現在の ~/.codex/auth.json を、指定アカウントの保存先に取り込む（ログイン後の保存にも使う）
function Save-CurrentAuthToAccount {
  param($Account)
  $realAuth = Join-Path (Get-RealCodexHome) 'auth.json'
  if (-not (Test-Path -LiteralPath $realAuth)) { throw (Get-Text 'LoginFirst') }
  $store = Get-SharedAuthStore $Account
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $store) | Out-Null
  Copy-Item -LiteralPath $realAuth -Destination $store -Force
  Set-ActiveShared $Account.id
  Write-Log "shared: saved current auth as $($Account.id)"
}

function Start-SharedAccount {
  param($Account)
  $app  = Get-ChatGptApp
  if (-not $app) { throw (Get-Text 'AppNotFound') }
  $real = Get-RealCodexHome
  $realAuth = Join-Path $real 'auth.json'
  New-Item -ItemType Directory -Force -Path $real, (Get-AccountPaths $Account.id).Base | Out-Null

  if (Test-RealHomeInstanceRunning) {
    throw (Get-Text 'SharedAlreadyRunning')
  }

  $active = Get-ActiveShared

  if (Test-Path -LiteralPath $realAuth) {
    # 必ずバックアップ（失敗時の復帰用）
    Copy-Item -LiteralPath $realAuth -Destination (Join-Path $real 'auth.json.switcher-bak') -Force
    # 直前にアクティブだった共有アカウントの保存先へ、現在のauth（ログイン更新）を取り込む
    if ($active -and $active -ne $Account.id) {
      $prev = Find-Account $active
      if ($prev -and $prev.mode -eq 'shared') {
        Copy-Item -LiteralPath $realAuth -Destination (Get-SharedAuthStore $prev) -Force
        Write-Log "shared: captured current auth into $($prev.id)"
      }
    }
  }

  # ターゲットの保存authがあれば実ホームへ展開。無ければ現状のまま（初回：ログイン後に保存する）
  $store = Get-SharedAuthStore $Account
  if (Test-Path -LiteralPath $store) {
    Copy-Item -LiteralPath $store -Destination $realAuth -Force
    Write-Log "shared: restored auth for $($Account.id)"
  } else {
    Write-Log "shared: no saved auth for $($Account.id); launching with current login"
  }
  Set-ActiveShared $Account.id

  # 実ホーム＝実Electronで通常起動（環境変数は上書きしない）
  Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
  Remove-Item Env:CODEX_ELECTRON_USER_DATA_PATH -ErrorAction SilentlyContinue
  if ($app.Kind -eq 'Store' -and $app.AppId) {
    Start-Process -FilePath 'explorer.exe' -ArgumentList ("shell:AppsFolder\{0}!{1}" -f $app.PackageFamilyName, $app.AppId)
  } else {
    Start-Process -FilePath $app.Exe
  }
  Write-Log "launched shared: $($Account.id)"
}

# ------------------------------------------------------------------ ショートカット

function Get-PowerShellExe {
  return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

# ------------------------------------------------------------------ ネイティブ（AppID / ジャンプリスト）

function Ensure-Native {
  if ('CGS.Native' -as [type]) { return $true }
  $code = @'
using System;
using System.Runtime.InteropServices;
namespace CGS {
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class CShellLink { }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
  interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder f, int c, IntPtr fd, int fl);
    void GetIDList(out IntPtr ppidl); void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder n, int c);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string n);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder d, int c);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string d);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder a, int c);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string a);
    void GetHotkey(out short h); void SetHotkey(short h);
    void GetShowCmd(out int s); void SetShowCmd(int s);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder p, int c, out int i);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string p, int i);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string r, int dw);
    void Resolve(IntPtr hwnd, int fl); void SetPath([MarshalAs(UnmanagedType.LPWStr)] string f);
  }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0000010b-0000-0000-C000-000000000046")]
  interface IPersistFile {
    void GetClassID(out Guid c); [PreserveSig] int IsDirty();
    void Load([MarshalAs(UnmanagedType.LPWStr)] string f, int m);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string f, [MarshalAs(UnmanagedType.Bool)] bool r);
    void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string f);
    void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string f);
  }
  [StructLayout(LayoutKind.Sequential)] struct PROPERTYKEY { public Guid fmtid; public uint pid; }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99")]
  interface IPropertyStore {
    void GetCount(out uint c); void GetAt(uint i, out PROPERTYKEY k);
    void GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
    void SetValue(ref PROPERTYKEY k, ref PROPVARIANT v); void Commit();
  }
  [StructLayout(LayoutKind.Explicit, Size = 24)] struct PROPVARIANT {
    [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p;
  }
  public static class Native {
    [DllImport("shell32.dll")] static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);
    [DllImport("propsys.dll")] static extern int InitPropVariantFromString([MarshalAs(UnmanagedType.LPWStr)] string s, out PROPVARIANT pv);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);
    public static void SetProcessAppId(string id) { SetCurrentProcessExplicitAppUserModelID(id); }
    public static void SetShortcutAppId(string lnk, string id) {
      var sl = (IShellLinkW)new CShellLink();
      var pf = (IPersistFile)sl;
      pf.Load(lnk, 2); // STGM_READWRITE
      var ps = (IPropertyStore)sl;
      var key = new PROPERTYKEY(); key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); key.pid = 5;
      PROPVARIANT pv; InitPropVariantFromString(id, out pv);
      ps.SetValue(ref key, ref pv); ps.Commit();
      pf.Save(lnk, true); PropVariantClear(ref pv);
    }
  }
}
'@
  try { Add-Type -TypeDefinition $code -ErrorAction Stop; return $true }
  catch { Write-Log ("native load failed: {0}" -f $_.Exception.Message); return $false }
}

function Set-ProcessAppId {
  try { if (Ensure-Native) { [CGS.Native]::SetProcessAppId($script:AppId) } } catch { Write-Log "SetProcessAppId: $_" }
}

function Set-ShortcutAppId {
  param([string]$LnkPath)
  try { if (Ensure-Native) { [CGS.Native]::SetShortcutAppId($LnkPath, $script:AppId) } } catch { Write-Log "SetShortcutAppId: $_" }
}

# 右クリック（ジャンプリスト）にアカウント一覧を出す
function Set-JumpList {
  try {
    Set-ProcessAppId
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    $ps   = Get-PowerShellExe
    $icon = Get-AppIconPath
    $jl = New-Object System.Windows.Shell.JumpList
    $jl.ShowRecentCategory = $false
    $jl.ShowFrequentCategory = $false

    $rows = @()
    $rows += [pscustomobject]@{ id = $script:MainId; label = (Get-Text 'Main') }
    foreach ($a in (Get-Config).accounts) { $rows += [pscustomobject]@{ id = $a.id; label = $a.display } }

    foreach ($r in $rows) {
      $t = New-Object System.Windows.Shell.JumpTask
      $t.Title           = $r.label
      $t.CustomCategory  = (Get-Text 'Accounts')
      $t.ApplicationPath = $ps
      $t.Arguments       = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Launch "{1}"' -f $script:ScriptPath, $r.id)
      if ($icon) { $t.IconResourcePath = $icon }
      $t.Description = ((Get-Text 'OpenAs') -f $r.label)
      $jl.JumpItems.Add($t)
    }

    # 一覧ウィンドウを開くタスク
    $open = New-Object System.Windows.Shell.JumpTask
    $open.Title = (Get-Text 'OpenPicker')
    $open.ApplicationPath = $ps
    $open.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script:ScriptPath)
    if ($icon) { $open.IconResourcePath = $icon }
    $jl.JumpItems.Add($open)

    $jl.Apply()
    Write-Log ("jumplist applied: {0} items" -f $jl.JumpItems.Count)
  } catch { Write-Log ("jumplist skipped: {0}" -f $_.Exception.Message) }
}

function New-Shortcut {
  param([string]$LnkPath, [string]$Arguments, [string]$IconPath, [string]$Description)
  $dir = Split-Path -Parent $LnkPath
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $wsh = New-Object -ComObject WScript.Shell
  $lnk = $wsh.CreateShortcut($LnkPath)
  $lnk.TargetPath = Get-PowerShellExe
  $lnk.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" {1}' -f $script:ScriptPath, $Arguments)
  $lnk.WorkingDirectory = Split-Path -Parent $script:ScriptPath
  $lnk.WindowStyle = 7   # 最小化で起動（コンソールのチラつき防止）
  if ($IconPath -and (Test-Path -LiteralPath $IconPath)) { $lnk.IconLocation = "$IconPath,0" }
  if ($Description) { $lnk.Description = $Description }
  $lnk.Save()
  return $LnkPath
}

function Get-AppIconPath {
  $app = Get-ChatGptApp
  if ($app -and $app.Exe) { return $app.Exe }
  return $null
}

function Get-AccountShortcutPath {
  param($Account)
  $desktop = [Environment]::GetFolderPath('Desktop')
  return (Join-Path $desktop ('ChatGPT - {0}.lnk' -f (Get-SafeName $Account.display)))
}

function New-AccountShortcut {
  param($Account)
  $lnk = Get-AccountShortcutPath $Account
  New-Shortcut -LnkPath $lnk -Arguments ('-Launch "{0}"' -f $Account.id) -IconPath (Get-AppIconPath) -Description ((Get-Text 'LaunchAs') -f $Account.display)
  Write-Log "shortcut created: $lnk"
  return $lnk
}

function New-PickerShortcuts {
  $icon = Get-AppIconPath
  $desktop = [Environment]::GetFolderPath('Desktop')
  $programs = Join-Path ([Environment]::GetFolderPath('Programs')) 'ChatGPT アカウント切替'
  $made = @()
  $made += New-Shortcut -LnkPath (Join-Path $desktop 'ChatGPT アカウント切替.lnk') -Arguments '' -IconPath $icon -Description (Get-Text 'ChooseAccount')
  $made += New-Shortcut -LnkPath (Join-Path $programs 'ChatGPT アカウント切替.lnk') -Arguments '' -IconPath $icon -Description (Get-Text 'ChooseAccount')
  $made += New-Shortcut -LnkPath (Join-Path $programs 'ChatGPT 切替（トレイ常駐）.lnk') -Arguments '-Tray' -IconPath $icon -Description (Get-Text 'TrayDescription')
  # ピン留めした切替アイコンを右クリック→アカウント一覧（ジャンプリスト）を出すための AppID を付与
  foreach ($m in $made) { Set-ShortcutAppId -LnkPath $m }
  Set-JumpList
  return $made
}

function Install-TrayAutoStart {
  $startup = [Environment]::GetFolderPath('Startup')
  return New-Shortcut -LnkPath (Join-Path $startup 'ChatGPT 切替（トレイ常駐）.lnk') -Arguments '-Tray' -IconPath (Get-AppIconPath) -Description (Get-Text 'TrayTitle')
}

# ------------------------------------------------------------------ GUI: ピッカー

function New-AvatarImage {
  param([string]$Hex, [string]$Text, [int]$Size = 28)
  Ensure-Gui
  $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
  $color = [System.Drawing.ColorTranslator]::FromHtml($Hex)
  $brush = New-Object System.Drawing.SolidBrush($color)
  $g.FillEllipse($brush, 0, 0, $Size - 1, $Size - 1)
  $font = New-Object System.Drawing.Font('Yu Gothic UI', [float]($Size * 0.45), [System.Drawing.FontStyle]::Bold)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
  $g.DrawString($Text, $font, [System.Drawing.Brushes]::White, $rect, $fmt)
  $g.Dispose()
  return $bmp
}

function Invoke-AddAccountFlow {
  Ensure-Gui
  $name = Show-InputDialog -Prompt (Get-Text 'AccountNamePrompt') -Title (Get-Text 'AddAccount')
  if ([string]::IsNullOrWhiteSpace($name)) { return $null }
  # モード選択: 分離（同時起動OK・各自のプロジェクト） / 完全共有（1つずつ・プロジェクト共有）
  $shared = Ask-YesNo ((Get-Text 'ModePrompt') -f $name) (Get-Text 'SharedModeQuestion')
  try {
    $acc = Add-Account -Display $name -Shared:$shared
  } catch {
    Show-Message $_.Exception.Message (Get-Text 'Error') 'Error'
    return $null
  }
  if ($acc.mode -eq 'shared') {
    if (Ask-YesNo ((Get-Text 'SharedAdded') -f $acc.display)) {
      try { Start-Account $acc.id } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' }
    }
  } else {
    if (Ask-YesNo ((Get-Text 'IsolatedAdded') -f $acc.display)) {
      try { Start-Account $acc.id } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' }
    }
  }
  return $acc
}

function Show-Picker {
  Ensure-Gui
  Set-JumpList

  $form = New-Object System.Windows.Forms.Form
  $form.Text = (Get-Text 'AppTitle')
  $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false
  $form.ShowInTaskbar = $true
  $form.KeyPreview = $true
  # 常時最前面にはしない（入力ダイアログが裏に隠れる原因になる）。表示時に一度だけ前面へ。
  $form.add_Shown({ $this.Activate(); $this.TopMost = $true; $this.TopMost = $false; $this.BringToFront() })
  $form.AutoSize = $true
  $form.AutoSizeMode = 'GrowAndShrink'
  $form.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)
  $form.BackColor = [System.Drawing.Color]::White
  $form.Padding = New-Object System.Windows.Forms.Padding(12)
  $iconPath = Get-AppIconPath
  if ($iconPath) { try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch {} }

  $script:PickerForm = $form

  $header = New-Object System.Windows.Forms.Label
  $header.Text = (Get-Text 'PickerHeading')
  $header.Font = New-Object System.Drawing.Font('Yu Gothic UI', 12, [System.Drawing.FontStyle]::Bold)
  $header.AutoSize = $true
  $header.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 8)

  $panel = New-Object System.Windows.Forms.FlowLayoutPanel
  $panel.FlowDirection = 'TopDown'
  $panel.WrapContents = $false
  $panel.AutoSize = $true
  $panel.AutoSizeMode = 'GrowAndShrink'
  $script:PickerPanel = $panel

  $footer = New-Object System.Windows.Forms.FlowLayoutPanel
  $footer.FlowDirection = 'LeftToRight'
  $footer.AutoSize = $true
  $footer.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)

  $btnAdd = New-Object System.Windows.Forms.Button
  $btnAdd.Text = (Get-Text 'AddAccountButton')
  $btnAdd.AutoSize = $true
  $btnAdd.Height = 34
  $btnAdd.FlatStyle = 'System'
  $btnAdd.add_Click({ if (Invoke-AddAccountFlow) { Update-PickerRows } })

  $btnMenu = New-Object System.Windows.Forms.Button
  $btnMenu.Text = (Get-Text 'Settings')
  $btnMenu.AutoSize = $true
  $btnMenu.Height = 34
  $btnMenu.FlatStyle = 'System'
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  [void]$menu.Items.Add((Get-Text 'Language'), $null, {
    if (Show-LanguageSelector) { $script:PickerForm.Tag = 'LanguageChanged'; $script:PickerForm.Close() }
  })
  [void]$menu.Items.Add((Get-Text 'CreatePickerShortcuts'), $null, { try { New-PickerShortcuts | Out-Null; Show-Message (Get-Text 'ShortcutsCreated') } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' } })
  [void]$menu.Items.Add((Get-Text 'StartTray'), $null, { Start-Process -FilePath (Get-PowerShellExe) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Tray' -f $script:ScriptPath) })
  [void]$menu.Items.Add((Get-Text 'AutoStartTray'), $null, { try { Install-TrayAutoStart | Out-Null; Show-Message (Get-Text 'StartupRegistered') } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' } })
  [void]$menu.Items.Add('-')
  [void]$menu.Items.Add((Get-Text 'OpenDataFolder'), $null, { New-Item -ItemType Directory -Force -Path $script:Root | Out-Null; Start-Process explorer.exe $script:Root })
  [void]$menu.Items.Add((Get-Text 'Diagnostics'), $null, { Start-Process -FilePath (Get-PowerShellExe) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Diagnose' -f $script:ScriptPath) })
  $btnMenu.add_Click({ $menu.Show($btnMenu, (New-Object System.Drawing.Point(0, $btnMenu.Height))) })

  $footer.Controls.Add($btnAdd)
  $footer.Controls.Add($btnMenu)

  $outer = New-Object System.Windows.Forms.FlowLayoutPanel
  $outer.FlowDirection = 'TopDown'
  $outer.WrapContents = $false
  $outer.AutoSize = $true
  $outer.AutoSizeMode = 'GrowAndShrink'
  $outer.Controls.Add($header)
  $outer.Controls.Add($panel)
  $outer.Controls.Add($footer)
  $form.Controls.Add($outer)

  $form.add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $script:PickerForm.Close() } })

  Update-PickerRows
  [void]$form.ShowDialog()
  $changeLanguage = ($form.Tag -eq 'LanguageChanged')
  $form.Dispose()
  if ($changeLanguage) { Show-Picker }
}

function Update-PickerRows {
  $panel = $script:PickerPanel
  $panel.SuspendLayout()
  $panel.Controls.Clear()
  $running = Get-RunningAccountIds
  $cfg = Get-Config

  $rows = @()
  $rows += [pscustomobject]@{ id = $script:MainId; display = $script:MainLabel; color = '#10A37F'; initial = 'M'; mode = 'isolated' }
  foreach ($a in $cfg.accounts) {
    $m = if ($a.PSObject.Properties.Name -contains 'mode') { $a.mode } else { 'isolated' }
    $rows += [pscustomobject]@{ id = $a.id; display = $a.display; color = $a.color; initial = $a.display.Substring(0, 1); mode = $m }
  }

  foreach ($r in $rows) {
    $btn = New-Object System.Windows.Forms.Button
    $isRunning = ($running -contains $r.id)
    $badge = $(if ($r.mode -eq 'shared') { (Get-Text 'SharedBadge') } else { '' })
    $btn.Text = '   ' + $r.display + $badge + $(if ($isRunning) { (Get-Text 'RunningBadge') } else { '' })
    $btn.Tag = $r.id
    $btn.Width = 400
    $btn.Height = 46
    $btn.TextAlign = 'MiddleLeft'
    $btn.ImageAlign = 'MiddleLeft'
    $btn.TextImageRelation = 'ImageBeforeText'
    $btn.Image = New-AvatarImage -Hex $r.color -Text $r.initial
    $btn.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $btn.BackColor = [System.Drawing.Color]::White
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Margin = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
    if ($isRunning) { $btn.ForeColor = [System.Drawing.Color]::FromArgb(16, 163, 127) }

    $btn.add_Click({
      try {
        Start-Account $this.Tag
        $script:PickerForm.Close()
      } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' }
    })

    if ($r.id -ne $script:MainId) {
      $cm = New-Object System.Windows.Forms.ContextMenuStrip
      $cm.Tag = $r.id
      if ($r.mode -eq 'shared') {
        $miSave = $cm.Items.Add((Get-Text 'SaveLogin'))
        $miSave.Tag = $r.id
        $miSave.add_Click({
          $acc = Find-Account $this.Tag
          if (Ask-YesNo ((Get-Text 'SaveLoginQuestion') -f $acc.display)) {
            try { Save-CurrentAuthToAccount $acc; Show-Message ((Get-Text 'LoginSaved') -f $acc.display) } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' }
          }
        })
        [void]$cm.Items.Add('-')
      }
      $mi1 = $cm.Items.Add((Get-Text 'CreateDesktopShortcut'))
      $mi1.Tag = $r.id
      $mi1.add_Click({ try { New-AccountShortcut -Account (Find-Account $this.Tag) | Out-Null; Show-Message (Get-Text 'DesktopShortcutCreated') } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' } })
      $mi2 = $cm.Items.Add((Get-Text 'Rename'))
      $mi2.Tag = $r.id
      $mi2.add_Click({
        $acc = Find-Account $this.Tag
        $n = Show-InputDialog -Prompt (Get-Text 'RenamePrompt') -Title (Get-Text 'Rename') -Default $acc.display
        if (-not [string]::IsNullOrWhiteSpace($n)) { try { Rename-Account $this.Tag $n; Update-PickerRows } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' } }
      })
      $mi3 = $cm.Items.Add((Get-Text 'RemoveAccount'))
      $mi3.Tag = $r.id
      $mi3.add_Click({
        $acc = Find-Account $this.Tag
        if (Ask-YesNo ((Get-Text 'RemoveAccountQuestion') -f $acc.display)) {
          try { Remove-Account $this.Tag; Update-PickerRows } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' }
        }
      })
      $btn.ContextMenuStrip = $cm
    }
    $panel.Controls.Add($btn)
  }

  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = (Get-Text 'PickerHint')
  $hint.MaximumSize = New-Object System.Drawing.Size(420, 0)
  $hint.AutoSize = $true
  $hint.ForeColor = [System.Drawing.Color]::Gray
  $hint.Font = New-Object System.Drawing.Font('Yu Gothic UI', 8.5)
  $hint.Margin = New-Object System.Windows.Forms.Padding(6, 6, 4, 0)
  $panel.Controls.Add($hint)

  $panel.ResumeLayout()
}

# ------------------------------------------------------------------ GUI: トレイ常駐

function Start-Tray {
  Ensure-Gui
  Set-JumpList
  $ni = New-Object System.Windows.Forms.NotifyIcon
  $iconPath = Get-AppIconPath
  $ni.Icon = [System.Drawing.SystemIcons]::Application
  if ($iconPath) { try { $ni.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch {} }
  $ni.Text = (Get-Text 'AppTitle')
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $menu.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)

  $menu.add_Opening({
    $ni.Text = Get-Text 'AppTitle'
    $m = $this
    $m.Items.Clear()
    $running = Get-RunningAccountIds
    $head = $m.Items.Add((Get-Text 'OpenChatGPT'))
    $head.Enabled = $false
    $mainItem = $m.Items.Add($script:MainLabel + $(if ($running -contains $script:MainId) { (Get-Text 'TrayRunning') } else { '' }))
    $mainItem.Tag = $script:MainId
    $mainItem.Image = New-AvatarImage -Hex '#10A37F' -Text 'M' -Size 20
    $mainItem.add_Click({ try { Start-Account $this.Tag } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' } })
    foreach ($a in (Get-Config).accounts) {
      $it = $m.Items.Add($a.display + $(if ($running -contains $a.id) { (Get-Text 'TrayRunning') } else { '' }))
      $it.Tag = $a.id
      $it.Image = New-AvatarImage -Hex $a.color -Text $a.display.Substring(0, 1) -Size 20
      $it.add_Click({ try { Start-Account $this.Tag } catch { Show-Message $_.Exception.Message (Get-Text 'Error') 'Error' } })
    }
    [void]$m.Items.Add('-')
    $add = $m.Items.Add((Get-Text 'AddAccountButton'))
    $add.add_Click({ Invoke-AddAccountFlow | Out-Null })
    $pick = $m.Items.Add((Get-Text 'OpenPicker'))
    $pick.add_Click({ Show-Picker })
    [void]$m.Items.Add('-')
    $quit = $m.Items.Add((Get-Text 'ExitTray'))
    $quit.add_Click({ [System.Windows.Forms.Application]::Exit() })
  })

  $ni.ContextMenuStrip = $menu
  $ni.add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Show-Picker } })
  $ni.Visible = $true
  Write-Log 'tray started'
  try {
    [System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
  } finally {
    $ni.Visible = $false
    $ni.Dispose()
  }
}

# ------------------------------------------------------------------ 診断

function Show-Diagnose {
  Write-Host (Get-Text 'DiagnosticHeading') -ForegroundColor Cyan
  Write-Host ((Get-Text 'Version') -f $script:AppVersion)
  Write-Host ((Get-Text 'Script') -f $script:ScriptPath)
  Write-Host ((Get-Text 'DataFolder') -f $script:Root)
  Write-Host ("PowerShell   : {0}" -f $PSVersionTable.PSVersion)
  Write-Host ("OS           : {0}" -f [Environment]::OSVersion.VersionString)
  Write-Host ''
  $app = Get-ChatGptApp
  if (-not $app) {
    Write-Host (Get-Text 'AppNotFoundDiagnostic') -ForegroundColor Red
  } else {
    Write-Host (Get-Text 'DesktopApp') -ForegroundColor Green
    Write-Host ((Get-Text 'AppKind') -f $app.Kind)
    Write-Host ((Get-Text 'AppVersion') -f $app.Version)
    Write-Host ((Get-Text 'AppLocation') -f $app.InstallLocation)
    Write-Host ("  EXE       : {0}" -f $(if ($app.Exe) { $app.Exe } else { (Get-Text 'NotFound') }))
    Write-Host ("  PFN       : {0}" -f $app.PackageFamilyName)
    Write-Host ("  AppId     : {0}" -f $app.AppId)
    if ($app.Exe) {
      try { $null = [System.IO.File]::OpenRead($app.Exe).Dispose(); Write-Host (Get-Text 'ExeReadable') } catch { Write-Host (Get-Text 'ExeReadFailed' ($_)) -ForegroundColor Yellow }
    }
  }
  Write-Host ''
  Write-Host ((Get-Text 'DefaultCodexHome') -f (Join-Path $env:USERPROFILE '.codex'), (Test-Path (Join-Path $env:USERPROFILE '.codex')))
  $stock = Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Roaming\Codex'
  Write-Host ((Get-Text 'DefaultElectronData') -f $stock, (Test-Path $stock))
  Write-Host ''
  $running = Get-RunningAccountIds
  $cfg = Get-Config
  $active = Get-ActiveShared
  Write-Host ((Get-Text 'AccountSummary') -f $cfg.accounts.Count, $(if ($active) { $active } else { (Get-Text 'None') })) -ForegroundColor Cyan
  Write-Host ("  [main] {0}{1}" -f $script:MainLabel, $(if ($running -contains $script:MainId) { (Get-Text 'TrayRunning') } else { '' }))
  foreach ($a in $cfg.accounts) {
    $p = Get-AccountPaths $a.id
    $m = if ($a.PSObject.Properties.Name -contains 'mode') { $a.mode } else { 'isolated' }
    Write-Host ("  [{0}] {1}  <{2}>{3}" -f $a.id, $a.display, $m, $(if ($running -contains $a.id) { (Get-Text 'TrayRunning') } else { '' }))
    if ($m -eq 'shared') {
      $store = Get-SharedAuthStore $a
      Write-Host ((Get-Text 'SharedAuth') -f $store, (Test-Path $store))
    } else {
      Write-Host ("      electron: {0}" -f $p.Electron)
      Write-Host ("      codex   : {0}" -f $p.Codex)
    }
  }
  Write-Host ''
  Write-Host (Get-Text 'Processes') -ForegroundColor Cyan
  try {
    Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object { $_.CommandLine -notmatch '--type=' } |
      ForEach-Object { Write-Host ("  PID {0}: {1}" -f $_.ProcessId, $_.CommandLine) }
  } catch { Write-Host (Get-Text 'ProcessQueryFailed' ($_)) }
  Write-Host ''
  Write-Host ((Get-Text 'Log') -f $script:LogPath)
}

# ------------------------------------------------------------------ エントリ

try {
  if ($Version) { Write-Host ("ChatGPT-Switcher {0}" -f $script:AppVersion); return }

  $cfg = Get-Config
  $savedLanguage = 'ja'
  if ($cfg.PSObject.Properties.Name -contains 'language' -and $cfg.language -in @('ja','en')) {
    $savedLanguage = $cfg.language
  }
  Set-InterfaceLanguage $savedLanguage
  if ($Language) { Set-InterfaceLanguage $Language }
  # Noninteractive commands use the saved language, or an explicit override.
  if (-not $Language -and -not ($Diagnose -or $List -or $Add -or $Remove -or $SaveAuth -or $Setup -or $AutoStartTray)) {
    if (-not (Show-LanguageSelector)) { return }
  }
  if ($Diagnose) { Show-Diagnose; return }

  if ($List) {
    $running = Get-RunningAccountIds
    $cfg = Get-Config
    Write-Host ("[{0}] {1}{2}" -f $script:MainId, $script:MainLabel, $(if ($running -contains $script:MainId) { (Get-Text 'Running') } else { '' }))
    foreach ($a in $cfg.accounts) {
      Write-Host ("[{0}] {1}{2}" -f $a.id, $a.display, $(if ($running -contains $a.id) { (Get-Text 'Running') } else { '' }))
    }
    return
  }

  if ($Add) {
    $acc = Add-Account -Display $Add -SkipShortcut:$NoShortcut -Shared:$Shared
    Write-Host ((Get-Text 'Added') -f $acc.id, $acc.display, $(if ($acc.mode -eq 'shared') { (Get-Text 'Shared') } else { '' }))
    Write-Host ((Get-Text 'LaunchCommand') -f $acc.id)
    if ($acc.mode -eq 'shared') {
      Write-Host (Get-Text 'SaveLoginInstructions')
      Write-Host ("  ChatGPT-Switcher.ps1 -SaveAuth {0}" -f $acc.id)
    }
    return
  }

  if ($SaveAuth) {
    $acc = Find-Account $SaveAuth
    if (-not $acc) { throw (Get-Text 'SaveAccountNotFound' ($SaveAuth)) }
    if ($acc.mode -ne 'shared') { throw (Get-Text 'NotShared' ($($acc.display))) }
    Save-CurrentAuthToAccount $acc
    Write-Host ((Get-Text 'CurrentLoginSaved') -f $acc.display)
    return
  }

  if ($Remove) { Remove-Account $Remove; Write-Host (Get-Text 'Removed' ($Remove)); return }

  if ($Setup) {
    $made = New-PickerShortcuts
    $made | ForEach-Object { Write-Host (Get-Text 'Created' ($_)) }
    $msg = (Get-Text 'ShortcutsCreatedPrefix') + ($made -join "`n") + (Get-Text 'PinInstructions')
    Write-Host $msg
    if (-not $NoShortcut) { Show-Message $msg }
    return
  }

  if ($AutoStartTray) { $lnk = Install-TrayAutoStart; Write-Host (Get-Text 'StartupPath' ($lnk)); return }

  if ($Tray) { Start-Tray; return }

  if ($Launch) { Start-Account $Launch; return }

  Show-Picker
} catch {
  Write-Log ("ERROR: {0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
  if ($Diagnose -or $List -or $Add -or $Remove) {
    Write-Host ((Get-Text 'ErrorPrefix') -f $_.Exception.Message) -ForegroundColor Red
    exit 1
  }
  Show-Message ((Get-Text 'ErrorDetails') -f $_.Exception.Message, $script:LogPath) (Get-Text 'AppTitle') 'Error'
  exit 1
}
