# Public Read-Only Game-State Contract

`game-state.schema.json` is the sole authority for the task snapshot shape. GDD Section 6 remains the sole gameplay authority. This contract exposes observable facts and does not prescribe architecture.

## Transport

```text
-EvalProcessToken=<opaque-process-token>
-EvalStatePath=<run-root>/state/engine-health.json
-EvalGameStatePath=<run-root>/state/game-state.json
```

The starter publishes `bridge_ready=true`, `provider_ready=false`, and `game_state=null`. A completed candidate publishes `provider_ready=true` and a schema-valid `game_state` object. Publish UTF-8 JSON through a sibling temporary file followed by atomic replacement, after relevant state changes and at least every 250 ms. The snapshot must remain at most 1 MiB.

## Identity and Freshness

- `process_token` equals the launch token.
- `process_id` identifies the current process.
- `snapshot_id` and `monotonic_ms` strictly increase within one process.
- `round_id` changes on each player-requested restart; `round_index` and `restart_count` increase accordingly.
- True Reopen creates new process identity and clean round-local state.
- Consumers reject snapshots older than 2000 ms unless a stricter operation limit applies.
- Object IDs remain stable for an object's lifetime in a round and reveal no internal Actor/class/package identity.

## Grid and Units

Cells use the public top-left origin, X-right, Y-down, 11x9 coordinate space. Time and fuse values are milliseconds. Counts and HUD mirrors are integers. The two players use stable public IDs `player_1` and `player_2`. Bomb ownership is reported as one of those IDs.

Destroyed crates and collected power-ups remain as records with terminal semantic states. `explosion_cells` is the union of currently visible damaging cells. `asset_bindings` reports the public logical assets actually used for required roles; it is descriptive and read-only.

## Read-Only Boundary

The bridge may read the candidate's authoritative state but must never invoke movement, bomb placement/detonation, damage, crate destruction, pickup, result, restart, spawn, teleport, timer change, or save behavior. It must not expose a score, verdict, checkpoint, expected route, private action sequence, source class, or Actor hierarchy.

## Consumer Errors

| Code | Meaning |
|---|---|
| `game_state_unavailable` | No readable task snapshot. |
| `game_state_invalid_json` | Snapshot is not one complete JSON object. |
| `game_state_schema_unsupported` | Unsupported schema version. |
| `game_state_identity_mismatch` | Process, round, or object identity mismatch. |
| `game_state_snapshot_regressed` | Snapshot or monotonic identity moved backward. |
| `game_state_stale` | Snapshot exceeded the freshness limit. |
| `game_state_provider_not_ready` | Bridge is healthy but gameplay truth is unavailable. |
| `game_state_semantic_inconsistent` | Related truth and feedback fields contradict each other. |

No consumer error authorizes a write or direct gameplay call.
