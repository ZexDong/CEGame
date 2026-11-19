HARD WALL-CLOCK LIMIT: You have at most 3600 seconds for this implementation turn. At that limit the launcher will stop the process and retain the project exactly as it exists; there is no extension or second generation turn.

You are implementing the Arrow Escape v2 Unity task in the current project.

Read, in order:

1. `GDD.md` — Section 6 is the sole player-facing acceptance specification.
2. `BENCHMARK_MANIFEST.json` and `ASSET_MANIFEST.json` — fixed versions, paths, assets, and write limits.
3. `ASSET_CONTACT_SHEET.png`, `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json` — supplied-media inventory and import facts.
4. `UNITY_BENCHMARK_TOOL_GUIDE.md` — reusable optional interfaces for the pinned Unity and CLI versions.
5. `TOOLCHAIN.md` — Arrow-specific scene, public tests, normal-input surface, and read-only Probe contract.
6. `Packages/com.omnigame.benchmark.arrow-escape.contracts/README.md` — public runtime contract details.

The contact sheet is an inventory preview attached at startup; it is not a final layout or a Reference composition. Implement every numbered GDD requirement. Save the required scene at `Assets/ArrowEscapeBenchmark/Scenes/ArrowEscape.unity`, keep it in Build Settings, and keep authored work under `Assets/ArrowEscapeBenchmark/**` plus the permitted Build Settings file and project-local logs. Preserve protected files and supplied source assets.

The declared public EditMode and PlayMode smokes, their fresh project-local logs, and their NUnit XML are available as implementation feedback through the pinned Unity CLI. They do not complete the puzzle. Player actions must remain connected to the visible Unity Input System route; direct gameplay, Restart, or result calls are not a player-control substitute.

The final saved scene must expose exactly one truthful, read-only `IArrowEscapeReadOnlyProbe` for contract `3.0`. It must report the same visible game state and targets the player receives; it must not mutate state, load fixtures, simulate input, reset the game, or force outcomes. Follow `TOOLCHAIN.md` for registry completeness, coordinates, target eligibility, and same-target press/release semantics.

Resolve compiler, import, serialized-reference, first-frame, input, camera, collider, raycast, font, and UI errors before judging gameplay. Continue until the complete GDD flow works, then state only the checks you actually performed and list any remaining incomplete numbered requirements.
