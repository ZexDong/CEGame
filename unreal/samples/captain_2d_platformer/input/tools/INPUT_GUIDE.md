# Captain's Key Run Public Input

This directory is the complete model-visible starting package for an Unreal Engine implementation task. It contains an answer-free source project, original raw sprite sheets and static room art data, player-facing design requirements, public engine and benchmark-interface documentation, a read-only observation contract, and repeatable public health checks.

## Required Reading Order

Read these files in order before changing the project:

1. `INITIAL_AGENT_PROMPT.md` — public boundaries and handoff expectations.
2. `tools/INPUT_GUIDE.md` — package map and authority boundaries.
3. `GDD.md` — the sole gameplay acceptance authority, especially Section 6.
4. `ASSET_MANIFEST.json`, then `assets/ASSET_CATALOG.md` — required art and exact asset facts.
5. `tools/TOOLCHAIN.md` — task-specific engine, entry, path, and environment parameters.
6. `tools/TOOL_GUIDE.md` — validated interfaces and navigation to the complete interface catalog.
7. `contracts/GAME_SESSION_SPEC.md` — implementation-independent read-only state transport.

`BENCHMARK_MANIFEST.json` is the machine-readable authority for the same paths, identities, policies, and order. 

## Authority Map

| Subject | Sole Authority |
|---|---|
| Player-visible gameplay acceptance | `GDD.md` Section 6 |
| Asset identity, dimensions, hashes, provenance, and license | `assets/ASSET_CATALOG.json` |
| Asset delivery and replacement policy | `ASSET_MANIFEST.json` |
| Task paths, engine parameters, and release policy | `BENCHMARK_MANIFEST.json` and `tools/TOOLCHAIN.md` |
| Validated public benchmark interfaces | `tools/TOOL_GUIDE.md` |
| Complete UE 5.7.4 and installed-plugin interface inventory | `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json` and `tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz` |
| Task-state snapshot shape | `contracts/game-state.schema.json` |


Tool, asset, contract, catalog, and smoke files do not add gameplay requirements. If any summary conflicts with a numbered row in `GDD.md` Section 6, the numbered row controls.

## Package Map

| Path | Purpose | Writable for Implementation |
|---|---|---:|
| `starter-project/` | Source-only answer-free Unreal project and final candidate root | Yes |
| `assets/files/` | Original sprite sheets and static map art data to import or process inside the project | No |
| `assets/legal/` | Offline license text and per-file license mapping | No |
| `contracts/` | Read-only observation schema and semantics | No |
| `self-check/PublicSmoke/` | Public project, tool, transport, reopen, and cleanup health check | No |
| `tools/` | Package consistency, manifest, and interface-catalog query utilities | No |
| Top-level Markdown, JSON, and catalog files | Requirements, facts, tooling, and release identity | No |

`references/room-reference.png` is a room composition design illustration showing the captain, pig and traversal objects. GDD ENEMY-01 defines the pig's patrol boundaries using room landmarks. `assets/files/map/room-layout.json` preserves the original static art placement; see `assets/files/map/README.md` for its data format. This is a single-room reconstruction. All required source art must be used; no preassembled gameplay or importer is supplied.

Only `starter-project/` is part of the candidate implementation surface. Build products, runtime state, captures, receipts, logs, packages, and evaluation evidence belong in a run directory outside this input copy.

This public package does not define a model, generation framework, time budget, or external scaffold-directory layout. Those execution choices are outside the gameplay and project contract.

## Starting Point

Open `starter-project/Captain2DScaffold.uproject`. The starter renders a stable English health screen and deliberately contains no player pawn, movement, key, exit, hazard, completion flow, or gameplay restart. Its task-state bridge reports `provider_ready=false` and `game_state=null`.

The final candidate must retain or equivalently replace the read-only bridge inside `starter-project/` so implemented gameplay publishes `provider_ready=true` and schema-valid authoritative truth. This is evaluator-interoperability plumbing, not a gameplay requirement, and it must never control or mutate gameplay.

Only the built-in `Paper2D` plugin is enabled. PaperZD, TypewriterPlugin, and Marketplace plugin payloads are absent and are not required. The supplied art remains raw PNG data outside the project so importing and assembling it are implementation work.

## Interface Catalog

The complete static Unreal Engine catalog is compressed. Query it without extracting the archive:

```powershell
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Name 'OpenLevel' -Limit 20
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Kind 'console_variable' -Name 'r.Shadow' -Limit 50
pwsh -NoProfile -File tools/Search-UnrealInterfaceCatalog.ps1 -Owner 'Paper2D' -Limit 50
```

Catalog entries document individual interfaces and their validation status. They are not an implementation pipeline or a task solution.

## Public Checks

Run the static package gate after changing any public file:

```powershell
pwsh -NoProfile -File tools/Test-PublicInput.ps1 -InputRoot .
```

Run the public runtime smoke only when a caller provides a validated Unreal Engine root, the repository public-tool root, and a fresh run directory outside this input:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot . `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

Public smoke checks an unmodified release copy: package identity, source build, a real rendered starter frame, the engine-health snapshot, the answer-free task bridge, a true new-process reopen, and final cleanup. It does not test or certify any gameplay requirement. After implementing the game, use the build/run entries in `tools/TOOLCHAIN.md` and the task-state schema to check your candidate; do not rewrite protected release manifests to make an edited project pass the starter identity gate.

## Public/Private Boundary

This package contains no original game project, private compatibility baseline, reference implementation, private evaluator, scoring rule, private trajectory, historical result, model run, or host-local evidence. Do not add any of those materials to the candidate.

Use normal player input to verify behavior. Do not add an answer button, cheat entry, direct result call, hidden fixture loader, writable observer, or route that bypasses normal play. Final claims must identify only checks actually run and any requirement IDs that remain incomplete or unverified.
