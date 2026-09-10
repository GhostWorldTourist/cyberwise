---
type: Game Canon
title: The corpo prologue is an assassination and a firing, and V and Jackie are already friends
description: What the corpo intro actually puts on screen - the employee ID on the bathroom mirror, Jenkins' failed hit on Abernathy, the call to Jackie, Lizzie's Bar as the moment V loses the job rather than the moment they meet, and the fullDisplayName records that give every named prologue NPC a first and last name.
tags: [canon, lifepath, corpo, prologue, arasaka, jackie]
status: stable
generated: { by: "claude", at: "2026-08-24T20:05:00-04:00" }
---

# The corpo prologue is an assassination and a firing, and V and Jackie are already friends

**Almost every wrong retelling of this prologue makes the same two mistakes:** it
treats Lizzie's Bar as where V and Jackie *meet*, and it treats the corpo
firing as a consequence of V's own failure. Both are backwards. The friendship
predates the prologue, and what strips V of the job is a counterintelligence
purge following somebody else's failed assassination.

Everything below is on screen during the intro. Read it there before repeating
anything from anywhere else - see
[Where lifepath canon actually lives](/canon/where-lifepath-canon-lives).

## The sequence, in order

1. **The bathroom.** V's HUD readout in the Arasaka Tower bathroom mirror shows
   the corporate employee record, including the ID.
2. **The call to Jackie**, made from that bathroom, before the meeting with
   Jenkins. They talk like people who already know each other well, because they
   do.
3. **Jenkins' meeting** and the operation against Abernathy - an attempted
   assassination, which **fails**.
4. **The counterintelligence purge** that follows the failed hit. This is the
   mechanism that ends V's career. It is not a performance review.
5. **Lizzie's Bar.** Jenkins' entourage strips V's corporate status and intends
   to kill them. Jackie intervenes and offers V a place alongside him and Mamá
   Welles.
6. **The timeskip.** Its length is not stated - see
   [What the game does not settle](/canon/what-the-game-does-not-settle).

## NC770416 is the game's, not an author's invention

```
NC770416
```

That is corpo V's Arasaka employee ID, displayed on the mirror HUD readout during
the prologue. It belongs to the **slot**, not to the character: every corpo V
carries it regardless of name, gender, look or any player choice, because the
scene is authored once.

**This was confabulated in the other direction and corrected.** Presented with
the number, the assistant assumed it was something a player had invented for
their own V and treated it as fan detail. It is on screen. The lesson generalises:
a suspiciously specific-looking identifier is as likely to be a thing CDPR
authored as a thing a player made up, and the intro sequence is thirty seconds
away from answering which.

Two consequences worth stating plainly, because both come up:

- **Two different players' corpo Vs share this ID.** It is not a personal
  identifier and cannot be used as one in a document that has to distinguish two
  characters.
- **A character document that invents a different Arasaka employee number is
  contradicting a visible on-screen fact**, which is a fine thing to do
  deliberately and an embarrassing thing to do by accident.

## The prologue cast has full names, and the game ships them

**Every named prologue NPC carries a `fullDisplayName` in the game's own
localization.** Read it there. It is one lookup, it is authoritative, and it
settles first names that community sources argue about.

```
archive\pc\content\lang_en_text.archive
  -> base\localization\en-us\onscreens\onscreens_final.json
     Story-base-gameplay-static_data-database-characters-npcs-records-quest-quests-q000-
       q000_corpo_<who>_displayName       # what the nameplate shows
       q000_corpo_<who>_fullDisplayName   # first AND last name
```

`displayName` is the short label (`Jenkins`, `Carter`, `Arasaka Agent`);
`fullDisplayName` is the full name shown when V targets them. Read as of
patch 2.31:

| record | displayName | fullDisplayName |
|---|---|---|
| `q000_corpo_jenkins` | Jenkins | **Arthur Jenkins** |
| `q000_corpo_abernathy` | Abernathy | **Susan Abernathy** |
| `q000_corpo_assistant` | Carter | **Carter Smith** |
| `q000_corpo_friend` | - | **Frank Nostra** |
| `q000_corpo_arasaka_m_receptionist` | Receptionist | **Stanley Judith** |
| `q000_corpo_coach` | Life Coach | **Brian Gustav** |
| `q000_corpo_netrunner` | Netrunner | **>>Slice543<<** |

**Carter Smith is V's assistant**, and he is the one who brings the late
reports in `q000_corpo_03a_office_chats` - the exchange where V can answer
*"They were supposed to be ready yesterday"* and *"Send them to my inbox. And
you and I will have a word about this later."* **Frank Nostra is a different
NPC** - the peer whose scene is captioned *"V's coworker is glad she's here, he
asks for his input about a work matter"*, which is the Biotechnica-agent
conversation. Community answers to "who is the reports guy" return Frank; that
is the wrong one of the two.

### Proving an NPC speaks a line, rather than inferring it

Matching a line to a character by *role* ("an assistant would bring reports") is
a guess that reads like a finding. The scene files carry the real binding, and
it is four hops:

```
WolvenKit.CLI convert serialize <scene>.scene
  screenplayStore.lines[].speaker.id    -> an actorId
  actors[].actorId.id -> actorName      -> e.g. "assistant"
  actors[].communityParams.entryName    -> the community + entry name
  <community>.community                 -> Character.<record>
  onscreens: <record>_fullDisplayName   -> the name
```

Worked, for the reports exchange: lines 40-45 alternate speaker `13` and the
player actor `19`; actor 13 is `assistant`, acquired from entry `assistant` in
`q000_corpo_com_arasaka_office`; that entry resolves to
`Character.q000_corpo_assistant`; whose `fullDisplayName` is **Carter Smith**.
The Biotechnica conversation is actor `10`, `arasaka_coworker`, a different
actor entirely.

**Do not stop at the subtitle file.** `lang_en_text.archive` gives the dialogue
but carries no speaker tags, so it can tell you a line exists and never who says
it. The `.scene` is the only thing that binds the two.

### This entry previously said the opposite, and was wrong

Until 2026-09-09 this article carried a section headed *"Jenkins and Abernathy:
surnames are canon, first names are not"*, instructing readers to treat any
first name as unverified and declining to name either candidate on the grounds
that naming one "would settle by repetition a thing the game never settled."

**The game settles it.** The `fullDisplayName` records above shipped in the base
game. The reasoning that produced the wrong note was sound in shape - community
sources really do invent first names for minor corporate characters - but it was
applied without opening the file that had the answer, and it hardened a lookup
that takes a minute into a standing refusal to answer. A rule that forbids
answering is far more expensive than a missing note, because it suppresses the
search as well as the answer.

The general lesson, which is why this is written up rather than quietly deleted:
**"the game never established this" is a claim about the game's data, and it
needs the data open before it can be made.** Absence in your memory is not
absence in the archive. Two independent routes agreed here - the localization
records, and a 2026-08-20 session that reached Carter Smith through the Fandom
wiki - but only the first is checkable.

One claim still uncorroborated: that Fandom page also says Carter dislikes
Arasaka's methods and later informs on V. **Nothing in the prologue's own
strings supports either**, so treat both as wiki-sourced until an in-game
readable or line turns up. The name is solid; the characterisation is not.

## What the prologue does NOT establish

The single largest unwritten space in corpo V's life sits right here:

**How V and Jackie became friends is not written anywhere in the game.** They are
simply already close when the prologue opens. No scene, no shard, no line
accounts for it.

That is a gift to a player and a trap for an assistant. The assistant working
from these sessions invented a ten-year friendship with a bar-fight origin,
stated it as background, and had to retract it. If a player wants that, help them
build it - but it is *theirs*, and it should be labelled as theirs in whatever
document it lands in.

## Scope

Read off the corpo intro sequence. The narrative facts do not depend on a game
patch; the `fullDisplayName` table was read out of `lang_en_text.archive` at
**patch 2.31** and should be re-read if CDPR ships another localization pass.
A lifepath-expanding mod can move any of it - if a player's account of the
prologue does not match this, assume a mod before assuming the player is wrong.

**Re-check after a patch:** the `q000_corpo_*_fullDisplayName` rows.
