#define MyAppName "ATAWAY Local Backend"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "ATAWAY"
#define MyAppExeName "node.exe"

#ifndef StageDir
  #define StageDir "D:\sovga\UY-DOKON\tools\installer\staging\backend-local"
#endif

#ifndef OutputDir
  #define OutputDir "D:\sovga\UY-DOKON\tools\installer\output"
#endif

[Setup]
AppId={{A9D06AD7-19F8-4E61-8B77-62E06A0D7C91}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\ATAWAY Local Backend
DefaultGroupName=ATAWAY Local Backend
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ataway-local-backend-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayIcon={app}\tools\nssm.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Dirs]
Name: "{app}\logs"
Name: "{app}\mongo-data"

[Files]
Source: "{#StageDir}\backend\*"; DestDir: "{app}\backend"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#StageDir}\node\*"; DestDir: "{app}\node"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#StageDir}\mongo\*"; DestDir: "{app}\mongo"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#StageDir}\tools\*"; DestDir: "{app}\tools"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\ATAWAY Local Backend\Open Install Folder"; Filename: "{app}"
Name: "{autodesktop}\ATAWAY Local Backend Folder"; Filename: "{app}"
Name: "{autoprograms}\ATAWAY Local Backend\Control Center"; Filename: "{app}\tools\ataway-control-center.exe"
Name: "{autodesktop}\ATAWAY Backend Control Center"; Filename: "{app}\tools\ataway-control-center.exe"
Name: "{autoprograms}\ATAWAY Local Backend\MongoDB Compass"; Filename: "{localappdata}\MongoDBCompass\Update.exe"; Parameters: "--processStart MongoDBCompass.exe"

[Run]
Filename: "{cmd}"; Parameters: "/c start /wait """" ""{app}\tools\compass-install.exe"" /S & exit /b 0"; Flags: runhidden waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "install ATAWAYMongoDB ""{app}\mongo\bin\mongod.exe"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYMongoDB AppDirectory ""{app}\mongo\bin"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYMongoDB AppParameters ""--dbpath \""{app}\mongo-data\"" --bind_ip 127.0.0.1 --port 27017 --logpath \""{app}\logs\mongodb.log\"" --logappend"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYMongoDB DisplayName ""ATAWAY MongoDB"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYMongoDB Description ""ATAWAY local MongoDB service"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYMongoDB Start SERVICE_AUTO_START"; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYMongoDB AppExit Default Restart"; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "start ATAWAYMongoDB"; Flags: waituntilterminated
Filename: "{cmd}"; Parameters: "/c timeout /t 3 /nobreak >nul"; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "install ATAWAYLocalBackend ""{app}\node\node.exe"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend AppDirectory ""{app}\backend"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend AppParameters ""src/server.js"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend AppStdout ""{app}\logs\backend.log"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend AppStderr ""{app}\logs\backend-error.log"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend DisplayName ""ATAWAY Local Backend"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend Description ""ATAWAY local backend service"""; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend Start SERVICE_AUTO_START"; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend DependOnService ATAWAYMongoDB"; Flags: waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "set ATAWAYLocalBackend AppExit Default Restart"; Flags: waituntilterminated
Filename: "{cmd}"; Parameters: "/c netsh advfirewall firewall delete rule name=""ATAWAY Local Backend 4000"" >nul 2>nul"; Flags: runhidden waituntilterminated
Filename: "{cmd}"; Parameters: "/c netsh advfirewall firewall add rule name=""ATAWAY Local Backend 4000"" dir=in action=allow protocol=TCP localport=4000"; Flags: runhidden waituntilterminated
Filename: "{app}\tools\nssm.exe"; Parameters: "start ATAWAYLocalBackend"; Flags: waituntilterminated
Filename: "{app}\tools\ataway-control-center.exe"; Description: "ATAWAY Backend Control Center ni ochish"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\tools\nssm.exe"; Parameters: "stop ATAWAYLocalBackend"
Filename: "{app}\tools\nssm.exe"; Parameters: "remove ATAWAYLocalBackend confirm"
Filename: "{app}\tools\nssm.exe"; Parameters: "stop ATAWAYMongoDB"
Filename: "{app}\tools\nssm.exe"; Parameters: "remove ATAWAYMongoDB confirm"
Filename: "{cmd}"; Parameters: "/c netsh advfirewall firewall delete rule name=""ATAWAY Local Backend 4000"" >nul 2>nul"; Flags: runhidden waituntilterminated
