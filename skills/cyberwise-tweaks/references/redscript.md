# Redscript authoring

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Signatures and script paths move between versions. Re-read the shipped script dump rather than trusting a remembered signature.

Writing `.reds` that changes world state, rather than authoring records
(`tweakdb-and-text.md`) or running console commands (`cet-lua.md`).

## The game ships its own API reference - read it

```
<game>\tools\redmod\scripts\
```

The vanilla script dump is **authoritative**: real signatures, real access
modifiers, the actual set of methods on a native class. Guessing a signature and
compiling until it sticks is slower and produces code that breaks on the next
patch for reasons nobody wrote down.

Read the file for the class you are touching before writing against it. For a
door, that is
`cyberpunk\devices\door\doorController.script` - which is how you learn there are
nine `ActionQuestForce*` verbs rather than the two everybody copies.

**Copy a pattern from a mod that already does it.** If something in the load
order already manipulates the thing you are about to manipulate, its approach is
proven against this game version in this environment. That is worth more than a
tidier design you invented.

## You cannot hook another mod's redscript class from a standalone mod

This is the finding that decides how every "fix somebody else's mod" job gets
done, so establish it before designing anything.

`@wrapMethod` / `@replaceMethod` work against **game** classes. Against a class
that another *mod* declares, they fail to compile. On one install this was tested
three ways - wildcard import, fully-qualified target, explicit single import -
and all three failed. The one apparent precedent in that load order, a mod
wrapping another mod's controller, turned out to be **inside a `/* */` block**:
its author had hit the same wall and commented it out rather than delete it.

So the clean, polite option - a small mod that hooks their behaviour without
touching their files - **is not available** for mod-declared classes. That is why
patching their file, or overriding it wholesale, is the choice on the table at
all. Do not spend an evening trying to make a hook compile before checking
whether the target class belongs to the game or to a mod.

**Check before promising.** If the class is declared in another mod's `.reds`,
say so early and move to the real options rather than discovering it three
compile failures later.

## Addressing a specific world object

`EntityID.GetHash()` returns a **Uint32** and cannot identify an object uniquely.
Comparing hashes will eventually match the wrong thing. Address through a
**PersistentID built from the full 64-bit hash** plus the component name:

```reds
let pid = CreatePersistentID(EntityID.FromHash(<64-bit hash>), n"controller");
let obj = persistency.GetConstAccessToPSObject(pid, n"DoorControllerPS") as DoorControllerPS;
persistency.QueuePSEvent(pid, n"DoorControllerPS", obj.ActionQuestForceCloseImmediate());
persistency.QueuePSEvent(pid, n"DoorControllerPS", obj.ActionQuestForceSeal());
```

**Measure the identifiers, do not guess them.** Class, entity ID, persistent-state
class and component name are all readable in game with a CET probe - see
`cet-lua.md`. An entity ID invented from a plausible name addresses nothing, and
the failure is silent.

**Order matters and the failure looks like success.** Sealing a door without
closing it first leaves it standing open and merely un-interactable: no error, no
log line, and a screenshot that looks broken rather than locked.

## Only ever undo your own change

State-changing mods must be able to tell *their* change from the game's. Track it
in a **mod-owned fact**:

```reds
// set your own fact when you act, and only revert while it is set
```

Without that, a revert eventually unseals a door the game deliberately closed, or
re-enables something a quest disabled - and the resulting bug appears long after,
in content that has nothing to do with the mod.

Gate on quest facts so the change applies only in the window it belongs to, and
add a listener on the fact that ends that window so the mod stands down by
itself. In a game where the gate conditions are false, the mod should **no-op
entirely** rather than assume its own state.

## Verify before shipping

Compile-test against the real load order rather than in isolation - the
compile-test recipe is in the `cyberwise` skill's `environment.md`. `scc` exit 0
means it compiles, **not** that it works: say which of the two you have actually
established when handing a mod over.
