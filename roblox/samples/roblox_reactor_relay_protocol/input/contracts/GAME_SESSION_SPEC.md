# Reactor Relay Protocol Public Evaluability Contract v1

This contract lets an independent controller observe different valid implementations and send real pointer/keyboard input without screenshots or fixed coordinates. It exposes semantic identity and player-visible state only. It does not provide gameplay shortcuts and does not itself prove that behavior is correct.

## 1. Ready condition

Within 12 seconds after Play begins:

- `Workspace.RR_ContractVersion` is the string `reactor-relay-v2-hard`.
- `Workspace.RR_Ready` is boolean `true`.
- The required tagged instances, Attributes, and visible GUI have replicated to the client.
- Tags are attached to the actual authoritative objects, not hidden stand-ins.

Instance names, parent hierarchy, screen resolution, and absolute screen coordinates are not frozen.

## 2. Real input and live engine coordinates

Every object tagged `RR_Control` is the actual visible `GuiButton` used by the player and has:

| Attribute | Type | Rule |
|---|---|---|
| `RR_TargetId` | string | Globally unique member of `control_ids` in the schema |
| `RR_Enabled` | boolean | Mirrors whether a legal click can act now |
| `RR_VisibleToPlayer` | boolean | Mirrors actual player-visible availability |

The primary action is one complete real left-button press and release inside that button. The controller may read `AbsolutePosition`, `AbsoluteSize`, `Visible`, `Active`, `Interactable`, and clipping ancestors from the engine to calculate the current on-screen center, then move the Windows pointer and click. It will not call `GuiButton:Activate()`, RemoteEvents, Bindables, modules, or business functions.

An available button must have a minimum visible hit rectangle of 44 by 32 device-independent pixels and must not be covered by another interactive object. If `RR_Enabled=false`, a click either has no effect or records the specified rejection while gameplay state remains unchanged.

## 3. Required tags and counts

| Tag | Count | Class | Identity |
|---|---:|---|---|
| `RR_GameState` | 1 | Configuration | overall run state |
| `RR_BayState` | 3 | Configuration | `RR_BayId` = A, B, or C, unique |
| `RR_Control` | 19 | GuiButton | unique `RR_TargetId` |
| `RR_HUDField` | 16 | GuiObject | unique `RR_FieldId` |

The 19 control IDs are exactly:

`start_button`, `bay_a`, `bay_b`, `bay_c`, `power_minus`, `power_plus`, `coolant_minus`, `coolant_plus`, `phase_left`, `phase_right`, `lock_button`, `arm_button`, `commit_button`, `scan_button`, `purge_button`, `sequence_a`, `sequence_b`, `sequence_c`, `restart_button`.

The 16 HUD field IDs are exactly:

`Cycle`, `Timer`, `Integrity`, `Faults`, `PowerPool`, `CoolantPool`, `ScanCharges`, `Purge`, `SelectedBay`, `Incident`, `LockProgress`, `ExpectedLockBay`, `CommitArmed`, `ArmTimer`, `SequenceProgress`, `Feedback`.

Each `RR_HUDField` must be the actual player-visible GuiObject for that information, with string Attribute `RR_FieldId` and string Attribute `RR_StateSource`. It must not tag a hidden duplicate.

## 4. Overall state Attributes

The unique `RR_GameState` Configuration continuously owns:

| Attribute | Type | New application / run value |
|---|---|---|
| `RR_ProtocolVersion` | string | `reactor-relay-v2-hard` |
| `RR_Revision` | integer number | monotonic; increases once per accepted or rejected completed action and meaningful phase transition |
| `RR_RunId` | integer number | 0 on menu; at least 1 after Start; increases on Start or Restart |
| `RR_Phase` | string | `Menu`; then `Cycle`, `Preview`, `Sequence`, `Won`, or `Lost` |
| `RR_Cycle` | integer number | 0 on menu; 1 on a new run; range 1–6 during play |
| `RR_TimeRemaining` | number | 18 at cycle start; 6 at sequence input start; 0 on menu |
| `RR_Integrity` | integer number | 100 |
| `RR_Faults` | integer number | 0 |
| `RR_UnallocatedPower` | integer number | 7 |
| `RR_UnallocatedCoolant` | integer number | 6 |
| `RR_ScanCharges` | integer number | 1 |
| `RR_PurgeAvailable` | boolean | true |
| `RR_SelectedBay` | string | `None` |
| `RR_IncidentId` | string | `None` |
| `RR_LockProgress` | integer number | 0 |
| `RR_ExpectedLockBay` | string | first bay in the frozen cycle lock order |
| `RR_CommitArmed` | boolean | false |
| `RR_CommitArmDeadline` | number | 0 |
| `RR_SequenceIndex` | integer number | 0 |
| `RR_EventSeq` | integer number | 0 on menu; at least 1 after Start |
| `RR_LastEvent` | string | `MenuReady` on menu, `RunStarted` after Start |
| `RR_LastSourceId` | string | `Game` unless an action identifies a control or bay |
| `RR_LastRejectCode` | string | `None` unless the last action was rejected |
| `RR_FeedbackText` | string | nonempty whenever an action result is being reported |

GameState values must update in the same rendered frame or within 0.25 seconds of their visible gameplay result. `RR_Revision` is a change detector, not an alternate completion signal.

## 5. Bay state Attributes

There are exactly three `RR_BayState` Configurations, one each for A, B, and C:

- `RR_BayId`: string A/B/C.
- `RR_CurrentPower`: integer 0–4.
- `RR_TargetPower`: integer 0–4.
- `RR_CurrentCoolant`: integer 0–3.
- `RR_TargetCoolant`: integer 0–3.
- `RR_CurrentPhase`: integer -2–2.
- `RR_TargetPhase`: integer -2–2.
- `RR_Status`: `UnlockedUnstable`, `UnlockedStable`, `LockedStable`, or `Faulted`.
- `RR_Locked`: boolean.
- `RR_Overloads`: nonnegative integer.

After all incident effects in each cycle, the three target-power values total no more than 7 and the three target-coolant values total no more than 6. The exact base and effective tuples are frozen in GDD Section 6.2 and `cycle_targets` in the schema. Targets remain player-visible. A controller may read them to plan clicks, but completion still requires real pointer input on the actual controls.

A matching bay remains UnlockedUnstable until all three values have matched continuously for 0.75 seconds. Any mismatch resets that interval. The frozen lock orders are Cycle 1 A/B/C, Cycle 2 B/C/A, Cycle 3 C/A/B, Cycle 4 B/A/C, Cycle 5 A/C/B, and Cycle 6 C/B/A.

## 6. Frozen logical layout

The root play canvas is exactly 1600 by 900 logical pixels. It is uniformly scaled and centered with letterboxing when the game viewport has a different size or aspect ratio. It must not stretch axes independently. Bay panel rectangles and all 19 control rectangles are exactly those in GDD Section 6.2 and `logical_layout` in the schema.

The controller still reads each actual button's live `AbsolutePosition` and `AbsoluteSize` from the engine. The frozen logical rectangles let it validate layout consistency and diagnose a missing or displaced control; they are not fixed Windows desktop coordinates.

## 7. Incidents and sequence

`RR_IncidentId` uses: `None`, `CoolantLeak.B`, `PhaseDrift.C`, `PowerSurge.A`, `DualLeak.AC`, `Crossfeed.BC`. The order and effects are exactly those in GDD requirements RULE-05 and RULE-06.

The preview and final input sequence is exactly A, C, B, A, C, B, C, A. Each preview symbol appears for 0.60 seconds with a 0.25-second blank gap. Sequence buttons are unavailable during Preview and become available only in Sequence. `RR_SequenceIndex` counts accepted symbols from 0 through 8.

An out-of-order stable lock attempt removes 10 integrity, adds one overload to that bay, unlocks all bays, resets lock progress to 0, and preserves allocations. After the correct third lock, `arm_button` becomes available. One Arm Commit click creates a non-extendable 3-second window. If Commit Cycle is not clicked in time, 10 integrity is removed, all bays unlock, lock progress resets, and allocations remain. If the 18-second cycle timer reaches zero first, only the ordinary cycle-timeout rule resolves.

## 8. Public events and rejection codes

Each completed action or important automatic transition increments `RR_EventSeq`, sets `RR_LastEvent`, `RR_LastSourceId`, `RR_LastRejectCode`, and shows `RR_FeedbackText` for at least 1 second.

Required event families:

- `MenuReady`, `RunStarted`, `Restarted`, `BaySelected.<A|B|C>`
- `PowerChanged`, `CoolantChanged`, `PhaseChanged`
- `BayStable.<A|B|C>`, `BayUnstable.<A|B|C>`, `BayLocked.<A|B|C>`
- `LockRejected.Unstable`, `AdjustmentRejected.Locked`, `AdjustmentRejected.ResourceLimit`
- `LockRejected.WrongOrder`, `LockOrderReset`, `CommitArmed`, `CommitArmExpired`, `CommitRejected.Unarmed`
- `CycleCommitted.<1..6>`, `CycleTimedOut`, `IncidentApplied.<IncidentId>`
- `IncidentScanned.<IncidentId>`, `PurgeUsed.<A|B|C>`, `PurgeRejected`
- `SequencePreviewStarted`, `SequenceInputStarted`, `SequenceAccepted.<A|B|C>`
- `Won`, `Lost.Integrity`, `Lost.Faults`, `Lost.Sequence`, `Lost.SequenceTimeout`

Rejection codes use: `None`, `WrongPhase`, `NoBaySelected`, `Locked`, `Unstable`, `ResourceLimit`, `Unavailable`, `AlreadyUsed`.

## 9. Timing and lifecycle

- Ready timeout: 12 seconds.
- Cycle timer: 18 real seconds; input, stability waiting, ordered locking, and commit arming must not pause it.
- Action/state reflection: 0.25 seconds.
- Feedback visibility: at least 1 second.
- Scan preview: 4 seconds.
- Stable-match interval: 0.75 seconds.
- Commit arm window: 3 seconds; it cannot be extended by repeated Arm Commit clicks.
- Final sequence input window: 6 seconds.
- R Clean Restart reflection: 2 seconds.
- A complete click fires at most once; press-only, release-only, drag-across, or boundary-crossing input does not fire.
- Clean Restart restores the exact CORE-02 state and resets the fixed schedule.
- Reopen shows Menu with `RR_RunId=0`, no active timer, and no restored gameplay progress.

## 10. Allowed and prohibited controller behavior

Allowed: read tagged public instances, Attributes, GUI text/visibility/geometry, and timer/state changes; move the real Windows pointer to live GuiButton coordinates; send complete mouse clicks and the R key.

Prohibited: modify source or state, call business functions/RemoteEvents/Bindables/GuiButton Activate, fabricate input or completion, directly set Attributes, use fixed screen coordinates, or use screenshots/image recognition to judge gameplay correctness.
