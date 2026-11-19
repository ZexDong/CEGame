# Initial Agent Prompt

Implement the Night Sky Duel Lab task in the writable Unreal project contained in this public input.

Before compiling or opening the editor, run `pwsh -NoProfile -File tools/Resolve-Unreal57.ps1`. Continue only when its JSON reports version `5.7.4` and changelist `51494982`, and pass the returned `engine_root` to every Unreal command.

## Read before editing

Read, in order:

1. `INITIAL_AGENT_PROMPT.md`
2. `tools/INPUT_GUIDE.md`
3. `GDD.md`
4. `ASSET_MANIFEST.json`
5. `assets/ASSET_CATALOG.md`
6. `tools/TOOLCHAIN.md`
7. `tools/TOOL_GUIDE.md`
8. `contracts/GAME_SESSION_SPEC.md`

`GDD.md` Section 6 is the sole gameplay acceptance authority. Tooling, manifests, observation schemas, starter text, and public smoke do not add gameplay rules.

## Workspace

- The only writable release root is `starter-project/`.
- Preserve all other public files exactly.
- Use Unreal Engine 5.7.4 and the documented independent `editor_game` runtime.
- Do not use network access, install software, add external dependencies, or require a Marketplace plugin.
- Generated directories, logs, captures, packages, usage, trajectories, and evaluation evidence must remain outside the protected public files and must not be included in the final project snapshot.

## Implementation boundary

The starter is intentionally answer-free. Build the gameplay forward from it. Do not create an answer button, cheat command, hidden fixture, direct win/damage call, or observer write channel.

Both visible fighters must use the supplied `SKM_Manny` 3D model and the eight supplied animation clips in the roles specified by `ASSET-01` and `ASSET-02`. The preimported skeletal mesh, Skeleton, and animation sequences are available under `/Game/Provided/Manny/` and `/Game/Provided/Manny/Animations/`; exact object paths, names, meanings, and dependencies are in `assets/ASSET_CATALOG.md` and `assets/ASSET_CATALOG.json`. Merely including the files or replacing the fighters with primitives, sprites, or unrelated models is not sufficient.

You may use C++, Blueprint, implementation-created materials, or a mixture. Paper2D and engine primitives remain available for scenery and supplemental effects, not as substitutes for required fighter art. Preserve or replace the existing read-only task bridge so the final gameplay publishes `provider_ready=true` and schema-valid truth described by `contracts/duel-state.schema.json`. Observation must never change gameplay.

## Verification and handoff

Use normal player input. Run only checks you can actually execute. At handoff:

1. Leave the complete candidate under `starter-project/`.
2. Exclude `Binaries/`, `DerivedDataCache/`, `Intermediate/`, `Saved/`, IDE state, logs, captures, packages, and temporary files.
3. Report the exact build, launch, restart, and reopen checks actually run.
4. List every unfinished or unverified requirement ID. Do not claim an unrun test passed.
