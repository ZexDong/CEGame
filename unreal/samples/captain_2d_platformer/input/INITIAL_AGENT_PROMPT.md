# Initial Agent Prompt

Implement the player-facing results in `GDD.md` using the answer-free Unreal project under `starter-project/`. This public input defines the task and its engineering boundaries; it does not prescribe a model, generation framework, or implementation architecture.

## Read First

Read the public files in this exact order:

1. `INITIAL_AGENT_PROMPT.md`
2. `tools/INPUT_GUIDE.md`
3. `GDD.md`
4. `ASSET_MANIFEST.json`
5. `assets/ASSET_CATALOG.md`
6. `tools/TOOLCHAIN.md`
7. `tools/TOOL_GUIDE.md`
8. `contracts/GAME_SESSION_SPEC.md`

`GDD.md` Section 6 is the sole source of gameplay acceptance requirements. Tool, asset, contract, catalog, smoke, and summary files do not add gameplay requirements.

## Workspace

- Start from `starter-project/Captain2DScaffold.uproject`.
- Deliver the final candidate through the same project entry.
- `starter-project/` is the only writable root in this public input.
- All other public files are protected. You may read them and copy required source assets into `starter-project/`, but do not modify or delete them.
- Put runtime state, captures, receipts, logs, packages, and other generated evidence outside this input copy.
- Do not access private source material, a reference implementation, a private evaluator, historical results, or another candidate workspace.

## Dependency Policy

- Network access is disabled for the task.
- Installing software, plugins, packages, services, or external dependencies is prohibited.
- Use Unreal Engine 5.7.4, the built-in `Paper2D` plugin, the supplied public files, and caller-provided public benchmark tools.
- PaperZD, TypewriterPlugin, and Marketplace plugins are not required and must not become candidate dependencies.
- Do not embed credentials, machine-specific paths, user or device identifiers, private data, or production data.

## Implementation and Verification Boundary

Implement every numbered requirement in `GDD.md` while preserving the implementation freedom stated there. Build the one supplied room using its mandatory map and art. Exactly one green pig patrols its lower-right floor corridor, between the short divider and the right wall, as specified in ENEMY-01. Do not add a scene-number UI or map transition. Process the raw sprite sheets and static tile/decoration data yourself; the starter contains no imported map or gameplay assembly. All required gameplay must be reachable through normal player keyboard input.

Retain or equivalently replace the `EvalGameStatePath` bridge inside the writable project. The final running candidate must publish `provider_ready=true` and schema-valid authoritative truth as defined in `contracts/game-state.schema.json`. This bridge is read-only evaluator-interoperability plumbing, not a gameplay requirement, and it must never control gameplay.

Do not add an answer button, cheat command, direct completion call, automatic fixture, evaluator-only route, hidden input shortcut, or any other path that bypasses normal play. Do not infer a private reference implementation, checkpoint, score, or fixed evaluator coordinate.

Use documented public interfaces only within their stated engine, platform, mode, and validation boundaries. An input receipt proves dispatch, not game consumption; verify behavior with fresh read-only state and contemporaneous player-visible feedback.

## Final Handoff

Leave the best runnable candidate in `starter-project/` and report:

- checks actually executed and their actual outcomes;
- the final project entry;
- any requirement IDs that remain incomplete or unverified; and
- any build, runtime, tool, or environment fault that prevented a check.

Do not claim an unexecuted check passed. Do not invent scores, package validity, evaluator results, or other evidence.
