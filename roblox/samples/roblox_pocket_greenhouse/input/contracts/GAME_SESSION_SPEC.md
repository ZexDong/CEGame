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


# Common Baseline Checklist

```text
checklist_id: common-baseline
checklist_revision: v2-draft
scope: game-independent; shared by all tasks
```

This English-only checklist is shared by all tasks and copied into each task's input.

## 1. What this is

The task's design document (GDD) defines everything **specific** to the game you are asked to
build. This checklist defines the **general expectations that apply to any playable game** —
things a design document normally does not spell out, such as "the game starts", "actions
give feedback", "losing lets you retry".

Together they are the complete set of published expectations:

```
what your delivery is judged against = the task's GDD + this checklist, nothing else
```

There are no hidden requirements outside these two documents.

## 2. How to read it

Every item is conditional: "**if** your game has X, **then** Y must hold". If the condition
does not apply to your game (for example, it has no fail state), the item is simply not
applicable. Items never add new gameplay: they only state qualities of whatever gameplay the
GDD asks for.

## 3. The checklist

### Startup and process

- **CB-01 It starts**: launched from its normal entry point, the game reaches a playable
  state (or its menu) without special steps.
- **CB-02 It does not crash or hang**: normal play does not hit errors that crash, freeze, or
  dead-end the main flow.
- **CB-03 It can be closed and reopened**: the game exits normally; after closing and
  starting it again, it returns to the initial (or saved) state the GDD describes.

### Input and feedback

- **CB-04 Controls work**: the control scheme the task declares (keys, clicks, drags)
  actually works through normal player input.
- **CB-05 Actions give feedback**: after a valid action, the player can perceive that it took
  effect (visually, numerically, or audibly).
- **CB-06 Invalid actions are rejected**: if some actions are not allowed (buying without
  money, opening a door without the key), the attempt must fail, must not corrupt state, and
  must give a noticeable cue.

### Interface

- **CB-07 Entry points are reachable**: buttons and entries needed for the main flow are
  visible and clickable (not transparent, covered, or off-screen).
- **CB-08 Text is readable**: key on-screen text and numbers are legible at the target
  resolution.
- **CB-09 Displays match reality**: displayed values (health, money, score) match the real
  game state and update when it changes.
- **CB-10 The UI does not block**: no popup or overlay permanently blocks the main flow.

### Flow and endings

- **CB-11 Winning is reachable**: if the game has a success ending, normal play as described
  by the GDD can reach it, and the success screen appears correctly.
- **CB-12 Losing allows retry**: if the game has a fail ending, failing is clearly
  communicated and a way to continue exists (retry or back to menu).
- **CB-13 Restart is clean**: if a restart exists, mutable state returns to its initial
  values with no leftovers from the previous round (objects, scores, listeners).
- **CB-14 An ending is final**: after win or lose, gameplay input stops having effect
  (retry/exit controls excepted); a finished round cannot be played on.
- **CB-15 No self-playing**: with no input given, the game must not advance to a win or loss
  by itself (unless the GDD explicitly designs a timer or similar mechanism).

### Delivery hygiene

- **CB-16 No debug leftovers**: no cheat buttons, instant-win entries, developer panels, or
  test text in the delivered game.
- **CB-17 No broken visuals**: no placeholder blocks, missing textures, or obviously
  stretched or misplaced assets (fine visual quality is judged separately; this item only
  covers "visibly broken").

### Dashboard

- **CB-18 The dashboard is conformant and honest**: implemented per the Game State Dashboard
  Contract, passes the provided self-check, and its reports agree with what is actually on
  screen.
