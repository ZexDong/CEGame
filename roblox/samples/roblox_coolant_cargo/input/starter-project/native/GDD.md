# Coolant Cargo Protocol — Game Design Document

```text
game_id: roblox_coolant_cargo
gdd_revision: 2026.08.26-r1
contract_version: coolant-cargo-v1
engine: Roblox Studio
```

## 1. Player experience

Coolant Cargo Protocol is a single-player, third-person reactor-recovery game. The player must complete two independently testable systems: open three coolant valves in order, and physically move an energy cell through pickup, charging and installation. When both systems are ready, the player stabilizes the reactor, performs a two-door airlock decontamination sequence and physically enters an evacuation zone.

The challenge comes from ordered actions, parallel state machines, asynchronous transitions, rejection rules, physical carrying, death recovery, checkpoints and clean restart. It must not depend on precise platforming, random timing, moving platforms or hidden puzzle guesses. A first playthrough should take roughly 5–8 minutes.

## 2. Controls

- `W/A/S/D`: move.
- Mouse: normal third-person camera.
- `Space`: ordinary jump; no required flow may depend on jumping.
- `E`: activate an in-range `ProximityPrompt`.
- `R`: immediately abandon the current run and begin a clean run.

No undisclosed key, chat command, dragged UI control or external command may be required.

## 3. Complete success flow

1. Spawn at the central start. The HUD shows coolant `0/3`, cell state `Rack`, reactor not stable, current objective and elapsed time.
2. Activate coolant valves in the exact order `Intake → Bypass → Outlet`. Each accepted valve advances once. The third makes coolant ready.
3. Pick up the visible energy cell from the rack. It becomes `Carried` and visibly follows the character.
4. Place the carried cell into the charge dock. It becomes `Docked`.
5. Activate the charge console. The cell becomes `Charging`; after 3–6 seconds it returns to `Docked` with charged state true. Progress or remaining state is visible.
6. Retrieve the charged cell. It becomes `Carried` and remains charged.
7. Install it into the reactor socket. It becomes `Installed` and power becomes ready.
8. When coolant and power are both ready, activate the reactor console. The reactor becomes stable. Earlier attempts are rejected without state mutation.
9. Within two seconds, the outer airlock door opens and is non-colliding; the inner door remains closed and colliding.
10. Physically enter the airlock and activate the decontamination console. Only a player inside the airlock with a stable reactor is accepted.
11. Decontamination lasts 3–6 seconds. The outer door closes before the inner door opens; both doors must never be traversable simultaneously.
12. Physically pass through the inner door and enter the evacuation zone. Completion, final time and a visible completion overlay are published.

## 4. Required rejection behavior

### REQ-CC-01 — Valve order

- A valve other than the expected valve is rejected.
- An already opened valve is rejected.
- Rejection does not advance the coolant step or open another valve.
- Feedback identifies that the action was rejected and indicates the expected valve.

### REQ-CC-02 — Cell lifecycle

- The charge dock rejects placement when the player is not carrying the cell.
- The reactor socket rejects an uncharged cell.
- A charging cell cannot be picked up.
- Only one energy cell exists. It cannot be duplicated across rack, character, dock and socket.

### REQ-CC-03 — Reactor and airlock

- The reactor console rejects activation unless both coolant and power are ready.
- Decontamination rejects activation unless the reactor is stable and the player is physically inside the airlock.
- The inner door cannot open before decontamination completes.
- The outer and inner doors are never both non-colliding/open.
- Entering the evacuation zone before the valid airlock sequence does not complete the game.

## 5. Death, checkpoint and restart

### REQ-CC-04 — Ordinary death

- The player can activate the `Safety` checkpoint and then physically touch the `Safety` hazard.
- Hazard contact causes ordinary Humanoid death within one second.
- Death count increments and the character respawns within 16 studs of the active checkpoint.
- Open valves, charged state and an installed cell remain valid across ordinary death.
- A carried cell is recovered to the rack instead of being lost or duplicated.
- A partial airlock operation returns to the nearest safe stable stage.

### REQ-CC-05 — Clean `R` restart

Within two seconds, restart creates a new run identity and restores all initial gameplay state: coolant `0/3`, closed valves, cell at rack and uncharged, reactor unstable, checkpoint `Central`, death count zero, airlock locked, doors in initial collision state, completion false, timer reset and initial HUD. Old delayed charge/decontamination callbacks must not mutate the new run.

`R` works after errors, during asynchronous work and after completion. A newly reopened Play session also begins clean.

## 6. HUD and feedback

The live `PlayerGui` must clearly expose:

- game title;
- current objective;
- coolant progress and expected valve;
- cell location/charging/charged state;
- reactor state;
- airlock stage;
- checkpoint and death count;
- elapsed or final time;
- temporary accepted/rejected action feedback for at least 1.5 seconds;
- completion overlay and restart instruction.

HUD content must reflect authoritative gameplay state rather than an independent cosmetic simulation.

## 7. Layout and accessibility

- All required targets are reachable by ordinary walking from the central spawn.
- No required target is more than 145 horizontal studs from the central spawn.
- Required walkways are at least 12 studs wide with at least 8 studs headroom.
- Required interactions are on approximately the same walkable level; target height difference is at most 2 studs.
- Interactions have at least a 7×7 stud approach footprint.
- The checkpoint and hazard are 12–35 studs apart; the hazard footprint is at least 8×8 studs.
- The airlock has at least 14×14 studs of safe interior space and its doors are at least 16 studs apart.
- Prompt activation distance is 6–14 studs, hold duration at most 0.5 seconds and key `E`.

The implementation may freely change absolute coordinates, decoration, hierarchy and reasonable dimensions while preserving these semantic constraints.

## 8. Public semantic contract

The authoritative machine-readable contract is `PUBLIC_SCHEMA.json`. Required high-level facts include:

- Workspace Attributes: `CCP_ContractVersion="coolant-cargo-v1"`, `CCP_Ready=true` only after the playable contract exists.
- Unique semantic Tags for central spawn, three valves, rack, cell, dock, charge console, socket, reactor console, checkpoint, hazard, outer/inner doors, airlock zone, decon console and evacuation zone.
- Valve IDs: `Intake`, `Bypass`, `Outlet`.
- Cell states: `Rack`, `Carried`, `Docked`, `Charging`, `Installed`.
- Airlock stages: `Locked`, `OuterOpen`, `Occupied`, `Decontaminating`, `InnerOpen`.
- Player Attributes and public event strings exactly as declared in `PUBLIC_SCHEMA.json`.

Tags identify semantics, not coordinates. Each required object must have the declared class, unique ID and a real physical/prompt behavior.

## 9. Equivalent implementations

Equivalent layouts, art styles, object hierarchies, script organization, UI composition and transition animation are allowed. Server-authoritative or otherwise secure equivalent architectures are allowed. Evaluation must not require Gold class names, Gold coordinates or Gold hierarchy.

## 10. Invalid shortcuts

The game is not complete if it only changes text or Attributes without corresponding physical state. Do not teleport the player as a substitute for traversal, spawn duplicate cells, complete without real evacuation-zone entry, bypass required order, make both airlock doors traversable, provide hidden debug completion controls or include private evaluator/Gold content.
