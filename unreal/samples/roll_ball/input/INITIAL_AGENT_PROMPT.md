# Initial Agent Prompt

You have a hard wall-clock limit of 3600 seconds.

The external launcher starts this generation-only timer when it provides the frozen public input, this prompt, the writable project root, Unreal Engine 5.7.4, and the public benchmark tools. If you have not handed off early, the launcher stops the entire generation process tree at exactly 3600 seconds. There is no grace period for cleanup, testing, reporting, or last-minute edits. Evaluation begins afterward from the files already on disk and uses a separate budget.

## Read first

Read the public files in the exact order listed in `tools/INPUT_GUIDE.md`. `GDD.md` Section 6 is the sole gameplay acceptance authority.

Before compiling or opening the editor, resolve and verify the engine with `pwsh -NoProfile -File tools/Resolve-Unreal57.ps1`. It accepts `-EngineRoot <path>` or the `UE_5_7_ROOT` environment variable and also checks the Epic Launcher installation record and the conventional per-machine UE 5.7 directory. Continue only when its JSON reports version `5.7.4` and changelist `51494982`; pass the returned `engine_root` to every Build, UnrealEditor, and public-runtime command. Do not double-click the `.uproject` before this check, and do not substitute another Unreal version.

Before handoff, set `GameDefaultMap` and `EditorStartupMap` in `starter-project/Config/DefaultEngine.ini` to the project-owned playable map you created. Leaving the starter value `/Engine/Maps/Entry` launches the inert preview and makes an Alt+P smoke check appear to do nothing. Verify one Alt+P (or the documented public runtime command) after a successful build, then record the observed window and map in your handoff.

## Workspace

- Start from `starter-project/RollBallStarter.uproject` and deliver through the same project entry.
- `starter-project/` is the only writable input root.
- All other public input files are protected and read-only.
- Put runtime state, captures, receipts, logs, packages, and generated evidence only in launcher-provided locations outside this input.
- Do not access another model workspace or any material outside this public input except the launcher-provided engine and public benchmark tools.

## Dependency policy

- Network access is disabled.
- Installing software, plugins, packages, services, or external dependencies is prohibited.
- Use Unreal Engine 5.7.4, built-in engine features, the supplied fixed-layout data, the cataloged board/ball mesh kit, and launcher-provided public tools.
- Marketplace plugins are not supplied and must not become candidate dependencies.
- Do not embed credentials, absolute machine paths, user or device identifiers, private data, or production data.

## Implementation and verification boundary

Implement the player results in `GDD.md` while preserving reasonable implementation freedom. Normal keyboard input must reach all required gameplay. Keep the fixed layout and trap positions supplied in `starter-project/Config/FixedRollBallLayout.json`, and use the supplied board, trap-hole, wall, and ball meshes in their required visible roles; do not replace them with primitives or hidden substitutes.

Retain and extend the read-only transport defined by `contracts/GAME_SESSION_SPEC.md`. The starter reports `provider_ready=false`; the completed candidate must publish schema-valid snapshots with `provider_ready=true` to the launcher path supplied through `-RollBallStatePath`. This transport is evaluator interoperability, not a gameplay control path, and it must never mutate the game.

Do not add an answer button, cheat command, direct completion call, automatic test fixture, evaluator-only route, hidden input shortcut, or any path that bypasses normal play. Do not read or infer a reference implementation, private test, score, checkpoint, or fixed evaluator trajectory.

An input receipt does not prove gameplay consumption. Verify behavior with fresh read-only state and contemporaneous player-visible feedback. Do not claim an unexecuted check passed.

## Final handoff

Before handing off, leave the best runnable candidate in `starter-project/`. Report the checks actually run and their outcomes, the final project entry, incomplete or unverified requirement IDs, and any build, runtime, tool, or environment fault. Do not invent scores, token counts, step counts, package validity, or evaluator results.

## Required scene setup and runtime proof

- Create and save a project-owned playable map under /Game/...; configure both GameDefaultMap and EditorStartupMap to that same /Game/... map.
- Light every required visible role (board, walls, traps, ball, and HUD context). At minimum add a DirectionalLight; add a SkyLight when needed for readable fill. A black or unlit runtime frame is not acceptable.
- Assign each supplied mesh a valid project or engine material before testing. Raw mesh material references may be absent from the input; rebind them to usable materials so no required object becomes invisible.
- Add keyboard mappings MoveX and MoveY for W/A/S/D and verify they drive the ball through normal input.
- Run in an independent window and capture a non-black frame. Confirm the board, ball, walls, traps, and HUD are visible, then verify movement, restart, exit, and a true close/reopen cycle.


Before handoff, delete generated Unreal folders and transient outputs from the delivered project, including Binaries/, Intermediate/, Saved/, DerivedDataCache/, IDE state, logs, captures, and packages. Keep runtime evidence in the launcher-owned run directory.

