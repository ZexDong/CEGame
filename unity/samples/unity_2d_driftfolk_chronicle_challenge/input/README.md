# Driftfolk: Stormbound — public input

Deliver the complete game and its required public session service. Both are part of the product, not optional tooling. Automated acceptance uses the published service to open a normal game, capture or restore legal states, and identify real scene objects. An absent or incorrect service can lose the requirements that genuinely depend on it; a working service alone does not establish correct gameplay.

## Read order

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `GAME_SESSION_SPEC.md` and `SESSION_MODEL.json`
4. `BENCHMARK_MANIFEST.json`
5. `ASSET_CATALOG.md`, `ASSET_MANIFEST.json`, and `ASSET_CONTACT_SHEET.png`
6. `COMMON_BASELINE.md`, `TOOLCHAIN.md`, and `UNITY_BENCHMARK_TOOL_GUIDE.md`

## Starting project

This is an implementation-free Unity project: an empty starter scene, modular visual and audio assets, public interface types, and optional development checks. No settlement simulation, logistics, complete screen composition, or completed game is supplied.

The launcher places this project in the working directory. Work in that project rather than creating a nested project. Save the completed scene at the path declared by the manifest, with that scene enabled first in Build Settings. All task paths, protected and writable areas, tool paths, and optional test filters are defined by `BENCHMARK_MANIFEST.json`.

The artwork contact sheet is an inventory of individual components, not a target screenshot or finished map. Preserve supplied media and attribution. The source media files and `legal/` are protected; `ASSET_CATALOG.md` explains the provenance boundary.

## Authority

`GDD.md` defines the game requirements. `GAME_SESSION_SPEC.md` defines the common service. `SESSION_MODEL.json` defines this game's public save vocabulary and legal relationships; its identical runtime copy is `Assets/Resources/session-model.json`. These serve distinct purposes. There is no separate Dashboard or legacy read-only Probe.
