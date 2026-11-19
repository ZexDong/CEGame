# Relay Foundry Protocol

## Premise and objective

You are a technician in a compact automated relay foundry. Complete three production orders, each by carrying one relay core through the correct **charge → stabilize → encode → deliver** sequence. When all three finished cores are delivered, power the exit and enter the evacuation bay.

The three order recipes are public and must be displayed in the game:

| Order | Charge | Stabilize | Encode |
|---|---|---|---|
| 1 — Ion Relay | Pulse | Brace | Cipher |
| 2 — Ember Relay | Arc | Float | Key |
| 3 — Flux Relay | Flux | Lock | Mark |

## Controls

- `W/A/S/D`: walk; mouse: camera; `Space`: jump.
- `E`: collect a core, apply the selected operation at a machine, deliver an encoded core, power the exit, or use an ordinary proximity interaction.
- `Q`: cycle the selected mode at the nearby machine. The current mode must be visible in the machine UI/HUD before the player presses `E`.
- `R`: abandon the current run and start a wholly new run.

All core, machine, console, and restart actions must be possible with ordinary player input. No action may silently complete from a distance.

## Player flow

1. Start at the central forge. The HUD shows Order 1 and its recipe.
2. At the core dock, press `E` to take the current order's raw core.
3. Visit the Charge Bay. Use `Q` until its selected mode matches the current order, then press `E`.
4. Repeat at the Stabilize Bay, then the Encode Bay, using that order's recipe.
5. At the delivery dock, press `E` to deliver the encoded core. The next order appears.
6. Repeat until all three orders are delivered.
7. Return to the exit console and press `E` to power the exit. The physical exit gate opens.
8. Walk through the opened gate and enter the evacuation bay to complete the run.

## Rules and state

### Core phases

Each current-order core is in exactly one of these states: `Absent`, `Raw`, `Charged`, `Stabilized`, `Encoded`, or `Faulted`.

- A new run begins with an `Absent` current core and Order 1 selected.
- The core dock supplies the current order's core as `Raw` only when it is absent.
- A correctly configured Charge Bay accepts only `Raw` and changes it to `Charged`.
- A correctly configured Stabilize Bay accepts only `Charged` and changes it to `Stabilized`.
- A correctly configured Encode Bay accepts only `Stabilized` and changes it to `Encoded`.
- The delivery dock accepts only `Encoded`; it increases delivered count and makes the next core `Absent`.

An `E` operation at any production bay using a wrong phase or wrong mode faults the current carried core. A faulted core cannot be processed or delivered. Take it to the Purge Bay and press `E`; purge restores it to `Raw` for the same order. Purging never erases an already delivered order.

Mode cycling alone must never change the core phase, order, delivered count, or exit state. A rejected action must leave all unrelated state unchanged and show a clear player-visible message.

### Failure, checkpoint, and restart

The foundry contains one marked safety checkpoint and one real hazard. Touching the checkpoint updates the respawn checkpoint. Touching the hazard must kill the character through normal Roblox character health/death behavior.

After ordinary death, the order number, delivered orders, exit power, and current core phase are preserved. The carried core is returned to its dock location; if it was in progress or faulted, collecting it again returns that same phase. The character respawns near the latest checkpoint. Ordinary death is not a restart.

Pressing `R` during play or after completion starts a new run: all order progress, current-core state, modes, checkpoint, faults, exit power, gate, completion result, and timer reset. A new RunId is created.

## HUD and feedback

The gameplay HUD must remain visible in Play mode and include: current order/name, recipe, core phase, the three selected machine modes, delivered count (`0/3` to `3/3`), checkpoint, exit-power state, timer, and a non-empty recent feedback line.

Show a clear feedback message for successful processing, wrong mode/phase, purge, delivery, checkpoint, hazard/death, locked exit console, exit power, completion, and restart. Completion must show a clear completed result and final time.

## World requirements

Create a legible, navigable foundry with the central forge, one dock, three distinct production bays, a purge bay, a safety checkpoint/hazard route, an exit console, a physical exit gate, and an evacuation zone. It may be styled freely. All essential destinations must be reachable by ordinary walking on a stable path; avoid required precision jumps or time-sensitive movement.

The hazard must be physically touchable and kill only on real contact. Before it is powered, the tagged exit gate must physically block the player; after power it must no longer block the player. Completion requires physically entering the evacuation zone, not merely powering the gate.

## Equivalence and restrictions

You may freely change placement, naming, visuals, text wording, hierarchy, architecture, and decorative content. You may not change recipes, control keys, state meanings, required Tags/Attributes/events, or the real-world behavior specified in EVALUABILITY_CONTRACT.md.

Forbidden shortcuts include: automatic order advancement without a nearby interaction, state-only fake completion, hidden completion keys, non-contact hazard death, a non-blocking pre-powered gate, and completing by pressing `E` without entering the evacuation zone.
