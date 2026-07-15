; Inno Setup script for BiblioGenius (Windows).
; Packages the Flutter Windows release bundle (incl. the injected Rust backend)
; into a single BiblioGenius-Setup.exe with Start Menu + optional desktop
; shortcut and an uninstaller. Per-user install by default (no admin required).
;
; Built by .github/workflows/release-windows.yml on a windows-latest runner:
;   iscc /DMyAppVersion=<version> windows\installer\BiblioGenius.iss
;
; NOTE: the installer is NOT code-signed (no Windows signing cert in the
; pipeline), so Windows SmartScreen will warn "unknown publisher" on first run.
; Document "More info -> Run anyway" on the downloads page. Signing needs a paid
; cert and is deferred.

#define MyAppName "BiblioGenius"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0-dev"
#endif
#define MyAppPublisher "BiblioGenius"
#define MyAppURL "https://bibliogenius.org"
#define MyAppExeName "bibliogenius.exe"

[Setup]
; Stable AppId so upgrades and uninstall are tracked across versions. Do not change.
AppId={{8F2A7C4E-1B3D-4E5F-9A6B-2C7D8E9F0A1B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=Output
OutputBaseFilename=BiblioGenius-Setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release bundle: bibliogenius.exe + DLLs + data\ + backend\.
; The recursive copy deliberately carries crsqlite.dll TWICE (app root AND
; backend\): the Flutter runner and the bundled backend each resolve the
; cr-sqlite extension next to their own executable at runtime (ADR-044 dynamic
; path, see crsqlite_dynamic.rs). Do not deduplicate.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
