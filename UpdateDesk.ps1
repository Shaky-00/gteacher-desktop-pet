# G Teacher Desktop Pet: public GitHub Release update checker (PowerShell 5.1).
# An update is never installed silently; the user chooses whether to open GitHub.
$script:PetVersion = [Version]'1.1.0'
$script:ReleaseApi = 'https://api.github.com/repos/Shaky-00/gteacher-desktop-pet/releases/latest'
$script:ReleasePage = 'https://github.com/Shaky-00/gteacher-desktop-pet/releases/latest'
$script:UpdateStampFile = Join-Path $script:SettingsDirectory 'last-update-check.txt'
$script:UpdateManualRequest = $false
$script:DeferredRelease = $null
$script:UpdateStartupTimer = $null
$script:UpdateTimeoutTimer = $null
$script:UpdateTimedOut = $false
$script:UpdateLogFile = Join-Path $script:SettingsDirectory 'update-check.log'

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
    $message = "小G 发现新衣服啦！ ✨`r`n`r`n目前版本：v$($script:PetVersion.ToString(3))`r`n最新版本：$tag`r`n`r`n要去 GitHub 发布页下载新版安装包吗？`r`n旧版的称呼、待办与手账都会留在电脑上哦。"
    $choice = [System.Windows.MessageBox]::Show(
        $script:Window, $message, '小G · 发现更新',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Information)
    if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
        try { [System.Diagnostics.Process]::Start($url) | Out-Null }
        catch { Show-UpdateMessage '暂时打不开发布页，请右键小G 再试一次。' '小G' }
    }
}

function Handle-UpdateRelease($release, [bool]$manual) {
    if ($null -eq $release -or [bool]$release.draft -or [bool]$release.prerelease) {
        if ($manual) { Show-UpdateMessage '目前还没有可用的正式版本。本地试用包尚未正式发布，请继续使用当前版本。' '小G' }
        return
    }
    $tag = [string]$release.tag_name
    if ($tag -notmatch '^v(\d+)\.(\d+)\.(\d+)$') {
        if ($manual) { Show-UpdateMessage '新版本号暂时识别不了，去 GitHub 发布页看看吧。' '小G' }
        return
    }
    $newVersion = [Version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
    if ($newVersion -le $script:PetVersion) {
        if ($manual) { Show-UpdateMessage "当前版本：v$($script:PetVersion.ToString(3))。GitHub 最新正式版：$tag。暂时没有需要安装的更新。" '小G' }
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

function Write-UpdateDiagnostic([string]$detail) {
    # Keep only the latest public update-check diagnostic; no nickname or notebook data.
    try {
        if (-not (Test-Path -LiteralPath $script:SettingsDirectory)) {
            [void](New-Item -ItemType Directory -Path $script:SettingsDirectory -Force)
        }
        ([DateTime]::Now.ToString('s') + "`r`n" + $detail) |
            Set-Content -LiteralPath $script:UpdateLogFile -Encoding UTF8
    } catch { }
}

function Get-UpdateFailureMessage([System.Exception]$failure) {
    $status = 0
    $networkStatus = ''
    $current = $failure
    while ($null -ne $current) {
        if ($current -is [System.Net.WebException]) {
            $networkStatus = [string]$current.Status
            if ($null -ne $current.Response -and $current.Response -is [System.Net.HttpWebResponse]) {
                $status = [int]$current.Response.StatusCode
            }
        }
        $current = $current.InnerException
    }
    Write-UpdateDiagnostic ("HTTP=$status; Network=$networkStatus`r`n" + $failure.ToString())
    switch ($status) {
        404 { return 'GitHub 暂未提供可用的正式版本（HTTP 404）。当前本地试用 ZIP 尚未作为正式版本发布，这不代表你的网络断开。' }
        403 { return 'GitHub 暂时拒绝了更新请求（HTTP 403），可能是请求限额或访问限制。请稍后重试，也可以直接查看仓库发布页。' }
        429 { return 'GitHub 更新请求过于频繁（HTTP 429），请稍后再试。' }
        407 { return '代理服务器要求验证（HTTP 407）。请检查电脑的代理设置后重试。' }
    }
    if ($status -ge 500) { return "GitHub 更新服务暂时异常（HTTP $status）。请稍后重试。" }
    if ($status -gt 0) { return "更新请求未成功（HTTP $status）。暂时无法判断是否有新版本，请稍后重试或查看仓库发布页。" }
    switch ($networkStatus) {
        'NameResolutionFailure' { return '无法解析 GitHub 的地址。请检查网络或 DNS 设置后重试；本次未能判断是否有新版本。' }
        'ProxyNameResolutionFailure' { return '无法连接配置的代理服务器。请检查代理设置后重试。' }
        'Timeout' { return '连接 GitHub 超时。请检查网络后重试；本次未能判断是否有新版本。' }
        'TrustFailure' { return '无法验证 GitHub 的安全证书。请检查系统时间或网络代理；本次未能判断是否有新版本。' }
        'SecureChannelFailure' { return '无法与 GitHub 建立安全连接。请检查系统更新或网络代理后重试。' }
        default { return '暂时无法连接 GitHub。请检查网络或代理后重试；这不表示已经是最新版。' }
    }
}

function Start-UpdateCheck {
    param([switch]$Manual)
    if ($null -ne $script:UpdateClient) {
        if ($Manual) {
            $script:UpdateManualRequest = $true
            Say '我正在查更新，再等一小会儿哦～'
        }
        return
    }
    $script:UpdateManualRequest = [bool]$Manual
    $script:UpdateTimedOut = $false
    if ($Manual) { Say '正在检查正式版本更新…… ✨' }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $client = New-Object System.Net.WebClient
        $client.Headers.Add('User-Agent', 'XiaoGDesktopPet/1.1.0')
        $client.Headers.Add('Accept', 'application/vnd.github+json')
        $script:UpdateClient = $client
        $client.add_DownloadStringCompleted({
            param($sender, $eventArgs)
            $manual = $script:UpdateManualRequest
            $script:UpdateManualRequest = $false
            if ($null -ne $script:UpdateTimeoutTimer) { $script:UpdateTimeoutTimer.Stop() }
            try {
                if ($eventArgs.Cancelled) {
                    if ($manual -and $script:UpdateTimedOut) {
                        Show-UpdateMessage '连接 GitHub 超时（等待超过 20 秒）。请检查网络或代理后重试；本次未能判断是否有新版本。' '小G · 连接超时'
                    }
                    return
                }
                if ($null -ne $eventArgs.Error) {
                    $message = Get-UpdateFailureMessage $eventArgs.Error
                    if ($manual) { Show-UpdateMessage $message '小G · 更新检查结果' }
                    return
                }
                # Access Result only after checking Cancelled and Error.
                try {
                    $release = $eventArgs.Result | ConvertFrom-Json -ErrorAction Stop
                    if ($null -eq $release -or $null -eq $release.PSObject.Properties['tag_name'] -or
                        $null -eq $release.PSObject.Properties['draft'] -or
                        $null -eq $release.PSObject.Properties['prerelease'] -or
                        $null -eq $release.PSObject.Properties['html_url']) {
                        throw 'GitHub release response is missing required fields.'
                    }
                } catch {
                    Write-UpdateDiagnostic ('Invalid release response: ' + $_.Exception.ToString())
                    if ($manual) {
                        Show-UpdateMessage '已连接更新服务，但返回内容不是有效的版本信息。暂时无法判断是否有新版本，请稍后重试。' '小G · 更新内容异常'
                    }
                    return
                }
                Write-UpdateDiagnostic ('Successfully received release ' + [string]$release.tag_name)
                try {
                    [DateTime]::UtcNow.ToString('o') | Set-Content -LiteralPath $script:UpdateStampFile -Encoding UTF8
                } catch { }
                Handle-UpdateRelease $release $manual
            } catch {
                Write-UpdateDiagnostic ('Update processing error: ' + $_.Exception.ToString())
                if ($manual) { Show-UpdateMessage '更新检查过程中出现了程序错误，暂时无法判断版本。错误详情已记入本机 update-check.log，可用于排查。' '小G · 更新检查异常' }
            } finally {
                $script:UpdateClient = $null
                $script:UpdateTimeoutTimer = $null
                try { $sender.Dispose() } catch { }
            }
        })
        $script:UpdateTimeoutTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:UpdateTimeoutTimer.Interval = [TimeSpan]::FromSeconds(20)
        $script:UpdateTimeoutTimer.Add_Tick({
            $script:UpdateTimeoutTimer.Stop()
            if ($null -ne $script:UpdateClient) {
                $script:UpdateTimedOut = $true
                Write-UpdateDiagnostic 'Request cancelled after 20-second timeout.'
                $script:UpdateClient.CancelAsync()
            }
        })
        $script:UpdateTimeoutTimer.Start()
        $client.DownloadStringAsync([Uri]$script:ReleaseApi)
    } catch {
        Write-UpdateDiagnostic ('Could not start update request: ' + $_.Exception.ToString())
        if ($null -ne $script:UpdateTimeoutTimer) { $script:UpdateTimeoutTimer.Stop(); $script:UpdateTimeoutTimer = $null }
        if ($null -ne $script:UpdateClient) {
            try { $script:UpdateClient.Dispose() } catch { }
            $script:UpdateClient = $null
        }
        if ($Manual) { Show-UpdateMessage '未能发起更新查询。请检查网络或代理后重试；本次未能判断是否有新版本。' '小G · 更新检查未完成' }
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
