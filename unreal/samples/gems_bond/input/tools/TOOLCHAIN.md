# Toolchain and project entry

| Binding | Value |
| --- | --- |
| Engine | Unreal Engine 5.7.4, CL 51494982, compatible CL 47537391, ++UE5+Release-5.7 |
| Platform / runtime | Windows x64; independent editor_game window |
| Native compiler | Visual Studio 2022; MSVC 14.44.35228; Windows SDK 10.0.26100.0 |
| Build driver | Installed engine Build.bat and bundled .NET 8.0.412 |
| Project | starter-project/GemsBondStarter.uproject |
| Editor target | GemsBondStarterEditor |
| Untouched default map | /Engine/Maps/Entry; unfinished health screen |
| Final default entry | The project's normal GameDefaultMap; implementation may change it |
| Declared editor plugins | PythonScriptPlugin and EditorScriptingUtilities |
| Required external runtime plugins | None |
| Native starter dependencies | Core, CoreUObject, Engine, InputCore, Json |
| Output viewport | 1280 x 720 or 1920 x 1080 physical client pixels, 16:9, DPI recorded |
| Determinism | -GameSeed=<uint32>, default 50; bind this in completed gameplay per RANDOM-01 |
| State output | -ObservationPath=<output.json>; see contracts/GAME_SESSION_SPEC.md |

Resolve the installation with `pwsh -NoProfile -File tools/Resolve-Unreal57.ps1`.
Use UE_5_7_ROOT or -EngineRoot to select an existing installation. The resolver checks
the actual Build.version and returns the build/editor paths as JSON; it never installs.
Use the engine's `Engine/Binaries/ThirdParty/Python3/Win64/python.exe` for the dependency-free
Python checks. PowerShell 7 is used for launch and desktop input; no pip install is needed.

Build one target with `Build.bat GemsBondStarterEditor Win64 Development -Project=<absolute-uproject> -WaitMutex -NoHotReloadFromIDE`.
Open with `UnrealEditor.exe <absolute-uproject>` or run the normal game with
`UnrealEditor.exe <absolute-uproject> -game -windowed -ResX=1280 -ResY=720 -ForceRes -NoSplash -NoP4`.
Exit using the game/window close control. The final normal Restart uses R or its visible control.
The unfinished starter instead exposes only a Space-key input probe and window close.

Keep the project descriptor path, editor target name and required engine version unchanged.
You may edit descriptor module/plugin declarations to match your project organization using
installed components. Code, asset organization and normal GameDefaultMap inside starter-project/
are free. Log files appear in starter-project/Saved/Logs. Generate evidence outside input/.
Individual executable interfaces and errors are documented by the engine tool guide.

All runtime visual art and background music are already UE packages in starter-project/Content/.
Optional event WAV cues remain in assets/files/audio/; import them into starter-project/ if used.
The PNGs in reference/ are documentation only. assets/ASSET_CATALOG.json lists exact
object paths, classes, dependencies, hashes, use and license for every package. Import
file paths are not included; reimport requires a new user-supplied source file.
Use the included animation clips as presentation; gameplay-linked animation graphs and
notifications are intentionally absent. No assembled level or combat implementation is supplied.

Run `pwsh -NoProfile -File tools/Test-PublicInput.ps1` for the immutable input gate.
After editing starter-project/, add -AllowProjectChanges to preserve checks of protected files
while allowing implementation changes. For a clean health check, run
`pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 -InputRoot <input> -RunRoot <empty-output> [-EngineRoot <engine>]`.
The smoke's README explains build, asset validation, snapshot, capture, input and reopen checks.
