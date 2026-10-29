param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$declaredVersion = (Get-Content -LiteralPath (Join-Path $project 'version.txt') -Raw).Trim()
if ($Version -ne $declaredVersion) {
    throw "Requested version $Version does not match version.txt ($declaredVersion)."
}

$main = Join-Path $project 'GTeacherPet.ps1'
$icon = Join-Path $project 'assets\gteacher.ico'
$exe = Join-Path $project 'dist\app\GTeacherPet.exe'
$installer = Join-Path $project 'installer\GTeacher.iss'
$outDir = Split-Path -Parent $exe
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

# Put the two companion scripts into the compiled executable. This prevents the
# installed app from needing to dot-source loose .ps1 files under a restrictive
# Windows PowerShell execution policy.
$embeddedSource = [System.IO.File]::ReadAllText($main, [System.Text.Encoding]::UTF8)
foreach ($name in @('LifeDesk.ps1', 'UpdateDesk.ps1')) {
    $needle = ". (Join-Path `$PSScriptRoot '$name')"
    if (-not $embeddedSource.Contains($needle)) { throw "Missing source include: $name" }
    $part = [System.IO.File]::ReadAllText((Join-Path $project $name), [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $embeddedSource = $embeddedSource.Replace($needle, "`r`n# BEGIN $name`r`n$part`r`n# END $name`r`n")
}
$compiledSource = Join-Path $outDir 'GTeacherPet.compiled.ps1'
[System.IO.File]::WriteAllText($compiledSource, $embeddedSource, (New-Object System.Text.UTF8Encoding($true)))

Import-Module ps2exe -RequiredVersion '1.0.18' -ErrorAction Stop
Invoke-ps2exe -inputFile $compiledSource -outputFile $exe -x64 -STA -noConsole `
    -iconFile $icon -title '小 G 老师' -product 'G Teacher Desktop Pet' `
    -description '温暖的 Windows 桌面陪伴小助手' -version "$Version.0" -DPIAware
if (-not (Test-Path $exe)) { throw 'PS2EXE did not create the application EXE.' }

$iscc = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($command) { $iscc = $command.Source }
}
if (-not $iscc) { throw 'ISCC.exe not found: install Inno Setup 6.' }

& $iscc "/DAppVersion=$Version" $installer
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed ($LASTEXITCODE)." }
$setup = Join-Path $project "dist\GTeacher-Setup-v$Version.exe"
if (-not (Test-Path $setup)) { throw "Missing installer: $setup" }

$hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  GTeacher-Setup-v$Version.exe" | Set-Content -LiteralPath "$setup.sha256" -Encoding ASCII
Write-Host "Built $setup"
Write-Host "SHA256 $hash"
