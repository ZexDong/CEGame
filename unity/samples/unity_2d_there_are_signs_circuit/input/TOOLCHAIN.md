# Sign Circuit public Unity toolchain contract

`GDD.md` Section 6 is the sole player-facing acceptance specification. This file
only defines the fixed Unity environment, the supported input and visible-UI
surfaces, the public tests, and the protected read-only observation API.

## 1. Fixed environment

- Unity Editor: `6000.0.80f1 (2dfd32957da2)`
- Unity Editor path: `D:\game\engine\unity\6000.0.80f1\Editor\Unity.exe`
- Unity CLI: `1.0.0-beta.3`
- Unity CLI path:
  `D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe`
- Input System: `1.19.0`
- Test Framework: `1.6.0`
- URP 2D: `17.0.4`
- uGUI: `2.0.0`
- Challenge scene: `Assets/Scenes/Benchmark/SignCircuit.unity`
- Menu scene: `Assets/Scenes/Menu.unity`
- Preserved scene: `Assets/Scenes/Levels/Level1+2.unity`
- Runtime work root: `Assets/Benchmark/Runtime/**`
- Optional Editor helper root: `Assets/Benchmark/Editor/**`
- Protected contract root: `Assets/BenchmarkContract/**`

Network access and package installation are unavailable. Use the current project,
the pinned packages, and the supplied assets. Do not add cloud, machine-absolute,
network, or uninstalled-package dependencies to the saved game.

## 2. Unity 6 compatibility facts

### 2.1 Runtime and Editor assemblies

- Runtime scripts must compile in Play Mode and player assemblies without a
  `UnityEditor` reference.
- One-shot authoring helpers may use `UnityEditor` only under
  `Assets/Benchmark/Editor/**`. The saved challenge cannot require an Editor
  callback, `AssetDatabase`, `EditorWindow`, or helper execution at Play time.
- Save the challenge scene, the permitted Menu edit, and the permitted Build
  Settings change. Keep the preserved `Level1+2` scene and protected assets
  unchanged.
- A compiler error, missing assembly, `Missing (Mono Script)`, missing serialized
  reference, or scene-deserialization error blocks the saved game and must be
  corrected at its source.

### 2.2 Input System 1.19

The required player-input boundary is the installed Input System package. Do not
change the project input setting. Supported runtime routes are:

- `UnityEngine.InputSystem.Keyboard.current` and `Mouse.current` polling;
- enabled `InputAction` objects; or
- `PlayerInput`.

Enable an `InputAction` before reading it and unsubscribe or disable it with its
owner. Restart and scene changes must not duplicate callbacks. Legacy
`UnityEngine.Input`, `Event.current`, `GUI.Button`, and IMGUI-only events are not
supported as the required control route. Required keyboard and pointer actions must come
through the player-facing Input System route. Calling a movement, interaction, checkpoint,
gate, terminal, Restart, or save method directly is not an input implementation.

### 2.3 Runtime uGUI/TMP and fonts

Required menu controls, Restart controls, HUD text, status text, and
pause/success/failure panels use real runtime uGUI/TMP surfaces:

- an active visible `Canvas`;
- a `GraphicRaycaster`;
- an active `EventSystem` with `InputSystemUIInputModule` or another module that
  consumes the installed Input System;
- visible uGUI `Graphic`, `Text`, or `TMP_Text` components; and
- real uGUI `Button` semantics for required pointer controls.

A `CanvasGroup` must remain visible, interactable, and raycast-enabled when its
controls are available. The intended control must be the unobscured top raycast
hit. Gameplay input must not also consume a pointer press already handled by UI.

Use an imported font, `Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf")`,
or a valid serialized TMP font asset. Do not request `Arial.ttf` or an operating-
system font at runtime.

UI Toolkit, `OnGUI`, `GUI`, `GUILayout`, and opaque custom drawing may decorate
the result but cannot be the only surface for required text, panels, or controls.

### 2.4 Camera, 2D physics, rendering, and audio

- Keep an enabled gameplay camera that renders the challenge and required UI.
- Keep visible route objects on rendered layers with usable proportions and
  ordering.
- When a Rigidbody2D controller is used, match Rigidbody2D, Collider2D, trigger,
  layer, gravity, ground, checkpoint, gate, and finish configuration. A rigidbody
  is allowed but is not a required controller architecture.
- Before writing a material property, verify that the shader exposes it. Do not
  assume every material has `_Color`.
- World-space `LineRenderer` points do not follow a Transform-only move; update
  stored world positions or use consistent local-space points.
- `Destroy` completes at frame end. Deactivate or unregister old objects and
  allow an advancing frame before rebuilding or globally indexing replacements.
- Configure audio components explicitly and keep optional clips null-safe.

### 2.5 Restart and persistence

A same-process Restart must clear transient timer, progress, sign, checkpoint,
gate, player, panel, input, callback, coroutine, effect, and audio state while
preserving only the valid best-time record required by the GDD. Pause and terminal
states must freeze the required gameplay without disabling the visible Restart
control. A genuine reopen uses a different Unity process and starts a clean
challenge while retaining only the valid best time.

## 3. Public Unity CLI tests

Use the current project path. Fully close any Editor that owns this exact project
before a CLI test and wait for its process and project lock to exit.

```powershell
$Project = (Resolve-Path '.').Path
$Editor = 'D:\game\engine\unity\6000.0.80f1\Editor\Unity.exe'
$Cli = 'D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe'
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$SmokeDir = Join-Path $Project 'Logs\PublicSmoke'
New-Item -ItemType Directory -Force -Path $SmokeDir | Out-Null
$EditXml = Join-Path $SmokeDir "public-editmode-$Stamp.xml"
$PlayXml = Join-Path $SmokeDir "public-playmode-$Stamp.xml"

& $Cli --json --non-interactive test $Project `
  --mode EditMode `
  --filter 'OmniGame.Benchmark.SignCircuit.PublicTests.SignCircuitPublicEditModeTests' `
  --output $EditXml --editor-path $Editor --timeout 600
$EditExit = $LASTEXITCODE

& $Cli --json --non-interactive test $Project `
  --mode PlayMode `
  --filter 'OmniGame.Benchmark.SignCircuit.PublicTests.SignCircuitPublicPlayModeTests' `
  --output $PlayXml --editor-path $Editor --timeout 900
$PlayExit = $LASTEXITCODE
```

Required results:

- EditMode: exit `0`, a new readable `$EditXml`, exactly `2/2 Passed`;
- PlayMode: exit `0`, a new readable `$PlayXml`, exactly `1/1 Passed`.

A missing, unreadable, stale, or zero-test XML is not a passing result. Use a new
timestamp and keep the authoritative XML under `Logs/PublicSmoke/`; do not use
root `TestResults.xml` or `TestResults/`.

The EditMode tests check the public contract and saved scene availability. The
PlayMode test loads the saved challenge, advances real player-loop frames, rejects
blocking runtime errors, and checks for a camera. It does not complete the GDD journey.

Graphical authoring may use:

```powershell
& $Cli --json --non-interactive open $Project --editor-path $Editor
```

Use `open` only when the Unity desktop is controllable. A shell-only environment
may author Unity Test Framework self-tests under `Assets/Benchmark/**`; such
self-tests are optional development aids and must not call gameplay result methods
directly.

## 4. Protected read-only observation contract

Keep `Assets/BenchmarkContract/**` unchanged. The public assembly namespace is
`OmniGame.Benchmark.SignCircuit.Contract`, and the schema version is `2`.
Gameplay code publishes current state through:

```csharp
SignCircuitProbePublisher.Publish(snapshot, actionTargets, observationTargets);
```

Publication must be fresh in Menu, Sign Circuit, and preserved legacy play. It is
read-only: it mirrors state and screen locations but does not perform movement,
jump, sign interaction, checkpoint acceptance, gate changes, terminal results,
Restart, scene changes, or persistence.

### 4.1 `SignCircuitSnapshot` fields

```text
schemaVersion
scene
phase
progress
remainingSeconds
targetSignMask
acceptedCheckpointMask
gateOpen
interactionAvailable
hudVisible
pauseVisible
successVisible
failureVisible
hasBestTime
bestTimeSeconds
playerPosition
statusText
feedback
```

`scene` and `phase` must be non-empty. `progress` is in `0..3`. Numeric values must
be finite. The snapshot must agree with the actual current scene, visible state,
player state, route state, and lifecycle state.

### 4.2 `SignCircuitActionTarget` fields and IDs

Fields:

```text
id
screenRect
visible
interactable
label
```

Required IDs:

```text
menu.sign_circuit
menu.levels
menu.original_level
menu.continue
ui.restart
```

### 4.3 `SignCircuitObservationTarget` fields and IDs

Fields:

```text
id
screenRect
visible
```

Required IDs in Sign Circuit:

```text
ui.progress
ui.timer
ui.best
ui.status
panel.pause
panel.success
panel.failure
```

### 4.4 Rectangle and identity rules

- `screenRect` uses bottom-left-origin Game View pixels.
- Clip every rectangle to the actual visible viewport intersection after Canvas
  scaling, anchors, display selection, camera selection, and transforms.
- Publish each semantic ID at most once per snapshot, case-insensitively.
  Duplicate IDs are rejected.
- A visible interactable action target retains at least a `1 x 1` clipped area
  and matches the real visible uGUI control that receives the normal pointer
  press and release.
- An observation target overlaps the corresponding real visible uGUI/TMP text or
  panel surface.
- For `panel.pause`, `panel.success`, and `panel.failure`, publish the visible
  panel container rather than only a title text rectangle. The container needs a
  coherent visible Graphic/background/border and bounded geometry between
  `0.25%` and `95%` of the viewport.
- A rectangle is a locator only. It cannot replace the matching visible control,
  text, panel, or gameplay state.

The required progress, timer, best-time, status, pause, success, failure,
`SIGN CIRCUIT`, original menu actions, and Restart semantics must therefore be
visible through the uGUI/TMP surface profile in Section 2.3.

## 5. Common tool symptoms

| Symptom | Technical check |
|---|---|
| `Arial.ttf is no longer a valid built in font` | Use `LegacyRuntime.ttf` or an imported/serialized font. |
| Required key or pointer has no effect | Check the current Input System device, enabled action or `PlayerInput`, active Game view, UI module, and advancing frames. |
| `CS0246` for InputSystem/UI/TMP/contract | Check pinned package and asmdef references plus script location. |
| Runtime assembly references `UnityEditor` | Move one-shot helper code under `Assets/Benchmark/Editor/**` or remove the dependency. |
| `Missing (Mono Script)` or missing object | Repair and save the serialized scene or prefab reference. |
| Scene cannot load | Save the permitted scene and add the intended entry to Build Settings. |
| UI click misses or also moves the player | Check Canvas, GraphicRaycaster, EventSystem, UI module, raycast-target ordering, target clipping, and UI-first consumption. |
| Material property error | Check `Material.HasProperty` or use the property exposed by the supplied shader. |
| Public PlayMode passes but controls do nothing | The public test proves startup health only; inspect the runtime Input System route and visible control geometry. |
| Restart duplicates behavior | Remove stale listeners, actions, coroutines, static state, spawned objects, and audio, then check repeated Restart. |
