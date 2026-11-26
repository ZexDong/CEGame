# Noir Roombreak Tool Contract

## Pinned runtime

- Unity Editor: `Unity`
- Unity CLI: `1.0.0-beta.3`
- New Input System: `1.19.0`
- URP: `17.0.4` with the supplied 2D Renderer assets
- uGUI: `2.0.0`
- Cinemachine: `3.1.5`
- Starter Scene: `Assets/NoirStarter/Scenes/NoirStarter.unity`
- Required final Scene: `Assets/NoirChallenge/Scenes/NoirRoombreak.unity`
- Target resolution: `1280x720`

The project was mechanically migrated from Unity `Unity` to the pinned
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

## Public read-only Probe

The final Scene must contain at least one active `MonoBehaviour` implementing:

`GameCreate.Benchmark.NoirRoombreak.INoirRoombreakProbe`

The package is
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
