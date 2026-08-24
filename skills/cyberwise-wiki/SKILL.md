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
| **base** | `wiki/` INSIDE this skill | yes | game, engine and format knowledge; cross-mod interaction PATTERNS |
| **user** | `<records>\wiki\` beside the game's own data | **never** | anything about a specific mod: its settings, how it works, its description - and the profile of the machine it all runs on |

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

### What a user bundle contains

Not just mods. **Every user bundle should hold these two**, and a bundle missing
either is a bundle that makes the next session start by guessing:

| path | what it is | built by |
|---|---|---|
| `machine.md` | this machine and this install: hardware, OS, frameworks, payload, and what the numbers rule in and out | `cyberwise-reports/tools/New-SystemProfile.ps1 -Wiki` |
| `mods/*.md` | one article per deployed mod | `cyberwise-modbase/tools/New-ModStubs.ps1` |

**Create the machine profile early - before the first diagnosis, not after the
third.** Without it, every session either asks the user to read numbers off a
screen or reasons about hardware it has never measured, and a wrong capacity does
not look wrong (`/process/a-capacity-read-from-the-wrong-api`). It is user-only
for the ordinary reason: it describes one person's machine, and the base bundle
ships.

**`machine.md` is regenerated whole; a mod article is not.** That difference is
deliberate and worth holding onto. Every line of the machine profile is measured,
so a merge would be half measurement and half memory with nothing marking which -
the generator overwrites, and the file says so in its own header. A mod article
starts as a stub and gets *deepened by hand*, so `New-ModStubs.ps1` skips one
that already exists and needs `-Force` to flatten it. Same bundle, opposite
rules, because one file has an author and the other has a measurement.

## The lifecycle, on a fresh install

The base bundle arrives with the skills, so game knowledge is there from the
first minute. The user bundle does not exist until somebody makes it, and until
it does **every session re-derives the same facts** - which mods are deployed,
what the hardware is, what was already worked out here. That is the cost this
whole thing exists to remove, so building it is the first job, not a later one.

```powershell
tools\Initialize-UserWiki.ps1 -GameRoot '<path>'
```

That creates `index.md` and `log.md`, generates `machine.md`, and writes one
honest stub per **deployed** mod. It is idempotent: run it again after adding
mods and it fills in what is new without flattening anything deepened by hand.
It refuses to write into the shipping bundle, checked two ways - by path, and by
reading the target's own `index.md` for a marker - because a path check alone
misses a copy of the base bundle sitting somewhere else.

Then deepen, in the order `cyberwise-modbase` gives: frameworks, settings-bearing
mods, anything already implicated in a finding, anything hooking a shared system,
everything else. **Stopping at stubs is a legitimate resting point** - a stub
that says where a mod lives and what it deploys is worth having, and a stub that
guesses what a mod does is worse than nothing, because it reads exactly like an
article somebody verified.

## Conformance and quality are different questions

`Test-Wiki.ps1` answers both, and keeps them apart:

- **Conformance** (`-Base` optional) decides the exit code. It checks the small
  mandatory core plus the distribution boundary. It is deliberately forgiving,
  because the spec says a consumer **must not** reject a bundle for a missing
  optional field, an unknown type, an extra key or a broken link.
- **Lint** (`-Lint`) reports quality and never affects the exit code. Stubs
  still outstanding, an article marked `stable` whose body is too short to have
  read anything, a missing `description`, a body claiming verification while its
  status disclaims it, links to articles nobody has written, duplicate titles,
  and an index that has drifted from the files beside it.

The split matters. A bundle mid-documentation is *supposed* to be full of drafts
and unwritten links; failing it for that would make the validator useless
exactly when the work is happening. But a bundle nobody lints slowly fills with
articles that parse and say nothing, and by then the drift is invisible.

**`index-drift` is the one to act on first.** An index that overstates coverage
is how a documentation effort quietly stops being trusted - everything else on
the list is a gap you can see, and that one is a gap that lies.

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
| `tools/Initialize-UserWiki.ps1` | create this user's bundle from nothing - frame, machine profile, one stub per deployed mod. Idempotent; refuses to touch the shipping bundle |
| `tools/Test-Wiki.ps1` | OKF 0.2 conformance, `-Base` to enforce that nothing user-only has leaked into the shipping bundle, `-Lint` for quality warnings that never fail the build |

The base bundle lives inside this skill, at `skills/cyberwise-wiki/wiki/`, and
that is deliberate. Skills install as whole-directory symlinks, so a bundle
kept beside them installs itself and can never drift out of sync with the skill
that documents it. It previously sat at the repo root, where `install.ps1`
linked only `skills/*` and the entire bundle was therefore unreachable from an
installed copy - every pointer resolved only in a repo checkout.

Run the base check before any commit that touches the bundle:

```powershell
tools\Test-Wiki.ps1 -Bundle .\wiki -Base          # from skills\cyberwise-wiki\
tools\Test-Wiki.ps1 -Bundle .\wiki -Base -Lint    # and the quality report
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
