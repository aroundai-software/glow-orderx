; Script generated for Inno Setup 6
; OrderX TallySync - Windows Installer

#define MyAppName "OrderX TallySync"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "OrderX"
#define MyAppURL "https://orderx.app"
#define MyAppExeName "TallySync.exe"

[Setup]
; Basic Application Info
AppId={{9B7F1B3C-4C82-4E87-9A15-8E7A0D5B7123}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Destination Folder (Default C:\OrderX_TallySync for full service read/write permissions)
DefaultDirName=C:\OrderX_TallySync
DisableDirPage=no
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=no

; Output Installer Settings
OutputDir=installer_output
OutputBaseFilename=OrderX_TallySync_Setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Permissions and UI Style
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
WizardStyle=modern
CloseApplications=force
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Dirs]
; Grant Users full access so non-admin users can view sync.log or edit .env easily
Name: "{app}"; Permissions: users-full

[Files]
; Main Executable & Service Wrapper
Source: "installer_staging\TallySync.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer_staging\myserviceinstaller.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer_staging\myserviceinstaller.xml"; DestDir: "{app}"; Flags: ignoreversion

; Helper Scripts
Source: "installer_staging\install_service.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer_staging\uninstall_service.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer_staging\restart_service.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer_staging\run_manual_sync.bat"; DestDir: "{app}"; Flags: ignoreversion

; Python Runtime and Dependencies
Source: "installer_staging\_internal\*"; DestDir: "{app}\_internal"; Flags: ignoreversion recursesubdirs createallsubdirs

; Configuration file (.env) - NEVER overwrite if user already has one
Source: "installer_staging\.env"; DestDir: "{app}"; Flags: onlyifdoesntexist

[Icons]
; Start Menu Shortcuts
Name: "{group}\Run Manual Sync Test"; Filename: "{app}\run_manual_sync.bat"; WorkingDir: "{app}"
Name: "{group}\Edit Configuration (.env)"; Filename: "notepad.exe"; Parameters: """{app}\.env"""; WorkingDir: "{app}"
Name: "{group}\View Sync Log"; Filename: "notepad.exe"; Parameters: """{app}\sync.log"""; WorkingDir: "{app}"
Name: "{group}\Restart Background Service"; Filename: "{app}\restart_service.bat"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

; Desktop Shortcut (Optional)
Name: "{commondesktop}\OrderX TallySync Test"; Filename: "{app}\run_manual_sync.bat"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
; Step 1: Cleanly terminate any running TallySync instances and remove any existing service before fresh registration
Filename: "taskkill.exe"; Parameters: "/F /IM TallySync.exe"; Flags: runhidden
Filename: "{app}\myserviceinstaller.exe"; Parameters: "stop"; Flags: runhidden waituntilterminated
Filename: "{app}\myserviceinstaller.exe"; Parameters: "uninstall"; Flags: runhidden waituntilterminated

; Step 2: Install and start the Windows Service
Filename: "{app}\myserviceinstaller.exe"; Parameters: "install"; Flags: runhidden waituntilterminated; StatusMsg: "Installing OrderX TallySync Background Service..."
Filename: "{app}\myserviceinstaller.exe"; Parameters: "start"; Flags: runhidden waituntilterminated; StatusMsg: "Starting OrderX TallySync Background Service..."

; Step 3: Optional post-install tasks on finish page
Filename: "notepad.exe"; Parameters: """{app}\.env"""; Description: "Open configuration file (.env) to review settings"; Flags: postinstall nowait unchecked
Filename: "{app}\run_manual_sync.bat"; Description: "Run an immediate sync test in console window"; Flags: postinstall nowait unchecked

[UninstallRun]
; Stop and remove service upon uninstallation from Windows Settings / Control Panel
Filename: "taskkill.exe"; Parameters: "/F /IM TallySync.exe"; Flags: runhidden
Filename: "{app}\myserviceinstaller.exe"; Parameters: "stop"; Flags: runhidden waituntilterminated
Filename: "{app}\myserviceinstaller.exe"; Parameters: "uninstall"; Flags: runhidden waituntilterminated

[UninstallDelete]
; Clean up generated log files upon uninstallation
Type: files; Name: "{app}\sync.log"
Type: files; Name: "{app}\tallysync.lock"
Type: files; Name: "{app}\myserviceinstaller.wrapper.log"
Type: files; Name: "{app}\myserviceinstaller.out.log"
Type: files; Name: "{app}\myserviceinstaller.err.log"
