# 小 G 生活手账 v0.9 | Windows PowerShell 5.1 / WPF
# Dot-sourced by GTeacherPet.ps1. Personal content stays on this Windows account.

$script:LifeFile = Join-Path $script:SettingsDirectory 'life.json'
$script:LifeData = @{
    tasks = @(); notes = @(); reminders = @(); anniversaries = @()
    city = '北京'; careEnabled = $true; careMinutes = 60
    focusDays = @{}; lastAnniversaryDay = ''
}
if (Test-Path -LiteralPath $script:LifeFile) {
    try {
        $old = Get-Content -LiteralPath $script:LifeFile -Encoding UTF8 -Raw | ConvertFrom-Json
        foreach ($key in @('tasks','notes','reminders','anniversaries')) {
            if ($null -ne $old.PSObject.Properties[$key] -and $null -ne $old.$key) {
                $script:LifeData[$key] = @($old.$key | Where-Object { $null -ne $_ } | Select-Object -First 1000)
            }
        }
        if ($null -ne $old.PSObject.Properties['city'] -and -not [string]::IsNullOrWhiteSpace($old.city)) {
            $script:LifeData.city = ([string]$old.city).Trim()
        }
        if ($null -ne $old.PSObject.Properties['careEnabled']) { $script:LifeData.careEnabled = [bool]$old.careEnabled }
        if ($null -ne $old.PSObject.Properties['careMinutes'] -and [int]$old.careMinutes -in @(30,45,60,90,120)) {
            $script:LifeData.careMinutes = [int]$old.careMinutes
        }
        if ($null -ne $old.PSObject.Properties['focusDays'] -and $null -ne $old.focusDays) {
            foreach ($entry in $old.focusDays.PSObject.Properties) {
                if ($entry.Name -match '^\d{4}-\d{2}-\d{2}$') { $script:LifeData.focusDays[$entry.Name] = [int]$entry.Value }
            }
        }
        if ($null -ne $old.PSObject.Properties['lastAnniversaryDay']) {
            $script:LifeData.lastAnniversaryDay = [string]$old.lastAnniversaryDay
        }
    } catch {
        # Do not destroy an unreadable file. Make a copy before the next save.
        try { Copy-Item -LiteralPath $script:LifeFile -Destination ($script:LifeFile + '.unreadable-' + (Get-Date -Format 'yyyyMMddHHmmss')) } catch { }
    }
}

function Save-Life {
    if (-not (Test-Path -LiteralPath $script:SettingsDirectory)) {
        [void](New-Item -ItemType Directory -Path $script:SettingsDirectory -Force)
    }
    $tmp = $script:LifeFile + '.pending'
    $json = $script:LifeData | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    if ([System.IO.File]::Exists($script:LifeFile)) {
        [System.IO.File]::Replace($tmp, $script:LifeFile, ($script:LifeFile + '.bak'))
    } else {
        [System.IO.File]::Move($tmp, $script:LifeFile)
    }
}

function New-LifeId { return [Guid]::NewGuid().ToString('N') }
function Life-Selected([string]$listName) {
    if ($null -eq $script:LifeControls) { return '' }
    $row = $script:LifeControls[$listName].SelectedItem
    if ($null -eq $row) { return '' }
    return [string]$row.Tag
}
function Life-Row([string]$listName, [string]$id, [string]$display) {
    $row = New-Object System.Windows.Controls.ListBoxItem
    $row.Content = $display
    $row.Tag = $id
    $row.Padding = [System.Windows.Thickness]::new(7)
    [void]$script:LifeControls[$listName].Items.Add($row)
}
function Life-Warn([string]$message) {
    [void][System.Windows.MessageBox]::Show($message, '小 G 老师的小提醒')
}
function Life-Confirm([string]$message) {
    return ([System.Windows.MessageBox]::Show($message, '小 G 老师确认一下',
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes)
}
function Life-Clean([string]$text, [int]$max) {
    $value = $text.Trim()
    if ($value.Length -gt $max) { return $value.Substring(0,$max) }
    return $value
}
function Life-Visible {
    return ($null -ne $script:LifeWindow -and $script:LifeWindow.IsVisible -and $null -ne $script:LifeControls)
}

function Refresh-LifeTasks {
    if (-not (Life-Visible)) { return }
    $c = $script:LifeControls
    $c.TaskRows.Items.Clear()
    $open = 0; $done = 0
    $today = (Get-Date).ToString('yyyy-MM-dd')
    foreach ($t in @($script:LifeData.tasks)) {
        if ([bool]$t.done -and [string]$t.completedOn -ne $today) { continue }
        if ([bool]$t.done) { $done++ } else { $open++ }
        $symbol = if ([bool]$t.done) { '☑' } else { '☐' }
        Life-Row 'TaskRows' ([string]$t.id) ("$symbol  " + [string]$t.text)
    }
    $c.TaskSummary.Text = "还剩 $open 项 · 已完成 $done 项"
}
function Refresh-LifeNotes {
    if (-not (Life-Visible)) { return }
    $script:LifeControls.NoteRows.Items.Clear()
    foreach ($note in @($script:LifeData.notes)) {
        Life-Row 'NoteRows' ([string]$note.id) ([string]$note.title)
    }
}
function Next-Anniversary([object]$entry) {
    $baseDate = [DateTime]::ParseExact([string]$entry.date, 'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture)
    $today = (Get-Date).Date
    if (-not [bool]$entry.annual -or $baseDate -ge $today) { return $baseDate.Date }
    $next = $baseDate.AddYears([Math]::Max(0,$today.Year - $baseDate.Year)).Date
    if ($next -lt $today) { $next = $next.AddYears(1) }
    return $next
}
function Refresh-LifeAnniversaries {
    if (-not (Life-Visible)) { return }
    $script:LifeControls.AnniversaryRows.Items.Clear()
    foreach ($a in @($script:LifeData.anniversaries)) {
        try {
            $next = Next-Anniversary $a
            $days = [int]($next - (Get-Date).Date).TotalDays
            $description = if ($days -lt 0) { '已经过去' } elseif ($days -eq 0) { '就是今天 🎉' } else { "还有 $days 天" }
            Life-Row 'AnniversaryRows' ([string]$a.id) ("{0}  ·  {1}（{2:MM-dd}）" -f $a.title,$description,$next)
        } catch { }
    }
}
function Refresh-Focus {
    $left = [Math]::Max(0,[int]$script:FocusRemaining)
    if ($script:FocusRunning) {
        $left = [Math]::Max(0, [int][Math]::Ceiling(($script:FocusDeadline - [DateTime]::UtcNow).TotalSeconds))
    }
    Update-FocusHud
    if (-not (Life-Visible)) { return }
    $c = $script:LifeControls
    $c.FocusClock.Text = ('{0:00}:{1:00}' -f [int][Math]::Floor($left/60), [int]($left%60))
    $c.FocusStatus.Text = if ($script:FocusRunning) {
        if ($script:FocusKind -eq 'break') { '正在休息 · 小 G 陪你放松' } else { '专注进行中 · 小 G 安静陪伴' }
    } elseif ($left -gt 0) { '已暂停 · 随时可以继续' } else { '准备好就开始吧！' }
    $c.FocusPause.Content = if ($script:FocusRunning) { '⏸ 暂停' } else { '▶ 继续' }
    $c.FocusPause.IsEnabled = ($left -gt 0 -or $script:FocusRunning)
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $count = 0
    if ($script:LifeData.focusDays.ContainsKey($today)) { $count = [int]$script:LifeData.focusDays[$today] }
    $c.FocusProgress.Text = "今天完成 $count 个专注番茄 🍅"
}

$script:FocusKind = 'work'
$script:FocusDeadline = [DateTime]::MinValue
$script:FocusHud = $null
$script:FocusHudOffset = 0.0
$script:FocusHudDragged = $false
$script:FocusHudPositioning = $false
$script:LastCareAt = Get-Date
$script:LastCareCheck = [DateTime]::MinValue
$script:LastBedtimeDay = ''
$script:WeatherBusy = $false
$script:WeatherClient = $null
$script:WeatherLocationClient = $null
$script:WeatherDelayTimer = $null

function Start-Focus([int]$minutes, [string]$kind) {
    if ($minutes -lt 1 -or $minutes -gt 180) { return }
    $script:FocusKind = $kind
    $script:FocusRemaining = $minutes * 60
    $script:FocusDeadline = [DateTime]::UtcNow.AddSeconds($script:FocusRemaining)
    $script:FocusRunning = $true
    $script:StoryActive = $false
    $script:StorySteps.Clear()
    Set-Mode 'Type' $true
    $script:LastInteraction = [DateTime]::UtcNow
    if ($kind -eq 'work') { Say "专注 $minutes 分钟！我安静陪你，加油～ 🍅" }
    else { Say "休息 $minutes 分钟！伸伸懒腰，喝点水吧～ 🌷" }
    Refresh-Focus
    Update-Menu-States
}
function Pause-Focus {
    if (-not $script:FocusRunning) { return }
    $script:FocusRemaining = [Math]::Max(1,[int][Math]::Ceiling(($script:FocusDeadline - [DateTime]::UtcNow).TotalSeconds))
    $script:FocusRunning = $false
    Say '番茄钟先暂停啦，需要时再继续。'
    Refresh-Focus; Update-Menu-States
}
function Resume-Focus {
    if ($script:FocusRemaining -le 0 -or $script:FocusRunning) { return }
    $script:FocusDeadline = [DateTime]::UtcNow.AddSeconds($script:FocusRemaining)
    $script:FocusRunning = $true
    Say '继续加油！小 G 又开始安静陪你啦。'
    Refresh-Focus; Update-Menu-States
}
function Reset-Focus {
    $script:FocusRunning = $false
    $script:FocusRemaining = 0
    $script:FocusKind = 'work'
    Refresh-Focus; Update-Menu-States
}
function Toggle-FocusQuick {
    if ($script:FocusRunning) { Pause-Focus }
    elseif ($script:FocusRemaining -gt 0) { Resume-Focus }
    else { Start-Focus 25 'work' }
}

function Ensure-FocusHud {
    if ($null -ne $script:FocusHud) { return }
    [xml]$hudXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="216" Height="62" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" ShowActivated="False"
        ResizeMode="NoResize" IsHitTestVisible="False" Topmost="True"
        FontFamily="Microsoft YaHei UI">
  <Border Margin="5" Background="#FFFFEBC2" BorderBrush="#FFE7B65B"
          BorderThickness="1.8" CornerRadius="18" Padding="9,6">
    <Border.Effect>
      <DropShadowEffect Color="#77613A" Opacity="0.24" BlurRadius="12" ShadowDepth="3"/>
    </Border.Effect>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="48"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="HudIcon" Text="⏰" FontSize="29" VerticalAlignment="Center" HorizontalAlignment="Center"/>
      <StackPanel Grid.Column="1" HorizontalAlignment="Left" VerticalAlignment="Center">
        <TextBlock x:Name="HudClock" Text="25:00" FontSize="22" FontWeight="Bold" Foreground="#FF614968" LineHeight="23"/>
        <TextBlock x:Name="HudCaption" Text="小 G 陪你专注 ✨" FontSize="11" Foreground="#FF896A49"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader($hudXaml)
    $script:FocusHud = [System.Windows.Markup.XamlReader]::Load($reader)
    $script:FocusHud.Owner = $script:Window
    $script:HudClock = $script:FocusHud.FindName('HudClock')
    $script:HudIcon = $script:FocusHud.FindName('HudIcon')
    $script:HudCaption = $script:FocusHud.FindName('HudCaption')
}

function Update-FocusHud {
    if ($script:FocusHudPositioning) { return }
    $active = ($script:FocusRunning -or $script:FocusRemaining -gt 0)
    if (-not $active) {
        if ($null -ne $script:FocusHud -and $script:FocusHud.IsVisible) { $script:FocusHud.Hide() }
        if ($script:FocusHudOffset -gt 0 -and -not $script:FocusHudDragged) {
            $script:FocusHudPositioning = $true
            try {
                $area = [System.Windows.SystemParameters]::WorkArea
                $script:Window.Top = [Math]::Min($area.Bottom - $script:Window.Height,
                    $script:Window.Top + $script:FocusHudOffset)
            } finally { $script:FocusHudPositioning = $false }
        }
        $script:FocusHudOffset = 0
        $script:FocusHudDragged = $false
        return
    }
    Ensure-FocusHud
    $area = [System.Windows.SystemParameters]::WorkArea
    $targetTop = $script:Window.Top + $script:Window.Height - 7
    if ($targetTop + $script:FocusHud.Height -gt $area.Bottom - 7) {
        $shift = $targetTop + $script:FocusHud.Height - ($area.Bottom - 7)
        $oldTop = $script:Window.Top
        $script:FocusHudPositioning = $true
        try { $script:Window.Top = [Math]::Max($area.Top + 4, $script:Window.Top - $shift) }
        finally { $script:FocusHudPositioning = $false }
        $script:FocusHudOffset += [Math]::Max(0,$oldTop - $script:Window.Top)
        $targetTop = $script:Window.Top + $script:Window.Height - 7
    }
    $script:FocusHud.Topmost = $script:Window.Topmost
    $script:FocusHud.Left = [Math]::Max($area.Left + 4, [Math]::Min(
        $script:Window.Left + ($script:Window.Width - $script:FocusHud.Width)/2,
        $area.Right - $script:FocusHud.Width - 4))
    $script:FocusHud.Top = [Math]::Min($targetTop, $area.Bottom - $script:FocusHud.Height - 4)
    $left = if ($script:FocusRunning) {
        [Math]::Max(0,[int][Math]::Ceiling(($script:FocusDeadline - [DateTime]::UtcNow).TotalSeconds))
    } else { [Math]::Max(0,[int]$script:FocusRemaining) }
    $script:HudClock.Text = ('{0:00}:{1:00}' -f [int][Math]::Floor($left/60), [int]($left%60))
    $script:HudIcon.Text = if ($script:FocusRunning) { '⏰' } else { '⏸' }
    $script:HudCaption.Text = if (-not $script:FocusRunning) { '暂停中 · 等你回来' }
                              elseif ($script:FocusKind -eq 'break') { '休息一下 🌷' }
                              else { '小 G 陪你专注 ✨' }
    if (-not $script:FocusHud.IsVisible) { $script:FocusHud.Show() }
}

# When the pet is dragged, the timer follows the character instead of drifting away.
$script:Window.Add_LocationChanged({ Update-FocusHud })
$script:Window.Add_SizeChanged({ Update-FocusHud })

function Complete-Focus {
    $script:FocusRunning = $false
    $script:FocusRemaining = 0
    if ($script:FocusKind -eq 'work') {
        $day = (Get-Date).ToString('yyyy-MM-dd')
        $old = 0
        if ($script:LifeData.focusDays.ContainsKey($day)) { $old = [int]$script:LifeData.focusDays[$day] }
        $script:LifeData.focusDays[$day] = $old + 1
        Save-Life
        Set-Mode 'Happy' $true
        Say '叮咚！完成一个专注番茄啦！休息一下吧～ 🍅'
    } else {
        Set-Mode 'Wave' $true
        Say '休息时间到～精神恢复了吗？我们慢慢继续。'
    }
    Refresh-Focus; Update-Menu-States
}

function Check-LifeCare {
    $now = Get-Date
    if (($now - $script:LastCareCheck).TotalSeconds -lt 30) { return }
    $script:LastCareCheck = $now
    if (-not $script:LifeData.careEnabled -or -not $script:AppConfig.speechEnabled -or
        $script:FocusRunning -or $script:Menu.IsOpen -or
        $null -ne $script:LifeWindow -or $null -ne $script:PanelWindow -or
        $null -ne $script:WeatherWindow) { return }
    if ($now.Hour -ge 23) {
        $day = $now.ToString('yyyy-MM-dd')
        if ($script:LastBedtimeDay -ne $day) {
            $script:LastBedtimeDay = $day
            Say '已经很晚啦，论文可以慢慢写，也要照顾好自己呀。🌙'
        }
        return
    }
    if ($now.Hour -lt 9) { return }
    if (($now - $script:LastCareAt).TotalMinutes -lt [int]$script:LifeData.careMinutes) { return }
    $script:LastCareAt = $now
    $lines = @(
        '小 G 提醒：喝一口水吧～🥤',
        '盯屏幕有一会儿啦，看看远处放松眼睛！',
        '我们站起来伸个懒腰，好不好？',
        '做得很棒！不过肩膀也该松一松啦。'
    )
    Say ([string]($lines | Get-Random))
}
function Check-LifeAnniversaries {
    $day = (Get-Date).ToString('yyyy-MM-dd')
    if ($script:LifeData.lastAnniversaryDay -eq $day) { return }
    foreach ($a in @($script:LifeData.anniversaries)) {
        try {
            if ((Next-Anniversary $a).Date -eq (Get-Date).Date) {
                $script:LifeData.lastAnniversaryDay = $day
                Save-Life
                Say ("🎉 今天是「{0}」！小 G 给你送上小星星！" -f $a.title)
                break
            }
        } catch { }
    }
}
$script:LifeTick = New-Object System.Windows.Threading.DispatcherTimer
$script:LifeTick.Interval = [TimeSpan]::FromSeconds(1)
$script:LifeTick.Add_Tick({
    if ($script:FocusRunning) {
        $script:FocusRemaining = [Math]::Max(0, [int][Math]::Ceiling(($script:FocusDeadline - [DateTime]::UtcNow).TotalSeconds))
        if ($script:FocusRemaining -le 0) { Complete-Focus }
    }
    Refresh-Focus
    # v0.9 pauses the timed-reminder feature; old reminders are kept in life.json.
    Check-LifeCare
    if ([DateTime]::UtcNow.Second % 30 -eq 0) { Check-LifeAnniversaries }
})
$script:LifeTick.Start()

# The user chooses a city explicitly; the app never guesses their address.
# Both asynchronous JSON requests use Open-Meteo's public non-commercial API.
$script:WeatherText = "输入城市后点「查天气」吧！小 G 会帮你看看今天适合怎样出门。"
function Weather-Describe([int]$code) {
    if ($code -eq 0) { return '晴朗 ☀' }
    if ($code -le 3) { return '多云 ⛅' }
    if ($code -le 48) { return '有雾 🌫' }
    if ($code -le 67) { return '有雨 🌧' }
    if ($code -le 77) { return '有雪 ❄' }
    if ($code -le 82) { return '阵雨 🌦' }
    if ($code -le 86) { return '阵雪 ❄' }
    if ($code -ge 95) { return '雷雨 ⛈' }
    return '天气变化中'
}
function Weather-Set([string]$status) {
    $script:WeatherText = $status
    if ($null -ne $script:WeatherControls) { $script:WeatherControls.WeatherInfo.Text = $status }
}
function Weather-Fail([string]$detail) {
    $script:WeatherBusy = $false
    Weather-Set ("暂时没有查到天气（$detail）。可以稍后重试；其他功能仍能离线使用。")
}
function Get-LifeWeather {
    if ($script:WeatherBusy -or $null -eq $script:WeatherControls) { return }
    $city = Life-Clean ([string]$script:WeatherControls.WeatherCity.Text) 60
    if ($city.Length -lt 2) { Life-Warn '先输入城市名吧，比如北京、上海或 Singapore。'; return }
    $script:LifeData.city = $city
    Save-Life
    $script:WeatherBusy = $true
    Weather-Set ("小 G 正在查找「$city」的天气… ☁")
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $url = 'https://geocoding-api.open-meteo.com/v1/search?name=' +
                [Uri]::EscapeDataString($city) + '&count=1&language=zh&format=json'
        $script:WeatherLocationClient = New-Object System.Net.WebClient
        $script:WeatherLocationClient.Encoding = [System.Text.Encoding]::UTF8
        $script:WeatherLocationClient.Add_DownloadStringCompleted({
            param($sender,$e)
            try {
                if ($null -ne $e.Error) { throw $e.Error }
                if ($e.Cancelled) { throw '请求已取消' }
                $geo = $e.Result | ConvertFrom-Json
                if ($null -eq $geo.PSObject.Properties['results'] -or
                    $null -eq $geo.results -or @($geo.results).Count -lt 1) { throw '没有找到这座城市' }
                $place = @($geo.results)[0]
                $script:WeatherPlace = [string]$place.name
                if ($null -ne $place.PSObject.Properties['admin1'] -and $place.admin1) {
                    $script:WeatherPlace += (' · ' + [string]$place.admin1)
                }
                $forecast = 'https://api.open-meteo.com/v1/forecast?latitude=' +
                    ([double]$place.latitude).ToString([System.Globalization.CultureInfo]::InvariantCulture) +
                    '&longitude=' +
                    ([double]$place.longitude).ToString([System.Globalization.CultureInfo]::InvariantCulture) +
                    '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m' +
                    '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max' +
                    '&timezone=auto&forecast_days=1'
                $script:WeatherClient = New-Object System.Net.WebClient
                $script:WeatherClient.Encoding = [System.Text.Encoding]::UTF8
                $script:WeatherClient.Add_DownloadStringCompleted({
                    param($source,$weatherArgs)
                    try {
                        if ($null -ne $weatherArgs.Error) { throw $weatherArgs.Error }
                        if ($weatherArgs.Cancelled) { throw '请求已取消' }
                        $data = $weatherArgs.Result | ConvertFrom-Json
                        $code = [int]$data.current.weather_code
                        $temp = [Math]::Round([double]$data.current.temperature_2m)
                        $feels = [Math]::Round([double]$data.current.apparent_temperature)
                        $low = [Math]::Round([double]$data.daily.temperature_2m_min[0])
                        $high = [Math]::Round([double]$data.daily.temperature_2m_max[0])
                        $rain = [int]$data.daily.precipitation_probability_max[0]
                        $description = Weather-Describe $code
                        $tip = if ($rain -ge 50) { '降雨概率不低，出门记得带伞哦～' }
                               elseif ($temp -le 8) { '有点冷，出门记得多穿一件。' }
                               elseif ($temp -ge 30) { '天气热热的，记得补水和防晒！' }
                               else { '今天也要好好照顾自己呀。' }
                        $stamp = (Get-Date).ToString('HH:mm')
                        Weather-Set ("{0}  ·  {1}`r`n`r`n现在 {2}℃（体感 {3}℃）`r`n今日 {4}～{5}℃ · 降雨概率最高 {6}%`r`n`r`n小 G：{7}`r`n`r`n更新于 {8}  ·  数据来源 Open-Meteo" -f
                            $script:WeatherPlace,$description,$temp,$feels,$low,$high,$rain,$tip,$stamp)
                        Say ("{0}，{1}，现在 {2}℃。{3}" -f $script:AppConfig.nickname,$description,$temp,$tip)
                    } catch { Weather-Fail $_.Exception.Message }
                    finally {
                        $script:WeatherBusy = $false
                        if ($null -ne $script:WeatherClient) { $script:WeatherClient.Dispose(); $script:WeatherClient = $null }
                    }
                })
                $script:WeatherClient.DownloadStringAsync([Uri]$forecast)
            } catch { Weather-Fail $_.Exception.Message }
            finally {
                if ($null -ne $script:WeatherLocationClient) {
                    $script:WeatherLocationClient.Dispose(); $script:WeatherLocationClient = $null
                }
            }
        })
        $script:WeatherLocationClient.DownloadStringAsync([Uri]$url)
    } catch { Weather-Fail $_.Exception.Message }
}

function Show-WeatherCard {
    if ($null -ne $script:WeatherWindow -and $script:WeatherWindow.IsVisible) {
        [void]$script:WeatherWindow.Activate()
        Get-LifeWeather
        return
    }
    try {
        [xml]$weatherXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="小 G 天气观察站" Width="426" Height="375" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        ShowInTaskbar="False" WindowStartupLocation="Manual" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style TargetType="{x:Type Button}">
      <Setter Property="Foreground" Value="#FF674A40"/>
      <Setter Property="Background" Value="#FFFFDA8E"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="Template">
        <Setter.Value><ControlTemplate TargetType="{x:Type Button}">
          <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" CornerRadius="12"
                  BorderBrush="#FFE3B66F" BorderThickness="1" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Background" Value="#FFFFC976"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Background" Value="#FFFFB85B"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate></Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="{x:Type TextBox}">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type TextBox}">
          <Border Background="#FFFFFEF7" CornerRadius="12" BorderBrush="#FFE7CA90" BorderThickness="1.5">
            <ScrollViewer x:Name="PART_ContentHost" Margin="7,2"/>
          </Border>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border Margin="13" CornerRadius="23" Background="#FFFFF7E4"
          BorderBrush="#FFE3BE79" BorderThickness="2" Padding="18">
    <Border.Effect><DropShadowEffect Color="#886647" BlurRadius="21" ShadowDepth="6" Opacity="0.3"/></Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Grid x:Name="WeatherDragHeader" Margin="0,0,0,14">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="☁️  小 G 的天气观察站" FontSize="19" FontWeight="Bold" Foreground="#FF5B4A6C"/>
          <TextBlock Text="让我看看今天的天空会是什么样～" FontSize="12" Foreground="#FF967C5D" Margin="0,4,0,0"/>
        </StackPanel>
        <Button x:Name="WeatherClose" Grid.Column="1" Content="✕" Width="35" Height="35" Padding="4"
                Background="#FFFFE9BE" VerticalAlignment="Top"/>
      </Grid>
      <DockPanel Grid.Row="1" LastChildFill="True" Margin="0,0,0,12">
        <Button x:Name="WeatherRefresh" DockPanel.Dock="Right" Content="🔎 查天气" Margin="8,0,0,0" MinWidth="104"/>
        <TextBox x:Name="WeatherCity" Height="38" MaxLength="60" ToolTip="输入城市：北京、广州、Singapore 等"/>
      </DockPanel>
      <Border Grid.Row="2" Background="#FFFFFDF5" CornerRadius="17" BorderBrush="#FFEBD4AC" BorderThickness="1">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="14">
          <TextBlock x:Name="WeatherInfo" TextWrapping="Wrap" FontSize="15" Foreground="#FF584B62" LineHeight="25"/>
        </ScrollViewer>
      </Border>
      <TextBlock Grid.Row="3" Text="✦ 天气来自 Open-Meteo · 按自己填写的城市查询" FontSize="11"
                 HorizontalAlignment="Center" Foreground="#FF99876D" Margin="0,11,0,0"/>
    </Grid>
  </Border>
</Window>
'@
        $reader = New-Object System.Xml.XmlNodeReader($weatherXaml)
        $script:WeatherWindow = [System.Windows.Markup.XamlReader]::Load($reader)
        $script:WeatherWindow.Owner = $script:Window
        $script:WeatherControls = @{}
        foreach ($name in @('WeatherInfo','WeatherCity','WeatherRefresh','WeatherClose','WeatherDragHeader')) {
            $script:WeatherControls[$name] = $script:WeatherWindow.FindName($name)
            if ($null -eq $script:WeatherControls[$name]) { throw "天气卡片缺少控件：$name" }
        }
        $script:WeatherControls.WeatherCity.Text = [string]$script:LifeData.city
        $script:WeatherControls.WeatherInfo.Text = $script:WeatherText
        $script:WeatherControls.WeatherRefresh.Add_Click({ Get-LifeWeather })
        $script:WeatherControls.WeatherClose.Add_Click({ $script:WeatherWindow.Close() })
        $script:WeatherControls.WeatherDragHeader.Add_MouseLeftButtonDown({
            try { $script:WeatherWindow.DragMove() } catch { }
        })
        $script:WeatherWindow.Add_Closed({
            $script:WeatherWindow = $null
            $script:WeatherControls = $null
        })
        $area = [System.Windows.SystemParameters]::WorkArea
        $left = $script:Window.Left - $script:WeatherWindow.Width + 26
        if ($left -lt $area.Left + 6) { $left = $script:Window.Left + $script:Window.Width - 18 }
        $script:WeatherWindow.Left = [Math]::Max($area.Left+6,[Math]::Min($left,$area.Right-$script:WeatherWindow.Width-6))
        $script:WeatherWindow.Top = [Math]::Max($area.Top+6,[Math]::Min(
            $script:Window.Top+15,$area.Bottom-$script:WeatherWindow.Height-6))
        $script:WeatherWindow.Show()
        Get-LifeWeather
    } catch {
        $script:WeatherWindow = $null
        $script:WeatherControls = $null
        Life-Warn ('天气小窗暂时打不开：' + $_.Exception.Message)
    }
}

function Start-WeatherExperience {
    $script:LastInteraction = [DateTime]::UtcNow
    # Weather is deliberate: interrupt any autonomous action sequence.
    $script:StoryActive = $false
    $script:StorySteps.Clear()
    Set-Mode 'Think' $true
    Say '嗯……让我查查今天的天空！ ☁️'
    if ($null -ne $script:WeatherWindow -and $script:WeatherWindow.IsVisible) {
        Show-WeatherCard
        return
    }
    if ($null -ne $script:WeatherDelayTimer) { $script:WeatherDelayTimer.Stop() }
    $script:WeatherDelayTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:WeatherDelayTimer.Interval = [TimeSpan]::FromMilliseconds(850)
    $script:WeatherDelayTimer.Add_Tick({
        $script:WeatherDelayTimer.Stop()
        Show-WeatherCard
    })
    $script:WeatherDelayTimer.Start()
}

function Show-LifeDesk([string]$page = 'todo') {
    $tabIndex = switch ($page) { 'focus' {1} 'notes' {2} 'anniversaries' {3} 'care' {4} default {0} }
    if (Life-Visible) {
        $script:LifeControls.LifeTabs.SelectedIndex = $tabIndex
        [void]$script:LifeWindow.Activate()
        return
    }
    try {
        [xml]$lifeXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="小 G 老师 · 生活手账" Width="810" Height="650" MinWidth="710" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="#FFFFF8E8"
        FontFamily="Microsoft YaHei UI" FontSize="14">
  <Window.Resources>
    <Style TargetType="{x:Type Button}">
      <Setter Property="Background" Value="#FFFFE2A7"/>
      <Setter Property="Foreground" Value="#FF654929"/>
      <Setter Property="Padding" Value="15,9"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="MinHeight" Value="36"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type Button}">
          <Border x:Name="RoundButton" Background="{TemplateBinding Background}"
                  BorderBrush="#FFE2BC73" BorderThickness="1.3" CornerRadius="13"
                  Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="RoundButton" Property="Background" Value="#FFFFD08E"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="RoundButton" Property="Background" Value="#FFFFC16F"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="{x:Type TextBox}">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="9,7"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type TextBox}">
          <Border Background="#FFFFFEF8" BorderBrush="#FFE7CB97"
                  BorderThickness="1.5" CornerRadius="12">
            <ScrollViewer x:Name="PART_ContentHost" Margin="7,3"/>
          </Border>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="{x:Type ListBox}">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type ListBox}">
          <Border Background="#FFFFFEF8" BorderBrush="#FFE6CB9C"
                  BorderThickness="1.3" CornerRadius="14" Padding="5">
            <ScrollViewer Focusable="False" CanContentScroll="True">
              <ItemsPresenter/>
            </ScrollViewer>
          </Border>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="{x:Type TabControl}">
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type TabControl}">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <TabPanel Grid.Row="0" IsItemsHost="True" KeyboardNavigation.TabIndex="1" Margin="3,1,3,0"/>
            <Border Grid.Row="1" Background="#FFFFFDF7" BorderBrush="#FFE6C58C"
                    BorderThickness="1" CornerRadius="17">
              <ContentPresenter x:Name="PART_SelectedContentHost" ContentSource="SelectedContent"/>
            </Border>
          </Grid>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="{x:Type TabItem}">
      <Setter Property="Foreground" Value="#FF765C4B"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type TabItem}">
          <Border x:Name="TabPill" Margin="2,2,2,9" Padding="13,9" CornerRadius="15"
                  Background="#FFFFF1D8" BorderBrush="#FFEBD2A5" BorderThickness="1">
            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="TabPill" Property="Background" Value="#FFFFE6B7"/></Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="TabPill" Property="Background" Value="#FFFFD68B"/>
              <Setter TargetName="TabPill" Property="BorderBrush" Value="#FFE0A74D"/>
              <Setter Property="Foreground" Value="#FF553A44"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="CarePill" TargetType="{x:Type RadioButton}">
      <Setter Property="Margin" Value="0,0,8,9"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type RadioButton}">
          <Border x:Name="CareTile" Background="#FFFFF8E9" BorderBrush="#FFE6CA93"
                  BorderThickness="1.2" CornerRadius="14" Padding="14,10">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="CareTile" Property="Background" Value="#FFFFEEC9"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="CareTile" Property="Background" Value="#FFFFD68B"/>
              <Setter TargetName="CareTile" Property="BorderBrush" Value="#FFE0AA53"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="CareSwitch" TargetType="{x:Type CheckBox}">
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="{x:Type CheckBox}">
          <Grid Margin="0,6,0,6">
            <Grid.ColumnDefinitions><ColumnDefinition Width="62"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border x:Name="SwitchTrack" Width="51" Height="29" CornerRadius="15"
                    Background="#FFE6DDC9" BorderBrush="#FFD7BD91" BorderThickness="1">
              <Ellipse x:Name="SwitchThumb" Width="21" Height="21" Fill="White"
                       HorizontalAlignment="Left" Margin="3"/>
            </Border>
            <ContentPresenter Grid.Column="1" ContentSource="Content" VerticalAlignment="Center"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="SwitchTrack" Property="Background" Value="#FFFFCF7B"/>
              <Setter TargetName="SwitchThumb" Property="HorizontalAlignment" Value="Right"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="19">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Margin="5,0,0,14">
      <TextBlock Text="✦ 小 G 老师的生活手账" FontSize="25" FontWeight="Bold" Foreground="#FF594467"/>
      <TextBlock Text="待办、专注、灵感和重要日子，都藏在这本小小的手账里。" FontSize="13" Foreground="#FF8C7655"/>
    </StackPanel>
    <Border Grid.Row="1" CornerRadius="13" BorderBrush="#FFE7C58E" BorderThickness="1.5" Background="#FFFFFDF6">
      <TabControl x:Name="LifeTabs" Margin="7" Background="#FFFFFDF6" FontSize="14">
        <TabItem Header="📝 今日待办">
          <Grid Margin="14">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="TaskSummary" Text="今天也要加油！" FontSize="16" Foreground="#FF6E5671" FontWeight="SemiBold" Margin="0,0,0,10"/>
            <ListBox x:Name="TaskRows" Grid.Row="1"/>
            <Grid Grid.Row="2" Margin="0,13,0,0">
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
              <TextBox x:Name="TaskInput" Height="39" MaxLength="150" ToolTip="例如：修改论文引言"/>
              <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,0">
                <Button x:Name="TaskAdd" Content="＋ 添加待办"/>
                <Button x:Name="TaskToggle" Content="✓ 完成 / 撤销"/>
                <Button x:Name="TaskDelete" Content="删除选中项" Background="#FFFFF0D8"/>
              </StackPanel>
            </Grid>
          </Grid>
        </TabItem>
        <TabItem Header="🍅 专注时光">
          <StackPanel Margin="20">
            <Border Background="#FFFFF0D1" BorderBrush="#FFEAC68A" BorderThickness="1.4" CornerRadius="20" Padding="24,25">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="⏰  和小 G 一起认真一会儿" FontWeight="SemiBold" FontSize="16"
                           Foreground="#FF8D6A59" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                <TextBlock x:Name="FocusClock" Text="00:00" FontSize="64" FontWeight="Bold"
                           Foreground="#FF5C4A69" HorizontalAlignment="Center"/>
                <TextBlock x:Name="FocusStatus" Text="准备好就开始吧！" Foreground="#FF7A6255" FontSize="16"
                           HorizontalAlignment="Center" Margin="0,0,0,22"/>
                <WrapPanel HorizontalAlignment="Center">
                  <Button x:Name="FocusStart25" Content="🍅 专注 25 分钟"/>
                  <Button x:Name="FocusStart45" Content="✨ 专注 45 分钟"/>
                  <Button x:Name="FocusBreak" Content="🌷 休息 5 分钟"/>
                </WrapPanel>
                <WrapPanel HorizontalAlignment="Center" Margin="0,10,0,0">
                  <Button x:Name="FocusPause" Content="⏸ 暂停" Background="#FFFFF9EC"/>
                  <Button x:Name="FocusReset" Content="↺ 重置" Background="#FFFFF9EC"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Background="#FFFFFCF4" BorderBrush="#FFEED9B6" BorderThickness="1" CornerRadius="17"
                    Padding="18" Margin="0,16,0,0">
              <StackPanel>
                <TextBlock x:Name="FocusProgress" Text="今天完成 0 个专注番茄 🍅"
                           FontSize="16" FontWeight="SemiBold" Foreground="#FF725978"/>
                <TextBlock Text="开始后，小 G 会留在原地安静陪你，脚边出现一个持续倒计时的小闹钟。时间到啦，它会开心地庆祝！"
                           TextWrapping="Wrap" LineHeight="22" Foreground="#FF8B785D" Margin="0,9,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </TabItem>
        <TabItem Header="📒 小 G 记事本">
          <Grid Margin="14">
            <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Grid Grid.Column="0" Margin="0,0,12,0">
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <TextBlock Text="我的小纸条" FontWeight="SemiBold" Foreground="#FF6D5874" Margin="0,0,0,7"/>
              <ListBox Grid.Row="1" x:Name="NoteRows"/>
            </Grid>
            <Grid Grid.Column="1">
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
              <TextBox x:Name="NoteTitle" MaxLength="80" Height="38" ToolTip="给这条笔记起个标题"/>
              <TextBox x:Name="NoteBody" Grid.Row="1" Margin="0,10,0,10" AcceptsReturn="True"
                       TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" MaxLength="20000"/>
              <WrapPanel Grid.Row="2">
                <Button x:Name="NoteNew" Content="＋ 新建"/>
                <Button x:Name="NoteSave" Content="保存笔记 ✓"/>
                <Button x:Name="NoteDelete" Content="删除选中的笔记" Background="#FFFFF0D8"/>
              </WrapPanel>
            </Grid>
          </Grid>
        </TabItem>
        <TabItem Header="🎂 重要日子">
          <Grid Margin="14">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <TextBlock Text="重要日子都记得住。每年重复的生日、纪念日也可以自动倒计时。" TextWrapping="Wrap" Foreground="#FF7A6550" Margin="0,0,0,10"/>
            <ListBox x:Name="AnniversaryRows" Grid.Row="1"/>
            <StackPanel Grid.Row="2" Margin="0,11,0,0">
              <WrapPanel Margin="0,0,0,9">
                <TextBox x:Name="AnniversaryInput" Width="300" MaxLength="80" ToolTip="例如：我们的纪念日" Margin="0,0,10,0"/>
                <DatePicker x:Name="AnniversaryDate" Width="150" Margin="0,0,12,0"/>
                <CheckBox x:Name="AnniversaryAnnual" Content="每年重复" VerticalAlignment="Center" IsChecked="True"/>
              </WrapPanel>
              <WrapPanel>
                <Button x:Name="AnniversaryAdd" Content="＋ 记录日子"/>
                <Button x:Name="AnniversaryDelete" Content="删除选中的日子" Background="#FFFFF0D8"/>
              </WrapPanel>
            </StackPanel>
          </Grid>
        </TabItem>
        <TabItem Header="🌷 关怀设置">
          <StackPanel Margin="20">
            <Border Background="#FFFFF2DC" BorderBrush="#FFEBD0A4" BorderThickness="1.3" CornerRadius="20" Padding="24">
              <StackPanel>
                <TextBlock Text="🌷  让小 G 温柔地关心你" FontWeight="Bold" FontSize="19"
                           Foreground="#FF64527A" Margin="0,0,0,6"/>
                <TextBlock Text="偶尔提醒喝水、伸展和休息。你专注时，小 G 会懂事地保持安静。"
                           TextWrapping="Wrap" Foreground="#FF8A7159" Margin="0,0,0,20"/>
                <CheckBox x:Name="CareToggle" Style="{StaticResource CareSwitch}"
                          Content="开启小 G 的日常关怀" FontSize="16" Foreground="#FF5F5067"/>
                <TextBlock Text="✨  关怀间隔" FontWeight="SemiBold" FontSize="16"
                           Foreground="#FF6B536F" Margin="0,20,0,12"/>
                <WrapPanel>
                  <RadioButton x:Name="Care30" Style="{StaticResource CarePill}" GroupName="CareInterval" Content="30 分钟"/>
                  <RadioButton x:Name="Care45" Style="{StaticResource CarePill}" GroupName="CareInterval" Content="45 分钟"/>
                  <RadioButton x:Name="Care60" Style="{StaticResource CarePill}" GroupName="CareInterval" Content="60 分钟"/>
                  <RadioButton x:Name="Care90" Style="{StaticResource CarePill}" GroupName="CareInterval" Content="90 分钟"/>
                  <RadioButton x:Name="Care120" Style="{StaticResource CarePill}" GroupName="CareInterval" Content="120 分钟"/>
                </WrapPanel>
                <Button x:Name="CareSave" Content="💛 保存关怀设置" HorizontalAlignment="Left" Margin="0,14,0,0"/>
              </StackPanel>
            </Border>
            <TextBlock Text="小提示：日常关怀在 09:00–23:00 之间出现，夜深后也会轻声说一句晚安。关闭后不会主动弹出关怀台词。"
                       TextWrapping="Wrap" Foreground="#FF94816D" Margin="10,17,10,0"/>
          </StackPanel>
        </TabItem>
      </TabControl>
    </Border>
    <TextBlock Grid.Row="2" Text="✦ 小 G 的生活功能不会读取你的屏幕内容，也不需要 ChatGPT API。" FontSize="12" Foreground="#FF927C62" HorizontalAlignment="Right" Margin="0,10,4,0"/>
  </Grid>
</Window>
'@
        $reader = New-Object System.Xml.XmlNodeReader($lifeXaml)
        $script:LifeWindow = [System.Windows.Markup.XamlReader]::Load($reader)
        $script:LifeWindow.Owner = $script:Window
        $script:LifeControls = @{}
        foreach ($id in @('LifeTabs','TaskRows','TaskSummary','TaskInput','TaskAdd','TaskToggle','TaskDelete',
            'FocusClock','FocusStatus','FocusProgress','FocusStart25','FocusStart45','FocusBreak','FocusPause','FocusReset',
            'NoteRows','NoteTitle','NoteBody','NoteNew','NoteSave','NoteDelete',
            'AnniversaryRows','AnniversaryInput','AnniversaryDate','AnniversaryAnnual','AnniversaryAdd','AnniversaryDelete',
            'CareToggle','Care30','Care45','Care60','Care90','Care120','CareSave')) {
            $script:LifeControls[$id] = $script:LifeWindow.FindName($id)
            if ($null -eq $script:LifeControls[$id]) { throw "生活手账缺少控件：$id" }
        }
        $c = $script:LifeControls
        $c.LifeTabs.SelectedIndex = $tabIndex
        $c.AnniversaryDate.SelectedDate = (Get-Date).Date
        $c.CareToggle.IsChecked = [bool]$script:LifeData.careEnabled
        $careId = 'Care' + ([int]$script:LifeData.careMinutes).ToString()
        if (-not $c.ContainsKey($careId)) { $careId = 'Care60' }
        $c[$careId].IsChecked = $true
        Initialize-LifeButtons
        $script:LifeWindow.Add_Closed({
            $script:LifeWindow = $null
            $script:LifeControls = $null
        })
        $script:LifeWindow.Show()
        Refresh-LifeTasks; Refresh-LifeNotes; Refresh-LifeAnniversaries; Refresh-Focus
    } catch {
        $script:LifeWindow = $null; $script:LifeControls = $null
        Life-Warn ('生活手账暂时没有打开：' + $_.Exception.Message)
    }
}

function Initialize-LifeButtons {
    $c = $script:LifeControls
    $c.TaskAdd.Add_Click({
        $v = Life-Clean ([string]$script:LifeControls.TaskInput.Text) 150
        if ([string]::IsNullOrWhiteSpace($v)) { Life-Warn '先写下要完成的小任务吧～'; return }
        if (@($script:LifeData.tasks).Count -ge 500) { Life-Warn '待办已经太多啦，请整理后再添加。'; return }
        $script:LifeData.tasks += [pscustomobject]@{
            id = New-LifeId; text = $v; done = $false; completedOn = ''; created = (Get-Date).ToString('yyyy-MM-dd')
        }
        Save-Life
        $script:LifeControls.TaskInput.Text = ''
        Refresh-LifeTasks
    })
    $c.TaskToggle.Add_Click({
        $id = Life-Selected 'TaskRows'
        if (-not $id) { Life-Warn '先选一条待办吧～'; return }
        foreach ($t in @($script:LifeData.tasks)) {
            if ([string]$t.id -eq $id) {
                $t.done = -not [bool]$t.done
                $t.completedOn = if ([bool]$t.done) { (Get-Date).ToString('yyyy-MM-dd') } else { '' }
                if ([bool]$t.done) { Say '勾掉一件事啦！又迈出一小步，真棒！ ✦' }
                break
            }
        }
        Save-Life; Refresh-LifeTasks
    })
    $c.TaskDelete.Add_Click({
        $id = Life-Selected 'TaskRows'
        if (-not $id) { Life-Warn '请先选中一条待办。'; return }
        if (-not (Life-Confirm '确定删除这条待办吗？')) { return }
        $script:LifeData.tasks = @($script:LifeData.tasks | Where-Object { [string]$_.id -ne $id })
        Save-Life; Refresh-LifeTasks
    })
    $c.FocusStart25.Add_Click({ Start-Focus 25 'work' })
    $c.FocusStart45.Add_Click({ Start-Focus 45 'work' })
    $c.FocusBreak.Add_Click({ Start-Focus 5 'break' })
    $c.FocusPause.Add_Click({
        if ($script:FocusRunning) { Pause-Focus } else { Resume-Focus }
    })
    $c.FocusReset.Add_Click({ Reset-Focus; Say '番茄钟已重置，我们重新开始也没关系。' })
    $c.NoteRows.Add_SelectionChanged({
        $id = Life-Selected 'NoteRows'
        if (-not $id) { return }
        foreach ($n in @($script:LifeData.notes)) {
            if ([string]$n.id -eq $id) {
                $script:LifeControls.NoteTitle.Text = [string]$n.title
                $script:LifeControls.NoteBody.Text = [string]$n.body
                break
            }
        }
    })
    $c.NoteNew.Add_Click({
        $script:LifeControls.NoteRows.SelectedIndex = -1
        $script:LifeControls.NoteTitle.Text = ''
        $script:LifeControls.NoteBody.Text = ''
        [void]$script:LifeControls.NoteTitle.Focus()
    })
    $c.NoteSave.Add_Click({
        $title = Life-Clean ([string]$script:LifeControls.NoteTitle.Text) 80
        $body = ([string]$script:LifeControls.NoteBody.Text).Trim()
        if (-not $title) { Life-Warn '先给小纸条起个标题吧。'; return }
        if ($body.Length -gt 20000) { Life-Warn '一条笔记最多 20000 字。'; return }
        $id = Life-Selected 'NoteRows'
        $found = $false
        foreach ($n in @($script:LifeData.notes)) {
            if ([string]$n.id -eq $id) {
                $n.title = $title
                $n.body = $body
                $n.updated = (Get-Date).ToString('s')
                $found = $true
                break
            }
        }
        if (-not $found) {
            if (@($script:LifeData.notes).Count -ge 300) { Life-Warn '小纸条已经装满啦，请先整理。'; return }
            $script:LifeData.notes += [pscustomobject]@{
                id = New-LifeId; title = $title; body = $body; updated = (Get-Date).ToString('s')
            }
        }
        Save-Life; Refresh-LifeNotes
        Say '小纸条收好啦！有趣的想法别让它溜走～ 📒'
    })
    $c.NoteDelete.Add_Click({
        $id = Life-Selected 'NoteRows'
        if (-not $id) { Life-Warn '请先选中一条已经保存的笔记。'; return }
        if (-not (Life-Confirm '要删除这条笔记吗？删除后无法在界面里撤销。')) { return }
        $script:LifeData.notes = @($script:LifeData.notes | Where-Object { [string]$_.id -ne $id })
        Save-Life; Refresh-LifeNotes
        $script:LifeControls.NoteTitle.Text = ''
        $script:LifeControls.NoteBody.Text = ''
    })
    $c.AnniversaryAdd.Add_Click({
        $title = Life-Clean ([string]$script:LifeControls.AnniversaryInput.Text) 80
        if (-not $title) { Life-Warn '给这个特别的日子起个名字吧～'; return }
        if ($null -eq $script:LifeControls.AnniversaryDate.SelectedDate) { Life-Warn '还没有选日期哦。'; return }
        if (@($script:LifeData.anniversaries).Count -ge 150) { Life-Warn '重要日子也太多啦，请先整理。'; return }
        $day = ([DateTime]$script:LifeControls.AnniversaryDate.SelectedDate).ToString('yyyy-MM-dd')
        $annual = [bool]$script:LifeControls.AnniversaryAnnual.IsChecked
        if (-not $annual -and ([DateTime]::Parse($day)).Date -lt (Get-Date).Date) {
            Life-Warn '不重复的倒计时请选择今天或未来日期。'; return
        }
        $script:LifeData.anniversaries += [pscustomobject]@{
            id = New-LifeId; title = $title; date = $day; annual = $annual
        }
        Save-Life
        $script:LifeControls.AnniversaryInput.Text = ''
        Refresh-LifeAnniversaries
        Say '这个重要的日子，小 G 会帮你记着！ 🎂'
    })
    $c.AnniversaryDelete.Add_Click({
        $id = Life-Selected 'AnniversaryRows'
        if (-not $id) { Life-Warn '请先选中一个日子。'; return }
        if (-not (Life-Confirm '确定要忘掉这个日子吗？')) { return }
        $script:LifeData.anniversaries = @($script:LifeData.anniversaries | Where-Object { [string]$_.id -ne $id })
        Save-Life; Refresh-LifeAnniversaries
    })
    $c.CareSave.Add_Click({
        $script:LifeData.careEnabled = [bool]$script:LifeControls.CareToggle.IsChecked
        foreach ($minutes in @(30,45,60,90,120)) {
            if ([bool]$script:LifeControls[('Care' + $minutes)].IsChecked) {
                $script:LifeData.careMinutes = $minutes
                break
            }
        }
        $script:LastCareAt = Get-Date
        Save-Life
        Say '关怀习惯保存好啦！我会注意不打扰你专注。 🌷'
    })
}
