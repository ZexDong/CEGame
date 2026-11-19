# RollBall Read-only Game State Contract

This directory defines the public observation transport for a completed candidate. It enables later normal-input evaluation without depending on candidate class names, object names, Blueprint paths, or hierarchy. It does not add gameplay requirements; `GDD.md` Section 6 remains the sole gameplay acceptance authority.

## Launch argument

The launcher supplies one fresh path outside the public input:

```text
-RollBallStatePath=<run-root>/task-state/game-state.json
```

The candidate must publish `contracts/game-state.schema.json` snapshots to that exact path. The starter already contains an answer-free bridge that reports:

```json
{
  "bridge_ready": true,
  "provider_ready": false,
  "game_state": null
}
```

The completed candidate retains the bridge and changes to `provider_ready=true` only after it can publish truthful current gameplay state.

## Write protocol

1. Create the parent directory if necessary.
2. Serialize one complete UTF-8 JSON object without a byte-order mark.
3. Write a temporary sibling file.
4. Atomically replace the target path.
5. Increment `snapshot_id` monotonically within the process.
6. Publish immediately after relevant state changes and at least once every 250 milliseconds while the game is running.
7. Publish one final best-effort snapshot during normal shutdown.

The publisher must not accept commands, mutate gameplay, trigger results, move the ball, reset the game, load fixtures, or report evaluator verdicts.

## Semantic mapping

| Field | Meaning |
|---|---|
| `layout_id` | Must remain `rollball-fixed-maze-10x10-v2`. |
| `trap_cells` | Fixed tile locations for the supplied trap-hole meshes. A tile location is not by itself a hazard verdict: the gameplay boundary is the visible center hole and its safe surrounding rim described by `GDD.md` Section 6. |
| `round_id` | Stable identity for one current run; changes on `R` restart and new process. |
| `round_index` | Starts at 1 and increments on in-process restart. |
| `restart_count` | Number of accepted player restarts in the current process. |
| `status` | `running`, `trap_hit`, or `maze_complete`, corresponding to the required HUD states. |
| `trap_hits` | Current run's trap-hit count. |
| `input_enabled` | Whether normal movement input may currently affect the ball. |
| `ball.world_position` | Current Unreal world position in project units. |
| `ball.grid_cell` | Current bottom-left-origin cell containing the ball center, or the nearest valid cell while resetting. |
| `ball.linear_velocity` | Current world linear velocity. |
| `ball.angular_velocity` | Current world angular velocity. |
| `ball.active` | Whether the ball participates in current gameplay. |
| `hud.*` | Truthful visible HUD text and visibility facts. |

## Health and honesty boundary

- `provider_ready=true` is valid only when the snapshot is current, schema-valid, and derived from authoritative gameplay state.
- The fixed layout fields must agree with `starter-project/Config/FixedRollBallLayout.json`.
- The state file is supporting truth, not sufficient evidence by itself. Later evaluation must correlate it with input receipts and contemporaneous client captures.
- Missing, stale, malformed, or dishonest state is an observation or candidate-contract problem; it must never be repaired by writing into the game.
- Extra diagnostic fields are allowed only where the schema permits them and must not claim `pass`, `fail`, a score, a private checkpoint, or evaluator identity.
