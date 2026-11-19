# Read-Only Room State Contract

`game-state.schema.json` version 2.0.0 defines semantic observations of the concepts in `GDD.md` Section 6. It adds no gameplay rule and requires no internal actor name, class, Blueprint, hierarchy or architecture.

The executor supplies `-EvalProcessToken` and the independent engine-health path `-EvalStatePath`. Publish task state to `-EvalGameStatePath=<run-root>/state/game-state.json`; never overwrite the engine transport. Engine health retains schema version 1.0.0.

Publish UTF-8 JSON atomically, on visible state changes and at least every 250 ms while running. Each snapshot carries the actual process ID/token, increasing snapshot ID, current monotonic time and a stable attempt identity. Death respawn and R create a new attempt identity and increase `round_index`; only manual R increases `restart_count`. These fields count attempts in this one room. A true reopen uses a new process identity and initial attempt counters.

The clean starter publishes `bridge_ready=true`, `provider_ready=false`, `game_state=null`. It contains no gameplay values or provider. An implemented game publishes `provider_ready=true` and fills the complete semantic state from actual gameplay truth:

| Field | Meaning / GDD concepts |
|---|---|
| `phase` | Active, dying, respawning or completed attempt; `HAZARD-02`, `OBJECTIVE-04`, `TERMINAL-01`. |
| `player` | Position, facing, movement/attack state, health, visibility and input availability; `INPUT-01`, `INPUT-02`, `COMBAT-01`, `HAZARD-01`. |
| `objective` | Actual key count/presence and exit state; `OBJECTIVE-01` through `OBJECTIVE-04`. |
| `session` | Current session deaths; `HAZARD-02`, `LIFECYCLE-01`, `LIFECYCLE-02`. |
| `feedback` | Currently visible locked/completion/death feedback and the displayed health, key and death values; `INTERFACE-01`. Locked text is optional; report false when it is absent. |
| `world.object_counts` | Current live/present player, key, functional exit, damaging spike groups, enemy, spring and one-way platform counts; `CONTENT-02`, `ENEMY-01`. A spike group counts as one hazard, regardless of the number of teeth. Dead enemies do not count as live. |
| `world.visible_targets` | Semantic target presence, visibility, enabled state and normalized client geometry. Include all existing functional objects, even when offscreen. Decorative doors are not exit targets. |
| `world.enemies` | Actual monster health, facing and patrol/attack/hit/death state; `ENEMY-01`, `ENEMY-02`. A dying/dead entry may remain while its animation is visible; remove it when the object is gone. |
| `world.springs` | Actual spring resting/compressing/launching/recovering state; `TRAVERSAL-01`. |

Object IDs are implementation-chosen stable identifiers for the lifetime of that object. Normalized coordinates use the captured client rectangle: x rightward, y downward, values in [0,1]. Targets outside the client have `visible=false` and null position/bounds; visible targets have actual current geometry. Player/enemy position represents the projected center clamped to the client boundary when offscreen. A collected key has `present=false`, `visible=false`, `enabled=false` and null geometry until removed from the target list. Counts and values must reflect actual state, not the desired initial values or requirements.

The observer must never damage, spawn, collect, unlock, complete, restart, teleport, attack or otherwise control the game. It reports neither checkpoint results nor scores. Observation flags must not alter gameplay. Runtime files and evidence belong outside the public input copy.
