# install.ps1 -- link the cyberwise skill family into Claude Code and Codex.
#
#     .\install.ps1                  # link all of them into both agents
#     .\install.ps1 -Remove          # unlink from both
#     .\install.ps1 -ClaudeOnly      # skip Codex
#     .\install.ps1 -Relink          # repoint links that belong to another copy
#
# Each skill is SYMLINKED (or junctioned) rather than copied, so editing this
# repo takes effect immediately with no reinstall step and no second copy to
# drift out of sync - and one repo serves both agents rather than two installs
# of the same notes diverging quietly.
#
# The family is split so that reading about keybinds costs nothing when the
# question is about textures. `cyberwise` is the front door and carries the
# method rules that apply to every task; the rest are topic skills.

[CmdletBinding()]
param(
    [string] $ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),
    # Codex honours CODEX_HOME when it is set, otherwise ~/.codex.
    [string] $CodexHome  = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [switch] $ClaudeOnly,
    [switch] $Remove,
    # Repoint a link that already exists but points at a DIFFERENT copy of the
    # family - typically the installer's snapshot under
    # %LOCALAPPDATA%\Programs\Cyberwise\skills. Without this the mismatch is only
    # reported, because silently redirecting somebody's links is not this
    # script's decision to make.
    [switch] $Relink
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'skills'

# Links found pointing at some other copy of the family. Counted rather than
# thrown, because the right answer depends on which copy the user meant to run.
$script:mismatched = 0

function Install-Family {
    param([Parameter(Mandatory)][string] $AgentHome, [Parameter(Mandatory)][string] $Label)

    $skillsDir = Join-Path $AgentHome 'skills'
    if ($Remove -and -not (Test-Path -LiteralPath $skillsDir)) { return }
    if (-not (Test-Path -LiteralPath $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }

    Write-Host "$Label -> $skillsDir" -ForegroundColor Cyan

    foreach ($skill in (Get-ChildItem -LiteralPath $src -Directory | Sort-Object Name)) {
        $link   = Join-Path $skillsDir $skill.Name
        $target = $skill.FullName

        if ($Remove) {
            if (Test-Path -LiteralPath $link) {
                $item = Get-Item -LiteralPath $link -Force
                if (-not $item.LinkType) { Write-Warning "  $($skill.Name) is a real directory, not a link - leaving it"; continue }

                # ONLY REMOVE LINKS THAT POINT AT *THIS* COPY.
                #
                # An installed copy running its own uninstaller used to delete
                # every cyberwise* link by name, which on a machine where someone
                # also has the repo linked for development deleted THEIR links
                # too - silently, as a side effect of uninstalling something
                # else. It happened here, during the first test of the installer.
                #
                # A link pointing somewhere else belongs to another install and
                # is none of our business.
                $actual = try { [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path -Parent $link), [string]@($item.Target)[0])) } catch { $null }
                if ($actual -and $actual -ne [IO.Path]::GetFullPath($target)) {
                    Write-Host "  skipped $($skill.Name) - points at another copy ($actual)" -ForegroundColor DarkGray
                    continue
                }

                # Remove-Item on a junction deletes the LINK, not the target - but
                # be explicit about it, because getting this wrong deletes the repo.
                [IO.Directory]::Delete($link, $false)
                Write-Host "  unlinked $($skill.Name)" -ForegroundColor DarkGray
            }
            continue
        }

        if (Test-Path -LiteralPath $link) {
            $item = Get-Item -LiteralPath $link -Force
            if (-not $item.LinkType) {
                Write-Warning "  $link exists and is a real directory, not a link. Move it aside first."
                continue
            }

            # CHECK WHERE IT POINTS, not merely that it is a link.
            #
            # "already linked" used to be printed for any existing link at all,
            # which made a link pointing at ANOTHER copy of the family read as a
            # healthy install. That is exactly how the installer's static
            # snapshot under %LOCALAPPDATA%\Programs\Cyberwise\skills kept
            # winning on a machine where the repo was also linked: nine of ten
            # skills silently loaded the snapshot, so every edit to the repo was
            # invisible to both agents and re-running this script said everything
            # was fine. A stale link and a good one look identical until you
            # resolve the target.
            $actual = try { [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path -Parent $link), [string]@($item.Target)[0])) } catch { $null }
            if ($actual -and $actual -eq [IO.Path]::GetFullPath($target)) {
                Write-Host "  already linked: $($skill.Name)" -ForegroundColor DarkGray
                continue
            }

            if (-not $Relink) {
                Write-Warning ("  $($skill.Name) points at another copy, so this one is NOT what the agents load:`n" +
                               "      links to: $actual`n" +
                               "      this copy: $target`n" +
                               "      re-run with -Relink to repoint it")
                $script:mismatched++
                continue
            }

            # Delete the LINK, not the target. Remove-Item on a junction has
            # historically been the wrong tool for this; be explicit.
            [IO.Directory]::Delete($link, $false)
            Write-Host "  repointing $($skill.Name) (was $actual)" -ForegroundColor Yellow
        }

        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
            Write-Host "  symlinked $($skill.Name)" -ForegroundColor Green
        } catch {
            # A symlink needs Developer Mode or an elevated shell; a directory
            # junction needs neither and behaves identically for this purpose.
            cmd /c mklink /J "$link" "$target" | Out-Null
            if (-not (Test-Path -LiteralPath $link)) { throw "could not link $link -> $target" }
            Write-Host "  junctioned $($skill.Name)" -ForegroundColor Green
        }
    }
}

Install-Family -AgentHome $ClaudeHome -Label 'Claude Code'

# Skip Codex only when asked, or when it would be the same directory twice.
if (-not $ClaudeOnly -and [IO.Path]::GetFullPath($ClaudeHome) -ne [IO.Path]::GetFullPath($CodexHome)) {
    Install-Family -AgentHome $CodexHome -Label 'Codex'
}

if (-not $Remove) {
    # Loud, and last, so it is the thing still on screen. A mismatch means the
    # agents are reading a different copy than the one just installed - which
    # looks like "my edits do nothing" and gets blamed on the agent.
    if ($script:mismatched) {
        Write-Host ''
        Write-Host ("$($script:mismatched) link(s) point at another copy of the family. Your agents are loading " +
                    "THAT copy, not this one.") -ForegroundColor Red
        Write-Host '  .\install.ps1 -Relink     # repoint them at this copy' -ForegroundColor Red
    }

    Write-Host ''
    Write-Host 'Claude Code: open /hooks once, or restart, so it picks up the new skills.' -ForegroundColor Yellow
    Write-Host 'Codex: restart it so it refreshes its global skill catalog.' -ForegroundColor Yellow
}
