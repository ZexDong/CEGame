# Public Read-Only Duel-State Contract

`duel-state.schema.json` is the sole authority for the task-level state snapshot shape. `GDD.md` Section 6 remains the sole gameplay acceptance authority. This contract exposes observable facts needed by later evaluation; it adds no gameplay rule and prescribes no internal class, Actor, Blueprint, component, or algorithm.

## Transport

The launcher supplies separate arguments:

```text
-EvalProcessToken=<opaque-process-token>
-EvalStatePath=<run-root>/state/engine-health.json
-EvalGameStatePath=<run-root>/state/duel-state.json
```

`EvalStatePath` is the engine-health transport used by the public Unreal executor. `EvalGameStatePath` is the task transport. They must be different files.

The starter publishes `bridge_ready=true`, `provider_ready=false`, and `game_state=null`. The final candidate must retain a read-only bridge and publish `provider_ready=true` with schema-valid state once gameplay is available. A missing provider prevents dynamic observation but does not authorize an evaluator to guess state or mutate the game.

Publish UTF-8 JSON by writing a sibling temporary file and atomically replacing the destination. Do not append. Publish after relevant state changes and at least once every 250 milliseconds. A snapshot must be at most 1 MiB.

## Identity and freshness

- `process_token` equals the opaque launch token.
- `process_id` identifies the current operating-system process.
- `snapshot_id` strictly increases in one process.
- `monotonic_ms` uses a process-local monotonic clock and strictly increases.
- `round_id` changes for every player-requested in-process restart.
- `round_index` increases whenever `round_id` changes.
- `restart_count` counts player-requested restarts.
- Reopen creates a new process token and process identifier and starts a clean round.
- Consumers reject snapshots older than 2000 milliseconds unless their operation uses a stricter documented limit.

## Semantics and units

- `normalized_position` and `normalized_bounds` use the current game client area, origin at upper left, and values in `[0,1]`.
- `player` and `rival` describe authoritative fighter truth. `input_enabled` indicates whether normal gameplay input may currently affect that fighter.
- `combat` describes current bolt/telegraph facts and the latest resolved event. It never contains a checkpoint verdict or score.
- `feedback` separately describes player-visible HUD and transient presentation so consumers can detect feedback drift.
- `visible_targets` contains current semantic metadata, not fixed private route coordinates or internal object names.

## Read-only boundary

The bridge may read candidate-owned authoritative state but must never:

- invoke movement, jump, attack, damage, block, spawn, KO, restart, or load behavior;
- accept a write request or command;
- infer missing truth from HUD text, logs, file names, or private expectations;
- expose a score, pass/fail verdict, checkpoint, expected input sequence, source class, Actor hierarchy, or reference implementation detail; or
- write anywhere except the launcher-provided state file and its sibling temporary file.

## Consumer error classifications

| Code | Meaning | Safe response |
|---|---|---|
| `duel_state_unavailable` | No readable task snapshot exists. | Keep affected observations unknown. |
| `duel_state_invalid_json` | The file is not one complete JSON object. | Retry only inside the freshness window. |
| `duel_state_schema_unsupported` | `schema_version` is unsupported. | Stop affected observation. |
| `duel_state_identity_mismatch` | Process or round identity conflicts with the requested session. | Discard and rebind. |
| `duel_state_snapshot_regressed` | Snapshot or monotonic identity moved backward. | Treat the transport as unhealthy. |
| `duel_state_stale` | The newest snapshot is too old. | Keep affected observations unknown. |
| `duel_state_provider_not_ready` | The bridge is healthy but gameplay truth is absent. | Allowed only for the unmodified starter smoke. |
| `duel_state_semantic_inconsistent` | Related truth and feedback fields contradict one another. | Preserve evidence for game-specific classification. |

No consumer error authorizes a write or direct gameplay call.
