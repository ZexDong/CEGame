# Toolchain and project entry

| Binding | Value |
| --- | --- |
| Engine | Unreal Engine, CL configured-build, compatible CL configured-build, ++UE5+Release-5.7 |
| Platform / runtime | desktop; independent editor_game window |
| Native compiler | Visual Studio 2022; MSVC 14.44.35228; native build SDK 10.0.26100.0 |
| Build driver | Installed engine Build.bat and bundled .NET 8.0.412 |
| Project | starter-project/BoneMaze.uproject |
| Editor target | BoneMazeEditor |
| Untouched default map | /Engine/Maps/Entry; unfinished health screen |
| Final default entry | The project's normal GameDefaultMap; implementation may change it |
| Declared editor plugins | PythonScriptPlugin and EditorScriptingUtilities |
| Required external runtime plugins | None |
| Native starter dependencies | Core, CoreUObject, Engine, InputCore, Json |
| Output viewport | 1280 x 720 or 1920 x 1080 physical client pixels, 16:9, DPI recorded |
| Determinism | -GameSeed=<uint32>, default 48; bind this in completed gameplay per MAZE-04 |
| State output | -ObservationPath=<output.json>; see contracts/GAME_SESSION_SPEC.md |

Resolve the installation with `pwsh -NoProfile -File tools/Resolve-Unreal57.ps1`.
Use UE_5_7_ROOT or -EngineRoot to select an existing installation. The resolver checks
the actual Build.version and returns the build/editor paths as JSON; it never installs.
Use the engine's `Engine/Binaries/ThirdParty/Python3/Win64/python.exe` for the dependency-free
Python checks. shell is used for launch and desktop input; no pip install is needed.

Build one target with `Build.bat BoneMazeEditor Win64 Development -Project=<absolute-uproject> -WaitMutex -NoHotReloadFromIDE`.
Open with `UnrealEditor.exe <absolute-uproject>` or run the normal game with
`UnrealEditor.exe <absolute-uproject> -game -windowed -ResX=1280 -ResY=720 -ForceRes -NoSplash -NoP4`.
Exit using the game/window close control. The final normal Restart uses R or its visible control.
The unfinished starter instead exposes only a Space-key input probe and window close.

The descriptor path, BoneMazeEditor build target and engine version are fixed. Descriptor
contents and module organization may be edited to support the implementation and the
normal default map. Supplied required package/object paths remain fixed under the
asset rules; newly authored files are free to use any organization inside starter-project/.
Log files appear in starter-project/Saved/Logs. Generate evidence outside input/.
All task material is contained in this input.
Individual executable interfaces and errors are documented by the engine tool guide.

All included art/audio assets are already UE packages under starter-project/Content/.
assets/ASSET_CATALOG.json lists exact object paths, classes, dependencies, hashes, purpose
and rights status for each package. Native packages are supplied without external
import files. Reimport requires a separately supplied source file. Animations have no gameplay notify tracks.
Particle systems, material functions and the pixelation material are presentation only;
their existence does not supply game logic, level assembly, UI widgets or event binding.

Run `pwsh -NoProfile -File tools/Test-PublicInput.ps1` for the immutable input gate.
After editing starter-project/, add -AllowProjectChanges to preserve checks of protected files
while allowing implementation changes. For a clean health check, run
`pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 -InputRoot <input> -RunRoot <empty-output> [-EngineRoot <engine>]`.
The smoke's README explains build, asset validation, snapshot, capture, input and reopen checks.
