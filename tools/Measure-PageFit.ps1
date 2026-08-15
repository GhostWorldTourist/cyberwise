# Measure-PageFit.ps1 -- does a page fit a given viewport without scrolling?
#
#     .\Measure-PageFit.ps1 -Path page.html -Width 3057 -Height 1550
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
    [int] $Width  = 3057,
    [int] $Height = 1550,
    [string] $Browser,
    [switch] $Screenshot,
    [string] $ShotPath
)

# NOTE: --window-size takes a comma-separated pair, and PowerShell parses a bare
# `--window-size=$W,$H` as an ARRAY - passing two separate arguments, so the flag
# is silently ignored and the browser reports its 800x600 default. Quote it.

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
