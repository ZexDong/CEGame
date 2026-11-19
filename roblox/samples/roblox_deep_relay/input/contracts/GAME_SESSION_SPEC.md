# Deep Relay Public Evaluation Protocol v1

This protocol lets one controller locate real gameplay objects in valid layouts.
Tags, Attributes, and events provide identity and state mirrors. Evaluation sends
normal player input and cross-checks position, velocity, health, Prompts, carried
items, collision, Touched events, doors, and HUD.
Object names, hierarchy, and absolute coordinates are not part of the protocol.

## 1. Readiness

Within 12 seconds of Play:

- `Workspace.DR_ContractVersion = "deep-relay-v1"`.
- `Workspace.DR_Ready = true`.
- Required tags, Attributes, Prompts, and navigation nodes are replicated.
- Tags identify authoritative functional instances, never decorative substitutes.

## 2. Interaction

Each `DR_Interactable` is a BasePart with:

| Attribute | Type | Requirement |
|---|---|---|
| DR_InteractionId | string | Globally unique; from schema interaction_ids |
| DR_SystemId | string | Power/Coolant/Auth/Assembly/Airlock/Checkpoint/Final |
| DR_ActionId | string | Matches current purpose |
| DR_Enabled | boolean | Mirrors whether the action is accepted |
| DR_ApproachNodeId | string | References one DR_NavNode |

The object or its descendants contain exactly one ProximityPrompt for the action.
KeyboardKeyCode=E; MaxActivationDistance=7-12 studs.
HoldDuration is 0-0.35 seconds for ordinary actions and 2.0 seconds for
Charger/Equalizer. Coolant.Inlet/Pump use 10.0 seconds and
PromptButtonHoldBegan/PromptButtonHoldEnded; players release before completion.
ObjectText or ActionText communicates the action.
The evaluator sends normal E press/hold/release, never direct Prompt API,
Remote, Bindable, or gameplay-function calls.
When DR_Enabled=false, the Prompt may be disabled. If still enabled, interaction
must emit the required rejection event without changing state.

## 3. Semantic tags and unique IDs

| Tag | Count | Instance | Required ID/Attributes |
|---|---:|---|---|
| DR_CentralSpawn | 1 | BasePart/SpawnLocation | ApproachNodeId |
| DR_GameState | 1 | Configuration | Section 6 |
| DR_Interactable | 28 | BasePart | Section 2 |
| DR_CarryItem | 5 | BasePart/Model | ItemId, ItemType, ItemState, HolderUserId, HomeStationId |
| DR_ItemStation | 11 | BasePart | StationId, AcceptsItemType, ApproachNodeId |
| DR_AirlockDoor | 2 | BasePart | DoorId=Outer/Inner, ApproachNodeId |
| DR_Hazard | 1 | BasePart | HazardId=ArcField, Active |
| DR_SafeZone | 1 | BasePart | ZoneId=HazardWait |
| DR_NavNode | 16-40 | BasePart | NodeId, NodeRole |
| DR_NavLink | 15-80 | Configuration | LinkId, FromNodeId, ToNodeId, Enabled, Bidirectional |
| DR_HUDField | 12 | GuiObject | FieldId, StateSource |

Exactly one interactable for each ID:

```text
Power.FusePickup
Power.FuseSocket
Power.Breaker.A
Power.Breaker.B
Power.Breaker.C
Power.Charger
Power.CellPickup
Coolant.Inlet
Coolant.Pump
Coolant.Lock
Coolant.CanisterPickup
Auth.Controller
Auth.Scanner.Alpha
Auth.Scanner.Beta
Auth.Scanner.Gamma
Auth.TokenPickup
Assembly.Slot.Coolant
Assembly.Slot.Cell
Assembly.Slot.Auth
Assembly.CorePickup
Airlock.OuterControl
Airlock.Equalizer
Airlock.InnerControl
Checkpoint.CoreShelf
Final.CoreSocket
Final.Stabilizer.1
Final.Stabilizer.2
Final.Stabilizer.3
```

Fixed ItemIds: PowerFuse, ChargedCell, CoolantCanister, AuthToken, RelayCore.
All five authoritative instances exist at Ready. Unproduced items are invisible,
noninteractive, and ItemState=Unavailable. Production makes them Available at
the specified Station. Each ItemId always has one authoritative instance.

The 11 ItemStation IDs are PowerFuseRack, PowerFuseSocket, PowerOutput,
CoolantOutput, AuthOutput, AssemblyCoolant, AssemblyCell, AssemblyAuth,
AssemblyCoreOutput, CoreShelf, and FinalCoreSocket.

## 4. Authoritative physical behavior

- Carried items descend from the character or physically follow it through a
  Constraint/per-frame motion, within 8 studs of HumanoidRootPart.
- Initially PowerFuse is Available; the other four items are Unavailable until
  their module/assembly completes.
- HolderUserId=0 unless Carried; while Carried it equals the actual player UserId.
  HomeStationId references a fixed station.
- Placed items appear within 10 studs of the appropriate Station.
- Installed/consumed components use ItemState=Installed and occupy their slot,
  or hide/remove their physical representation while preserving one state record.
  They cannot be picked up again.
- Door tags identify the real blocking BaseParts. Closed doors have
  CanCollide=true; opening sets it false within 1.5 seconds. Both doors must never
  be noncollidable simultaneously.
- DR_Hazard identifies the authoritative contact/Touched part. It kills during
  Active and causes no damage during Safe.
- Real nearby player E input triggers module completion, installation,
  checkpoint activation, core installation, and final stabilization.

## 5. Navigation

Each DR_NavNode is an invisible or translucent Anchored BasePart with
CanCollide=false. DR_NodeId is globally unique; DR_NodeRole is
Spawn/Transit/Approach/SafeWait/Checkpoint/Goal.
X/Z size is at least 2x2 studs. Its center is 2.5-4.5 studs above walkable ground;
a default character can stand within 3 studs.

Each DR_NavLink is a `Configuration` with unique DR_LinkId, existing
DR_FromNodeId/DR_ToNodeId, current DR_Enabled traversability, and
DR_Bidirectional. Attachment0/Attachment1 lie within 3 studs of their nodes.
Static open edges stay enabled; doors/hazards update variable edges.
PathfindingLink has no Enabled property; this protocol does not require writing
such a property.
Adjacent nodes require a continuous ordinary walking route, width >=10 studs,
headroom >=8 studs, and edge length <=70 studs. The controller computes direction
from current node positions.
Every interactable, station, and airlock door references one ApproachNodeId from
which normal movement reaches its real Prompt or contact range.

## 6. DR_GameState Attributes

The single Configuration continuously exposes:

| Attribute | Type | New-run value |
|---|---|---|
| DR_ProtocolVersion | string | deep-relay-v1 |
| DR_RunId | integer | >=1 |
| DR_RunStatus | string | InProgress |
| DR_Phase | string | RestoreSystems |
| DR_PowerState | string | NeedFuse |
| DR_PowerBreakerProgress | integer | 0 |
| DR_CoolantState | string | Unbalanced |
| DR_CoolantPressure | number | 0 |
| DR_AuthState | string | Offline |
| DR_AuthScanProgress | integer | 0 |
| DR_AssemblyState | string | Waiting |
| DR_AssemblyProgress | integer | 0 |
| DR_CarryItemId | string | None |
| DR_AirlockState | string | OpenOuter |
| DR_CheckpointId | string | Central |
| DR_HazardState | string | Safe/Active according to cycle |
| DR_CoreInstalled | boolean | false |
| DR_StabilizerProgress | integer | 0 |
| DR_StabilizerDeadline | number | 0 |
| DR_ObjectiveId | string | Restore.AnySystem |
| DR_DeathCount | integer | 0 |
| DR_RunStart | number | Current server time |
| DR_FinalTime | number | 0 |
| DR_EventSeq | integer | >=1 |
| DR_LastEvent | string | RunStarted |
| DR_LastSourceId | string | Game |
| DR_LastRejectCode | string | None |
| DR_FeedbackText | string | Nonempty |

See EVALUATION_SCHEMA.json for all enums, ObjectiveIds, and types.

## 7. Events

Each event increments EventSeq and updates LastEvent, LastSourceId,
LastRejectCode, and FeedbackText. Show feedback in the HUD for at least 1.5 seconds.

```text
RunStarted
Restarted
ItemPickedUp.<ItemId>
ItemDropped.<ItemId>
Rejected.AlreadyCarrying
Rejected.WrongItem
Rejected.WrongStage
Power.FuseInserted
Power.BreakerAdvanced.<A|B|C>
Power.BreakerReset
Power.ChargeInterrupted
Power.Completed
Coolant.PressureChanged
Coolant.Overpressure
Coolant.NotStable
Coolant.Completed
Auth.Started
Auth.ScanAdvanced.<Alpha|Beta|Gamma>
Auth.ScanReset
Auth.Completed
Assembly.ItemInstalled.<ItemId>
Assembly.Completed
Airlock.OuterClosed
Airlock.EqualizeInterrupted
Airlock.Equalized
Airlock.InnerLocked
Airlock.InnerOpened
CheckpointActivated.CoreShelf
Hazard.Safe
Hazard.Active
HazardTriggered.ArcField
Respawned.Central
Respawned.CoreShelf
Final.CoreInstalled
Final.StabilizerAdvanced.<1|2|3>
Final.StabilizerReset.WrongOrder
Final.StabilizerReset.Timeout
Completed
```

Suffix parameters use only fixed ItemIds/node numbers above. Continuous pressure
need not increment EventSeq every frame: update Attributes/HUD every 0.25 seconds
and emit events on start, stop, overpressure, and completion.

## 8. HUD tags

Exactly one DR_HUDField for each of Objective, Systems, PowerProgress,
CoolantPressure, AuthProgress, CarryItem, AssemblyProgress, Airlock, Hazard,
Checkpoint, Timer, and Feedback: 12 total.
Tag the actual visible TextLabel/TextButton/Frame. StateSource references the
corresponding section 6 Attribute or an explicit combination.
Evaluation reads Text, Visible, AbsolutePosition, AbsoluteSize,
TextTransparency, and occlusion.

## 9. Timing and tolerances

- Ready: 12 seconds.
- Ordinary Prompt HoldDuration: 0-0.35 seconds.
- Charger/Equalizer HoldDuration: 2.0 +/-0.2 seconds.
- Coolant Inlet/Pump HoldDuration: 10.0 seconds. Pressure changes only during
  real holds and stops within 0.25 seconds of release.
- Feedback visibility: >=1.5 seconds.
- Door collision update: <=1.5 seconds.
- Hazard-contact death: <=1 second.
- R restart: <=2 seconds.
- Hazard cycle: 6 seconds, Safe 2 and Active 4; transition tolerance +/-0.25 seconds.
- Phase: `(serverTime - DR_RunStart) mod 6`; below 2 is Safe, otherwise Active.
- Final stabilization window: 30 +/-0.5 seconds.
- Carrying-core WalkSpeed: 12 +/-0.5; normal WalkSpeed: 16 +/-0.5.

## 10. Evaluator boundary

Allowed: read public objects, Attributes, Prompts, positions, velocities, health,
collision, Touched, and HUD; control normal input through SendInput; passively
listen to events and contact.
Forbidden: edit candidate source/business state; set CFrame/Pivot/velocity;
teleport; call candidate Remote/Module/Bindable/gameplay functions; directly fire
Prompts; forge Touched; infer gameplay success from tags/Attributes alone; or use
screenshots/LLMs to determine gameplay-state or rule verdicts.
