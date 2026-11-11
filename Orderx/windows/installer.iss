[Setup]
AppId={{2A958A9F-4CD9-4D3C-84FA-E1B48E89DEE7}
AppName=Orderx
AppVersion=1.0.0
AppPublisher=VK Traders
DefaultDirName={autopf}\Orderx
DisableProgramGroupPage=yes
OutputDir=..\build\windows\installer
OutputBaseFilename=Orderx_Installer
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\vk_traders.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Orderx"; Filename: "{app}\vk_traders.exe"
Name: "{autodesktop}\Orderx"; Filename: "{app}\vk_traders.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vk_traders.exe"; Description: "{cm:LaunchProgram,Orderx}"; Flags: nowait postinstall skipifsilent
