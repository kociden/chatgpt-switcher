# Run with: powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/Localization.Tests.ps1
# No Pester dependency. UI actions use temporary account data and never launch ChatGPT.
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repoPath 'ChatGPT-Switcher.ps1'
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
# Load definitions without running the application's entry point.
$source = [IO.File]::ReadAllText($path)
$entry = $source.LastIndexOf("`ntry {")
if ($entry -lt 0) { throw 'Entry point not found' }
$definitionsStart = $source.IndexOf('$ErrorActionPreference =')
Invoke-Expression $source.Substring($definitionsStart, $entry - $definitionsStart)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('switcher-localization-' + [guid]::NewGuid())
$script:Root = $testRoot
$script:ConfigPath = Join-Path $testRoot 'accounts.json'
$script:LogPath = Join-Path $testRoot 'switcher.log'
function Assert-True { param($Condition, $Message) if (-not $Condition) { throw $Message } }
function Set-ProcessAppId {}
function Set-JumpList {}
function Get-AppIconPath { return $null }
function Get-RunningAccountIds { return @() }
Ensure-Gui

# Every modal test has a timeout so a regression cannot leave an unattended dialog open.
function Invoke-UiTest {
  param([scriptblock]$Open, [scriptblock]$Inspect)
  $script:UiFailure = $null
  $script:UiObserved = $false
  $script:UiInspect = $Inspect
  $script:UiDeadline = [DateTime]::UtcNow.AddSeconds(10)
  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = 100
  $timer.add_Tick({
    $forms = @([System.Windows.Forms.Application]::OpenForms)
    if ($forms.Count) {
      $form = $forms[-1]
      try {
        $script:UiObserved = $true
        & $script:UiInspect $form
      } catch { $script:UiFailure = $_; $form.Close() }
      if ([DateTime]::UtcNow -gt $script:UiDeadline) {
        $script:UiFailure = 'UI test timed out'
        $form.Close()
      }
    }
  })
  $timer.Start()
  try { & $Open } finally { $timer.Stop(); $timer.Dispose() }
  Assert-True $script:UiObserved 'Dialog did not open'
  if ($script:UiFailure) { throw $script:UiFailure }
}

try {
  $cfg = [pscustomobject]@{ accounts = @([pscustomobject]@{ id='test'; display='Test Account'; color='#4285F4'; mode='isolated' }); activeShared='unchanged' }
  Save-Config $cfg
  foreach ($code in @('ja', 'en')) {
    Set-InterfaceLanguage $code
    foreach ($property in $script:Translations.PSObject.Properties) {
      $value = $property.Value.$code
      Assert-True (-not [string]::IsNullOrWhiteSpace($value)) "Missing $code/$($property.Name)"
      $null = $value -f 'Sample', 'Sample', 'Sample'
      # Both translations must interpolate the same arguments.
      $jaSlots = @([regex]::Matches($property.Value.ja, '\{\d+\}') | ForEach-Object { $_.Value }) -join ','
      $enSlots = @([regex]::Matches($property.Value.en, '\{\d+\}') | ForEach-Object { $_.Value }) -join ','
      Assert-True ($jaSlots -eq $enSlots) "Placeholder mismatch: $($property.Name)"
    }
    Assert-True ((Get-Text 'DuplicateAccount' 'Sample') -match 'Sample') 'Interpolation failed'
    $script:TargetLanguage = $code
    Invoke-UiTest { $script:Selected = Show-LanguageSelector } {
      param($form)
      $combo = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] }
      $combo.SelectedIndex = [Array]::IndexOf(@('ja', 'en'), $script:TargetLanguage)
      $form.AcceptButton.PerformClick()
    }
    Assert-True $script:Selected 'Selection was cancelled'
    Assert-True ((Get-Config).language -eq $code) 'Language not persisted'
    Assert-True ((Get-Config).accounts[0].display -eq 'Test Account') 'Account data changed'
    Assert-True ((Get-Config).activeShared -eq 'unchanged') 'Existing config property lost'
    Invoke-UiTest { Show-Picker } {
      param($form)
      Assert-True ($form.Text -eq (Get-Text 'AppTitle')) 'Picker title not translated'
      Assert-True ($script:PickerPanel.Controls[0].Text -match [regex]::Escape((Get-Text 'MainLabel'))) 'Main account not translated'
      $form.Close()
    }
    Invoke-UiTest { $script:Answer = Ask-YesNo 'Test' } {
      param($form)
      Assert-True ($form.AcceptButton.Text -eq (Get-Text 'No')) 'Confirmation default must be No'
      $form.AcceptButton.PerformClick()
    }
    Assert-True (-not $script:Answer) 'No confirmed the action'
    Invoke-UiTest { $script:InputValue = Show-InputDialog -Prompt 'Test' -Default 'Sample' } {
      param($form)
      Assert-True ($form.CancelButton.Text -eq (Get-Text 'Cancel')) 'Cancel not translated'
      $form.AcceptButton.PerformClick()
    }
    Assert-True ($script:InputValue -eq 'Sample') 'Input dialog lost its value'
    Write-Host "PASS: $code catalog, interpolation, selector, persistence, picker, confirmation and input"
  }
  $before = [IO.File]::ReadAllText($script:ConfigPath)
  Invoke-UiTest { $script:Selected = Show-LanguageSelector } { param($form) $form.Close() }
  Assert-True (-not $script:Selected) 'Closing selector did not cancel'
  Assert-True ($before -eq [IO.File]::ReadAllText($script:ConfigPath)) 'Cancelled selection changed config'
  Write-Host 'PASS: cancelling startup preserves configuration'
  $cliOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -Language en -List
  Assert-True ($LASTEXITCODE -eq 0) 'English CLI invocation failed'
  Assert-True ([bool]($cliOutput -match 'Main \(original signed-in account\)')) 'CLI language override ignored'
  Write-Host 'PASS: explicit English CLI language override'
  Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion) syntax and UI runtime"
} finally {
  # Only delete the exact temporary test directory created above.
  if ((Test-Path -LiteralPath $testRoot) -and (Split-Path -Leaf $testRoot).StartsWith('switcher-localization-')) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
