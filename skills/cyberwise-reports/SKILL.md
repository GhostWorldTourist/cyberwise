---
name: cyberwise-reports
description: Generate deliverables about a modded Cyberpunk 2077 install - a system profile that says what is likely wrong, a full mod-list inventory with descriptions, and the house style plus headless verification for any HTML or Discord-markdown report. Use when someone reports a problem with no detail, when asked what mods are installed, or when generating any page or report for a user to read.
---

# Cyberwise: reports and deliverables

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** The profiler reads framework versions and log states; re-check those paths. Nothing in the report design depends on a game patch.

Load `cyberwise` alongside this for the method rules.

## Start here when the report is "it's broken"

```powershell
tools\New-SystemProfile.ps1 -GameRoot '<path>'
```

Writes Discord-pasteable markdown and an HTML report, led by a **flags** section
naming what is likely to be the problem. Only fields that change a diagnosis are
collected - VRAM against total texture volume, pagefile, drive type, framework
versions, load-order health, whether redscript last compiled. Motherboard model
explains nothing about a mod, so it is not there.

Every flag names the symptom **and** the reason, and carries the items it
counted: a flag saying "60 archives are unlisted" is unactionable until you know
which 60, and **seeing the list is also how a wrong flag gets caught.**

## Inventory the mod list

```powershell
tools\New-ModManifest.ps1 -StagingRoot '<manager staging root>' -NexusApiKey <key>
```

**It reads a manager's staging root, not the game directory.** A Vortex-style
staging root is auto-detected; anything else needs `-StagingRoot` pointed at it
(for MO2, its `mods\` folder). A fully manual install has no staging tree, so the
tool has nothing to walk.

Most of it works offline because a manager that installed from Nexus encodes
`<Display Name>-<NexusID>-<version>-<timestamp>` into the folder name, which
yields the name, a working URL and the install date with no credentials. That
naming is Vortex's; MO2 folder names are user-editable, so expect name-only for
renamed folders. `-NexusApiKey` adds summaries, author, category and the real
adult-content flag, cached so re-runs are free. `-HideNSFW` omits adult mods.

**`-NoNexus` guarantees no network call.** A key stored in Credential Manager is
picked up automatically, so without this switch "I did not pass a key" is not the
same as "it stayed offline". Use it for a quick inventory, on a metered or
offline connection, or any time reaching a third-party API is not something the
user asked for.

Two things before trusting the NSFW filter, both measured on one 846-mod install:

- **Without an API key it is a name heuristic and it under-detects.** It caught
  17 there. Adult mods with innocuous names sail past.
- **Flags propagate across a shared Nexus ID**, because one page carries one flag
  but ships many differently-named files. That alone caught 7 of those 17.

**The output is the user's actual mod list. Treat it as personal:** write it
outside any repo and never commit it.

## Any generated page: measure it, do not eyeball it

**Get the viewport from the user, not from the screen.**

```powershell
tools\Show-ViewportProbe.ps1        # they size a window; it reports its own viewport
tools\Measure-PageFit.ps1 -Path page.html -Width <w> -Height <h> -Screenshot -ShotPath shot.png
```

Detecting the display assumes maximised on the primary at 100% zoom, and cannot
express "the little side panel" or "half-width on monitor 2" at all. Ask.

Then **say what that viewport implies** rather than silently designing to it: on
a small one, agree what earns the top of the page and accept scrolling for the
rest; on a TV, scale the type up hard. An unreadable page that fits is not a win.

And **look at the output, not just the number** - pass `-Screenshot` and read the
image. Two failure modes a screenshot cannot show you, and one a number cannot:

- **An element pushed clean off the page.** A long inline label with
  `white-space:nowrap` forced its row wider than its container and shoved a
  keycap past the right edge - not clipped, not squeezed, *absent*.
- **A layout that "fits" because the flag was ignored.** In PowerShell,
  `--window-size=$W,$H` unquoted parses as an **array**, so the browser silently
  renders at its 800x600 default. Quote it.
- **`DocHeight == ViewHeight` does not mean the page fills the window.**
  `scrollHeight` has the viewport as its floor. Re-measure against a short window
  for the true content height.

House style - palette, one type base, flex over CSS multi-column, Discord's lack
of table rendering and its 2000-character cap: `references/report-design.md`.

## Tools

| tool | does |
|---|---|
| `tools/New-SystemProfile.ps1` | machine + install facts that change a diagnosis, flags first |
| `tools/New-ModManifest.ps1` | inventory of an installed load order, with descriptions |
| `tools/ModManifestHtml.ps1` | HTML renderer for the manifest (dot-sourced) |
| `tools/NexusCredential.ps1` | Nexus API key in Windows Credential Manager |
| `tools/Show-ViewportProbe.ps1` | asks the user's own browser window how big it is |
| `tools/Measure-PageFit.ps1` | does a generated page fit a given viewport |

**Pass the paths explicitly.** These carry defaults for a game root, a staging
root and a viewport. A default that happens to exist on the wrong machine is
worse than an error, because the output looks plausible.

## Reference material

| file | covers |
|---|---|
| `references/report-design.md` | palette, layout, Discord constraints, verifying headless |
