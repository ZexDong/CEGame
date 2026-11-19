# Gem's Bond - implementation input

Implement the complete survival tower-defense game described by GDD.md using
the supplied UE 5.7.4 empty starter and presentation assets.

Read in order:

1. INITIAL_AGENT_PROMPT.md - workspace and handoff contract.
2. GDD.md - all numbered gameplay requirements and complete balance/wave tables.
3. tools/TOOLCHAIN.md - engine resolution, build, run and allowed project edits.
4. assets/ASSET_CATALOG.md and reference/tools/INPUT_GUIDE.md - exact assets and illustrative frames.
5. contracts/GAME_SESSION_SPEC.md and naming-tables.json - read-only semantic observations.
6. tools/TOOL_GUIDE.md - individual engine/tool interfaces.

The project entry is starter-project/GemsBondStarter.uproject. Its current entry shows a diagnostic
screen. The Space probe checks input delivery only. The game map,
economy, combat, wave control, UI assembly and lifecycle remain to be implemented.
All runtime visual assets are already in starter-project/Content/. Their visible use is mandatory
for the structures, animated enemies, environment and HUD specified by GDD Section 6.

BENCHMARK_MANIFEST.json lists the required engine, project paths, contracts and file hashes.
Use tools/Test-PublicInput.ps1 for package integrity and self-check/PublicSmoke/Invoke-PublicSmoke.ps1
for a clean copied build and starter runtime health session. Their documentation describes
the scope and results; neither awards gameplay credit.
