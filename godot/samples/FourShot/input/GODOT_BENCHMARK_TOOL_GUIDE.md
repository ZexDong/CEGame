# Shared Godot Development, Running, and Self-Test Guide

```text
catalog_id: godot-common-tool-guide
catalog_revision: 2026.08.15-godot-4.7.1-windows-executor
godot_version: 4.7.1.stable.official.a13da4feb
executor: GodotWindowsExecutor.ps1
scope: game-independent Godot and host interfaces
```

> This document provides game-independent project-operation guidance for implementers using a public Godot input starter package.
> For a specific game's gameplay, input, resolution, assets, and submission requirements, follow `GDD-en.md`, `TOOLCHAIN-en.md`, `MaterialMapping-en.md`, and the files under `legal/` in that game's public package.
> This document neither adds to nor relaxes any game's acceptance requirements.

## 1. Environment Baseline

- Engine baseline: Godot 4.7.x. The current shared execution capabilities were validated with Godot 4.7.1 on Windows.
- The GUI executable on the current evaluation machine is fixed at `E:\GameEngine\Godot\Godot_v4.7.1-stable_win64.exe`.
- The console executable on the current evaluation machine is fixed at `E:\GameEngine\Godot\Godot_v4.7.1-stable_win64_console.exe`.
- When invoked from WSL, the corresponding paths are `/mnt/e/GameEngine/Godot/Godot_v4.7.1-stable_win64.exe` and `/mnt/e/GameEngine/Godot/Godot_v4.7.1-stable_win64_console.exe`.
- Use the Godot executables designated above by the task owner; do not change the major version on your own.
- The shared Windows executor can start and stop projects, send keyboard and mouse input to a real game window, save window screenshots, read a project's public read-only JSON state, and archive logs.
- The shared executor works through Windows window and input APIs. It cannot generally query arbitrary Godot node trees, control bounds, hierarchy, occlusion relationships, or private game state.
If this document conflicts with a game's public package, the more specific instructions in that game package take precedence.

### 1.1 Mapping to the Public Tool-Documentation Requirements

| `ENGINEERING_GUIDE.md:425` requirement | Location in this document |
|---|---|
| How to open, run, stop, and restart | Section 4, Section 8.3, and Section 8.7 |
| How to view logs | Section 4.3 and Section 9 |
| Where assets are located | Section 3.2; the specific game's public package must state the actual path |
| Which tools may be used | Section 2 |
| Which areas may be modified | Section 3.3 |
| Where the current unified engine test entry point is | Section 8.1 |

This document covers project and tool operation only. It contains no game-specific gameplay, scoring rules, private evaluation trajectories, reference implementations, or historical results.

## 2. Available Tools

| Tool | Use case | Entry point | Output/result |
|---|---|---|---|
| Godot Project Manager | Import or select the public starter project | Import the project's `project.godot` | Project appears in the list and can be opened in the editor |
| Godot editor | Create scenes, scripts, resources, and input mappings; run and debug manually | Editor UI, F5/F6, F8, Output, Debugger | Actual game window, parse/runtime errors, and manual interaction results |
| Godot console executable | Query version, perform headless import, collect import logs | `E:\GameEngine\Godot\Godot_v4.7.1-stable_win64_console.exe` | Version string, import exit code, and text log |
| Godot GUI executable | Start a candidate project through its normal main entry point | `E:\GameEngine\Godot\Godot_v4.7.1-stable_win64.exe --path <PROJECT>` | An interactive, real top-level game window |
| Shared Windows executor | Automated start/stop, keyboard/mouse input, window screenshots, state polling, and reopening | `GodotWindowsExecutor.ps1` | Process, window handle, input results, PNG, state object, and stop result |
| PowerShell JSON/log tools | Inspect read-only observation state and scan errors | `Get-Content`, `ConvertFrom-Json`, `Select-String` | Structured state and matching error-log lines |

These tools address different concerns: use the Godot editor for development and manual debugging, the Godot CLI for imports and log inspection, and the shared executor for automating a real window and collecting evidence. Static file inspection cannot replace actually running the game, and state JSON cannot replace the rendered view.

## 3. Projects, Assets, and Modification Scope

### 3.1 Common Starting Project

The public starter project is normally located in the game package's `sp/`. If a package uses another name, follow that package's instructions. Before making changes, check that:

1. `project.godot` exists in the project directory;
2. the main scene configured by `project.godot` exists and can be opened;
3. public assets, license files, and task documents are complete;
4. the project does not depend on local absolute paths, network downloads, or plugins not included in the package.

If the project entry point or a required public file is missing, report a starter-package issue. Do not guess the baseline that the owner intended, and do not copy files from a reference implementation or another candidate project to fill the gap.

### 3.2 Asset Locations and Usage

`engine-godot/` contains only the shared executor, minimal interface test project, and validation documents. It provides no gameplay assets for any specific game. Game assets must be explicitly supplied in the corresponding public input starter package. Common locations and files are:

| Content | Common relative path | How to use it |
|---|---|---|
| Source assets | `Asserts/` | Import into `sp/` only the files needed by the public task and permitted by their licenses |
| License notices | `legal/LICENSES.md` and `legal/CREDITS.md` | Read before importing; preserve notices that must accompany distributed assets in the submission |
| Asset mapping guide | `MaterialMapping-en.md` | Follow it to confirm asset purpose and destination; do not guess mappings if the file is absent |


A specific game may use different names or place assets directly in `sp/`. Always follow that game's public `TOOLCHAIN-en.md`, `MaterialMapping-en.md`, and license files. Do not download material from the network or copy it from a known-correct reference, another candidate project, or a private evaluation package. Report a starter-package issue when assets are missing or their licensing is unclear.

### 3.3 Permitted Modification Scope

Allowed by default:

- Create and modify scenes, scripts, resources, input mappings, and project settings under the game's public `sp/` as needed to implement `GDD-en.md`;
- Import into `sp/` assets publicly supplied for that game and permitted by their licenses;
- Create a separate local self-test evidence directory outside the project for logs, screenshots, and copies of read-only state. Do not include this directory in the submitted project.

Not allowed by default:

- Modify `GDD-en.md`, this tool guide, license notices, or a frozen asset inventory to change task requirements;
- Modify the shared executor, minimal interface test project, or private evaluator to make a candidate pass;
- Read or copy a known-correct reference, private scoring rules, private trajectories, faulty versions, or historical results;
- Add write-state interfaces, answer buttons, level-skipping, direct victory, or scoring-only cheat entry points;
- Make `.godot/` cache, local absolute paths, external accounts, servers, or runtime downloads prerequisites for a working project.

If a specific game's public package explicitly expands or narrows the modification scope, follow that game's public instructions.

## 4. Using the Editor and Command Line

### 4.1 Opening a Project

1. Import the starter project's `project.godot` in Godot Project Manager;
2. wait for the initial resource import to finish;
3. inspect Output and Debugger, and fix parse, resource-reference, and main-scene errors first.

If Godot Project Manager reports an incompatible project version, do not automatically upgrade the major version. First confirm that you are using the Godot 4.7.x version designated by the task owner.

### 4.2 Running in the Editor

1. Use Run Project or F5 to launch through the normal main entry point configured in `project.godot`;
2. use F6 only while developing an individual scene; it must not replace a full-main-entry-point self-test required by the public specification;
3. complete tests through normal player input;
4. inspect the actual game window, Output, and Debugger together after running.

The following built-in Godot tools may be used directly during development:

| Editor tool | How to use it | Primary checks |
|---|---|---|
| Scene dock and Inspector | Select nodes in the current scene and edit exported properties, resources, and signal connections in Inspector | Scene hierarchy, resource references, layout, and editable parameters |
| 2D/3D workspace | Edit visible objects in the design view; after running, the real game window remains authoritative | Initial layout, colliders, camera, and visible range |
| Script editor | Open scripts, use built-in error indications, and inspect parse results after saving | Syntax, types, signals, and resource-path errors |
| Project Settings → Input Map | Add actions required by the public specification and bind keyboard or mouse events | Action names, key mappings, and press/release semantics |
| Output | Inspect output after start, interaction, retry, and exit | Script errors, resource-load failures, and custom diagnostic logs |
| Debugger → Errors | Run and reproduce the problem, then inspect the error stack | Source script, line number, and call chain |
| Debugger → Monitors/Profiler | Inspect frame time, memory, and object counts during an actual run | Obvious stutter, continuously growing object counts, and uncleared instances |
| Remote scene tree | Inspect the current runtime instance only while debugging your own implementation | Whether instances are actually created/cleared; it is not formal player input or sufficient acceptance evidence by itself |

Input Map only declares input actions. During self-test, still send events through a real keyboard or mouse; do not call the gameplay function behind an action directly from a debug console.

### 4.3 Running from the Command Line and Viewing Logs

You can also use the same-version Godot executable supplied by the task owner for command-line checks. The following paths can be used directly on the current evaluation machine:

```powershell
$godotConsole = 'E:\GameEngine\Godot\Godot_v4.7.1-stable_win64_console.exe'
$godotGui = 'E:\GameEngine\Godot\Godot_v4.7.1-stable_win64.exe'

& $godotConsole --version
& $godotConsole --headless --editor --import --path '<PROJECT_DIR>' --log-file '<IMPORT_LOG>'
& $godotGui --path '<PROJECT_DIR>' --log-file '<RUN_LOG>'
```

These commands respectively confirm the version, perform a headless import, and launch through the project's normal main entry point. A successful headless import proves only that the engine can import the project; it does not prove that gameplay is complete. Runtime inspection must use the GUI executable to produce a real window.

After import or execution, scan for common blocking errors with PowerShell:

```powershell
Select-String -Path '<IMPORT_LOG>','<RUN_LOG>' `
  -Pattern 'SCRIPT ERROR|Parse Error|Failed loading resource|ERROR:'
```

Do not write local Godot paths, user directories, or temporary evidence paths into the submitted project. A Godot process with exit code 0 may still have script or resource errors in its log, so inspect the log content as well.

### 4.4 Stopping a Run

- Editor run: use the stop button at the upper right or press F8;
- standalone game window: close the window normally first;
- shared executor: call `Stop-GodotProject -Process <PROCESS> -TimeoutMs 5000`; it requests normal closure first and terminates the process only after timeout.

After stopping, confirm that the process exited and preserve its runtime log. Merely hiding or minimizing the window, or reloading a scene, does not count as stopping.

### 4.5 Restarting a Round and Closing/Reopening

- **Restart the current round:** use a player-visible Retry, Restart, or Return to Menu and Re-enter entry point in the game. The game's `GDD-en.md` defines the specific entry point.
- **Close and reopen:** actually stop the current Godot process, then start a new process through the normal entry point in `project.godot`. Compare PIDs and check which state should persist and which should be cleared.
- If the public game requirements do not define an in-game restart, do not add a gameplay button solely because of this shared document. You can still complete the project-level smoke test by closing and restarting the process.

See Section 8.7 for the shared executor's reopen calls.

## 5. Normal Input and Observable Feedback

Self-tests must use entry points that are actually available to the player:

- Keyboard tests should distinguish press, hold, and release. Continuous movement cannot be validated from a single key event.
- Mouse tests should move, press, and release over a visible, unobstructed, interactive target in the current view. A drag should cover its start, hold, movement, and release at the endpoint.
- Do not call internal gameplay functions for attack, resolution, victory, failure, reset, or save directly in place of player input.
- Major conclusions should be supported by the rendered view, state changes, and logs together—not merely by script names, node existence, or static text.

### 5.1 Two Automation Input-Dispatch Levels

Automated Godot runs may use either of the following normal input paths. Whether the operating-system pointer moves is not sufficient to determine whether the game received input:

1. **Windows window-level input:** `GodotWindowsExecutor.ps1`, described in Sections 7–8, operates a visible game window through Windows window and input APIs. It requires an interactive desktop, the target window handle, and current window focus; mouse operations may move the operating-system pointer.
2. **Godot engine-level input:** a formal evaluator or in-engine test runner may construct normal `InputEventMouseMotion`, `InputEventMouseButton`, and `InputEventKey` instances and submit them directly to the target Godot `Window` input queue through `Window.push_input(InputEvent, true)`. This path does not drive the physical Windows mouse, so the user's system pointer normally does not move, but the game still receives motion, press, hold, release, and keyboard events through normal Godot input dispatch.

Engine-level input is neither static-screenshot inference nor a direct call to internal build, attack, victory, reset, or other gameplay functions. An automated drag must still move to a visible source, press, send multiple held-motion events, reach a visible destination, and release. Before clicking, the runner must still resolve and confirm a currently visible, unobstructed, interactive target. Formal evidence should record the input interface, event type, position, button/key state, time or frame, and the corresponding rendered/state change.

It is therefore normal for the user's physical mouse not to move during a formal evaluation; this does not mean that the evaluator did not operate the game. Do not manually interact with the candidate window while either dispatch path is running, because unplanned input could contaminate the evidence.

The shared executor can confirm only that input reached the target top-level Godot window. It cannot automatically determine which internal Control or node received it. Implementers should therefore provide clear visible feedback and avoid interfaces operable only through invisible regions or secret coordinates.

## 6. Read-Only Observation State

If a specific game's public starter package already provides a read-only state snapshot or observation bridge, preserve its public protocol and keep its state synchronized with the rendered view. Observation data may include phases, counts, positions, results, or persistent state required for evaluation, but must remain within the fields and boundaries defined by that game's public documentation.

The read-only observation surface must:

- observe only; it must not modify game state or call gameplay functions;
- provide no cheat commands for skipping levels, spawning objects, or resolving outcomes directly;
- reveal no reference implementation, private scoring rules, or answers;
- prefer atomic replacement or another stable write method to avoid exposing partially written JSON;
- never assume that an evaluator can read arbitrary internal nodes or private variables when no public protocol exists.

Observation state is a cross-check for visual evidence; it cannot replace actual player operation and rendering.

## 7. Self-Testing with the Shared Windows Executor

The shared executor is `GodotWindowsExecutor.ps1` in this directory. It requires an interactive Windows desktop, a visible game window, and writable Godot user and evidence directories.

### 7.1 Current Unified Engine Test Entry Point

The current unified **environment-capability test entry point** is `GodotWindowsExecutor.ps1 -Mode Probe`. Change to `truestart/engine-godot/`, then run:

```powershell
$executorScript = '.\GodotWindowsExecutor.ps1'
$godotGui = 'E:\GameEngine\Godot\Godot_v4.7.1-stable_win64.exe'
$probeProject = '.\MinimalTestProject'
$probeEvidence = '.\evidence\local-probe'

& $executorScript -Mode Probe `
  -GodotPath $godotGui `
  -ProjectPath $probeProject `
  -EvidenceDirectory $probeEvidence
```

On success, inspect `probe-summary.json`, `gui-run-1.log`, `gui-run-2.log`, and `01`–`06-*.png`. These results prove only that the shared executor works; they do not prove that any specific game passes.

`Probe` mode tests only the bundled `MinimalTestProject/`; it cannot accept an arbitrary candidate project as a gameplay-evaluation entry point. Each game's unified self-test entry point must be specified separately by its public package. If there is no game-level wrapper script, use the `Library` mode described in Section 8.2 to write a self-test script based on that game's public input, observation protocol, and player flows.

### 7.2 Library Entry Point and Tool Table

Load the function library at the beginning of your PowerShell self-test script:

```powershell
. '.\GodotWindowsExecutor.ps1' -Mode Library
```

The following interfaces can be used directly:

| Interface | Key parameters | Return or output | Purpose |
|---|---|---|---|
| `Start-GodotProject` | `Executable`, `Project`, `LogPath`, optional `AdditionalArguments` | `System.Diagnostics.Process` | Start a project from the directory containing `project.godot` |
| `Wait-GodotWindow` | `Process`, optional `TimeoutMs` | Top-level window handle | Wait for the real game window to appear |
| `Get-GodotClientBounds` | `WindowHandle` | Client-area X/Y/width/height | Confirm window dimensions and calculate client coordinates |
| `Set-GodotWindowFocus` | `WindowHandle` | None | Restore and foreground the window before sending keyboard input |
| `Send-GodotKeyDown/Up` | Windows `VirtualKey` | Throws on failure | Send key-down and key-up separately |
| `Send-GodotKeyPress` | `VirtualKey`, optional `HoldMs` | Throws on failure | Send one complete key press |
| `Send-GodotMouseMove` | `WindowHandle`, `ClientX/Y` | Converted screen point | Move the pointer to game client-area coordinates |
| `Send-GodotMouseButton` | `State=Down/Up`, `Button` | Throws on failure | Independently control left/middle/right mouse-button press and release |
| `Send-GodotMouseClick` | `WindowHandle`, `ClientX/Y`, optional `HoldMs` | Throws on failure | Focus the window and perform a left click |
| `Send-GodotMouseDrag` | Start/end points, steps, interval, button | Throws on failure | Press, move in steps, and release to complete a drag |
| `Get-GodotWindowHit` | `WindowHandle`, `ClientX/Y` | Screen point, hit handle, whether target is the top-level window | Confirm before clicking that the point still belongs to the game window |
| `Save-GodotWindowScreenshot` | `WindowHandle`, PNG `Path` | Saved file object | Focus the window and capture its client area |
| `Get-GodotProbeState` | `StatePath` | PowerShell object converted from JSON | Read the project's public read-only state snapshot |
| `Wait-GodotProbeState` | State path, property, expected value, timeout | Complete state object when the condition is met | Wait for actual state change instead of using a fixed sleep as the criterion |
| `Stop-GodotProject` | `Process`, optional `TimeoutMs` | PID, exit code, exited status | Request normal closure, then terminate after timeout |

`ClientX/Y` coordinates are relative to the upper-left corner of the game client area, not absolute desktop coordinates. Click positions must come from the current visible view or the game's public layout/semantic information; do not copy fixed coordinates from a reference implementation or the minimal test project.

### 7.3 Starting, Taking a Screenshot, and Stopping

```powershell
. '.\GodotWindowsExecutor.ps1' -Mode Library

$godotGui = 'E:\GameEngine\Godot\Godot_v4.7.1-stable_win64.exe'
$projectDir = '<PROJECT_DIR>'
$evidenceDir = '.\self-test-evidence\run-001'
$logPath = Join-Path $evidenceDir 'godot.log'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$gameProcess = $null
try {
    $gameProcess = Start-GodotProject `
      -Executable $godotGui -Project $projectDir -LogPath $logPath
    $gameWindow = Wait-GodotWindow -Process $gameProcess -TimeoutMs 15000
    $bounds = Get-GodotClientBounds -WindowHandle $gameWindow
    $bounds | ConvertTo-Json | Set-Content `
      -Path (Join-Path $evidenceDir 'window.json') -Encoding UTF8
    Save-GodotWindowScreenshot -WindowHandle $gameWindow `
      -Path (Join-Path $evidenceDir '01-initial.png') | Out-Null

    # Add the actual input and state checks required by Sections 8.4–8.6 here.
}
finally {
    # Release any input that might still be held before exiting after an interruption.
    try { Send-GodotMouseButton -State Up -Button Left } catch {}
    try { Send-GodotMouseButton -State Up -Button Middle } catch {}
    try { Send-GodotMouseButton -State Up -Button Right } catch {}
    try { Send-GodotKeyUp -VirtualKey 0x41 } catch {} # A
    try { Send-GodotKeyUp -VirtualKey 0x44 } catch {} # D
    try { Send-GodotKeyUp -VirtualKey 0x53 } catch {} # S
    try { Send-GodotKeyUp -VirtualKey 0x57 } catch {} # W
    if ($null -ne $gameProcess) {
        Stop-GodotProject -Process $gameProcess -TimeoutMs 5000 | Out-Null
    }
}
```

### 7.4 Keyboard Input

Common Windows VirtualKeys: Enter=`0x0D`, Escape=`0x1B`, Space=`0x20`, Left/Up/Right/Down=`0x25/0x26/0x27/0x28`, A/D/S/W=`0x41/0x44/0x53/0x57`.

```powershell
Set-GodotWindowFocus -WindowHandle $gameWindow

# One complete key press: hold for 100 ms, then release.
Send-GodotKeyPress -VirtualKey 0x0D -HoldMs 100 # Enter

# Continuous-movement verification must explicitly distinguish press, hold, and release.
Send-GodotKeyDown -VirtualKey 0x57 # W down
try {
    Start-Sleep -Milliseconds 600
    # Read state or take a screenshot here to confirm continued movement during the hold.
}
finally {
    Send-GodotKeyUp -VirtualKey 0x57 # W up
}
```

The shared minimal loop has tested the A key. When a specific game uses other keys, test their press, hold, release, and focus behavior in the same way.

### 7.5 Mouse Click and Drag

```powershell
# Choose coordinates from the currently visible target.
$targetX = 640
$targetY = 360
$hit = Get-GodotWindowHit -WindowHandle $gameWindow `
  -ClientX $targetX -ClientY $targetY
if (-not $hit.IsGodotTopLevelWindow) {
    throw 'TARGET_POINT_NOT_IN_GODOT_WINDOW'
}
Send-GodotMouseClick -WindowHandle $gameWindow `
  -ClientX $targetX -ClientY $targetY -HoldMs 100

# Drag with the left button from the current visible start to the current visible endpoint.
Send-GodotMouseDrag -WindowHandle $gameWindow `
  -StartX 300 -StartY 300 -EndX 700 -EndY 300 `
  -Steps 16 -StepDelayMs 25 -Button Left
```

The numbers above demonstrate parameter format only; they must not be used directly as evaluation coordinates for a specific game. `Get-GodotWindowHit` confirms only a top-level window hit. Use visual feedback or public read-only state to confirm that the correct internal Godot control was clicked.

### 7.6 Reading and Waiting for Read-Only State

The specific game's public observation protocol supplies `StatePath`. On Windows, Godot's `user://` usually maps to `%APPDATA%\Godot\app_userdata\<PROJECT_NAME>\`, but do not guess file names or fields.

```powershell
$statePath = '<PUBLIC_STATE_JSON_PATH>'

$before = Get-GodotProbeState -StatePath $statePath
Send-GodotKeyPress -VirtualKey 0x20 -HoldMs 100 # Space
$after = Wait-GodotProbeState -StatePath $statePath `
  -Property 'phase' -ExpectedValue 'playing' -TimeoutMs 5000

$before | ConvertTo-Json -Depth 10 | Set-Content `
  -Path (Join-Path $evidenceDir 'state-before.json') -Encoding UTF8
$after | ConvertTo-Json -Depth 10 | Set-Content `
  -Path (Join-Path $evidenceDir 'state-after.json') -Encoding UTF8
Save-GodotWindowScreenshot -WindowHandle $gameWindow `
  -Path (Join-Path $evidenceDir '02-after-input.png') | Out-Null
```

`phase` and `playing` only demonstrate the call format; replace them with actual properties and values from the game's public protocol. If a game has no public observation protocol, remove the state-reading steps and self-test using normal input, visuals, and logs. Do not add a write-state interface privately.

### 7.7 Resetting and Closing/Reopening

Reset by clicking a player-visible retry/restart entry point, then read state and save a screenshot. Do not directly reload a scene or call a private reset function in place of player action.

When closing and reopening, save the first PID, call `Stop-GodotProject`, start the project and wait for its window again, and confirm that the second PID differs:

```powershell
$firstPid = $gameProcess.Id
$firstStop = Stop-GodotProject -Process $gameProcess -TimeoutMs 5000

$gameProcess = Start-GodotProject `
  -Executable $godotGui -Project $projectDir `
  -LogPath (Join-Path $evidenceDir 'godot-reopen.log')
$gameWindow = Wait-GodotWindow -Process $gameProcess -TimeoutMs 15000

if ($gameProcess.Id -eq $firstPid) {
    throw 'NEW_PROCESS_NOT_CONFIRMED'
}
Save-GodotWindowScreenshot -WindowHandle $gameWindow `
  -Path (Join-Path $evidenceDir '03-reopened.png') | Out-Null
```

### 7.8 Items Without a General-Purpose Tool

There is currently no ready-to-use general-purpose automated evaluation tool for reading arbitrary internal Godot nodes/controls; automatically determining whether internal controls are hidden, transparent, clipped, or occluded; performing OCR or template matching; waiting for visual conditions; reliably capturing minimized or occluded windows; or providing cross-platform input. Developers may use the Godot editor's Remote scene tree to debug their own projects, but it cannot replace normal player input and public observation protocols in formal evaluation. If a task genuinely requires a new automated evaluation capability, first create a separate tool and validate it against a minimal project. Do not disguise fixed sleeps or private reference coordinates as a validated capability.

## 8. Logs, Screenshots, and Error Attribution

For each run, use a separate directory to store:

- Godot import and runtime logs;
- key screenshots before and after input;
- public read-only state snapshots;
- start, stop, retry, and new-process records;
- reproduction steps and expected/actual results.

Screenshots require the target window to be foreground, visible, and unobstructed by other windows. Fixed waits may be used for UI stabilization but should not be the sole passing criterion. Prefer waiting for public state or a confirmable visual change.

Distinguish three problem categories:

1. **Project issue:** parse errors, missing resources, gameplay errors, or unusable UI under a valid environment and input;
2. **Environment/executor issue:** input not sent, window or screenshot failure, unwritable permissions/user directory, or state-reader failure;
3. **Starter-package issue:** the public project entry point, assets, licenses, or required baseline were already missing before development began.

Do not hide environment or starter-package failures by changing gameplay requirements, and do not automatically treat them as game-feature failures.
