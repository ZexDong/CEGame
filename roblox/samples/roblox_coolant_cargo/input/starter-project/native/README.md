# Coolant Cargo Protocol — Public Input

This directory is the complete model-visible task input. Start with `INITIAL_AGENT_PROMPT.md`, then read `GDD.md`, `PUBLIC_SCHEMA.json`, `ASSET_CATALOG.md`, `TOOLCHAIN.md` and the engine tool catalog.

## Required elements

- Blank place: `Starter/CoolantCargoStart.rbxlx`
- Rojo starter: `Starter/project/default.project.json`
- Shared public Schema source: `Starter/project/src/shared/CoolantCargoSchema.luau`
- Task visual palette: `TaskAssets/VISUAL_PALETTE.json`
- Public game contract: `GDD.md` and `PUBLIC_SCHEMA.json`
- Engine-wide individual tool catalog: `ROBLOX_STUDIO_BENCHMARK_TOOL_GUIDE.md`
- Task-local tool paths: `TOOLCHAIN.md`
- Public compile/build smoke: `tools/PUBLIC_SMOKE.ps1`

The task provides no external bitmap or audio asset. The palette is a style input for procedural Roblox primitives and UI. Gold, private evaluation, score weights and evaluator trajectories are intentionally absent.
