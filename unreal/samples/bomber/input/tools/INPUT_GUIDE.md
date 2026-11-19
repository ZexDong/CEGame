# Bomber Local Duel Public Input

This is the complete public starting package for an Unreal Engine 5.7.4 implementation task. It contains an answer-free C++ starter, a fixed 11x9 duel layout, privacy-scanned original 3D assets, English player-facing requirements, a complete UE 5.7.4 interface catalog, a read-only observation contract, offline license text, and repeatable package checks.

The clean asset kit deliberately includes original visual content but excludes original gameplay code and assembled gameplay assets. No original game mode, pawn Blueprint, AI, input mapping, StateTree, data registry, gameplay map, menu, save, evaluator, or solution is present.

## Required Reading Order

1. `INITIAL_AGENT_PROMPT.md`
2. `tools/INPUT_GUIDE.md`
3. `GDD.md`, especially Section 6
4. `ARENA_LAYOUT.md`
5. `ASSET_MANIFEST.json`, then `assets/ASSET_CATALOG.md`
6. `tools/TOOLCHAIN.md`
7. `tools/TOOL_GUIDE.md`
8. `contracts/GAME_SESSION_SPEC.md`

`BENCHMARK_MANIFEST.json` is the machine-readable package authority. 

## Authority Map

| Subject | Sole Authority |
|---|---|
| Gameplay acceptance | `GDD.md` Section 6 |
| Fixed cell layout and crate contents | `starter-project/Config/BomberArenaLayout.json` |
| Asset paths, hashes, provenance, and dependencies | `assets/ASSET_CATALOG.json` |
| Asset delivery and replacement policy | `ASSET_MANIFEST.json` |
| Engine, entry, paths, and release policy | `BENCHMARK_MANIFEST.json` and `tools/TOOLCHAIN.md` |
| Task-state snapshot shape | `contracts/game-state.schema.json` |


Supporting documents do not add gameplay requirements. If a summary conflicts with a numbered row in GDD Section 6, the numbered row controls.

## Package Map

| Path | Purpose | Writable |
|---|---|---:|
| `starter-project/` | Answer-free Unreal project, clean asset kit, and candidate root | Yes |
| `assets/legal/` | Offline license text and per-file mapping | No |
| `contracts/` | Read-only observation schema and semantics | No |
| `self-check/PublicSmoke/` | Public build/run/reopen/cleanup health check | No |
| `tools/` | Consistency, manifest, and catalog-query tools | No |
| Top-level documentation and manifests | Requirements and release facts | No |

Generated build products, runtime state, logs, captures, packages, and evaluation evidence belong outside this input copy.

## Starting Point

Open `starter-project/BomberStarter.uproject`. The starter renders a stable English health screen and publishes `provider_ready=false` with `game_state=null`. It contains no playable player, grid arena, bomb, explosion, crate, power-up, duel HUD, countdown, timer, result, or gameplay restart.

The project does include the mandatory raw visual kit:

- the original Quinn character mesh, two material variants, skeleton, textures, and idle animation;
- the original BlockoutMap wall, crate, and Bomb/Fire/Skate meshes;
- the original Bomber bomb mesh and four material variants; and
- the original local-player arrow marker mesh/material.

These assets are inputs, not a solution. The implementation must use them exactly as required by `ASSET-01` through `ASSET-04`.

## Public Checks

Static package gate:

```powershell
pwsh -NoProfile -File tools/Test-PublicInput.ps1 -InputRoot .
```

Runtime starter smoke, with a validated engine and public executor:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot . `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

Public smoke resolves and validates UE 5.7.4 automatically when `-EngineRoot` is omitted; set `UE_5_7_ROOT` or pass `-EngineRoot` for a non-standard installation. It checks only package/build/render/transport/reopen/cleanup health. It does not test or certify gameplay requirements.

## Public/Private Boundary

Do not add the original project, private baseline, Gold implementation, evaluator, private trajectories, scoring rules, historical results, or host-local evidence. Verify gameplay through normal keys only. Do not add a cheat, answer button, direct result call, evaluation-only teleport, hidden fixture loader, or writable observer.


