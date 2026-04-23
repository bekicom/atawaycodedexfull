[Setup]
AppId={{B9C56D3F-4B45-4F09-A8B5-2B44D0A6A921}
AppName=KIYIM DOKON POS
AppVersion=1.0.0
AppPublisher=ATAWAY
DefaultDirName={autopf}\KIYIM DOKON POS
DefaultGroupName=KIYIM DOKON POS
AllowNoIcons=yes
LicenseFile=
OutputDir=..\dist
OutputBaseFilename=KIYIM_DOKON_POS_Setup_1.0.0
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64compatible
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\flutter_client.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop shortcut yaratish"; GroupDescription: "Qo'shimcha:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\KIYIM DOKON POS"; Filename: "{app}\flutter_client.exe"; WorkingDir: "{app}"
Name: "{group}\Dasturni o'chirish"; Filename: "{uninstallexe}"
Name: "{autodesktop}\KIYIM DOKON POS"; Filename: "{app}\flutter_client.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\flutter_client.exe"; Description: "KIYIM DOKON POS ni ishga tushirish"; Flags: nowait postinstall skipifsilent
