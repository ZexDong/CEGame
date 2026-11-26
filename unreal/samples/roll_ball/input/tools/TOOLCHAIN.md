# RollBall Fixed Maze Toolchain

This file is authoritative for task-specific engine, path, entry, and environment parameters. `tools/TOOL_GUIDE.md` is authoritative for individual public interface signatures. `GDD.md` Section 6 remains the sole gameplay acceptance authority.

## Fixed environment

| Item | Value |
|---|---|
| Engine | Unreal Engine, configured engine build |
| Platform | desktop |
| Runtime mode | Independent `editor_game` window |
| Editor target | `RollBallStarterEditor Win64 Development` |
| Project root | `starter-project/` |
| Project file | `starter-project/RollBallStarter.uproject` |
| Default map | Starter preview only: `/Engine/Maps/Entry`; completed candidates must use a project `/Game/...` map |
| Final entry | `starter-project/RollBallStarter.uproject` using its configured default map |
| Fixed layout | `starter-project/Config/FixedRollBallLayout.json` |
| Required board floor mesh | `/Game/StarterContent/Architecture/Floor_400x400` |
| Required trap-hole mesh | `/Game/StarterContent/Architecture/Floor_400x400_Hole` |
| Required board wall mesh | `/Game/StarterContent/Architecture/Wall_400x200` |
| Required ball mesh | `/Game/StarterContent/Shapes/Shape_Sphere` |
| Viewport | 1280 x 720 client area, windowed |
| Application scale | 1.0 |
| Marketplace plugins | Not supplied and not required |
| Shell | shell or later |

## Engine discovery (required before Build/Open/Run)

The launcher may provide an engine path out of band, and model shells may not inherit that value. Resolve it explicitly:

```powershell
$engineInfo = pwsh -NoProfile -File tools/Resolve-Unreal57.ps1
$engine = ($engineInfo | ConvertFrom-Json).engine_root
```

To use a launcher-provided or manually selected path, pass `-EngineRoot <path>` or set `UE_5_7_ROOT`. The resolver checks `Engine/Build/Build.version`, `UnrealEditor.exe`, `UnrealEditor-Cmd.exe`, and `Build.bat`, and rejects every version other than Unreal Engine CL configured-build. If it fails, record the environment block; do not open the project with another engine. The `.uproject` `EngineAssociation` value identifies the 5.7 line but does not prove the Unreal patch.

The release contains the starter project plus a small cataloged raw visual mesh kit. It does not contain an assembled map, gameplay Blueprint, gameplay binary, or generated build output. Unreal-generated `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`, IDE state, logs, captures, and packages are not release inputs.

## Portable placeholders

| Placeholder | Resolution |
|---|---|
| `<input>` | This public input copy |
| `<project>` | `<input>/project` |
| `<engine-root>` | Launcher-selected Unreal Engine root |
| `<benchmark-tools-root>` | Launcher-provided root containing `engine/unreal-Unreal/` |
| `<run-root>` | Fresh launcher-owned evidence directory outside `<input>` |

Never replace these placeholders in a committed file with a host absolute path.

## Build entry

```powershell
& "<engine-root>/Engine/Build/BatchFiles/Build.bat" `
  RollBallStarterEditor Win64 Development `
  "<project>/RollBallStarter.uproject" `
  -WaitMutex -NoHotReloadFromIDE
```

## Public runtime entry

```powershell
Import-Module "<benchmark-tools-root>/engine/unreal-Unreal/executor/UnrealEvaluationExecutor.psm1" -Force
Import-Module "<benchmark-tools-root>/engine/unreal-Unreal/observer/UnrealEvaluationObserver.psm1" -Force
```

Use `Start-UnrealEvaluationSession` with the project file, a fresh run root, an engine-health state path, the selected engine root, and a 1280 x 720 window. The starter itself is checked with `-ObserverDisabledControl`. A completed candidate must additionally receive:

```text
-RollBallStatePath=<run-root>/task-state/game-state.json
```

The candidate publishes the read-only file defined in `contracts/GAME_SESSION_SPEC.md` atomically. Gameplay remains reachable only through normal player input. The state publisher reports facts and must not control gameplay.

## Data Validation and Cook

The public starter contains only raw supplied `.uasset` meshes and no project `.umap` or assembled gameplay binary, so release authoring did not require a Cook. A candidate that adds or modifies project content may use these independent interfaces:

```powershell
& "<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" `
  "<project>/RollBallStarter.uproject" `
  -run=DataValidation -ProjectOnly -unattended -nop4 -nosplash `
  -stdout -FullStdOutLogOutput
```

```powershell
& "<engine-root>/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" `
  "<project>/RollBallStarter.uproject" `
  -run=Cook -TargetPlatform=Windows `
  -unattended -nop4 -nosplash -stdout -FullStdOutLogOutput
```

Generated output must remain outside the frozen public input snapshot.

## Fixed layout usage

`starter-project/Config/FixedRollBallLayout.json` is immutable public fixture data. It uses bottom-left grid coordinates and contains:

- `grid.width`, `grid.height`, and `grid.cell_size_unreal_units`;
- `start_cell` and `exit_cell`;
- exact `trap_cells`;
- `vertical_walls`, where each `{x,y}` is the vertical wall on the left edge of cell `(x,y)` and `x=grid.width` is the right perimeter;
- `horizontal_walls`, where each `{x,y}` is the horizontal wall on the bottom edge of cell `(x,y)` and `y=grid.height` is the top perimeter.

An implementation may parse this file directly or convert it into project-authored data, but the final player-facing layout must remain identical.

## Content and write boundary

Exact supplied content, hashes, requirement relationships, and license boundaries are in `ASSET_MANIFEST.json`, `assets/ASSET_CATALOG.json`, `assets/ASSET_CATALOG.md`, and `assets/legal/ASSET_LICENSE_MAP.json`. Only `starter-project/` is writable during generation. Launcher evidence and model-run metadata remain outside this input.

## Policies

- Network and installation are disabled.
- External dependencies are prohibited except the launcher engine and public benchmark tools.
- Normal player input is the only gameplay-control path.
- Observation is read-only.
- Every run uses fresh evidence paths and verifies cleanup.
- Tool and environment faults remain distinct from candidate behavior.

/Engine/Maps/Entry is only a preview entry for the starter. A completed candidate must create a project-owned playable map and set both GameDefaultMap and EditorStartupMap to its /Game/... asset path. Runtime verification must use an independent window with valid lighting and a visible, non-black frame; record the independent run command, selected map, and state file path in the handoff/evidence.

Supplied raw meshes can reference materials that are not included in the input snapshot. Candidates must assign each required mesh a valid available material (including project-authored fallback materials where necessary); missing source materials must never leave the board, walls, traps, or ball invisible.


