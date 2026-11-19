HARD WALL-CLOCK LIMIT: You have at most 3600 seconds for this implementation turn. At that limit the launcher will stop the process and retain the project exactly as it exists; there is no extension or second generation turn.

# Dungeon Duel 3D v2 implementation assignment

Work in the current Unity project. Read, in order:

1. `GDD.md` — Section 6 is the sole player-facing acceptance specification.
2. `BENCHMARK_MANIFEST.json` and `ASSET_MANIFEST.json` — versions, paths, supplied content, and write limits.
3. `ASSET_CONTACT_SHEET.png`, `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json` — supplied-media inventory and exact source facts.
4. `UNITY_BENCHMARK_TOOL_GUIDE.md` — reusable optional interfaces for the pinned Unity and CLI versions.
5. `TOOLCHAIN.md` — Dungeon-specific scene, public tests, normal-input surfaces, and read-only Probe contract.
6. `Packages/com.omnigame.benchmark.dungeon-duel.contracts/README.md` — public runtime contract details.

The contact sheet is an inventory preview attached at startup; it is not a final encounter layout or an evaluation Reference. The required saved scene is:

```text
Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity
```

The canonical main Scene already exists and contains the supplied art-only arena,
camera, lighting, geometry, and named markers. Extend this saved arena into the
playable encounter. Replacing it with an empty Scene or a primary primitive-only
graybox does not satisfy `VISUAL-01` or `ASSET-01`.

Build all authored gameplay under `Assets/DungeonDuelBenchmark/**` plus the permitted Build Settings file and project-local logs. Preserve supplied assets and protected files. Implement every numbered GDD requirement and exactly one truthful `IDungeonDuelBenchmarkProbe`.

Use Unity Input System mouse and keyboard routes and real visible runtime surfaces. Runtime HUD and Restart use uGUI or TMP with a compatible EventSystem route; IMGUI or UI Toolkit cannot be their only player-facing implementation. Runtime code must not reference `UnityEditor`, and the final game must already exist as saved Unity assets rather than requiring an Editor startup callback.

The declared public EditMode and PlayMode smokes, their fresh project-local logs, and their NUnit XML are available as implementation feedback through the pinned Unity CLI. They expose startup failures but do not complete the encounter. Player actions and results must remain connected to the real player-facing runtime route rather than direct gameplay, Restart, or result calls.

Resolve compile, import, serialized-reference, first-frame, input, camera, collider, navigation, material, audio, font, and UI errors before judging gameplay. State only the checks actually performed and list any incomplete numbered GDD requirement.
