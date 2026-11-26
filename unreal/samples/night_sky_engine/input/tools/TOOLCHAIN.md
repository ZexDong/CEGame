# Night Sky Duel Lab Toolchain

`BENCHMARK_MANIFEST.json` is the machine-readable authority for paths and identities. This document explains the task-specific use of those facts. `GDD.md` Section 6 remains the sole gameplay acceptance authority.

## Fixed environment

| Field | Value |
|---|---|
| Engine | Unreal Engine, configured engine build, branch `++UE5+Release-5.7` |
| Engine binding precision | The task toolchain is bound to the validated Unreal Engine build. |
| Platform | desktop |
| Runtime mode | Independent `editor_game` window |
| Project | `starter-project/NightSkyDuelScaffold.uproject` |
| Editor target | `NightSkyDuelScaffoldEditor Win64 Development` |
| Game target | `NightSkyDuelScaffold Win64 Development` |
| Starter map | `/Engine/Maps/Entry` |
| Final entry | The same project using its configured `GameDefaultMap` |
| Viewport | 1280 x 720 client area, windowed, application scale 1.0 |
| Built-in plugin | `Paper2D` |
| Marketplace plugins | Not supplied and not required |
| Validated compiler family | Visual Studio 2022 v143; the baseline build used toolset 14.44.35228 and Visual C++ 19.44.35223 |
| Shell | shell or later |

The project is source-only. Unreal-generated `Binaries/`, `DerivedDataCache/`, `Intermediate/`, `Saved/`, IDE state, logs, captures, and packages are not release inputs.

## Portable placeholders

| Placeholder | Resolution |
|---|---|
| `<input>` | This public input copy |
| `<project>` | `<input>/project` |
| `<engine-root>` | Launcher-selected Unreal Engine root |
| `<benchmark-tools-root>` | Launcher-provided repository root containing `engine/unreal-Unreal/` |
| `<run-root>` | Fresh launcher-owned run and evidence directory outside `<input>` |

Never commit a host-specific replacement for these placeholders.

Resolve the engine with `pwsh -NoProfile -File tools/Resolve-Unreal57.ps1`; the result validates UE 5.7.4 (CL 51494982) and supplies the editor, commandlet, and Build.bat paths.

## Build

```powershell
& "<engine-root>/Engine/Build/BatchFiles/Build.bat" `
  NightSkyDuelScaffoldEditor Win64 Development `
  "<project>/NightSkyDuelScaffold.uproject" `
  -WaitMutex -NoHotReloadFromIDE
```

Exit code 0 means UnrealBuildTool completed that build target. It does not prove gameplay correctness.

## Optional validation

```powershell
& "<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" `
  "<project>/NightSkyDuelScaffold.uproject" `
  -run=DataValidation -unattended -nop4 -nosplash -stdout -FullStdOutLogOutput
```

This command may write generated project state. Exclude it from the submitted source snapshot.

## Optional Win64 package

```powershell
& "<engine-root>/Engine/Build/BatchFiles/RunUAT.bat" BuildCookRun `
  "-project=<project>/NightSkyDuelScaffold.uproject" `
  -NoP4 -Platform=Win64 -ClientConfig=Development `
  -Build -Cook -Stage -Pak -Package -Archive `
  "-ArchiveDirectory=<run-root>/package" -UTF8Output
```

Package output belongs outside the public input and candidate source snapshot.

## Public independent runtime

```powershell
Import-Module "<benchmark-tools-root>/engine/unreal-Unreal/executor/UnrealEvaluationExecutor.psm1" -Force
Import-Module "<benchmark-tools-root>/engine/unreal-Unreal/observer/UnrealEvaluationObserver.psm1" -Force
```

Start with a fresh run root, a separate engine-health state file, and these additional arguments:

```text
-EvalGameStatePath=<run-root>/state/duel-state.json
-ForceRes
```

The executor supplies `-EvalProcessToken` and `-EvalStatePath`. The task-state path must be a different file. The final candidate must publish `provider_ready=true` and schema-valid state at the task path while keeping the transport read-only.

Run the public smoke on the current host. Write its results outside the release.

## Public smoke

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot <input> `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

Exit code 0 means the public package and starter-health assertions passed. Exit code 1 means a release or project assertion failed. Exit code 2 means the tool, environment, or cleanup state blocked a valid smoke verdict. The smoke never certifies a GDD gameplay requirement.

## Interface catalog

The public guide documents the validated 16-operation executor and observer surface in detail. The complete engine catalog is stored in compressed JSONL and can be queried with:

```powershell
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Name <fragment> -Limit 25
```

Catalog entries are single-interface facts and are not a prescribed implementation pipeline.

## Assets and write boundary

The required Manny skeletal model and eight animations are preimported Unreal assets under `starter-project/Content/Provided/Manny/`. The corresponding art-only FBX reference files remain under `assets/files/Manny/`. Exact names, visible roles, dependencies, package paths, object paths, and hashes are in `assets/ASSET_CATALOG.json`; the readable lookup is `assets/ASSET_CATALOG.md`. Mandatory use is defined only by `ASSET-01` and `ASSET-02` in `GDD.md`.

The preimported model contains its bind Skeleton and skin weights. The animation sequences reference that Skeleton. The Skeleton asset is `/Game/Provided/Manny/SKM_Manny_Skeleton`; the source skeleton identity is `SK_Mannequin`. FBX units are centimeters. The authored animation durations are data facts, not gameplay timings. Materials and textures do not need importing; the mesh carries material slots, and candidate-authored colors are allowed. No additional plugin or graph is needed to use these assets.

Only `starter-project/` is writable during generation. Keep `assets/files/` and all other public reference files unchanged; preimported `.uasset` files are already inside `starter-project/Content/Provided/Manny/`. Runtime evidence and model-run metadata remain outside this input.

## Policies

- Network: disabled.
- Installation: prohibited.
- External dependencies: prohibited except the launcher-selected engine and public benchmark tools.
- Plugins: built-in `Paper2D` only in the starter; no Marketplace dependency.
- Input: normal player keyboard or pointer paths only.
- Observation: read-only snapshots and client captures only.
- Cleanup: release controlled inputs and stop the process tree even after failure.

Public interfaces return operation facts and fault classification, never gameplay scores or verdicts.
