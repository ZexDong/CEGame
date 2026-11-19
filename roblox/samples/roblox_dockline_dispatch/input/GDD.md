# Dockline Dispatch: Night Shift Game Design Document

## 1. Overview

A single-player, third-person warehouse logistics game with one level.
During a night shift, process a fragile glass crate, cold-chain case, and encrypted
safe. Scan, process, weigh, label, route, and stage each package. Load the pallet
in the fixed weight order, collect a dispatch seal, cross a periodic forklift
lane, install the seal on the truck, and enter the final dispatch code.

The focus is multi-object state, shared stations, legal/illegal actions, physical
carrying, routing recovery, ordered loading, deterministic hazards, death
recovery, and lifecycle behavior. Use ordinary walking and real ProximityPrompts,
without platforming, random puzzles, unpredictable rigid bodies, or image recognition.
First playthrough: 8-12 minutes. Development: approximately 100-200 meaningful
create/edit/build/repair actions.

## 2. Player input

W/A/S/D moves; mouse controls the third-person camera.
Space is normal Roblox jump, but the main route never requires jumping.
E interacts, picks up, places, or operates equipment.
Hold E for 1.5 seconds to wrap fragile goods or 2.0 seconds to condition cold goods.
R abandons the run and starts completely clean.
No undocumented keys. All gameplay interactions use real ProximityPrompts;
the evaluator never calls gameplay Remotes or Prompt APIs.

## 3. World areas

Include spawn/Manifest console; three Inbound shelves; shared scanner, scale, and
label stations; fragile/cold/secure processing; conveyor load point, two
diverters, dispatch console, RejectBuffer; staging Bays A/B/C; three-slot pallet
and seal output; seal checkpoint shelf, safe waiting area, periodic forklift
lane; truck seal socket and final code panel.
All prerequisite workspaces and the hazard are walkable or observable.
Even if package processing fails, HUD, R, rejections, hazard death, and initial
checkpoint recovery remain independently testable.

## 4. Fixed packages and routes

| PackageId | Name | RequiredProcess | Weight | Route | Bay |
|---|---|---|---:|---|---|
| GlassCrate | Fragile glass crate | FragileWrap | 3 | B | Bay B |
| ColdCase | Cold-chain case | ColdCondition | 5 | C | Bay C |
| CipherBox | Encrypted safe | SecureAuth | 8 | A | Bay A |

Exactly one authoritative instance of each package exists at run start.
Carry at most one DD_CarryItem.

## 5. Shift start and scanning

1. Initially RunStatus=AwaitingStart; world, HUD, hazard cycle, and packages exist.
2. Press E at Manifest.StartShift to set InProgress and RunStart to server time.
3. Reject pickups/station progress before shift start without state changes.
4. Process packages in any order after starting.
5. Pick up from its Inbound shelf; the physical object follows the character.
6. Scan the carried package at Inspection.Scanner. Display PackageId,
   RequiredProcess, and RouteId. Rescanning cannot duplicate or regress it.
7. Reject scanner use without a carried package and show feedback.

## 6. Package-specific processing

### 6.1 Fragile wrapping

Bring scanned GlassCrate to Process.FragileWrap. Hold E for 1.5 seconds.
Early release interrupts without ProcessComplete. Reject other packages without loss.

### 6.2 Cold conditioning

Bring scanned ColdCase to Process.ColdCondition. Hold E for 2.0 seconds.
Early release interrupts. Reject other packages.

### 6.3 Secure authorization

Carry scanned CipherBox and operate Secure.AuthStart.
Enter Delta -> Alpha -> Charlie. Wrong order resets only AuthProgress;
CipherBox remains carried and scanned.
Three correct keys set ProcessComplete=true.
Reject authorization start/keys unless carrying scanned CipherBox.
Processing another package or R clears temporary authorization progress.

## 7. Weighing and labeling

Scanning and the required process must be complete.
Use Measure.Scale while carrying the package to record its fixed MeasuredWeight.
Reject weighing without a package, scan, or process.
Then use Label.Printer with the fixed RouteId; reject printing before weighing.
The labeled package is ReadyToRoute and remains carried.

## 8. Conveyor routing and rejection recovery

### 8.1 Diverters

Each real Prompt toggles one diverter between Left and Right.

| RouteId | Diverter One | Diverter Two |
|---|---|---|
| A | Left | Left |
| B | Left | Right |
| C | Right | Right |

HUD and equipment signs show current diverter states and this route table.

### 8.2 Correct and incorrect routes

1. Conveyor.Load places a carried ReadyToRoute package at the real loading point
   and clears CarryItemId.
2. At most one package occupies the conveyor.
3. Diverters may change before or after loading.
4. Conveyor.Dispatch resolves within 3 seconds.
5. Matching RouteId sends the package to its Bay with state Staged.
6. A mismatch sends it to RejectBuffer with state Rejected and increments
   RejectCount. Other packages and completed preparation remain unchanged.
7. Rejected packages preserve scan/process/weight/label. Reject.Return picks up
   the package again for reloading/rerouting.
8. Reject dispatch without a package, while busy, or with an unlabeled package.
9. Routing never duplicates, destroys, or hides a package outside the map.

## 9. Staging and pallet loading

Correctly routed packages physically occupy their respective Bays.
Staging.Pickup.A/B/C retrieves only that Bay's Staged package.
Load CipherBox -> GlassCrate -> ColdCase into Pallet.Slot.Cipher/Glass/Cold.
Wrong item/order preserves the carried item and existing PalletProgress.
All three installed packages become Palletized; PalletState=Complete.
Expose one DispatchSeal at Pallet.SealPickup.
Carrying the seal sets WalkSpeed=13; otherwise WalkSpeed=16.

## 10. Checkpoint, hazard, and death recovery

1. From DD_HazardEpoch, `(serverTime - HazardEpoch) mod 7 < 3` is Safe;
   the remaining 4 seconds are Active.
2. The cycle runs from Ready independently of package progress.
3. HUD, world lights, and DD_HazardState agree. Death preserves phase;
   R sets a new HazardEpoch.
4. Physical contact with Active DD_Hazard kills within 1 second.
   The same authoritative part never damages during Safe.
5. DD_SafeZone before the lane is safe in every phase.
6. Initial CheckpointId=Start. Ordinary death respawns near spawn and preserves
   completed package processing, routing, and pallet progress.
7. Place DispatchSeal at Checkpoint.SealShelf: set checkpoint SealShelf and clear
   CarryItemId. The same Prompt retrieves it.
8. Death after activation respawns near the shelf and returns the seal there,
   preserving pallet progress.
9. Ordinary packages return to their current legal HomeStation, never duplicate
   or become permanently lost.

## 11. Truck seal and final dispatch

Carry the seal across during Safe and install it at Truck.SealSocket.
Set SealInstalled=true; it is no longer carryable.
Immediately start a 20-second code window for 2 -> 4 -> 1.
Wrong order or timeout resets only FinalCodeProgress and immediately restarts
the 20-second window; the seal remains installed.
Correct completion sets Completed, freezes FinalTime, and shows completion.
After Completed, gameplay state is frozen except for R.

## 12. HUD and feedback

Show current objective; shift/completion status; all three package summaries;
carried item; scan contents; authorization progress; both diverters and route
table; conveyor state; pallet progress; Safe/Active hazard; checkpoint; timer;
and latest feedback.
Every event synchronizes DD_FeedbackText with visible HUD feedback for >=1.5
seconds. Completion shows success, final time, and R restart.

## 13. Failure, R, and Reopen

### Local failures

Reject not-started/no-item/wrong-item/wrong-stage actions without progress.
Early release leaves wrapping/conditioning incomplete.
Authorization error resets AuthProgress. Misrouting preserves preparation in
RejectBuffer. Wrong pallet order neither consumes nor regresses anything.
Final error/timeout resets FinalCodeProgress while retaining the seal.

### R restart

Within 2 seconds, strictly increase RunId and restore AwaitingStart.
Reset packages, processing, weighing, labels, routing, rejections, staging,
pallet, seal, checkpoint, deaths, code, and completion.
Return packages to Inbound, seal to Unavailable, diverters to Left, conveyor to
Empty, and character to spawn at WalkSpeed=16.
Old delayed tasks, connections, and timers cannot affect the new run.

### Reopen

No persistent progress. Restarting Play enters a fresh AwaitingStart game;
RunId may begin at 1.

## 14. World and movement constraints

1. All targets have continuous static collidable walking routes, requiring no
   jump, teleport, moving platform, or precise camera angle.
2. Clear width >=10 studs and headroom >=8; forklift lane width >=12.
3. Interaction standing points differ from ApproachNode by <=2 vertical studs.
4. Each interactable has one ApproachNodeId reachable within real Prompt range.
5. Critical objects cannot overlap so that one E fires multiple Prompts.
6. DD_NavNode supplies live positions. DD_NavLink is semantic Configuration,
   not PathfindingLink; do not set a Roblox Enabled property.
7. Each edge represents a real walking route; DD_Enabled mirrors traversability.
8. Safe nodes exist before/after the lane and remain safe during Active.
9. Final code buttons lie within 35 horizontal studs of Truck.SealSocket.
10. Coordinates, orientation, names, and decoration may vary. No fixed evaluator
    coordinates are required.

## 15. Consistency and invalid substitutes

State mirrors actual input/world behavior. Each CarryItemId has one authoritative
instance across world, character, and installed positions. DD_CarryItemId matches
the physical follower. No package becomes Labeled before scan/process/weighing.
StagedCount equals actual Bay occupancy. The seal becomes Available only after
PalletProgress=3. Completed requires SealInstalled and the full final code.
Death preserves RunId, RunStart, and completed logistics; R increments RunId and
resets the game.

No automatic advancement without reaching Prompts; state-only/HUD-only
substitutes; hidden keys, admin commands, test buttons, or Remote shortcuts;
destruction/duplication after rejection; timed death without Active contact;
teleport-based normal travel/checkpoints/completion; premature Completed;
or names, source strings, and tags substituted for observed behavior.
