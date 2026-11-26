# Unreal Engine Benchmark Tool Guide

This public guide documents individual validated benchmark interfaces for Unreal Engine and points to the complete engine-and-plugin interface catalog. It is not a gameplay recipe, evaluator, score definition, task pipeline, or reference implementation. Task-specific paths remain in `tools/TOOLCHAIN.md`, and gameplay acceptance remains solely in `GDD.md` Section 6.

## Published Capability Identity

| Field | Value |
|---|---|
| Engine | Unreal Engine, configured engine build |
| Platform | desktop |
| Runtime mode | Independent `editor_game` window |
| Compiler | v143 toolset `14.44.35207`; MSVC `19.44.35228` |
| Capability contract | `engine/unreal-Unreal/CAPABILITIES.md`, contract `1.0.0` |
| Executor module | `engine/unreal-Unreal/executor/UnrealEvaluationExecutor.psm1` |
| Native interop | `engine/unreal-Unreal/executor/Private/WindowsEvaluationNative.cs`, version `1.1.0` |
| Observer module | `engine/unreal-Unreal/observer/UnrealEvaluationObserver.psm1` |
| Operation envelope | `engine/unreal-Unreal/executor/schemas/operation-result.schema.json` |
| Engine-health schema | `engine/unreal-Unreal/executor/schemas/state-snapshot.schema.json` |

The validation summary is an engine-level fact. It does not certify any Captain's Key Run gameplay behavior. A caller resolves `<benchmark-tools-root>` to a public repository copy containing the published engine modules; host-specific paths must not be committed to this input.

## Complete Unreal Engine and Installed-Plugin Interface Catalog

The adjacent `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json` and `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz` form the version-bound all-interface catalog for Unreal Engine 5.7.4 changelist 51494982 on Windows x64 in `editor_game` mode.

The catalog contains 546,387 independently addressable records extracted from 74,084 Unreal Engine source/header files, engine configuration defaults, reflection macros, console registrations, UnrealBuildTool and AutomationTool commands, and every installed engine plugin descriptor and module. It includes public C++ callables, reflected classes, interfaces, structures, enums, Blueprint-callable functions and properties, delegates/events, console commands and variables, configuration settings, build-tool modes, and plugin descriptors/modules.

Every record contains a name, purpose, owner/version, engine-relative source, exact entry, parameters, preconditions, return/result, faults, side effects, a minimal single-interface example, validation status, validation description, and limitations. Engine source bodies, third-party source bodies, host paths, evaluator rules, and task solutions are not copied.

Query the compressed catalog without extracting it:

```powershell
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Name 'OpenLevel' -Limit 20
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Kind 'console_variable' -Name 'r.Shadow' -Limit 50
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Owner 'Paper2D' -Limit 50
```

Static catalog entries are `documented_not_validated` unless their source surface is unsupported on Windows, in which case they are `unsupported_in_target_environment`. The validated benchmark interfaces described below have separate dynamic evidence. The catalog documents one interface per record and does not provide a multi-interface task solution.

## Common operation envelope

Every operation returns an object with `operation`, `status`, `input_dispatched`, `feedback_observed`, `target_visible`, `executor_fault`, `environment_fault`, `unsupported`, `result`, `fault`, and `evidence` fields as defined by the operation-result schema. `status` is one of `ok`, `timeout`, `executor_fault`, `environment_fault`, or `unsupported`. A successful input receipt means that the executor inserted an input edge into the bound window; it does not prove that the game consumed it. Evidence paths are run-relative and must not be copied into the public input.

The executor owns one active input lease. Callers must release every held key or mouse button in a `finally` block and must stop each acquired session, including after an exception. Observer calls are read-only and never mutate the game.

## 1. Start-UnrealEvaluationSession

**Purpose:** Start one independent Unreal game window, bind its process and top-level window, and establish the engine-health state transport.

**Exact entry:** `Start-UnrealEvaluationSession` from `UnrealEvaluationExecutor.psm1`.

**Parameters:** Required `ProjectPath:string`, `RunRoot:string`; provide `StatePath:string` (inside `RunRoot`), and one engine selector: `EngineReference:object`, `EngineRoot:string`, or `EditorPath:string`. Optional `LauncherManifestPath:string`, `ProcessToken:string`, `WindowWidth:int=1280` (320–16384), `WindowHeight:int=720` (240–16384), `TimeoutMs:int=60000` (1000–300000), `FocusTimeoutMs:int=1500` (0–10000), `ObserverDisabledControl:switch`, and `AdditionalArguments:string[]`.

**Preconditions:** Windows, a valid `.uproject`, a new run root, a resolvable Unreal Engine editor, and neutral controlled keyboard/pointer state. The state parent must already exist and be inside the run root. For this task, pass `-EvalGameStatePath=<run-root>/state/game-state.json` and `-ForceRes` as additional arguments; the task path must differ from `StatePath`, and `-ForceRes` applies the requested client size.

**Result:** The common envelope with `result.session`, `session_id`, `process_id`, `process_token`, `window_handle_token`, `client_size`, `coordinate_space`, `window_dpi`, `state_path`, `initial_snapshot_id`, `initial_round_id`, `state_first_frame_confirmed`, `stable_visible_frame_confirmed`, `launch_mode`, and process containment information.

**Faults:** Invalid starter-project/run/state paths, engine selection failures, stale state conflicts, non-neutral input, process/window discovery failures, foreground or first-frame timeouts, and job/watchdog initialization failures. Stable public fault codes are listed under `Start` in the capability contract.

**Side effects:** Starts a child process tree, acquires the input lease, removes a stale regular state file, and causes the game to publish its engine-health snapshot. It does not call task gameplay.

**Minimal example:**

```powershell
$sessionResult = Start-UnrealEvaluationSession `
  -ProjectPath '<input>/starter-project/Captain2DScaffold.uproject' `
  -RunRoot '<run-root>' `
  -StatePath '<run-root>/state/engine-health.json' `
  -ProcessToken 'run-process-001' `
  -EngineRoot '<engine-root>' `
  -WindowWidth 1280 -WindowHeight 720 `
  -AdditionalArguments @('-EvalGameStatePath=<run-root>/state/game-state.json', '-ForceRes')
```


**Limitations:** `stable_visible_frame_confirmed` in the receipt is not a substitute for a later capture/probe. The control mode deliberately has no observer state evidence. The executor is Windows-only. UnrealBuildTool on Windows can reject an otherwise valid source build when the project copy is placed so deeply that generated action paths exceed the platform's supported path length; use a short writable workspace path that stays within Windows path-length limits.

## 2. Stop-UnrealEvaluationSession

**Purpose:** Close a started session and verify input, process-tree, and lease cleanup.

**Exact entry:** `Stop-UnrealEvaluationSession`.

**Parameters:** Required `Session:object`; optional `GraceTimeoutMs:int=10000` (100–120000) and `FaultCleanupTimeoutMs:int=5000` (100–30000).

**Preconditions:** A session returned by Start or Reopen is still owned by the caller. The caller has released ordinary holds where possible.

**Result:** `result.session_id`, process identity, close request and exit facts, job counts, handle state, `input_lease_released`, retry retention, and detailed `input_cleanup` (keys, buttons, cursor, watchdog, and post-check fields).

**Faults:** Missing or exited target, invalid window, close timeout, input/watchdog cleanup failure, job-handle failure, lease failure, or process-tree cleanup failure.

**Side effects:** Requests normal window close, releases controlled input, restores the pointer, closes the containment job on success, and may retain a failed session for a safe cleanup retry.

**Minimal example:**

```powershell
$stopResult = Stop-UnrealEvaluationSession -Session $sessionResult.result.session
```


**Limitations:** A forced fault cleanup or latched watchdog is not a normal success. Do not ignore a non-`ok` result or reuse a retained session without following its cleanup fields.

## 3. Invoke-UnrealPressKey

**Purpose:** Send one bounded key-down/key-up pair to the bound game window.

**Exact entry:** `Invoke-UnrealPressKey`.

**Parameters:** Required `Session:object`, `Key:string`; optional `DurationMs:int=40` (0–60000). Keys use the executor's supported Windows key names.

**Preconditions:** An active session with a valid foreground window and no held copy of the same key.

**Result:** Key, duration, down/up monotonic timestamps, and bound window/process tokens.

**Faults:** Window identity/focus failures, unsupported or already-held key, watchdog faults, and key-down/up dispatch failures.

**Side effects:** Inserts one normal input pair and always attempts the up edge. It does not read or alter task state.

**Minimal example:**

```powershell
$receipt = Invoke-UnrealPressKey -Session $session -Key 'Space' -DurationMs 40
```


**Limitations:** The receipt alone cannot establish gameplay consumption; pair it with a fresh observer snapshot and visible capture when a result matters.

## 4. Start-UnrealKeyHold

**Purpose:** Insert one bounded key-down edge and leave that key held for a caller-controlled interval.

**Exact entry:** `Start-UnrealKeyHold`.

**Parameters:** Required `Session:object`, `Key:string`.

**Preconditions:** Active session, foreground confirmation, supported key, and the key is not already held.

**Result:** `{key, edge:'down', held:true, window_handle_token, process_token}` in the common envelope.

**Faults:** Window/focus, unsupported/already-held key, watchdog, input-state, and dispatch failures.

**Side effects:** Leaves one controlled key down until Release or emergency cleanup.

**Minimal example:**

```powershell
try {
  $down = Start-UnrealKeyHold -Session $session -Key 'D'
  # Perform a bounded observation interval here.
}
finally {
  Stop-UnrealKeyHold -Session $session -Key 'D'
}
```


**Limitations:** There is no automatic total hold timeout. The caller owns the bound and the `finally` release. A host process kill is outside the native watchdog guarantee.

## 5. Stop-UnrealKeyHold

**Purpose:** Release one key previously held by the executor.

**Exact entry:** `Stop-UnrealKeyHold`.

**Parameters:** Required `Session:object`, `Key:string`; optional `Cleanup:switch` for cleanup paths.

**Preconditions:** Active session and a supported key. Normally the key is held by this session.

**Result:** `{key, edge:'up', held:false, cleanup, emergency_release, window_handle_token, process_token}`.

**Faults:** Window/focus, unsupported/not-held key, watchdog, emergency-release, and key-up dispatch failures.

**Side effects:** Sends a key-up edge and verifies controlled input where possible.

**Minimal example:**

```powershell
$up = Stop-UnrealKeyHold -Session $session -Key 'D'
```


**Limitations:** A release receipt does not prove a game-specific transition. A watchdog or emergency release can prevent stuck input but still returns a fault that must be recorded.

## 6. Move-UnrealPointer

**Purpose:** Move the controlled pointer to a normalized client-area position.

**Exact entry:** `Move-UnrealPointer`.

**Parameters:** Required `Session:object`, `NormalizedX:double` and `NormalizedY:double`, each in `[0,1]`. The origin is the upper-left client corner.

**Preconditions:** Active visible session, valid client area, foreground confirmation, and no latched watchdog fault.

**Result:** Normalized and client pixel position, coordinate space, DPI, and bound tokens.

**Faults:** Window/focus/client-area, watchdog, and pointer dispatch failures.

**Side effects:** Moves the host pointer within the bound game client area.

**Minimal example:**

```powershell
$move = Move-UnrealPointer -Session $session -NormalizedX 0.50 -NormalizedY 0.50
```


**Limitations:** The function does not locate a target or click it. Use current observer metadata only when a task exposes such metadata; do not hard-code private coordinates.

## 7. Start-UnrealMouseHold

**Purpose:** Insert one mouse-button-down edge.

**Exact entry:** `Start-UnrealMouseHold`.

**Parameters:** Required `Session:object`, `Button:string`. Supported buttons are `Left`, `Right`, `Middle`, `X1`, and `X2` plus documented aliases.

**Preconditions:** Active focused session, supported button, and button not already held.

**Result:** `{button, edge:'down', held:true, window_handle_token, process_token}`.

**Faults:** Window/focus, unsupported/already-held button, watchdog, input-state, and dispatch failures.

**Side effects:** Leaves one controlled button down until MouseUp or cleanup.

**Minimal example:**

```powershell
try {
  $mouseDown = Start-UnrealMouseHold -Session $session -Button 'Left'
}
finally {
  Stop-UnrealMouseHold -Session $session -Button 'Left'
}
```


**Limitations:** There is no total hold timeout; callers must use a bounded interval and `finally` release.

## 8. Stop-UnrealMouseHold

**Purpose:** Release one mouse button held by the executor.

**Exact entry:** `Stop-UnrealMouseHold`.

**Parameters:** Required `Session:object`, `Button:string`; optional `Cleanup:switch`.

**Preconditions:** Active session and supported button.

**Result:** `{button, edge:'up', held:false, cleanup, emergency_release, window_handle_token, process_token}`.

**Faults:** Window/focus, unsupported/not-held button, watchdog, emergency-release, and dispatch failures.

**Side effects:** Sends button-up and performs controlled-input cleanup checks.

**Minimal example:**

```powershell
$mouseUp = Stop-UnrealMouseHold -Session $session -Button 'Left'
```


**Limitations:** A non-`ok` cleanup result must remain an executor fault, not a candidate result.

## 9. Invoke-UnrealClick

**Purpose:** Move, press, and release one mouse button at a normalized client position.

**Exact entry:** `Invoke-UnrealClick`.

**Parameters:** Required `Session:object`, `NormalizedX:double`, `NormalizedY:double` in `[0,1]`; optional `Button:string='Left'`, `DurationMs:int=40` (0–60000).

**Preconditions:** Active visible session and a position chosen from current public visibility metadata or a player-visible interaction; no `TargetId` is accepted.

**Result:** Position, client coordinates, button, duration, and bound tokens.

**Faults:** Inherits MovePointer, MouseDown, and MouseUp faults.

**Side effects:** Performs one normal click and releases the button in a `finally` path.

**Minimal example:**

```powershell
$click = Invoke-UnrealClick -Session $session -NormalizedX 0.50 -NormalizedY 0.50
```


**Limitations:** The executor does not claim that a click hit a gameplay object. Confirm hit behavior independently from fresh state and visible feedback.

## 10. Invoke-UnrealDrag

**Purpose:** Perform one bounded pointer drag from a normalized start to end position.

**Exact entry:** `Invoke-UnrealDrag`.

**Parameters:** Required `Session:object`, `StartX`, `StartY`, `EndX`, `EndY:double` in `[0,1]`; optional `Button:string='Left'`, `DurationMs:int=500` (1–60000), `Steps:int=10` (1–1000).

**Preconditions:** Active visible session, valid client area, and a caller-selected public target range.

**Result:** Start/end positions and an array of per-step monotonic/client-coordinate receipts.

**Faults:** Inherits pointer and mouse hold faults, including any mid-drag window or watchdog failure.

**Side effects:** Sends down, each planned move, and up; the button is released in cleanup.

**Minimal example:**

```powershell
$drag = Invoke-UnrealDrag -Session $session `
  -StartX 0.25 -StartY 0.50 -EndX 0.75 -EndY 0.50 `
  -Button 'Left' -DurationMs 500 -Steps 10
```


**Limitations:** `DurationMs` and `Steps` plan intervals; they are not a hard total timeout. This task does not require drag behavior.

## 11. Find-UnrealVisibleTarget

**Purpose:** Read one currently published visible-target metadata record without moving or activating it.

**Exact entry:** `Find-UnrealVisibleTarget` from `UnrealEvaluationObserver.psm1`.

**Parameters:** Either `Snapshot:object` or `StatePath:string` plus `ExpectedProcessToken:string`; both forms require `TargetId:string`. Optional `MaxAgeMs:int=2000` (1–600000), `ExpectedProcessId:int`, `ExpectedRoundId:string`, and `ExpectedObjectId:string`.

**Preconditions:** A complete, fresh state snapshot that follows the observer schema and identity contract.

**Result:** `found`, `usable`, `classification`, target/object IDs, normalized bounds, `visible`, `enabled`, `topmost`, activation metadata, source identities, and freshness.

**Faults:** Invalid or stale snapshot, identity mismatch, ambiguous/invalid target metadata, and out-of-range bounds. A missing target is a healthy `status=ok` result with `found=false`, not an executor fault.

**Side effects:** None; this is a single read-only operation.

**Minimal example:**

```powershell
$state = Read-UnrealEvaluationState -StatePath '<run-root>/state/engine-health.json' `
  -ExpectedProcessToken $sessionResult.result.process_token
$target = Find-UnrealVisibleTarget -Snapshot $state.result.snapshot -TargetId 'public-health-marker'
```


**Limitations:** It only interprets metadata the running project actually publishes. It does not prove pixel-level visibility, gameplay reachability, or an interaction result.

## 12. Read-UnrealEvaluationState

**Purpose:** Read one fresh, atomic engine-level state snapshot.

**Exact entry:** `Read-UnrealEvaluationState`.

**Parameters:** Required `StatePath:string`, `ExpectedProcessToken:string`; optional `MaxAgeMs:int=2000` (1–600000), `ExpectedProcessId:int`, `ExpectedRoundId:string`, `ExpectedObjectId:string`, `MinimumSnapshotId:long`, `MinimumMonotonicMs:double`, and `MaxSnapshotBytes:int=1048576` (256–16777216).

**Preconditions:** The launcher-provided state file is inside its run root and is written atomically by the running process.

**Result:** `snapshot`, `freshness`, `snapshot_sha256`, and `byte_length` in the common envelope.

**Faults:** Missing/unreadable path, invalid JSON/schema, identity mismatch, regressed IDs or clock, stale file, and invalid object/HUD/target data.

**Side effects:** None; one bounded file read only.

**Minimal example:**

```powershell
$read = Read-UnrealEvaluationState -StatePath '<run-root>/state/engine-health.json' `
  -ExpectedProcessToken $sessionResult.result.process_token -MaxAgeMs 2000
```


**Limitations:** This interface reads the engine-health schema. Captain's Key Run task truth uses the separate `EvalGameStatePath` transport and `contracts/game-state.schema.json`; a task consumer must validate that file separately.

## 13. Wait-UnrealEvaluationCondition

**Purpose:** Poll a state path with a bounded Boolean predicate and retain the sampled evidence.

**Exact entry:** `Wait-UnrealEvaluationCondition`.

**Parameters:** Required `StatePath:string`, `ExpectedProcessToken:string`, `Predicate:scriptblock`, `TimeoutMs:int` (1–600000), `IntervalMs:int` (1–60000), and `MaxSamples:int` (1–10000). Optional identity arguments, `MaxAgeMs:int=2000`, `EvidencePath:string`, and `EvidenceRoot:string`.

**Preconditions:** A valid state path and a predicate that returns exactly one Boolean for each supplied snapshot. Evidence output must be a new path inside the evidence root.

**Result:** `matched`, termination reason, monotonic start/end, elapsed time, limits, sample count, and samples. A healthy unmet predicate has `status=timeout`; no healthy sample is `unsupported`.

**Faults:** Inherits state/evidence faults and reports predicate execution or non-Boolean predicate results.

**Side effects:** Reads state repeatedly and may write a wait-sample evidence JSON at the requested run-relative path. It never writes the game.

**Minimal example:**

```powershell
$wait = Wait-UnrealEvaluationCondition -StatePath '<run-root>/state/engine-health.json' `
  -ExpectedProcessToken $sessionResult.result.process_token `
  -Predicate { param($snapshot) $snapshot.first_frame -eq $true } `
  -TimeoutMs 5000 -IntervalMs 100 -MaxSamples 60 `
  -EvidencePath '<run-root>/waits/first-frame.json' -EvidenceRoot '<run-root>'
```


**Limitations:** The first sample is immediate and both timeout and sample count bound the call. Do not use fixed sleeps as a substitute for a condition and do not treat a timeout as a candidate failure when the state transport itself was unhealthy.

## 14. Save-UnrealClientCapture

**Purpose:** Save one PNG of the currently bound game client area.

**Exact entry:** `Save-UnrealClientCapture`.

**Parameters:** Required `Session:object`, `OutputPath:string` inside the run root; optional `ArtifactId:string='capture-<guid>'` matching the stable ID pattern.

**Preconditions:** Active visible session, fresh output path that does not exist, valid client area, and no reparse-point ancestor.

**Result:** Artifact identity, width/height, window/process tokens, client-only flag, foreground and coordinate facts, DPI, exposure samples, and a capture evidence reference.

**Faults:** Window/focus/watchdog, invalid or escaping output path, existing output, reparse ancestor, capture environment/bound transaction, and PNG integrity failures.

**Side effects:** Writes one new PNG and its operation receipt under the caller's run root. It never captures the desktop.

**Minimal example:**

```powershell
$capture = Save-UnrealClientCapture -Session $session `
  -OutputPath '<run-root>/captures/health-frame.png' -ArtifactId 'health-frame-01'
```


**Limitations:** Exposure sampling is not a mathematical proof that every pixel is unobstructed. A capture cannot establish hidden game state or a gameplay verdict.

## 15. Restart-UnrealEvaluationSession

**Purpose:** Send one public player restart activation through either a key or a visible click.

**Exact entry:** `Restart-UnrealEvaluationSession`.

**Parameters:** Required `Session:object`; use the key parameter set `Key:string='R'`, or the click parameter set with `NormalizedX/Y:double` in `[0,1]` and optional `Button:string='Left'`.

**Preconditions:** The session is active and the chosen activation is a documented normal player input. The caller must observe the resulting state separately.

**Result:** `activation_kind`, primitive input receipt, and `restart_feedback_requires_observer=true`.

**Faults:** Inherits the selected key or click operation faults.

**Side effects:** Sends only the public input; it does not call a restart function or alter state directly.

**Minimal example:**

```powershell
$restart = Restart-UnrealEvaluationSession -Session $session -Key 'R'
```


**Limitations:** The operation's `ok` status does not prove a game reset. Confirm a fresh state identity and player-visible reset using bounded observation.

## 16. Reopen-UnrealEvaluationSession

**Purpose:** Stop the old process and start a new process through the same public entry.

**Exact entry:** `Reopen-UnrealEvaluationSession`.

**Parameters:** Required `Session:object`; optional `GraceTimeoutMs:int=10000` (100–120000) and `StartTimeoutMs:int=60000` (1000–300000). The session's original launch configuration is reused.

**Preconditions:** A valid active session and a healthy engine selector/configuration retained by that session.

**Result:** Old stop attempts and identity, normal-stop confirmation, then a new session, process ID, process token, window token, state path, initial snapshot identity, and containment facts.

**Faults:** Missing session, old-stop/cleanup failure, unchanged process identity, or any inherited Start fault.

**Side effects:** Ends the old process tree, releases and reacquires the input lease, and starts a separate process. It does not preserve or inject gameplay progress.

**Minimal example:**

```powershell
$reopen = Reopen-UnrealEvaluationSession -Session $session
```


**Limitations:** Reopen is not a map reload or PIE restart. A new process identity must be checked before interpreting its state. The operation does not itself assert persistence semantics.

## 17. UnrealBuildTool source build

**Purpose:** Compile the source target required by the public project entry.

**Exact entry:** `<engine-root>/Engine/Build/BatchFiles/Build.bat`.

**Parameters:** Positional target `Captain2DScaffoldEditor`, platform `Win64`, configuration `Development`, project `<input>/starter-project/Captain2DScaffold.uproject`; compiler selector `-CompilerVersion=14.44.35207`; switches `-WaitMutex` and `-NoHotReloadFromIDE`.

**Preconditions:** Unreal Engine with its supported Windows C++ toolchain, a writable project root, and a project path short enough for generated Windows action paths.

**Result:** Process exit code and standard output. Exit code `0` means the requested build completed; any other code requires inspection of the build output.

**Faults:** Missing engine/toolchain, invalid target/project, header or compiler error, locked output, and generated path-length rejection. Treat missing host tools as environment faults and source/compiler diagnostics as project facts.

**Side effects:** Creates or updates generated `Binaries/` and `Intermediate/` content under the writable project. These directories are never release inputs.

**Minimal example:**

```powershell
& '<engine-root>/Engine/Build/BatchFiles/Build.bat' `
  Captain2DScaffoldEditor Win64 Development `
  '<input>/starter-project/Captain2DScaffold.uproject' `
  '-CompilerVersion=14.44.35207' -WaitMutex -NoHotReloadFromIDE
```


**Limitations:** A successful build proves compilation only. It does not prove asset validation, a rendered frame, input behavior, task-state semantics, or any gameplay requirement.

## 18. Unreal Data Validation commandlet

**Purpose:** Ask Unreal to load and validate the project's discoverable assets and project references without an interactive editor session.

**Exact entry:** `<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe` with `-run=DataValidation`.

**Parameters:** Project path followed by `-run=DataValidation -unattended -nop4 -nosplash -stdout -FullStdOutLogOutput`.

**Preconditions:** A built or loadable Unreal Engine project and a writable generated-output area.

**Result:** Process exit code and commandlet log. Exit code `0` with no validation error marker is the healthy command result.

**Faults:** Engine/project load failure, missing module or plugin, invalid asset/reference, commandlet crash, and host I/O failures. Preserve the raw log outside public input.

**Side effects:** May create `Saved/`, caches, and other generated project files; it does not modify protected public documents or source assets.

**Minimal example:**

```powershell
& '<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe' `
  '<input>/starter-project/Captain2DScaffold.uproject' `
  -run=DataValidation -unattended -nop4 -nosplash -stdout -FullStdOutLogOutput
```


**Limitations:** Data Validation is not a compiler, Cook, rendered-frame test, player-input test, or gameplay verdict. Projects may define additional validators, so rerun it after relevant asset changes.

## 19. Unreal Cook commandlet

**Purpose:** Resolve and serialize the configured Windows content needed by a selected map.

**Exact entry:** `<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe` with `-run=Cook`.

**Parameters:** Project path, `-run=Cook`, `-TargetPlatform=Windows`, one public map selection such as `-Map=/Engine/Maps/Entry`, and `-unattended -nop4 -nosplash -stdout -FullStdOutLogOutput`.

**Preconditions:** A loadable Unreal Engine project, a valid selected map or configured candidate default map, and writable Cook output outside protected public files.

**Result:** Process exit code and Cook log. Exit code `0` with no Cook failure or fatal marker is the healthy command result.

**Faults:** Project/module/plugin load failure, missing package/reference, serialization or shader failure, invalid target platform, and disk/environment faults.

**Side effects:** Writes generated Cook and cache content, normally under `Saved/` and related generated directories. Those files are excluded from release input.

**Minimal example:**

```powershell
& '<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe' `
  '<input>/starter-project/Captain2DScaffold.uproject' `
  -run=Cook -TargetPlatform=Windows -Map=/Engine/Maps/Entry `
  -unattended -nop4 -nosplash -stdout -FullStdOutLogOutput
```


**Limitations:** The example selects only the starter map. A candidate that changes its default map must Cook its actual final entry. Cook success does not prove a playable frame or gameplay correctness.

## 20. AutomationTool BuildCookRun

**Purpose:** Build the Win64 game target and perform Cook, Stage, Pak, Package, and Archive after the exact-toolchain Editor target has already been built.

**Exact entry:** `<engine-root>/Engine/Build/BatchFiles/RunUAT.bat BuildCookRun`.

**Parameters:** Project path; `-NoP4`; `-Platform=Win64`; `-ClientConfig=Development`; `-SkipBuildEditor`; `-Build`; `-Cook`; `-Stage`; `-Pak`; `-Package`; `-Archive`; a fresh private `-ArchiveDirectory`; `-UTF8Output`; and `-UbtArgs=-CompilerVersion=14.44.35207`.

**Preconditions:** The Unreal Engine Editor target has already completed through Interface 17 with the same compiler selector. The project root and private archive destination are writable, and the destination is outside protected public input.

**Result:** AutomationTool exit code, build/cook/stage/package log, and a Win64 archive. Exit code `0` with `BUILD SUCCESSFUL` is the healthy command result.

**Faults:** Missing AutomationTool, compiler/toolset drift, game-target compiler or linker failure, Cook/reference failure, staging/Pak failure, invalid archive destination, or disk/environment failure.

**Side effects:** Writes generated project data and a packaged archive. These outputs are private run artifacts and are excluded from the release input.

**Minimal example:**

```powershell
& '<engine-root>/Engine/Build/BatchFiles/RunUAT.bat' BuildCookRun `
  '-project=<input>/starter-project/Captain2DScaffold.uproject' `
  -NoP4 -Platform=Win64 -ClientConfig=Development `
  -SkipBuildEditor -Build -Cook -Stage -Pak -Package -Archive `
  '-ArchiveDirectory=<run-root>/package' -UTF8Output `
  '-UbtArgs=-CompilerVersion=14.44.35207'
```


**Limitations:** The explicit Editor build and game build are separate operations. Compiler argument forwarding inside AutomationTool is not validated here. Package success does not prove gameplay correctness.

## 21. Invoke-PublicSmoke.ps1

**Purpose:** Exercise the package, build, real-frame, state, Reopen, evidence, and cleanup health contract as one public diagnostic entry.

**Exact entry:** `self-check/PublicSmoke/Invoke-PublicSmoke.ps1`.

**Parameters:** Required `InputRoot`, `EngineRoot`, `BenchmarkToolsRoot`, and a new or empty `RunRoot` outside the input.

**Preconditions:** An unmodified release input copy, Unreal Engine, the exact public executor/observer modules, an Interactive desktop, and a short fresh run path. Edited candidate projects use the individual build/run interfaces; their changed sources do not match the starter release identity gate.

**Result:** Exit code `0`, `1`, or `2` plus `<run-root>/public-smoke-result.json` following the published result schema.

**Faults:** Package/project assertion failure is exit `1`; invalid parameters, missing tools, executor/environment failure, or unverified cleanup is exit `2`. Fault details and raw output remain run-relative and outside input.

**Side effects:** Builds the writable project and writes only generated project output plus logs, state, receipts, captures, and the result under the provided run root.

**Minimal example:**

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot '<input>' -EngineRoot '<engine-root>' `
  -BenchmarkToolsRoot '<benchmark-tools-root>' -RunRoot '<run-root>'
```


**Limitations:** Public smoke is a health check only. It deliberately does not send task gameplay, evaluate a GDD requirement, produce D1–D6 values, or certify a reference implementation.

## Public fault handling

Operation fault labels describe an unsuccessful tool operation; preserve receipts and diagnose the actual cause. A missing or malformed candidate, build failure, crash, black frame, timeout or bad state provider is a candidate defect unless positive evidence identifies a tool or host fault. No interface in this guide returns a gameplay score or pass/fail verdict.


## Bundled public tool runtime

Pass the absolute `input/tools/runtime` directory as `-BenchmarkToolsRoot` to public smoke commands. It contains the versioned executor, observer, native interop and schemas. Runtime health is measured in the new smoke output; historical validation receipts are not shipped.
