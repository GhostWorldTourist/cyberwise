// CyberwiseTray.cs -- a tray icon for people who do not open terminals.
//
// WHY THIS EXISTS
//
// Cyberwise's diagnostics are PowerShell, and its audience is Cyberpunk 2077
// modders, most of whom will never open a terminal. A tray icon is an interface
// point they already understand: it is visible, it has a menu, and it can be
// clicked. This is that point.
//
// Its first job is the crash watcher. A watcher launched from a shell dies with
// the shell, dies on reboot, and dies silently if it throws - and an
// investigation that believes it is recording and is not is worse than one that
// knows it has no data. So the icon shows watcher state at a glance and turns
// RED when the game is running and the watcher is not, which is the only
// combination that is actively losing evidence.
//
// TARGET: .NET Framework 4.8, deliberately. It ships with Windows 10 1903+ and
// Windows 11, so the exe has NO runtime for a user to install - which matters
// more than language features for an audience that is already intimidated. It
// also builds with the csc.exe already on every Windows box, so no SDK is
// needed to produce it. See build.ps1.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

// Windows shows an executable's FileDescription - not its filename - in
// Settings > Taskbar > "Select which icons appear on the taskbar", in Task
// Manager, and in the file's own properties. With no version resource it falls
// back to "CyberwiseTray.exe", which looks like something that installed itself
// without asking. AssemblyTitle becomes FileDescription; csc builds the Win32
// version resource from these attributes, so no separate .rc file is needed.
[assembly: System.Reflection.AssemblyTitle("Cyberwise")]
[assembly: System.Reflection.AssemblyDescription("Crash watcher and diagnostics for modded Cyberpunk 2077")]
[assembly: System.Reflection.AssemblyProduct("Cyberwise")]
[assembly: System.Reflection.AssemblyCompany("Ghost World Tourist")]
[assembly: System.Reflection.AssemblyCopyright("MIT")]
[assembly: System.Reflection.AssemblyVersion("2026.8.16.0")]
[assembly: System.Reflection.AssemblyFileVersion("2026.8.16.0")]

namespace Cyberwise
{
    internal static class Program
    {
        [DllImport("kernel32.dll")] private static extern bool AttachConsole(int pid);
        private const int ATTACH_PARENT_PROCESS = -1;

        [STAThread]
        private static void Main(string[] args)
        {
            args = args ?? new string[0];

            // --run-value <name>: check a different Run entry than the real one.
            // For tests, so proving the stale-path warning never involves
            // breaking the user's own logon setting.
            int rv = Array.FindIndex(args, a => a.Equals("--run-value", StringComparison.OrdinalIgnoreCase));
            if (rv >= 0 && args.Length > rv + 1) TrayApp.RunValue = args[rv + 1];

            // --selftest prints what the app can see and exits. This is a
            // /target:winexe, so it has no console of its own - attaching to the
            // parent's lets it report into the terminal that launched it.
            //
            // It earns its place twice: it is the only way to verify detection
            // without eyeballing a tray menu, and it gives a non-technical user
            // something to paste when asking for help.
            if (args != null && args.Any(a => a.Equals("--selftest", StringComparison.OrdinalIgnoreCase)))
            {
                AttachConsole(ATTACH_PARENT_PROCESS);
                Console.WriteLine(TrayApp.SelfTest());
                return;
            }

            // --icon-preview <file.png> renders the icon at every tray size on
            // both light and dark backgrounds. A 16 px icon cannot be judged from
            // source, and this is the only honest way to check it is legible.
            int pi = Array.FindIndex(args ?? new string[0],
                a => a.Equals("--icon-preview", StringComparison.OrdinalIgnoreCase));
            if (pi >= 0 && args.Length > pi + 1)
            {
                AttachConsole(ATTACH_PARENT_PROCESS);
                TrayApp.WriteIconPreview(args[pi + 1]);
                Console.WriteLine("wrote " + args[pi + 1]);
                return;
            }

            // One tray icon, not one per launch. A second icon controlling the
            // same watcher is a good way to end up with two watchers.
            bool isNew;
            using (var mutex = new Mutex(true, "Global\\CyberwiseTraySingleInstance", out isNew))
            {
                if (!isNew)
                {
                    MessageBox.Show("Cyberwise is already running - look for the icon in your system tray.",
                        "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var tray = new TrayApp()) { Application.Run(); }
            }
        }
    }

    /// <summary>
    /// Text that is on its way to somewhere with a length limit.
    /// </summary>
    // "Copy crash summary" exists so somebody can paste it into a help channel,
    // and Discord caps a message at 2000 characters. Going over does not arrive
    // truncated - it does not arrive at all, and the person is left retyping it
    // by hand at the exact moment they are already stuck.
    //
    // PUBLIC, and pulled out of the menu handler, so the test suite can call it
    // with no clipboard, no tray and no game. A cap that only runs behind a
    // context menu is a cap nobody ever proves.
    public static class Paste
    {
        public const int DiscordLimit = 2000;

        /// <summary>
        /// Trim to <paramref name="limit"/> characters by dropping whole lines
        /// off the END, then saying how many went. Callers list newest first, so
        /// what goes is the oldest.
        /// </summary>
        public static string Fit(string text, int limit)
        {
            if (string.IsNullOrEmpty(text) || text.Length <= limit) return text;

            var lines = new List<string>(text.Replace("\r\n", "\n").TrimEnd('\n').Split('\n'));
            int dropped = 0;
            while (lines.Count > 1)
            {
                lines.RemoveAt(lines.Count - 1);
                dropped++;
                string note = string.Format(
                    "  ...and {0} more line(s), dropped to fit a {1}-character message.", dropped, limit);
                string candidate = string.Join(Environment.NewLine, lines)
                                 + Environment.NewLine + note + Environment.NewLine;
                if (candidate.Length <= limit) return candidate;
            }

            // One line longer than the whole budget. Cutting it mid-word is ugly;
            // returning something that will not send is worse.
            return text.Substring(0, Math.Max(0, limit - 1)) + "…";
        }
    }

    /// <summary>
    /// Plain key=value settings. Not JSON on purpose: .NET Framework has no
    /// built-in JSON reader worth the reference, and this file is meant to be
    /// legible and editable by the same person who is scared of a terminal.
    /// </summary>
    internal sealed class Config
    {
        public string GameRoot = "";
        public string WatchDir = "";
        public string Watcher  = "";
        // Start watching as soon as the tray starts. On by default: someone who
        // installed a crash watcher wants it watching, and an icon that sits
        // there recording nothing until you find the right menu item is a trap.
        public bool AutoStartWatcher = true;

        public static string Path
        {
            get
            {
                var dir = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "cyberwise");
                Directory.CreateDirectory(dir);
                return System.IO.Path.Combine(dir, "tray.ini");
            }
        }

        public static Config Load()
        {
            var c = new Config();
            if (File.Exists(Path))
            {
                foreach (var line in File.ReadAllLines(Path))
                {
                    var i = line.IndexOf('=');
                    if (i <= 0 || line.TrimStart().StartsWith("#")) continue;
                    var k = line.Substring(0, i).Trim();
                    var v = line.Substring(i + 1).Trim();
                    if (k.Equals("GameRoot", StringComparison.OrdinalIgnoreCase)) c.GameRoot = v;
                    else if (k.Equals("WatchDir", StringComparison.OrdinalIgnoreCase)) c.WatchDir = v;
                    else if (k.Equals("Watcher", StringComparison.OrdinalIgnoreCase)) c.Watcher = v;
                    else if (k.Equals("AutoStartWatcher", StringComparison.OrdinalIgnoreCase))
                        c.AutoStartWatcher = !(v.Equals("false", StringComparison.OrdinalIgnoreCase) || v == "0");
                }
            }
            c.FillDefaults();
            return c;
        }

        public void Save()
        {
            var sb = new StringBuilder();
            sb.AppendLine("# Cyberwise tray settings. Edit and then use Reload settings in the menu.");
            sb.AppendLine("# GameRoot: your Cyberpunk 2077 folder (the one containing bin\\x64).");
            sb.AppendLine("GameRoot=" + GameRoot);
            sb.AppendLine("# WatchDir: where crash logs are written.");
            sb.AppendLine("WatchDir=" + WatchDir);
            sb.AppendLine("# Watcher: full path to Watch-Crashes.ps1.");
            sb.AppendLine("Watcher=" + Watcher);
            sb.AppendLine("# AutoStartWatcher: begin watching as soon as Cyberwise starts.");
            sb.AppendLine("AutoStartWatcher=" + (AutoStartWatcher ? "true" : "false"));
            File.WriteAllText(Path, sb.ToString());
        }

        /// <summary>Guess anything not set, so first run needs no configuration.</summary>
        public void FillDefaults()
        {
            if (string.IsNullOrWhiteSpace(GameRoot)) GameRoot = FindGameRoot() ?? "";

            if (string.IsNullOrWhiteSpace(WatchDir) && !string.IsNullOrWhiteSpace(GameRoot))
                WatchDir = System.IO.Path.Combine(GameRoot, "_crashwatch");

            // A REMEMBERED PATH THAT NO LONGER EXISTS IS WORSE THAN NO PATH.
            // The settings file survives moving, reinstalling or deleting the
            // copy it was written by - so an installed build happily inherits a
            // Watcher path pointing into a repo that has since been tidied away.
            // The tray then checks File.Exists, finds nothing, and silently does
            // not watch: no icon change, no message, no recording.
            // Forget it and re-derive instead.
            if (!string.IsNullOrWhiteSpace(Watcher) && !File.Exists(Watcher)) { Watcher = ""; }

            // ...AND A REMEMBERED PATH TO THE FLAT FALLBACK COPY IS AS BAD,
            // for a reason that is invisible from here: it EXISTS, so the check
            // above happily keeps it, but it cannot resolve
            // New-InstallSnapshot.ps1 beside it. The watcher then runs, samples
            // fine, and silently records no session-start snapshot - so the one
            // question the snapshots exist to answer, WHAT CHANGED SINCE THIS
            // LAST WORKED, has nothing behind it.
            //
            // This is the half that reaches EXISTING installs. Preferring the
            // skills-tree copy in the candidate list below only helps a machine
            // that has never written this file; anyone who ran an older build
            // keeps the crippled path for ever. Judge the remembered path by
            // whether it can actually do the job, not by whether it is there.
            if (!string.IsNullOrWhiteSpace(Watcher))
            {
                try
                {
                    var dir = System.IO.Path.GetDirectoryName(Watcher);
                    if (string.IsNullOrEmpty(dir) ||
                        !File.Exists(System.IO.Path.Combine(dir, "New-InstallSnapshot.ps1")))
                    { Watcher = ""; }
                }
                catch { Watcher = ""; }
            }

            // A REMEMBERED PATH TO THE FLAT FALLBACK IS REPLACED WHEN THE REAL
            // ONE IS THERE. The check above asks whether the remembered copy
            // CAN snapshot, and on this machine an older installer had left
            // New-InstallSnapshot.ps1 beside the flat copy - so it passes, and
            // the flat path is kept for ever even though the proper copy sits
            // in the skills tree next to it. That leftover is not shipped any
            // more, so the day anything tidies it the watcher silently stops
            // snapshotting and nothing says so.
            //
            // Narrow on purpose: only a path in the app ROOT is replaced, and
            // only when a skills-tree copy actually exists. Someone who pointed
            // Watcher at their own clone meant it, and keeps it.
            if (!string.IsNullOrWhiteSpace(Watcher))
            {
                try
                {
                    var exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(System.IO.Path.DirectorySeparatorChar);
                    var dir = (System.IO.Path.GetDirectoryName(Watcher) ?? "").TrimEnd(System.IO.Path.DirectorySeparatorChar);
                    if (string.Equals(dir, exeDir, StringComparison.OrdinalIgnoreCase))
                    {
                        var proper = System.IO.Path.Combine(exeDir, @"skills\cyberwise-crashes\tools\Watch-Crashes.ps1");
                        if (File.Exists(proper)) { Watcher = proper; }
                    }
                }
                catch { }
            }

            if (string.IsNullOrWhiteSpace(Watcher))
            {
                // PREFER THE COPY INSIDE THE SKILLS TREE, in every layout.
                //
                // Watch-Crashes.ps1 resolves its siblings from $PSScriptRoot -
                // New-InstallSnapshot.ps1 for the session-start snapshot, and
                // UpstreamGuard.ps1 two directories up. Run from a flat copy
                // beside the exe, neither path exists: the snapshot silently
                // never happens, so "what changed since it last worked" - the
                // first question a crash asks - has nothing to answer with.
                //
                // The installed layout puts the tree at {app}\skills, which was
                // missing from this list entirely, so an install could only ever
                // find the flat copy. Both installed and repo layouts are listed
                // below, tree first, and the flat copy is kept last as a
                // fallback for an older install that has one.
                var exeDir = AppDomain.CurrentDomain.BaseDirectory;
                foreach (var candidate in new[]
                {
                    System.IO.Path.Combine(exeDir, @"skills\cyberwise-crashes\tools\Watch-Crashes.ps1"),
                    System.IO.Path.Combine(exeDir, @"..\skills\cyberwise-crashes\tools\Watch-Crashes.ps1"),
                    System.IO.Path.Combine(exeDir, @"..\..\skills\cyberwise-crashes\tools\Watch-Crashes.ps1"),
                    System.IO.Path.Combine(exeDir, "Watch-Crashes.ps1"),
                })
                {
                    if (File.Exists(candidate)) { Watcher = System.IO.Path.GetFullPath(candidate); break; }
                }
            }
        }

        /// <summary>
        /// Steam, GOG and Epic all install elsewhere and the drive is the user's
        /// choice, so never assume a default path - read the storefront's own
        /// record. Anything found is confirmed by the exe actually being there.
        /// </summary>
        public static string FindGameRoot()
        {
            var seen = new List<string>();

            try
            {
                var steam = Microsoft.Win32.Registry.GetValue(
                    @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath", null) as string;
                if (!string.IsNullOrEmpty(steam))
                {
                    seen.Add(System.IO.Path.Combine(steam, @"steamapps\common\Cyberpunk 2077"));

                    // Libraries can live on other drives; libraryfolders.vdf lists them.
                    var vdf = System.IO.Path.Combine(steam, @"steamapps\libraryfolders.vdf");
                    if (File.Exists(vdf))
                        foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\""))
                            seen.Add(System.IO.Path.Combine(m.Groups[1].Value.Replace(@"\\", @"\"),
                                @"steamapps\common\Cyberpunk 2077"));
                }
            }
            catch { /* a missing or unreadable key is not an error, just no answer */ }

            try
            {
                foreach (var root in new[] { @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\GOG.com\Games\1423049311",
                                             @"HKEY_LOCAL_MACHINE\SOFTWARE\GOG.com\Games\1423049311" })
                {
                    var gog = Microsoft.Win32.Registry.GetValue(root, "path", null) as string;
                    if (!string.IsNullOrEmpty(gog)) seen.Add(gog);
                }
            }
            catch { }

            foreach (var p in seen)
                if (!string.IsNullOrEmpty(p) && File.Exists(System.IO.Path.Combine(p, @"bin\x64\Cyberpunk2077.exe")))
                    return p;

            return null;
        }
    }

    internal sealed class TrayApp : IDisposable
    {

        private readonly NotifyIcon _icon;
        private readonly ContextMenuStrip _menu;
        // Fully qualified: System.Threading is imported for Mutex/Sleep, and it
        // has a Timer too. The ambiguity is a compile error, not a silent pick.
        private readonly System.Windows.Forms.Timer _timer;

        private readonly ToolStripMenuItem _miStatus, _miGame, _miCrashes;
        private readonly ToolStripMenuItem _miStartStop, _miAtLogon;

        private Config _cfg;
        private int _lastCrashCount = -1;
        private State _state = State.Unknown;

        private enum State { Unknown, Idle, Watching, Losing }

        public TrayApp()
        {
            _cfg = Config.Load();

            _menu = new ContextMenuStrip();

            var title = new ToolStripMenuItem("Cyberwise") { Enabled = false };
            _miStatus  = new ToolStripMenuItem("Watcher: …")   { Enabled = false };
            _miGame    = new ToolStripMenuItem("Game: …")      { Enabled = false };
            _miCrashes = new ToolStripMenuItem("Crashes: …")   { Enabled = false };

            _miStartStop = new ToolStripMenuItem("Start watching", null, OnStartStop);
            _miAtLogon   = new ToolStripMenuItem("Start Cyberwise when I log in", null, OnToggleAtLogon)
                           { CheckOnClick = false };

            _menu.Items.Add(title);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(_miStatus);
            _menu.Items.Add(_miGame);
            _menu.Items.Add(_miCrashes);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(_miStartStop);
            _menu.Items.Add(_miAtLogon);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(new ToolStripMenuItem("Copy crash summary", null, OnCopySummary));
            _menu.Items.Add(new ToolStripMenuItem("Open crash folder", null, OnOpenFolder));
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(new ToolStripMenuItem("Settings…", null, OnSettings));
            _menu.Items.Add(new ToolStripMenuItem("Reload settings", null, (s, e) => { _cfg = Config.Load(); Refresh(); }));
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(new ToolStripMenuItem("Exit", null, OnExit));

            _icon = new NotifyIcon
            {
                Icon = MakeIcon(Color.Gray),
                Text = "Cyberwise",
                Visible = true,
                ContextMenuStrip = _menu
            };
            _icon.DoubleClick += (s, e) => OnOpenFolder(s, e);

            // 5 s is responsive enough to feel live and cheap enough to ignore.
            _timer = new System.Windows.Forms.Timer { Interval = 5000 };
            _timer.Tick += (s, e) => Refresh();
            _timer.Start();

            // Write the settings file on first run so the detected values are
            // visible and editable, rather than living only in memory where a
            // user cannot see what was guessed on their behalf.
            if (!File.Exists(Config.Path)) { try { _cfg.Save(); } catch { } }

            // Start watching without being asked. This is what makes autostart
            // mean something: after a reboot the icon returns AND the recording
            // resumes, rather than the icon returning and quietly recording
            // nothing until someone notices.
            if (_cfg.AutoStartWatcher && !WatcherRunning())
            {
                if (File.Exists(_cfg.Watcher)) { try { StartWatcher(silent: true); } catch { } }
                else
                {
                    // Say it. Silently not watching is the failure this app is
                    // for; it must never be the thing doing it.
                    _icon.ShowBalloonTip(10000, "Cyberwise",
                        "Cannot find the crash watcher script, so nothing is being recorded. "
                        + "Open Settings and check the Watcher path.", ToolTipIcon.Error);
                }
            }

            // Say so at startup if the logon entry is stale. This is the one
            // moment the user is looking, and the alternative is finding out
            // weeks later that nothing has started since they moved a folder.
            var autoProblem = AutoStartProblem();
            if (autoProblem != null)
                _icon.ShowBalloonTip(10000, "Cyberwise startup", autoProblem.Split('\n')[0], ToolTipIcon.Warning);

            if (string.IsNullOrWhiteSpace(_cfg.GameRoot))
            {
                _icon.ShowBalloonTip(8000, "Cyberwise",
                    "Could not find Cyberpunk 2077 automatically. Open Settings and set GameRoot.",
                    ToolTipIcon.Warning);
            }
            Refresh();
        }

        // ------------------------------------------------------------- state --

        private string CrashDir
        {
            get { return string.IsNullOrWhiteSpace(_cfg.WatchDir) ? null : Path.Combine(_cfg.WatchDir, "crashinfo"); }
        }

        private static bool GameRunning()
        {
            try { return Process.GetProcessesByName("Cyberpunk2077").Length > 0; } catch { return false; }
        }

        /// <summary>
        /// Find the watcher by its -File argument, NOT by a bare script-name
        /// substring: a bare match also matches the process doing the asking,
        /// which cheerfully reports a watcher that is not running.
        /// </summary>
        private static bool WatcherRunning()
        {
            try
            {
                using (var s = new System.Management.ManagementObjectSearcher(
                    "SELECT CommandLine FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'"))
                foreach (var o in s.Get())
                {
                    var cl = o["CommandLine"] as string;
                    if (cl != null && cl.IndexOf("-File", StringComparison.OrdinalIgnoreCase) >= 0
                                   && cl.IndexOf("Watch-Crashes.ps1", StringComparison.OrdinalIgnoreCase) >= 0)
                        return true;
                }
            }
            catch { }
            return false;
        }

        private int CrashCount()
        {
            var d = CrashDir;
            if (d == null || !Directory.Exists(d)) return 0;
            // Top level only: _superseded holds de-duplicated copies and counting
            // them would report crashes that never happened.
            return Directory.GetFiles(d, "*.json", SearchOption.TopDirectoryOnly).Length;
        }

        private void Refresh()
        {
            bool watching = WatcherRunning();
            bool game     = GameRunning();
            int  crashes  = CrashCount();

            // The one combination that is actively losing evidence gets its own
            // colour, because it is the only one the user must act on.
            State next = !watching ? (game ? State.Losing : State.Idle) : State.Watching;

            if (next != _state)
            {
                _state = next;
                Color c = next == State.Watching ? Color.FromArgb(0x35, 0xC7, 0x59)
                        : next == State.Losing   ? Color.FromArgb(0xE0, 0x3B, 0x3B)
                        : Color.FromArgb(0xC9, 0x9A, 0x2E);
                var old = _icon.Icon;
                _icon.Icon = MakeIcon(c);
                if (old != null) DestroyIcon(old.Handle);

                if (next == State.Losing)
                    _icon.ShowBalloonTip(8000, "Cyberwise",
                        "The game is running but the crash watcher is not. Nothing is being recorded.",
                        ToolTipIcon.Warning);
            }

            _miStatus.Text    = "Watcher: " + (watching ? "running" : "stopped");
            _miGame.Text      = "Game: "    + (game ? "running" : "not running");
            _miCrashes.Text   = "Crashes recorded: " + crashes;
            _miStartStop.Text = watching ? "Stop watching" : "Start watching";
            _miAtLogon.Checked = AutoStartEnabled();

            _icon.Text = Truncate("Cyberwise - " + (watching ? "watching" : "not watching")
                                  + (game ? ", game running" : "") + " - " + crashes + " crash(es)");

            if (_lastCrashCount >= 0 && crashes > _lastCrashCount)
                _icon.ShowBalloonTip(10000, "Crash recorded", LatestCrashLine() ?? "A new crash was captured.",
                    ToolTipIcon.Info);
            _lastCrashCount = crashes;
        }

        // NotifyIcon.Text throws above 63 characters rather than truncating.
        private static string Truncate(string s) { return s.Length <= 63 ? s : s.Substring(0, 60) + "..."; }

        // ------------------------------------------------------------ actions --

        private void OnStartStop(object sender, EventArgs e)
        {
            if (WatcherRunning()) { StopWatcher(); }
            else                  { StartWatcher(); }
            Refresh();
        }

        private void StartWatcher(bool silent = false)
        {
            if (!File.Exists(_cfg.Watcher))
            {
                if (silent) return;
                MessageBox.Show("Cannot find Watch-Crashes.ps1.\n\nExpected at:\n" + _cfg.Watcher +
                                "\n\nOpen Settings and set the Watcher path.",
                                "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            try
            {
                Directory.CreateDirectory(_cfg.WatchDir);
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    // EVERY path is quoted. The default game folder is
                    // "Cyberpunk 2077" - with a space - and an unquoted path
                    // splits, so PowerShell receives a truncated -File and dies
                    // instantly. That failure looks exactly like "the platform
                    // will not let me start a process", and once cost real time.
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden"
                              + " -File \"" + _cfg.Watcher + "\""
                              + " -Dir \"" + _cfg.WatchDir + "\""
                              + (string.IsNullOrWhiteSpace(_cfg.GameRoot) ? "" : " -GameRoot \"" + _cfg.GameRoot + "\""),
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                Process.Start(psi);

                // Started is not running. Confirm before claiming success -
                // reporting a watcher that is not there is the failure this
                // whole application exists to prevent.
                Thread.Sleep(1200);
                if (!WatcherRunning() && !silent)
                    MessageBox.Show("The watcher was launched but is not running.\n\n" +
                                    "Check the paths in Settings, especially if any contain unusual characters.",
                                    "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            catch (Exception ex)
            {
                if (silent) return;
                MessageBox.Show("Could not start the watcher:\n\n" + ex.Message,
                                "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void StopWatcher()
        {
            try
            {
                using (var s = new System.Management.ManagementObjectSearcher(
                    "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'"))
                foreach (var o in s.Get())
                {
                    var cl = o["CommandLine"] as string;
                    if (cl == null) continue;
                    if (cl.IndexOf("-File", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    if (cl.IndexOf("Watch-Crashes.ps1", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    try { Process.GetProcessById(Convert.ToInt32(o["ProcessId"])).Kill(); } catch { }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not stop the watcher:\n\n" + ex.Message,
                                "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // AUTOSTART VIA THE PER-USER RUN KEY, NOT A SCHEDULED TASK.
        //
        // The first version used `schtasks /Create /SC ONLOGON`, which failed
        // with "Access is denied" even in the user's own session: creating a
        // task in the root folder generally wants elevation, and this is a
        // per-user tray app that should never ask for admin. HKCU\...\Run needs
        // no elevation ever, is the ordinary mechanism for exactly this, and is
        // visible to the user in Task Manager > Startup where they can turn it
        // off without coming back here.
        //
        // It also autostarts the TRAY rather than the watcher directly. The tray
        // then starts the watcher itself, so there is one thing to supervise
        // instead of two, and the icon comes back after a reboot - which is what
        // someone means by "start automatically" anyway.
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        // Not a const: --run-value lets a test point the autostart checks at a
        // throwaway registry value instead of the user's real "Cyberwise" entry.
        // A test that has to break someone's actual logon to prove a warning
        // works is not a test anyone should run twice.
        internal static string RunValue = "Cyberwise";

        private static string ExePath { get { return Application.ExecutablePath; } }

        private static bool AutoStartEnabled() { return AutoStartTarget() != null; }

        /// <summary>The path the Run entry actually points at, or null if unset.</summary>
        private static string AutoStartTarget()
        {
            try
            {
                using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey, false))
                {
                    var v = k == null ? null : k.GetValue(RunValue) as string;
                    return string.IsNullOrWhiteSpace(v) ? null : v.Trim().Trim('"');
                }
            }
            catch { return null; }
        }

        /// <summary>
        /// Why this exists: a Run entry stores an ABSOLUTE PATH. Move, rename or
        /// delete the folder the exe lives in and Windows simply fails to launch
        /// it at logon and says nothing at all. The symptom is "the icon stopped
        /// appearing", with no error anywhere to explain it - and if the watcher
        /// was starting from here, the recording stops with it.
        ///
        /// Returns null when everything is fine, or a sentence describing the
        /// problem. Checked at startup and reported by --selftest, because a
        /// broken autostart that nothing detects is the same failure mode as a
        /// watcher that is not running and nothing says so.
        /// </summary>
        private static string AutoStartProblem()
        {
            var target = AutoStartTarget();
            if (target == null) return null;

            if (!File.Exists(target))
                return "Cyberwise is set to start when you log in, but the file it points at is gone:\n\n"
                     + target + "\n\nIt was probably moved or renamed. Turn the setting off and on again "
                     + "to point it at this copy.";

            try
            {
                if (!string.Equals(Path.GetFullPath(target), Path.GetFullPath(ExePath),
                                   StringComparison.OrdinalIgnoreCase))
                    return "Logon startup points at a different copy of Cyberwise:\n\n" + target
                         + "\n\nThis one is:\n\n" + ExePath
                         + "\n\nThat is fine if you meant it - otherwise turn the setting off and on again.";
            }
            catch { }
            return null;
        }

        private void OnToggleAtLogon(object sender, EventArgs e)
        {
            try
            {
                using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k == null) throw new Exception("could not open the Run key");

                    if (AutoStartEnabled())
                    {
                        k.DeleteValue(RunValue, false);
                    }
                    else
                    {
                        // Quoted: the path may contain spaces, and an unquoted
                        // Run entry silently starts the wrong thing or nothing.
                        k.SetValue(RunValue, "\"" + ExePath + "\"");
                        _cfg.AutoStartWatcher = true;
                        try { _cfg.Save(); } catch { }
                    }
                }

                // Confirm rather than assume: reporting a setting that did not
                // take is the failure this app exists to prevent elsewhere.
                bool want = !_miAtLogon.Checked;
                if (AutoStartEnabled() != want)
                    MessageBox.Show("Windows did not accept the change to startup settings.",
                                    "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not change the startup setting:\n\n" + ex.Message +
                                "\n\nCyberwise still works while it is open - it just will not " +
                                "start by itself after a reboot.",
                                "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            Refresh();
        }

        private void OnOpenFolder(object sender, EventArgs e)
        {
            var d = CrashDir;
            if (d == null) { OnSettings(sender, e); return; }
            Directory.CreateDirectory(d);
            try { Process.Start("explorer.exe", "\"" + d + "\""); } catch { }
        }

        private void OnSettings(object sender, EventArgs e)
        {
            if (!File.Exists(Config.Path)) _cfg.Save();
            try { Process.Start(new ProcessStartInfo(Config.Path) { UseShellExecute = true }); } catch { }
        }

        /// <summary>
        /// A summary someone can paste when asking for help - which is what this
        /// audience actually needs to do next.
        /// </summary>
        private void OnCopySummary(object sender, EventArgs e)
        {
            var sb = new StringBuilder();
            sb.AppendLine("Cyberpunk 2077 crash summary");
            sb.AppendLine("game version: " + GameVersion());
            sb.AppendLine("crashes recorded: " + CrashCount());
            var d = CrashDir;
            if (d != null && Directory.Exists(d))
                foreach (var f in Directory.GetFiles(d, "*.json", SearchOption.TopDirectoryOnly)
                                           .OrderByDescending(File.GetLastWriteTimeUtc).Take(10))
                    sb.AppendLine("  " + Summarise(f));

            // Crashes are listed newest first, so what Fit drops off the end is
            // the oldest and least relevant. Ten unreadable files or a couple of
            // very long district names is all it takes to run over.
            string text = Paste.Fit(sb.ToString(), Paste.DiscordLimit);
            try { Clipboard.SetText(text); _icon.ShowBalloonTip(4000, "Cyberwise", "Summary copied to the clipboard.", ToolTipIcon.Info); }
            catch { }
        }

        private string GameVersion()
        {
            try
            {
                var exe = Path.Combine(_cfg.GameRoot ?? "", @"bin\x64\Cyberpunk2077.exe");
                return File.Exists(exe) ? FileVersionInfo.GetVersionInfo(exe).ProductVersion : "unknown";
            }
            catch { return "unknown"; }
        }

        private string LatestCrashLine()
        {
            var d = CrashDir;
            if (d == null || !Directory.Exists(d)) return null;
            var f = Directory.GetFiles(d, "*.json", SearchOption.TopDirectoryOnly)
                             .OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
            return f == null ? null : Summarise(f);
        }

        /// <summary>
        /// Pull the few fields worth showing straight out of the text. Regex
        /// rather than a parser is a deliberate trade for zero dependencies -
        /// and if CDPR changes the shape, this degrades to "(unreadable)" rather
        /// than crashing the tray.
        /// </summary>
        private static string Summarise(string file)
        {
            try
            {
                var t = File.ReadAllText(file);
                string district = Match(t, "\"district\"\\s*:\\s*\"([^\"]*)\"");
                string when     = Match(t, "\"timeCrash\"\\s*:\\s*\"([^\"]*)\"");
                string len      = Match(t, "\"sessionLength\"\\s*:\\s*([0-9.]+)");
                string oom      = Match(t, "\"isOom\"\\s*:\\s*(true|false)");
                double secs; double.TryParse(len, System.Globalization.NumberStyles.Any,
                                             System.Globalization.CultureInfo.InvariantCulture, out secs);
                return string.Format("{0}  {1}  after {2} min{3}",
                    string.IsNullOrEmpty(when) ? "?" : when,
                    string.IsNullOrEmpty(district) ? "(no district)" : district,
                    Math.Round(secs / 60.0, 1),
                    oom == "true" ? "  OUT OF MEMORY" : "");
            }
            catch { return Path.GetFileName(file) + " (unreadable)"; }
        }

        private static string Match(string text, string pattern)
        {
            var m = Regex.Match(text, pattern);
            return m.Success ? m.Groups[1].Value : "";
        }

        private void OnExit(object sender, EventArgs e)
        {
            // Leave the watcher running on purpose: quitting the UI should not
            // stop the recording someone may be relying on. Stop watching first
            // if that is what you meant.
            _icon.Visible = false;
            Application.Exit();
        }

        // ------------------------------------------------------------- plumbing --

        /// <summary>
        /// Everything the app can see, as text. Deliberately reports what it
        /// FOUND rather than what it assumed - "not found" is a real answer and
        /// far more useful than a plausible default.
        /// </summary>
        public static string SelfTest()
        {
            var cfg = Config.Load();
            var sb = new StringBuilder();
            sb.AppendLine("Cyberwise tray self-test");
            sb.AppendLine("  settings file : " + Config.Path + (File.Exists(Config.Path) ? "" : "  (not written yet)"));
            sb.AppendLine("  game root     : " + (string.IsNullOrWhiteSpace(cfg.GameRoot) ? "NOT FOUND" : cfg.GameRoot));

            var exe = string.IsNullOrWhiteSpace(cfg.GameRoot) ? null : Path.Combine(cfg.GameRoot, @"bin\x64\Cyberpunk2077.exe");
            sb.AppendLine("  game version  : " + (exe != null && File.Exists(exe)
                ? FileVersionInfo.GetVersionInfo(exe).ProductVersion : "unknown"));

            sb.AppendLine("  watch dir     : " + (string.IsNullOrWhiteSpace(cfg.WatchDir) ? "NOT SET" : cfg.WatchDir));
            sb.AppendLine("  watcher script: " + (string.IsNullOrWhiteSpace(cfg.Watcher) ? "NOT FOUND"
                : cfg.Watcher + (File.Exists(cfg.Watcher) ? "" : "  (MISSING)")));
            sb.AppendLine("  watcher       : " + (WatcherRunning() ? "running" : "not running"));
            sb.AppendLine("  game          : " + (GameRunning() ? "running" : "not running"));
            var target = AutoStartTarget();
            sb.AppendLine("  start at logon: " + (target == null ? "no" : "yes -> " + target));
            var problem = AutoStartProblem();
            if (problem != null)
                sb.AppendLine("  WARNING       : " + problem.Split('\n')[0].TrimEnd());

            var crashDir = string.IsNullOrWhiteSpace(cfg.WatchDir) ? null : Path.Combine(cfg.WatchDir, "crashinfo");
            int n = (crashDir != null && Directory.Exists(crashDir))
                ? Directory.GetFiles(crashDir, "*.json", SearchOption.TopDirectoryOnly).Length : 0;
            sb.AppendLine("  crashes       : " + n);
            if (crashDir != null && Directory.Exists(crashDir))
                foreach (var f in Directory.GetFiles(crashDir, "*.json", SearchOption.TopDirectoryOnly)
                                           .OrderByDescending(File.GetLastWriteTimeUtc).Take(5))
                    sb.AppendLine("      " + Summarise(f));
            return sb.ToString();
        }

        private sealed class RunResult { public int ExitCode; public string Error = ""; }

        private static RunResult Run(string exe, string args)
        {
            var psi = new ProcessStartInfo(exe, args)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var p = Process.Start(psi))
            {
                string err = p.StandardError.ReadToEnd();
                string outp = p.StandardOutput.ReadToEnd();
                p.WaitForExit(15000);
                return new RunResult { ExitCode = p.ExitCode, Error = string.IsNullOrWhiteSpace(err) ? outp : err };
            }
        }

        /// <summary>
        /// A cybernetic eye, drawn at runtime so state is a colour rather than a
        /// second asset to ship.
        ///
        /// DESIGNING FOR 16 PIXELS. At tray size there is room for roughly four
        /// ideas, so they have to be the right four: a dark bezel to read as
        /// hardware, a bright iris carrying the state colour, a SLIT pupil -
        /// which is what makes it read as inhuman rather than as a dot - and one
        /// specular pixel so it looks like a lens. Anything else (aperture
        /// blades, circuitry, an eyelid) turns to mud at this size.
        ///
        /// Everything is proportional to the requested size because the tray asks
        /// for 16, 20, 24 or 32 px depending on DPI, and a shape hard-coded for
        /// 16 is a blurry mess when scaled up to 32.
        ///
        /// The bezel is near-black with a light top edge: the tray background can
        /// be light OR dark, and an icon that relies on contrast with only one of
        /// them disappears on the other half of all machines.
        /// </summary>
        internal static Bitmap DrawEye(int size, Color iris)
        {
            var bmp = new Bitmap(size, size);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);

                float s = size;

                // ALMOND, not a circle. At 16 px the outline is most of what the
                // eye has to say, and a lens shape says "eye" instantly where a
                // disc says "status dot". The first version was a disc and read
                // as exactly that.
                // Sized to fill the tile. The tray gives ~16 px and every pixel
                // spent on margin is one not spent on the shape, so the lens runs
                // almost edge to edge horizontally and takes about 74% of the
                // height - enough for the slit to read, without the antialiased
                // outline clipping at the boundary.
                float mid = s * 0.5f;
                float tipL = s * 0.015f, tipR = s * 0.985f;
                float top = s * 0.13f, bot = s * 0.87f;

                using (var lens = new System.Drawing.Drawing2D.GraphicsPath())
                {
                    lens.AddBezier(tipL, mid, s * 0.26f, top, s * 0.74f, top, tipR, mid);
                    lens.AddBezier(tipR, mid, s * 0.74f, bot, s * 0.26f, bot, tipL, mid);
                    lens.CloseFigure();

                    // A pale sclera is what keeps this legible on a DARK taskbar.
                    // A dark-on-dark icon vanishes for half of all users, and no
                    // amount of iris colour fixes that.
                    using (var sclera = new SolidBrush(Color.FromArgb(255, 222, 229, 238)))
                        g.FillPath(sclera, lens);

                    // Iris clipped to the lens, so it fills the eye edge to edge
                    // the way a slit-pupil predator's does.
                    var saved = g.Clip;
                    g.SetClip(lens, System.Drawing.Drawing2D.CombineMode.Intersect);

                    float id = s * 0.68f;
                    var irisRect = new RectangleF((s - id) / 2f, (s - id) / 2f, id, id);
                    using (var b = new SolidBrush(iris)) g.FillEllipse(b, irisRect);
                    using (var rim = new Pen(Color.FromArgb(120, 0, 0, 0), Math.Max(1f, s * 0.05f)))
                        g.DrawEllipse(rim, irisRect);

                    // Slit pupil - the one feature doing the "not human" work.
                    float pw = Math.Max(1.5f, s * 0.115f);
                    float ph = s * 0.62f;
                    using (var pupil = new SolidBrush(Color.FromArgb(255, 8, 9, 11)))
                        g.FillEllipse(pupil, (s - pw) / 2f, (s - ph) / 2f, pw, ph);

                    g.Clip = saved;

                    // Dark outline last, over everything: this is what holds the
                    // shape together on a LIGHT taskbar.
                    using (var edge = new Pen(Color.FromArgb(255, 18, 20, 24), Math.Max(1f, s * 0.062f)))
                        g.DrawPath(edge, lens);
                }

                // Specular highlight - but ONLY above 16 px. At tray-default size
                // it lands within a pixel of the slit and merges with it, reading
                // as a notch bitten out of the pupil rather than as a highlight.
                // A detail that turns to noise at the size the thing is actually
                // used is worse than no detail.
                if (s >= 20)
                {
                    float gd = Math.Max(1.3f, s * 0.10f);
                    using (var glint = new SolidBrush(Color.FromArgb(225, 255, 255, 255)))
                        g.FillEllipse(glint, s * 0.29f, s * 0.27f, gd, gd);
                }
            }
            return bmp;
        }

        private static Icon MakeIcon(Color iris)
        {
            // Ask Windows what size the tray actually wants: 16 at 100% DPI, but
            // 20/24/32 as scaling goes up. Drawing at the real size beats drawing
            // 16 and letting it be stretched.
            int size = SystemInformation.SmallIconSize.Width;
            if (size < 16) size = 16;

            using (var bmp = DrawEye(size, iris))
            {
                IntPtr h = bmp.GetHicon();
                try { using (var tmp = Icon.FromHandle(h)) { return (Icon)tmp.Clone(); } }
                finally { DestroyIcon(h); }
            }
        }

        /// <summary>
        /// Render the real icon code to a PNG contact sheet: every state, every
        /// tray size, on both light and dark backgrounds, with 8x blow-ups.
        /// Uses the SAME DrawEye the tray uses, so what you inspect is what
        /// ships - a preview drawn by a second copy of the code would only prove
        /// the copy looks right.
        /// </summary>
        public static void WriteIconPreview(string path)
        {
            int[] sizes = { 16, 20, 24, 32 };
            var states = new[]
            {
                new { Name = "watching",     C = Color.FromArgb(0x35, 0xC7, 0x59) },
                new { Name = "idle",         C = Color.FromArgb(0xC9, 0x9A, 0x2E) },
                new { Name = "losing",       C = Color.FromArgb(0xE0, 0x3B, 0x3B) },
            };
            var backgrounds = new[] { Color.FromArgb(0xF3, 0xF3, 0xF3), Color.FromArgb(0x20, 0x20, 0x20) };

            int cell = 150, rowH = 150;
            using (var sheet = new Bitmap(cell * states.Length + 90, rowH * backgrounds.Length + 30))
            using (var g = Graphics.FromImage(sheet))
            using (var font = new Font("Segoe UI", 9))
            {
                g.Clear(Color.FromArgb(0x80, 0x80, 0x80));
                for (int bi = 0; bi < backgrounds.Length; bi++)
                {
                    using (var bg = new SolidBrush(backgrounds[bi]))
                        g.FillRectangle(bg, 0, 30 + bi * rowH, sheet.Width, rowH);

                    for (int si = 0; si < states.Length; si++)
                    {
                        int x = 60 + si * cell, y = 40 + bi * rowH;
                        var label = new SolidBrush(bi == 0 ? Color.Black : Color.White);
                        if (bi == 0) g.DrawString(states[si].Name, font, label, x, 8);

                        // actual sizes, in a row
                        int ax = x;
                        foreach (var sz in sizes)
                        {
                            using (var b = DrawEye(sz, states[si].C)) g.DrawImageUnscaled(b, ax, y + 40 - sz);
                            ax += sz + 6;
                        }
                        // 16 px blown up 6x, nearest neighbour: shows exactly
                        // which pixels are lit, which is what legibility is.
                        using (var b = DrawEye(16, states[si].C))
                        {
                            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
                            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
                            g.DrawImage(b, new Rectangle(x, y + 46, 96, 96));
                        }
                        label.Dispose();
                    }
                }
                sheet.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            }
        }

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool DestroyIcon(IntPtr handle);

        public void Dispose()
        {
            if (_timer != null) _timer.Dispose();
            if (_icon != null) { _icon.Visible = false; _icon.Dispose(); }
            if (_menu != null) _menu.Dispose();
        }
    }
}
