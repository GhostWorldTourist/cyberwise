---
name: cyberwise-handover
description: Write the morning handover after a long unattended run on a modded Cyberpunk 2077 install - hours of work, often several tasks at once, for someone who was not watching. Use when signing off from a long session, when asked what got done overnight or across a batch of work, or when a run produced more findings than a terminal can carry. Produces one scannable page - a scoreboard, status-labelled sections, verified-versus-inferred claims, the mistakes made along the way, and a short list of what cannot move without them.
---

# Cyberwise: the handover

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** nothing here reads game data, so a patch cannot
> break it. Re-check if the report palette in `cyberwise-reports` changes, since
> this shares it.

Load `cyberwise` alongside this for the method rules.

## The problem

A long unattended run ends with hundreds of tool calls in scrollback. They come
back to a wall. They cannot tell what shipped, what broke, what is waiting on
them, or which of the confident sentences were actually checked. Everything you
found is technically present and practically lost.

One page fixes it. Not a summary - a **handover**.

## Answer five questions, in this order

1. **What is the shape of the night?** Counts, before any prose.
2. **What is finished?** With the evidence that it is.
3. **What did you get wrong?**
4. **What needs them?** The short list nothing can proceed without.
5. **What is still open but not blocking?**

If a section serves none of those five, cut it. A handover is not a diary.

## Re-verify before you write. This is a gate, not advice.

**Every time-sensitive claim gets re-checked immediately before it goes in the
report** - not reused from when you found it.

On a machine the user is also touching, state changes underneath you. A 2026-08-30
handover shipped four stale claims in one page: a package described as needing
installation that was already installed, diagnostic files described as safe to
delete that were already deleted, a mod reported undeployed that was deployed and
working, and a compat mod called "built but not deployed" that was live in the
compile log. Every one had been true when checked, hours earlier.

**The "what needs you" section is the most damaging place to be stale**, because
it is the list they act on. Re-run every check behind it. If a reading really is
point-in-time, timestamp it - "as of 23:40" - rather than writing an undated
present tense.

## Structure

**Lead with the scoreboard.** A strip of big numbers across the top: packages
shipped, commits, tests green, findings, sites mapped. Someone with thirty
seconds should get the shape from that strip alone.

**Give it a nav that jumps to the sections.** Long pages are scanned, not read.

**Label every section with its state**, as a chip, so it reads at a glance:

| chip | means |
|---|---|
| `SHIPPED` | done, and here is the evidence |
| `ANSWERED` | a question was asked; this is the answer |
| `NEEDS A DECISION` | you did the work, the choice is theirs |
| `NEEDS YOU` | blocked on something only they can do |
| `OPEN` | known, not blocking, not forgotten |

Five words. Do not invent synonyms - `FIXED`, `PARTLY SHIPPED` and `CORRECTED`
are the same three states wearing new clothes, and a vocabulary that grows stops
being scannable.

**Number sections to match their list if they gave one.** That numbering carries
real information - it tells them their eighth request was not dropped. Do not
number a set that has no order; decorative `01 / 02 / 03` is noise.

**Separate done from needs-you ruthlessly**, and end with a dedicated open
section. Nothing else on the page is worth as much.

## Evidence discipline

**Say what was tested and what was reasoned.** "Compile-tested, exit 0" and
"should work" are different claims and must look different on the page.

**State the bounds of a finding.** A sector scan that only saw 77 of 140 sectors
did not clear the other 63 - say so, in the section, not in a footnote.

**Name things they can act on.** A filename they cannot resolve is not a finding;
resolve it to the mod. An identifier with no lookup path is a chore you handed
back. See the front door's rules on this.

**Report your own errors, in the report.** If you were wrong during the run, the
handover says so plainly and says what the truth was. A page that lists only wins
is a page they have to independently verify, which defeats it. This is also the
cheapest possible way to make the rest credible.

## Write it as a page

Terminal scrollback is the thing you are rescuing them from, so do not deliver
the rescue in scrollback. Publish it, hand over the link, keep the terminal reply
to the two or three headlines and the link.

`templates/handover.html` is the reference. It uses the same palette as
`cyberwise-reports` so a night's output looks like the rest of the family:
`#fcee0a` yellow, `#00f0ff` cyan, `#ff003c` red on `#07070a`, mono headings with
the chromatic-aberration shadow, a faint grid ground. Single dark theme by
choice - it matches the subject and every other page this family produces.

Wide content - tables, log excerpts, path lists - goes in its own
`overflow-x:auto` container so the page body never scrolls sideways.

## Before you hand it over

- Every number in the scoreboard traceable to something you actually ran
- Every "needs you" item re-checked in the last few minutes
- Your own mistakes present
- Every filename resolved to a mod name
- Caveats sitting with their findings, not collected at the bottom
- Nothing claimed as verified that was reasoned

## Anti-patterns

**A wall of prose with no scoreboard.** They cannot triage it.

**Burying a blocker in a paragraph.** If it needs them, it goes in the open list,
even if you also discuss it above.

**Only good news.** Unbelievable, and it makes the true parts unbelievable too.

**A finding with no action.** "TweakXL logged 181 errors" is half a sentence.
Whose mod, what breaks, what to do.

**Padding the count.** Five real findings beat five real findings and nine
observations.

## Related

- `cyberwise-reports` - the palette, and the other pages this family builds
- `cyberwise-feedback` - when a finding belongs to a mod author instead
