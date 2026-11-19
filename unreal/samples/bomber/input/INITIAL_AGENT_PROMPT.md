# Initial Implementation Prompt

Implement the complete **Bomber Local Duel** inside the supplied Unreal project.

## Read First

Read, in order: `tools/INPUT_GUIDE.md`, `GDD.md`, `ARENA_LAYOUT.md`, `ASSET_MANIFEST.json`, `assets/ASSET_CATALOG.md`, `tools/TOOLCHAIN.md`, `tools/TOOL_GUIDE.md`, and `contracts/GAME_SESSION_SPEC.md`.

`GDD.md` Section 6 is the sole gameplay acceptance authority. Layout, asset, tool, and contract files provide data and interfaces; they do not add gameplay rules.

## Workspace and Environment

- The only writable root is `starter-project/`.
- Use Unreal Engine 5.7.4 on Windows x64.
- Network access and installing engines, packages, plugins, or external dependencies are prohibited.
- Keep build products, logs, captures, state, packages, and evaluation evidence outside this input copy.

## Required Boundaries

- Implement every numbered requirement in GDD Section 6.
- Use every mandatory supplied original asset in its required visible role.
- Do not copy original gameplay code, gameplay Blueprints, maps, menus, AI, data registries, StateTrees, credits, author/community UI, or promotional content.
- Use normal keyboard input for verification.
- Do not add cheats, direct win/draw calls, answer buttons, evaluation-only teleports, hidden fixtures, or a writable observer.
- Retain or equivalently replace the read-only task-state bridge so the completed game publishes schema-valid truth with `provider_ready=true`. Observation must never mutate gameplay.

## Final Handoff

Leave the completed candidate at `starter-project/BomberStarter.uproject` and report only checks actually run, their real results, incomplete/unverified requirement IDs, and known player-facing limitations.

