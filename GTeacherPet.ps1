# 小G Desktop Pet v1.1.0 - Windows PowerShell 5.1 + WPF
# Uses the original generated transparent character paintings. No API keys.
# v1.1 unifies the workbench and adds optional offline voice and input fixes.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# PS2EXE turns this script into GTeacherPet.exe. In compiled mode $PSScriptRoot
# is empty, and PS2EXE 1.0.18 provides $ScriptRoot as its replacement.
if (-not $PSScriptRoot) { $PSScriptRoot = $ScriptRoot }
if (-not $PSScriptRoot -or -not (Test-Path -LiteralPath $PSScriptRoot)) {
    throw 'Cannot locate the installation directory for G Teacher Pet.'
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GTeacherNativeHotkey {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr window, int id);
}
'@

$script:AssetDirectory = Join-Path $PSScriptRoot 'sprites'
$script:SettingsDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'GTeacherDesktopPet'
$script:SettingsFile = Join-Path $script:SettingsDirectory 'settings.json'
$script:DefaultPhrases = @{
  activity = @(
    '咦？桌面的另一边会有什么呢？', '出发！今天也要找到一点新鲜事。',
    '嘿嘿，我发现了一片新的桌面领地！', '向左看看……再向右看看！',
    '小星星雷达启动！寻找好玩的东西～', '走一走，脑袋里的灵感也会动起来。',
    '今天的小冒险从这一步开始！', '前面那个角落，好像藏着惊喜。',
    '我决定先观察一下，再出发！', '唔，刚刚看见什么闪了一下？',
    '这边也不错！我再走两步。', '原来桌面这么大呀，探险继续！'
  )
  companion = @(
    '{name}，慢慢来，我会陪着你。', '记得喝水哦，别让自己太累啦。',
    '把眼睛从屏幕上挪开一小会儿吧。', '认真努力的你，已经很棒了。',
    '忙完这一小段，咱们就休息一下。', '深呼吸，肩膀可以放松一点点。',
    '就算今天进度不多，也算认真前进了。', '别太着急，我们一点一点来。',
    '小G就在这里，安静陪你。', '坐久了记得站起来活动活动～',
    '你忙你的，我负责给小星星充电。', '论文慢慢改，灵感会来的！',
    '一会儿喝点水，再继续加油吧。', '今天也辛苦啦，给你一颗小星星！'
  )
  interaction = @(
    '{name}，怎么啦？有什么事需要帮忙吗？', '我在我在！想聊聊天吗？',
    '嘿嘿，摸摸头收到啦！', '是想聊论文，还是偷偷休息五分钟呀？',
    '小G已就位！', '找我聊天按 {hotkey} 哦～',
    '今天也要加油呀！抱抱。', '我听见啦，有什么新想法？',
    '再戳一下，我就要害羞啦。', '我在这里等你，随时喊我！'
  )
}
$script:AppConfig = @{
  nickname = ''; hotkeyLetter = 'G'; scale = 1.0; topmost = $true;
  mode = 'activity'; speechEnabled = $true;
  voiceEnabled = $false; voiceName = ''; voiceVolume = 65;
  phrases = @{
    activity = @($script:DefaultPhrases.activity)
    companion = @($script:DefaultPhrases.companion)
    interaction = @($script:DefaultPhrases.interaction)
  }
}

if (Test-Path $script:SettingsFile) {
    try {
        $stored = Get-Content -LiteralPath $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($stored.nickname) { $script:AppConfig.nickname = [string]$stored.nickname }
        if ($null -ne $stored.scale -and [double]$stored.scale -ge 0.65 -and [double]$stored.scale -le 1.8) { $script:AppConfig.scale = [double]$stored.scale }
        if ($null -ne $stored.topmost) { $script:AppConfig.topmost = [bool]$stored.topmost }
        if ($null -ne $stored.PSObject.Properties['mode'] -and [string]$stored.mode -in @('activity','companion')) {
            $script:AppConfig.mode = [string]$stored.mode
        } elseif ($null -ne $stored.PSObject.Properties['autonomous']) {
            # A previous quiet-mode setting becomes companion mode on upgrade.
            $script:AppConfig.mode = if ([bool]$stored.autonomous) { 'activity' } else { 'companion' }
        }
        if ($null -ne $stored.PSObject.Properties['speechEnabled']) { $script:AppConfig.speechEnabled = [bool]$stored.speechEnabled }
        if ($null -ne $stored.PSObject.Properties['voiceEnabled']) { $script:AppConfig.voiceEnabled = [bool]$stored.voiceEnabled }
        if ($null -ne $stored.PSObject.Properties['voiceName']) { $script:AppConfig.voiceName = [string]$stored.voiceName }
        if ($null -ne $stored.PSObject.Properties['voiceVolume']) { $script:AppConfig.voiceVolume = [Math]::Max(0, [Math]::Min(100, [int]$stored.voiceVolume)) }
        if ($null -ne $stored.PSObject.Properties['phrases'] -and $null -ne $stored.phrases) {
            foreach ($group in @('activity','companion','interaction')) {
                $found = $null
                if ($null -ne $stored.phrases.PSObject.Properties[$group]) { $found = $stored.phrases.$group }
                if ($null -ne $found) {
                    $valid = @($found | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_.Length -gt 0 -and $_.Length -le 100 })
                    if ($valid.Count -gt 0) { $script:AppConfig.phrases[$group] = @($valid | Select-Object -First 50) }
                }
            }
        }
    } catch { }
}

function Save-Settings {
    if (-not (Test-Path $script:SettingsDirectory)) {
        [void](New-Item -ItemType Directory -Path $script:SettingsDirectory -Force)
    }
    $script:AppConfig | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8
}

function Ask-Nickname([string]$currentName) {
    $answer = [Microsoft.VisualBasic.Interaction]::InputBox(
      '小G以后该怎么称呼你？每台电脑可以单独设置哦。',
      '欢迎领养小G', $currentName)
    if (-not [string]::IsNullOrWhiteSpace($answer)) {
        $script:AppConfig.nickname = $answer.Trim().Substring(0, [Math]::Min(20, $answer.Trim().Length))
        Save-Settings
    }
}

if ([string]::IsNullOrWhiteSpace($script:AppConfig.nickname)) {
    Ask-Nickname ''
    if ([string]::IsNullOrWhiteSpace($script:AppConfig.nickname)) {
        $script:AppConfig.nickname = '小伙伴'
        Save-Settings
    }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="小G" Width="298" Height="400"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="Manual">
  <Window.Resources>
    <Style x:Key="HoneyMenu" TargetType="{x:Type ContextMenu}">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type ContextMenu}">
            <Border Background="#FFFFF5D9" BorderBrush="#FFE6B65A" BorderThickness="2"
                    CornerRadius="15" Padding="7" MinWidth="230">
              <Border.Effect><DropShadowEffect Color="#88652C" BlurRadius="18" ShadowDepth="5" Opacity="0.22"/></Border.Effect>
              <StackPanel IsItemsHost="True"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HoneyItem" TargetType="{x:Type MenuItem}">
      <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="#FF584326"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type MenuItem}">
            <Border x:Name="HoverTile" Background="Transparent" CornerRadius="10" Margin="1,1" Padding="12,7">
              <ContentPresenter ContentSource="Header" VerticalAlignment="Center" HorizontalAlignment="Left"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="HoverTile" Property="Background" Value="#FFFFDB94"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HoneySeparator" TargetType="{x:Type Separator}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Separator}">
            <Border Height="1" Margin="10,6" Background="#FFE9CB91"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

  </Window.Resources>
  <Grid x:Name="Root" Background="Transparent">
    <Viewbox Stretch="Uniform">
      <Canvas Width="300" Height="400">
        <Border x:Name="Bubble" Canvas.Left="8" Canvas.Top="0" Width="284" Height="70"
                Background="#FFFEF8" BorderBrush="#F2CC8B" BorderThickness="2"
                CornerRadius="18" Visibility="Collapsed">
          <Border.Effect><DropShadowEffect BlurRadius="9" ShadowDepth="2" Opacity="0.23"/></Border.Effect>
          <TextBlock x:Name="BubbleText" Text="你好呀！" FontFamily="Microsoft YaHei UI"
                     FontSize="16" Foreground="#45446E" TextWrapping="Wrap" TextAlignment="Center"
                     VerticalAlignment="Center" HorizontalAlignment="Center" Margin="12,5"/>
        </Border>
        <Image x:Name="PetImage" Canvas.Left="0" Canvas.Top="80" Width="300" Height="315"
               Stretch="Uniform" RenderTransformOrigin="0.5,0.65" SnapsToDevicePixels="False">
          <Image.RenderTransform>
            <TransformGroup>
              <ScaleTransform x:Name="FaceDirection" ScaleX="1" ScaleY="1"/>
              <RotateTransform x:Name="Tilt" Angle="0"/>
              <TranslateTransform x:Name="Float" Y="0"/>
            </TransformGroup>
          </Image.RenderTransform>
        </Image>
        <TextBlock x:Name="SleepZzz" Canvas.Left="205" Canvas.Top="118" Text="Zzz" FontFamily="Segoe UI"
                   FontWeight="Bold" FontSize="26" Foreground="#FF84A4DC" Visibility="Collapsed" Opacity="0.2">
          <TextBlock.RenderTransform><TranslateTransform x:Name="ZzzShift"/></TextBlock.RenderTransform>
        </TextBlock>
        <TextBlock x:Name="ThinkingMark" Canvas.Left="235" Canvas.Top="128" Text="✦" FontFamily="Segoe UI Symbol"
                   FontWeight="Bold" FontSize="26" Foreground="#FFFFC45C" Visibility="Collapsed" Opacity="0.2">
          <TextBlock.RenderTransform><TranslateTransform x:Name="ThinkShift"/></TextBlock.RenderTransform>
        </TextBlock>
      </Canvas>
    </Viewbox>
  </Grid>
</Window>
'@

$xmlReader = New-Object System.Xml.XmlNodeReader($xaml)
$script:Window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
$iconPath = Join-Path $PSScriptRoot 'assets/gteacher.ico'
if (-not (Test-Path -LiteralPath $iconPath)) { $iconPath = Join-Path $PSScriptRoot 'gteacher.ico' }
if (Test-Path -LiteralPath $iconPath) {
    $script:Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath)
}
function Part([string]$name) {
    $found = $script:Window.FindName($name)
    if ($null -eq $found) { throw "Missing WPF part: $name" }
    return $found
}
$script:PetImage = Part 'PetImage'
$script:Bubble = Part 'Bubble'
$script:BubbleText = Part 'BubbleText'
$script:Float = Part 'Float'
$script:Tilt = Part 'Tilt'
$script:FaceDirection = Part 'FaceDirection'
$script:SleepZzz = Part 'SleepZzz'
$script:ZzzShift = Part 'ZzzShift'
$script:ThinkingMark = Part 'ThinkingMark'
$script:ThinkShift = Part 'ThinkShift'
$script:Mode = 'Idle'
$script:StorySteps = New-Object System.Collections.Queue
$script:StoryActive = $false
$script:LastInteraction = [DateTime]::UtcNow
$script:LastHover = [DateTime]::MinValue
$script:PointerPressed = $false
$script:PanelWindow = $null
$script:PanelControls = $null
$script:LifeWindow = $null
$script:LifeControls = $null
$script:WeatherWindow = $null
$script:WeatherControls = $null
$script:IgnoreClickRelease = $false
$script:PressPoint = [System.Windows.Point]::new(0, 0)
$script:HotkeyHandle = [IntPtr]::Zero
$script:HotkeyRegistered = $false
$script:FocusRunning = $false
$script:FocusRemaining = 0
$script:FocusMenuItem = $null
$script:LifeTick = $null
$script:UpdateClient = $null
$script:UpdatePromptTimer = $null

$script:Pictures = @{}
foreach ($file in (Get-ChildItem -LiteralPath $script:AssetDirectory -Filter '*.png' -File)) {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.UriSource = [System.Uri]::new($file.FullName, [System.UriKind]::Absolute)
    $bmp.EndInit()
    $bmp.Freeze()
    $script:Pictures[$file.Name] = $bmp
}
function Picture([string]$name) {
    if (-not $script:Pictures.ContainsKey($name)) { throw "Missing sprite: $name" }
    $script:PetImage.Source = $script:Pictures[$name]
    # Correct original image-to-image variations in feet height, measured on alpha silhouettes.
    # In particular, view_06's feet sit ~36 source pixels above view_02's.
    $bottoms = @{'view_01.png'=482; 'view_02.png'=482; 'view_06.png'=446;
                 'view_07.png'=443; 'quarter_left.png'=482; 'pose_01.png'=468;
                 'wave_alt.png'=468; 'pose_02.png'=468; 'pose_06.png'=439;
                 'pose_00.png'=472; 'pose_05.png'=441; 'walk_alt.png'=452}
    $bottom = 472
    if ($bottoms.ContainsKey($name)) { $bottom = $bottoms[$name] }
    [System.Windows.Controls.Canvas]::SetTop($script:PetImage, 80.0 + (472.0 - $bottom) * 315.0 / 512.0)
}

function Say([string]$text) {
    $script:BubbleText.Text = $text
    $script:Bubble.Visibility = 'Visible'
    $script:BubbleTimer.Stop(); $script:BubbleTimer.Start()
    if ($script:AppConfig.voiceEnabled) { [void](Speak-PetText $text) }
}

function Say-From([string]$group, [bool]$manual = $false) {
    if (-not $manual -and -not $script:AppConfig.speechEnabled) { return }
    $lines = @($script:AppConfig.phrases[$group])
    if ($lines.Count -eq 0) { $lines = @($script:DefaultPhrases[$group]) }
    $message = [string]($lines | Get-Random)
    $message = $message.Replace('{name}', $script:AppConfig.nickname)
    $message = $message.Replace('{hotkey}', ('Ctrl+Alt+' + $script:AppConfig.hotkeyLetter))
    Say $message
}

$script:BubbleTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:BubbleTimer.Interval = [TimeSpan]::FromSeconds(4.8)
$script:BubbleTimer.Add_Tick({ $script:BubbleTimer.Stop(); $script:Bubble.Visibility = 'Collapsed' })

function Start-Float([double]$distance = -7, [double]$seconds = 1.55) {
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animation.From = 0; $animation.To = $distance
    $animation.Duration = New-Object System.Windows.Duration -ArgumentList ([TimeSpan]::FromSeconds($seconds))
    $animation.AutoReverse = $true
    $animation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $script:Float.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $animation)
}

function Start-DetailMotion([string]$effect) {
    $script:SleepZzz.Visibility = 'Collapsed'
    $script:ThinkingMark.Visibility = 'Collapsed'
    $script:SleepZzz.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:ThinkingMark.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:ZzzShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $script:ThinkShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    if ($effect -eq 'Sleep') {
        $script:SleepZzz.Visibility = 'Visible'
        $rise = New-Object System.Windows.Media.Animation.DoubleAnimation
        $rise.From = 12; $rise.To = -17
        $rise.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(2.3))
        $rise.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $script:ZzzShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty,$rise)
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
        $fade.From = 0.12; $fade.To = 0.92
        $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.2))
        $fade.AutoReverse = $true
        $fade.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $script:SleepZzz.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$fade)
    }
    if ($effect -eq 'Think') {
        $script:ThinkingMark.Visibility = 'Visible'
        $drift = New-Object System.Windows.Media.Animation.DoubleAnimation
        $drift.From = 4; $drift.To = -9
        $drift.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(0.95))
        $drift.AutoReverse = $true
        $drift.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $script:ThinkShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty,$drift)
        $glow = New-Object System.Windows.Media.Animation.DoubleAnimation
        $glow.From = 0.2; $glow.To = 0.95
        $glow.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(0.95))
        $glow.AutoReverse = $true
        $glow.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $script:ThinkingMark.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$glow)
    }
}

$script:ActionTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ActionTimer.Interval = [TimeSpan]::FromSeconds(3.5)
$script:ActionTimer.Add_Tick({
    $script:ActionTimer.Stop()
    if ($script:StoryActive) { Advance-Story }
    else { Set-Mode 'Idle' $true }
})
$script:MotionTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:MotionTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$script:MotionTimer.Add_Tick({
    if ($script:Mode -ne 'Walk') { return }
    $elapsed = ([DateTime]::UtcNow - $script:MotionStarted).TotalSeconds
    $t = [Math]::Min(1.0, [Math]::Max(0.0, $elapsed / $script:MotionDuration))
    # Smoothstep: one continuous journey; no rapid reversal or up/down jitter.
    $smooth = $t * $t * (3.0 - 2.0 * $t)
    $script:Window.Left = $script:MotionFromX + ($script:MotionToX - $script:MotionFromX) * $smooth
    $script:Window.Top = $script:MotionFromY + ($script:MotionToY - $script:MotionFromY) * $smooth
    if ($t -ge 1) {
        $script:MotionTimer.Stop()
        if ($script:StoryActive) { Advance-Story }
        else { Set-Mode 'Idle' $true }
    }
})

# Feet alternate at a fixed position while the window follows its smooth path.
$script:FootstepIndex = 0
$script:FootstepTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:FootstepTimer.Interval = [TimeSpan]::FromMilliseconds(260)
$script:FootstepTimer.Add_Tick({
    if ($script:Mode -ne 'Walk') { $script:FootstepTimer.Stop(); return }
    $script:FootstepIndex = 1 - $script:FootstepIndex
    if ($script:FootstepIndex -eq 0) { Picture 'pose_05.png' }
    else { Picture 'walk_alt.png' }
})

# A different image frame for the upper waving hand; sleep remains gently animated
# as a continuous breath, without flashing between mismatched blanket silhouettes.
$script:GestureIndex = 0
$script:GestureTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:GestureTimer.Interval = [TimeSpan]::FromMilliseconds(420)
$script:GestureTimer.Add_Tick({
    if ($script:Mode -ne 'Wave') { $script:GestureTimer.Stop(); return }
    $script:GestureIndex = 1 - $script:GestureIndex
    if ($script:GestureIndex -eq 0) { Picture 'pose_01.png' }
    else { Picture 'wave_alt.png' }
})

function Begin-Wander {
    $area = [System.Windows.SystemParameters]::WorkArea
    $minX = [int][Math]::Ceiling($area.Left + 8)
    $maxX = [int][Math]::Floor($area.Right - $script:Window.Width - 8)
    $minY = [int][Math]::Ceiling($area.Top + 8)
    $maxY = [int][Math]::Floor($area.Bottom - $script:Window.Height - 8)
    if ($maxX -le $minX -or $maxY -le $minY) { Set-Mode 'Idle'; return }
    $script:MotionFromX = $script:Window.Left
    $script:MotionFromY = $script:Window.Top
    # Avoid a tiny 'walk' that appears to shake in place.
    $targetX = $script:MotionFromX; $targetY = $script:MotionFromY
    for ($attempt = 0; $attempt -lt 9; $attempt++) {
        $targetX = Get-Random -Minimum $minX -Maximum ($maxX + 1)
        $targetY = Get-Random -Minimum $minY -Maximum ($maxY + 1)
        $distance = [Math]::Sqrt([Math]::Pow($targetX - $script:MotionFromX, 2) + [Math]::Pow($targetY - $script:MotionFromY, 2))
        if ($distance -ge 115) { break }
    }
    $script:MotionToX = [double]$targetX
    $script:MotionToY = [double]$targetY
    $script:MotionDuration = [Math]::Max(3.2, [Math]::Min(8.5, $distance / 92.0))
    $script:MotionStarted = [DateTime]::UtcNow
    $script:FaceDirection.ScaleX = if ($script:MotionToX -ge $script:MotionFromX) { 1 } else { -1 }
    $script:MotionTimer.Start()
}

function Set-Mode([string]$nextMode, [bool]$automatic = $false) {
    if (-not $automatic) {
        # A user gesture always takes priority over the current autonomous routine.
        $script:StoryActive = $false
        $script:StorySteps.Clear()
        if ($null -ne $script:AutoTimer) { Schedule-Auto }
    }
    $script:Mode = $nextMode
    $script:ActionTimer.Stop(); $script:MotionTimer.Stop()
    $script:FootstepTimer.Stop(); $script:GestureTimer.Stop()
    if ($null -ne $script:BlinkRestoreTimer) { $script:BlinkRestoreTimer.Stop() }
    $script:Float.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $script:Tilt.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $script:FaceDirection.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $null)
    $script:FaceDirection.ScaleY = 1
    $script:Float.Y = 0; $script:Tilt.Angle = 0; $script:FaceDirection.ScaleX = 1
    Start-DetailMotion $nextMode
    switch ($nextMode) {
        'Sleep' {
            Picture 'pose_06.png'; Start-Float -3.5 1.65
            $breath = New-Object System.Windows.Media.Animation.DoubleAnimation
            $breath.From = 1.0; $breath.To = 1.018
            $breath.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.65))
            $breath.AutoReverse = $true
            $breath.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $script:FaceDirection.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$breath)
            if (-not $automatic) { Say 'Zzz……小G盖好毯子啦。' }
            if ($automatic) { $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(6.0); $script:ActionTimer.Start() }
        }
        'Wave' {
            Picture 'pose_01.png'; Start-Float -5 0.65
            $script:GestureIndex = 0
            $script:GestureTimer.Start()
            if (-not $automatic) { Say ("{0}，嗨嗨！今天也要加油呀！" -f $script:AppConfig.nickname) }
            $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(3.5)
            $script:ActionTimer.Start()
        }
        'Think' {
            Picture 'pose_02.png'; Start-Float -3 1.7
            $sway = New-Object System.Windows.Media.Animation.DoubleAnimation
            $sway.From = -1.4; $sway.To = 1.4
            $sway.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.4))
            $sway.AutoReverse = $true
            $sway.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $script:Tilt.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$sway)
            $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(4.5)
            if (-not $automatic) { Say '这道题，我们一起想一想。' }
            $script:ActionTimer.Start()
        }
        'Happy' {
            Picture 'pose_03.png'; Start-Float -17 0.45
            $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(3.0)
            if (-not $automatic) { Say '耶！今天也有一点小进步！' }
            $script:ActionTimer.Start()
        }
        'Type' {
            Picture 'pose_04.png'; Start-Float -3 0.38
            $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(5.0)
            if (-not $automatic) { Say '哒哒哒……小G帮忙敲键盘！' }
            $script:ActionTimer.Start()
        }
        'Walk' {
            Picture 'pose_05.png'
            if (-not $automatic) { Say '我要去桌面另一边看看啦～' }
            Begin-Wander
            if ($script:Mode -eq 'Walk') {
                $script:FootstepIndex = 0
                $script:FootstepTimer.Start()
            }
        }
        'LookLeft' {
            Picture 'view_02.png'; Start-Float -2 1.8
            $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(1.6)
            $script:ActionTimer.Start()
        }
        'LookRight' {
            Picture 'view_06.png'; Start-Float -2 1.8
            $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(1.6)
            $script:ActionTimer.Start()
        }
        'TurnLeft' { Picture 'quarter_left.png' }
        'TurnRight' { Picture 'view_07.png' }
        'Portrait' {
            Picture 'portrait.png'; Start-Float -5 1.4
            $script:ActionTimer.Interval = [TimeSpan]::FromSeconds(3.5)
            if (-not $automatic) { Say '小星星和眼镜都戴好啦！' }
            $script:ActionTimer.Start()
        }
        default { $script:Mode = 'Idle'; Picture 'pose_00.png'; Start-Float -6 1.55 }
    }
}

# Instead of choosing an isolated pose every few seconds, autonomous behavior
# is composed of short sequences with natural entry/exit turns and pauses.
function Advance-Story {
    if ($script:StorySteps.Count -le 0) {
        $script:StoryActive = $false
        Set-Mode 'Idle' $true
        Schedule-Auto
        return
    }
    $step = $script:StorySteps.Dequeue()
    Set-Mode ([string]$step.Mode) $true
    if ($step.Mode -eq 'Walk') { return }  # Finishes when the actual walk reaches its destination.
    $script:ActionTimer.Stop()
    $script:ActionTimer.Interval = [TimeSpan]::FromSeconds([double]$step.Seconds)
    $script:ActionTimer.Start()
}

function Start-Story([string]$story) {
    $script:StorySteps.Clear()
    $steps = switch ($story) {
        'CuriosityLeft' { @(
          @{Mode='TurnLeft';Seconds=0.55}, @{Mode='LookLeft';Seconds=1.45},
          @{Mode='TurnLeft';Seconds=0.55}, @{Mode='Idle';Seconds=0.3},
          @{Mode='Think';Seconds=1.8}, @{Mode='Idle';Seconds=0.3}) }
        'CuriosityRight' { @(
          @{Mode='TurnRight';Seconds=0.55}, @{Mode='LookRight';Seconds=1.45},
          @{Mode='TurnRight';Seconds=0.55}, @{Mode='Idle';Seconds=0.3},
          @{Mode='Happy';Seconds=1.7}) }
        'LookAround' { @(
          @{Mode='TurnLeft';Seconds=0.5}, @{Mode='LookLeft';Seconds=1.1},
          @{Mode='TurnLeft';Seconds=0.5}, @{Mode='Idle';Seconds=0.45},
          @{Mode='TurnRight';Seconds=0.5}, @{Mode='LookRight';Seconds=1.1},
          @{Mode='TurnRight';Seconds=0.5}, @{Mode='Idle';Seconds=0.5}) }
        'Explore' { @(
          @{Mode='TurnRight';Seconds=0.5}, @{Mode='LookRight';Seconds=0.9},
          @{Mode='TurnRight';Seconds=0.45}, @{Mode='Walk';Seconds=0},
          @{Mode='Think';Seconds=1.6}, @{Mode='Wave';Seconds=1.65}) }
        'Patrol' { @(
          @{Mode='Walk';Seconds=0}, @{Mode='TurnLeft';Seconds=0.45},
          @{Mode='LookLeft';Seconds=1.0}, @{Mode='TurnLeft';Seconds=0.45},
          @{Mode='Wave';Seconds=1.4}) }
        'Work' { @(
          @{Mode='Think';Seconds=2.15}, @{Mode='Type';Seconds=2.4},
          @{Mode='Happy';Seconds=1.4}) }
        'Nap' { @(
          @{Mode='Think';Seconds=1.0}, @{Mode='Sleep';Seconds=6.0},
          @{Mode='Wave';Seconds=1.6}) }
        'GentleWave' { @(@{Mode='Wave';Seconds=1.65}, @{Mode='Idle';Seconds=0.5}) }
        'GentleThink' { @(@{Mode='Think';Seconds=2.6}, @{Mode='Idle';Seconds=0.65}) }
        'GentleNap' { @(@{Mode='Sleep';Seconds=5.4}, @{Mode='Idle';Seconds=0.8}) }
        'GentleWork' { @(@{Mode='Type';Seconds=2.6}, @{Mode='Think';Seconds=1.8}) }
        default { @(@{Mode='Wave';Seconds=1.7}, @{Mode='Idle';Seconds=0.4}) }
    }
    foreach ($step in $steps) { $script:StorySteps.Enqueue($step) }
    $script:StoryActive = $true
    Advance-Story
}

# A short 135 ms closed-eye sprite makes spontaneous blinks unobtrusive.
$script:BlinkRestoreTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:BlinkRestoreTimer.Interval = [TimeSpan]::FromMilliseconds(135)
$script:BlinkRestoreTimer.Add_Tick({
    $script:BlinkRestoreTimer.Stop()
    if ($script:Mode -eq 'Idle') { Picture 'pose_00.png' }
})
$script:BlinkTimer = New-Object System.Windows.Threading.DispatcherTimer
function Schedule-Blink {
    $script:BlinkTimer.Stop()
    $script:BlinkTimer.Interval = [TimeSpan]::FromMilliseconds((Get-Random -Minimum 2900 -Maximum 7600))
    $script:BlinkTimer.Start()
}
$script:BlinkTimer.Add_Tick({
    if ($script:Mode -eq 'Idle' -and -not $script:PointerPressed) {
        Picture 'blink_closed.png'
        $script:BlinkRestoreTimer.Stop()
        $script:BlinkRestoreTimer.Start()
    }
    Schedule-Blink
})

$script:AutoTimer = New-Object System.Windows.Threading.DispatcherTimer
function Schedule-Auto {
    $script:AutoTimer.Stop()
    if ($script:AppConfig.mode -eq 'activity') {
        $wait = Get-Random -Minimum 3 -Maximum 7
    } else {
        $wait = Get-Random -Minimum 11 -Maximum 19
    }
    $script:AutoTimer.Interval = [TimeSpan]::FromSeconds($wait)
    $script:AutoTimer.Start()
}
$script:AutoTimer.Add_Tick({
    $script:AutoTimer.Stop()
    if (-not $script:FocusRunning -and -not $script:StoryActive -and $script:Mode -eq 'Idle' -and
        -not $script:PointerPressed -and -not $script:Menu.IsOpen -and
        ($null -eq $script:LifeWindow) -and ($null -eq $script:WeatherWindow) -and
        ([DateTime]::UtcNow - $script:LastInteraction).TotalSeconds -gt 3) {
        if ($script:AppConfig.mode -eq 'activity') {
            $choice = @('Explore','Explore','Patrol','LookAround','CuriosityLeft',
                        'CuriosityRight','Work','Work','Nap','Wave') | Get-Random
        } else {
            # Companion mode never places Walk in its automatic action queue.
            $choice = @('GentleWave','GentleWave','GentleThink','GentleThink',
                        'GentleNap','GentleWork','CuriosityLeft','CuriosityRight') | Get-Random
        }
        Start-Story $choice
    } else { Schedule-Auto }
})

function Open-ChatGPT {
    try { Start-Process 'https://chatgpt.com/' }
    catch { Say '浏览器暂时没打开，试试手动访问 chatgpt.com 哦。' }
}

function Register-CurrentHotkey {
    if ($script:HotkeyHandle -eq [IntPtr]::Zero) { return $false }
    if ($script:HotkeyRegistered) {
        [void][GTeacherNativeHotkey]::UnregisterHotKey($script:HotkeyHandle, 7318)
        $script:HotkeyRegistered = $false
    }
    $code = [uint32][int][char]$script:AppConfig.hotkeyLetter
    $script:HotkeyRegistered = [GTeacherNativeHotkey]::RegisterHotKey($script:HotkeyHandle, 7318, 3, $code)
    return $script:HotkeyRegistered
}

function Change-Nickname {
    Ask-Nickname $script:AppConfig.nickname
    Say ("好的，以后就叫你 {0}！" -f $script:AppConfig.nickname)
}
function Show-PersonalSettings {
    Show-ControlPanel
}

function Set-PetMode([string]$newMode, [bool]$announce = $true) {
    if ($newMode -notin @('activity','companion')) { return }
    $script:AppConfig.mode = $newMode
    $script:StoryActive = $false
    $script:StorySteps.Clear()
    Set-Mode 'Idle'
    $script:LastInteraction = [DateTime]::UtcNow
    Schedule-Auto
    Schedule-Ambient
    Update-Menu-States
    Save-Settings
    if ($announce) {
        if ($newMode -eq 'activity') { Say '活动模式启动！我去找点好玩的～' }
        else { Say '陪伴模式启动，我留在这里陪你。' }
    }
}

function Show-ControlPanel {
    # Release the pet/context-menu capture before showing an editable modal form.
    $script:PointerPressed = $false
    $script:IgnoreClickRelease = $false
    $script:Window.ReleaseMouseCapture()
    $script:Menu.IsOpen = $false
    [void][System.Windows.Input.Mouse]::Capture($null)
    $script:LastInteraction = [DateTime]::UtcNow
    Set-Mode 'Idle'
    $script:AutoTimer.Stop()
    $script:AmbientTimer.Stop()
    try {
    [xml]$panelXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="小G的小屋 · 控制台" Width="710" Height="650"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#FFFFF8E9" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style TargetType="{x:Type Button}">
      <Setter Property="Background" Value="#FFFFE1A4"/>
      <Setter Property="Foreground" Value="#FF654B2A"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="15,9"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type Button}">
          <Border x:Name="ButtonTile" Background="{TemplateBinding Background}" BorderBrush="#FFE2B765"
                  BorderThickness="1.5" CornerRadius="10" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonTile" Property="Background" Value="#FFFFD186"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonTile" Property="Background" Value="#FFF6BA5D"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="{x:Type TextBox}">
      <Setter Property="Foreground" Value="#FF554631"/>
      <Setter Property="CaretBrush" Value="#FF554631"/>
      <Setter Property="SelectionBrush" Value="#FFF1C46C"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Background" Value="#FFFFFEF8"/>
      <Setter Property="BorderBrush" Value="#FFE5C891"/>
      <Setter Property="BorderThickness" Value="1.5"/>
      <Setter Property="Padding" Value="8"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type TextBox}">
          <Border x:Name="InputTile" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="11">
            <ScrollViewer x:Name="PART_ContentHost" Focusable="False"/>
          </Border>
          <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="InputTile" Property="BorderBrush" Value="#FFC99048"/></Trigger></ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <Style TargetType="{x:Type ComboBox}">
      <Setter Property="FontSize" Value="14"/><Setter Property="MinHeight" Value="36"/>
      <Setter Property="Foreground" Value="#FF654B2A"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type ComboBox}">
          <Grid>
            <ToggleButton Focusable="False" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
              <ToggleButton.Template><ControlTemplate TargetType="{x:Type ToggleButton}">
                <Border x:Name="Tile" Background="#FFFFFEF8" BorderBrush="#FFE5C891" BorderThickness="1.5" CornerRadius="10">
                  <TextBlock Text="⌄" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"/>
                </Border>
                <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Tile" Property="BorderBrush" Value="#FFC99048"/></Trigger></ControlTemplate.Triggers>
              </ControlTemplate></ToggleButton.Template>
            </ToggleButton>
            <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" IsHitTestVisible="False" Margin="10,4,28,4" VerticalAlignment="Center"/>
            <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
              <Border Background="#FFFFFEF8" BorderBrush="#FFE5C891" BorderThickness="1" CornerRadius="10" Padding="4" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                <ScrollViewer MaxHeight="240" CanContentScroll="True"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
              </Border>
            </Popup>
          </Grid>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <Style TargetType="{x:Type TabItem}">
      <Setter Property="Foreground" Value="#FF806849"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="18,10"/>
      <Setter Property="Margin" Value="0,0,8,10"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type TabItem}">
          <Border x:Name="TabPill" Background="#FFFFF0D6" BorderBrush="#FFE8D0A0" BorderThickness="1" CornerRadius="13" Padding="{TemplateBinding Padding}">
            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="TabPill" Property="Background" Value="#FFFFE5B1"/></Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="TabPill" Property="Background" Value="#FFFFD58B"/>
              <Setter TargetName="TabPill" Property="BorderBrush" Value="#FFE3AF55"/>
              <Setter Property="Foreground" Value="#FF604725"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="TabPill" Property="BorderBrush" Value="#FFB88431"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="{x:Type TabControl}">
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type TabControl}">
          <Grid KeyboardNavigation.TabNavigation="Local">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <TabPanel IsItemsHost="True" KeyboardNavigation.TabIndex="1"/>
            <Border Grid.Row="1" Background="{TemplateBinding Background}" BorderBrush="#FFE9C88B" BorderThickness="1" CornerRadius="14" Padding="2">
              <ContentPresenter x:Name="PART_SelectedContentHost" ContentSource="SelectedContent" Margin="2"/>
            </Border>
          </Grid>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border Margin="14" BorderBrush="#FFE7C27F" BorderThickness="1.5" CornerRadius="16" Background="#FFFFF9EB">
    <Grid Margin="18">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Margin="4,0,4,12">
        <TextBlock Text="小G的小屋" FontSize="25" FontWeight="Bold" Foreground="#FF544062"/>
        <TextBlock Text="这里可以布置小G的日常、台词和小习惯。" FontSize="13" Foreground="#FF8B785E" Margin="0,3,0,0"/>
      </StackPanel>
      <TabControl Grid.Row="1" Background="#FFFFF9EB" BorderBrush="#FFE9C88B" FontSize="14">
        <TabItem Header="基本设置">
          <Grid Margin="13">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="252"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="3,8,20,0">
              <TextBlock Text="日常生活模式" FontWeight="SemiBold" Foreground="#FF5A4B38" Margin="0,0,0,5"/>
              <ComboBox x:Name="ModeChoice" Height="34" FontSize="14" Background="#FFFFFCF3" Margin="0,0,0,5">
                <ComboBoxItem Content="活动模式 · 会到处探险"/>
                <ComboBoxItem Content="陪伴模式 · 原地陪你"/>
              </ComboBox>
              <TextBlock Text="活动会走动；陪伴不自动位移，动作与说话都更轻缓。" TextWrapping="Wrap" FontSize="12" Foreground="#FF8E7A5B" Margin="0,0,0,14"/>
              <TextBlock Text="我该怎么称呼你？" FontWeight="SemiBold" Foreground="#FF5A4B38" Margin="0,0,0,5"/>
              <Border Background="#FFFFFEF8" BorderBrush="#FFE5C891" BorderThickness="1.5" CornerRadius="11" Margin="0,0,0,14" Padding="5,2">
                <TextBox x:Name="NicknameChoice" Style="{x:Null}" MinHeight="38" MaxLength="20"
                         FontSize="14" FontFamily="Microsoft YaHei UI" Foreground="#FF554631" CaretBrush="#FF554631"
                         Background="Transparent" BorderThickness="0" Padding="4,3" VerticalContentAlignment="Center"
                         IsReadOnly="False" IsEnabled="True" Focusable="True" IsTabStop="True"/>
              </Border>
              <TextBlock Text="打开 ChatGPT 的快捷键" FontWeight="SemiBold" Foreground="#FF5A4B38" Margin="0,0,0,5"/>
              <Border Background="#FFFFE8B9" CornerRadius="10" Padding="12,8" HorizontalAlignment="Left" Margin="0,0,0,14">
                <TextBlock Text="Ctrl + Alt + G" FontSize="15" FontWeight="SemiBold" Foreground="#FF654B2A"/>
              </Border>
              <CheckBox x:Name="TopmostChoice" Content="始终在其他窗口前面" FontSize="14" Foreground="#FF5A4B38" Margin="0,0,0,12"/>
              <CheckBox x:Name="SpeechChoice" Content="允许小G 偶尔主动说话" FontSize="14" Foreground="#FF5A4B38" Margin="0,0,0,15"/>
              <TextBlock Text="桌宠大小" FontWeight="SemiBold" Foreground="#FF5A4B38" Margin="0,0,0,4"/>
              <DockPanel><TextBlock x:Name="ScaleLabel" DockPanel.Dock="Right" Width="85" TextAlignment="Right" VerticalAlignment="Center" Foreground="#FF796048"/><Slider x:Name="ScaleChoice" Minimum="1" Maximum="10" TickFrequency="1" TickPlacement="BottomRight" IsSnapToTickEnabled="True" SmallChange="1" LargeChange="1" Margin="0,0,8,0"/></DockPanel>
            </StackPanel>
            <Border Grid.Column="1" Background="#FFFFF0CD" BorderBrush="#FFE9CD95" BorderThickness="1" CornerRadius="14" Margin="0,8,0,0">
              <StackPanel Margin="10" HorizontalAlignment="Center">
                <TextBlock Text="小G · 星星档案" Foreground="#FF796048" FontWeight="Bold" FontSize="13" HorizontalAlignment="Center"/>
                <Image x:Name="PanelPortrait" Width="216" Height="230" Stretch="Uniform" Margin="0,8,0,0"/>
                <TextBlock Text="当前装扮：蓝色绒帽与星星围巾" FontSize="12" Foreground="#FF685944" TextAlignment="Center" TextWrapping="Wrap" Margin="5,6,5,0"/>
                <TextBlock Text="换装衣柜，未来慢慢解锁 ✦" FontSize="12" Foreground="#FF998460" TextAlignment="Center" Margin="3,13,3,0"/>
              </StackPanel>
            </Border>
          </Grid>
        </TabItem>
        <TabItem Header="小G的语料库">
          <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="14,12">
            <StackPanel>
              <TextBlock Text="每行一句台词。可以写 {name} 表示本机昵称，{hotkey} 表示聊天快捷键。" TextWrapping="Wrap" FontSize="13" Foreground="#FF7C674E" Margin="0,0,0,11"/>
              <TextBlock Text="出去探险时 · 活动模式" FontWeight="Bold" Foreground="#FF66503B" Margin="0,0,0,4"/>
              <TextBox x:Name="ActivityLines" AcceptsReturn="True" TextWrapping="Wrap" Height="125" VerticalScrollBarVisibility="Auto" Margin="0,0,0,11"/>
              <TextBlock Text="待在身旁时 · 陪伴模式" FontWeight="Bold" Foreground="#FF66503B" Margin="0,0,0,4"/>
              <TextBox x:Name="CompanionLines" AcceptsReturn="True" TextWrapping="Wrap" Height="125" VerticalScrollBarVisibility="Auto" Margin="0,0,0,11"/>
              <TextBlock Text="你点我、摸摸我时 · 互动语料" FontWeight="Bold" Foreground="#FF66503B" Margin="0,0,0,4"/>
              <TextBox x:Name="InteractionLines" AcceptsReturn="True" TextWrapping="Wrap" Height="125" VerticalScrollBarVisibility="Auto" Margin="0,0,0,6"/>
              <TextBlock Text="修改后点保存才会生效。每组最多 50 句；建议每句不超过 30 字。" FontSize="12" Foreground="#FF8E795E" TextWrapping="Wrap"/>
            </StackPanel>
          </ScrollViewer>
        </TabItem>

        <TabItem Header="语音试听">
          <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="18,12">
            <StackPanel>
              <TextBlock Text="让小G读出台词" FontSize="20" FontWeight="Bold" Foreground="#FF604B38" Margin="0,0,0,8"/>
              <TextBlock Text="使用电脑已有的语音，不需要联网或 API。先试听，喜欢再开启。" Foreground="#FF8B785E" TextWrapping="Wrap" Margin="0,0,0,18"/>
              <CheckBox x:Name="VoiceEnabledChoice" Content="开启小G语音朗读" Foreground="#FF5A4B38" Margin="0,0,0,18"/>
              <TextBlock Text="音色" Foreground="#FF5A4B38" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <ComboBox x:Name="VoiceChoice" Height="38" Margin="0,0,0,18"/>
              <TextBlock Text="音量" Foreground="#FF5A4B38" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <Slider x:Name="VoiceVolumeChoice" Minimum="0" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" SmallChange="5" LargeChange="10" Margin="0,0,0,16"/>
              <WrapPanel Margin="0,0,0,15">
                <Button x:Name="VoicePreviewBtn" Content="▶ 试听一下" Margin="0,0,10,0"/>
                <Button x:Name="VoiceStopBtn" Content="■ 停止播放" Background="#FFFFF2D5"/>
              </WrapPanel>
              <TextBlock x:Name="VoiceStatus" Foreground="#FF8B785E" TextWrapping="Wrap" Margin="0,0,0,10"/>
              <TextBlock Text="试听不会自动开启语音。开启、音色和音量设置点击保存后生效；关闭开关会立即停止播放。" Foreground="#FF8B785E" TextWrapping="Wrap" FontSize="12"/>
            </StackPanel>
          </ScrollViewer>
        </TabItem>
      </TabControl>
      <DockPanel Grid.Row="2" Margin="4,14,4,0" LastChildFill="False">
        <Button x:Name="ResetLinesBtn" Content="恢复默认台词" DockPanel.Dock="Left" Background="#FFFFF2D5"/>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
          <Button x:Name="CancelBtn" Content="先不改啦" Background="#FFFFF2D5" Margin="0,0,10,0"/>
          <Button x:Name="SaveBtn" Content="保存我的小屋  ✓"/>
        </StackPanel>
      </DockPanel>
    </Grid>
  </Border>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader($panelXaml)
    $script:PanelWindow = [System.Windows.Markup.XamlReader]::Load($reader)
    $script:PanelWindow.Owner = $script:Window
    $script:PanelWindow.Icon = $script:Window.Icon
    $script:PanelControls = @{}
    foreach ($id in @('ModeChoice','NicknameChoice','TopmostChoice','SpeechChoice','ScaleChoice','ScaleLabel','VoiceEnabledChoice','VoiceChoice','VoiceVolumeChoice','VoicePreviewBtn','VoiceStopBtn','VoiceStatus',
                    'PanelPortrait','ActivityLines','CompanionLines','InteractionLines','ResetLinesBtn','CancelBtn','SaveBtn')) {
        $script:PanelControls[$id] = $script:PanelWindow.FindName($id)
    }
    $p = $script:PanelControls
    $p.ModeChoice.SelectedIndex = if ($script:AppConfig.mode -eq 'activity') { 0 } else { 1 }
    $p.NicknameChoice.Text = $script:AppConfig.nickname
    $script:PanelWindow.Add_ContentRendered({
        [void]$script:PanelControls.NicknameChoice.Focus()
        [void][System.Windows.Input.Keyboard]::Focus($script:PanelControls.NicknameChoice)
        $script:PanelControls.NicknameChoice.SelectAll()
    })
    Initialize-VoicePanel
    $p.TopmostChoice.IsChecked = $script:AppConfig.topmost
    $p.SpeechChoice.IsChecked = $script:AppConfig.speechEnabled
    $p.ScaleChoice.Value = [Math]::Max(1, [Math]::Min(10, [Math]::Round(($script:AppConfig.scale - 0.7) / 0.1) + 1))
    $p.ScaleLabel.Text = ('{0} / 10' -f [int]$p.ScaleChoice.Value)
    $p.ScaleChoice.Add_ValueChanged({
        $level = [int]$script:PanelControls.ScaleChoice.Value
        $script:PanelControls.ScaleLabel.Text = ('{0} / 10' -f $level)
        $previewScale = 0.7 + ($level - 1) * 0.1
        $script:Window.Width = 298 * $previewScale
        $script:Window.Height = 400 * $previewScale
    })
    $script:PanelWindow.Add_Closed({ Stop-PetVoice; Resize-Pet 0 })
    $p.PanelPortrait.Source = $script:Pictures['portrait.png']
    $p.ActivityLines.Text = $script:AppConfig.phrases.activity -join "`r`n"
    $p.CompanionLines.Text = $script:AppConfig.phrases.companion -join "`r`n"
    $p.InteractionLines.Text = $script:AppConfig.phrases.interaction -join "`r`n"
    $p.ResetLinesBtn.Add_Click({
        $result = [System.Windows.MessageBox]::Show('恢复三组默认台词？当前编辑的文字会被替换，保存后才会生效。',
            '恢复默认台词', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            $script:PanelControls.ActivityLines.Text = $script:DefaultPhrases.activity -join "`r`n"
            $script:PanelControls.CompanionLines.Text = $script:DefaultPhrases.companion -join "`r`n"
            $script:PanelControls.InteractionLines.Text = $script:DefaultPhrases.interaction -join "`r`n"
        }
    })
    $p.CancelBtn.Add_Click({ $script:PanelWindow.Close() })
    $p.SaveBtn.Add_Click({
        $c = $script:PanelControls
        $nickname = ([string]$c.NicknameChoice.Text).Trim()
        if ($nickname.Length -lt 1 -or $nickname.Length -gt 20) {
            [void][System.Windows.MessageBox]::Show('昵称请填 1～20 个字符哦。','小G提醒'); return
        }
        $changedPhrases = @{}
        foreach ($group in @('activity','companion','interaction')) {
            $key = switch ($group) { 'activity' {'ActivityLines'} 'companion' {'CompanionLines'} default {'InteractionLines'} }
            $rawLines = @(([string]$c[$key].Text) -split '\r?\n')
            $clean = @($rawLines | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
            if ($clean.Count -lt 1 -or $clean.Count -gt 50 -or @($clean | Where-Object { $_.Length -gt 100 }).Count -gt 0) {
                [void][System.Windows.MessageBox]::Show('每组台词需要 1～50 句，每句不能超过 100 个字符。','语料库需要调整'); return
            }
            $changedPhrases[$group] = $clean
        }
        if ([bool]$c.VoiceEnabledChoice.IsChecked -and $null -eq $c.VoiceChoice.SelectedItem) {
            [void][System.Windows.MessageBox]::Show('没有检测到可用的系统语音。请先关闭语音开关，或安装语音包后重启小G。','语音暂不可用'); return
        }
        $script:AppConfig.voiceEnabled = [bool]$c.VoiceEnabledChoice.IsChecked
        $script:AppConfig.voiceName = [string]$c.VoiceChoice.SelectedItem
        $script:AppConfig.voiceVolume = [int]$c.VoiceVolumeChoice.Value
        Stop-PetVoice
        $script:AppConfig.nickname = $nickname
        $script:AppConfig.topmost = [bool]$c.TopmostChoice.IsChecked
        $script:Window.Topmost = $script:AppConfig.topmost
        $script:AppConfig.speechEnabled = [bool]$c.SpeechChoice.IsChecked
        $script:AppConfig.phrases = $changedPhrases
        $newScale = [Math]::Round(0.7 + ([int]$c.ScaleChoice.Value - 1) * 0.1, 2)
        $script:AppConfig.scale = $newScale
        Resize-Pet 0
        $newMode = if ($c.ModeChoice.SelectedIndex -eq 1) { 'companion' } else { 'activity' }
        Set-PetMode $newMode $false
        $script:PanelWindow.DialogResult = $true
    })
    [void]$script:PanelWindow.ShowDialog()
    if ($script:PanelWindow.DialogResult -eq $true) { Say '小屋布置好啦！我会记住的～' }
    } catch {
        [void][System.Windows.MessageBox]::Show(('设置窗口暂时出问题了：' + $_.Exception.Message), '小G提醒')
    } finally {
        $script:PanelWindow = $null
        $script:PanelControls = $null
        Schedule-Auto
        Schedule-Ambient
    }
}
function Resize-Pet([double]$step) {
    if ($script:Mode -eq 'Walk') { Set-Mode 'Idle' }
    $newScale = [Math]::Round([Math]::Max(0.7, [Math]::Min(1.65, $script:AppConfig.scale + $step)), 2)
    $script:AppConfig.scale = $newScale
    $script:Window.Width = 298 * $newScale
    $script:Window.Height = 400 * $newScale
    $area = [System.Windows.SystemParameters]::WorkArea
    $script:Window.Left = [Math]::Max($area.Left, [Math]::Min($script:Window.Left, $area.Right - $script:Window.Width))
    $script:Window.Top = [Math]::Max($area.Top, [Math]::Min($script:Window.Top, $area.Bottom - $script:Window.Height))
    Save-Settings
}

function Interact-WithPet {
    $script:LastInteraction = [DateTime]::UtcNow
    Set-Mode 'Wave'
    Say-From 'interaction' $true
}

$menu = New-Object System.Windows.Controls.ContextMenu
$script:Menu = $menu
$menu.Style = $script:Window.FindResource('HoneyMenu')
$commands = @(
  @('打开 ChatGPT 网页  ↗','Chat'),
  @('看看今日天气  ☀','Weather'), @('工作台  📒','Life'),
  @('','Divider'),
  @('摸摸小G','Interact'), @('带小G散步','Walk'),
  @('给小G盖毯子','Sleep'), @('叫醒小G','Idle'),
  @('','Divider'),
  @('活动模式 · 点击切换','ToggleMode'),
  @('打开小G 控制台  ⚙','Settings'),
  @('检查小G 更新  ✨','CheckUpdate'),
  @('始终置顶：已开启','Topmost'),
  @('','Divider'),
  @('退出小G','Exit')
)
foreach ($entry in $commands) {
    if ($entry[1] -eq 'Divider') {
        $line = New-Object System.Windows.Controls.Separator
        $line.Style = $script:Window.FindResource('HoneySeparator')
        [void]$menu.Items.Add($line)
        continue
    }
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $entry[0]; $item.Tag = $entry[1]
    $item.Style = $script:Window.FindResource('HoneyItem')
    if ($entry[1] -eq 'ToggleMode') { $script:ModeMenuItem = $item }
    if ($entry[1] -eq 'Topmost') { $script:TopmostMenuItem = $item }
    if ($entry[1] -eq 'Walk') { $script:WalkMenuItem = $item }
    if ($entry[1] -eq 'Focus') { $script:FocusMenuItem = $item }
    $item.Add_Click({
      param($sender, $eventArgs)
      switch ([string]$sender.Tag) {
        'Chat' { Open-ChatGPT }
        'Todo' { Show-LifeDesk 'todo' }
        'Weather' { Start-WeatherExperience }
        'Life' { Show-LifeDesk 'todo' }
        'Focus' { Toggle-FocusQuick }
        'Interact' { Interact-WithPet }
        'Settings' { Show-ControlPanel }
        'CheckUpdate' { Start-UpdateCheck -Manual }
        'ToggleMode' {
            if ($script:AppConfig.mode -eq 'activity') { Set-PetMode 'companion' }
            else { Set-PetMode 'activity' }
        }
        'Topmost' {
            $script:Window.Topmost = -not $script:Window.Topmost
            $script:AppConfig.topmost = $script:Window.Topmost
            Save-Settings
            Update-Menu-States
            if ($script:Window.Topmost) { Say '置顶已开启，我会陪在你眼前～' }
            else { Say '置顶已关闭，需要我的时候再叫我～' }
        }
        'Exit' { $script:Window.Close() }
        default {
            $script:LastInteraction = [DateTime]::UtcNow
            Set-Mode ([string]$sender.Tag)
        }
      }
    })
    [void]$menu.Items.Add($item)
}
(Part 'Root').ContextMenu = $menu
function Update-Menu-States {
    if ($script:AppConfig.mode -eq 'activity') {
        $script:ModeMenuItem.Header = '当前：活动模式  ⇄  切换陪伴'
        $script:WalkMenuItem.IsEnabled = $true
        $script:WalkMenuItem.Header = '带小G散步'
    } else {
        $script:ModeMenuItem.Header = '当前：陪伴模式  ⇄  切换活动'
        $script:WalkMenuItem.IsEnabled = $false
        $script:WalkMenuItem.Header = '散步（活动模式下可用）'
    }
    $script:TopmostMenuItem.Header = if ($script:Window.Topmost) { '始终置顶：已开启  ✓' } else { '始终置顶：已关闭  ×' }
    if ($null -ne $script:FocusMenuItem) {
        if ($script:FocusRunning) { $script:FocusMenuItem.Header = '番茄钟：暂停专注  ⏸' }
        elseif ($script:FocusRemaining -gt 0) { $script:FocusMenuItem.Header = '番茄钟：继续专注  ▶' }
        else { $script:FocusMenuItem.Header = '番茄钟：开始专注  🍅' }
    }
}
$menu.Add_Opened({
    # The pet stays still while its owner is choosing an interaction.
    if ($script:StoryActive) { Set-Mode 'Idle' }
    Update-Menu-States
})
Update-Menu-States

# Mouse hover is enough to receive a wave; cooldown avoids a wave every time
# the pointer briefly crosses the transparent window.
$script:PetImage.Add_MouseEnter({
    $now = [DateTime]::UtcNow
    if (($now - $script:LastHover).TotalSeconds -lt 5 -or
        ($now - $script:LastInteraction).TotalSeconds -lt 2) { return }
    $script:LastHover = $now
    $script:LastInteraction = $now
    Set-Mode 'Wave'
    Say-From 'interaction' $true
})

# A short click is an interaction; only a deliberate mouse move (>9px)
# turns into a window drag. This replaces DragMove-on-mousedown, which
# swallowed normal clicks in v0.2.
$script:Window.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    $script:PointerPressed = $true
    $script:IgnoreClickRelease = $false
    $script:PressPoint = $eventArgs.GetPosition($script:Window)
    [void]$script:Window.CaptureMouse()
})
$script:Window.Add_MouseMove({
    param($sender, $eventArgs)
    if (-not $script:PointerPressed -or $eventArgs.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
    $point = $eventArgs.GetPosition($script:Window)
    $distance = [Math]::Sqrt([Math]::Pow($point.X - $script:PressPoint.X, 2) + [Math]::Pow($point.Y - $script:PressPoint.Y, 2))
    if ($distance -lt 9) { return }
    $script:PointerPressed = $false
    $script:IgnoreClickRelease = $true
    $script:FocusHudDragged = $true
    $script:LastInteraction = [DateTime]::UtcNow
    if ($script:Mode -eq 'Walk') { Set-Mode 'Idle' }
    $script:Window.ReleaseMouseCapture()
    try { $script:Window.DragMove() } catch { }
})
$script:Window.Add_MouseLeftButtonUp({
    if ($script:PointerPressed) {
        $script:PointerPressed = $false
        $script:Window.ReleaseMouseCapture()
        if (-not $script:IgnoreClickRelease) { Interact-WithPet }
    }
    $script:IgnoreClickRelease = $false
})

$script:AmbientTimer = New-Object System.Windows.Threading.DispatcherTimer
function Schedule-Ambient {
    $script:AmbientTimer.Stop()
    $wait = if ($script:AppConfig.mode -eq 'activity') {
        Get-Random -Minimum 30 -Maximum 48
    } else {
        Get-Random -Minimum 48 -Maximum 76
    }
    $script:AmbientTimer.Interval = [TimeSpan]::FromSeconds($wait)
    $script:AmbientTimer.Start()
}
$script:AmbientTimer.Add_Tick({
    if (-not $script:FocusRunning -and $script:AppConfig.speechEnabled -and -not $script:Menu.IsOpen -and
        ($null -eq $script:PanelWindow) -and ($null -eq $script:LifeWindow) -and
        ($null -eq $script:WeatherWindow) -and
        ([DateTime]::UtcNow - $script:LastInteraction).TotalSeconds -gt 17) {
        Say-From $script:AppConfig.mode
    }
    Schedule-Ambient
})

# Productivity features share the existing WPF dispatcher and custom pet bubble.
. (Join-Path $PSScriptRoot 'VoiceDesk.ps1')
. (Join-Path $PSScriptRoot 'LifeDesk.ps1')
. (Join-Path $PSScriptRoot 'UpdateDesk.ps1')

$script:Window.Add_SourceInitialized({
    try {
        $interop = New-Object System.Windows.Interop.WindowInteropHelper($script:Window)
        $script:HotkeyHandle = $interop.Handle
        $script:Source = [System.Windows.Interop.HwndSource]::FromHwnd($script:HotkeyHandle)
        $script:HotkeyHook = [System.Windows.Interop.HwndSourceHook]{
            param([IntPtr]$hwnd, [int]$message, [IntPtr]$wParam, [IntPtr]$lParam, [ref]$handled)
            if ($message -eq 0x0312 -and $wParam.ToInt32() -eq 7318) {
                Open-ChatGPT
                $handled.Value = $true
            }
            return [IntPtr]::Zero
        }
        $script:Source.AddHook($script:HotkeyHook)
        if (-not (Register-CurrentHotkey)) { Say 'Ctrl+Alt+G 被其他程序占用了，仍可右键打开 ChatGPT。' }
    } catch { Say '快捷键暂不可用，但右键仍可打开聊天。' }
})
$script:Window.Add_Closed({
    Stop-PetVoice -Dispose
    $script:BubbleTimer.Stop(); $script:ActionTimer.Stop()
    $script:MotionTimer.Stop(); $script:FootstepTimer.Stop(); $script:GestureTimer.Stop()
    $script:BlinkTimer.Stop(); $script:BlinkRestoreTimer.Stop()
    $script:AutoTimer.Stop(); $script:AmbientTimer.Stop()
    if ($null -ne $script:LifeTick) { $script:LifeTick.Stop() }
    if ($null -ne $script:WeatherDelayTimer) { $script:WeatherDelayTimer.Stop() }
    if ($null -ne $script:WeatherClient) { try { $script:WeatherClient.CancelAsync(); $script:WeatherClient.Dispose() } catch { } }
    if ($null -ne $script:WeatherLocationClient) { try { $script:WeatherLocationClient.CancelAsync(); $script:WeatherLocationClient.Dispose() } catch { } }
    if ($null -ne $script:FocusHud) { try { $script:FocusHud.Close() } catch { } }
    if ($null -ne $script:WeatherWindow) { try { $script:WeatherWindow.Close() } catch { } }
    if ($null -ne $script:UpdatePromptTimer) { $script:UpdatePromptTimer.Stop() }
    if ($null -ne $script:UpdateStartupTimer) { $script:UpdateStartupTimer.Stop() }
    if ($null -ne $script:UpdateTimeoutTimer) { $script:UpdateTimeoutTimer.Stop() }
    if ($null -ne $script:UpdateClient) {
        try { $script:UpdateClient.CancelAsync(); $script:UpdateClient.Dispose() } catch { }
    }
    if ($script:HotkeyRegistered) {
        [void][GTeacherNativeHotkey]::UnregisterHotKey($script:HotkeyHandle, 7318)
    }
    if ($null -ne $script:Source -and $null -ne $script:HotkeyHook) {
        $script:Source.RemoveHook($script:HotkeyHook)
    }
})

$script:Source = $null
$script:HotkeyHook = $null
$script:Window.Width = 298 * $script:AppConfig.scale
$script:Window.Height = 400 * $script:AppConfig.scale
$script:Window.Topmost = $script:AppConfig.topmost
$area = [System.Windows.SystemParameters]::WorkArea
$script:Window.Left = $area.Right - $script:Window.Width - 32
$script:Window.Top = $area.Bottom - $script:Window.Height - 16
Set-Mode 'Idle'
Schedule-Ambient
Schedule-Blink
Schedule-Auto
Start-UpdateCheckOnLaunch
if ($script:AppConfig.mode -eq 'activity') {
    Say ("{0}，我来探险啦！" -f $script:AppConfig.nickname)
} else {
    Say ("{0}，今天让我陪着你吧。" -f $script:AppConfig.nickname)
}
[void]$script:Window.ShowDialog()
