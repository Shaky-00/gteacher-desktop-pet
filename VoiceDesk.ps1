# Optional offline Windows desktop TTS. No network requests or API keys.
$script:PetSynth = $null
$script:PetVoices = @()
$script:VoiceFailure = ''

function Initialize-PetVoice {
    if ($null -ne $script:PetSynth) { return $true }
    $candidate = $null
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $candidate = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $script:PetVoices = @($candidate.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
        if ($script:PetVoices.Count -eq 0) { throw '没有检测到可用的桌面语音。' }
        $candidate.SetOutputToDefaultAudioDevice()
        $script:PetSynth = $candidate
        $script:VoiceFailure = ''
        return $true
    } catch {
        $script:VoiceFailure = '本机语音暂不可用：' + $_.Exception.Message
        $script:PetVoices = @()
        if ($null -ne $candidate) { try { $candidate.Dispose() } catch { } }
        return $false
    }
}

function Stop-PetVoice {
    param([switch]$Dispose)
    if ($null -ne $script:PetSynth) {
        try { $script:PetSynth.SpeakAsyncCancelAll() } catch { }
        if ($Dispose) {
            try { $script:PetSynth.Dispose() } catch { }
            $script:PetSynth = $null
        }
    }
}

function Speak-PetText {
    param([string]$Text, [switch]$Preview, [string]$VoiceName = '', [int]$Volume = -1)
    if (-not $Preview -and -not $script:AppConfig.voiceEnabled) { return $false }
    if (-not $Preview -and $null -ne $script:PanelControls -and $script:PanelControls.ContainsKey('VoiceEnabledChoice') -and
        -not [bool]$script:PanelControls.VoiceEnabledChoice.IsChecked) { return $false }
    if (-not (Initialize-PetVoice)) { return $false }
    try {
        if (-not $VoiceName) { $VoiceName = [string]$script:AppConfig.voiceName }
        $available = @($script:PetVoices | Where-Object { $_.Name -eq $VoiceName })
        if ($available.Count -eq 0) {
            $available = @($script:PetVoices | Where-Object { $_.Culture.Name -like 'zh-*' })
        }
        if ($available.Count -eq 0) { $available = @($script:PetVoices[0]) }
        Stop-PetVoice
        $script:PetSynth.SelectVoice([string]$available[0].Name)
        if ($Volume -lt 0) { $Volume = [int]$script:AppConfig.voiceVolume }
        $script:PetSynth.Volume = [Math]::Max(0, [Math]::Min(100, $Volume))
        $script:PetSynth.Rate = 0
        $clean = ([regex]::Replace($Text, '[\p{Cs}\p{So}]', '')).Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { return $false }
        if ($clean.Length -gt 300) { $clean = $clean.Substring(0, 300) }
        [void]$script:PetSynth.SpeakAsync($clean)
        $script:VoiceFailure = ''
        return $true
    } catch {
        $script:VoiceFailure = '语音播放失败：' + $_.Exception.Message
        if ($null -ne $script:PanelControls -and $script:PanelControls.ContainsKey('VoiceStatus')) {
            $script:PanelControls.VoiceStatus.Text = $script:VoiceFailure
        }
        return $false
    }
}

function Initialize-VoicePanel {
    $c = $script:PanelControls
    $c.VoiceEnabledChoice.IsChecked = [bool]$script:AppConfig.voiceEnabled
    $c.VoiceVolumeChoice.Value = [int]$script:AppConfig.voiceVolume
    $c.VoiceChoice.Items.Clear()
    if (Initialize-PetVoice) {
        foreach ($v in $script:PetVoices) { [void]$c.VoiceChoice.Items.Add([string]$v.Name) }
        $saved = @($script:PetVoices | Where-Object { $_.Name -eq $script:AppConfig.voiceName })
        if ($saved.Count -eq 0) { $saved = @($script:PetVoices | Where-Object { $_.Culture.Name -like 'zh-*' }) }
        if ($saved.Count -eq 0) { $saved = @($script:PetVoices[0]) }
        $c.VoiceChoice.SelectedItem = [string]$saved[0].Name
        $chinese = @($script:PetVoices | Where-Object { $_.Culture.Name -like 'zh-*' })
        $c.VoiceStatus.Text = if ($chinese.Count -gt 0) {
            '已找到系统音色。点击试听；如果没有声音，请确认音量和音频输出设备。'
        } else {
            '未检测到中文桌面音色。可先试听现有音色；中文朗读可能不完整。安装中文文本转语音包后请重启小G。'
        }
    } else {
        $c.VoiceStatus.Text = $script:VoiceFailure + ' 可以关闭语音开关，继续正常使用小G。'
    }
    $c.VoicePreviewBtn.Add_Click({
        $panel = $script:PanelControls
        if ($null -eq $panel.VoiceChoice.SelectedItem) {
            $panel.VoiceStatus.Text = '没有可试听的系统音色。请安装文本转语音包后重启小G。'
            return
        }
        $ok = Speak-PetText -Text '你好呀，我是小G。忙了一会儿，也记得喝口水，休息一下。' -Preview `
            -VoiceName ([string]$panel.VoiceChoice.SelectedItem) -Volume ([int]$panel.VoiceVolumeChoice.Value)
        $panel.VoiceStatus.Text = if ($ok) { '已开始试听。喜欢的话勾选语音开关，再点击保存。' } else { $script:VoiceFailure }
    })
    $c.VoiceStopBtn.Add_Click({
        Stop-PetVoice
        $script:PanelControls.VoiceStatus.Text = '已停止播放。'
    })
    $c.VoiceEnabledChoice.Add_Unchecked({ Stop-PetVoice })
}
