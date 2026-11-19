# Tidal Lock Dispatch — Game Design Document

```text
game_id: roblox_tidal_lock_dispatch
gdd_revision: 2026.08.26-r1
contract_version: tidal-lock-v1
engine: Roblox Studio
```

## 1. Player experience

Tidal Lock Dispatch is a single-player, third-person industrial canal-control game. The player starts a pump station, operates two lock chambers, four authoritative gates and four barge-advance segments, moves one cargo barge from upstream to a terminal dock, locks two mooring clamps in order and dispatches the cargo.

Difficulty comes from water-level, gate and barge interlocks; asynchronous movement; rejected commands; checkpoint death recovery and clean restart. It must not depend on precise jumping, random timing, vehicle driving or hidden puzzle guesses. A first playthrough should take roughly 6–9 minutes.

## 2. Controls

- `W/A/S/D`: move.
- Mouse: normal third-person camera.
- `Space`: ordinary jump; no required action depends on jumping.
- `E`: activate an in-range `ProximityPrompt`.
- `R`: abandon the run and begin a clean run.

The player does not directly drive the barge. It moves only after a valid segment command.

## 3. World states

Semantic zones are `Upstream → Lock1 → Transfer → Lock2 → Terminal`. They are protocol identities, not absolute compass directions.

- Lock 1 external upstream level is High; Transfer is Mid.
- Lock 2 external upstream level is Mid; Terminal is Low.
- Both lock chambers initially have Low water.
- Barge initially occupies `Upstream`.
- Stable level enum: `Low`, `Mid`, `High`.
- Segment enum: `S1`, `S2`, `S3`, `S4`.

## 4. Complete success flow

1. Spawn centrally. HUD shows next pump `Prime`, Lock 1/2 levels, all gates closed, barge at Upstream, clamps unlocked, objective and timer.
2. Activate pump consoles in order `Prime → Balance → Vent`; the pump station becomes online.
3. Fill Lock 1 from Low to High and wait 3–5 seconds for a stable High level.
4. Open Lock 1 upstream gate. Run segment S1: barge travels Upstream → Lock1 over 3–5 seconds. Close the upstream gate.
5. Drain Lock 1 from High to Mid. Open its downstream gate. Run S2: barge travels Lock1 → Transfer. Close the downstream gate.
6. Fill Lock 2 from Low to Mid. Open Lock 2 upstream gate. Run S3: barge travels Transfer → Lock2. Close the upstream gate.
7. Drain Lock 2 from Mid to Low. Open Lock 2 downstream gate. Run S4: barge travels Lock2 → Terminal. Close the downstream gate.
8. At the dock, lock `Port` first and then `Starboard`.
9. Activate Dispatch. Completion and final time are published with a visible overlay.

## 5. Interlocks and rejection rules

### REQ-TL-01 — Pump station

- A pump other than the expected `Prime/Balance/Vent` step is rejected without advancing.
- An already enabled pump is rejected.
- Lock-level commands are rejected while the pump station is offline.

### REQ-TL-02 — Water levels

- Only transitions declared in `PUBLIC_SCHEMA.json` are legal.
- Lock 1: Low→High by Fill; High→Mid by Drain.
- Lock 2: Low→Mid by Fill; Mid→Low by Drain.
- A transition is rejected if either gate of that lock is open, another transition for that lock is busy, or direction is invalid.
- During a 3–5 second transition, transitioning/target/progress state and the visible water plane update. The final plane is within 1.5 studs of the matching level marker.

### REQ-TL-03 — Gates

- Lock1.Upstream opens only at High; Lock1.Downstream only at Mid.
- Lock2.Upstream opens only at Mid; Lock2.Downstream only at Low.
- A gate is rejected during a level transition or when the opposite gate of the same lock is open.
- A closed gate physically blocks traversal/barge route; an open gate becomes physically passable within two seconds.
- Both gates of one lock are never simultaneously passable.

### REQ-TL-04 — Barge

- S1 requires barge Upstream, Lock1 High and Lock1 upstream gate open.
- S2 requires barge Lock1, Lock1 Mid and Lock1 downstream gate open.
- S3 requires barge Transfer, Lock2 Mid and Lock2 upstream gate open.
- S4 requires barge Lock2, Lock2 Low and Lock2 downstream gate open.
- Wrong segment, wrong location, wrong level, closed gate or movement already in progress is rejected.
- Accepted movement is visible, lasts 3–5 seconds and ends with the single barge inside the target semantic zone.

### REQ-TL-05 — Docking

- Clamps reject commands unless the barge is at Terminal.
- `Starboard` rejects until `Port` is locked.
- Repeating a locked clamp is rejected without changing the other clamp.
- Dispatch rejects until barge is Terminal and both clamps are locked.

All rejections preserve authoritative state and produce visible feedback for at least 1.5 seconds.

## 6. Death, checkpoints and restart

### REQ-TL-06 — Ordinary death

Checkpoint zones exist at Lock1, Transfer and Terminal. The active checkpoint advances when the player physically enters the corresponding zone. Physical contact with the `Spill` hazard causes ordinary Humanoid death within one second, increments death count and respawns within 16 studs of the active checkpoint.

Pump progress, stable water levels, gate states, barge location, completed segments and clamp state survive ordinary death. An in-progress level or barge transition continues or resolves consistently; it must not duplicate or become permanently busy.

### REQ-TL-07 — Clean `R` restart

Within two seconds, restart creates a new run identity and restores pump step zero, pumps offline, both levels Low, no transitions, all gates closed/colliding, barge Upstream/not moving, clamps unlocked, checkpoint Central, death count zero, completion false, timer reset and initial HUD. Old delayed callbacks must not mutate the new run.

`R` works after rejected actions, during a level/barge transition and after completion. A separately reopened Play session begins clean.

## 7. HUD and feedback

The live `PlayerGui` exposes title, objective, next pump/pump status, both stable/target/progress level states, four gate states, barge location/movement/segment, clamps, checkpoint, death count, elapsed/final time, accepted/rejected feedback and completion overlay with restart instruction.

HUD must reflect authoritative gameplay state.

## 8. Layout and accessibility

- All controls and required zones are reachable by ordinary walking.
- Required semantic targets are within 175 horizontal studs of central spawn.
- Walkways are at least 12 studs wide with 8 studs headroom.
- Required target height difference is at most 2 studs.
- Each prompt has at least a 7×7 approach footprint; prompt separation is at least 14 studs.
- Prompt key is `E`, activation range 6–14 studs and hold duration at most 0.5 seconds.
- Checkpoint/hazard distance is 12–35 studs; hazard footprint at least 8×8 studs.
- The barge ends within 10 studs of its target semantic zone.

Absolute coordinates, decoration, hierarchy and reasonable dimensions may vary.

## 9. Public semantic contract

The authoritative machine-readable contract is `PUBLIC_SCHEMA.json`. High-level facts include:

- Workspace Attributes: `TLD_ContractVersion="tidal-lock-v1"`, `TLD_Ready=true` only after the playable contract exists.
- Exact unique counts and IDs for central spawn, pump consoles, chambers, water planes, level markers/consoles, gates, barge, mooring zones, advance consoles, clamps, dispatch console, checkpoints and hazard.
- Required player Attributes, enums, transition tables, segment prerequisites and public event families declared in `PUBLIC_SCHEMA.json`.

Tags and Attributes locate semantics without revealing coordinates. Required objects must have real prompts, collision, movement and engine behavior.

## 10. Equivalent implementations and invalid shortcuts

Equivalent layouts, hierarchy, art, UI composition, animation and script architecture are allowed. Evaluation must not require Gold coordinates or class names.

Invalid shortcuts include teleporting the barge/player instead of visible valid movement, changing only text/Attributes without physical state, allowing both gates open, duplicating the barge, bypassing level/segment/clamp order, hidden completion controls, or shipping evaluator/Gold code in the candidate.
