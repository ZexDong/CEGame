# Captain's Key Run Toolchain

This file is authoritative for task-specific engine, project, path, and environment parameters. `tools/TOOL_GUIDE.md` documents the validated public benchmark interfaces and links the complete static interface catalog. `GDD.md` Section 6 remains the sole gameplay acceptance authority.

## Fixed Environment

| Item | Value |
|---|---|
| Engine | Unreal Engine 5.7.4, changelist 51494982 |
| Platform | Windows x64 |
| Runtime mode | Independent `editor_game` window |
| Source target | `Captain2DScaffoldEditor Win64 Development` |
| Project root | `starter-project/` |
| Project file | `starter-project/Captain2DScaffold.uproject` |
| Starter/default map | `/Engine/Maps/Entry` through `starter-project/Config/DefaultEngine.ini` |
| Final entry | `starter-project/Captain2DScaffold.uproject` using its configured default map |
| Viewport | 1280 x 720 client area, windowed |
| Application scale | 1.0 |
| Built-in plugin | `Paper2D` |
| Marketplace plugins | Not supplied and not required |
| Compiler toolset | v143 `14.44.35207`; MSVC `19.44.35228` |
| Shell | PowerShell 7 or later |

## Engine Discovery

Run `tools/Resolve-Unreal57.ps1` before editor, build, or smoke commands. It searches `UE_5_7_ROOT`, Epic Launcher's `LauncherInstalled.dat`, and the standard Program Files `UE_5.7` directory, then validates UE 5.7.4 CL 51494982 and the `UnrealEditor.exe`, `UnrealEditor-Cmd.exe`, and `Build.bat` files. The JSON output supplies `engine_root`, `editor`, `editor_cmd`, and `build`. If discovery fails, treat the environment as blocked.

The project is source-only. Unreal-generated `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`, IDE state, logs, captures, and packages are not release inputs.

## Portable Placeholders

| Placeholder | Resolution |
|---|---|
| `<input>` | This public input copy |
| `<project>` | `<input>/project` |
| `<engine-root>` | Caller-selected Unreal Engine 5.7.4 root |
| `<benchmark-tools-root>` | Caller-provided repository root containing `engine/unreal-5.7.4/` |
| `<run-root>` | Fresh evidence directory outside `<input>` |

Never replace these placeholders in a committed public file with a host absolute path.

## Complete Interface Catalog

The static catalog is bound to Unreal Engine 5.7.4 changelist 51494982, Windows x64, and `editor_game` mode:

- `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json`
- `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz`
- `tools/Search-UnrealInterfaceCatalog.ps1`

The catalog covers public C++ callables, Blueprint/reflection surfaces, delegates, console commands and variables, configuration keys, UBT/UAT modes, and installed engine plugin descriptors/modules. Entries are individually documented and marked `documented_not_validated` or `unsupported_in_target_environment`; the benchmark interfaces in the public guide have separate dynamic validation evidence.

## Project Build Entry

```powershell
& "<engine-root>/Engine/Build/BatchFiles/Build.bat" `
  Captain2DScaffoldEditor Win64 Development `
  "<project>/Captain2DScaffold.uproject" `
  '-CompilerVersion=14.44.35207' -WaitMutex -NoHotReloadFromIDE
```

Exit code `0` means UnrealBuildTool completed the requested target. Any other exit code is a build or environment fault that must be diagnosed from command output; it is not a gameplay verdict.

## Project Validation Entry

```powershell
& "<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" `
  "<project>/Captain2DScaffold.uproject" `
  -run=DataValidation -unattended -nop4 -nosplash -stdout -FullStdOutLogOutput
```

This command may write generated project files. Keep them out of protected release files and final delivery.

## Cook and Package Entry

Build the Editor target first with the project build entry. Then use AutomationTool for the Win64 game target and forward the same compiler selector through UnrealBuildTool:

```powershell
& "<engine-root>/Engine/Build/BatchFiles/RunUAT.bat" BuildCookRun `
  "-project=<project>/Captain2DScaffold.uproject" `
  -NoP4 -Platform=Win64 -ClientConfig=Development `
  -SkipBuildEditor -Build -Cook -Stage -Pak -Package -Archive `
  "-ArchiveDirectory=<run-root>/package" -UTF8Output `
  "-UbtArgs=-CompilerVersion=14.44.35207"
```

Build the Editor target explicitly before this packaging command. Package output belongs under the external run root. Cook and packaging are documented interfaces; they are not claimed as validated for this source-only room starter.

## Public Runtime Entry

The public benchmark runtime is the validated executor, not an in-editor PIE session. Resolve and import its modules from the caller-provided public-tool root:

```powershell
Import-Module "<benchmark-tools-root>/engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1" -Force
Import-Module "<benchmark-tools-root>/engine/unreal-5.7.4/observer/UnrealEvaluationObserver.psm1" -Force
```

Before import, PublicSmoke verifies the SHA-256 identities declared in `BENCHMARK_MANIFEST.json` for the capability contract, validation summary, executor, native interop source, observer, operation-result schema, and engine-state schema.

Use `Start-UnrealEvaluationSession` with the project file, a fresh run root, an engine-health state path, the selected engine root, a 1280 x 720 window, and these additional arguments:

```text
-EvalGameStatePath=<run-root>/state/game-state.json
-ForceRes
-nohighdpi
```

The executor supplies `-EvalProcessToken` and `-EvalStatePath` for the engine-health transport. The task-state argument must point to a different file. `-ForceRes` requests the client size. The starter enables per-monitor DPI awareness, including unattended runs, so Windows does not magnify the client capture.

The final candidate must retain or equivalently replace the project bridge so it publishes `provider_ready=true` and schema-valid gameplay truth at the task-state path. This public engineering contract enables evaluator interoperability, adds no gameplay requirement, and exposes no write or gameplay-control operation.

## Public Smoke Entry

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot <input> `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

The run root must be new or empty and outside the public input. Exit code `0` means all public health assertions passed. Exit code `1` means a release or project assertion failed. Exit code `2` means the smoke could not produce a valid verdict because its parameters, tools, environment, or cleanup contract were unhealthy. The result file is `<run-root>/public-smoke-result.json` and follows `self-check/PublicSmoke/schemas/public-smoke-result.schema.json`.

## Assets and Write Boundary

Source sprite sheets are under `assets/files/treasure-hunters/`; original static art layout data is under `assets/files/map/`, with the room composition design reference under `references/`. The JSON tile/decoration format is documented in `assets/files/map/README.md`. Import, slicing, collision construction, animation assembly and gameplay binding are implementation work. Required use, exact dimensions, frame facts, and hashes are in `ASSET_MANIFEST.json` and `assets/ASSET_CATALOG.json`. Copy or import them into `starter-project/Content/`; do not edit the protected source files.

Only `starter-project/` is writable within this public input. Build and runtime tools may create generated project directories, but final delivery must exclude generated output. Runtime evidence and evaluation material remain outside the input copy.

## Policies

- Network: disabled.
- Installation: prohibited.
- External dependencies: prohibited except the selected engine and caller-provided public benchmark tools.
- Plugins: built-in `Paper2D` only; no PaperZD, TypewriterPlugin, or Marketplace dependency.
- Input: normal player keyboard or mouse paths only.
- Observation: read-only snapshots and client captures only.
- Evidence: fresh run-relative paths; never overwrite existing evidence.
- Cleanup: release held inputs, stop the process tree, and verify cleanup even after a failed check.

Public interfaces report operations and faults, not gameplay pass/fail or a score. Keep tool and environment faults distinct from candidate behavior.
