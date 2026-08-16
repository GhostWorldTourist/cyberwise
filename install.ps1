# install.ps1 -- link the cyberwise skill family into Claude Code and Codex.
#
#     .\install.ps1                  # link all of them into both agents
#     .\install.ps1 -Remove          # unlink from both
#     .\install.ps1 -ClaudeOnly      # skip Codex
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
    [switch] $Remove
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'skills'

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
                # Remove-Item on a junction deletes the LINK, not the target - but
                # be explicit about it, because getting this wrong deletes the repo.
                [IO.Directory]::Delete($link, $false)
                Write-Host "  unlinked $($skill.Name)" -ForegroundColor DarkGray
            }
            continue
        }

        if (Test-Path -LiteralPath $link) {
            $item = Get-Item -LiteralPath $link -Force
            if ($item.LinkType) {
                Write-Host "  already linked: $($skill.Name)" -ForegroundColor DarkGray
            } else {
                Write-Warning "  $link exists and is a real directory, not a link. Move it aside first."
            }
            continue
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
    Write-Host ''
    Write-Host 'Claude Code: open /hooks once, or restart, so it picks up the new skills.' -ForegroundColor Yellow
    Write-Host 'Codex: restart it so it refreshes its global skill catalog.' -ForegroundColor Yellow
}
