# Implement Chomp

Read `tools/INPUT_GUIDE.md`, `GDD.md`, `assets/ASSET_CATALOG.md`, `contracts/GAME_SESSION_SPEC.md`, `tools/TOOLCHAIN.md`, and the engine tool guide in that order. Implement every numbered requirement in GDD Section 6, including its QUALITY requirements, in the supplied Unreal Engine 5.7.4 project. Other documents provide resources, tooling and observation semantics, not additional gameplay scoring rules.

Your implementation root is `starter-project/`; the final entry remains `starter-project/ChompStarter.uproject`. You may replace the welcome view, create levels and actors, change project source/configuration and add your own resources inside that root. Preserve the public files outside `starter-project/`. Mandatory art is ready to use in `starter-project/Content/Art/`; writable source copies are already in `starter-project/SourceArt/`. Apply ASSET-01..05, including visible use and permitted transformations. Generated project caches belong under the project only; place evidence and your final report in an externally supplied output directory.

Use only this input, the installed engine/SDK and the supplied public engine tools. Do not inspect other task directories or use private reference/evaluation materials. The task is offline: do not download code/assets, install software, use external services or require accounts. You may read the installed engine's source/API documentation. Internal architecture is free. Use the supplied art for the roles bound by ASSET-01..05; additional art may fill other roles.

Keep normal player controls and truthful read-only observation. Do not add answer buttons, fixture commands, hidden state setters, automatic victory actions or test-specific gameplay. The starter's observation publisher only serializes supplied real state; connect or replace it without making it a gameplay control channel. `-ChompSeed` is only an initial randomness seed, not an easier game mode.

Deliver the complete buildable project and report the actual build/run checks performed, their results, and any unfinished requirement IDs. Do not claim a smoke check proves full gameplay or claim checks that were not run.

Section 6.4 defines timing/contact boundaries, permitted route choices, death-overlay Restart and presentation variation; read it together with the numbered rows.
