# Roblox Studio engine tool interface catalog

```text
catalog_id: roblox-studio-common-tool-guide
catalog_revision: 2026.08.26-base-interfaces
rojo: configured version
luau_compile: configured version track
scope: game-independent Roblox Studio, Luau, Rojo, and Windows host interfaces
```

This English-only catalog describes individual interfaces available to a Roblox Studio project on the pinned Windows host. It does not prescribe an implementation order, pipeline, validation ladder, gameplay solution, evaluator trajectory, or combination strategy. Project-specific paths, controls, public tests, Tags, Attributes, and delivery requirements belong to each task's `TOOLCHAIN.md` and GDD.

## 1. Supplied tool bindings

Paths are relative to the public input root:

```text
Rojo compiler       Tools/rojo.exe
Luau compiler       Tools/luau-compile.exe
Roblox Studio       discovered under %LOCALAPPDATA%/Roblox/Versions/version-*/RobloxStudioBeta.exe
Studio logs         %LOCALAPPDATA%/Roblox/logs/
```

`Tools/rojo.exe --version` reports the bundled Rojo version. The latest installed `RobloxStudioBeta.exe` by file modification time is normally the current Studio binary, but a caller may bind an explicit verified path.

## 2. Windows host project interfaces

| Interface | Individual operations | Result surface |
|---|---|---|
| shell | Resolve paths, enumerate files, create directories, copy files, start a process, wait for a PID, and read exit codes | objects, stdout, stderr, process state |
| .NET file APIs | Read/write text or bytes, parse JSON/XML, compute hashes, and inspect timestamps | returned objects or exceptions |
| `rg` | Search file names and text with glob filters | matching paths and lines |
| Git | Inspect status, diff, tracked files, and authored changes | textual or machine-readable repository state |
| CIM process queries | Read PID, executable path, creation time, parent PID, and command line | `Win32_Process` records |
| Windows window APIs | Enumerate, identify, focus, and inspect visible windows by exact PID | HWND/PID/title records |
| Windows SendInput | Send ordinary keyboard and mouse press/release events to the verified foreground window | OS input acknowledgement plus observable game response |

File/process operations should use resolved literal paths. A PID is not a durable identity unless its executable path and creation time still match.

## 3. Rojo command interfaces

### Version

```powershell
& '.\Tools\rojo.exe' --version
```

Result surfaces: stdout and process exit code.

### Build a place

```powershell
& '.\Tools\rojo.exe' build '.\project\default.project.json' -o '.\RelayFoundryCandidate.rbxlx'
```

Result surfaces: stdout/stderr, process exit code, the RBXLX file, its timestamp, and its SHA-256. A successful build means the project JSON and `$path` mappings were assembled; it does not compile Luau or prove Play behavior.

### Build a model

```powershell
& '.\Tools\rojo.exe' build '.\path\model.project.json' -o '.\Model.rbxmx'
```

Result surfaces are the same as a place build, with an RBXMX model output.

### Generate a sourcemap

```powershell
& '.\Tools\rojo.exe' sourcemap '.\project\default.project.json' -o '.\sourcemap.json'
```

Result surfaces: process exit code and JSON mapping between filesystem sources and DataModel instances.

### Serve a live project

```powershell
& '.\Tools\rojo.exe' serve '.\project\default.project.json' --port 34872
```

Result surfaces: long-running server PID, console log, port listener, and Studio plugin connection state. The serve process only synchronizes mapped content; it does not start Play or exercise gameplay.

## 4. Luau compiler interface

Compile one source file without emitting bytecode:

```powershell
& '.\Tools\luau-compile.exe' --null '.\project\src\server\Game.server.luau'
```

Compile every Luau source independently:

```powershell
$scripts = Get-ChildItem -LiteralPath '.\project\src' -Recurse -File -Filter '*.luau'
foreach ($script in $scripts) {
    & '.\Tools\luau-compile.exe' --null $script.FullName
    if ($LASTEXITCODE -ne 0) { throw "Luau compile failed: $($script.FullName)" }
}
```

Result surfaces: diagnostics, source location, and process exit code. Compilation validates Luau syntax and compiler-supported semantics; it cannot prove a Roblox class has a guessed runtime member or that the game initializes.

Other supported compiler modes can be inspected with:

```powershell
& '.\Tools\luau-compile.exe' --help
```

## 5. Roblox Studio executable and place interfaces

### Discover installed Studio binaries

```powershell
$versions = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'
$studio = Get-ChildItem -LiteralPath $versions -Recurse -File -Filter 'RobloxStudioBeta.exe' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
```

Result surfaces: absolute executable path, size, version directory, and timestamp.

### Open a local RBXLX

```powershell
$process = Start-Process -FilePath $studio.FullName -ArgumentList @('-localPlaceFile', (Resolve-Path '.\RelayFoundryCandidate.rbxlx').Path) -PassThru
```

Result surfaces: Studio PID, visible window, session log, loaded Edit DataModel, and `OpenPlaceSuccess` records. Opening a place does not mean a PlayClient exists.

### Interactive Play controls

When the correct Studio 3D viewport has foreground focus:

```text
F5          start Play
Shift+F5    stop Play and return to Edit
```

Result surfaces: PlayServer/PlayClient DataModels, rendered viewport, character, Output records, and gameplay state. Keyboard input must target the verified Studio PID and foreground window.

## 6. Studio log interface

Studio session logs are normally written under:

```text
%LOCALAPPDATA%/Roblox/logs/
```

Useful directly observable records include:

```text
OpenPlaceSuccess
Edit / PlayServer / PlayClient DataModel creation
Luau parse errors
"is not a valid member" runtime errors
infinite yield warnings
Creator output from print/warn/error
Studio shutdown and session identity
```

A caller should bind a log by start time, place identity, and Studio PID/session rather than reading an arbitrary newest historical log.

## 7. Roblox API discovery interfaces

| Source | Individual use |
|---|---|
| Roblox Creator API Reference | Read the documented properties, methods, events, inheritance, security, and deprecation state of an engine class |
| Studio API Dump | Inspect machine-readable classes, members, value types, tags, and security for the installed track |
| `ReflectionMetadata.xml` | Inspect editor-facing class/member metadata shipped with Studio |
| Studio Command Bar | Create a minimal instance, read a member, assign a value, or connect an event in a controlled place |
| Minimal Play probe | Observe runtime-only behavior, replication, character, physics, prompt, UI, or service behavior |

An Attribute named like an engine property is still only custom data. For example, `instance:SetAttribute('Enabled', false)` does not disable a class that has no `Enabled` property.

## 8. DataModel construction interfaces

| Type or service | Individual interfaces |
|---|---|
| `Instance` | `new`, `Clone`, `Destroy`, `FindFirstChild`, `WaitForChild`, `IsA`, ancestry and parenting |
| `Workspace` | world instances, gravity, raycasts, overlap queries, current camera, and public Attributes |
| `ReplicatedStorage` | replicated ModuleScripts, values, remotes, and shared configuration |
| `ServerScriptService` | authoritative server Scripts and modules |
| `StarterPlayerScripts` | player LocalScripts and client input/HUD code |
| `StarterGui` | GUI templates cloned to each PlayerGui |
| `Players` | player lifecycle, characters, PlayerGui, and player Attributes |
| `RunService` | server/client identity, frame callbacks, heartbeat, render step, and Studio checks |

`WaitForChild(name, timeout)` returns `nil` after a finite timeout. Unbounded waits can hide failed initialization.

## 9. Attributes and tags

### Attributes

```luau
instance:SetAttribute("StateName", "Ready")
local value = instance:GetAttribute("StateName")
local all = instance:GetAttributes()
local connection = instance:GetAttributeChangedSignal("StateName"):Connect(function() end)
```

Attributes replicate according to their owning instance and are directly observable. They should mirror real state rather than replace physical or player-visible behavior.

### CollectionService tags

```luau
local CollectionService = game:GetService("CollectionService")
CollectionService:AddTag(instance, "SemanticTag")
local tagged = CollectionService:GetTagged("SemanticTag")
local added = CollectionService:GetInstanceAddedSignal("SemanticTag")
local removed = CollectionService:GetInstanceRemovedSignal("SemanticTag")
```

Tags expose semantic discovery independent of object names or hierarchy. A tag alone does not make a decorative object authoritative.

## 10. Player input and interaction interfaces

| Interface | Individual operations |
|---|---|
| `UserInputService` | observe keyboard, mouse, touch, focus, and processed input on the client |
| `ContextActionService` | bind/unbind named actions and receive input-state transitions |
| `ProximityPrompt` | visible nearby keyboard/gamepad/touch interaction, activation distance, hold duration, and prompt events |
| `ProximityPromptService` | observe prompt shown/hidden/triggered events across the client |
| `GuiButton` | activated, mouse/touch/gamepad UI interaction |
| default character controls | WASD movement, mouse camera, Space jump |

Normal player actions should be connected to these visible input routes. Calling business functions, firing remotes directly, or programmatically triggering a prompt is not ordinary player input.

## 11. Character, physics, and navigation interfaces

| Interface | Individual operations |
|---|---|
| `Humanoid` | health, death, movement state, walking, jumping, and respawn-related observation |
| `HumanoidRootPart` | character position, orientation, assembly velocity, and physical contact context |
| `BasePart` | `Touched`, collision, query/touch flags, material, color, size, CFrame, and network ownership facts |
| `Workspace:Raycast` | ray query with `RaycastParams` filters |
| overlap queries | `GetPartBoundsInBox`, `GetPartBoundsInRadius`, and `GetPartsInPart` with `OverlapParams` |
| `PathfindingService` | create a Path and compute waypoints through compatible world geometry |
| `PivotTo` / CFrame writes | move authored models or setup fixtures; not a substitute for normal player movement in gameplay evaluation |

`PathfindingLink` exposes members such as `Attachment0`, `Attachment1`, `Label`, and `IsBidirectional`; do not assume it has an `Enabled` property. Verify unfamiliar members against the current API source or a minimal probe.

## 12. UI interfaces

| Type | Individual interfaces |
|---|---|
| `ScreenGui` | player screen-space GUI root and display ordering |
| `Frame` | panels, backgrounds, grouping, clipping, and layout containers |
| `TextLabel` / `TextButton` | readable text and button interaction |
| `UIListLayout` / `UIGridLayout` | automatic child arrangement |
| `UIScale` / constraints | responsive scale and size limits |
| `BillboardGui` | camera-facing world label anchored to an Adornee |
| `SurfaceGui` | UI rendered on a BasePart face |
| `PlayerGui` | the live player-specific GUI hierarchy |

Use `AbsolutePosition`, `AbsoluteSize`, visibility, clipping, and ZIndex/DisplayOrder to diagnose visible overlap. A GUI instance that exists outside the viewport or behind another layer is not necessarily readable.

## 13. Remote communication interfaces

| Type | Individual interfaces |
|---|---|
| `RemoteEvent` | `FireServer`, `OnServerEvent`, `FireClient`, `FireAllClients`, and `OnClientEvent` |
| `RemoteFunction` | `InvokeServer`, `OnServerInvoke`, `InvokeClient`, and `OnClientInvoke` |
| `BindableEvent` | same-context event communication |
| `BindableFunction` | same-context request/response communication |

The server should validate client requests and own authoritative gameplay state. An evaluator may observe ordinary replicated state but should not invoke candidate remotes or business functions as a player shortcut.

## 14. Rendering, image, audio, and persistence interfaces

| Interface | Individual operations |
|---|---|
| `Lighting` and effects | brightness, clock, atmosphere, color correction, bloom, depth of field, and shadows |
| `Camera` | CFrame, focus, viewport size, projection, and screen/world conversions |
| built-in materials | visual material selection without external media |
| `Sound` / `SoundService` | playback, looping, volume, and grouping when an accessible sound asset is provided |
| `DataStoreService` | published-experience persistence; Studio availability depends on settings and network access |
| `HttpService` JSON methods | encode/decode JSON; outbound HTTP requires permission and is not assumed by an offline task |

External marketplace IDs and network services should not become undeclared dependencies.

## 15. Result interfaces

| Result type | Observable surface |
|---|---|
| Luau diagnostics | compiler stdout/stderr and exit code |
| Rojo build | process result, RBXLX/RBXMX bytes, timestamp, XML structure, and SHA-256 |
| Studio Edit session | exact PID/window, OpenPlace record, DataModel, Output, and session log |
| Studio Play session | PlayServer/PlayClient, viewport, character, replicated state, HUD, physics, and Output |
| JSON/JSONL | project-owned snapshots, manifests, checkpoints, traces, and receipts |
| PNG | captured visible viewport or fixed-state visual evidence |

Generated caches, lock files, temporary QA places, and historical logs are not source assets and should not be treated as authored project content.
