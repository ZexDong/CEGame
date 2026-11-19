# Noir Roombreak Challenge Public Project

Public Input revision: `v2.3-docv2-session-20260909`  
GDD revision: `v2.3-docv2-session-20260909`  
Public contracts: `game-state-dashboard/v2`, `game-session/v1`

Build the complete five-room game and its required session services. The
Automated acceptance section at the start of `GDD.md` explains why both are
required. The current directory is your writable project copy.

## Authoritative reading map

| Document | Purpose |
|---|---|
| `INITIAL_AGENT_PROMPT.md` | Task, budget, deliverables and workspace boundary |
| `GDD.md` Section 6.2 | All game-specific rules and public session state relationships |
| `GAME_SESSION_SPEC.md` | Required chapter, capture/restore and real-object behavior |
| `SESSION_MODEL.json` | Public content version, names, ranges and editable fields |
| `DASHBOARD_SPEC.md` and `NAMING_TABLES.json` | Required read-only state reporting |
| `COMMON_BASELINE.md` | General playable-delivery requirements |
| `TOOLCHAIN.md` and `BENCHMARK_MANIFEST.json` | Pinned tools, scene paths, protected files and test filters |
| `UNITY_BENCHMARK_TOOL_GUIDE.md` | Available Unity commands and project-local feedback |
| `ASSET_MANIFEST.json`, `ASSET_CATALOG.md`, `ASSET_CATALOG.json` | Supplied media, exact paths, dimensions and importer facts |
| `ASSET_CONTACT_SHEET.png` | Attached visual inventory |
| `Packages/com.gamecreate.benchmark.noir-roombreak.contracts/Runtime/README.md` | Public observation type definitions |
| `Packages/com.gamecreate.game-session/Runtime/` | Public session type definitions and format utilities |

Do not create a nested project. Save the final scene at
`Assets/NoirChallenge/Scenes/NoirRoombreak.unity` and enable it first in Build
Settings. Keep implementation and derived media in `Assets/NoirChallenge/**`.
Keep logs and development-check results in this project's `Logs/**`.

## Supplied media

The media root is `Assets/TaskAssets/NoirSource/`. Player, Anda and Obser
textures have substantial transparent padding. Read the published visible
bounds and importer facts when choosing their visible scale. Vulto JPG frames
are opaque character references on black, not backgrounds. Source prefabs
with omitted gameplay scripts are media references, not implemented actors.
Keep protected source files and importers unchanged.

## Development feedback

`TOOLCHAIN.md` lists the exact public filters and a project-local command
example. Starter smoke checks import/assets and a camera frame. Dashboard
checks cover reporting format. Session checks cover basic chapter entry,
detached capture, restore, invalid-request rejection and object identity.

The Dashboard and session checks require your final game scene and are
expected to fail on the unfinished starter. All checks are development aids.
Passing starter smoke alone does not establish delivery of the game or
the session services. Public session checks also do not cover every legal
state edit, transient timing boundary, game rule or presentation requirement.

No private source project or other generated submission is needed. Read and
write only inside this project, apart from invoking the pinned tool binaries.
