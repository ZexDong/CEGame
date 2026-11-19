# Game State Dashboard Contract

```text
contract_id: game-state-dashboard
contract_revision: v2-draft
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
| `targets` | Clickable on-screen elements | `kind`, screen rect `[x, y, width, height]` in the current game view, `visible`, `interactable` |

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

The snapshot format is identical for every engine; only the transport differs:

- **Unity**: the starter project contains a skeleton (`Dashboard.cs`) with the interface,
  data types, and serialization already written. Fill in the mapping from your own game state.
  Typical effort is a few dozen lines.
- **Other engines**: implement the same collection logic and append each snapshot as one JSON
  line to the file path stated in the task's toolchain notes.

World-to-screen projection for `targets` uses your engine's standard camera/UI APIs.

## 7. Self-check tool

The starter project includes a self-check tool you can run at any time. It verifies snapshot
format validity, allowed `phase` values, rects within the screen, positions within the level
bounds, and that every name required by the naming tables is reported. Passing the self-check
means the dashboard is well-formed; it does not judge gameplay.

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
