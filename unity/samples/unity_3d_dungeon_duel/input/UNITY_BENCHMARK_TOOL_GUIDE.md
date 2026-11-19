# Unity Engine Tool Interface Catalog

```text
catalog_id: unity-common-tool-guide
catalog_revision: 2026.08.26-base-interfaces
unity_editor: 6000.0.80f1
unity_cli: 1.0.0-beta.3
input_system_track: 1.19.x
scope: game-independent Unity and host interfaces
```

This English-only catalog describes individual interfaces available on the pinned Unity host.
It does not define a required order, strategy, validation ladder, or implementation workflow.
Project-specific scenes, assets, controls, tests, contracts, and writable paths are declared by
each task.

## 1. Fixed host bindings

```text
Unity Editor  D:\game\engine\unity\6000.0.80f1\Editor\Unity.exe
Unity CLI     D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe
Input System  1.19.x
```

The project `ProjectSettings/ProjectVersion.txt` and `Packages/manifest.json` remain the
source of truth for project versions. Files under `D:\game\engine` are host-owned and are not
project authoring targets.

## 2. Host project interfaces

| Interface | Available operations | Result surface |
|---|---|---|
| PowerShell | Start processes, inspect files, create directories, copy files, and compose command arguments | stdout, stderr, process exit code |
| .NET file APIs | Read and write text or bytes, resolve paths, enumerate files, compute hashes, and parse XML/JSON | returned objects or exceptions |
| `rg` | Search file names and text with glob filters | matching paths and lines |
| Git | Inspect status, diff, tracked files, and authored changes | textual or machine-readable repository state |
| CIM process queries | Read Windows process IDs and command lines | `Win32_Process` records |

## 3. Unity CLI global interface

General form:

```text
unity [global-options] <command> [command-options]
```

| Option | Interface |
|---|---|
| `--format human|json|tsv|ndjson` | Select the CLI output encoding |
| `--json` | Alias for `--format json` |
| `--non-interactive` | Disable interactive prompts |
| `--quiet` | Suppress informational output |
| `--verbose` | Include detailed failure information and stack traces |
| `--no-banner` | Suppress the startup banner |
| `--proxy <url>` | Set an HTTP, HTTPS, SOCKS, or PAC proxy for the invocation |
| `--proxy-disable` | Ignore proxy settings for the invocation |
| `--log-proxy` | Record outbound requests in `proxy-request.json` |
| `--no-log-proxy` | Disable proxy request logging for the invocation |
| `--version` | Print the CLI version |

CLI options belong before the raw Unity-argument separator `--`. A project path is supplied
as the command's positional project argument; a duplicate raw `-projectPath` is not needed.

## 4. Unity CLI project commands

### `unity run`

Batch-mode Editor invocation for import, compilation, or a project-owned static method.

```text
unity run [project]
  [--editor-path <path>]
  [--editor-version <version>]
  [--architecture <arch>]
  [--timeout <seconds>]
  [-- <raw Unity Editor arguments>]
```

Common raw Editor arguments include:

```text
-executeMethod <Namespace.Type.Method>
-logFile <path>
-nographics
-quit
```

Result surfaces are the CLI response, process exit code, the requested Editor log, and any
project-owned files written by the invoked method.

### `unity test`

Unity Test Framework invocation.

```text
unity test [project]
  [--mode EditMode|PlayMode]
  [--filter <pattern>]
  [--output <nunit-xml-path>]
  [--editor-path <path>]
  [--editor-version <version>]
  [--architecture <arch>]
  [--timeout <seconds>]
  [-- <raw Unity Editor arguments>]
```

Result surfaces are the CLI response, process exit code, NUnit XML, and any requested Editor
log. A failed test command can return a nonzero CLI exit code while still writing a readable
NUnit XML file containing the individual test results.

### `unity build`

Player-build invocation backed by a project-owned static build method.

```text
unity build [project]
  --target <build-target>
  --execute-method <Namespace.Type.Method>
  [--build-target-group <group>]
  [--output-path <path>]
  [--log-file <path>]
  [--editor-path <path>]
  [--editor-version <version>]
  [--architecture <arch>]
  [--args <string>]
  [--no-tail]
  [--allow-dirty-build]
```

The static method receives Unity's command line and owns the actual `BuildPipeline` call.
Result surfaces are the CLI response, process exit code, build log, and project-defined build
output.

### `unity open`

Interactive Editor launch.

```text
unity open [project]
  [--editor-path <path>]
  [--editor-version <version>]
  [--architecture <arch>]
  [--build-target <target>]
  [--build-target-group <group>]
  [--args <raw Unity Editor argument string>]
```

Result surfaces are the CLI launch response, the Editor process, and any explicitly requested
Editor log.

## 5. Unity CLI host-information commands

| Command | Interface | Result surface |
|---|---|---|
| `unity doctor --json` | Inspect CLI version, installed Editors, authentication state, PATH state, Windows long-path state, proxy state, and recent CLI logs | structured diagnostic report |
| `unity license status --json` | Read current sign-in and license activity | structured license status |
| `unity license list --json` | List visible licenses | structured license records |
| `unity cache info --json` | Read Unity CLI download-cache location and size | structured cache information |
| `unity diagnose proxy --json` | Produce a redacted proxy diagnostic report | stdout and a diagnostic file |
| `unity env --json` | Read Unity Hub environment locations | structured environment information |
| `unity language` | Read the current CLI display language | textual CLI state |
| `unity language --set <code>` | Change the CLI display language preference | updated CLI preference |
| `unity shell --protocol ndjson` | Expose the CLI through a persistent NDJSON request/response stream | NDJSON over stdin/stdout |

Engine installation, upgrade, removal, cloud, account-management, analytics, and cache deletion
commands are outside this project-authoring catalog.

## 6. Unity Editor scripting interfaces

Editor-only APIs belong in an `Editor/` folder or an Editor-only assembly definition.
Runtime assemblies cannot reference `UnityEditor`.

| Namespace or type | Individual interfaces |
|---|---|
| `UnityEditor.AssetDatabase` | Find, create, copy, move, delete, import, refresh, load, and save project assets |
| `UnityEditor.SceneManagement.EditorSceneManager` | Create, open, inspect, mark dirty, and save Scene assets |
| `UnityEditor.PrefabUtility` | Create Prefabs, instantiate Prefabs, inspect instance status, and apply or revert overrides |
| `UnityEditor.SerializedObject` / `SerializedProperty` | Read and write serialized object fields through Unity serialization |
| `UnityEditor.EditorBuildSettings` | Read or replace the enabled Scene list |
| `UnityEditor.BuildPipeline` | Build a Player from project Scenes and build options |
| `UnityEditor.Build.Reporting.BuildReport` | Read structured Player-build results |
| `UnityEditor.Compilation.CompilationPipeline` | Inspect assemblies and compilation events |
| `UnityEditor.EditorApplication` | Read Editor state, schedule callbacks, control play/pause, and request Editor exit |
| `UnityEditor.EditorUtility` | Mark objects dirty, display progress, and expose Editor utility operations |
| `UnityEditor.TestTools.TestRunner.Api.TestRunnerApi` | Programmatically list or execute Unity Test Framework tests |
| `UnityEditor.MenuItem` | Register project-owned Editor menu commands |

## 7. Unity runtime construction and observation interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `UnityEngine.GameObject` / `Component` | Create objects, add or query components, set active state, tags, layers, and hierarchy |
| `UnityEngine.Transform` / `RectTransform` | Read and write position, rotation, scale, anchors, pivots, offsets, and parent relationships |
| `UnityEngine.Object` | Instantiate, destroy, find, and compare Unity objects |
| `UnityEngine.ScriptableObject` | Create runtime or serialized data objects |
| `UnityEngine.SceneManagement.SceneManager` | Load, unload, query, and switch runtime Scenes |
| `UnityEngine.Resources` | Load assets under a project `Resources` folder |
| `UnityEngine.JsonUtility` | Serialize and deserialize Unity-compatible JSON data |
| `UnityEngine.PlayerPrefs` | Read, write, save, and delete small persistent preference values |
| `Application.persistentDataPath` | Resolve the platform-specific persistent-data directory |
| `Debug.Log`, `LogWarning`, `LogError`, `LogException` | Write runtime or Editor console records |

`Object.Destroy` completes at the end of a frame. Destroyed Unity objects use Unity's
fake-null behavior.

## 8. Input System 1.19.x interfaces

### Runtime input

```text
Keyboard.current
Mouse.current
Gamepad.current
InputAction
InputActionMap
InputActionAsset
InputActionReference
PlayerInput
InputSystemUIInputModule
```

### Device and state interfaces

```text
InputSystem.AddDevice<TDevice>()
InputSystem.RemoveDevice(device)
device.MakeCurrent()
InputSystem.QueueStateEvent(device, state)
InputSystem.QueueDeltaStateEvent(control, value)
InputState.Change(deviceOrControl, state, updateType)
InputSystem.Update()
InputUser.PerformPairingWithDevice(device, user)
```

Relevant low-level state types include:

```text
KeyboardState
MouseState
GamepadState
MouseButton
InputUpdateType
```

### Input test interfaces

```text
InputTestFixture
Press(control)
Release(control)
Set(control, value)
```

Legacy `UnityEngine.Input.GetKey*`, `GetMouseButton*`, and `Input.mousePosition` can throw at
runtime when the project enables only the new Input System backend.

## 9. UI and event interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `UnityEngine.Canvas` | Screen Space Overlay, Screen Space Camera, and World Space UI roots |
| `UnityEngine.UI.GraphicRaycaster` | Raycast against uGUI graphics |
| `UnityEngine.EventSystems.EventSystem` | Current selection, pointer routing, and `RaycastAll` |
| `UnityEngine.EventSystems.PointerEventData` | Pointer position and event payload |
| `UnityEngine.InputSystem.UI.InputSystemUIInputModule` | Route Input System actions into the EventSystem |
| `UnityEngine.UI.Button`, `Image`, `Text` | Standard uGUI controls and graphics |
| `TMPro.TMP_Text`, `TextMeshProUGUI` | TextMesh Pro text when the project includes TMP |
| `RectTransformUtility` | Convert among screen, world, and RectTransform coordinates |

Unity 6 exposes the built-in legacy runtime font as `LegacyRuntime.ttf`; the old built-in
name `Arial.ttf` is not accepted by `Resources.GetBuiltinResource<Font>`.

## 10. Camera, rendering, image, and geometry interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `Camera` | `ScreenToWorldPoint`, `WorldToScreenPoint`, culling, target textures, and explicit `Render()` |
| `RenderTexture` | Off-screen camera targets |
| `Texture2D` | `ReadPixels`, `Apply`, pixel access, and `EncodeToPNG` |
| `ScreenCapture` | `CaptureScreenshot` for a rendered Game view |
| `ImageConversion` | Decode encoded image bytes into textures |
| `Renderer` / `SpriteRenderer` | Visible bounds, sorting, material, color, and sprite state |
| `LineRenderer` | Polyline geometry in world or local space |
| `Material` / `Shader` | Property discovery and material state |
| `Physics` / `Physics2D` | Raycast, overlap, collider, layer-mask, and contact queries |
| `Collider` / `Collider2D` | Player-facing or simulation hit geometry |
| `CanvasRenderer` / `Graphic` | uGUI render and raycast geometry |

A Camera render to a `RenderTexture` does not automatically include a Screen Space Overlay
Canvas. `ScreenCapture.CaptureScreenshot` depends on a rendered Game view. Shader properties
can be queried with `Material.HasProperty`.

## 11. Animation, navigation, lifecycle, and audio interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `Animator` / `AnimationClip` | Animator parameters, states, clips, and runtime playback |
| `PlayableDirector` / Timeline types | Timeline playback when the project includes Timeline |
| `NavMesh` / `NavMeshAgent` | Navigation queries and agent movement when navigation data is available |
| `Coroutine`, `WaitForSeconds`, `WaitUntil` | Frame-spanning runtime behavior |
| `Time` | Delta time, real time, time scale, and frame count |
| `AudioSource` / `AudioClip` | Audio playback, one-shot playback, volume, pitch, and looping |
| `Application` | Paths, platform information, focus, quit, and lifecycle events |

`AudioSource.PlayOneShot(clip)` accepts an explicit clip even when `AudioSource.clip` is null.
A `NavMeshAgent` requires compatible reachable navigation data.

## 12. Unity Test Framework interfaces

```text
[Test]
[TestCase]
[UnityTest]
[SetUp]
[TearDown]
[UnitySetUp]
[UnityTearDown]
Assert
LogAssert
```

EditMode tests execute in the Editor test platform. Frame-based PlayMode `[UnityTest]` tests
can advance Scenes, coroutines, rendering, Input System updates, and runtime lifecycle code.
NUnit XML is the standard structured result format exposed by `unity test`.

## 13. Project-local result interfaces

| Result type | Interface |
|---|---|
| Editor log | Compiler diagnostics, import output, runtime exceptions, test-run details, and Editor shutdown state |
| NUnit XML | Test discovery count, pass/fail/skip state, assertions, messages, and stack traces |
| JSON | Project-owned structured snapshots, diagnostics, manifests, or command results |
| PNG | Game-view, Camera, RenderTexture, or project-owned image captures |
| Text or JSONL logs | Project-owned runtime traces and incremental observations |
| Unity YAML assets | Serialized Scenes, Prefabs, materials, settings, and references |

Unity can recreate `Library/`, `Temp/`, and `Logs/`. Output durability depends on the path
selected by the caller and the task's writable-path contract.
