# Register-CrashWatch.ps1 -- keep the crash watcher alive without a terminal.
#
#     .\Register-CrashWatch.ps1 -Dir <output folder> [-GameRoot <path>]  # install
#     .\Register-CrashWatch.ps1 -Status                                  # is it on?
#     .\Register-CrashWatch.ps1 -Remove                                  # uninstall
#     .\Register-CrashWatch.ps1 -Dir <...> -WhatIf                       # show, do nothing
#
# WHY THIS AND NOT "just run the watcher"
#
# A watcher launched from a shell dies with the shell, dies on reboot, and dies
# silently if it throws. None of that is visible - and an investigation that
# believes it is recording, and is not, is worse than one that knows it has no
# data. The next crash looks like it produced no telemetry.
#
# A scheduled task fixes all three: it starts at logon, restarts if it stops, and
# survives reboots. It needs no elevation for a per-user logon task, and no tray
# icon or background service to install.
#
# ALSO: AN ASSISTANT MAY NOT BE ABLE TO START THE WATCHER AT ALL. In a sandboxed
# or supervised tool session the process tree can be reaped when the call
# returns, so Start-Process reports success and leaves nothing running. Register
# it as a task instead and the problem disappears - the task scheduler owns the
# process, not the session.

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Dir,
    [string] $GameRoot,
    [string] $TaskName = 'Cyberwise crash watch',
    [int]    $IntervalSec = 15,
    [switch] $Status,
    [switch] $Remove
)

$watcher = Join-Path $PSScriptRoot 'Watch-Crashes.ps1'

function Get-Task { Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }

# ------------------------------------------------------------------- status --

if ($Status) {
    $t = Get-Task
    if (-not $t) { Write-Host "not registered ('$TaskName')" -ForegroundColor Yellow; exit 0 }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host "task      $TaskName" -ForegroundColor Green
    Write-Host "state     $($t.State)"
    if ($info) {
        Write-Host "last run  $($info.LastRunTime)   result $($info.LastTaskResult)"
        Write-Host "next run  $($info.NextRunTime)"
    }
    # Registered is not running: report the process separately, and match on the
    # -File argument. A bare 'Watch-Crashes.ps1' substring also matches the query
    # doing the asking, which reports a watcher that is not there.
    $live = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
              Where-Object { $_.CommandLine -like '*-File*Watch-Crashes.ps1*' })
    Write-Host "process   $(if ($live.Count) { "running (pid $($live[0].ProcessId))" } else { 'NOT running' })" `
        -ForegroundColor $(if ($live.Count) { 'Green' } else { 'Yellow' })
    exit 0
}

# ------------------------------------------------------------------- remove --

if ($Remove) {
    if (-not (Get-Task)) { Write-Host "nothing to remove ('$TaskName' is not registered)"; exit 0 }
    if ($PSCmdlet.ShouldProcess($TaskName, 'unregister scheduled task')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "removed '$TaskName'" -ForegroundColor Green
    }
    exit 0
}

# ----------------------------------------------------------------- register --

if (-not $Dir)                              { throw "-Dir is required (where session CSVs and crashinfo\ go)" }
if (-not (Test-Path -LiteralPath $watcher)) { throw "Watch-Crashes.ps1 not found beside this script: $watcher" }

# Resolve WITHOUT touching the disk. Resolve-Path needs the path to exist, and
# under -WhatIf the directory has not been created - which silently left $Dir
# empty and printed a preview of a command containing -Dir "". A preview that
# shows something other than what would run is worse than no preview.
$Dir = [IO.Path]::GetFullPath($Dir)
if ($GameRoot) {
    if (-not (Test-Path -LiteralPath $GameRoot)) { throw "-GameRoot does not exist: $GameRoot" }
    $GameRoot = [IO.Path]::GetFullPath($GameRoot)
}

# Creating the output folder is a prerequisite, not the operation being previewed,
# so it is exempt from -WhatIf. The task registration below is what -WhatIf gates.
if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force -WhatIf:$false | Out-Null }

# Quote every path in the argument string. Start-Process -ArgumentList does NOT
# quote array elements, and the default game directory is "Cyberpunk 2077" - a
# path with a space. Getting this wrong makes the launch fail with "does not have
# a '.ps1' extension" and look, from outside, exactly like a platform limitation.
# That mistake cost real time on this project.
$args = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden'
    '-File', "`"$watcher`""
    '-Dir',  "`"$Dir`""
    '-IntervalSec', $IntervalSec
)
if ($GameRoot) { $args += @('-GameRoot', "`"$((Resolve-Path -LiteralPath $GameRoot).Path)`"") }

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($args -join ' ')
$trigger = New-ScheduledTaskTrigger -AtLogOn

# RestartCount/RestartInterval are the point of the exercise: a watcher that dies
# comes back by itself. ExecutionTimeLimit 0 = never kill it for running long.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

if ($PSCmdlet.ShouldProcess($TaskName, "register logon task running $watcher")) {
    if (Get-Task) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }

    # Register, then PROVE it. `| Out-Null` hides a non-terminating failure, and
    # this script previously printed "registered and started" over an "Access is
    # denied" that left nothing registered at all. Reporting success you have not
    # checked is the exact failure this skill warns about elsewhere; do not let
    # the tool that watches for crashes be the thing that lies about its state.
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Description "Watches Cyberpunk 2077 for crashes and captures its post-mortem telemetry (cyberwise)." `
            -ErrorAction Stop | Out-Null
    } catch {
        throw ("could not register '$TaskName': $($_.Exception.Message)`n" +
               "Task creation can be blocked by policy, by a restricted/sandboxed session, or by an " +
               "account without the right. Run this from a normal PowerShell window; if it still fails, " +
               "start the watcher directly instead:`n" +
               "  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$watcher','-Dir','$Dir'`n" +
               "(quote both paths - the default game directory contains a space)")
    }

    if (-not (Get-Task)) { throw "Register-ScheduledTask reported no error but '$TaskName' does not exist afterwards." }

    try { Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop }
    catch { Write-Warning "registered, but could not start it now: $($_.Exception.Message). It will start at next logon." }

    Write-Host "registered '$TaskName'" -ForegroundColor Green
    Write-Host "  output   $Dir"
    Write-Host "  check    .\Register-CrashWatch.ps1 -Status"
    Write-Host "  remove   .\Register-CrashWatch.ps1 -Remove"
} else {
    Write-Host "WhatIf: would register '$TaskName' running:" -ForegroundColor Yellow
    Write-Host "  powershell.exe $($args -join ' ')"
}
exit 0
