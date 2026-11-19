HARD WALL-CLOCK LIMIT: You have at most 3600 seconds for this implementation turn. At that limit the launcher will stop the process and retain the project exactly as it exists; there is no extension or second generation turn.

# Task

Deliver a complete playable Unity game AND the required session services in this project. Both are required parts of the submission. Read the Automated acceptance section at the start of `GDD.md`: missing or incorrect session services cause the affected requirements to lose credit, even when the game can be played manually.

The authoritative game requirements and public state relationships are together in `GDD.md` Section 6.2. Read `GAME_SESSION_SPEC.md` and `SESSION_MODEL.json` for the full session contract. Chapter entry, capture, restore and actor lookup must operate the actual game. A method signature, success flag, or partial save does not satisfy the required behavior. Your game architecture and implementation remain your choice.

Before editing, read `README.md`, `GDD.md`, `TOOLCHAIN.md`, `UNITY_BENCHMARK_TOOL_GUIDE.md`, `BENCHMARK_MANIFEST.json`, `ASSET_MANIFEST.json`, `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, `DASHBOARD_SPEC.md`, `GAME_SESSION_SPEC.md`, `SESSION_MODEL.json`, `COMMON_BASELINE.md`, `NAMING_TABLES.json`, and the supplied observation and session contracts. `ASSET_CONTACT_SHEET.png` is attached as the visual inventory. Use the catalogs for exact media paths and transparent-padding/importer facts.

Create and save `Assets/NoirChallenge/Scenes/NoirRoombreak.unity`, make it the first enabled Build Settings Scene, and complete the five-room menu-to-success journey. Use Unity `6000.0.80f1`, New Input System `1.19.0`, uGUI, and normal player-facing keyboard and pointer input. Keep all implementation and derived media under `Assets/NoirChallenge/**`; preserve protected assets and importers.

Deliver one active `GameCreate.Session.IGameSession`, the read-only `Benchmark.Dashboard.IGameStateDashboard`, and the read-only legacy Probe specified in `TOOLCHAIN.md`. All three describe the same actual game. Only the session service establishes permitted saved-state situations; the observation surfaces never drive gameplay or results.

Public development checks are available for starter smoke, the Dashboard, and session behavior. `GameCreate.Session.PublicChecks` checks chapter entry, detached capture, cross-chapter restore, invalid-request rejection and real actor mapping. The filters and scope are in `TOOLCHAIN.md`. You may use these checks within the existing budget; they contain no game implementation, and passing them does not certify the full game. Inspect actual gameplay and presentation using the available project-local tools.

Pass a new project-local `-logFile` to every Unity command. Work only in this copied project. Do not inspect sibling projects, host-global Editor logs, user-profile data, or network services. Do not install another Unity Editor or use legacy `UnityEngine.Input`.
