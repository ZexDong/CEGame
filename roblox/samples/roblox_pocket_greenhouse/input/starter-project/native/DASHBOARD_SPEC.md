# Game State Dashboard Contract — Roblox Transport

```text
contract_id: game-state-dashboard-roblox
contract_revision: v2-roblox-1
scope: game-independent snapshot; per-task names come from naming-tables.json
```

## 1. Purpose and boundary

The delivered Roblox place must contain a small **read-only reporting component** called the dashboard. It translates the candidate's internal implementation into a fixed snapshot. The game is still played only through normal player input.

The dashboard must never expose actions, resets, cheats, score forcing, RemoteEvents that alter gameplay, or direct references intended for external mutation.

## 2. Required Roblox entry point

Create a ModuleScript at exactly:

`ReplicatedStorage/BenchmarkDashboard`

Requiring it returns a table with exactly one public function:

```lua
local Dashboard = require(game.ReplicatedStorage.BenchmarkDashboard)
local snapshot = Dashboard.GetSnapshot()
```

`GetSnapshot()` takes no arguments and returns a fresh plain Lua table serializable by `HttpService:JSONEncode`. Calling it must not change gameplay state.

## 3. Snapshot shape

```json
{
  "revision": 42,
  "phase": "playing",
  "slots": {
    "day": 2,
    "coins": 3,
    "water": 2,
    "sunberry_inventory": 0,
    "moonleaf_inventory": 1,
    "selected_plot": 2
  },
  "entities": [
    { "kind": "plot_1", "state": "sunberry_stage1_dry" },
    { "kind": "plot_2", "state": "empty" },
    { "kind": "plot_3", "state": "moonleaf_ripe" }
  ],
  "targets": [
    { "kind": "water_button", "rect": [920, 610, 140, 48], "visible": true, "interactable": true }
  ]
}
```

| Field | Rule |
|---|---|
| `revision` | Non-negative integer. Increment whenever any reported value, entity, target visibility, or target interactivity changes. |
| `phase` | Exactly one of `not_ready`, `menu`, `playing`, `paused`, `won`, `lost`. |
| `slots` | Name-to-number map using every slot in `naming-tables.json`. Use `selected_plot = 0` for no selection. |
| `entities` | Exactly one entry for each required plot kind. Each has `kind` and one allowed `state`. No world coordinate is required for this task. |
| `targets` | One entry for every required target kind, including currently hidden ones. |

## 4. Target rectangles

Each target contains:

- `kind`: exact public name;
- `rect`: `[x, y, width, height]` in current playable viewport pixels;
- `visible`: whether the player can currently see the control;
- `interactable`: whether a normal left click can currently activate it.

Use the live GUI object's `AbsolutePosition` and `AbsoluteSize` after layout has completed. A hidden target may use `[0, 0, 0, 0]`. A visible rectangle must have positive size and remain within the current viewport. Do not report design-time positions or assume a fixed resolution.

For the three plots, the target rectangle must cover the visibly clickable plot area. Decorative descendants must not steal or block the reported click point.

## 5. Required names and states

All names, allowed plot states, slot bounds and target kinds are defined in `naming-tables.json`. Internal names and architecture remain free; map them to the public vocabulary.

## 6. Lifecycle

- Before UI/state is ready, return `phase = "not_ready"` with valid top-level fields.
- Start screen uses `phase = "menu"`.
- Active round uses `phase = "playing"`.
- End screens use `won` or `lost`.
- Restart must return the snapshot to the exact initial playing state from the GDD and increase revision.
- Requiring the ModuleScript early must not permanently cache fake initial values; `GetSnapshot()` must read the live current state.

## 7. Honesty and causality

The snapshot must agree with visible UI and actual rules. Private QA may cross-check random target rectangles by real clicks and compare visible numeric text with slots. State must not advance without the player input specified by the GDD. If the dashboard contradicts the game, dependent checks cannot pass.

## 8. Self-check scope

The supplied self-check validates structure, JSON serialization, allowed phases, required names, unique plots, numeric slots and target rectangles. Passing it proves only that the report is well formed, not that the gameplay is correct.
