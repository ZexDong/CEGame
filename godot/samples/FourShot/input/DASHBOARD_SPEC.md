# Game State Dashboard Contract

```text
contract_id: game-state-dashboard
contract_revision: v2-godot-draft
scope: game-independent; per-task names come from the task's naming tables
```

This English-only contract is shared by all tasks. Each task's input copies the current file
byte-for-byte. The per-task naming tables (which slot names, entity kinds, and clickable-target
kinds your game must report) are published with each task's design document.

## 1. What the dashboard is

Your delivered game must include a small **read-only reporting component**, called the
dashboard. At any moment it can produce a **snapshot** of the current game state in the fixed
format below. It is part of the delivery requirements, like compiling and running.

The dashboard is strictly read-only. It has no action, reset, cheat, or result-forcing API,
and it never substitutes for gameplay: the game is always operated through normal player
input (real keyboard and mouse). The dashboard only reports.

Why it exists: your internal names, object structure, and coordinate system are your own free
choices. The dashboard is the fixed translation layer between your implementation and the
outside world. You map your internals into the fixed format once; everything else about your
implementation stays entirely up to you.

## 2. The snapshot format

A snapshot is a JSON object:

```json
{
  "revision": 42,
  "phase": "playing",
  "slots":   { "keys": 1, "hp": 3 },
  "entities": [
    { "kind": "player", "cell": [2, 3], "state": "normal" },
    { "kind": "door",   "cell": [7, 3], "state": "closed" },
    { "kind": "key",    "cell": [5, 1], "state": "normal" }
  ],
  "targets": [
    { "kind": "restart_button", "rect": [1100, 640, 120, 48],
      "visible": true, "interactable": true }
  ]
}
```

| Field | Meaning | Rules |
|---|---|---|
| `revision` | Snapshot version counter | Increment whenever reported state changes |
| `phase` | Current top-level game phase | Only these values: `not_ready`, `menu`, `playing`, `paused`, `won`, `lost`. Do not invent new values |
| `slots` | Key numeric values | Name → number map. The required names come from the task's naming tables |
| `entities` | Gameplay objects currently present | Each entry: `kind`, position, `state`. Required kinds and their allowed `state` values come from the naming tables |
| `targets` | Clickable on-screen elements | `kind`, viewport rect `[x, y, width, height]` with a top-left origin, `visible`, `interactable` |

## 3. Names are assigned by the task, not by you

Internally you may name anything however you like. When filling the snapshot, you must map
your internals onto the exact names published in the task's naming tables. The tables only
contain concepts the design document already mentions, so they reveal nothing about how to
implement the game. Anything you add that is not in the tables (decoration, extra effects)
does not need to be reported.

## 4. Coordinates belong to the task's level data

Positions in `cell` always use the coordinate space of the level data shipped with the task
(for example, grid cell indices of the provided level file). Your internal world scale,
origin, and axes are your own; convert back to the task's coordinates when reporting. If a
task has no grid, its naming tables state what to report instead (typically a screen rect,
like `targets`, or no position at all).

## 5. Random seed

If your game has randomized content, it must accept an externally supplied seed (the exact
entry point — command-line argument or config file — is stated in the task's toolchain
notes). The same seed must reproduce the same layout. Games without randomness skip this.

## 6. How to implement it

The starter project contains `dashboard.gd`, which defines the snapshot shape, revision
handling, JSON serialization, and file transport. Wire the dashboard into the actual game
systems and runtime scene, then implement the four state-mapping categories in `capture()`:
phase, slots, entities, and targets. Publish the latest complete JSON object to the `user://`
path declared by the task's `TOOLCHAIN.md`; do not expose any write or action endpoint. The
external evaluator polls that file and retries short reads while Godot is replacing its
contents. The four categories describe the snapshot mapping; they are not the complete
integration workload.

For a `Control`, use its global viewport rectangle. World objects must be projected through
the active `Camera2D` or `Camera3D` before reporting a screen rectangle.

## 7. Self-check tool

The starter project includes a self-check tool you can run after the scene has settled for one
frame. It verifies snapshot format validity, allowed `phase` values, required numeric slots,
allowed entity kinds/states, two-coordinate reported positions within level bounds, and reported target
rects within the screen. It does not require every target kind to be present in every phase.
Passing the self-check means the dashboard is well-formed; it does not judge gameplay.

Run it directly with `<Godot console> --headless --path <project> --script
res://benchmark/dashboard_self_check.gd`. Like the Unity PlayMode self-check, it loads the
configured main scene, waits one frame, finds the dashboard by type rather than node name, and
returns process exit code `0` on success or `1` on failure.

## 8. Honesty is verified

Reported snapshots are cross-checked against what is actually on screen and against input
causality (for example: state must not advance to `won` while no input is being given, unless
the design document says so; a reported entity must actually be visible at the reported
place). If the dashboard's reports contradict the real game, the dashboard is treated as
unreliable, and everything that depended on it is treated as not delivered. Reporting your
real state faithfully is always the cheapest way to pass.

## 9. If the dashboard is missing or wrong

The dashboard is a published delivery requirement. If it is missing, malformed, or
inconsistent with the real game, the parts of acceptance that depend on it cannot pass;
partially implemented dashboards are judged per reported item. The dashboard itself is a
small fixed cost, not the main goal of the task — build the game first, then wire the
dashboard to it truthfully.
