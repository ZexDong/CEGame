# Dockline Dispatch Public Evaluation Protocol v1

The shared controller locates real gameplay objects in valid layouts.
Tags, Attributes, and events provide identity and state mirrors. Real input is
cross-checked against character position, velocity, health, Prompts, package
position/carrying, collision, Touched, and HUD.
Names, hierarchy, coordinates, and orientation are not contractual.

## 1. Readiness

Within 12 seconds of Play, Workspace.DD_ContractVersion=dockline-dispatch-v1 and
Workspace.DD_Ready=true. Required tags, Attributes, Prompts, state, and navigation
are client-replicated. Tags identify authoritative functional instances.

## 2. Interaction

Each DD_Interactable is a BasePart with unique DD_InteractionId from the fixed
list, DD_SystemId, DD_ActionId matching its real purpose, boolean DD_Enabled
mirroring acceptance, and DD_ApproachNodeId referencing one node.
Systems are Manifest/Inbound/Inspection/Process/Secure/Measure/Label/Conveyor/
Routing/Reject/Staging/Pallet/Checkpoint/Truck/Final.
Exactly one descendant/self ProximityPrompt performs the action.
KeyboardKeyCode=E, MaxActivationDistance=7-12 studs.
Ordinary HoldDuration=0-0.35 seconds; FragileWrap=1.5; ColdCondition=2.0.
ActionText/ObjectText describes the action.
Prompts remain Enabled in AwaitingStart and InProgress so real E can test
rejections. DD_Enabled mirrors acceptance only. When false, E emits the specified
rejection and visible feedback without gameplay changes.
Completed may disable gameplay Prompts; R remains usable.
Evaluation sends real press/hold/release only, never direct Prompt API,
Remote, Bindable, or gameplay calls.

## 3. Fixed InteractionIds

Exactly one of each:

```text
Manifest.StartShift
Inbound.Pickup.Glass
Inbound.Pickup.Cold
Inbound.Pickup.Cipher
Inspection.Scanner
Process.FragileWrap
Process.ColdCondition
Secure.AuthStart
Secure.Key.Delta
Secure.Key.Alpha
Secure.Key.Charlie
Measure.Scale
Label.Printer
Conveyor.Load
Routing.Diverter.One
Routing.Diverter.Two
Conveyor.Dispatch
Reject.Return
Staging.Pickup.A
Staging.Pickup.B
Staging.Pickup.C
Pallet.Slot.Cipher
Pallet.Slot.Glass
Pallet.Slot.Cold
Pallet.SealPickup
Checkpoint.SealShelf
Truck.SealSocket
Final.Code.2
Final.Code.4
Final.Code.1
```

## 4. Tags, counts, and authoritative objects

| Tag | Count | Instance | Required ID/Attributes |
|---|---:|---|---|
| DD_CentralSpawn | 1 | BasePart/SpawnLocation | DD_ApproachNodeId |
| DD_GameState | 1 | Configuration | Section 8 |
| DD_Interactable | 30 | BasePart | Sections 2-3 |
| DD_CarryItem | 4 | BasePart/Model | DD_ItemId, DD_ItemState, DD_HolderUserId, DD_HomeStationId, DD_ApproachNodeId |
| DD_Package | 3 | BasePart/Model | Section 5 |
| DD_ItemStation | 13 | BasePart | StationId, AcceptsItemId, ApproachNodeId |
| DD_StagingBay | 3 | BasePart | BayId=A/B/C, PackageId, ApproachNodeId |
| DD_Hazard | 1 | BasePart | HazardId=ForkliftLane, Active |
| DD_SafeZone | 1 | BasePart | ZoneId=ForkliftWait |
| DD_NavNode | 18-55 | BasePart | NodeId, NodeRole |
| DD_NavLink | 20-100 | Configuration | LinkId, FromNodeId, ToNodeId, Enabled, Bidirectional |
| DD_HUDField | 13 | GuiObject | FieldId, StateSource |

CarryItemIds: GlassCrate, ColdCase, CipherBox, DispatchSeal. All four instances
exist at Ready; packages are Inbound, seal Unavailable.
DD_ItemId is a unique fixed ID. DD_ItemState mirrors DD_PackageState for packages;
the seal uses Unavailable/Available/Carried/Staged/Installed.
DD_HolderUserId is integer 0 unless carried, then the real player UserId.
DD_HomeStationId identifies the current legal Station/Bay/Pallet/installed return
position. DD_ApproachNodeId references the current reachable pickup node; even
Unavailable/Installed objects point to the nearest legal observation node.

StationIds: InboundGlass, InboundCold, InboundCipher, ScannerPad, FragileWrapPad,
ColdConditionPad, SecureAuthPad, ScalePad, LabelPad, ConveyorLoadPad, RejectBuffer,
PalletSealOutput, SealShelf (13 total).

## 5. Package Attributes

| Attribute | Type | Requirement |
|---|---|---|
| DD_PackageId | string | GlassCrate/ColdCase/CipherBox |
| DD_PackageState | string | Inbound/Carried/Scanned/Processed/Weighed/Labeled/OnConveyor/Rejected/Staged/Palletized |
| DD_RequiredProcess | string | FragileWrap/ColdCondition/SecureAuth |
| DD_RouteId | string | B/C/A as in GDD |
| DD_ExpectedWeight | number | 3/5/8 |
| DD_Scanned | boolean | Initially false |
| DD_ProcessComplete | boolean | Initially false |
| DD_MeasuredWeight | number | Initially 0; ExpectedWeight after weighing |
| DD_LabelRouteId | string | Initially None; RouteId after labeling |
| DD_HolderUserId | integer | 0 when not carried |
| DD_HomeStationId | string | Current legal return Station |
| DD_ApproachNodeId | string | Current pickup node |

PackageState summarizes progress. Scanned, ProcessComplete, MeasuredWeight, and
LabelRouteId persist through routing rejection. Progress agrees with physical
position. DispatchSeal has DD_CarryItem but not DD_Package.

## 6. Physical behavior

Carried items descend from the character or follow through Weld/Constraint/
per-frame physics within 8 studs of HumanoidRootPart. At most one is Carried.
Uncarried items have HolderUserId=0 and lie within 10 studs of their legal
HomeStation/Bay/Pallet/conveyor position.
Conveyor.Load physically places the package and clears CarryItemId.
Dispatch moves/repositions it to its correct Bay/RejectBuffer within 3 seconds
without duplication/destruction. Palletized packages occupy their slots or keep
one Installed representation and cannot be picked up.
The seal becomes Available only after PalletProgress=3.
DD_Hazard is the authoritative contact/Touched part; Safe never damages.
Scanning, processing, weighing, labeling, loading, routing, pallet, checkpoint,
seal, and code progress require real nearby player E input.

## 7. Navigation without absolute coordinates

DD_NavNode is an Anchored, noncollidable BasePart with globally unique DD_NodeId,
DD_NodeRole=Spawn/Transit/Approach/SafeWait/Checkpoint/Goal, X/Z size >=2x2 studs,
center 2.5-4.5 studs above walkable ground, and a standable point within 3 studs.

DD_NavLink is semantic Configuration, never PathfindingLink.
Use only DD_LinkId, DD_FromNodeId, DD_ToNodeId, boolean DD_Enabled, and boolean
DD_Bidirectional Attributes. References must resolve.
Do not set nonexistent Roblox Enabled, Attachment0, or Attachment1 properties.
Edges represent continuous walking routes of width >=10 studs, headroom >=8,
length <=70. Interactables, ItemStations, StagingBays, and CarryItems reference
one ApproachNodeId. The controller reads live relative positions rather than
fixed coordinates or camera angles.

## 8. DD_GameState Attributes

| Attribute | Type | New-run value |
|---|---|---|
| DD_ProtocolVersion | string | dockline-dispatch-v1 |
| DD_RunId | integer | >=1 |
| DD_RunStatus | string | AwaitingStart |
| DD_Phase | string | AwaitingStart |
| DD_CarryItemId | string | None |
| DD_GlassState | string | Inbound |
| DD_ColdState | string | Inbound |
| DD_CipherState | string | Inbound |
| DD_AuthState | string | Idle |
| DD_AuthProgress | integer | 0 |
| DD_DiverterOne | string | Left |
| DD_DiverterTwo | string | Left |
| DD_ConveyorState | string | Empty |
| DD_ConveyorPackageId | string | None |
| DD_StagedCount | integer | 0 |
| DD_RejectCount | integer | 0 |
| DD_PalletState | string | Waiting |
| DD_PalletProgress | integer | 0 |
| DD_CheckpointId | string | Start |
| DD_HazardState | string | Safe/Active according to cycle |
| DD_HazardEpoch | number | Server time at Ready |
| DD_SealInstalled | boolean | false |
| DD_FinalCodeProgress | integer | 0 |
| DD_FinalCodeDeadline | number | 0 |
| DD_ObjectiveId | string | Start.Shift |
| DD_DeathCount | integer | 0 |
| DD_RunStart | number | 0 until shift start |
| DD_FinalTime | number | 0 |
| DD_EventSeq | integer | >=1 |
| DD_LastEvent | string | RunPrepared |
| DD_LastSourceId | string | Game |
| DD_LastRejectCode | string | None |
| DD_FeedbackText | string | Nonempty |

RunStatus=AwaitingStart/InProgress/Completed.
Phase=AwaitingStart/ProcessPackages/Routing/Pallet/Dispatch/Completed.
Phase is guidance and cannot block independent legal hazard tests.

## 9. Public events

Every discrete result strictly increments DD_EventSeq, updates DD_LastEvent,
uses InteractionId/PackageId/HazardId as DD_LastSourceId, sets a non-None
DD_LastRejectCode on rejection, and synchronizes DD_FeedbackText with visible HUD.

- `RunPrepared`, `ShiftStarted`, `Restarted`
- `Rejected.NotStarted`, `Rejected.NoItem`, `Rejected.AlreadyCarrying`, `Rejected.WrongItem`, `Rejected.WrongStage`, `Rejected.Busy`
- `ItemPickedUp.GlassCrate`, `ItemPickedUp.ColdCase`, `ItemPickedUp.CipherBox`, `ItemPickedUp.DispatchSeal`
- `Package.Scanned.GlassCrate`, `Package.Scanned.ColdCase`, `Package.Scanned.CipherBox`
- `Process.WrapInterrupted`, `Process.GlassCompleted`, `Process.ColdInterrupted`, `Process.ColdCompleted`
- `Secure.Started`, `Secure.Advanced.Delta`, `Secure.Advanced.Alpha`, `Secure.Advanced.Charlie`, `Secure.Reset`, `Secure.Completed`
- `Package.Weighed.GlassCrate`, `Package.Weighed.ColdCase`, `Package.Weighed.CipherBox`
- `Package.Labeled.GlassCrate`, `Package.Labeled.ColdCase`, `Package.Labeled.CipherBox`
- `Routing.DiverterOne.Left`, `Routing.DiverterOne.Right`, `Routing.DiverterTwo.Left`, `Routing.DiverterTwo.Right`
- `Conveyor.Loaded.GlassCrate`, `Conveyor.Loaded.ColdCase`, `Conveyor.Loaded.CipherBox`
- `Conveyor.Staged.A`, `Conveyor.Staged.B`, `Conveyor.Staged.C`, `Conveyor.Rejected`, `Reject.Recovered`
- `Pallet.Installed.CipherBox`, `Pallet.Installed.GlassCrate`, `Pallet.Installed.ColdCase`, `Pallet.Completed`
- `CheckpointActivated.SealShelf`, `CheckpointSealPickedUp`
- `Hazard.Safe`, `Hazard.Active`, `HazardTriggered.ForkliftLane`, `Respawned.Start`, `Respawned.SealShelf`
- `Truck.SealInstalled`, `Final.Advanced.2`, `Final.Advanced.4`, `Final.Advanced.1`, `Final.Reset.WrongOrder`, `Final.Reset.Timeout`, `Completed`

A continuous hold need not emit every frame; emit start, interruption, completion.

## 10. HUD

Exactly one visible DD_HUDField for each Objective, Shift, Packages, CarryItem,
Scanner, Auth, Routing, Conveyor, Pallet, Hazard, Checkpoint, Timer, Feedback.
StateSource references section 8, package Attributes, or an explicit combination.
Evaluation reads Text, Visible, AbsolutePosition, AbsoluteSize,
TextTransparency, and occlusion. Do not tag hidden substitutes.

## 11. Timing and tolerances

Ready <=12 seconds; ordinary HoldDuration 0-0.35 seconds.
FragileWrap=1.5 +/-0.2 seconds; ColdCondition=2.0 +/-0.2.
Early release stops processing within 0.25 seconds without completion.
Conveyor resolves within 3 seconds. Feedback remains visible >=1.5 seconds.
Hazard-contact death <=1 second; R restart <=2 seconds.
Hazard cycle=7 seconds: Safe 3, Active 4, transition tolerance +/-0.25.
Final code window=20 +/-0.5 seconds.
WalkSpeed=16 normally or 13 carrying the seal, tolerance +/-0.5.

## 12. Evaluator boundary

Allowed: read public objects, Attributes, Prompts, positions, velocities, health,
collision, Touched, and HUD; use Windows SendInput/equivalent normal input;
read live relative navigation positions; passively listen to events/contact.
Forbidden: edit source/state; set character CFrame/Pivot/velocity; teleport; call
candidate Remote/Module/Bindable/gameplay functions; directly fire Prompts; forge
Touched; infer success from tags/Attributes alone; use screenshots/LLMs to judge
gameplay; or control using fixed coordinates/routes/camera angles.
