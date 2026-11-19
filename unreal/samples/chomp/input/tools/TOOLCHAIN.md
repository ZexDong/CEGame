# Chomp toolchain

## Required environment and entry

Unreal Engine 5.7.4, CL 51494982; Windows x64; independent `editor_game` window. The required compiler toolchain is Visual Studio 2022 MSVC 14.44 and Windows SDK 10.0.26100.0. Engine discovery validates the exact `Engine/Build/Build.version`, editor and build tools. Supply `-EngineRoot <engine-root>` or `UE_5_7_ROOT`; the resolver also reads the Epic launcher installation manifest and a conventional installation location. It does not install or download anything.

The starter entry is `starter-project/ChompStarter.uproject`, target `ChompStarterEditor`; the standalone target is `ChompStarter`. The current default map is the installed engine's `/Engine/Maps/Entry`. A completed implementation sets its own final map in `starter-project/Config/DefaultEngine.ini`. No complete maze map is provided.

## Individual commands

```powershell
$engine = (& ./tools/Resolve-Unreal57.ps1 | ConvertFrom-Json).engine_root
$project = (Resolve-Path ./starter-project/ChompStarter.uproject).Path
& "$engine/Engine/Build/BatchFiles/Build.bat" ChompStarterEditor Win64 Development "-Project=$project" -WaitMutex -NoHotReloadFromIDE
```

Launch from a writable implementation copy:

```powershell
& "$engine/Engine/Binaries/Win64/UnrealEditor.exe" $project -game -windowed -ResX=1280 -ResY=720 -ForceRes -NoSplash -NoP4 -NoLiveCoding -culture=en
```

For read-only output append `-ChompStatePath=<absolute-run-root>/game-state.json`. The path is supplied by the caller and is outside the protected input. For reproducible choices append `-ChompSeed=1337`; the completed game accepts other integers too. The untouched starter has no random gameplay.

## Observation and viewport

`contracts/game-state.schema.json` is the task schema. Use `tools/Test-Observation.ps1 -Path <snapshot>` to validate it. The generic engine observer's fixture schema is not a substitute. The starter transport publishes at 20 Hz; the public contract permits at least 10 Hz. The game provider remains unavailable until implemented.

The capture size is 1280x720 physical client pixels, windowed. High-DPI awareness is enabled in project configuration to prevent OS bitmap stretching. Record the actual window DPI; normalized observation bounds always refer to the physical client image. Do not change host display scaling. HUD/menu layout also supports 1920x1080 per GDD. Capture only the owned client window, never the whole desktop. Normal menu Apply can change window settings; a caller's explicit viewport override applies only to that launch. No fixed private pixel coordinates are required.

## Resources and plugins

`starter-project/Content/Art/` contains supplied static presentation assets with portable metadata. Engine primitives such as `/Engine/BasicShapes/Cube.Cube` and `/Engine/BasicShapes/Sphere.Sphere` remain available from the installed engine. `starter-project/SourceArt/Meshes/` contains seven OBJ sources in centimeters; `starter-project/SourceArt/Textures/` contains the PNG wall-edge source; `starter-project/SourceArt/UI/` contains SVG/PNG life-icon sources. `starter-project/Content/Art/UI/T_LifeIcon.uasset` is a ready-to-use 128x128 texture with alpha and UI settings. The imported mesh/texture reimport metadata resolves to these project-local sources. Matching reference copies remain in `assets/files/raw/` and `assets/files/ui/`. Visible use is mandatory under ASSET-01..05; reimport is optional because the UE assets are already supplied. Catalog dependencies are exact. The design board is in `contracts/maze-layout.json`, a mirror of GDD Section 6.

Only built-in editor helpers PythonScriptPlugin and EditorScriptingUtilities are explicitly enabled. No third-party plugin is required. The full installed-engine and built-in-plugin interface catalog is included. Game code may use any installed engine module while respecting the offline policy.

## Public health tools

`tools/Test-PublicInput.ps1 -InputRoot <input> [-VerifySnapshot]` validates structure and optionally verifies every supplied-file hash. The latter mode applies to the untouched input, not an edited candidate. `self-check/PublicSmoke/Invoke-PublicSmoke.ps1 -InputRoot <fresh-copy> -EngineRoot <engine-root> -BenchmarkToolsRoot <public-tools-workspace> -RunRoot <new-output-directory>` builds and verifies the untouched welcome frame, schema, normal close and new-process reopen. It sends no gameplay input and evaluates no gameplay requirement. Exit 0 means health passed; a nonzero exit preserves diagnostic logs/receipts for the failed operation.

The public tools workspace supplies `engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1` and its sibling native/schema dependencies. These are reusable external tools, not files in the task project. The guide documents each interface, its parameters and its limitations. No credentials or network endpoint are needed.

Writes are limited to `starter-project/` for implementation and the externally supplied run directory for evidence. Protected documents, schemas and raw reference resources outside the project remain unchanged.
