# Rift Hunting Toolchain

This file is authoritative for task-specific engine, path, entry, and environment parameters. `tools/TOOL_GUIDE.md` is authoritative for individual public interface signatures. `GDD.md` Section 6 remains the sole gameplay acceptance authority.

## Fixed environment

| Item | Value |
|---|---|
| Engine | Unreal Engine |
| Platform | desktop |
| Runtime mode | Independent `editor_game` window |
| Candidate editor target after adding source | `ArenaSliceEditor Win64 Development` |
| Project root | `starter-project/` |
| Project file | `starter-project/ArenaSlice.uproject` |
| Default map | `/Game/Arena/Maps/StarterArena` |
| Final entry | `starter-project/ArenaSlice.uproject` using its configured default map |
| Viewport | 1280 x 720 client area, windowed |
| Application scale | 1.0 |
| Marketplace plugins | Not supplied and not required |
| Shell | shell or later |

The release project is Content-only. An implementation may add a source target. Unreal-generated `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`, IDE state, logs, and packages are not release inputs.

## Portable placeholders

| Placeholder | Resolution |
|---|---|
| `<input>` | This public input copy |
| `<project>` | `<input>/project` |
| `<engine-root>` | Launcher-selected Unreal Engine root |
| `<benchmark-tools-root>` | Launcher-provided root containing `engine/unreal-Unreal/` |
| `<run-root>` | Fresh launcher-owned evidence directory outside `<input>` |

Never replace these placeholders in a committed file with a host absolute path.

Resolve the engine with `pwsh -NoProfile -File tools/Resolve-Unreal56.ps1`; the result validates UE 5.6.1 (CL 44394996) and supplies the editor, commandlet, and Build.bat paths.

## Build entry

If the candidate adds source code:

```powershell
& "<engine-root>/Engine/Build/BatchFiles/Build.bat" `
  ArenaSliceEditor Win64 Development `
  "<project>/ArenaSlice.uproject" `
  -WaitMutex -NoHotReloadFromIDE
```

A Content-only candidate is validated through editor load, Data Validation, and Cook rather than an invented source target.

## Data Validation

```powershell
& "<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" `
  "<project>/ArenaSlice.uproject" `
  -run=DataValidation -ProjectOnly -unattended -nop4 -nosplash `
  -stdout -FullStdOutLogOutput
```

## Win64 Cook

```powershell
& "<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" `
  "<project>/ArenaSlice.uproject" `
  -run=Cook -TargetPlatform=Windows -Map=/Game/Arena/Maps/StarterArena `
  -unattended -nop4 -nosplash -stdout -FullStdOutLogOutput
```

Generated output must remain outside a released input snapshot.

## Public runtime entry

```powershell
Import-Module "<benchmark-tools-root>/engine/unreal-Unreal/executor/UnrealEvaluationExecutor.psm1" -Force
Import-Module "<benchmark-tools-root>/engine/unreal-Unreal/observer/UnrealEvaluationObserver.psm1" -Force
```

Use `Start-UnrealEvaluationSession` with the project file, a fresh run root, an engine-health state path, the selected engine root, and a 1280 x 720 window. Supply these candidate task-state paths:

```text
-ActionRoguelikeSnapshotPath=<absolute-snapshot-path>
-ActionRoguelikeEventsPath=<absolute-events-path>
-ForceRes
```

The launcher selects distinct absolute task-state paths inside each fresh run root and creates their parent directories. These are argument values, not fixed filenames; preserve paths containing spaces and never derive them from the project location. The executor supplies its own process token and engine-health state path. The candidate must publish the read-only files defined in `contracts/GAME_SESSION_SPEC.md` atomically. Gameplay remains reachable only through normal player input.

## Assets and write boundary

Exact supplied assets, hashes, object paths, requirement relationships, and license boundaries are in `ASSET_MANIFEST.json`, `assets/ASSET_CATALOG.json`, `assets/ASSET_CATALOG.md`, and `assets/legal/`. Only `starter-project/` is writable during generation. Launcher evidence and model-run metadata remain outside this input.

## Public smoke

Run the public health check from the input root with a new or empty external run directory:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot <input> `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

Before launching Unreal, the smoke verifies the package manifest, every public tool identity declared in `BENCHMARK_MANIFEST.json`, and the two public task-state schemas. It creates a disposable exact project copy inside `<run-root>`, runs Data Validation and the real window lifecycle against that copy, uses the executor's observer-disabled stable-window mode for this Content-only common start, obtains bounded non-black client captures before and after a true process Reopen, and verifies final process/input cleanup. Capture receipts record the actual host client size; the fixed 1280 x 720 candidate-evaluation viewport remains the separate launcher contract above. A candidate must separately publish the read-only task state described in `contracts/GAME_SESSION_SPEC.md`.

Exit code `0` means every public health assertion passed. Exit code `1` means a release or project assertion failed. Exit code `2` means parameters, tools, environment, evidence, or cleanup prevented a valid verdict. The machine result is `<run-root>/public-smoke-result.json` and follows `self-check/PublicSmoke/schemas/public-smoke-result.schema.json`. Public smoke never certifies `GDD.md` gameplay requirements.

## Policies

- Network and installation are disabled.
- External dependencies are prohibited except the launcher engine and public benchmark tools.
- Normal player input is the only gameplay-control path.
- Observation is read-only.
- Every run uses fresh evidence paths and verifies cleanup.
- Tool and environment faults remain distinct from candidate behavior.
