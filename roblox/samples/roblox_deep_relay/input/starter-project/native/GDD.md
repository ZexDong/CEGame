# Deep Relay: Lockdown Recovery Game Design Document

## 1. Overview

Deep Relay is a single-player, third-person facility restoration game with one
level. Restore independent power, coolant, and authorization systems in an
offline underground relay station. Collect their three output components,
assemble the relay core in order, pass an interlocked airlock, checkpoint, and
periodic hazard, then install and stabilize the core.

The task emphasizes a long stateful flow, valid and invalid actions, physical
carrying, continuous numeric control, safety interlocks, death recovery, and
lifecycle behavior. The main route must be walkable without precision platforming,
random puzzles, unpredictable physics, or visual guessing.
Expected first playthrough: 8-12 minutes. Expected development effort: roughly
100-200 meaningful create, edit, build, and repair actions.

## 2. Player input

- W/A/S/D: movement.
- Mouse: third-person camera.
- Space: normal Roblox jump; the main route must not require jumping.
- E: normal interaction or pickup/placement.
- Hold E: fuse charging, coolant inlet/pumping, and airlock equalization.
- R: immediately abandon the run and start a completely clean run.

Do not require undocumented keys. Every E interaction uses a real
ProximityPrompt.

## 3. World areas

Include a central spawn/objective hall; power, coolant, and authorization service
areas; core assembly area; two-door airlock; exit checkpoint shelf; periodic
hazard corridor with a clearly safe waiting area; and relay installation/final
stabilization area.
All three services are independently reachable from spawn and may be completed
in any order. Core assembly requires all three modules.

## 4. Complete success flow

### 4.1 Power tuning

1. Pick up `PowerFuse` from its rack.
2. Insert it into the power socket. Reject wrong items without consuming them.
3. The power panel displays `B -> C -> A`.
4. Operate the breakers in that order. Wrong order resets only breaker progress;
   the inserted fuse remains.
5. Hold E at the charger for 2.0 seconds. Releasing early prevents completion and
   resets accumulated charge.
6. Complete the power module and expose exactly one `ChargedCell` on its output.

### 4.2 Coolant balance

1. Pressure starts at 0; the stable target range is 45-55.
2. Holding E at the inlet increases pressure by 12 units/second; release stops it.
3. Once pressure exceeds 0, holding E at the pump reduces it by 5 units/second.
4. The locking lever is usable only after pressure remains at 45-55 for 1.0 second.
5. Pressure above 65 triggers overpressure venting to 20. The module remains
   incomplete and other systems are unaffected.
6. A legal lock completes coolant and exposes one `CoolantCanister`.

Discrete frame updates are allowed. Public pressure Attributes and HUD update at
least every 0.25 seconds; rate tolerance is +/-20%.

### 4.3 Authorization calibration

1. Activate the authorization controller.
2. Display `Gamma -> Alpha -> Beta`.
3. Operate the three scan terminals in order.
4. Wrong order resets only scan progress, leaving other systems/items unchanged.
5. Three correct scans complete authorization and expose one `AuthToken`.

### 4.4 Core assembly

1. Carry at most one item. It physically follows the character while carried.
   Installation, checkpoint placement, or death recovery places it at the
   appropriate Station. A free-drop key is not required.
2. Assembly order is `CoolantCanister -> ChargedCell -> AuthToken`.
3. Bring each item to its assembly slot and press E.
4. Reject wrong items or stages without losing the carried item or prior progress.
5. Installing all three exposes exactly one `RelayCore`.
6. Carrying RelayCore sets WalkSpeed to 12. Placement, installation, death, or R
   restores WalkSpeed to 16.

### 4.5 Airlock and checkpoint

1. Initially the outer door is open, inner door closed, state `OpenOuter`.
2. Carry RelayCore into the airlock.
3. Close the outer door with its controller; state becomes `Sealed`.
4. Hold E at the equalizer for 2.0 seconds to reach `Equalized`. Early release
   returns to `Sealed`.
5. Reject opening the inner door before equalization. Both authoritative doors
   must never be passable simultaneously.
6. Open the inner door after equalization; state becomes `OpenInner`.
7. Place RelayCore on the exit checkpoint shelf, show checkpoint confirmation,
   and allow it to be picked up again.

### 4.6 Hazard corridor and final stabilization

1. Use a deterministic 6-second cycle relative to `RunStart`:
   `(serverTime - RunStart) mod 6 < 2` is `Safe`; the other 4 seconds are `Active`.
   HUD and world lights display the state. Ordinary death preserves phase; R
   begins a new phase.
2. Physical contact with the authoritative Active hazard kills within 1 second.
   The same part causes no damage while Safe.
3. Respawn near the latest checkpoint and return RelayCore to its shelf.
   Preserve module, assembly, and airlock state.
4. Retrieve the core and cross during Safe. Safe waiting areas never cause damage.
5. Install RelayCore at the relay socket; it is no longer carryable.
6. Show `2 -> 1 -> 3` on the final panel. Start a 30-second stabilization countdown
   immediately upon core installation.
7. Operate the nodes in order. Wrong order or timeout resets only stabilization
   progress and immediately begins another 30-second attempt; the core stays
   installed.
8. After all three nodes, set `RunStatus = Completed`, freeze the timer, and show
   completion with final time.
9. After completion, gameplay state remains frozen except for R.

## 5. HUD and feedback

Display continuously or in the relevant phase: current objective; Power/Coolant/
Authorization status; breaker/scan progress; pressure and target range; carried
item; assembly progress; airlock state; Safe/Active hazard state; checkpoint; run
timer; and latest feedback.

Every protocol event synchronizes `DR_FeedbackText` with the visible HUD for at
least 1.5 seconds. Wording may vary but must express the event. Completion shows
success, final time, and an R restart prompt.

## 6. Failure, death, restart, and Reopen

### Local failures

- Power error: BreakerProgress=0; fuse remains.
- Overpressure: Pressure=20.
- Authorization error: ScanProgress=0.
- Assembly error: preserve item and progress.
- Illegal airlock opening: preserve doors and equalization state.
- Final error/timeout: StabilizerProgress=0; core remains installed.

### Ordinary death

Preserve RunId, RunStart, completed modules, outputs, assembly, airlock, and timer.
Increment DeathCount. Respawn near the latest checkpoint.
Ordinary carried items return to their Home Station. RelayCore returns to an
activated CoreShelf, otherwise to assembly output.
Critical items must never duplicate or become permanently lost.

### R restart

Return to central spawn within 2 seconds and strictly increase RunId.
Reset all modules, items, assembly, airlock, checkpoint, death count,
stabilization, completion, and HUD to new-run values.
Old delayed tasks, connections, and timers must not affect the new run.

### Reopen

No persistent progress. Stopping Play and launching again starts a fresh initial
game. RunId may start from 1 again.

## 7. World and movement constraints

1. Every required target is connected by continuous static collidable walking
   routes. No jump, ladder, teleport, or moving platform is required.
2. Route clear width >=10 studs and headroom >=8 studs; airlock/hazard width
   >=12 studs.
3. Interaction standing points differ vertically from adjacent navigation nodes
   by no more than 2 studs.
4. Each interactable has one ApproachNodeId. A default character near that node
   can enter the real Prompt range.
5. Navigation edges do not cross closed doors, hazards, or noncollidable ground.
   Variable DR_NavLink edges mirror traversability through Enabled.
6. At least one hazard waiting node remains safe during Active.
7. No overlapping critical objects that let one E trigger multiple Prompts.
8. Reach the exit only through the airlock and the final area only through the
   hazard corridor.
9. Coordinates, orientations, room order, and decoration are flexible; the
   evaluator must not need predetermined absolute coordinates.
10. Each final stabilization node is within 40 horizontal studs of
    Final.CoreSocket and connected through legal navigation edges.

## 8. State consistency

- Module completion comes only from its real gameplay.
- Each ItemId has one authoritative instance across world, player, and slots.
- CarryItemId matches the physically following DR_CarryItem.
- AssemblyProgress equals the number of correctly installed required items.
- RelayCore cannot appear before AssemblyProgress=3.
- Both airlock doors cannot simultaneously have CanCollide=false.
- Completed requires the installed core and all three stabilization nodes in order.
- FinalTime becomes positive only after Completed and remains frozen.
- Ordinary death preserves RunId/RunStart; R increments RunId and resets the run.

## 9. Equivalent implementations

Coordinates, room orientation, object names, Model hierarchy, code organization,
materials, lighting, equivalent UI layout, door animation, and feedback wording
may vary. Basic Parts may form visual objects.
Do not alter fixed inputs, sequences, numeric windows, local-failure semantics,
public tags/Attributes/events, navigation protocol, physical carrying, door
interlocks, hazard cycle, or completion conditions.

## 10. Invalid substitutes

Do not auto-advance without reaching real Prompts; update Attributes/HUD without
changing authoritative items/doors/collision/health/world state; use hidden keys,
Remotes, test buttons, or administrator commands; overlap semantic objects to
trigger multiple actions with one E; provide invisible bypasses; kill on a timer
without Active Hazard contact; teleport players as normal gameplay; set Completed
before core installation/stabilization; or substitute names/source strings for
observed behavior.
