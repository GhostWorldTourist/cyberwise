# Objects with a jack-in slot, and which of them are a way in

> **Verified:** Cyberpunk 2077 patch 2.31 (base + EP1) - August 2026
> **Re-check after a patch:** every depot path here was unbundled from this
> install's archives. A game patch can move or retire an `.ent`, so re-verify a
> path before relying on it. The component rule in "What makes a jack-in" is
> read from the shipped script dump and changes far more rarely.

When an access point prop looks wrong for a scene, this is what else can carry
the port - and, more importantly, which of those actually open a network.

## What makes a jack-in

Not a TweakDB flag and not the device class. **Two components on the assembled
entity**, checked once at `OnGameAttached` (`deviceBase.script:513-576`):

| # | requirement |
|---|---|
| 1 | a `workWorkspotResourceComponent` named `personalLinkPlayerWorkspot` |
| 2 | an `entSlotComponent` named `IKslots` holding a slot named `personalLinkSlot`, `personalLinkSlotRight` or `personalLinkSlotBottom` |

`GetSlotTag()` (`:1498`) returns the first of those three slot names it finds, or
`''` - and an empty tag switches the whole thing off.

**Either component may come from the appearance, not the `.ent`.** This is the
trap: `vending_machine_1.ent` has neither, and `vending_machines.app` supplies
both. Reading only the `.ent` gets vending machines wrong. It also means a
*specific appearance* can lack the slot while its siblings have it.

`AccessPointControllerPS` and `PerkTrainingControllerPS` skip the component
check with a class default of `m_hasPersonalLinkSlot = true`.

## Jack-in is not breach - the distinction that matters here

A port gets V's hand into the object. Whether the **minigame** appears is decided
separately (`scriptableDeviceBasePS.script:2396, 2653, 1558`), and needs
`HasNetworkBackdoor()`, which requires all three of:

1. `hasNetworkBackdoor` set on that placement (authored per-instance, **0 by
   default on nearly everything**),
2. the device powered,
3. `GetBackdoorAccessPoint()` resolving - i.e. **an access point already on its
   network**.

`AccessPointControllerPS` overrides this and returns true whenever powered. That
is the whole difference:

> **A placed access point is a way in by itself. A placed vending machine is
> not**, however many personal-link slots it has.

NetSec does not change that. `Adopt.reds` adopts a device onto a registered AP
only when the device *already has* an access point that fails to resolve in the
world; a device with no network at all falls to `unlockWhenNoAccessPoint`, and
`grantStrandedJackIn` grants a **port, not a backdoor**.

**So: if the goal is another way into a network, place something from the first
table.** The second table is for adding a second jack-in to a network that
already has an access point.

## Access points - self-sufficient breach points

| depot path (`.ent`) | what it looks like |
|---|---|
| `base\gameplay\devices\masters\access_points\accesspoint.ent` | the standard AP, **14 appearances** |
| `base\gameplay\devices\masters\access_points\antenna_access_point.ent` | **comms/antenna pole**, socket at the base. Tall; wants sky clearance |
| `base\gameplay\devices\masters\access_points\antenna_access_point_small.ent` | short antenna; shares the same 14 appearances |
| `base\gameplay\devices\masters\access_points\router_wall.ent` | wall router. Flat-backed - mount it or it floats |
| `base\gameplay\devices\masters\access_points\router_wall_stillage.ent` | router on industrial shelving; expects a rack behind it |
| `base\gameplay\devices\masters\access_points\accesspoint_crouch.ent` | low AP with a crouch animation. **No appearance choice** |
| `base\gameplay\devices\masters\access_points\accesspoint_hidden.ent` | no appearance entries, but still has the socket mesh - "hidden" is quest state, not invisibility |
| `base\gameplay\devices\masters\access_points\corpse_access_point.ent` | **a body you jack into**. Lies on the ground |
| `base\gameplay\devices\masters\loot_container_access_point\loot_container_access_point.ent` | crate/container AP; slot is low on the object |
| `base\gameplay\devices\masters\loot_container_access_point\loot_container_access_point_airdrop.ent` | airdrop crate, larger |
| `ep1\gameplay\devices\masters\access_points\accesspoint.ent` | EP1 copy, identical appearances |

The 14 appearances on `accesspoint.ent` (World Builder shows them with an
`access_point_` prefix): `..._socket_a_entropy`, `_b_entropy`, `_c_kitsch`,
`_d_kitsch`, `_e_neomil`, `_f_neomil`, `_g_neokitsch`, `_h_neokitsch`,
`antenna_small`, `antenna_small_access_point_entropy_a`,
`antenna_small_access_point_neomilitary_b`, `arasaka_access_point_b`,
`router_b`, `router_entropy`.

**The antenna access point is the comms pole.** There is no non-AP antenna or
utility pole in the game with a jack-in, which turns out to be convenient.

## Port but no breach - a second jack-in for an existing network

All ship with `hasNetworkBackdoor = 0`.

| depot path | notes |
|---|---|
| `base\gameplay\devices\vending_machines\vending_machine_1.ent` | 80 appearances; port comes from the appearance, slot is low - leave floor clearance, do not sink it |
| `..\vending_machine_2.ent` / `_3.ent` | 63 and 64 appearances |
| `..\vending_machine_weapons_1.ent` | weapon vending machine |
| `..\ice_machine.ent` | **only** the `kitsch_*` appearances have the slot; both `entropy_*` do not |
| `base\gameplay\devices\forklift\forklift.ent` | **forklift**. Large footprint and a crush trigger - keep it off NPC paths |
| `base\gameplay\devices\utilities\industrial\industrial_cleaning_machine.ent` | floor cleaner |
| `base\gameplay\devices\masters\terminals\door_terminal_1.ent` / `_1b.ent` | wall-mounted door terminal |
| `base\gameplay\devices\masters\computers\computer_1.ent` | desktop, 16 appearances, all work |
| `base\gameplay\devices\masters\computers\laptop_1.ent` | desk height |
| `base\gameplay\devices\home_appliances\tv_sets\tv_1.ent` | **only** the `television_*_16x9` appearances |
| `base\gameplay\devices\home_appliances\tv_sets\screen_1.ent` | **only** the `screen_*_21x9` ones |
| `base\gameplay\devices\arcade_machines\arcade_machine_1.ent` | all 6 appearances |
| `base\gameplay\devices\confession_booth\confession_booth_1.ent` | big; needs an alcove |

EP1 adds `ep1\gameplay\devices\masters\computers\bunker_computer.ent`,
`bunker_laptop.ent`, `computer_bunker.ent`, `computer_oa.ent`.

## Verified negatives - look right, are not

No personal-link slot in **any** appearance: electric box, fuse box/generator,
netrunner chair, braindance headset, control panels, jukebox, intercoms,
data terms, stash, **the big satellite dish** (`plate_antenna_large`),
netrunner's nest control panel, all electrical/street poles, the vending
*terminal* (unlike the machines), and every camera and turret.

## Placement

**Entity -> Device, never Entity -> Template.** Device writes a
`worldDeviceNode` with a `deviceConnections` list and a persistent flag;
Template writes a `worldEntityNode`, which is geometry only. NetSec registers
access points from `AccessPointControllerPS.GameAttached()`, and only a device
node makes the game instantiate and persist that controller the way vanilla
expects.

To turn a table-two object into a breach point you need **both** halves:
`hasNetworkBackdoor = 1` in its instance data **and** a `deviceConnections`
entry pointing at a real access point's NodeRef. The flag alone does nothing,
because `GetBackdoorAccessPoint()` returns null when the connection list is
empty.

**Slot orientation** decides where V stands: priority is
`personalLinkSlotRight` -> `personalLinkSlot` -> `personalLinkSlotBottom`. A
`Bottom` object (vending machines, computers, crates) needs clear floor in
front; a `Right` object needs clearance on its right.

## One honest limit

This establishes the port and the class **from the files**. It does not prove
what the action list looks like in play for a given placement - that is
answered by logging the offered actions on the running device, not by reading
`.ent` files. The access-point templates are the safe bet precisely because
their breach does not depend on placement context at all.
