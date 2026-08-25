---
type: Diagnostic Method
title: A bind dialog reading "unknown+key" is a device on the machine, not a mod
description: An overlay stopped opening on the key it had always used, and its bind dialog started showing a phantom modifier in front of every extended key. Everything on the software side was eliminated first - a full mod purge included. The cause was a wireless keyboard that was switched off and still plugged into a dock.
tags: [cet, hotkeys, hid, input, overlay, hardware, wrong-theory, diagnosis]
status: draft
generated: { by: "claude", at: "2026-08-25T11:20:00-04:00" }
---

# A bind dialog reading "unknown+key" is a device on the machine, not a mod

**Symptom.** An in-game overlay stopped opening on the key it had opened on for
months. Its own bind dialog, which had always displayed that key by name, began
displaying `unknown+<key>` - a modifier it could not name, in front of the key
being pressed.

**Cause.** A wireless keyboard, **switched off**, still plugged into a
Thunderbolt dock, presenting a phantom HID device that contributed a modifier
nothing else on the machine reported.

Between those two sentences sat a multi-day investigation, and the reason it
took that long is that every plausible suspect is in the game.

## The fingerprint that names the layer

**Some keys bound cleanly and some did not.** A numeric-keypad key bound
normally; the arrow keys, Insert and Delete all came back with the phantom
modifier attached.

That split - **extended-scancode keys affected, main-block keys not** - is the
signature of a second device contributing scancodes, rather than of any
software. Software that intercepted input would not draw the line there.

The second half of the fingerprint is that **everything else on the machine
typed perfectly**: the desktop, a text editor, the Start menu, and the game's own
text fields. Only the consumer that reads raw HID scancodes saw the extra device.
"But my keyboard works fine" is therefore not evidence, and a user offering it is
describing a different layer.

## What was eliminated first, and why none of it was cheap

Recorded because each of these is where the next person will also start:

- **A mod changed the binding.** Disproved by the strongest test available: the
  same key failed on a vanilla install with only the script extender present,
  after a full purge of the mod list.
- **The shader injector was intercepting input.** Disproved by renaming its DLL.
  The user's own objection - *why would that be the culprit?* - was correct, and
  the test was run anyway because it was cheap.
- **A monitoring overlay** that had been installed on the machine for years
  without incident.
- **Exclusive fullscreen versus borderless.**
- **Extra builds of a chat application** installed for multiple accounts.

Every one of those is a software theory, and the fault was not in software at
all.

## The rule this produces

**Inventory the physical input devices before touching the game.** Docks and
hubs, KVMs, a laptop lid, a powered-off wireless keyboard or controller still
enumerated by the OS, a device left in pairing mode. A device that is off is not
a device that is absent - it is enumerated, and it can still contribute.

Unplug rather than reason: the test is seconds, and the machine is a layer that
almost never appears in a mod-list investigation.

## What it looks like in the stored binding

A binding captured while the phantom was present is not merely displayed wrongly
- it is **stored** wrongly. A chord recorded as filler-plus-key can never match a
plain keypress afterwards, so the binding is dead until it is re-recorded with
the device gone. See
[a binding can be stored as a packed integer](/input/packed-key-codes) for the
slots and the filler value.

## What was not verified

One machine, one dock, one event. The mechanism - a second HID contributing to
what the game reads - is standard input handling; the specific device class and
the extended-key split are one observation. The elimination list is the durable
part.

## Do not settle for another key

The tempting resolution is to bind the overlay somewhere else. It resolves
nothing, and the note it leaves behind ("this overlay cannot use that key")
outlives the broken hardware and teaches the next reader something false about
the software -
[a workaround outlives the fault it was written for](/process/a-workaround-outlives-the-fault).

## Related

- [Five separate stores hold key bindings](/input/five-binding-stores)
- [A binding store can lose its contents, and an empty store looks exactly like the wrong store](/input/a-binding-store-can-empty-itself) - the other way a binding goes bad without a mod
- [A CET mod folder without init.lua is not a mod](/engine/cet-mod-loading) - the log line that says whether the overlay's render layer started at all
