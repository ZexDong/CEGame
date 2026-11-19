# RollBall Fixed Maze

## 1. One-sentence task

Build a top-down physics game in which the player rolls the supplied ball mesh across the supplied 3D chessboard-style board meshes, navigates the fixed maze, avoids the dangerous centers of the fixed trap tiles, and reaches the fixed exit with clear running, failure, completion, restart, and reopen behavior (`LAYOUT-01` through `REOPEN-01`).

## 2. Scope

### 2.1 Required work

| Requirement ID | Summary |
|---|---|
| `LAYOUT-01` | Use the supplied 3D board tile and wall meshes to present the fixed 10x10 maze and its exact wall connectivity. |
| `LAYOUT-02` | Keep the fixed start, exit, and sixteen trap tiles, including their visible center openings. |
| `CAMERA-01` | Present the entire maze through a stable top-down view. |
| `MOVEMENT-01` | Roll the ball with normal `W`, `A`, `S`, and `D` input. |
| `MOVEMENT-02` | Use the supplied ball mesh with continuous physics-like motion rather than cell teleportation. |
| `COLLISION-01` | Keep the ball inside the maze, block it with walls, and visibly bounce/rebound from walls when it has noticeable speed. |
| `HAZARD-01` | Detect contact with the central hole/opening of a fixed trap tile and enter the failure response. |
| `HAZARD-02` | Show failure feedback, increment the trap count, and reset safely. |
| `GOAL-01` | Complete only when the ball reaches the fixed exit. |
| `GOAL-02` | Lock the completed run and show the completion state. |
| `UI-01` | Show the required status and trap-hit information. |
| `RESTART-01` | Restart the same fixed run with `R`. |
| `REOPEN-01` | Start fresh after a true process reopen. |
| `EXIT-01` | Exit normally with `Esc`. |

### 2.2 Not included

The public task is one bounded fixed-board experience. It does not define or depend on any additional board, campaign, or progression context.

| Related requirement IDs | Out-of-scope content |
|---|---|
| `LAYOUT-01`, `LAYOUT-02` | Procedural generation, random seeds, rotating layouts, or changing trap positions. |
| None | Online services, Steam integration, achievements, leaderboards, multiplayer, account login, or network play. |
| None | Menus, board selection, additional boards, progression, collectibles, enemies, timers, scoring, or saved campaigns. |
| `MOVEMENT-01` | Mandatory gamepad support. Gamepad support is allowed but is not required. |

## 3. Starting state

| Item | Starting state | Acceptance requirement |
|---|---|---|
| Project entry | `starter-project/RollBallStarter.uproject` opens with Unreal Engine 5.7.4. | `QUALITY-01` |
| Fixed maze data | The 10x10 layout, wall connectivity, start cell, exit cell, and trap cells are present as public immutable data and an inert preview. | `LAYOUT-01`, `LAYOUT-02` |
| Supplied visual kit | The supplied board floor, board trap-hole, board wall, and ball static meshes are present as raw public content but are not assembled into gameplay. | `LAYOUT-01`, `MOVEMENT-02` |
| Player object | No playable ball pawn exists. | `MOVEMENT-01`, `MOVEMENT-02` |
| Hazards | Trap tiles are visible in the preview, including their center openings, but have no gameplay behavior. | `HAZARD-01`, `HAZARD-02` |
| Completion | The exit is visible in the preview but has no gameplay behavior. | `GOAL-01`, `GOAL-02` |
| Interface | The preview explicitly states that gameplay is not implemented. | `UI-01` |
| Observation bridge | The public bridge reports `provider_ready=false` and `game_state=null`. | Engineering contract in `contracts/GAME_SESSION_SPEC.md` |

## 4. Player goal and complete flow

### 4.1 Player goal

The player must guide the supplied ball from the blue start cell at `(0,0)` to the green exit cell at `(9,9)` without entering the central opening of any fixed red trap tile. The outer rim and four surrounding sides of a trap tile are safe floor (`LAYOUT-02`, `MOVEMENT-01`, `HAZARD-01`, `GOAL-01`).

### 4.2 Complete player flow

```text
Enter the game
-> [LAYOUT-01, LAYOUT-02, CAMERA-01] See the complete fixed board, the supplied ball at the start, fixed trap openings, and the exit
-> [MOVEMENT-01, MOVEMENT-02] Hold and release W/A/S/D to roll through corridors
-> [COLLISION-01] Correct direction after walls block and rebound the ball
-> [HAZARD-01, HAZARD-02] If the ball enters a trap opening, see the failure response and resume from the start
-> [GOAL-01, GOAL-02] Reach the exit and enter the locked completion state
-> [RESTART-01] Press R to begin the same fixed run again, or [EXIT-01] press Esc to quit
```

### 4.3 Core loop

```text
[MOVEMENT-01] Apply directional input
-> [MOVEMENT-02] Read the ball's continuous motion
-> [COLLISION-01] React to walls, rebounds, and corridor boundaries
-> [HAZARD-01, GOAL-01] Avoid trap openings and approach the exit
-> choose the next direction
```

## 5. Player controls

| Requirement ID | Player action | When used | Response summary |
|---|---|---|---|
| `MOVEMENT-01` | Hold or release `W`, `A`, `S`, or `D` | While status is `RUNNING` | Apply movement in the corresponding screen direction. |
| `RESTART-01` | Press `R` | During running, trap feedback, or completion | Start a clean run on the same fixed layout. |
| `EXIT-01` | Press `Esc` | At any visible game state | Close the game normally. |

## 6. Numbered requirements: sole acceptance authority

### 6.1 Requirement granularity

Each row defines one independently judgeable player result. Exact quantities, coordinates, timings, strings, ordering, and prohibitions that affect acceptance are defined here.

### 6.2 Task-specific requirements

| Requirement ID | Preconditions | Player action or trigger | Required result | Prohibited result | Player-visible feedback | Failure, repetition, restart, reopen, or other boundary |
|---|---|---|---|---|---|---|
| `LAYOUT-01` | The game enters its playable scene. | Natural scene start. | The playable arena uses the supplied board floor and wall meshes together with the complete 10x10 cell and wall arrangement identified as `rollball-fixed-maze-10x10-v2` in the supplied fixed-layout data. All perimeter and internal walls in that layout are present as gameplay collision boundaries. | The arena must not procedurally regenerate, choose another seed, omit layout walls, add route-changing walls, replace the supplied board meshes, or substitute a different maze. | The full fixed board is visible from the normal play view and the supplied board geometry is recognizable. | The same layout and supplied board meshes must remain in use after trap recovery, `R` restart, and true process reopen. |
| `LAYOUT-02` | `LAYOUT-01` is present. | Natural scene start. | The supplied trap-hole mesh is used at exactly `(4,9)`, `(6,8)`, `(0,8)`, `(8,6)`, `(0,7)`, `(3,7)`, `(6,7)`, `(1,5)`, `(4,4)`, `(7,4)`, `(6,3)`, `(1,1)`, `(8,1)`, `(9,1)`, `(6,0)`, and `(7,0)`. The ball starts at the center of cell `(0,0)`, the exit occupies cell `(9,9)`, and coordinates use the supplied bottom-left origin, with `x` increasing right and `y` increasing up. | The start, exit, or traps must not move, duplicate, disappear, change type, or lose the supplied hole geometry between runs. | Start, trap openings, and exit cells are visually distinguishable. | Trap recovery, restart, and reopen restore exactly these cells and the supplied trap-hole presentation. |
| `CAMERA-01` | The playable scene is active. | Natural scene start and normal movement. | A stable top-down camera shows the entire 10x10 maze at once. Screen up corresponds to increasing layout `y`, and screen right corresponds to increasing layout `x`. The ball, walls, traps, and exit remain readable throughout normal play. | The camera must not rotate, mirror the layout, follow so closely that required cells leave the view, or become controlled by mouse movement. | The maze orientation and all gameplay-critical objects remain clear. | Camera orientation and framing remain the same after trap recovery, restart, and reopen. |
| `MOVEMENT-01` | Status is `RUNNING` and the ball is not in trap recovery. | Hold `W`, `A`, `S`, or `D`, then release it. | `W` drives the ball toward increasing `y`, `S` toward decreasing `y`, `A` toward decreasing `x`, and `D` toward increasing `x`. Holding a key continues applying motion input; releasing it stops applying that directional input. Opposite and diagonal key combinations may be handled by any consistent physics implementation. | Input must not teleport the ball, directly set success, disable collisions, or work only through a debug or evaluator-only path. | The ball visibly accelerates in the requested direction when not blocked. The motion has a deliberately slippery feel: releasing a key removes new drive but does not instantly cancel existing travel, and a direction change needs a short counter-steering interval before the ball settles into the new direction. | Movement input is ignored while the run is completed and while trap recovery has temporarily disabled control. |
| `MOVEMENT-02` | Status is `RUNNING`. | Apply and release movement input. | The supplied 3D sphere mesh is the visible player object. It uses continuous physical motion: its world position changes across frames, the sphere visibly rotates around a horizontal axis as it travels, and it retains bounded momentum after input release before damping or collision slows it. The player can read the ball’s three-dimensional shading and rotation from the normal camera. | The ball must not be replaced by a 2D sprite, flat icon, primitive, unrelated mesh, cell-center teleport, instant route traversal, or visually unrotated sliding marker. | Translation, three-dimensional form, and rolling rotation are all visible from the top-down camera. | Repeated direction changes remain stable and controllable; restart or reset removes old linear and angular velocity. |
| `COLLISION-01` | The ball is moving during `RUNNING`. | Drive the ball with noticeable speed into a perimeter or internal wall. | The wall physically blocks the ball. On a clear non-zero-speed impact, the ball visibly bounces/rebounds away from the wall by reversing its inward motion, then remains on the playable board and can be steered normally. | The ball must not pass through, tunnel through, climb over, become stuck inside, or leave the playable maze through a wall during ordinary input; a meaningful-speed impact must not simply dead-stop without a visible bounce/rebound. | Contact produces a visible block and bounce/rebound; a near-zero-speed touch may settle or slide. | Repeated wall contacts and bounces/rebounds must not disable later movement or corrupt the fixed layout. |
| `HAZARD-01` | Status is `RUNNING`; the ball has not completed the maze. | The ball overlaps the visible central hole/opening of any trap tile listed by `LAYOUT-02`. | The run immediately leaves ordinary running play and begins one trap-recovery transaction. The same opening contact is counted once. | Trap-rim or surrounding safe-floor contact must not trigger the failure response; a trap opening must not complete the maze, move a trap, regenerate the maze, create multiple counts from one uninterrupted contact, or allow continued player control during recovery. | Status changes to the exact text `TRAP HIT`. | Contact with non-trap floor or the safe outer rim of a trap tile must not trigger this requirement. A new opening contact after recovery may trigger it again. |
| `HAZARD-02` | `HAZARD-01` has begun. | Natural recovery sequence. | `TRAP HIT` remains visible for at least 0.75 seconds and no longer than 2.0 seconds. The displayed trap-hit count increases by exactly one. By the end of the interval, the ball is restored to the center of `(0,0)` with zero linear and angular velocity, status returns to `RUNNING`, and normal input is enabled. | The ball must not respawn on a trap opening, preserve pre-hit velocity, change the fixed layout, reset the trap-hit count, or accept movement before recovery ends. | The failure text and updated count are readable, followed by the restored running view. | Repeated opening contacts repeat the same transaction. `R` during recovery performs `RESTART-01` and cancels the pending recovery without a later stale reset. |
| `GOAL-01` | Status is `RUNNING`; the ball has not entered trap recovery. | The ball touches or enters the exit cell `(9,9)`. | The run completes exactly once. | Completion must not occur from entering another cell, pressing an unrelated key, touching a trap, starting the game, or using a hidden shortcut. | Status changes to the exact text `MAZE COMPLETE`. | Further overlap with the exit during the same completed run has no additional effect. |
| `GOAL-02` | `GOAL-01` has completed the run. | Natural post-completion state and attempted movement input. | The ball is held in a stable completed state, movement input no longer changes its position, the trap-hit count remains readable, and `MAZE COMPLETE` remains visible until `R` or process exit. | Traps, old momentum, timers, or movement input must not change gameplay state after completion. A new maze must not be generated. | The fixed maze, ball, and persistent completion text remain visible. | `R` performs `RESTART-01`; `Esc` performs `EXIT-01`. |
| `UI-01` | The playable scene is visible. | Natural state changes. | A readable HUD always shows `STATUS: RUNNING`, `STATUS: TRAP HIT`, or `STATUS: MAZE COMPLETE` according to the true state, plus `TRAP HITS: <non-negative integer>` and `R - RESTART`. Updates are visible in the same frame or the next rendered frame after the authoritative state change. | HUD text must not contradict the real state, remain hidden, use placeholder text, or show completion before `GOAL-01`. | The exact labels and current values are visible without opening a menu. | Restart and reopen show `STATUS: RUNNING` and `TRAP HITS: 0`. |
| `RESTART-01` | The game is running, recovering from a trap, or completed. | Press `R` once. | A new clean run begins within 2.0 seconds on the same fixed layout. The ball is centered at `(0,0)` with zero linear and angular velocity, status is `RUNNING`, trap hits are `0`, input is enabled, and no old recovery or completion action fires later. | Restart must not generate a different layout, preserve trap hits, preserve terminal status, preserve velocity, or require process relaunch. | The restored start state and reset HUD are visible. | Repeated `R` presses leave one healthy current run and do not accumulate duplicate balls, traps, exits, cameras, HUDs, timers, or input bindings. |
| `REOPEN-01` | The process has previously been played in any state and then closed. | Start a genuinely new game process. | The new process begins a fresh run using the same fixed layout, with the ball at `(0,0)`, status `RUNNING`, trap hits `0`, and normal input enabled. | Gameplay progress, completion, trap-hit count, velocity, or pending recovery from the old process must not persist. | The standard initial running view is visible. | No gameplay save is required or allowed by this task. |
| `EXIT-01` | Any normal visible game state is active. | Press `Esc` once. | The game requests a normal quit and closes without requiring a debug console, editor stop button, or forced process kill. | `Esc` must not restart, complete, or corrupt the run before exit. | The game window closes normally. | Applies during running, trap recovery, and completion. |

### 6.3 Requirements shared by every task

| Requirement ID | Formal requirement |
|---|---|
| `QUALITY-01` | The project starts, runs, exits, and starts again according to the public instructions. |
| `QUALITY-02` | The main flow uses normal player input and does not depend on an answer button, cheat entry, or direct gameplay-result shortcut. |
| `QUALITY-03` | Critical entries, text, and controls are visible, discoverable, readable, and operable. |
| `QUALITY-04` | Player actions produce perceivable feedback, and visible feedback agrees with the real game state. |
| `QUALITY-05` | No severe error blocks the main flow. |
| `QUALITY-06` | Repeated runs from the same initial conditions are substantially stable. |

These shared requirements define objective playability only. They do not require a unique architecture, art style, or UI layout.

## 7. Success, failure, and multi-step flow

### 7.1 Success

| Requirement IDs | Steps before success | Success condition | State after success | Feedback |
|---|---|---|---|---|
| `GOAL-01`, `GOAL-02` | Navigate the fixed maze while running. | The ball reaches `(9,9)`. | Movement and later gameplay mutation are locked until restart or exit. | Persistent `STATUS: MAZE COMPLETE`. |

### 7.2 Failure

| Requirement IDs | Failure condition | State after failure | Feedback | Retry |
|---|---|---|---|---|
| `HAZARD-01`, `HAZARD-02` | The ball enters the central opening of any fixed trap tile. | Brief recovery, then a clean running state at `(0,0)` on the same layout. | `STATUS: TRAP HIT` for 0.75 to 2.0 seconds and trap count +1. | The safe rim remains traversable; continue from the restored start or press `R` for a full clean restart. |

### 7.3 Multi-step order

| Flow step | Required IDs | Summary | Must not appear early |
|---|---|---|---|
| Initial running | `LAYOUT-01`, `LAYOUT-02`, `CAMERA-01`, `UI-01` | Fixed board meshes, trap openings, start state, and running HUD are established. | `GOAL-01`, `HAZARD-01` |
| Navigation | `MOVEMENT-01`, `MOVEMENT-02`, `COLLISION-01` | Player rolls through the fixed corridors and can rebound from walls. | `GOAL-02` |
| Trap recovery | `HAZARD-01`, `HAZARD-02` | Input locks briefly, feedback appears, count increments, and the ball resets. | `GOAL-01`, ordinary movement during recovery |
| Completion | `GOAL-01`, `GOAL-02` | Exit contact commits the terminal state. | Any later gameplay mutation before restart |

## 8. Interface and feedback

| Requirement IDs | Information or state | Appearance and updates | Player distinction |
|---|---|---|---|
| `LAYOUT-02` | Start, trap openings, and exit | Visible whenever the board is visible. | Blue start, red center openings, safe trap rims, and green exit or equally clear alternatives. |
| `UI-01` | Current status | Always visible and updated with authoritative state. | Running, trap recovery, and completion. |
| `UI-01`, `HAZARD-02` | Trap-hit count | Starts at zero, increments once per completed trap transaction, resets on restart/reopen. | Current run's accumulated failures. |
| `RESTART-01` | Restart instruction | Always visible as `R - RESTART`. | How to begin a clean run without closing the process. |

## 9. Restart, reopen, and saving

| Scenario | Requirement ID | Reset summary | Preserve summary | Final state |
|---|---|---|---|---|
| Restart current game | `RESTART-01` | Ball transform and velocities, status, trap hits, pending recovery/completion work. | Exact fixed layout and trap positions. | Fresh `RUNNING` run at `(0,0)`. |
| Close and reopen | `REOPEN-01` | All gameplay state from the old process. | Exact fixed layout and trap positions. | Fresh `RUNNING` run at `(0,0)`. |

## 10. Existing functionality to preserve

| Requirement IDs | Existing public function | Player use | Required preservation |
|---|---|---|---|
| `LAYOUT-01`, `LAYOUT-02` | Fixed layout data and its visible starter preview | Inspect the supplied board before implementation. | The final playable board must continue to use the same public layout identity, coordinates, and supplied board/trap-hole meshes, although the inert preview may be replaced by the playable presentation. |
| `EXIT-01` | `Esc` quits the answer-free starter | Close the starter window. | The final candidate retains normal `Esc` quit behavior. |

## 11. Assets and content

| Requirement IDs | Asset or content | Hard requirement | Player-facing use | Equivalent replacement |
|---|---|---:|---|---|
| `LAYOUT-01`, `LAYOUT-02` | `starter-project/Config/FixedRollBallLayout.json` | Yes | Defines the fixed maze, start, exit, walls, and trap locations. | No; this exact layout data is the benchmark fixture. |
| `LAYOUT-01` | `starter-project/Content/StarterContent/Architecture/Floor_400x400.uasset` | Yes | Supplied solid 3D board tile for safe floor cells. Its three-dimensional thickness and shading must remain visible in play. | No; use the supplied mesh. |
| `LAYOUT-01`, `LAYOUT-02`, `HAZARD-01` | `starter-project/Content/StarterContent/Architecture/Floor_400x400_Hole.uasset` | Yes | Supplied 3D trap tile with a visible center opening and safe surrounding rim. The rim and opening must remain distinct in the playable view. | No; use the supplied mesh. |
| `LAYOUT-01` | `starter-project/Content/StarterContent/Architecture/Wall_400x200.uasset` | Yes | Supplied 3D board wall for the fixed maze boundaries, with visible height above the floor. | No; use the supplied mesh. |
| `MOVEMENT-02` | `starter-project/Content/StarterContent/Shapes/Shape_Sphere.uasset` | Yes | Supplied 3D sphere mesh used for the player-controlled ball, with readable volume, lighting, and rolling rotation. | No; use the supplied mesh. |
| None (informational) | Project-authored materials, lighting, HUD fonts, and ordinary decorative details | No | Present the required supplied meshes and communicate state. | Yes, provided the required mesh identities and player-visible outcomes remain unchanged. |

The four required mesh packages are clean 3D visual assets. They are supplied as raw 3D assets and must be instantiated as the visible floor, trap tile, wall, and ball. A 2D maze drawing, sprite sheet, flat icon, or primitive substitute does not satisfy the mesh requirements, even if it matches the layout.

No additional art, sound, font, or Marketplace plugin is required beyond the supplied raw mesh kit and the fixed layout fixture.

## 12. Implementation freedom

Unless Section 6 states otherwise, the implementer may freely choose:

- C++, Blueprint, or a combination;
- classes, components, nodes, data structures, and state-machine architecture;
- physical tuning values that remain controllable and satisfy the required outcomes;
- materials, lighting, ordinary decorative details, and HUD placement;
- how the fixed JSON layout is imported or converted into runtime geometry;
- whether restart resets actors in place or reloads the current scene;
- additional gamepad support or harmless accessibility options.

The supplied board and ball meshes, the trap opening versus safe-rim behavior, and the visible non-zero-speed wall rebound are not implementation choices and may not be replaced by primitives, hidden substitutes, or a different collision outcome.

## 13. Pre-handoff self-check

- [x] Section 6 is the only authority for acceptance-changing must and must-not rules.
- [x] Every scope summary points to a numbered requirement.
- [x] Fixed coordinates, exact strings, timings, and lifecycle behavior are defined in Section 6.
- [x] Success, failure, repeated trap contact, restart, and reopen are explicit.
- [x] The supplied board and ball meshes, trap center-opening hazard boundary, and non-zero-speed wall rebound are explicit without prescribing implementation details.
- [x] The task does not require private class names, Blueprint nodes, algorithms, evaluator cases, or scores.
- [x] The fixed layout supports repeatable normal-input evaluation without prescribing one implementation.
