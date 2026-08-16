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
    /// Plain key=value settings. Not JSON on purpose: .NET Framework has no
    /// built-in JSON reader worth the reference, and this file is meant to be
    /// legible and editable by the same person who is scared of a terminal.
    /// </summary>
    internal sealed class Config
    {
        public string GameRoot = "";
        public string WatchDir = "";
        public string Watcher  = "";

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
            File.WriteAllText(Path, sb.ToString());
        }

        /// <summary>Guess anything not set, so first run needs no configuration.</summary>
        public void FillDefaults()
        {
            if (string.IsNullOrWhiteSpace(GameRoot)) GameRoot = FindGameRoot() ?? "";

            if (string.IsNullOrWhiteSpace(WatchDir) && !string.IsNullOrWhiteSpace(GameRoot))
                WatchDir = System.IO.Path.Combine(GameRoot, "_crashwatch");

            if (string.IsNullOrWhiteSpace(Watcher))
            {
                // Beside the exe first (the installed layout), then the repo
                // layout, so a developer running from source also works.
                var exeDir = AppDomain.CurrentDomain.BaseDirectory;
                foreach (var candidate in new[]
                {
                    System.IO.Path.Combine(exeDir, "Watch-Crashes.ps1"),
                    System.IO.Path.Combine(exeDir, @"..\skills\cyberwise-crashes\tools\Watch-Crashes.ps1"),
                    System.IO.Path.Combine(exeDir, @"..\..\skills\cyberwise-crashes\tools\Watch-Crashes.ps1"),
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
        private const string TaskName = "Cyberwise crash watch";

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
            _miAtLogon   = new ToolStripMenuItem("Start automatically at logon", null, OnToggleAtLogon)
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
            _miAtLogon.Checked = TaskExists();

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

        private void StartWatcher()
        {
            if (!File.Exists(_cfg.Watcher))
            {
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
                if (!WatcherRunning())
                    MessageBox.Show("The watcher was launched but is not running.\n\n" +
                                    "Check the paths in Settings, especially if any contain unusual characters.",
                                    "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            catch (Exception ex)
            {
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

        private static bool TaskExists()
        {
            try
            {
                var p = Run("schtasks.exe", "/Query /TN \"" + TaskName + "\"");
                return p.ExitCode == 0;
            }
            catch { return false; }
        }

        private void OnToggleAtLogon(object sender, EventArgs e)
        {
            if (TaskExists())
            {
                var p = Run("schtasks.exe", "/Delete /TN \"" + TaskName + "\" /F");
                if (p.ExitCode != 0)
                    MessageBox.Show("Could not remove the logon task:\n\n" + p.Error, "Cyberwise",
                                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            else
            {
                if (!File.Exists(_cfg.Watcher))
                {
                    MessageBox.Show("Set the Watcher path in Settings first.", "Cyberwise",
                                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                // schtasks needs the whole command as ONE argument, so the inner
                // quotes are doubled. Getting this wrong registers a task that
                // silently never runs.
                var inner = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden"
                          + " -File \\\"" + _cfg.Watcher + "\\\""
                          + " -Dir \\\"" + _cfg.WatchDir + "\\\""
                          + (string.IsNullOrWhiteSpace(_cfg.GameRoot) ? "" : " -GameRoot \\\"" + _cfg.GameRoot + "\\\"");
                var p = Run("schtasks.exe",
                    "/Create /SC ONLOGON /TN \"" + TaskName + "\" /TR \"" + inner + "\" /F /RL LIMITED");

                if (p.ExitCode != 0)
                    MessageBox.Show("Could not create the logon task:\n\n" + p.Error +
                                    "\n\nThis can be blocked by company policy. The watcher still works while " +
                                    "Cyberwise is running - it just will not start by itself after a reboot.",
                                    "Cyberwise", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                else if (!TaskExists())
                    MessageBox.Show("The task was reported as created but is not there afterwards.",
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
            try { Clipboard.SetText(sb.ToString()); _icon.ShowBalloonTip(4000, "Cyberwise", "Summary copied to the clipboard.", ToolTipIcon.Info); }
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
            sb.AppendLine("  logon task    : " + (TaskExists() ? "registered" : "not registered"));

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
                float mid = s * 0.5f;
                float tipL = s * 0.035f, tipR = s * 0.965f;
                float top = s * 0.175f, bot = s * 0.825f;

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

                    float id = s * 0.58f;
                    var irisRect = new RectangleF((s - id) / 2f, (s - id) / 2f, id, id);
                    using (var b = new SolidBrush(iris)) g.FillEllipse(b, irisRect);
                    using (var rim = new Pen(Color.FromArgb(120, 0, 0, 0), Math.Max(1f, s * 0.05f)))
                        g.DrawEllipse(rim, irisRect);

                    // Slit pupil - the one feature doing the "not human" work.
                    float pw = Math.Max(1.5f, s * 0.115f);
                    float ph = s * 0.56f;
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
