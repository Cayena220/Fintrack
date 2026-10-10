; FinTrack Windows installer (Inno Setup 6).
;
; Build the app first, then compile this script from the repo root:
;   cd app && flutter build windows --release --dart-define-from-file=env.json && cd ..
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.0 installer\fintrack.iss
;
; Output: installer\Output\FinTrack-Setup-<version>.exe

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "FinTrack"
#define AppExe "fintrack.exe"
#define AppPublisher "FinTrack"
#define UrlScheme "io.fintrack.app"
#define BuildDir "..\app\build\windows\x64\runner\Release"

; 64-bit VC++ runtime DLLs on the build machine. ISCC is a 32-bit process, so
; System32 would be redirected to the 32-bit copies; Sysnative avoids that.
#if FileExists(GetEnv("SystemRoot") + "\Sysnative\msvcp140.dll")
  #define SysDir GetEnv("SystemRoot") + "\Sysnative"
#else
  #define SysDir GetEnv("SystemRoot") + "\System32"
#endif

[Setup]
; Never change AppId: Windows uses it to find the existing install on upgrade.
AppId={{BD6EA19D-9983-42D8-9748-2624FCDA95A1}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
; Per-user install: no admin prompt, and the HKCU URL scheme below matches.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
OutputDir=Output
OutputBaseFilename=FinTrack-Setup-{#AppVersion}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Flutter apps need the Visual C++ runtime. Shipping the DLLs next to the exe
; avoids asking users to install the redistributable separately.
Source: "{#SysDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#SysDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#SysDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; io.fintrack.app:// links (Google sign-in, email confirmation) open the app.
; The app also registers this on startup; see lib/services/windows_deep_link.dart.
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}"; ValueType: string; ValueName: ""; ValueData: "URL:{#UrlScheme}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
