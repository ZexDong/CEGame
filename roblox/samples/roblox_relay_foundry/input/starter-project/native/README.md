# Relay Foundry public input

This directory is the complete model-visible Roblox Studio scaffold input. Work directly in `project/`; do not create another nested project copy.

## Read order

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `BENCHMARK_MANIFEST.json` and `ASSET_MANIFEST.json`
4. `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json`
5. `ROBLOX_STUDIO_ENGINE_TOOL_GUIDE.md`
6. `TOOLCHAIN.md`
7. `EVALUABILITY_CONTRACT.md` and `EVALUATION_SCHEMA.json`
8. `CANDIDATE_SELF_CHECK.txt`

## Fixed task facts

- Input revision: `v1.1-roblox-tool-catalog-3600s-20260826`
- Scaffold/generation hard wall-clock limit: `3600` seconds
- Rojo project: `project/default.project.json`
- Required built place: `RelayFoundryCandidate.rbxlx`
- Authored source root: `project/src/**`
- Supplied engine tools: `Tools/rojo.exe`, `Tools/luau-compile.exe`
- Public scaffold test: `ScaffoldTests/RUN_SCAFFOLD_TESTS.ps1`

The starter contains public protocol constants and an empty server/client source structure, not a gameplay solution. No external art download is required: this task intentionally uses Roblox built-in geometry, materials, lighting, UI, ProximityPrompt, and the default character as its supplied asset surface. Exact paths and roles are declared in the asset files.

Public scaffold checks expose compile/build/package mistakes and do not prove the full game. Complete gameplay claims require a real Roblox Studio Play session and normal player input.

