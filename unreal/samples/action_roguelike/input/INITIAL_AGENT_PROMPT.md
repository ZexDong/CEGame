# Initial Agent Prompt

You have a hard wall-clock limit of 3600 seconds.

The external launcher starts this generation-only timer when it makes the frozen public input, this prompt, the writable project root, Unreal Engine 5.6.1, and the public benchmark tools available and authorizes work. If you have not handed off early, the launcher stops the entire generation process tree at exactly 3600 seconds. There is no grace period for cleanup, testing, reporting, or last-minute edits. Evaluation begins afterward from the files already on disk and uses a separate budget.

Before compiling or opening the editor, run `pwsh -NoProfile -File tools/Resolve-Unreal56.ps1`. Continue only when its JSON reports version `5.6.1` and changelist `44394996`, and pass the returned `engine_root` to every Unreal command.

## Read first

Read the public files in the exact order listed in `tools/INPUT_GUIDE.md`. `GDD.md` Section 6 is the sole source of gameplay acceptance requirements.

## Workspace

- Start from `starter-project/ArenaSlice.uproject` and deliver through the same project entry.
- `starter-project/` is the only writable input root.
- All other input files are protected and read-only.
- Put runtime state, captures, receipts, logs, packages, and generated evidence only in launcher-provided locations outside this input.
- Do not access another model workspace or material outside this public input except the launcher-provided engine and public benchmark tools.

## Dependency policy

- Network access is disabled.
- Installing software, plugins, packages, services, or external dependencies is prohibited.
- Use Unreal Engine 5.6.1, built-in engine plugins, the supplied assets, and launcher-provided public tools.
- Marketplace plugins are not supplied and must not become candidate dependencies.
- Do not embed credentials, absolute machine paths, user or device identifiers, private data, or production data.

## Implementation and verification boundary

Implement the player results in `GDD.md` while preserving reasonable implementation freedom. Normal keyboard and mouse input must reach all required gameplay. Implement the read-only transport defined by `contracts/GAME_SESSION_SPEC.md`, publishing schema-valid snapshots and event batches to the launcher-provided paths. This is evaluator interoperability, not an additional gameplay requirement, and it must never control gameplay.

Do not add an answer button, cheat command, direct completion call, automatic test fixture, evaluator-only route, hidden input shortcut, or any path that bypasses normal play. Do not read or infer a reference implementation, private test, score, checkpoint, or fixed evaluator coordinate.

An input receipt does not prove gameplay consumption. Verify behavior with fresh read-only state and contemporaneous player-visible feedback. Do not claim an unexecuted check passed.

## Final handoff

Before handing off, leave the best runnable candidate in `starter-project/`. Report the checks actually run and their outcomes, the final project entry, incomplete or unverified requirement IDs, and any build, runtime, tool, or environment fault. Do not invent scores, token counts, step counts, package validity, or evaluator results.
