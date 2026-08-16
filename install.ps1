# install.ps1 -- link the cyberwise skill family into Claude Code.
#
#     .\install.ps1              # link all of them
#     .\install.ps1 -Remove      # unlink
#
# Each skill is SYMLINKED (or junctioned) rather than copied, so editing this
# repo takes effect immediately with no reinstall step and no second copy to
# drift out of sync.
#
# The family is split so that reading about keybinds costs nothing when the
# question is about textures. `cyberwise` is the front door and carries the
# method rules that apply to every task; the rest are topic skills.

[CmdletBinding()]
param(
    [string] $ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),
    [switch] $Remove
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'skills'

$skillsDir = Join-Path $ClaudeHome 'skills'
if (-not (Test-Path -LiteralPath $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }

foreach ($skill in (Get-ChildItem -LiteralPath $src -Directory | Sort-Object Name)) {
    $link   = Join-Path $skillsDir $skill.Name
    $target = $skill.FullName

    if ($Remove) {
        if (Test-Path -LiteralPath $link) {
            $item = Get-Item -LiteralPath $link -Force
            if (-not $item.LinkType) { Write-Warning "$($skill.Name) is a real directory, not a link - leaving it"; continue }
            # Remove-Item on a junction deletes the link, not the target - but be
            # explicit about it, because getting this wrong deletes the repo.
            [IO.Directory]::Delete($link, $false)
            Write-Host "unlinked $($skill.Name)" -ForegroundColor DarkGray
        }
        continue
    }

    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.LinkType) {
            Write-Host "already linked: $($skill.Name)" -ForegroundColor DarkGray
        } else {
            Write-Warning "$link exists and is a real directory, not a link. Move it aside first."
        }
        continue
    }

    try {
        New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
        Write-Host "symlinked $($skill.Name)" -ForegroundColor Green
    } catch {
        # A symlink needs Developer Mode or an elevated shell; a directory
        # junction needs neither and behaves identically for this purpose.
        cmd /c mklink /J "$link" "$target" | Out-Null
        if (-not (Test-Path -LiteralPath $link)) { throw "could not link $link -> $target" }
        Write-Host "junctioned $($skill.Name)" -ForegroundColor Green
    }
}

if (-not $Remove) {
    Write-Host ''
    Write-Host 'Open /hooks once, or restart, so Claude Code picks up the new skills.' -ForegroundColor Yellow
}
