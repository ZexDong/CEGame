# RollBall Fixed Maze Public Input

This directory is the complete model-visible starting package for an Unreal Engine implementation task. It contains an answer-free starter project, a cataloged raw visual mesh and lit-material kit for the board and ball, an immutable fixed 10x10 layout with sixteen fixed trap tiles, player-facing requirements, public engine-tool documentation, a read-only observation contract, notices, and repeatable package checks.

## Required reading order

Read these files in order before changing the project:

1. `INITIAL_AGENT_PROMPT.md` — time, workspace, dependency, and handoff rules.
2. `tools/INPUT_GUIDE.md` — package map and authority boundaries.
3. `GDD.md` — the sole gameplay acceptance authority, especially Section 6.
4. `FIXED_LAYOUT.md` — human-readable view of the supplied layout data.
5. `ASSET_MANIFEST.json`, then `assets/ASSET_CATALOG.md` and `assets/legal/ASSET_LICENSE_MAP.json` — exact public content facts, replacement policy, and license boundaries.
6. `tools/TOOLCHAIN.md` — task-specific engine, entry, path, and environment parameters.
7. `tools/TOOL_GUIDE.md` — one public interface at a time.
8. `contracts/GAME_SESSION_SPEC.md` — implementation-independent read-only state transport.

Before any editor or build command, run `tools/Resolve-Unreal57.ps1` and use its reported `engine_root`. This avoids relying on a launcher GUI association or an inherited environment variable and verifies the exact UE 5.7.4 patch required by this task.

The starter intentionally points at `/Engine/Maps/Entry`. A completed candidate must change both `GameDefaultMap` and `EditorStartupMap` to its project-owned playable map; otherwise Alt+P only runs the inert starter preview.

`BENCHMARK_MANIFEST.json` is the machine-readable authority for this order, paths, identities, and policies. 

## Authority map

| Subject | Sole authority |
|---|---|
| Player-visible gameplay acceptance | `GDD.md` Section 6 |
| Fixed cell, wall, start, exit, and trap data | `starter-project/Config/FixedRollBallLayout.json` as required by `GDD.md` Section 6 |
| Content identity, hashes, licenses, and replacement policy | `assets/ASSET_CATALOG.json` and `ASSET_MANIFEST.json` |
| Task paths, engine parameters, and release policy | `BENCHMARK_MANIFEST.json` and `tools/TOOLCHAIN.md` |
| Public engine interface signatures | `tools/TOOL_GUIDE.md` and the adjacent complete catalog |
| Candidate state snapshot shape | `contracts/game-state.schema.json` |


Tool, content, contract, and smoke documents do not add gameplay requirements. If a summary conflicts with a numbered row in `GDD.md` Section 6, the numbered row controls.

## Package map

| Path | Purpose | Writable during generation |
|---|---|---:|
| `starter-project/` | Answer-free Unreal project, fixed fixture, and supplied raw visual meshes; no assembled gameplay | Yes |
| `contracts/` | Read-only observation schema and semantics | No |
| `assets/legal/` | Offline third-party notice and license text | No |
| `self-check/PublicSmoke/` | Public project and starter-health check | No |
| `tools/` | Package consistency and catalog query utilities | No |
| All top-level documents and JSON files | Requirements, content facts, tooling, and release identity | No |

Build products, runtime state, captures, receipts, logs, packages, and evaluator evidence belong under a launcher-provided run root outside this input directory.

## Starting point

Open `starter-project/RollBallStarter.uproject` with Unreal Engine. The starter presents a small inert 3D mesh and material display with real lighting and a patterned rotating sphere. It deliberately contains no playable ball, movement, active traps, completion flow, gameplay restart, or game-state provider. Its read-only bridge reports `provider_ready=false` and `game_state=null`.

The fixed layout and raw meshes are supplied content, not a gameplay solution. The candidate must assemble the collidable playable maze, use the required supplied meshes, and implement every player result in `GDD.md` Section 6.

## Public checks

Run the static package gate after any public-file change:

```powershell
pwsh -NoProfile -File tools/Test-PublicInput.ps1 -InputRoot .
```

Run the public runtime smoke from a launcher that supplies a validated Unreal Engine root, the repository public-tool root, and a fresh run directory outside this input:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot . `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

The smoke script resolves Unreal Engine itself when `-EngineRoot` is omitted. Pass `-EngineRoot <engine-root>` for a non-standard installation.

Public smoke checks package identity, a source build, a stable rendered starter frame, the answer-free bridge, normal stop, a true new-process reopen, and final cleanup. It does not test or certify any gameplay requirement.

## Public/private boundary

This package contains only the public starter, task requirements, supplied assets, and public tooling. Keep generated runtime evidence outside the input package.

Use normal player input to verify behavior. Do not add an answer button, cheat entry, direct result call, hidden fixture loader, writable observer, or route that exists only for evaluation.
