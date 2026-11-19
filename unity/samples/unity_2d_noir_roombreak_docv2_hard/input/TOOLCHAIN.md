# Noir Roombreak Tool Contract

## Pinned runtime

- Unity Editor: `6000.0.80f1`
- Unity CLI: `1.0.0-beta.3`
- New Input System: `1.19.0`
- URP: `17.0.4` with the supplied 2D Renderer assets
- uGUI: `2.0.0`
- Cinemachine: `3.1.5`
- Starter Scene: `Assets/NoirStarter/Scenes/NoirStarter.unity`
- Required final Scene: `Assets/NoirChallenge/Scenes/NoirRoombreak.unity`
- Target resolution: `1280x720`

The project was mechanically migrated from Unity `6000.0.39f1` to the pinned
Editor. Do not add the `com.unity.feature.2d` umbrella or install, upgrade, or
downgrade packages.

## Player input

Use `UnityEngine.InputSystem`, never `UnityEngine.Input`. Required keyboard
controls are `A`, `D`, `Space`, `C`, `Z`, `Escape`, and `R`. Menu and overlay
pointer actions must also use the New Input System.

## Saved Scene and build order

Create and save `Assets/NoirChallenge/Scenes/NoirRoombreak.unity` and set it as
the first enabled Scene in `ProjectSettings/EditorBuildSettings.asset`. A
runtime-only or unsaved temporary Scene does not satisfy the required project
entry.

## Primary Game State Dashboard

The final Scene must contain at least one active `MonoBehaviour` implementing:

`Benchmark.Dashboard.IGameStateDashboard`

- Skeleton: `Assets/NoirChallenge/Runtime/NoirDashboard.cs`.
- Naming tables: `NAMING_TABLES.json`, with an identical runtime copy at
  `Assets/Resources/naming-tables.json`.
- Protected self-check: `Assets/DashboardSelfCheck/**`, using PlayMode filter:
  `GameCreate.Benchmark.NoirRoombreak.DashboardChecks`.
- Transport: in-process through `IGameStateDashboard.Capture()`; no dashboard
  file output is required.

The returned `Snapshot` uses a C# `List<SlotEntry>` for slots, while
`DashboardJson.ToJson` emits the contract's exact JSON name-to-number object.
Entities contain only `kind`, `cell`, and `state`. Targets contain only `kind`,
`rect`, `visible`, and `interactable`. Do not add action, reset, teleport,
damage, victory, or scoring methods.

## Public session service

Implement one active `GameCreate.Session.IGameSession` component using the supplied
`Packages/com.gamecreate.game-session` types. `GAME_SESSION_SPEC.md` defines
chapter entry, detached save capture, valid restore, atomic rejection and real
actor lookup. `SESSION_MODEL.json` supplies the content version and names; its
runtime copy is `Assets/Resources/session-model.json`.

The five entry IDs are `room-1` through `room-5`. A successful operation agrees
with the actual scene, Dashboard and subsequent normal Input System actions.
No additional menu is required for this service. The task's automatic acceptance
uses this mandatory service; see `GDD.md` Section 1 for the delivery consequences.
The public state relationships are together in `GDD.md` Section 6.2.

Protected session development checks are in `Assets/SessionSelfCheck/**`.
PlayMode filter: `GameCreate.Session.PublicChecks` (4 tests). They load the
required final scene from `BENCHMARK_MANIFEST.json`; missing game/session
implementation is an expected failure on the starter. They check every declared
chapter, complete public capture format, detached copies, cross-chapter restore,
loading suspension, invalid-request rejection, and reported actors' real poses.
They use only the public contracts and your own saves, and do not provide game
logic or validate every gameplay requirement. Collection order and opaque save
representation are implementation choices.

## Legacy Probe compatibility sidecar

For backward compatibility with the earlier public observation contract, the
final Scene must also contain one truthful active `MonoBehaviour` implementing:

`GameCreate.Benchmark.NoirRoombreak.INoirRoombreakProbe`

This compatibility sidecar is declared in
`Packages/com.gamecreate.benchmark.noir-roombreak.contracts`. The Probe is
observation only: it must reflect normally reached live state and must not drive
input, mutate gameplay, teleport, defeat enemies, force results, reset state, or
load Scenes.

Screen points and rectangles use bottom-left coordinates, matching
`Mouse.current.position` and `Camera.WorldToScreenPoint`. `StateSequence`
increases only when player-visible state changes. Probe collections must remain
safe while objects are absent, transitioning, defeated, or being destroyed.
`CurrentRoomIndex` is `-1` on the menu and `0` through `4` for Rooms 1 through 5.

## Supplied assets

The exact supplied root is `Assets/TaskAssets/NoirSource/`.
`ASSET_CONTACT_SHEET.png` is supplied with the initial request. Read
`ASSET_CATALOG.md` and `ASSET_CATALOG.json` before assembling Player, Anda,
Obser, room geometry, VFX/lighting, and audio. Several character textures have
extreme transparent padding, so use the published source bounds and importer
facts so the visible player-facing result remains recognizable.

Keep protected sources and importers unchanged. Put scripts, derived crops,
sprites, materials, animations, prefabs, tests, and the final Scene under
`Assets/NoirChallenge/**`. Source prefabs with omitted upstream gameplay scripts
are media and composition references, not complete gameplay objects. Audio may
use `AudioSource.clip` plus `Play()`, `PlayOneShot`, or short-lived sources; the
supplied clips must play in their intended player-facing roles.

## Unity CLI and local output

Use the argument placement and exact-project process handling documented in
`UNITY_BENCHMARK_TOOL_GUIDE.md`. Every Unity command must use a new project-local
`-logFile`. Put NUnit XML and all other tool output under this project's
`Logs/**` tree, not under `Temp/` or a user profile.

The exact public test filters are:

```text
GameCreate.Benchmark.NoirRoombreak.PublicSmoke.EditMode
GameCreate.Benchmark.NoirRoombreak.PublicSmoke.PlayMode
```

After setting the environment and timestamp paths shown in the common guide,
the game-specific test commands are:

```powershell
& $Cli --json --non-interactive --proxy-disable test $Project --mode EditMode `
  --filter 'GameCreate.Benchmark.NoirRoombreak.PublicSmoke.EditMode' `
  --output $EditXml --editor-path $Editor --timeout 600 -- -logFile $EditLog

& $Cli --json --non-interactive --proxy-disable test $Project --mode PlayMode `
  --filter 'GameCreate.Benchmark.NoirRoombreak.PublicSmoke.PlayMode' `
  --output $PlayXml --editor-path $Editor --timeout 900 -- -logFile $PlayLog
```

Each new XML must exist, be readable, discover the expected public test, and
report it passed. These public tests check the declared public workspace route;
they do not prove every player-facing behavior in the GDD.



## Running public session checks

With the final scene saved and enabled, this optional check runs inside the
current project. Use fresh log/XML paths for each invocation:

```powershell
$Project = (Get-Location).Path
$Cli = 'D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe'
$Editor = 'D:\game\engine\unity\6000.0.80f1\Editor\Unity.exe'
$Check = Join-Path $Project ('Logs\SessionChecks\' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Check -Force | Out-Null
& $Cli --json --non-interactive --proxy-disable test $Project --mode PlayMode `
  --filter 'GameCreate.Session.PublicChecks' --output "$Check\tests.xml" `
  --editor-path $Editor --timeout 600 -- -logFile "$Check\editor.log"
Get-Content -LiteralPath "$Check\editor.log" -Tail 100
```

Inspect the XML test count and each failure. A missing result or zero discovered
tests is not a passing check. Other public filters use the same command shape,
with their declared mode and unique output paths.
