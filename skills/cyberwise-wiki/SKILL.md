---
name: cyberwise-wiki
description: Store what you learn about this game and this install as an OKF knowledge bundle instead of burying it in a skill file - the article format, the two bundles and why one never ships, and the validator that enforces the boundary. Use before writing anything down that a later session would want to look up, and whenever a skill file is growing a section that is really reference material.
---

# Cyberwise: the wiki

> **Verified:** OKF 0.2, and Cyberpunk 2077 patch 2.31 - August 2026

Load `cyberwise` alongside this for the method rules.

A skill file is instructions. A wiki article is knowledge. Those are different
things and they rot at different rates, which is why they belong in different
places. When a `SKILL.md` grows a section explaining how the appearance system
stores an index, or what an `.xl` can declare, that section has stopped being
guidance and become reference - and it will be read once a year by somebody who
needed it in the first thirty seconds.

Knowledge goes in a bundle. The skill keeps a pointer.

## Two bundles, and only one of them ships

| bundle | lives | ships | holds |
|---|---|---|---|
| **base** | `wiki/` in this repo | yes | game, engine and format knowledge; cross-mod interaction PATTERNS |
| **user** | `<records>\wiki\` beside the game's own data | **never** | anything about a specific mod: its settings, how it works, its description |

**The user bundle must never be redistributed.** Its content is derived from mod
authors' own descriptions, config files and mod pages. Publishing a compiled
version of that is harvesting somebody else's work and passing it on, whatever
the intent was. Nothing can stop a person uploading their own bundle somewhere -
but nothing in this family will help them, and nothing here will produce one
already packaged for it.

**Location is the boundary, not a field.** A field gets forgotten; a path does
not. `Test-Wiki.ps1 -Base` turns it into a check that fails.

The line runs between a pattern and a product:

- **Base, ships.** "A loot mod that enumerates every `Clothing_Record` will pick
  up abstract `$base` templates, because templates are valid records that carry
  no `displayName`." That is a fact about the game's data model. It may name a
  mod as an *example*.
- **User, never ships.** "Threadscape's blacklist file is at this path, its
  settings mean this, and here is what its author wrote about it." That is the
  author's work restated.

### What is already in the base bundle

Read the bundle's own `index.md` for the current list; these are its areas and
what each is for.

| area | holds |
|---|---|
| `/patterns` | facts about the data model that surface as mod conflicts |
| `/engine` | how the game and its script layers behave, independent of any mod |
| `/install` | what each way of assembling an install makes untrue about the files on disk |
| `/process` | how to do the work so the result survives review - partitioning a documentation pass, verifying derived identifiers, saying what you did not check |

`/process` is the odd one: it is not knowledge about the game but about the ways
work *about* the game goes wrong. It is here because a lesson that lives only in
a conversation has to be learned again by every fresh session.

## The article format

OKF 0.2: a directory of markdown files with YAML frontmatter, no schema
registry, no required tooling. `index.md` and `log.md` are reserved names; every
other `.md` is a concept, and its ID is its bundle path minus the extension.

```markdown
---
type: Game Mechanic
title: Appearance is stored by index, not by name
description: One sentence, because this is what a reader sees before opening it.
tags: [appearance, presets, ccxl]
status: stable
sources:
  - id: acu-preset
    resource: /formats/acu-preset
generated: { by: "claude", at: "2026-08-23T14:02:00-04:00" }
---
```

`type` is the only always-mandatory key. Everything else is optional, and a
consumer **must not reject** an article for a missing optional field, an unknown
type, an extra key, a broken link or an absent index - broken links "may simply
represent not-yet-written knowledge", which is the point of writing links before
articles.

Four things worth getting right because they are silent when wrong:

- **Timestamps carry an explicit UTC offset.** `2026-08-23T14:02:00-04:00`, not
  a bare local time. Half the crash reasoning in this family once went wrong on
  exactly this.
- **Footnotes key to `sources[].id`, never to position.** A positional index
  misattributes silently the moment somebody reorders the list.
- **`log.md` is newest-first**, ISO `YYYY-MM-DD` headings. It is the thing that
  makes a bundle reviewable a month later, so write the *why*, not the diff.
- **Only a ROOT `index.md` may carry frontmatter**, and only `okf_version`.

## Tools

| tool | what it does |
|---|---|
| `tools/Test-Wiki.ps1` | OKF 0.2 conformance, plus `-Base` to enforce that nothing user-only has leaked into the shipping bundle |

Run the base check before any commit that touches `wiki/`:

```powershell
tools\Test-Wiki.ps1 -Bundle .\wiki -Base
```

## Writing an article that is worth having

The failure mode is a page that restates what anyone could see. Every article
here should answer something that cost somebody time.

- **Lead with the finding, not the background.** The reader arrived because
  something is broken.
- **Quote the artefact.** A three-line code fence from the actual `.reds` or
  `.yaml` outranks a paragraph describing it, and it lets the next reader check
  you.
- **Record what was ruled out and why.** Half the value of a hard diagnosis is
  the four wrong roads nobody needs to walk again.
- **Say what you did not verify.** `status: draft` and a plain sentence beats a
  confident article that turns out to be wrong - a note that is false is worse
  than no note.
