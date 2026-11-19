# Dockline Dispatch Public Input

This is the complete model-visible input for **Dockline Dispatch: Night Shift**. It contains the GDD, public semantic contract, blank starter, public Schema, asset facts, a game-independent Roblox tool catalog, and public scaffold checks. It contains no Gold, private evaluator, scoring weights, hidden route, historical result, or candidate solution.

## Read in this order

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `BENCHMARK_MANIFEST.json` and `ASSET_MANIFEST.json`
4. `EVALUABILITY_CONTRACT.md` and `EVALUATION_SCHEMA.json`
5. `VISUAL_DIRECTION.md`, `ASSET_CATALOG.md`, and `TaskAssets/`
6. `ROBLOX_STUDIO_TOOL_GUIDE.md`
7. `TOOLCHAIN.md` and `ScaffoldTests/README.md`
8. `project/`, the starter Place, and `legal/`

## Fixed facts

- Engine: Roblox Studio Stable, one local player, `StreamingEnabled=false`.
- Starter project: `project/default.project.json`.
- Starter Place: `DocklineDispatchStart.rbxlx`.
- Development limit: exactly 3600 seconds. At timeout, stop and return the current implementation; do not open a second development session.
- Main input: W/A/S/D, mouse, Space, E/held E, and R as defined by the GDD.
- The starter contains no target gameplay. The shared Schema is public constants only.

Run `ScaffoldTests/Test-InputScaffold.ps1` to validate the public package structure. A scaffold PASS does not prove the game builds, starts, or satisfies gameplay.
