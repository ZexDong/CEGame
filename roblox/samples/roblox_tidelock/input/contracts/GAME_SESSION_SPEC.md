# Tide Lock public session contract v1

`GDD.md` is the gameplay authority. `SESSION_MODEL.json` is the complete machine-readable inventory of names, counts, types, legal enum values, geometry and timing. `src/TideLockSchema.luau` contains public constants only. All names are case-sensitive.

## Entry, discovery and observation

Start a normal single-player Studio Play session. Within 12 seconds Workspace attributes are `TL_ContractVersion="tide-lock-v1"` and `TL_Ready=true`; required objects, tags, player attributes and HUD have replicated. Resolve actual Workspace instances through `CollectionService:GetTagged(tag)`, filter to the live world, then read their nonempty `TL_SemanticId`. Tags must be attached to authoritative functional objects, never decorative substitutes. HUD tags are resolved within the current player's PlayerGui.

There is no chapter-entry, Capture, Restore, state injection or session-service API. Reopen means a new ordinary Play session, not restoration of a state snapshot. Normal asynchronous actions are observed through authoritative state, real character movement/health, object appearance, HUD and telemetry; a telemetry claim alone is not completion evidence. Use the time limits and state relations in the model and GDD; do not add hidden API obligations.

## World objects

The machine model lists exact counts and identities for GameState, CentralSpawn, OrderDisplay, three Routing nodes, two Pump objects, Core.Rack/Item/Socket, Checkpoint.Transfer, three Hazard objects, four Waypoint objects and Final.Left/Right/Console. Except the GameState Model, these are real BaseParts (spawn may be a SpawnLocation). Every required object has a nonempty TL_SemanticId. Each interactive target has exactly one corresponding ProximityPrompt in itself or descendants.

Ten TL_ApproachPoint parts map to the ten IDs in `approach_target_ids` through TL_TargetSemanticId. They are Anchored, noncolliding and nontouching, may be transparent, stand on reachable ground, and never trigger gameplay. Within 3 studs of the approach center a default character must be within the target's prompt range. They cannot be inside walls, hazards, the air or inaccessible decoration.

Prompt properties: E, MaxActivationDistance 6–12, HoldDuration ≤0.4 seconds, RequiresLineOfSight false. Keep Enabled true when an action or required rejection is available; world prompts may be disabled when Failed/Completed blocks interaction. Evaluation sends ordinary E only, never a Prompt API or business call.

## Attribute details and state relations

All player attributes and enums in SESSION_MODEL are mandatory throughout the session. New run values: RunId integer ≥1; RunState Active; RoutingComplete false, RoutingProgress 0 and RoutingNext the first node ID; PressureComplete false and both pump states Idle; CoreTransferComplete/CarryingCore false; Checkpoint Central; FinalStage Locked; CompletionState InProgress; DeathCount/RetryCount 0; RunStart current server time; FinalTime 0; EventSerial integer ≥1; LastEvent RunStarted; EventDetail a nonempty string or None; FeedbackText nonempty. Actual attribute names use the TL_ prefix exactly as listed in the model.

OrderDisplay has TL_OrderCsv with each routing name exactly once and matching visible text. Nodes have TL_RoutingId, distinct TL_OrderIndex 1–3, TL_Activated boolean, TL_InitialColor Color3 and TL_InitialMaterial string. Activated count equals RoutingProgress; RoutingNext is the next node or Complete. Activation visibly changes the tagged base or directly attached light within 1 second.

Pumps have TL_PumpId, TL_PumpState matching Player state, TL_GaugeValue 0–100, TL_SafeMin=40, TL_SafeMax=60, TL_CycleSeconds=8. Running values update at least every 0.2 seconds. A visible SurfaceGui/BillboardGui or world gauge shows value, pointer/fill and safe interval. Locked freezes within the interval; Rejected returns to Idle and zero in 1 second.

Core.Item has TL_CoreState (AtRack/Carried/Installed), TL_CarrierUserId (0 when not carried, otherwise player UserId); Carried is visibly near and follows the character; Installed is visibly at the socket. The tagged Transfer part, TL_CheckpointId=Transfer, receives the real Touched that establishes the checkpoint.

Hazards have TL_HazardId, unique TL_SequenceIndex 1–3, TL_HazardState and matching TL_Active boolean, and TL_DamagePerTouch ≥100. The tagged BasePart itself is the real damaging Touched object. Each phase lasts ≥2.5 seconds; Inactive contact is harmless and Active default-character contact kills within 0.75 seconds. Waypoints have TL_SequenceIndex 0–3, Anchored true, CanCollide true, CanTouch false; they are real safe standing regions. Moving from i to i+1 crosses hazard index i+1.

Levers have TL_LeverId Left/Right and TL_LeverState Idle/Armed; Armed visibly changes the base or its direct light. Console TL_ConsoleState is Locked/Ready/Confirm/Failed/Completed and agrees with Player FinalStage and RunState. Window decisions use server time and at most 0.25-second input/replication tolerance.

Systems are independent. FinalStage is Locked before all three completion flags, then Ready. Death preserves RunId/RunStart and completed systems. Retry resets only final levers/windows/overlay and increases RetryCount. Completed arises only from real in-range console E in DualArmed's live window; FinalTime then freezes. R starts a clean run and resets world, UI and all run state. Fresh Play inherits no progress.

## HUD

PlayerGui contains exactly one TL_HUDRoot, TL_FailureOverlay and TL_CompletionOverlay GuiObject and exactly one clickable TL_RetryButton TextButton/ImageButton inside the failure overlay. Required text fields carry TL_HUDField and TL_HudRole matching all ten `hud_roles` entries. Text is readable at 1280×720. Feedback agrees with TL_FeedbackText and lasts ≥1.5 seconds. Failure overlay and Retry are visible/clickable in Failed; completion overlay is visible in Completed; otherwise each corresponding overlay is hidden.

## One-way telemetry

ReplicatedStorage contains `RemoteEvent TL_PublicTelemetry`. The server only publishes with `FireClient(player, payload)`; do not add OnServerEvent gameplay shortcuts. The evaluator listens and never calls this remote.

For each event enumerated in SESSION_MODEL, update authoritative state first or in the same Heartbeat, strictly increment TL_EventSerial, set TL_LastEvent and TL_EventDetail (involved ID/reason or None), update nonempty TL_FeedbackText, then emit:

```luau
{ serial = number, event = string, detail = string,
  runId = number, serverTime = number }
```

Payload event strings must be drawn from the complete `events` list in SESSION_MODEL. Serial numbers are increasing integers; publish only actual events. Errors/rejections leave unrelated and already accepted progress intact as specified in the GDD.

## Evaluator permissions

Read public tags/attributes/prompts/UI, character position/velocity/health, collision and object physics. Passively listen to Touched and one-way telemetry. Read-only PathfindingService queries and ordinary OS keyboard/mouse input are allowed.

Do not mutate candidate source/state, set CFrame/Pivot/velocity/health, teleport, fake Touched, or call Remote/Bindable/ModuleScript/Prompt/business functions to advance play. Tags alone do not prove functionality. D1–D5 judgments use engine observations, not screenshot or language-model gameplay judgments.
