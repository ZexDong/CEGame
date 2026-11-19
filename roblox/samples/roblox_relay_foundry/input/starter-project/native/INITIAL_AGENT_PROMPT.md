HARD WALL-CLOCK LIMIT: You have at most 3600 seconds for this implementation turn. At that limit the launcher will stop the generation process and retain the project exactly as it exists for evaluation. There is no automatic extension or second generation turn.

You are implementing the Relay Foundry Roblox Studio task in the current input directory.

Read, in order:

1. `GDD.md` — the player-facing game specification.
2. `BENCHMARK_MANIFEST.json` and `ASSET_MANIFEST.json` — fixed revision, paths, assets, and delivery facts.
3. `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json` — supplied built-in asset inventory and intended roles.
4. `ROBLOX_STUDIO_ENGINE_TOOL_GUIDE.md` — reusable individual Roblox Studio, Luau, Rojo, and host interfaces.
5. `TOOLCHAIN.md` — Relay Foundry-specific paths, public checks, normal-input surface, and read-only observation contract.
6. `EVALUABILITY_CONTRACT.md`, `EVALUATION_SCHEMA.json`, and `CANDIDATE_SELF_CHECK.txt` — public interoperability and factual self-check requirements.

Work in `project/`. Implement every GDD requirement using normal Roblox gameplay. Preserve all public `RFP_*` protocol strings. Build `RelayFoundryCandidate.rbxlx`, test in a real Studio PlayClient, and deliver factual `RUN_REPORT.txt` and `DEVELOPMENT_TRACE.txt` files.

Use the engine tool guide as an interface catalog, not as a hidden solution. Resolve compile, Rojo mapping, API-member, first-frame, PlayClient, input, character, prompt, HUD, and Output errors before judging gameplay. State only tests you actually performed and list any remaining incomplete requirements.

