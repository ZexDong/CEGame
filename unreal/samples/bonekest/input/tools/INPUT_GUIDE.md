# BoneMaze - implementation input

Build the complete 3D dungeon exploration game described in GDD.md.

Read in order:

1. INITIAL_AGENT_PROMPT.md - implementation and handoff instructions.
2. GDD.md - numbered gameplay, presentation and required-asset requirements.
3. tools/TOOLCHAIN.md - engine, project, build and run contracts.
4. assets/ASSET_CATALOG.md and reference/tools/INPUT_GUIDE.md - exact art assets and visual targets.
5. contracts/GAME_SESSION_SPEC.md and naming-tables.json - read-only semantic transport.
6. tools/TOOL_GUIDE.md - individual engine/tool interfaces.

The project entry is starter-project/BoneMaze.uproject. Presentation packages are already in
its Content directory. The empty starter's health screen is not a playable dungeon.
Implement all three maze sizes, discovery, pursuit, keys, gates, economy, presentation
and lifecycle. GDD Section 6 is the sole source of acceptance requirements, including
the boundary clauses assigned to its 66 numbered requirements in Section 6.4.

BENCHMARK_MANIFEST.json lists project paths, engine requirements and file hashes.
 The public checks verify package/runtime health only.
Asset credits and the local-use distribution boundary are in assets/legal/ASSET_NOTICES.md.
