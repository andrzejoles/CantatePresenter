; Instalator CantatePresenter dla Windows (Inno Setup 6). Budowany w CI z katalogu po `dotnet publish`:
;   ISCC.exe /DAppVersion=2.7.0 /DSourceDir=...\publish\CantatePresenter /O<katalog wyjściowy> windows\installer\CantatePresenter.iss
; Instalacja dla bieżącego użytkownika bez uprawnień administratora (albo dla wszystkich, jeśli wybierze to w oknie).
; Dane (%APPDATA%\CantatePresenter) nie są częścią instalacji i zostają po odinstalowaniu.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\publish\CantatePresenter"
#endif

[Setup]
; Stały identyfikator: nowa wersja instaluje się na miejscu poprzedniej.
AppId={{C6DA36DB-7D95-4CC5-BA23-971B3CC122D0}
AppName=CantatePresenter
AppVersion={#AppVersion}
AppVerName=CantatePresenter {#AppVersion}
AppPublisher=Andrzej Oles
AppPublisherURL=https://github.com/andrzejoles/CantatePresenter
AppCopyright=© 2026 Andrzej Oles
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\CantatePresenter
DefaultGroupName=CantatePresenter
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputBaseFilename=CantatePresenter-Windows-x64-Setup-{#AppVersion}
SetupIconFile=..\src\CantatePresenter.WinUI\Assets\app.ico
UninstallDisplayIcon={app}\CantatePresenter.exe
UninstallDisplayName=CantatePresenter
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Działająca aplikacja jest zamykana przed aktualizacją (Menedżer ponownego uruchamiania Windows).
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\CantatePresenter"; Filename: "{app}\CantatePresenter.exe"
Name: "{autodesktop}\CantatePresenter"; Filename: "{app}\CantatePresenter.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\CantatePresenter.exe"; Description: "{cm:LaunchProgram,CantatePresenter}"; Flags: nowait postinstall skipifsilent
