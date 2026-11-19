# Brick'n'Balls Challenge

Public Input revision: `v1.4-tool-guide-v5-20260825`  
GDD revision: `v1.1-player-goals-only-20260825`  
Benchmark ID: `unity.brick_n_balls_challenge.v1`

## 1. One-sentence task

Create a complete 2D arcade challenge in which the player launches a limited supply of balls into a colorful brick field, earns score by damaging bricks, and reaches the original game's shared end-of-run presentation.

## 2. Scope

### 2.1 Required

| Requirement | Summary |
|---|---|
| LOOP-01 | Start a run from a menu. |
| LOOP-02 | Aim and launch balls with the pointer. |
| RULE-01 | Balls move and rebound inside the playfield. |
| RULE-02 | Every brick begins with three health, loses one health per contact, and can be destroyed. |
| RULE-03 | Score and ball supply follow the run state exactly. |
| FLOW-01 | Clearing all bricks ends the run. |
| FLOW-02 | Exhausting all balls before clearing the field ends the run only after the final active ball is gone. |
| LIFE-01 | Restarting a dirty run restores a clean run. |
| LIFE-02 | Closing and reopening starts from a clean menu. |
| UI-01 | Menu, HUD, shared result screen, and controls are readable and usable. |
| ART-01 | Supplied visual and audio assets are assembled into recognizable gameplay roles. |

### 2.2 Not included

Online services, accounts, leaderboards, purchases, procedural level editors, and multiple campaigns are outside this task.

## 3. Starting state

The project contains a saved entry Scene, supplied arcade sprites and sound effects, the public read-only observation contract, and the pinned Unity tool documentation. The target gameplay is not implemented.

## 4. Player goal and flow

```text
Open the game
→ [LOOP-01] start a run
→ [LOOP-02] aim and launch a ball
→ [RULE-01, RULE-02, RULE-03] watch rebounds, brick damage, score, and remaining balls
→ [FLOW-01 or FLOW-02] reach the shared result screen
→ return to the menu and start another run
```

## 5. Player actions

| Requirements | Action | Result |
|---|---|---|
| LOOP-01 | Click the visible start control. | A fresh brick field and HUD appear. |
| LOOP-02 | Point within the playfield and complete one click. | One available ball launches from the launcher toward the chosen direction. |
| LIFE-01 | Press `R` while a run is active. | The run returns to its clean initial gameplay state. |
| FLOW-01, FLOW-02 | Click the visible result-screen control. | The shared result screen closes and the menu returns. |

## 6. Numbered requirements: sole acceptance source

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback | Boundary |
|---|---|---|---|---|---|---|
| LOOP-01 | The game has opened. | Click Start. | One fresh run begins with exactly 24 visible bricks arranged as three rows of eight, and exactly 3 available balls. | Gameplay must not consume a ball before the run starts. | The menu gives way to the playfield and HUD. | Reopening the application returns here through the menu. |
| LOOP-02 | A run is active and at least one ball remains. | Complete one click at a non-UI point inside the playfield. | Exactly one ball is consumed and launched from the visible launcher toward the chosen point. | Pressing without releasing, clicking a HUD or result control, clicking outside the playfield, or clicking after the supply reaches zero must not launch a ball. | A supplied launch sound and a visible moving ball confirm the action. | A click at the launcher position itself may be ignored. |
| RULE-01 | A ball is active. | Allow time to advance. | The ball moves continuously, rebounds from the left, right, and top boundaries, and is removed after it leaves below the launcher boundary. | A ball must not pass permanently through a boundary or remain active forever outside the playfield. | Motion, rebounds, and supplied wall-impact or ball-loss sound feedback are observable. | Multiple active balls may coexist. |
| RULE-02 | A moving ball contacts one visible brick. | Allow one contact to resolve. | That brick alone loses exactly one health. Every brick begins at exactly three health; a brick at zero health disappears and cannot be hit again. | One contact must not remove multiple health or damage unrelated bricks. | Three-, two-, and one-health states are visibly distinguishable, and supplied hit or destruction feedback is observable. | All 24 initial bricks use the same three-health rule. |
| RULE-03 | A run is active. | Launch balls, hit bricks, miss, and try invalid inputs. | The HUD always shows current score and unlaunched ball count; score increases by exactly one for each brick damage event and the count decreases by exactly one for each valid launch. | Misses, wall contacts, incomplete clicks, UI clicks, outside-playfield clicks, and attempts with zero available balls must not award score or consume another ball. | HUD values update promptly after each accepted event and remain unchanged after rejected input. | Values never become negative. |
| FLOW-01 | At least one brick remains. | Destroy the last visible brick. | Active play stops and the same shared end-of-run screen used by failure appears with the final score and a control that returns to the menu. | Clearing the field must not leave gameplay active or present a separate restart-only victory flow. | The final score and return-to-menu control are readable. | Further playfield clicks do not launch balls while the result screen is visible. |
| FLOW-02 | Bricks remain and no unlaunched balls remain. | Let the final active ball leave the playfield. | Active play stops and the shared end-of-run screen appears with final score and a control that returns to the menu. | Failure must not occur while an active ball can still hit a brick. | The final score and return-to-menu control are readable. | Further playfield clicks do not launch balls while the result screen is visible. |
| LIFE-01 | A run has a launched ball, changed score, or damaged brick. | Press `R`. | Score returns to zero, exactly 3 balls are available, no balls are active, and all 24 bricks return with exactly three health; the next complete click is accepted exactly once. | Old balls, listeners, terminal state, damage, or score may not leak into the fresh run. | The reset field and HUD are visible. | Repeated restarts remain stable. |
| LIFE-02 | Any state. | Fully close the Unity process and start a different process for the project. | The first player-facing state is a clean menu with zero score, zero active balls, and no result screen. | A previous result, score, active ball, or damaged field must be restored. | The menu is visible before a new run starts. | No save data is required. |
| UI-01 | Any state. | Observe and use the game. | Start, score, balls, final score, return-to-menu control, launcher, balls, all 24 bricks, and three brick-health states are readable and unobstructed at 1280×720. | Debug labels, placeholder blocks, broken glyphs, invisible click targets, or overlapping surfaces may not block the flow. | Accepted and rejected core actions have understandable visible feedback. | Equivalent readable layouts are allowed. |
| ART-01 | The supplied task assets are available. | Play through menu, launch, rebounds, brick hits, brick destruction, ball loss, and the shared result flow. | The supplied ball, brick, cannon base, cannon pipe, side wall, top wall, three button-state sprites, and six sound effects are used in their recognizable roles and form one coherent arcade presentation. | Supplied media must not remain unused or be replaced by obvious debug placeholders. | Visual assets appear in the player view; launch, wall, hit, destruction, loss, and button actions use the corresponding supplied audio feedback. | Reasonable recoloring, scaling, and tiling are allowed. |

## 7. End-of-run summary

| Trigger | Requirements | Visible result |
|---|---|---|
| Field cleared | FLOW-01 | The shared end-of-run screen shows final score and returns to the menu. |
| Ball supply exhausted with bricks remaining | FLOW-02 | The same shared end-of-run screen shows final score and returns to the menu after the last active ball is gone. |

## 8. Interface summary

The menu, HUD, launcher, brick-health feedback, ball motion, shared result screen, final score, and return-to-menu control correspond to UI-01. No unique layout is required.

## 9. Restart and reopen

Dirty-run restart follows LIFE-01. A genuine different-process reopen follows LIFE-02. No gameplay progress persists.

## 10. Existing behavior

This reconstruction follows the fixed upstream runtime values and shared result flow represented by the supplied reference game.

## 11. Assets

ART-01 applies to the files under `Assets/TaskAssets`. Equivalent layouts are allowed, but the supplied media must be visibly and audibly assembled.

## 12. Implementation and evaluation boundary

The numbered requirements define player-facing goals. Class names, hierarchy, algorithms, component choices, and validation procedures are not requirements. Tool and read-only observation requirements are documented in `TOOLCHAIN.md`.
