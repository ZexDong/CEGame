# Game State Dashboard Contract

```text
contract_id: game-state-dashboard
contract_revision: v2-defold-20260828
scope: shared by all Defold tasks; per-task names and coordinates come from naming-tables.json
```

Every delivered game reports its real current state through the same read-only Dashboard format.
The game may use any internal names or architecture; it maps those internals to the task's public
names when producing a snapshot. The Dashboard has no input, reset, cheat, or result-forcing API.
Normal gameplay remains exclusively controlled through keyboard and mouse input.

## Snapshot

Each complete snapshot is appended as one JSON line to the path stated in `TOOLCHAIN.md`:

```json
{
  "revision": 42,
  "phase": "playing",
  "slots": { "keys": 1, "time_remaining": 37.5 },
  "entities": [
    { "id": "player", "kind": "player", "cell": [2, 3],
      "state": "normal", "visible": true },
    { "id": "crate-2", "kind": "cargo", "position": [4.5, 0.0, -2.0],
      "size": [0.8, 1.0, 0.8], "state": "world", "visible": true }
  ],
  "targets": [
    { "kind": "restart_button", "rect": [1100, 640, 120, 48],
      "visible": true, "interactable": true }
  ]
}
```

- `revision` starts at 1 and strictly increases only when the reported payload changes. Merely
  reading or querying the state must not increment it.
- `phase` is exactly one of `not_ready`, `menu`, `playing`, `paused`, `won`, or `lost`.
- `slots` contains the numeric values required by the task's naming tables. Encode boolean facts
  as `0` or `1` only when the naming tables explicitly define that slot that way.
- `entities` contains the gameplay objects required by the naming tables.
- `targets` contains the currently relevant clickable UI regions.

## Entities and coordinates

Every entity has a stable `id`, public `kind`, public `state`, and truthful `visible` flag. An ID
remains attached to the same logical object for the whole run. A task's naming tables choose one
geometry representation for each entity kind:

- `cell`: two or three integer coordinates in a discrete task grid;
- `position`: two or three continuous coordinates in the task's public world space;
- `position` plus `size`: a continuous axis-aligned body, where `size` is the full extent in the
  same dimensions and units;
- `rect`: `[x, y, width, height]` in game-view pixels;
- no geometry: only for a logical state that genuinely has no meaningful location.

An entity must not mix `cell`, `position`, and `rect`. `size` is valid only with `position` and
must have the same dimensionality. The task's `naming-tables.json` defines axes, origin, units,
bounds, and which geometry each kind uses. Off-screen but still active objects may be reported
with `visible: false`; an object claimed visible must agree with the rendered game.

All target rectangles use game-view pixels with origin at the bottom-left, independent of the
host desktop's coordinate system. Width and height are non-negative. `visible` and `interactable`
must reflect the real UI at that snapshot.

## Per-task naming tables

The task publishes a schema-version-2 `naming-tables.json` containing the only allowed slot names,
entity kinds and states, target kinds, coordinate space, game-view rectangle space, and normal
controls. It follows the supplied `naming-tables.schema.json`. Internal object names are never
inspected. Objects not listed by the task do not need to be reported. Randomized tasks also publish
a seed entry; the same seed must reproduce the same gameplay layout.

## Defold transport

The starter project includes `dashboard.lua`. Supply it with a capture function that only reads
the same authoritative variables used by gameplay and rendering. Call `dashboard.update(dt)` from
the normal update loop and `dashboard.publish_now()` after important state changes when immediate
observation is needed. Call `dashboard.final()` at shutdown. Do not add input handling to the
Dashboard module.

Run the supplied `dashboard_self_check.py` against `dashboard.jsonl` and the task's
`naming-tables.json`. The check proves contract conformance, not gameplay correctness. Evaluation
also cross-checks reported state against input causality and the actual rendered UI; fabricated or
stale state is treated as unavailable evidence.
