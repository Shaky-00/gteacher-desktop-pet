# Windows PowerShell 5.1 / STA regression checks. Does not run the pet entrypoint.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$project = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with Windows PowerShell -STA.' }

$windows = @{}
$pattern = @'
(?ms)\[xml\]\$(\w+)\s*=\s*@'\r?\n(.*?)\r?\n'@
'@
foreach ($file in @(Get-ChildItem -LiteralPath $project -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')) {
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw ($file.Name + ': ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; ')) }
    $source = [IO.File]::ReadAllText($file.FullName)
    foreach ($match in [regex]::Matches($source, $pattern)) {
        [xml]$document = $match.Groups[2].Value
        $reader = New-Object System.Xml.XmlNodeReader($document)
        $windows[$match.Groups[1].Value] = [Windows.Markup.XamlReader]::Load($reader)
    }
}
if ($windows.Count -ne 5) { throw "Expected 5 WPF windows; loaded $($windows.Count)." }
try {
    $panel = $windows['panelXaml']
    $panel.Show()
    $box = $panel.FindName('NicknameChoice')
    $box.Text = '中文输入测试'
    [void]$box.Focus()
    $box.SelectAll()
    $panel.UpdateLayout()
    if ($box.IsReadOnly -or -not $box.IsEnabled -or -not $box.Focusable) { throw 'Nickname input must be editable.' }
    if ($null -eq $box.Template) { throw 'Nickname input has no native template.' }
    $glyph = $box.GetRectFromCharacterIndex(0)
    if ($glyph.IsEmpty -or $glyph.Height -lt 8) { throw 'Nickname text is clipped or not laid out.' }
    if ($box.Text -ne '中文输入测试') { throw 'Nickname text was not retained.' }
    # Check that the workbench's placeholder is visual only, not stored input.
    $life = $windows['lifeXaml']
    $name = $life.FindName('AnniversaryInput')
    if ($name.Text -ne '') { throw 'Anniversary placeholder must not become saved text.' }
    $name.Text = '我们的纪念日'
    if ($name.Text -ne '我们的纪念日') { throw 'Anniversary input failed.' }
} finally {
    foreach ($window in $windows.Values) { $window.Close() }
}

# Optional audio must not initialize a synthesizer while disabled.
$script:AppConfig = @{ voiceEnabled = $false; voiceName = ''; voiceVolume = 65 }
$script:PanelControls = $null
. (Join-Path $project 'VoiceDesk.ps1')
if (Speak-PetText '这段文字不应该播放') { throw 'Disabled TTS should not play.' }
if ($null -ne $script:PetSynth) { throw 'Disabled TTS must not initialize an audio engine.' }

# Verify version decisions independently of network and dialogs.
$script:SettingsDirectory = Join-Path ([IO.Path]::GetTempPath()) ('xiaog-check-' + [Guid]::NewGuid().ToString('N'))
. (Join-Path $project 'UpdateDesk.ps1')
function Show-UpdateMessage([string]$message, [string]$heading) { $script:ObservedUpdateMessage = $message }
function Show-UpdateOffer($release) { $script:ObservedOffer = [string]$release.tag_name }
$script:ObservedUpdateMessage = ''; $script:ObservedOffer = ''
$version = (Get-Content -LiteralPath (Join-Path $project 'version.txt') -Raw).Trim()
Handle-UpdateRelease ([pscustomobject]@{tag_name="v$version";draft=$false;prerelease=$false;html_url='https://github.com/Shaky-00/gteacher-desktop-pet/releases'}) $true
if (-not $script:ObservedUpdateMessage -or $script:ObservedOffer) { throw 'Current release must report no update.' }
Handle-UpdateRelease ([pscustomobject]@{tag_name='v99.0.0';draft=$false;prerelease=$false;html_url='https://github.com/Shaky-00/gteacher-desktop-pet/releases/tag/v99.0.0'}) $true
if ($script:ObservedOffer -ne 'v99.0.0') { throw 'A newer stable release must be offered.' }
$script:ObservedUpdateMessage = ''
Handle-UpdateRelease $null $true
if (-not $script:ObservedUpdateMessage) { throw 'No release must produce an explicit message.' }
try {
    $failure = New-Object System.Net.WebException -ArgumentList 'Synthetic DNS failure', ([System.Net.WebExceptionStatus]::NameResolutionFailure)
    $message = Get-UpdateFailureMessage $failure
    if ($message -notmatch 'DNS') { throw 'DNS failure must not be reported as up-to-date.' }
} finally {
    if (Test-Path -LiteralPath $script:SettingsDirectory) { Remove-Item -LiteralPath $script:SettingsDirectory -Recurse -Force }
}
Write-Host 'PASS: PowerShell syntax; 5 WPF windows; nickname text layout; anniversary text; disabled TTS; update decisions.'
