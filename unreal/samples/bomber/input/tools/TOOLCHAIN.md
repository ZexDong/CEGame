# Bomber Local Duel Toolchain

## Authoritative Environment

| Field | Value |
|---|---|
| Engine | Unreal Engine 5.7.4 |
| Changelist | 51494982 |
| Branch | `++UE5+Release-5.7` |
| Platform | Windows x64 |
| Runtime mode | Unreal Editor with `-game`, 1280x720 window |
| Project root | `starter-project/` |
| Project file | `starter-project/BomberStarter.uproject` |
| Starter/default map | `/Engine/Maps/Entry` |
| Fixed layout | `starter-project/Config/BomberArenaLayout.json` |
| Content-only asset plugin | `starter-project/Plugins/BlockoutMap/BlockoutMap.uplugin` |

Use this exact engine identity. Do not migrate to another version. Host-specific engine installation paths must not be written into the project or public documents.

## Engine Discovery

Run `tools/Resolve-Unreal57.ps1` before any editor, build, or smoke command. The resolver searches `UE_5_7_ROOT`, Epic Launcher's `LauncherInstalled.dat`, and the standard Program Files `UE_5.7` directory. It validates `Engine/Build/Build.version` as UE 5.7.4 CL 51494982 and confirms `UnrealEditor.exe`, `UnrealEditor-Cmd.exe`, and `Build.bat`. The JSON output contains `engine_root`, `editor`, `editor_cmd`, and `build`. If no match is found, treat the environment as blocked; do not use another engine version.

## Open, Build, Run, Stop, and Reopen

```powershell
& <engine-root>/Engine/Binaries/Win64/UnrealEditor.exe starter-project/BomberStarter.uproject -NoSplash -NoP4

& <engine-root>/Engine/Build/BatchFiles/Build.bat BomberStarterEditor Win64 Development starter-project/BomberStarter.uproject -WaitMutex -NoHotReloadFromIDE

& <engine-root>/Engine/Binaries/Win64/UnrealEditor.exe starter-project/BomberStarter.uproject -game -windowed -ResX=1280 -ResY=720 -NoSplash -NoP4
```

Stop by closing the game window normally. Reopen means a genuinely new operating-system process after the prior process exits; in-process restart and level reload do not count.

## Public Runtime Arguments

The launcher may append:

```text
-EvalProcessToken=<opaque-process-token>
-EvalStatePath=<run-root>/state/engine-health.json
-EvalGameStatePath=<run-root>/state/game-state.json
```

Both outputs are read-only snapshots written outside the input copy.

## Clean Asset Kit

Exact hashes and dependencies are in `assets/ASSET_CATALOG.json`. Primary logical paths are:

```text
/BlockoutMap/BlockoutMap/Characters/Mannequins/Meshes/SKM_Quinn_Simple
/BlockoutMap/BlockoutMap/Characters/Mannequins/Materials/Quinn/MI_Quinn_01
/BlockoutMap/BlockoutMap/Characters/Mannequins/Materials/Quinn/MI_Quinn_02
/BlockoutMap/BlockoutMap/Animations/MM_Manny_Idle
/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Wall
/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Box
/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Bomb
/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Fire
/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Skate
/Game/Bomber/Meshes/SM_Bomb
/Game/Bomber/Materials/MI_Bombs/MI_Bomb_Blue
/Game/Bomber/Materials/MI_Bombs/MI_Bomb_Pink
/Game/Bomber/Materials/MI_Bombs/MI_Bomb_Silver
/Game/Bomber/Materials/MI_Bombs/MI_Bomb_Yellow
/Game/Bomber/Meshes/SM_PlayerArrowStart
/Game/Bomber/Materials/MI_PlayerArrowStart
```

The plugin is content-only. It contains no module, Blueprint, map, input mapping, AI, data registry, StateTree, game feature action, or gameplay implementation. `/Game/Bomber/SkeletalMeshes/SKEL_Bomber` is supplied as a hard dependency of the character kit.

## Writable and Protected Areas

- Writable: `starter-project/`
- Protected: everything outside `starter-project/`
- Excluded generated directories: `Binaries/`, `DerivedDataCache/`, `Intermediate/`, `Saved/`, `.vs/`, IDE files, logs, captures, packages, and evaluation evidence.

## Public Tools

Use `tools/TOOL_GUIDE.md` and the compressed interface catalog for individual engine interfaces. Query examples:

```powershell
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Name 'OpenLevel' -Limit 20
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Owner 'Engine' -Limit 50
```

Static package check:

```powershell
pwsh -NoProfile -File tools/Test-PublicInput.ps1 -InputRoot .
```

Public runtime smoke is documented in `self-check/PublicSmoke/CONTRACT.md`; it resolves UE 5.7.4 automatically when `-EngineRoot` is omitted and validates starter health only.


