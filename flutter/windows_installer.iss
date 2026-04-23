[Setup]
AppId={{A8C28ED2-8C70-4D5A-8B71-2E9B8A3E21F2}
AppName=KIYIM DOKON POS
AppVersion=1.0.0
AppPublisher=Ataway
DefaultDirName={autopf}\KIYIM DOKON POS
DefaultGroupName=KIYIM DOKON POS
DisableProgramGroupPage=yes
OutputDir=build\windows\x64\installer
OutputBaseFilename=KIYIM_DOKON_POS_Setup_1.0.0
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\flutter_client.exe
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\KIYIM DOKON POS"; Filename: "{app}\flutter_client.exe"
Name: "{autodesktop}\KIYIM DOKON POS"; Filename: "{app}\flutter_client.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\flutter_client.exe"; Description: "Launch KIYIM DOKON POS"; Flags: nowait postinstall skipifsilent
