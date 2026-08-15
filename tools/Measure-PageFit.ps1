# Measure-PageFit.ps1 -- does a page fit a given viewport without scrolling?
#
#     .\Measure-PageFit.ps1 -Path page.html                 # this machine's screen
#     .\Measure-PageFit.ps1 -Path page.html -Width 1920 -Height 1080
#
# Returns the document height, the viewport, and the overflow. Eyeballing a
# screenshot tells you a page is too tall but not by how much, which turns
# layout tuning into guesswork; a number turns it into arithmetic.
#
# Works by copying the page, appending a script that stamps the measurements
# into <title>, and reading that back out of --dump-dom. Headless Chromium has
# no other way to return a value from the page over the command line.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path,

    # Viewport to test against. Omitted, it is measured from this machine's
    # primary display - the page is being sized for whoever is running this, and
    # any fixed number here would be one author's monitor. Pass both explicitly
    # when sizing for a screen you are not sitting at.
    [int] $Width,
    [int] $Height,

    [string] $Browser,
    [switch] $Screenshot,
    [string] $ShotPath
)

# NOTE: --window-size takes a comma-separated pair, and PowerShell parses a bare
# `--window-size=$W,$H` as an ARRAY - passing two separate arguments, so the flag
# is silently ignored and the browser reports its 800x600 default. Quote it.

function Get-PrimaryViewport {
    # WinForms reports the working area - the screen minus the taskbar - in the
    # process's coordinate space, which is what a maximised browser window gets
    # and therefore closer to the truth than the raw panel resolution.
    #
    # Two ways it can be unavailable: PowerShell without the Windows Desktop
    # runtime, and non-Windows. Fall back to the display mode, then to 1080p,
    # which is an arbitrary but stated default rather than a silent one.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        if ($wa.Width -gt 0 -and $wa.Height -gt 0) { return @([int]$wa.Width, [int]$wa.Height) }
    } catch { }
    try {
        $v = Get-CimInstance Win32_VideoController -ErrorAction Stop |
             Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
        if ($v) { return @([int]$v.CurrentHorizontalResolution, [int]$v.CurrentVerticalResolution) }
    } catch { }
    return @(1920, 1080)
}

if (-not $Width -or -not $Height) {
    $auto = Get-PrimaryViewport
    if (-not $Width)  { $Width  = $auto[0] }
    if (-not $Height) { $Height = $auto[1] }
    # --window-size is in CSS pixels. On a display running above 100% scaling the
    # browser fits proportionally fewer of them than the panel has physical
    # pixels, so on a scaled screen measure the real window and pass it.
    Write-Verbose "viewport ${Width}x${Height} (auto-detected primary display)"
}

if (-not $Browser) {
    $Browser = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Browser) { throw 'no Chromium-based browser found' }

$html = Get-Content -LiteralPath $Path -Raw
$probe = @'
<script>
(function(){
  var d = document.documentElement;
  // widest element that overflows horizontally, if any - a single wide child
  // will produce a scrollbar and is worth naming rather than hunting for.
  var over = '';
  document.querySelectorAll('*').forEach(function(el){
    if (el.getBoundingClientRect().right > d.clientWidth + 1 && !over) {
      over = el.className || el.tagName;
    }
  });
  document.title = 'FIT|' + d.scrollHeight + '|' + d.clientHeight + '|' +
                   d.scrollWidth + '|' + d.clientWidth + '|' + over;
})();
</script>
'@
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("fit_" + [guid]::NewGuid().ToString('N') + '.html')
Set-Content -LiteralPath $tmp -Value ($html -replace '(?i)</body>', "$probe</body>") -Encoding UTF8

try {
    $uri = 'file:///' + ($tmp -replace '\\','/')
    $dom = & $Browser --headless=new --disable-gpu --hide-scrollbars `
                      "--window-size=$Width,$Height" --virtual-time-budget=4000 `
                      --dump-dom $uri 2>$null | Out-String

    if ($dom -notmatch '<title>FIT\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|([^<]*)</title>') {
        throw 'probe did not report - page may have failed to load'
    }
    $r = [pscustomobject]@{
        DocHeight   = [int]$matches[1]
        ViewHeight  = [int]$matches[2]
        DocWidth    = [int]$matches[3]
        ViewWidth   = [int]$matches[4]
        OverflowsX  = $matches[5]
        Fits        = ([int]$matches[1] -le [int]$matches[2])
        OverflowPx  = [Math]::Max(0, [int]$matches[1] - [int]$matches[2])
    }

    if ($Screenshot) {
        if (-not $ShotPath) { $ShotPath = [IO.Path]::ChangeExtension($tmp, '.png') }
        & $Browser --headless=new --disable-gpu --hide-scrollbars `
                   "--window-size=$Width,$Height" --virtual-time-budget=4000 `
                   "--screenshot=$ShotPath" ('file:///' + ($Path -replace '\\','/')) 2>$null | Out-Null
        $r | Add-Member -NotePropertyName Shot -NotePropertyValue $ShotPath
    }
    return $r
}
finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
