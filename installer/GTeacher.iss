#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif

[Setup]
AppId={{FA49B827-1FE4-42D3-9C2C-2E7D498388A4}
AppName=小G
AppVersion={#AppVersion}
AppVerName=小G v{#AppVersion}
AppPublisher=G Teacher Desktop Pet Contributors
AppPublisherURL=https://github.com/Shaky-00/gteacher-desktop-pet
AppUpdatesURL=https://github.com/Shaky-00/gteacher-desktop-pet/releases/latest
DefaultDirName={localappdata}\Programs\GTeacherDesktopPet
DefaultGroupName=小G
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
UsePreviousAppDir=yes
OutputDir=..\dist
OutputBaseFilename=GTeacher-Setup-v{#AppVersion}
SetupIconFile=..\assets\gteacher.ico
UninstallDisplayIcon={app}\GTeacherPet.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
MinVersion=10.0

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："

[Files]
Source: "..\dist\app\GTeacherPet.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\sprites\*.png"; DestDir: "{app}\sprites"; Flags: ignoreversion
Source: "..\assets\gteacher.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\小G"; Filename: "{app}\GTeacherPet.exe"; IconFilename: "{app}\gteacher.ico"
Name: "{autodesktop}\小G"; Filename: "{app}\GTeacherPet.exe"; IconFilename: "{app}\gteacher.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\GTeacherPet.exe"; Description: "现在打开小G"; Flags: nowait postinstall skipifsilent

; Inno Setup never deletes the per-user notebook directory on install/uninstall.
; The app stores settings.json and life.json in %LOCALAPPDATA%\GTeacherDesktopPet.
