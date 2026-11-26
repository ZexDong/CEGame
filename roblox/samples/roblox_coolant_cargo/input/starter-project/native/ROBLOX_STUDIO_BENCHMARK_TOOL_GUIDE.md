# Roblox Studio Engine Tool Interface Catalog

```text
catalog_id: roblox-studio-common-tool-guide
catalog_revision: 2026.08.26-verified-interfaces
engine: Roblox Studio (installed host version)
language: Luau
project_builder: Rojo 7.x
scope: game-independent Roblox Studio and Windows host interfaces
```

This English-only catalog describes individual interfaces available to a game-development agent. It does not prescribe an implementation order, a pipeline, an evaluator trajectory, or a required combination of tools. A task may expose only a subset of these interfaces; the task-local `TOOLCHAIN.md` is the source of truth for paths.

## 1. Host file and process interfaces

| Interface | Individual operations | Result surface |
|---|---|---|
| shell | Resolve paths, inspect/copy files, create directories, launch processes, read exit codes | objects, stdout, stderr, exit code |
| .NET file APIs | Read/write text or bytes, parse JSON/XML, enumerate paths, compute SHA-256 | returned objects or exceptions |
| `rg` | Search file names and text | matching paths and lines |
| Git | Inspect status, diff, revision and tracked files | text or machine-readable output |
| CIM process queries | Read process IDs, creation times, command lines and window state | `Win32_Process` records |

Host-owned engine installations and caches are not project-authoring targets.

## 2. Rojo project interface

Rojo maps filesystem source into a Roblox DataModel and can build an XML place:

```powershell
rojo build .\default.project.json --output .\Game.rbxlx
```

Important project-file fields and mappings include:

```text
name
tree
$className
$path
$properties
*.server.luau  -> Script
*.client.luau  -> LocalScript
*.luau         -> ModuleScript when mapped as a module
```

Result surfaces are stdout, stderr, the process exit code and the generated `.rbxlx`. Rojo validates project mapping and serialization; it does not prove Luau syntax, Roblox API validity, runtime initialization, input, HUD behavior or gameplay completion.

All `$path` values in a deliverable project should be project-relative. Absolute developer-machine paths are unsuitable for a portable submission.

## 3. Luau compiler interface

`luau-compile` parses and compiles individual Luau files:

```powershell
luau-compile.exe .\src\server\GameServer.server.luau
```

Each `.luau` file can be invoked independently. The bundled verified compiler accepts the source path directly; its `--mode` spelling varies across Luau builds, so the portable public smoke does not require that optional flag. Result surfaces are compiler diagnostics and exit code. A zero exit code proves syntax/bytecode compilation only; it does not validate engine class members or runtime permissions.

Luau multiple-local syntax uses one identifier list and one expression list:

```luau
local lockId, action = getLockId(), getAction()
```

Do not write `local lockId = getLockId(), action = getAction()`.

## 4. Roblox Studio place interfaces

Roblox Studio can open `.rbxl` or `.rbxlx` places interactively. Observable host surfaces include:

- a visible Studio main window;
- `OpenPlaceSuccess` and place identity in the Studio log;
- Edit, PlayServer and PlayClient DataModel lifecycle records;
- Creator Output records from `print`, `warn` and runtime errors;
- clean return from Play to Edit.

Opening a place in Edit mode is different from executing it in Play. A successful Rojo build or `OpenPlaceSuccess` does not imply a successful PlayServer or PlayClient.

Only evaluator-owned Studio PIDs may be closed automatically. A hidden helper process without a visible main window is not, by itself, proof that an interactive Studio window is still open.

## 5. Windows virtual input interfaces

Windows `SendInput` can emit physical-equivalent keyboard and mouse input to the foreground Studio window. Individual inputs include key down, key up, key tap, mouse move, mouse button down/up and wheel movement.

Common Roblox/Studio keys include:

```text
W A S D       character movement
Space         jump
E             common ProximityPrompt action
R             task-defined restart when declared by the GDD
F5            start Play in Studio
F6            stop Play in Studio
```

Before sending input, callers can independently verify the live HWND, foreground process, visible title and 3D viewport focus. Input acceptance can be observed through engine position, velocity, camera or `UserInputService` state. Merely issuing a key event is not proof that the game received it.

## 6. Core DataModel and Instance interfaces

| Interface | Individual operations |
|---|---|
| `game:GetService(name)` | Resolve an engine service |
| `Instance.new(className)` | Create an engine object |
| `Instance.Parent` | Attach or detach hierarchy members |
| `FindFirstChild`, `WaitForChild(name, timeout)` | Resolve children immediately or with a bounded wait |
| `GetChildren`, `GetDescendants` | Enumerate hierarchy |
| `IsA`, `ClassName` | Validate runtime type |
| `Clone`, `Destroy` | Duplicate or remove objects |
| `GetAttribute`, `SetAttribute`, `GetAttributes` | Read/write public custom state |
| `GetPropertyChangedSignal` | Observe property changes |

Use bounded `WaitForChild` when a server-created object may fail to appear. A custom Attribute records data but does not automatically implement an engine behavior.

## 7. Services commonly used by Roblox games

| Service | Individual interfaces |
|---|---|
| `Players` | player lifecycle, characters, `LocalPlayer`, respawn |
| `Workspace` | world hierarchy, raycasts, server-time access, spatial queries |
| `ReplicatedStorage` | shared modules, public RemoteEvents and replicated state |
| `ServerScriptService` | authoritative server scripts |
| `StarterPlayer` / `StarterPlayerScripts` | player and LocalScript defaults |
| `StarterGui` / `PlayerGui` | GUI templates and live player GUI |
| `CollectionService` | add/query/remove semantic Tags |
| `TweenService` | timed property interpolation |
| `PathfindingService` | compute navigation paths and inspect waypoint status |
| `RunService` | frame events and server/client context |
| `UserInputService` | keyboard, mouse, touch and processed-input events |
| `ContextActionService` | bind and unbind named player actions |
| `HttpService` | JSON encode/decode and GUID generation; network requests require separate permission |

## 8. Parts, characters, collision and touch

`BasePart` exposes position, CFrame, size, velocity, anchoring, collision, touch and visual material state. Useful surfaces include:

```text
Position, CFrame, Size
AssemblyLinearVelocity
Anchored, CanCollide, CanTouch, CanQuery
Touched, TouchEnded
Color, Material, Transparency
GetTouchingParts()
```

Characters commonly expose `Humanoid`, `HumanoidRootPart`, health, movement state and respawn lifecycle. Collision and touch should be observed in live Play when behavior depends on physics.

Engine-owned properties are not uniformly writable from normal Scripts. In the currently observed Studio host, assigning `Workspace.FallenPartsDestroyHeight` from an ordinary server Script raises a capability error and terminates that script. Configure such place-level settings in the serialized place/project when supported, or implement game hazards with explicit parts and server logic.

## 9. Semantic discovery interfaces

`CollectionService` Tags, Attributes and stable public names can expose a layout-independent protocol:

```luau
local objects = CollectionService:GetTagged("GAME_Interactable")
local role = object:GetAttribute("GAME_Role")
```

Callers can validate uniqueness, class and Attribute schema before using an object. Tags and Attributes identify semantics; they do not replace physical collision, prompts or engine state transitions.

## 10. ProximityPrompt interfaces

`ProximityPrompt` exposes player-facing interaction properties such as:

```text
ActionText, ObjectText
KeyboardKeyCode
MaxActivationDistance
HoldDuration
RequiresLineOfSight
Enabled
Triggered, TriggerEnded
```

The prompt must be attached to a supported world object or attachment. A player normally activates it with the configured real input while within range.

## 11. Client/server communication

| Interface | Individual operations |
|---|---|
| `RemoteEvent` | `FireServer`, `OnServerEvent`, `FireClient`, `OnClientEvent` |
| `RemoteFunction` | request/response invocation when required |
| replicated Attributes | server-authored state visible to clients |

Server code should validate player identity, state, range and ordering for business actions. Client code should use finite waits and visible startup warnings if required remotes are unavailable.

## 12. UI interfaces

| Class | Individual interfaces |
|---|---|
| `ScreenGui` | live screen-space GUI root |
| `Frame` | layout panel and visual grouping |
| `TextLabel`, `TextButton` | text, status and button presentation |
| `ImageLabel`, `ImageButton` | raster asset presentation |
| `UIListLayout`, `UIGridLayout`, `UIPadding` | layout and spacing |
| `BillboardGui`, `SurfaceGui` | world-attached UI |

Common properties include `Visible`, `Text`, `TextColor3`, `BackgroundColor3`, `Size`, `Position`, `AnchorPoint`, `LayoutOrder`, `AbsolutePosition` and `AbsoluteSize`. Runtime HUD state is observed under the player's `PlayerGui`, not only under `StarterGui`.

## 13. Camera and rendering interfaces

`Workspace.CurrentCamera` exposes camera type, CFrame, focus, field of view and viewport size. `WorldToViewportPoint` and `ViewportPointToRay` convert between semantic world targets and the current view.

Formal engine-state evaluation need not use screenshots. Screenshots may be captured separately for visual presentation or a declared visual-only dimension.

## 14. Tweening, timing and lifecycle

`TweenService:Create(instance, TweenInfo, goals)` creates an asynchronous transition. `Tween.Completed` exposes completion. `task.wait`, `task.delay`, `task.spawn`, `os.clock` and `Workspace:GetServerTimeNow()` expose timing surfaces.

Long-running tasks should bind work to a run/revision token when restart can occur, so an old delayed callback cannot mutate a new run. Restart can independently reset player Attributes, world collision, doors, prompts, carried objects, timers and completion state.

## 15. Pathfinding interfaces and caveats

`PathfindingService:CreatePath()` creates a path query. A computed `Path` exposes `Status` and `GetWaypoints()`. Characters can follow waypoints through normal movement or `Humanoid:MoveTo` in game-owned NPC logic.

`PathfindingLink` exposes `Attachment0`, `Attachment1`, `Label` and `IsBidirectional`. It does not expose an `Enabled` property in the verified host metadata. `link:SetAttribute("Enabled", false)` only stores custom data; it does not disable the engine link.

## 16. Logging and structured result interfaces

| Result surface | Typical content |
|---|---|
| Studio session log | place identity, DataModel lifecycle, runtime errors, Output records |
| `print` / `warn` | concise runtime state and diagnostics |
| JSON / JSONL | project-owned manifests, snapshots and incremental evidence |
| RBXLX | XML place generated by Rojo or Studio |
| SHA-256 manifest | immutable identity for source, place, tool and result files |
| PNG | optional visual-only capture |

Short line-oriented JSON records are less likely to be truncated than one very large Output record.

## 17. API discovery interfaces

Before using an unfamiliar class member, an agent may independently consult:

- Roblox Creator API documentation;
- the installed Studio API dump or reflection metadata;
- Studio autocomplete and Properties inspection;
- a minimal isolated Studio probe that creates the class and reads/writes the member.

Class names do not imply symmetric properties. Rojo success and Luau syntax success are not evidence that a runtime member exists or is writable.
