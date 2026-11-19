# Rift Hunting Public Input

This directory is the complete model-visible starting package for an Unreal Engine 5.6.1 implementation task. It contains an answer-free Content-only project, unassembled source assets, the player-facing design requirements, public tool documentation, a read-only observation contract, and repeatable package checks.

## Required reading order

1. `INITIAL_AGENT_PROMPT.md`
2. `tools/INPUT_GUIDE.md`
3. `GDD.md`
4. `ASSET_MANIFEST.json`
5. `assets/ASSET_CATALOG.md`
6. `assets/legal/LICENSE_SCOPE.md`
7. `tools/TOOLCHAIN.md`
8. `tools/TOOL_GUIDE.md`
9. `contracts/GAME_SESSION_SPEC.md`
10. `self-check/PublicSmoke/CONTRACT.md`

`GDD.md` Section 6 is the sole gameplay acceptance authority. Tool, asset, contract, smoke, and summary documents do not add gameplay requirements.

## Authority map

| Subject | Sole Authority |
|---|---|
| Player-visible gameplay acceptance | `GDD.md` Section 6 |
| Asset identity, hashes, provenance, license, and requirement relationship | `assets/ASSET_CATALOG.json` |
| Asset delivery and replacement policy | `ASSET_MANIFEST.json` |
| Public asset rights navigation and license-ID mapping | `assets/legal/LICENSE_SCOPE.md` and `assets/legal/ASSET_LICENSE_MAP.json` |
| Task paths, engine parameters, and generation policy | `BENCHMARK_MANIFEST.json` and `tools/TOOLCHAIN.md` |
| Public benchmark interface signatures | `tools/TOOL_GUIDE.md` |
| Read-only task-state transport | `contracts/GAME_SESSION_SPEC.md` and its JSON schemas |


## Package map

| Path | Purpose | Writable During Generation |
|---|---|---:|
| `starter-project/` | Answer-free Unreal project and final candidate root | Yes |
| `contracts/` | Implementation-independent read-only observation schemas | No |
| `assets/legal/` | Public asset-rights boundary and license-ID mapping | No |
| `self-check/PublicSmoke/` | Public project, tool, Reopen, capture, and cleanup health check | No |
| Top-level documents and JSON files | Requirements, assets, tools, policies, and release identity | No |

Build products, runtime state, captures, receipts, logs, packages, usage, and evaluator evidence belong under launcher-owned paths outside this input.

## Starting point

Open `starter-project/ArenaSlice.uproject`. The configured map is `/Game/Arena/Maps/StarterArena`. It contains a static arena and unassembled models, animations, materials, textures, and meshes. It contains no player pawn, gameplay Blueprint, Anim Blueprint, AI, UI, input assets, save system, wave logic, win flow, or loss flow.

The project has no `Source/` directory or gameplay module at release. Implementers may add source code, Blueprints, configuration, and content under `starter-project/`. Supplied binary assets are source material, not implemented gameplay.

## Public checks

Before running editor, build, or smoke commands, resolve the installed engine:

```powershell
$engineInfo = pwsh -NoProfile -File tools/Resolve-Unreal56.ps1 | ConvertFrom-Json
$engineInfo | Format-List
```

The resolver accepts `-EngineRoot` or `UE_5_6_ROOT`, checks launcher and conventional install locations, and only succeeds for UE 5.6.1 changelist 44394996. It reports validated editor, commandlet, and Build.bat paths.

Run the static package gate after any public-file change:

```powershell
pwsh -NoProfile -File tools/Test-PublicInput.ps1 -InputRoot .
```

Run the repeatable public smoke with a fresh external run root:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot . `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <new-empty-run-root>
```

The smoke validates package and public-tool identity, the public contract schemas, creates a disposable exact project copy under the external run root, runs Data Validation on that copy, performs an observer-disabled stable-window Start suitable for this Content-only common start, obtains a bounded non-black client capture, performs a true process Reopen, and verifies final cleanup. Each capture receipt records the actual host client size; this common-start smoke does not certify the separate 1280 x 720 candidate-evaluation viewport contract. It does not evaluate gameplay requirements or write generated directories into the public input. Candidate gameplay-state publication is checked only after an implementation supplies the public contract.

## Public/private boundary

This package contains no original source project, compatibility baseline, reference implementation, evaluator, scoring rule, private trajectory, historical result, scaffold run, or host-local evidence. Do not add any of those materials to the candidate.

Use normal player input to verify behavior. Do not add an answer button, cheat entry, direct result call, hidden fixture loader, or writable observer. Final claims must name only checks actually run and must list unfinished or unverified requirement IDs.
