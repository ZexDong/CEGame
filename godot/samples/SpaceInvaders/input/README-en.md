# SpaceInvaders Benchmark Input

This directory is the single canonical model-visible Input for the first-level-victory fixed-shooter task.

| Path | Purpose |
|---|---|
| `INITIAL_AGENT_PROMPT-en.md` | Required reading order, delivery constraints, and verification expectations |
| `GDD-en.md` | Complete player-facing contract; Sections 6 and 12 are authoritative |
| `TOOLCHAIN-en.md` | Engine, entry, controls, material paths, dashboard transport, and verification |
| `BENCHMARK_MANIFEST.json` | Machine-readable path and entry index |
| `sp/` | Answer-empty Godot 4.7.1 starter with a read-only dashboard skeleton |
| `Assets/` | Material catalog, coverage, manifest, and contact sheet |
| `legal/` | Preserved license and attribution records |
| `COMMON_BASELINE.md`, `DASHBOARD_SPEC.md`, `GODOT_BENCHMARK_TOOL_GUIDE.md` | Shared benchmark contracts |

The starter contains no game implementation, reference trajectory, private scoring, historical result, or answer overlay. Only the copied `sp/` project is writable.
