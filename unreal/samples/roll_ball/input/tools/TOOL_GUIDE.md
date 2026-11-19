# Unreal Engine 5.7.4 Benchmark Tool Guide

This is the task's public, single-interface guide for the published Unreal benchmark surface. It documents interfaces that a candidate or launcher may call independently; it is not a gameplay recipe, evaluator, score definition, or reference implementation. Task-specific paths remain in `tools/TOOLCHAIN.md`, and gameplay acceptance remains solely in `GDD.md` Section 6.

## Published capability identity

| Field | Value |
|---|---|
| Engine | Unreal Engine 5.7.4, changelist 51494982 |
| Platform | Windows x64 |
| Runtime mode | Independent `editor_game` window |
| Capability contract | `engine/unreal-5.7.4/CAPABILITIES.md`, contract `1.0.0` |
| Executor module | `engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1` |
| Native interop | `engine/unreal-5.7.4/executor/Private/WindowsEvaluationNative.cs` |
| Observer module | `engine/unreal-5.7.4/observer/UnrealEvaluationObserver.psm1` |
| Operation envelope | `engine/unreal-5.7.4/executor/schemas/operation-result.schema.json` |
| Engine-health schema | `engine/unreal-5.7.4/executor/schemas/state-snapshot.schema.json` |

Run the public smoke on the current host; keep its results outside the release.

## Complete UE 5.7.4 and installed-plugin interface catalog

The adjacent `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json` and `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz` form the version-bound all-interface catalog. It contains 546,387 independently addressable records extracted from 74,084 UE 5.7.4 source/header files, engine config defaults, reflection macros, console registrations, UBT/UAT commands, and every installed engine plugin descriptor and module.

Every record contains name, purpose, owner/version, engine-relative source, exact entry, parameters, preconditions, return/result, faults, side effects, a minimal single-interface example, validation status, validation description, and limitations. Third-party source bodies, engine source bodies, host paths, evaluator rules, and task solutions are not copied.

Query the compressed catalog without extracting it:

```powershell
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Name 'OpenLevel' -Limit 20
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Kind 'console_variable' -Name 'r.Shadow' -Limit 50
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Owner 'EnhancedInput' -Limit 50
```

Catalog entries are `documented_not_validated` unless their source surface is unsupported on Windows. The 16 executor/observer interfaces below are separately `validated` by the published capability run. The catalog is an interface reference, not a multi-interface pipeline or task solution.

## Common operation envelope

Every public executor/observer operation returns an object with `operation`, `status`, `input_dispatched`, `feedback_observed`, `target_visible`, `executor_fault`, `environment_fault`, `unsupported`, `result`, `fault`, and `evidence` fields. `status` is `ok`, `timeout`, `executor_fault`, `environment_fault`, or `unsupported`.

An input receipt proves only that an input edge was inserted into the bound window. It does not prove that the game consumed the input. Gameplay conclusions require fresh read-only state and contemporaneous client capture. Evidence paths are run-relative and must remain outside the frozen input.

The executor owns one active input lease. Release every held key or mouse button in `finally`, and stop every acquired session even after an exception.

## Validated public interfaces

### 1. `Start-UnrealEvaluationSession`

- **Purpose:** Start an independent Unreal game window, bind its process and top-level window, acquire the input lease, and establish engine-health observation.
- **Required:** `ProjectPath`, `RunRoot`, `StatePath`, and one of `EngineReference`, `EngineRoot`, or `EditorPath`.
- **Optional:** `ProcessToken`, `WindowWidth=1280`, `WindowHeight=720`, `TimeoutMs=60000`, `FocusTimeoutMs=1500`, `ObserverDisabledControl`, `AdditionalArguments`.
- **Result:** Public session handle, process/window tokens, client size, DPI/coordinate space, state identity, launch mode, and containment facts.
- **Limitations:** Windows and UE 5.7.4 `editor_game` only. Control mode proves window health but not observer state.

```powershell
$start = Start-UnrealEvaluationSession `
  -ProjectPath '<input>/starter-project/RollBallStarter.uproject' `
  -RunRoot '<run-root>' `
  -StatePath '<run-root>/state/engine-health.json' `
  -EngineRoot '<engine-root>' `
  -WindowWidth 1280 -WindowHeight 720
```

### 2. `Stop-UnrealEvaluationSession`

- **Purpose:** Release controlled input, request normal window close, confirm process-tree exit, and release the input lease.
- **Required:** `Session`.
- **Optional:** `GraceTimeoutMs=10000`, `FaultCleanupTimeoutMs=5000`.
- **Limitation:** A forced cleanup or latched watchdog remains a fault even if it prevents stuck input.

### 3. `Invoke-UnrealPressKey`

- **Purpose:** Send one bounded key-down/key-up pair.
- **Required:** `Session`, `Key`.
- **Optional:** `DurationMs=40`.
- **Limitation:** Receipt alone does not prove gameplay consumption.

### 4. `Start-UnrealKeyHold`

- **Purpose:** Send one key-down edge for a caller-bounded hold.
- **Required:** `Session`, `Key`.
- **Limitation:** No automatic total hold timeout; always pair with release in `finally`.

### 5. `Stop-UnrealKeyHold`

- **Purpose:** Release a key held by the session.
- **Required:** `Session`, `Key`.
- **Optional:** `Cleanup` for cleanup paths.

```powershell
try {
  Start-UnrealKeyHold -Session $session -Key 'W'
  # Observe for a bounded interval.
}
finally {
  Stop-UnrealKeyHold -Session $session -Key 'W'
}
```

### 6. `Move-UnrealPointer`

- **Purpose:** Move the host pointer to a normalized client-area position.
- **Required:** `Session`, `NormalizedX`, `NormalizedY`, each in `[0,1]`.
- **Limitation:** Does not locate or click a semantic target.

### 7. `Start-UnrealMouseHold`

- **Purpose:** Send one mouse-button-down edge.
- **Required:** `Session`, `Button` (`Left`, `Right`, `Middle`, `X1`, or `X2`).
- **Limitation:** Pair with `Stop-UnrealMouseHold` in `finally`.

### 8. `Stop-UnrealMouseHold`

- **Purpose:** Release a mouse button held by the session.
- **Required:** `Session`, `Button`.
- **Optional:** `Cleanup`.

### 9. `Invoke-UnrealClick`

- **Purpose:** Move, press, and release at one normalized client point.
- **Required:** `Session`, `NormalizedX`, `NormalizedY`.
- **Optional:** `Button=Left`, `DurationMs=40`.
- **Limitation:** Does not accept a target ID; discover current bounds before clicking.

### 10. `Invoke-UnrealDrag`

- **Purpose:** Perform one bounded normalized pointer drag.
- **Required:** `Session`, `StartX`, `StartY`, `EndX`, `EndY`.
- **Optional:** `Button=Left`, `DurationMs=500`, `Steps=10`.

### 11. `Find-UnrealVisibleTarget`

- **Purpose:** Read one current semantic target from a task-published snapshot.
- **Required:** A `Snapshot` or `StatePath`/`ExpectedProcessToken`, plus `TargetId`.
- **Optional:** freshness and expected identity fields.
- **Limitation:** Read-only; it does not move the pointer or click.

### 12. `Read-UnrealEvaluationState`

- **Purpose:** Read and validate one atomic engine-health snapshot.
- **Required:** `StatePath`, `ExpectedProcessToken`.
- **Optional:** maximum age, expected process/round/object identity, minimum IDs/times, maximum bytes.
- **Limitation:** Single read; no polling or gameplay interpretation.

### 13. `Wait-UnrealEvaluationCondition`

- **Purpose:** Poll read-only snapshots until one Boolean predicate matches or a bound is reached.
- **Required:** state identity, `Predicate`, `TimeoutMs`, `IntervalMs`, `MaxSamples`.
- **Optional:** evidence output and expected identities.
- **Limitation:** The predicate must return exactly one Boolean and must not mutate gameplay.

### 14. `Save-UnrealClientCapture`

- **Purpose:** Save a new PNG of the bound game client area.
- **Required:** `Session`, `OutputPath` inside the session run root.
- **Optional:** stable `ArtifactId`.
- **Limitation:** Client-only sampling does not prove that every pixel is unoccluded.

### 15. `Restart-UnrealEvaluationSession`

- **Purpose:** Send a public restart key or click without calling gameplay functions.
- **Required:** `Session`; key mode defaults to `R`, or provide click coordinates.
- **Limitation:** The function returns only the activation receipt; callers must separately observe the new round.

### 16. `Reopen-UnrealEvaluationSession`

- **Purpose:** Normally stop the old process and start a new one with a new PID/token.
- **Required:** `Session`.
- **Optional:** `GraceTimeoutMs=10000`, `StartTimeoutMs=60000`.
- **Limitation:** A failed old Stop prevents starting the new process.

## Build and commandlet interfaces

### UnrealBuildTool editor build

- **Exact entry:** `<engine-root>/Engine/Build/BatchFiles/Build.bat`.
- **Task invocation:** `RollBallStarterEditor Win64 Development <project> -WaitMutex -NoHotReloadFromIDE`.
- **Side effects:** Writes `Binaries/` and `Intermediate/` under the writable project.

### Data Validation commandlet

- **Exact entry:** `UnrealEditor-Cmd.exe <project> -run=DataValidation -ProjectOnly ...`.
- **Status:** `documented_not_validated` for the raw-mesh starter because it contains no assembled map or gameplay binary content.
- **Side effects:** May write logs, caches, and validation output outside protected release files.

### Cook commandlet

- **Exact entry:** `UnrealEditor-Cmd.exe <project> -run=Cook -TargetPlatform=Windows ...`.
- **Status:** `documented_not_validated` for this authoring-only source release.
- **Side effects:** Produces Cook and staging output; keep it outside the frozen input.

## Fault handling

Branch on the stable lowercase `fault.code` and the envelope flags, not on human-readable messages. Window binding, input dispatch, observer, capture, cleanup, environment, and unsupported faults must remain distinct from candidate gameplay failure. Never convert missing or invalid evidence into a pass or fail claim.


## Bundled public tool runtime

Pass the absolute `input/tools/runtime` directory as `-BenchmarkToolsRoot` to public smoke commands. It contains the versioned executor, observer, native interop and schemas. Runtime health is measured in the new smoke output; historical validation receipts are not shipped.
