# Roblox Studio Engine Tool Interface Catalog

```text
catalog_id: roblox-studio-common-tool-guide
catalog_revision: 2026.08.31-base-interfaces
roblox_studio: Stable Windows channel
rojo_cli: 7.7.0
luau_cli: bundled host build
scope: game-independent Roblox Studio, Luau, Rojo, and host interfaces
```

This English-only catalog describes individual interfaces available on the Roblox Studio host.
It does not define a required order, strategy, validation ladder, implementation workflow, game
logic, or evaluation method. Project-specific places, assets, controls, contracts, tests, and
writable paths are declared by each task.

## 1. Fixed host bindings

```text
Roblox Studio  RobloxStudioBeta.exe from the installed Stable channel
Rojo CLI      rojo.exe 7.7.0
Luau compiler luau-compile.exe from the bundled host tools
Shell         Windows PowerShell or PowerShell 7
```

The active Roblox Studio installation can be located under the per-user Roblox `Versions`
directory. The task manifest and Rojo project file remain the source of truth for project paths.
Host-installed engine and tool files are not project authoring targets.

## 2. Host project interfaces

| Interface | Available operations | Result surface |
|---|---|---|
| PowerShell | Start processes, inspect files, create directories, copy files, and compose command arguments | stdout, stderr, process exit code |
| .NET file APIs | Read and write text or bytes, resolve paths, enumerate files, compute hashes, and parse XML/JSON | returned objects or exceptions |
| `rg` | Search file names and text with glob filters | matching paths and lines |
| Git | Inspect status, diff, tracked files, and authored changes | textual or machine-readable repository state |
| CIM process queries | Read Windows process IDs, executable paths, and command lines | `Win32_Process` records |
| SHA-256 | Compute a content identity with `Get-FileHash` or .NET cryptography APIs | hexadecimal digest |
| ZIP APIs | Create, read, and enumerate ZIP archives | archive files, entry records, or exceptions |

## 3. Roblox Studio application interfaces

| Interface | Available operations | Result surface |
|---|---|---|
| Explorer | Inspect the DataModel hierarchy; create, rename, duplicate, reparent, and delete instances | visible hierarchy and selection |
| Properties | Read and write exposed instance properties and Attributes | property values and editor validation |
| Script Editor | Create and edit Script, LocalScript, and ModuleScript source | source text and editor diagnostics |
| Output | Display engine messages, script output, warnings, errors, and stack traces | timestamped console records |
| Play | Start or stop a Studio server and local client session | Play windows, runtime DataModel, Output, and logs |
| Run | Start or stop simulation without a player character | runtime DataModel, Output, and logs |
| Command Bar | Execute Luau in the current Studio context | returned values, DataModel changes, or errors |
| Tag Editor | Add, remove, and inspect CollectionService Tags | Tag membership shown in Studio |
| Asset Manager | Inspect and insert project-accessible images, meshes, audio, packages, and places | imported assets and asset identifiers |
| Toolbox | Search and insert permitted Creator Store assets | inserted instances and asset metadata |
| Terrain Editor | Create, import, paint, replace, and clear Terrain regions | Terrain voxel data |
| Material Manager | Inspect and apply built-in or project material variants | material assignments and variants |
| Device Emulator | Change viewport device, resolution, orientation, and safe-area presentation | emulated Game view |
| Plugin Manager | Enable, disable, install, update, or remove Studio plugins | installed plugin state |

## 4. DataModel and instance interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `game` / `DataModel` | `GetService`, descendant queries, place identifiers, creator identifiers, and close callbacks |
| `Instance` | `new`, `Clone`, `Destroy`, `FindFirstChild`, `WaitForChild`, `GetChildren`, `GetDescendants`, `IsA`, `IsDescendantOf` |
| `PVInstance` / `Model` | `GetPivot`, `PivotTo`, `GetBoundingBox`, `GetScale`, `ScaleTo`, and primary-part properties |
| `Workspace` | World properties, part queries, raycasts, server time, Terrain, and CurrentCamera |
| `ReplicatedStorage` | Instances replicated to server and clients |
| `ServerStorage` | Server-only instance storage |
| `ServerScriptService` | Server Script hosting |
| `StarterPlayer` | Player/character defaults, StarterPlayerScripts, and StarterCharacterScripts |
| `StarterGui` | GUI instances copied to PlayerGui |
| `Lighting` | Time, brightness, atmosphere, effects, and environment lighting |
| `SoundService` | Global audio properties and SoundGroup routing |
| `Teams` | Team instances and team assignment properties |

## 5. Properties, Attributes, Tags, and signals

| Interface | Individual operations | Result surface |
|---|---|---|
| Properties | Direct property read and assignment on a compatible class | property value or runtime error |
| Attributes | `SetAttribute`, `GetAttribute`, `GetAttributes`, `GetAttributeChangedSignal` | Attribute values and change signals |
| CollectionService Tags | `AddTag`, `RemoveTag`, `HasTag`, `GetTags`, `GetTagged`, instance-added and instance-removed signals | tagged instance collections and signals |
| `RBXScriptSignal` | `Connect`, `Once`, `Wait` | `RBXScriptConnection` or yielded event results |
| `RBXScriptConnection` | `Connected`, `Disconnect` | connection state |
| `BindableEvent` | `Fire`, `Event` | in-process event delivery |
| `BindableFunction` | `Invoke`, `OnInvoke` | in-process request return value |

Attributes and Tags are available through both Studio and Luau. Class properties are defined by
the Roblox API for each instance type.

## 6. World, geometry, and physics interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `BasePart` | Transform, size, anchoring, collision, touch, query, transparency, assembly velocity, network ownership, and touch signals |
| `Part` | Block, ball, cylinder, wedge, and corner-wedge primitive geometry |
| `MeshPart` | Mesh identifier, texture identifier, collision fidelity, render fidelity, and mesh geometry |
| `Attachment` | Local/world transforms and attachment relationships |
| `WeldConstraint` | Part0, Part1, enabled state, and part connection |
| `Motor6D` | Part0, Part1, C0, C1, Transform, and rig connection |
| Constraint classes | Align, hinge, spring, rope, rod, vector force, linear velocity, angular velocity, and related constraints |
| `RaycastParams` | Filter type, filter descendants, collision group, water handling, and query flags |
| `RaycastResult` | Hit instance, position, normal, material, and distance |
| `OverlapParams` | Filter type, filter descendants, collision group, and result limits |
| `PhysicsService` | Collision-group registration and collision relationships |
| `Terrain` | Voxel regions, fill primitives, copy regions, and material colors |

## 7. Character and player interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `Players` | Player enumeration, join/leave signals, character lookup, user lookup, and Humanoid descriptions |
| `Player` | Character, PlayerGui, Backpack, Team, attributes, respawn, and client player properties |
| `Humanoid` | Health, movement properties, states, animations, movement requests, descriptions, and death signals |
| `HumanoidRootPart` | Character root transform and BasePart assembly properties |
| `HumanoidDescription` | Appearance, body scale, animation, clothing, accessory, and emote properties |
| `Backpack` | Container for player-owned Tool instances |
| `Tool` | Equip state, activation signals, handle, tooltip, texture, and grip properties |
| `ContextActionService` | Named input-action bindings and touch buttons |

## 8. Interaction and communication interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `ProximityPrompt` | Keys, hold duration, activation distance, text, enabled state, exclusivity, and prompt signals |
| `ProximityPromptService` | Global prompt shown, hidden, triggered, and hold signals |
| `ClickDetector` | Activation distance, cursor icon, click, hover, and right-click signals |
| `RemoteEvent` | `FireServer`, `FireClient`, `FireAllClients`, `OnServerEvent`, and `OnClientEvent` |
| `RemoteFunction` | `InvokeServer`, `InvokeClient`, `OnServerInvoke`, and `OnClientInvoke` |
| `UnreliableRemoteEvent` | Unreliable client/server event-transfer interfaces |
| `TextChatService` | Chat version, channels, commands, message properties, and delivery callbacks |

## 9. Input and camera interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `UserInputService` | Keyboard, mouse, touch, gamepad, text-box focus, mouse behavior, and input signals |
| `ContextActionService` | Action bindings, priorities, input types, and touch-button properties |
| `GuiService` | GUI inset, selected object, navigation, safe-zone, and menu signals |
| `Camera` | Camera type, subject, CFrame, field of view, viewport size, world/viewport conversion, and ray generation |
| `Mouse` | Hit transform, target, screen coordinates, icon, button, movement, and wheel signals |
| `HapticService` | Supported vibration motors and motor values |
| `VRService` | VR enablement, head/controller transforms, and recenter signals |

## 10. User interface interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `ScreenGui` | Display order, inset handling, safe area, enabled state, and reset-on-spawn properties |
| `SurfaceGui` / `BillboardGui` | World-space UI face, adornee, size, distance, offset, and visibility properties |
| `GuiObject` | Position, size, anchor, rotation, visibility, active state, ZIndex, automatic size, clipping, and input signals |
| `Frame` / `ScrollingFrame` | Container styling, scrolling, canvas, scrollbar, and layout properties |
| `TextLabel` / `TextButton` / `TextBox` | Text, font, size, scaling, wrapping, editing, activation, and selection properties |
| `ImageLabel` / `ImageButton` | Image, color, transparency, scale type, slice, hover, and activation properties |
| `ViewportFrame` | WorldModel, CurrentCamera, ambient color, light color, and light direction |
| UI layout classes | List, grid, page, table, padding, scale, aspect-ratio, and size constraints |
| UI appearance classes | Corner, stroke, and gradient properties |

## 11. Runtime services

| Namespace or type | Individual interfaces |
|---|---|
| `RunService` | Runtime-mode queries and Stepped, Heartbeat, PreSimulation, PostSimulation, and RenderStepped signals |
| `TweenService` | Tween creation and interpolation values |
| `Debris` | Scheduled instance removal |
| `HttpService` | JSON encode/decode, GUID generation, URL encoding, and enabled HTTP requests |
| `MemoryStoreService` | Sorted maps, queues, and hash maps |
| `DataStoreService` | Named data stores, ordered stores, and versioned keys |
| `MessagingService` | Cross-server topic publish and subscribe |
| `TeleportService` | Place/server teleport operations and options |
| `MarketplaceService` | Product, pass, asset, subscription, and purchase information |
| `BadgeService` | Badge information, ownership checks, and award operations |
| `LocalizationService` | Locale, translator, and localization-table interfaces |

Service availability can depend on Studio settings, publication state, permissions, and network
access.

## 12. Rendering, effects, and asset interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `Lighting` | Environment time, ambient colors, exposure, shadows, technology, and child effects |
| `Atmosphere` | Density, offset, color, decay, glare, and haze |
| Post-processing effects | Bloom, blur, color correction, depth of field, and sun rays |
| `ParticleEmitter` | Texture, rate, lifetime, speed, spread, color, size, transparency, light, and emission controls |
| `Beam` / `Trail` | Attachment endpoints, texture, width, color, transparency, curve, and lifetime properties |
| `Highlight` | Adornee, fill, outline, color, transparency, and depth mode |
| `Decal` / `Texture` | Image, color, transparency, face, tiling, and offset properties |
| `SurfaceAppearance` | Color, metalness, normal, and roughness maps |
| `MaterialVariant` | Base material and texture-map overrides |
| `ContentProvider` | Asset preloading and asset-fetch status |
| `InsertService` | Permitted asset-model, package, and asset-version loading |

## 13. Animation, audio, navigation, and timing interfaces

| Namespace or type | Individual interfaces |
|---|---|
| `Animator` | Animation loading, playing-track enumeration, and animation-played signals |
| `AnimationTrack` | Play, stop, speed, weight, time position, marker signals, looping, and priority |
| `Sound` | Sound identifier, playback, time position, volume, pitch, looping, rolloff, and load/playback signals |
| `SoundGroup` | Group volume and effect routing |
| `PathfindingService` | Path creation and raw/smooth path computation |
| `Path` | Compute status, waypoints, blocked/unblocked signals, and cost configuration |
| `PathfindingLink` | Attachment endpoints, label, cost, bidirectional state, and agent-radius properties |
| `PathfindingModifier` | Label and pass-through properties |
| `task` library | `spawn`, `defer`, `delay`, `wait`, `cancel`, and supported synchronization operations |
| `DateTime` | Unix timestamp conversion, current time, ISO formatting, and universal/local components |

## 14. Luau language and source interfaces

| Interface | Individual operations | Result surface |
|---|---|---|
| Luau parser/compiler | Parse and compile `.lua` or `.luau` source | compiler output, diagnostics, and exit code |
| Type annotations | Primitive, table, function, union, intersection, optional, generic, and exported types | Script Editor diagnostics |
| Mode comments | `--!strict`, `--!nonstrict`, and `--!nocheck` | Script Editor diagnostics |
| ModuleScript | Return a value through `require` | returned module value or runtime error |
| Standard libraries | `math`, `string`, `table`, `utf8`, `bit32`, `buffer`, `coroutine`, `os`, and task-related globals | library return values or runtime errors |
| Debug information | Traceback and info surfaces exposed by Roblox Luau | strings, stack information, or errors |

General compiler form:

```text
luau-compile.exe [options] <source-file>
```

The command returns compiler output on stdout/stderr and a process exit code.

## 15. Rojo CLI interfaces

General form:

```text
rojo [global-options] <command> [command-options]
```

### `rojo build`

```text
rojo build <project-file> -o <output.rbxlx|output.rbxmx>
```

Result surfaces are stdout, stderr, process exit code, and the output file.

### `rojo serve`

```text
rojo serve <project-file> [--address <address>] [--port <port>]
```

Result surfaces are the listening address, session messages, stdout/stderr, and process exit state.

### `rojo sourcemap`

```text
rojo sourcemap <project-file> -o <sourcemap.json>
```

Result surfaces are stdout/stderr, process exit code, and the JSON output file.

### `rojo fmt-project`

```text
rojo fmt-project <project-file>
```

Result surfaces are formatted project text, diagnostics, and process exit code.

### `rojo upload`

```text
rojo upload <project-file> --asset_id <asset-id> --cookie <cookie>
```

Result surfaces are stdout/stderr, process exit code, and the remote asset update. Credentials and
network permission are required.

Rojo project files expose fields such as `$className`, `$path`, `$properties`, `$attributes`, and
nested instance names.

## 16. Studio process, log, and file interfaces

| Result type | Interface |
|---|---|
| Studio process | Windows process identifier, executable path, command line, main-window handle, and exit state |
| Studio log | Engine startup, place loading, plugin, network, script, Play, rendering, and shutdown records |
| Output window | Script messages, warnings, runtime errors, and stack traces |
| `.rbxlx` / `.rbxmx` | XML Roblox place or model serialization |
| `.rbxl` / `.rbxm` | Binary Roblox place or model serialization |
| `.project.json` | Rojo DataModel mapping |
| `.lua` / `.luau` | Luau source text |
| JSON | Project manifests, configuration, snapshots, or diagnostics |
| PNG / JPEG | Project images, textures, screenshots, or generated captures |
| Text / JSONL logs | Project records and incremental observations |
| ZIP | Project source or delivery archive |

Studio logs are stored in the Roblox log directory selected by the installed Windows client.
File durability depends on the output path and the task's writable-path contract.

## 17. Scope boundary

This catalog is game-independent. It lists individual engine and host interfaces only. It does
not contain a game implementation, gameplay-logic tutorial, tool combination, private evaluator,
score definition, hidden trace, target coordinates, Gold implementation, or required workflow.
