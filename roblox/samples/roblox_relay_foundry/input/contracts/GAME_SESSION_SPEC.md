# Relay Foundry public evaluability contract v1

This is a public gameplay protocol. It lets interoperable tooling find semantic objects across valid implementations, but its state mirrors do not replace real gameplay. Tags must be attached to the authoritative physical object involved in play, rather than to a decorative proxy.

## Readiness and general rules

Within 12 seconds of Play beginning, Workspace must have `RFP_ContractVersion` (string `relay-foundry-v1`) and `RFP_Ready` (boolean `true`). All required objects, tags, Attributes, prompts, HUD, and player state must then be available.

Object names and hierarchy are unrestricted. Essential tagged targets must be on walkable, connected ground no more than 180 horizontal studs from `RFP_CentralSpawn`, with at least a 10-stud clear walking width and 8-stud headroom along required routes. Layout, direction, and exact coordinates are not prescribed.

## Required tags

| Tag | Count | Authoritative object requirement | Required attributes |
|---|---:|---|---|
| `RFP_CentralSpawn` | 1 | BasePart or SpawnLocation; new runs spawn within 24 studs | — |
| `RFP_CoreDock` | 1 | BasePart with the real core-collect interaction | — |
| `RFP_ProductionBay` | 3 | BasePart with real selector and operation interactions | `RFP_BayId`: `Charge`, `Stabilize`, `Encode` |
| `RFP_PurgeBay` | 1 | BasePart with real fault-purge interaction | — |
| `RFP_DeliveryDock` | 1 | BasePart with real delivery interaction | — |
| `RFP_SafetyCheckpoint` | 1 | BasePart actually touched to set checkpoint | `RFP_Id = Safety` |
| `RFP_Hazard` | 1 | BasePart whose real touch kills the character | `RFP_Id = Safety` |
| `RFP_ExitConsole` | 1 | BasePart with real exit-power interaction | — |
| `RFP_ExitDoor` | 1 | BasePart that physically blocks when unpowered | — |
| `RFP_EvacuationZone` | 1 | BasePart actually entered to complete | — |

There must be exactly one `ProximityPrompt` for the `E` operation on the CoreDock, each ProductionBay, PurgeBay, DeliveryDock, and ExitConsole. It may be a descendant of the tagged part. `KeyboardKeyCode=E`, `MaxActivationDistance` is 6–14 studs, and `HoldDuration` is at most 0.5 seconds.

Each ProductionBay must additionally expose exactly one nearby real mode-selector `ProximityPrompt` with `KeyboardKeyCode=Q`, `MaxActivationDistance` 6–14 studs, and `HoldDuration` at most 0.5 seconds. Using Q changes only that bay's selected mode and visibly updates the HUD/world feedback.

## Player attributes

All fields below must continuously exist on every player and mirror real state.

| Attribute | Type | New-run value / legal values |
|---|---|---|
| `RFP_RunId` | integer number | at least 1; strictly increases on R |
| `RFP_OrderIndex` | integer number | 1–3 while unfinished, 4 after third delivery |
| `RFP_CorePhase` | string | `Absent`, `Raw`, `Charged`, `Stabilized`, `Encoded`, `Faulted` |
| `RFP_ChargeMode` | string | `Pulse`, `Arc`, `Flux`; new run `Pulse` |
| `RFP_StabilizeMode` | string | `Brace`, `Float`, `Lock`; new run `Brace` |
| `RFP_EncodeMode` | string | `Cipher`, `Key`, `Mark`; new run `Cipher` |
| `RFP_DeliveredCount` | integer number | 0–3, new run 0 |
| `RFP_FaultCount` | integer number | non-negative, new run 0 |
| `RFP_Checkpoint` | string | `Central` or `Safety`, new run `Central` |
| `RFP_Powered` | boolean | false on a new run |
| `RFP_Completed` | boolean | false on a new run |
| `RFP_RunStart` | number | current server time; unchanged by ordinary death |
| `RFP_FinalTime` | number | 0 before completion; positive and frozen after completion |
| `RFP_DeathCount` | integer number | non-negative, new run 0 |
| `RFP_EventSerial` | integer number | at least 1; strictly increases for every listed event |
| `RFP_LastEvent` | string | one listed event; new run `RunStarted` |
| `RFP_FeedbackText` | string | non-empty and simultaneously visible in HUD |

## Recipes, state transitions, and event vocabulary

The recipe sequence is fixed: `1: Pulse/Brace/Cipher`, `2: Arc/Float/Key`, `3: Flux/Lock/Mark`.

Every listed event increments EventSerial, assigns LastEvent exactly, and supplies semantically matching non-empty visible feedback for at least 1.5 seconds.

| Behavior | Event |
|---|---|
| new run starts | `RunStarted` |
| core collected | `CoreCollected` |
| Charge succeeds | `Processed.Charge` |
| Stabilize succeeds | `Processed.Stabilize` |
| Encode succeeds | `Processed.Encode` |
| a bay operation has wrong phase | `Rejected.WrongPhase` |
| a bay operation has wrong selected mode | `Rejected.WrongMode` |
| a faulted core is purged | `CorePurged` |
| encoded core delivered | `CoreDelivered` |
| checkpoint touched | `CheckpointActivated.Safety` |
| hazard truly touched | `HazardTriggered.Safety` |
| respawn near Safety | `Respawned.Safety` |
| exit console used too early | `ExitLocked` |
| exit powered after three deliveries | `ExitPowered` |
| character truly enters evacuation zone | `Completed` |
| R creates a new run | `Restarted` |

For a wrong phase or wrong mode at a production bay, CorePhase becomes `Faulted`, FaultCount increases by one, and DeliveredCount/OrderIndex/Powered/Completed do not change. A rejected dock, purge, delivery, or console action must leave unrelated state unchanged and provide visible feedback; it need not use a special event string.

Purge applies only to `Faulted`, changing it to `Raw`. Delivery applies only to `Encoded`; it increments DeliveredCount and OrderIndex, then makes the next core `Absent`. No fourth core exists. Exit power applies only when DeliveredCount is 3. Completion applies only when Powered is true and the character actually enters the tagged evacuation zone.

## Physical and lifecycle invariants

- `RFP_DeliveredCount` equals the number of genuinely delivered cores; the current order cannot be skipped.
- The tagged door has `CanCollide=true` and blocks normal character movement before power. Within 2 seconds of `ExitPowered`, it changes to `CanCollide=false` and allows passage.
- The tagged hazard kills within 1.5 seconds of a genuine character touch. It cannot kill merely by elapsed time or a remote action.
- Ordinary death increments DeathCount but preserves RunId, RunStart, order progress, modes, faults, DeliveredCount, and Powered. The current core is recoverable from CoreDock with the same phase.
- R increments RunId and restores every listed new-run value, closes/blocks the door, clears completed UI, and returns the character near CentralSpawn within 3 seconds.
- R after completion has the same complete-reset semantics.

## Permitted observation; prohibited shortcuts

Automated tooling may read this public protocol, normal Roblox object/state information, HUD text, collision, character health/position/velocity, and real Touched signals, then issue ordinary keyboard and mouse input.

It must not modify candidate source or state; teleport/set character transform or velocity; call candidate RemoteEvents, Bindables, ModuleScripts, or business functions; directly fire a ProximityPrompt; or give credit solely because a Tag/Attribute exists. Valid game implementations must not rely on such shortcuts either.
