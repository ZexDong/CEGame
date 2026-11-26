# Unity 6 Tool Use Guide

```text
common_tool_guide_id: unity-common-tool-guide-v5-20260825
unity_editor: Unity
unity_cli: 1.0.0-beta.3
input_system_track: 1.19.x
runner_route: unity-cli-plus-project-local-logs-v1
```

This English-only document contains reusable Unity and Unity CLI facts for the pinned
tool versions above. Per-project paths, entry Scenes, test filters, assets, controls, and
observation APIs are documented by that project.

## 1. Pinned tools and command boundaries

```text
Unity Editor  $env:UNITY_EDITOR
Unity CLI     $env:UNITY_CLI
Input System  1.19.x
```

Use the versions declared by the current project if they differ from this tuple. Call the
installed tools, but do not install, upgrade, remove, or modify the engine directory.

The supported Unity CLI top-level commands are `run`, `test`, `open`, and `status`.
Unity CLI owns the project path plus Unity's batch/quit/project arguments. Do not forward
`-batchmode`, `-quit`, or `-projectPath` after `--`.

CLI options such as `--json`, `--non-interactive`, `--proxy-disable`, `--mode`,
`--filter`, `--output`, `--editor-path`, and `--timeout` belong before `--`.
Raw Unity Editor arguments, such as `-logFile`, belong after `--` for `run` and `test`,
or after `--args` for `open`.

`status` only observes an already open Editor. It does not import, compile, enter Play
Mode, run tests, or prove that gameplay works.

## 2. Work in the current project and keep tool output local

Run the tools from the current Unity project root. Do not create a nested project copy.
Resolve the project path with:

```powershell
$Project = (Get-Location).Path
$Cli = $env:UNITY_CLI
$Editor = $env:UNITY_EDITOR
```

Unity may delete or recreate `Temp/` while importing or opening a project. Do not store
logs, NUnit XML, or screenshots in `Temp/`. Use a stable project-local directory such as
`Logs/ToolChecks/<timestamp>/` and use a new filename for every command.

Always pass an explicit project-local `-logFile`. Do not depend on the global Editor log
under a user profile. If the expected local log is missing, stop the Unity process that
owns this exact project and rerun the bounded command with a new local log.

Only one Unity Editor may own the same project at a time. Close the exact project owner
before starting another `run`, `test`, or `open` command for that project.

## 3. Unity 6 runtime and Editor assembly facts

- Runtime assemblies must not reference `UnityEditor`.
- `AssetDatabase`, Editor windows, import callbacks, and editor scripting belong under an
  `Editor/` folder or an Editor-only assembly definition.
- A playable build must use saved Scenes, Prefabs, ScriptableObjects, materials, and other
  serialized assets. Do not require an Editor startup callback to generate the game.
- Save every required entry Scene and place it in Build Settings as declared by the
  current project's public manifest.
- A successful script compilation does not prove that serialized Scene references are
  valid. Enter real Play frames to expose missing references and first-frame exceptions.

## 4. Input System Package 1.19.x

When `ProjectSettings.asset` uses the new Input System, use APIs such as:

```csharp
Keyboard.current
Mouse.current
InputAction
InputActionReference
PlayerInput
```

Do not use legacy `UnityEngine.Input.GetKey*`, `GetMouseButton*`, or
`Input.mousePosition` in a new-Input-System-only project. These calls may compile and then
throw during Play.

Make sure required action maps are enabled after Scene load and after a restart. Keep UI
input routing ahead of world interaction so a pointer action handled by the UI does not
also fall through to gameplay.

`InputSystemUIInputModule` is in `UnityEngine.InputSystem.UI`. In the pinned 1.19 track,
a newly enabled module with no actions calls `AssignDefaultActions()` from `OnEnable()`.
An explicit call is optional. Correctly serialized custom UI actions are also valid.

## 5. Runtime UI and fonts

For uGUI/TMP interfaces, the normal runtime route uses:

- an active `Canvas`;
- a `GraphicRaycaster` for pointer-driven UI;
- visible `Graphic`, `Text`, or `TMP_Text` elements;
- one active `EventSystem` for the current player-facing route;
- an Input-System-compatible UI module;
- real `RectTransform` and raycast geometry for interactive controls.

Disable `raycastTarget` on display-only graphics and text when they do not receive input.
An invisible or transparent full-screen graphic can become the top raycast hit and block
the intended button or world target. Inspect the actual `GraphicRaycaster` top hit when a
visible control does not respond.

`OnGUI`, `GUI.Button`, and `GUILayout` are immediate-mode interfaces and do not provide the
same serialized `RectTransform`/raycaster surfaces as uGUI. Use the runtime UI technology
allowed by the current project files.

Unity 6 does not accept the old built-in font name `Arial.ttf`. Script-created uGUI Text
can use an imported/serialized font or:

```csharp
Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf")
```

TMP text should reference a valid serialized TMP font asset. Verify glyphs, layout, and
click geometry in real Play frames rather than only in EditMode.

## 6. Camera, physics, rendering, lifecycle, and audio facts

- Keep the required active Camera enabled and rendering a meaningful frame.
- Visible world input targets need suitable Renderer or Graphic geometry and the required
  Collider/Collider2D. Check layers, masks, Z/depth, ray origins, and screen/world
  conversion together.
- A `NavMeshAgent` must be on a baked reachable NavMesh before it can navigate.
- Shader Graph materials may not expose `_Color`. Use `Material.HasProperty` before setting
  a shader property.
- `LineRenderer.useWorldSpace = true` stores points in world coordinates. Moving only the
  owner Transform does not move those stored points.
- `Object.Destroy` completes at the end of the frame. When rebuilding objects, deactivate
  or unregister the old objects first and allow destruction to cross a player-loop frame
  before global rediscovery.
- Unity destroyed-object fake-null applies to components such as `AudioSource` and
  `Animator`. Assign required components explicitly and keep runtime calls null-safe.
- `AudioSource.PlayOneShot(clip)` is valid even when `AudioSource.clip` remains null.
  Inspect serialized clip references and actual playback behavior instead of assuming a
  null default `clip` means no audio is used.

## 7. Reading supplied assets correctly

Use the current project's asset catalog, contact sheet, and import facts for exact paths and
roles. Do not guess paths when a catalog exists.

- A contact sheet is an inventory preview, not a finished runtime background.
- Source texture dimensions are not the same as visible character size. For padded
  sprites, inspect the sprite rect, alpha bounds when supplied, pivot, and pixels per unit.
- Check Sprite Mode, slicing, filter mode, wrap mode, nine-slice borders, material
  dependencies, and animation layout before use.
- A supplied Prefab with missing or omitted scripts is not automatically a runnable final
  object. Reuse the valid media and serialized parts according to the catalog.
- Map supplied audio to the semantic event roles documented by the current project instead
  of leaving clips unused.
- Preserve readable scale and aspect ratio; avoid unintended stretching, cropping,
  transparent padding, sorting errors, and placeholder replacement of supplied major media.

## 8. Import, compile, and public test commands

Use a bounded import/compile pass with a new local log:

```powershell
$Project = (Get-Location).Path
$Cli = $env:UNITY_CLI
$Editor = $env:UNITY_EDITOR
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$CheckDir = "$Project\Logs\ToolChecks\$Stamp-compile"
$HostTemp = "$CheckDir\host-temp"
$EditorLog = "$CheckDir\editor.log"
New-Item -ItemType Directory -Force -Path $CheckDir,$HostTemp | Out-Null
$OldTemp=$env:TEMP; $OldTmp=$env:TMP
try {
  $env:TEMP=$HostTemp; $env:TMP=$HostTemp
  & $Cli --json --non-interactive --proxy-disable run $Project `
    --editor-path $Editor --timeout 600 -- -logFile $EditorLog
  if ($LASTEXITCODE -ne 0) { throw "Unity import/compile failed: $LASTEXITCODE" }
} finally {
  $env:TEMP=$OldTemp; $env:TMP=$OldTmp
}
Get-Content -LiteralPath $EditorLog -Tail 200
```

A zero exit code is not a replacement for reading the new log. Check for compiler errors,
package resolution failures, import failures, missing references, and first-frame runtime
exceptions.

Use the exact public filters declared by the current project. If a project declares no
filter, omit `--filter` rather than passing a placeholder:

```powershell
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$CheckDir = "$Project\Logs\ToolChecks\$Stamp-tests"
$HostTemp = "$CheckDir\host-temp"
$EditXml = "$CheckDir\editmode.xml"
$PlayXml = "$CheckDir\playmode.xml"
$EditLog = "$CheckDir\editmode.log"
$PlayLog = "$CheckDir\playmode.log"
New-Item -ItemType Directory -Force -Path $CheckDir,$HostTemp | Out-Null
$OldTemp=$env:TEMP; $OldTmp=$env:TMP
try {
  $env:TEMP=$HostTemp; $env:TMP=$HostTemp
  & $Cli --json --non-interactive --proxy-disable test $Project --mode EditMode `
    --filter '<public-editmode-filter>' --output $EditXml `
    --editor-path $Editor --timeout 600 -- -logFile $EditLog
  if ($LASTEXITCODE -ne 0) { throw "EditMode test failed: $LASTEXITCODE" }

  & $Cli --json --non-interactive --proxy-disable test $Project --mode PlayMode `
    --filter '<public-playmode-filter>' --output $PlayXml `
    --editor-path $Editor --timeout 900 -- -logFile $PlayLog
  if ($LASTEXITCODE -ne 0) { throw "PlayMode test failed: $LASTEXITCODE" }
} finally {
  $env:TEMP=$OldTemp; $env:TMP=$OldTmp
}
```

For each new NUnit XML file, verify that it exists, is readable, discovered at least one
test, and contains the expected public test identities and all-passed results. Read the
matching log when a test process exits nonzero or the XML is missing.

An EditMode pass proves import/serialization facts only. A PlayMode `[UnityTest]` must yield
real player-loop frames to observe `Awake`, `Start`, `Update`, runtime UI, input routing,
and first-frame exceptions.

## 9. Play-mode observation

Use `unity open` for desktop interaction only when the current environment actually exposes
a controllable Game view. A shell-only process must not claim that it operated an Editor
window it could not control.

A reported UI rectangle must use actual rendered screen pixels after `CanvasScaler`,
anchors, Camera/display selection, and transforms. When a visible pointer control fails,
inspect the real screen corners, active display, `GraphicRaycaster` top hit, EventSystem
route, and target rectangle together.

## 10. Safe exact-project open and reopen

Reloading a Scene or stopping and re-entering Play Mode is not a new Unity process. To bind
an Editor safely on Windows, match the exact normalized project path in the Unity command
line. Never stop every `Unity.exe` process.

```powershell
function Get-ExactProjectUnityProcess([string]$ProjectPath) {
  $Exact = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
  $Token = [regex]::Escape($Exact)
  $Pattern = '(?i)(?:^|\s)-projectPath\s+(?:"' + $Token + '"|' + $Token + ')(?=\s|$)'
  @(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
      [string]$_.CommandLine -match $Pattern
    })
}
```

Before `open`, record any exact-project PIDs. Use a new local log, wait for exactly one new
matching PID, and retain that PID:

```powershell
$Before = @(Get-ExactProjectUnityProcess $Project | ForEach-Object { [int]$_.ProcessId })
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$OpenLog = "$Project\Logs\ToolChecks\open-$Stamp.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OpenLog) | Out-Null
& $Cli --json --non-interactive --proxy-disable open $Project `
  --editor-path $Editor --args "-logFile `"$OpenLog`""

$Deadline = [DateTime]::UtcNow.AddSeconds(120)
do {
  Start-Sleep -Milliseconds 500
  $New = @(Get-ExactProjectUnityProcess $Project | Where-Object {
      $Before -notcontains [int]$_.ProcessId
    })
} until ($New.Count -eq 1 -or [DateTime]::UtcNow -ge $Deadline)
if ($New.Count -ne 1) { throw 'Could not bind exactly one Unity PID for this project.' }
$ProjectUnityPid = [int]$New[0].ProcessId
```

To close the project, stop only the recorded exact-project PID, wait for exit, and re-query
the exact path before opening again. If matching returns zero or multiple unexpected PIDs,
stop nothing until ownership is resolved. Never use `taskkill /IM Unity.exe` or
`Stop-Process -Name Unity`.

## 11. Unity diagnostic facts

Unity CLI output, NUnit XML when applicable, and the matching project-local log expose
different parts of the same command. The first project-owned file or Scene in a compiler
diagnostic or stack trace usually identifies the actionable location.

| Symptom | Tool-focused check |
|---|---|
| C# compiler error | Read the exact `CS####` diagnostic and referenced file/line. |
| Legacy input exception | Replace legacy polling and verify the new Input System action map is enabled. |
| `Arial.ttf` error | Use `LegacyRuntime.ttf` or an imported/serialized font. |
| Material property error | Check `Material.HasProperty` before writing the property. |
| Missing script/reference | Inspect saved Scene/Prefab references and keep Editor code out of runtime assemblies. |
| Visible UI does not click | Inspect Canvas, Raycaster, EventSystem, input module, top hit, display, and screen rectangle. |
| UI click affects the world | Fix UI-first routing and block fall-through. |
| Collider/raycast miss | Check collider presence, layer masks, Z/depth, Camera, and hit geometry. |
| `NavMeshAgent` does not move | Confirm a baked reachable NavMesh and that the agent is placed on it. |
| Test process exits nonzero | Read the new XML and matching local log; do not rely on the exit code alone. |
| Project cannot open | Confirm no existing Unity process owns the exact project path. |
