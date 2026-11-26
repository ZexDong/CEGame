# Night Sky Duel Lab Public Input

This directory is the complete model-visible starting package for an Unreal Engine implementation task. It contains an answer-free project with a preimported Manny art set, the player-facing design requirements, public engine tooling documentation, a read-only observation contract, and repeatable package and runtime health checks.

## Required reading order

1. `INITIAL_AGENT_PROMPT.md`
2. `tools/INPUT_GUIDE.md`
3. `GDD.md`
4. `ASSET_MANIFEST.json`
5. `assets/ASSET_CATALOG.md`
6. `tools/TOOLCHAIN.md`
7. `tools/TOOL_GUIDE.md`
8. `contracts/GAME_SESSION_SPEC.md`

`BENCHMARK_MANIFEST.json` is the machine-readable authority for the same paths, policies, identities, and order. 

## Authority map

| Subject | Sole authority |
|---|---|
| Gameplay acceptance | `GDD.md` Section 6 |
| Asset delivery and replacement policy | `ASSET_MANIFEST.json` |
| Asset identity, provenance, and license facts | `assets/ASSET_CATALOG.json` |
| Engine, project, runtime, and release parameters | `BENCHMARK_MANIFEST.json` and `tools/TOOLCHAIN.md` |
| Public engine and executor interfaces | `tools/TOOL_GUIDE.md` and its compressed interface catalog |
| Task-state snapshot shape | `contracts/duel-state.schema.json` |


Tool, asset, contract, and smoke documents add no gameplay requirements. A conflict with a numbered row in `GDD.md` Section 6 is resolved in favor of that numbered row.

## Package map

| Path | Purpose | Writable during generation |
|---|---|---:|
| `starter-project/` | Answer-free Unreal project with preimported Manny art assets and final candidate root | Yes |
| `assets/files/Manny/` | Protected art-only Manny model and animation FBX reference files | No |
| `assets/legal/` | Offline source notice and per-origin asset license explanation | No |
| `contracts/` | Read-only observation schema and semantics | No |
| `self-check/PublicSmoke/` | Public project, tool, transport, Reopen, and cleanup health check | No |
| `tools/` | Package identity and interface-catalog utilities | No |
| Top-level Markdown and JSON | Requirements, facts, and release identity | No |

Build products, runtime state, captures, receipts, packages, usage, trajectories, and evaluation evidence belong in launcher-owned directories outside this input copy.

## Starting point

Open `starter-project/NightSkyDuelScaffold.uproject`. The starter draws an English health screen and contains no arena, gameplay controls, combat, health rules, rival cadence, KO flow, or gameplay restart. Its task-state bridge deliberately reports `provider_ready=false`.

The final candidate may extend or replace the bridge inside `starter-project/` so implemented gameplay publishes `provider_ready=true` with schema-valid read-only truth. This is evaluator-interoperability plumbing, does not add a gameplay rule, and must never control or mutate gameplay.

The required `SKM_Manny` model, its Skeleton, and eight animation sequences are already available under `starter-project/Content/Provided/Manny/` and `/Game/Provided/Manny/`. Use these preimported assets visibly as required by `ASSET-01` and `ASSET-02`; see `assets/ASSET_CATALOG.md` for names, meanings, object paths, and dependencies. The starter contains no preassembled fighter.

No gameplay map, Blueprint, code, save, or assembled gameplay asset is included. The built-in `Paper2D` plugin is enabled but optional for scenery or effects; it does not permit replacing the required 3D fighters with sprites.

## Public checks

Before running editor, build, or smoke commands, resolve the installed engine:

```powershell
$engineInfo = pwsh -NoProfile -File tools/Resolve-Unreal57.ps1 | ConvertFrom-Json
$engineInfo | Format-List
```

The resolver accepts `-EngineRoot` or `UE_5_7_ROOT`, checks launcher and conventional install locations, and only succeeds for Unreal Engine configured engine build. It reports validated editor, commandlet, and Build.bat paths.

Static package gate:

```powershell
pwsh -NoProfile -File tools/Test-PublicInput.ps1 -InputRoot .
```

Art-payload rejection regression tests (temporary fixtures are written outside the input):

```powershell
pwsh -NoProfile -File self-check/AssetPayload/Test-AssetPayload.ps1 -InputRoot .
```

Runtime health smoke, using launcher-provided roots:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot . `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

Public smoke checks package identity, source build, a real rendered frame, the engine-health snapshot, the answer-free task bridge, a true new-process Reopen, and final cleanup. It does not test or certify a gameplay requirement.

## Public/private boundary

This package contains no original snapshot, compatibility baseline, reference implementation, private evaluator, scoring rule, private trajectory, historical result, model run, or host-local evidence. Use normal player input for verification. Do not add an answer button, cheat entry, direct result call, hidden fixture loader, or writable observer. Final claims must identify only checks actually run and any unfinished requirement IDs.
