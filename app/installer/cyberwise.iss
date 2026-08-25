; cyberwise.iss -- the installer a non-technical modder can actually run.
;
;   ..\build-installer.ps1        builds the tray exe, then compiles this
;
; DESIGN RULES, all of them about the audience rather than about Windows:
;
; 1. PER-USER, NEVER ADMIN. PrivilegesRequired=lowest means no UAC prompt at
;    all. A scary yellow shield on an unsigned installer is exactly where this
;    audience stops, and nothing here needs machine-wide rights: the app lives
;    in LocalAppData, the skills go in the user's own profile, and autostart is
;    the per-user Run key.
;
; 2. A STABLE LOCATION. The whole reason this exists: autostart stores an
;    absolute path, and running from a cloned repo means tidying a projects
;    folder silently breaks logon startup with no error anywhere. An installed
;    copy does not move.
;
; 3. REUSE install.ps1 RATHER THAN REIMPLEMENT IT. The skills are linked by the
;    same script the repo uses, shipped alongside them, so there is one linking
;    implementation to be correct instead of two to drift apart. It is also
;    non-destructive about links that already exist, which matters on a machine
;    where someone has the repo linked for development.

#define AppName      "Cyberwise"
#define AppVersion   "2026.08.25.1"
#define AppPublisher "Ghost World Tourist"
#define AppExe       "CyberwiseTray.exe"

[Setup]
AppId={{6B1C0D4E-7F2A-4C31-9E5B-CW2077BACKUP}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppSupportURL=https://github.com/GhostWorldTourist/cyberwise
DefaultDirName={localappdata}\Programs\Cyberwise
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Cyberwise-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
; The audience is Windows-only because the game's tooling is.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup";  Description: "Start Cyberwise when I log in"; GroupDescription: "Options:"
Name: "skills";   Description: "Install the Cyberwise skills for Claude Code and Codex"; GroupDescription: "Options:"
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Options:"; Flags: unchecked

[Files]
Source: "..\bin\CyberwiseTray.exe";  DestDir: "{app}"; Flags: ignoreversion
; A FALLBACK copy, not the one that should run. Watch-Crashes.ps1 resolves its
; siblings from $PSScriptRoot - New-InstallSnapshot.ps1 for the session-start
; snapshot, UpstreamGuard.ps1 two levels up - and neither exists from {app}. Run
; flat, the watcher works but silently takes no install snapshot, so "what
; changed since this last worked" has nothing to answer with. The tray now
; prefers {app}\skills\cyberwise-crashes\tools\ (shipped below) and falls back
; here only for an older install. See the candidate list in CyberwiseTray.cs.
Source: "..\..\skills\cyberwise-crashes\tools\Watch-Crashes.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\install.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\skills\*";            DestDir: "{app}\skills"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\README.md";           DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\LICENSE";             DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\README.md";              DestDir: "{app}"; DestName: "README-tray.md"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";            Filename: "{app}\{#AppExe}"
Name: "{group}\Crash logs";            Filename: "{app}"
Name: "{autodesktop}\{#AppName}";      Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Per-user autostart. No elevation, and visible to the user in Task Manager >
; Startup where they can switch it off without coming back here.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; \
    ValueName: "Cyberwise"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
; Link the skills using the repo's own installer, so there is one implementation.
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install.ps1"""; \
    StatusMsg: "Installing skills for Claude Code and Codex..."; \
    Flags: runhidden waituntilterminated; Tasks: skills
Filename: "{app}\{#AppExe}"; Description: "Start Cyberwise now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Unlink the skills before the files go, or the links are left dangling.
; install.ps1 -Remove only removes links pointing at THIS install - a link
; belonging to another copy (a cloned repo, say) is left alone. Without that,
; uninstalling here silently deletes a developer's links as a side effect.
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install.ps1"" -Remove"; \
    Flags: runhidden waituntilterminated; RunOnceId: "UnlinkSkills"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\skills"

[Code]
// Do not leave the old copy running while replacing it under itself - the
// install appears to succeed and the user keeps looking at a tray icon from a
// version that no longer exists on disk.
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/IM CyberwiseTray.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/IM CyberwiseTray.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;

// The watcher is a powershell.exe, so it cannot be killed by image name without
// taking every other PowerShell on the machine with it. Ask the tray's own
// mechanism instead: it exits when its folder mutex is gone, but the honest
// thing is simply to leave it - it is harmless, and it stops at the next logon.
// Deliberately NOT killing arbitrary powershell processes here.
