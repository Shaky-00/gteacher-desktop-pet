# G Teacher Desktop Pet: public GitHub Release update checker (PowerShell 5.1).
# An update is never installed silently; the user chooses whether to open GitHub.
$script:PetVersion = [Version]'1.0.0'
$script:ReleaseApi = 'https://api.github.com/repos/Shaky-00/gteacher-desktop-pet/releases/latest'
$script:ReleasePage = 'https://github.com/Shaky-00/gteacher-desktop-pet/releases/latest'
$script:UpdateStampFile = Join-Path $script:SettingsDirectory 'last-update-check.txt'
$script:UpdateManualRequest = $false
$script:DeferredRelease = $null
$script:UpdateStartupTimer = $null

function Show-UpdateMessage([string]$message, [string]$heading) {
    [void][System.Windows.MessageBox]::Show(
        $script:Window, $message, $heading,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information)
}

function Show-UpdateOffer($release) {
    if ($null -eq $release) { return }
    $tag = [string]$release.tag_name
    # Only GitHub pages under this repository are trusted as update destinations.
    $url = [string]$release.html_url
    if ($url -notmatch '^https://github\.com/Shaky-00/gteacher-desktop-pet/releases/tag/v\d+\.\d+\.\d+/?$') {
        $url = $script:ReleasePage
    }
    $message = "小 G 发现新衣服啦！ ✨`r`n`r`n目前版本：v$($script:PetVersion.ToString(3))`r`n最新版本：$tag`r`n`r`n要去 GitHub 发布页下载新版安装包吗？`r`n旧版的称呼、待办与手账都会留在电脑上哦。"
    $choice = [System.Windows.MessageBox]::Show(
        $script:Window, $message, '小 G 老师 · 发现更新',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Information)
    if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
        try { [System.Diagnostics.Process]::Start($url) | Out-Null }
        catch { Show-UpdateMessage '暂时打不开发布页，请右键小 G 再试一次。' '小 G 老师' }
    }
}

function Handle-UpdateRelease($release, [bool]$manual) {
    if ($null -eq $release -or [bool]$release.draft -or [bool]$release.prerelease) {
        if ($manual) { Show-UpdateMessage '发布页还没有可用的稳定版本，再等等小 G 哦～' '小 G 老师' }
        return
    }
    $tag = [string]$release.tag_name
    if ($tag -notmatch '^v(\d+)\.(\d+)\.(\d+)$') {
        if ($manual) { Show-UpdateMessage '新版本号暂时识别不了，去 GitHub 发布页看看吧。' '小 G 老师' }
        return
    }
    $newVersion = [Version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
    if ($newVersion -le $script:PetVersion) {
        if ($manual) { Show-UpdateMessage "已是最新版本 v$($script:PetVersion.ToString(3))，继续开心相伴吧！" '小 G 老师' }
        return
    }
    if (-not $manual -and ($script:FocusRunning -or $script:FocusRemaining -gt 0)) {
        # Never interrupt a focus session with an automatic update dialog.
        $script:DeferredRelease = $release
        if ($null -eq $script:UpdatePromptTimer) {
            $script:UpdatePromptTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:UpdatePromptTimer.Interval = [TimeSpan]::FromSeconds(15)
            $script:UpdatePromptTimer.Add_Tick({
                if ($null -ne $script:DeferredRelease -and -not $script:FocusRunning -and $script:FocusRemaining -le 0) {
                    $pending = $script:DeferredRelease
                    $script:DeferredRelease = $null
                    $script:UpdatePromptTimer.Stop()
                    Show-UpdateOffer $pending
                }
            })
        }
        $script:UpdatePromptTimer.Start()
        return
    }
    Show-UpdateOffer $release
}

function Start-UpdateCheck {
    param([switch]$Manual)
    if ($null -ne $script:UpdateClient) {
        if ($Manual) { Say '我正在查更新，再等一小会儿哦～' }
        return
    }
    $script:UpdateManualRequest = [bool]$Manual
    if ($Manual) { Say '正在看看小 G 有没有新衣服…… ✨' }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $client = New-Object System.Net.WebClient
        $client.Headers.Add('User-Agent', 'GTeacherDesktopPet/1.0.0')
        $client.Headers.Add('Accept', 'application/vnd.github+json')
        $script:UpdateClient = $client
        $client.add_DownloadStringCompleted({
            param($sender, $args)
            $manual = $script:UpdateManualRequest
            $script:UpdateManualRequest = $false
            try {
                if ($args.Cancelled) { return }
                if ($null -ne $args.Error) {
                    if ($manual) { Show-UpdateMessage '暂时连不上 GitHub 更新服务，请稍后再试。' '小 G 老师' }
                    return
                }
                $release = $args.Result | ConvertFrom-Json
                if (-not (Test-Path -LiteralPath $script:SettingsDirectory)) {
                    [void](New-Item -ItemType Directory -Path $script:SettingsDirectory -Force)
                }
                try {
                    [DateTime]::UtcNow.ToString('o') | Set-Content -LiteralPath $script:UpdateStampFile -Encoding UTF8
                } catch { }
                Handle-UpdateRelease $release $manual
            } catch {
                if ($manual) { Show-UpdateMessage '更新信息读取失败，请稍后再试。' '小 G 老师' }
            } finally {
                $script:UpdateClient = $null
                try { $sender.Dispose() } catch { }
            }
        })
        $client.DownloadStringAsync([Uri]$script:ReleaseApi)
    } catch {
        if ($null -ne $script:UpdateClient) {
            try { $script:UpdateClient.Dispose() } catch { }
            $script:UpdateClient = $null
        }
        if ($Manual) { Show-UpdateMessage '暂时没法查更新，过一会儿再试试吧。' '小 G 老师' }
    }
}

function Start-UpdateCheckOnLaunch {
    # Check at most once per 24 hours; no network calls while the window starts.
    try {
        if (Test-Path -LiteralPath $script:UpdateStampFile) {
            $raw = (Get-Content -LiteralPath $script:UpdateStampFile -Raw -Encoding UTF8).Trim()
            $last = [DateTime]::Parse($raw).ToUniversalTime()
            if (([DateTime]::UtcNow - $last).TotalHours -lt 24) { return }
        }
    } catch { }
    $script:UpdateStartupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:UpdateStartupTimer.Interval = [TimeSpan]::FromSeconds(7)
    $script:UpdateStartupTimer.Add_Tick({
        $script:UpdateStartupTimer.Stop()
        Start-UpdateCheck
    })
    $script:UpdateStartupTimer.Start()
}
