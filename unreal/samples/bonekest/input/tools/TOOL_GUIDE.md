# Unreal Engine 5.7.4 Tool Guide

This guide documents individual tools for building, running, controlling and observing the project. Project paths and prerequisites are in `tools/TOOLCHAIN.md`; game requirements are in `GDD.md` Section 6.

## Engine and tool entry points

| Field | Value |
|---|---|
| Engine | Unreal Engine 5.7.4, changelist 51494982 |
| Platform | Windows x64 |
| Runtime mode | Independent `editor_game` window |
| Executor module | `tools/engine/executor/UnrealEvaluationExecutor.psm1` |
| Native interop | `tools/engine/executor/Private/WindowsEvaluationNative.cs` |
| Observer module | `tools/engine/observer/UnrealEvaluationObserver.psm1` |
| Operation envelope | `tools/engine/executor/schemas/operation-result.schema.json` |
| Engine-health schema | `tools/engine/executor/schemas/state-snapshot.schema.json` |

## Complete UE 5.7.4 and installed-plugin interface catalog

The adjacent `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json` and `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz` describe UE 5.7.4 interfaces: public declarations, reflected interfaces, console commands/settings, configuration, UBT/UAT commands and installed engine plugins.

Each record gives its name, purpose, owner/engine version, engine-relative declaration location, exact entry, parameters, preconditions, return/result, faults, side effects, a minimal example, platform availability and limitations.

Query the compressed catalog without extracting it:

```powershell
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Name 'OpenLevel' -Limit 20
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Kind 'console_variable' -Name 'r.Shadow' -Limit 50
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Owner 'EnhancedInput' -Limit 50
```

The availability field is `documented` for cataloged interfaces or `unavailable_on_windows` for interfaces belonging to other platform targets. Check each interface's module, process and thread prerequisites before calling it.

## Common operation envelope

Every public executor/observer operation returns an object with `operation`, `status`, `input_dispatched`, `feedback_observed`, `target_visible`, `executor_fault`, `environment_fault`, `unsupported`, `result`, `fault`, and `evidence` fields. `status` is `ok`, `timeout`, `executor_fault`, `environment_fault`, or `unsupported`.

An input receipt proves only that an input edge was inserted into the bound window. It does not prove that the game consumed the input. Gameplay conclusions require fresh read-only state and contemporaneous client capture. Evidence paths are run-relative and must remain outside input/.

The executor owns one active input lease. Release every held key or mouse button in `finally`, and stop every acquired session even after an exception.

## Runtime tools

### 1. `Start-UnrealEvaluationSession`

- **Purpose:** Start an independent Unreal game window, bind its process and top-level window, acquire the input lease, and establish engine-health observation.
- **Required:** `ProjectPath`, `RunRoot`, `StatePath`, and one of `EngineReference`, `EngineRoot`, or `EditorPath`.
- **Optional:** `ProcessToken`, `WindowWidth=1280`, `WindowHeight=720`, `TimeoutMs=60000`, `FocusTimeoutMs=1500`, `ObserverDisabledControl`, `AdditionalArguments`.
- **Result:** Public session handle, process/window tokens, client size, DPI/coordinate space, state identity, launch mode, and containment facts.
- **Limitations:** Windows and UE 5.7.4 `editor_game` only. Control mode proves window health but not observer state.

```powershell
$start = Start-UnrealEvaluationSession `
  -ProjectPath '<input>/starter-project/BoneMaze.uproject' `
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
- **Task invocation:** `BoneMazeEditor Win64 Development -Project=<project> -WaitMutex -NoHotReloadFromIDE`.
- **Side effects:** Writes `Binaries/` and `Intermediate/` under the writable project.

### Data Validation commandlet

- **Exact entry:** `UnrealEditor-Cmd.exe <project> -run=DataValidation -ProjectOnly ...`.
- **Side effects:** May write logs, caches, and validation output outside protected input files.

### Cook commandlet

- **Exact entry:** `UnrealEditor-Cmd.exe <project> -run=Cook -TargetPlatform=Windows ...`.
- **Side effects:** Produces Cook and staging output; keep it outside input/.

## Fault handling

Use the lowercase `fault.code` and envelope flags to distinguish window, input, observation, capture, cleanup, environment and unsupported-operation faults. Input receipts report delivery to the window; confirm the response through current state and the rendered view. PublicSmoke checks starter-project/runtime health.

## Game observation transport

The engine-health schema and game observation schema describe different data.
Use `Start-UnrealEvaluationSession -ObserverDisabledControl` to bind its game window.
Use `tools/check_observation.py <snapshot.json>` to validate a game-state snapshot.
See `contracts/GAME_SESSION_SPEC.md` for its parameters, types, identity and error behavior.
No observation interface accepts input, state setters, or gameplay commands.

## Editor and build surfaces

| Interface | Entry and parameters | Preconditions and effects | Result and errors |
| --- | --- | --- | --- |
| Editor target build | `Build.bat BoneMazeEditor Win64 Development -Project=<uproject> -WaitMutex -NoHotReloadFromIDE` | Installed MSVC/SDK; writes Binaries and Intermediate | Exit 0 on build success; compiler diagnostics otherwise |
| Python commandlet | `UnrealEditor-Cmd.exe <uproject> -run=pythonscript -script=<script> -unattended` | PythonScriptPlugin enabled; an editor script may save assets | Exit code and Python log; exception on unsupported property or invalid package |
| Asset validation | `UnrealEditor-Cmd.exe <uproject> -run=DataValidation -ProjectOnly -unattended -NullRHI` | Accessible project assets; writes logs | Nonzero on validation failure; does not prove rendering |
| Cook | `UnrealEditor-Cmd.exe <uproject> -run=Cook -TargetPlatform=Windows -unattended` | Buildable project and content; writes Saved/Cooked | Missing imports and compile failures are errors |
| Editor asset library | `unreal.EditorAssetLibrary.load_asset(<package>)` | EditorScriptingUtilities enabled | Asset object or null; loads a package |
| Animation metadata | `unreal.AnimationLibrary.get_animation_notify_events(<sequence>)` | Editor animation library and loaded sequence | Array of notify events; no gameplay action |

The complete catalog includes all installed engine plugins, including the declared
PythonScriptPlugin and EditorScriptingUtilities, and the standard animation, particle, material,
audio and UI surfaces used by the asset collection. These two declared plugins
are editor authoring conveniences; the game has no third-party runtime plugin.
Platform restrictions and module prerequisites are listed with each interface.


## Bundled public tool runtime

Pass the absolute `input/tools/runtime` directory as `-BenchmarkToolsRoot` to public smoke commands. It contains the versioned executor, observer, native interop and schemas. Runtime health is measured in the new smoke output; historical validation receipts are not shipped.
