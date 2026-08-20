---
name: cyberwise-sitebuilder
description: Turn a folder of character documents, mod reports and notes into a website - plain HTML, CSS and JS with no build step, no runtime and no account, deployable by copying a folder. Use when someone wants to publish or share their V's backstory, character records or install documentation as a web page rather than a Markdown file.
---

# Cyberwise: sitebuilder

> **Verified:** 2026-08-20
> **Re-check after a patch:** nothing here depends on a game patch. Re-check when
> the character document layout changes.

Somebody has written their V. It is sitting in a `.md` file that nobody will ever
read, because *"read this Markdown file"* is a thing you can only ask of other
developers. This turns the folder into a website.

```powershell
tools\New-CharacterSite.ps1 -From <characters folder> -Out <site folder> -Open
```

That is the whole interface. The output folder is the site: copy it to a web
host, a USB stick or a Discord upload, or double-click `index.html`.

## What it must never do: flatten the documents

**This is the rule the tool exists to serve.** Character documents are not four
copies of one form. On the install this was built against, one V is a classified
Arasaka personnel dossier, one is a monologue spoken to a dying man, one is a
journalist's interview by a campfire, one is a transcript of an AI being
interrogated about its own records. **The format is the characterisation.**

So it renders each document as written and styles around it. It does not extract
fields into a template - a template would make all four the same shape, which is
the one outcome that would make the site worse than the files.

Two places this shows up concretely, both of which have tests:

- **A field block keeps its lines.** Markdown says consecutive lines are one
  paragraph, which is right for prose that hard-wraps and catastrophic for
  `SUBJECT:` / `CODENAME:` / `AKAS:`, where each line is a field. A colon-
  terminated run of capitals keeps its own line; wrapped prose does not.
- **A nested list nests.** The indentation in a dossier is structure, not
  decoration.

## Why there is no dependency

The audience is somebody with no technical patience. Every dependency is a place
they stop: a runtime to install, a package manager to learn, an account to make.
So the whole thing is PowerShell, which is already on the machine, and the output
is plain HTML, one stylesheet and one small script.

**The site must work from `file://`.** Nothing fetches - the browser blocks it
from a filesystem origin - so every page is complete when written, and nothing is
loaded from another host. That is also what makes it private by default: no
tracking, no fonts phoning home, no CDN.

## The layout it reads

Every subfolder of `-From` is a character:

```
characters\valkyrie\Profile - Valkyrie.md    the document (required)
characters\valkyrie\Meta - Valkyrie.md       optional second section
characters\valkyrie\media\*.jpg|png|webp     optional images
```

Anything else in the folder is ignored, so presets, backups and working notes can
live beside the document without being published. A folder whose name starts with
`_` is a draft and is skipped unless `-IncludeDrafts` is passed.

`Profile*.md` is the convention, but a folder holding exactly one Markdown file
works without it - a convention nobody was told about is a trap.

## Media is optional, and its absence must not look broken

The prototype was built for somebody who had **no images at all**, which is the
normal starting state. A character with no media gets a nameplate tile, not an
empty frame where a photograph should be. When images do arrive, drop them in
`media\` and rebuild.

A note from that first build: every character was called V-something, so the
first-letter monogram drew the same glyph on all four cards. Until there are
photographs the **name** is the artwork.

## Tools

| tool | does |
|---|---|
| `tools/New-CharacterSite.ps1` | the whole site: index, one page per character, CSS, JS |
| `tools/ConvertFrom-Markdown.ps1` | the Markdown subset these documents use (dot-sourced) |

## Not built yet

- **Media galleries beyond a simple grid.** `cyberwise-media` does not exist.
- **Other sections** - a mod list from `cyberwise-reports`, a hotkey sheet from
  `cyberwise-hotkeys`. Both already render HTML; the work is a shared shell, not
  new rendering.
- **A per-character accent chosen by the author.** Accents currently cycle
  through a fixed palette. Editing `site.css` retunes the whole set.
