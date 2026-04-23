#define MyAppName "ATAWAY POS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "ATAWAY"
#define MyAppExeName "flutter_client.exe"

#ifndef StageDir
  #define StageDir "D:\sovga\UY-DOKON\tools\installer\staging\flutter-local"
#endif

#ifndef OutputDir
  #define OutputDir "D:\sovga\UY-DOKON\tools\installer\output"
#endif

[Setup]
AppId={{D42309E8-8E4D-47B5-A881-EA22D52C6548}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\ATAWAY POS
DefaultGroupName=ATAWAY POS
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ataway-pos-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#StageDir}\app\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\ATAWAY POS"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\ATAWAY POS"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "ATAWAY POS ni ishga tushirish"; Flags: nowait postinstall skipifsilent
