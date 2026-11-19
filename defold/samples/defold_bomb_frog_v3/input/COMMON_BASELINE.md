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
