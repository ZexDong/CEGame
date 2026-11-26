# Dungeon Four Shot — Public Starter Package

Input revision: `g07-movement-direction-click-fire-v6-20260909`.

This directory provides the complete public contract, a runnable Godot starter project, licensed resources, and self-test instructions. It contains no reference answer, private scoring implementation, internal evaluation journey, or historical score.

| Content | Purpose |
|---|---|
| `INITIAL_AGENT_PROMPT-en.md` | High-level challenge entry for the development agent: reading order, prohibitions, verification, and delivery |
| `GDD-en.md` | v0.24 gameplay specification; Section 6 is the sole atomic observable acceptance contract, including persistent shooting in the last nonzero WASD movement direction, mouse-click firing, reduced enemy projectile damage, and fixed-seed behavior |
| `TOOLCHAIN-en.md` | Required stack, player input, v2.1 read-only state protocol, prohibited capabilities, verification |
| `GODOT_BENCHMARK_TOOL_GUIDE.md` | Generic runtime, window, keyboard/mouse, screenshot, and executor guidance |
| `MaterialMapping-en.md` | Non-normative asset path, purpose, provenance, and integrity index |
| `sp/` | Minimal answer-empty Godot starter plus benchmark dashboard skeleton |
| `legal/LICENSES.md`, `legal/ASSET_AUTHORIZATION.md` | Licenses and task-granted authorization |

The development agent should begin with `INITIAL_AGENT_PROMPT-en.md`, then follow its reading order through `GDD-en.md`, `TOOLCHAIN-en.md`, and the other contracts. Evaluation drives the visible game window through normal keyboard/mouse input and cross-checks the image, read-only snapshot, and logs. It does not read candidate state outside the public contract.
