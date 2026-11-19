# Noir Roombreak Challenge

Public Input revision: `v1.11-tool-guide-v5-20260825`  
GDD revision: `v1.7-player-goals-only-20260825`  
Benchmark ID: `unity.noir_roombreak_challenge.v1`

## 1. One-sentence task

Create a complete single-player 2D noir action-platform challenge in which the player starts cleanly, crosses five connected rooms, survives movement and combat threats, and reaches a clear success presentation (`FLOW-01`, `WORLD-01`, `MOVE-01`, `COMBAT-01`, `DASH-01`, `SUCCESS-01`, `UI-01`, `AV-01`).

## 2. Scope

### 2.1 Required outcomes

| Requirement ID | Player-facing summary |
|---|---|
| FLOW-01 | Open on a clean menu and start a fresh run. |
| WORLD-01 | Traverse five consecutive, visibly distinct rooms in a fixed order. |
| MOVE-01 | Move and jump through solid platform geometry. |
| COMBAT-01 | Defeat an unaware enemy with a valid close backstab. |
| DASH-01 | Spend a limited charge for a brief fast, invulnerable dash. |
| ANDA-01 | Face an Anda that patrols, detects, chases, and can disengage. |
| OBSER-01 | Face an Obser that visibly locks on before producing a lethal laser. |
| DAMAGE-01 | Treat any valid unprotected player hit as immediate death. |
| RESPAWN-01 | Use bonds for room-local recovery and a bench for global recovery. |
| CAMERA-01 | Keep the current room readable without revealing later rooms early. |
| PAUSE-01 | Pause and resume the active run without hidden simulation. |
| SUCCESS-01 | Clear the final encounter and reach a stopped success state. |
| RESTART-01 | Restart any dirty run into one clean initial state. |
| REOPEN-01 | Begin a genuinely new process at the clean menu. |
| UI-01 | Keep menu, HUD, pause, warning, and success information usable. |
| AV-01 | Assemble the supplied media into one coherent noir presentation. |

### 2.2 Excluded scope

Accounts, online services, purchases, procedural generation, inventory systems, and multiple campaigns are outside this task. These exclusions add no game requirement beyond Section 6.2.

## 3. Starting state

| Item | Starting state | Requirement ID when acceptance is affected |
|---|---|---|
| Available entry | The supplied workspace contains a starter entry but not the requested complete challenge. | FLOW-01, WORLD-01 |
| Player and threats | Supplied player, Anda, Obser, room, effect, and audio media are available for the requested experience. | ANDA-01, OBSER-01, AV-01 |
| Initial run values | The required fresh-run values are defined only by the numbered requirements. | FLOW-01, DASH-01, RESPAWN-01 |
| Existing interface | No existing interface should be treated as proof of the requested final menu, HUD, pause, warning, or success states. | FLOW-01, PAUSE-01, SUCCESS-01, UI-01 |
| Existing functionality | The starter does not constitute the complete movement, combat, room, recovery, or lifecycle flow. | MOVE-01, COMBAT-01, DASH-01, DAMAGE-01, RESPAWN-01, RESTART-01, REOPEN-01 |
| Work still required | Deliver the complete player-facing run summarized in this document. | FLOW-01 through AV-01 |

## 4. Player goal and complete flow

### 4.1 Player goal

The player learns the movement and threat language, manages dash charges and bonds, crosses the five rooms in order, survives the final mixed encounter, and reaches success (`WORLD-01`, `MOVE-01`, `COMBAT-01`, `DASH-01`, `ANDA-01`, `OBSER-01`, `DAMAGE-01`, `RESPAWN-01`, `SUCCESS-01`).

### 4.2 Complete player flow

```text
Enter the game
-> [FLOW-01] observe the clean menu and start a fresh run
-> [WORLD-01, MOVE-01] cross Rooms 1 and 2
-> [RESPAWN-01, WORLD-01] reach and activate the Room 3 bench
-> [ANDA-01, OBSER-01, COMBAT-01, DASH-01] cross Rooms 4 and 5
-> [SUCCESS-01] defeat the required final threats and complete the final exit
-> [RESTART-01] return to a clean initial state when restarting
-> [REOPEN-01] see the clean menu first after a genuine process reopen
```

### 4.3 Core loop

```text
[MOVE-01, CAMERA-01] read and traverse the current room
-> [ANDA-01, OBSER-01] identify threat states
-> [COMBAT-01, DASH-01] choose stealth attack, dash, or avoidance
-> [DAMAGE-01, RESPAWN-01] recover through the applicable death boundary when hit
-> [WORLD-01, SUCCESS-01] advance to the next room or finish the run
```

## 5. Player actions

| Requirement ID | Player action | When it is used | Game-response summary |
|---|---|---|---|
| MOVE-01 | Hold `A` or `D`. | While alive and unpaused. | Move horizontally in the held direction. |
| MOVE-01 | Press and release `Space`. | From grounded platform contact while alive and unpaused. | Jump, then stop adding jump intent after release. |
| COMBAT-01 | Press `C`. | Near an unaware enemy. | Attempt the close backstab defined by COMBAT-01. |
| DASH-01 | Press `Z`. | While alive, unpaused, and able to spend a charge. | Attempt the directional dash defined by DASH-01. |
| PAUSE-01 | Press `Escape` or use the visible pause controls. | During an active run. | Pause or resume the same run state. |
| RESTART-01 | Press `R` or use a visible Restart control. | From gameplay, pause, death handling, or success. | Return through the clean restart flow. |
| FLOW-01, PAUSE-01, SUCCESS-01 | Use the pointer on visible controls. | On menu, pause, or success presentation. | Activate the corresponding visible action. |

Additional equivalent bindings may exist. The required behavior of the listed actions is defined only in Section 6.2.

## 6. Numbered game requirements

### 6.1 Requirement structure

Each row below represents an independently observable game requirement. Exact counts, values, ordering, text roles, timing boundaries, and prohibited outcomes are defined here rather than in later summaries.

### 6.2 Game-specific requirements

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback | Failure, repetition, restart, or other boundary |
|---|---|---|---|---|---|---|
| FLOW-01 | A fresh process has opened. | Observe the first state, then use Start. | A clean menu appears first; Start begins Room 1 with the player alive, 3 bonds, and 3 dash charges. | Gameplay must not advance behind the menu, and old run state must not appear. | Title, controls summary, and Start are readable. | Repeated menu-to-run transitions remain clean. |
| WORLD-01 | A run is active. | Reach each right-side room exit in order. | Rooms 1 through 5 are crossed consecutively; each has platforms, a clear entry, a clear exit, and at least one authored threat or traversal challenge. Room 1 introduces movement with one readable Anda encounter; Room 2 combines platform traversal with an Anda or combined detection threat; Room 3 presents the visible bench transition and introduces the Obser lock and laser; Room 4 combines Anda and Obser while rewarding charge management; Room 5 presents a final mixed encounter followed by the success exit. | Skipping directly to the final room, looping to the wrong room, or exposing an empty test room is not allowed. | The active room is visually distinct and its progress is understandable. | Returning across an open doorway may be supported, but room order does not change. |
| MOVE-01 | The player is alive and the game is not paused. | Hold `A` or `D`; press and release `Space`. | Horizontal movement follows the held direction, jumping leaves grounded platforms, and releasing controls stops adding movement intent. | Input must not move a dead player or advance gameplay while paused. | Motion, facing, grounded contact, and jump audio or animation are perceptible. | The player cannot pass through solid room floors and walls. |
| COMBAT-01 | A living enemy is nearby and has not detected the player. | Approach from behind and press `C`. | A valid close backstab defeats exactly that enemy and restores one dash charge without exceeding 3. | Attacking from the front, from too far away, through a wall, or against an already defeated enemy must not defeat it or grant a charge. | Attack and defeat feedback are visible and audible. | Pressing `C` with no valid target leaves state unchanged. |
| DASH-01 | The player is alive, unpaused, and has at least one dash charge. | Press `Z` in the current movement or facing direction. | Exactly one charge is consumed; the player makes a brief fast dash and is invulnerable only during that dash. | A dash at zero charges must not move the player, grant invulnerability, or make charges negative; invulnerability must not persist after the dash. | Charge HUD, dash trail or burst, motion, and audio update together. | A dash may defeat an enemy crossed during its active interval. |
| ANDA-01 | A living Anda exists in the current room. | Remain outside sight, then enter and leave its detection area. | Anda patrols before detection, visibly becomes alert, and chases after detecting the player; it can return to a non-chasing state after losing the player. | Anda must not remain a motionless decoration or chase through solid room geometry. | Patrol direction, alert state, and chase motion are distinguishable. | Touching an active Anda is handled by DAMAGE-01 unless the player is dashing. |
| OBSER-01 | A living Obser exists in the current room. | Enter its observed area and remain long enough to be targeted. | Obser shows a readable lock-on warning before a continuous laser becomes dangerous. | The laser must not be lethal before the visible warning, fire through unrelated rooms, or stay active after Obser is defeated. | Warning and active laser phases are visually distinct and accompanied by suitable audio. | An active dash can cross the laser without death only during dash invulnerability. |
| DAMAGE-01 | The player is alive and not dash-invulnerable. | Touch an active enemy, active laser, or lethal room hazard. | One valid hit causes immediate death and starts the applicable respawn flow. | Health bars, partial damage, delayed repeated hits, or surviving a valid hit without dash invulnerability are not allowed. | Death state and supplied death audio are clear before control returns. | Simultaneous hazards consume at most one bond for one death. |
| RESPAWN-01 | The player dies. | Allow death handling to complete. | If bonds are above zero, exactly one bond is consumed and the player reappears at the current room entrance with that room's enemies reset. If no bond is available, the player reappears at the latest activated bench with 3 bonds, all rooms' enemies restored, and run progress after that bench reset. | A soft respawn must not reset unrelated earlier rooms; a global respawn must not preserve defeated enemies or a later-room position. | Bonds, respawn type, room, enemies, and player position visibly agree. | A Room 3 bench is the guaranteed bench; before it is activated, the run-start bench is used. |
| CAMERA-01 | The player is in any room. | Move across that room and through its exit. | The camera follows within the current room boundary, does not show later rooms prematurely, and switches cleanly to the next room boundary at transition. | Camera drift outside all room bounds, persistent split views, or an unframed player is not allowed. | Player, nearby threats, platforms, and the current exit remain readable at 1280x720. | Transition timing may be immediate or briefly animated. |
| PAUSE-01 | A run is active. | Press `Escape`, observe, then press `Escape` or use Resume. | A pause overlay appears, gameplay time and player or enemy motion stop, and resume continues the same state. | Menu-only, success, or dead states must not keep simulating hidden gameplay. | Pause title, Resume, and Restart are readable. | Restart from pause follows RESTART-01. |
| SUCCESS-01 | The player reaches Room 5 and all required final threats are defeated. | Cross the final exit or complete the final encounter. | Gameplay stops and a success screen appears with a clear completion message and controls for returning to the menu and starting cleanly again. | Success must not occur in an earlier room, while a required final threat remains, or while gameplay continues behind the overlay. | Completion state and follow-up controls are readable. | Player input cannot damage or move gameplay while success is visible. |
| RESTART-01 | The run is dirty: room, bonds, charges, enemies, pause, death, or success differs from initial state. | Press `R` or use a visible Restart control. | The game returns to one clean initial menu state; the next Start opens Room 1 with 3 bonds, 3 charges, all enemies restored, no pause, and no success overlay. | Old player objects, listeners, defeated enemies, timers, lock warnings, lasers, or saved room progress must not leak. | The clean menu appears once and accepts one Start action. | Repeated dirty restarts remain stable. |
| REOPEN-01 | Any state has been reached. | Fully close the project process and open it under a different process ID. | The first player-facing state is the clean menu with no retained room progress, pause, success, bonds loss, enemy defeat, or dash use. | Merely re-entering Play Mode or reloading inside the same process is not a reopen. | The same clean menu is visible before a new run. | No persistent progression is required. |
| UI-01 | Any required state is active. | Observe and use the presentation. | Menu, current room, bonds, dash charges, pause, warning phases, and success controls are readable, unobstructed, and synchronized with player-visible state. | Broken glyphs, invisible click targets, placeholder labels, debug panels, overlapping critical UI, or stale HUD values are not allowed. | Accepted and rejected core actions provide understandable visual or audio feedback. | Equivalent readable layouts are allowed. |
| AV-01 | Supplied task assets are available. | Traverse the run and trigger movement, combat, dash, detection, laser, death, respawn, and success. | Supplied player, Anda, Obser, room, effect, and audio media appear in recognizable roles and form one coherent high-contrast noir game. | Obvious debug primitives or replacement placeholders must not stand in for the supplied major media. | Silhouettes, danger effects, animation, lighting, and audio remain coordinated. | Recoloring, scaling, slicing, and material tuning are allowed. |

## 7. Success, failure, and multi-stage flow

### 7.1 Success

| Requirement IDs | Before success | Success condition summary | Success state summary | Visible summary |
|---|---|---|---|---|
| WORLD-01, SUCCESS-01 | Cross the five rooms in order and resolve the required final threats. | Complete the final encounter or final exit only after the Room 5 condition is met. | Gameplay stops in the success presentation. | Completion information and follow-up controls are readable. |

### 7.2 Failure

| Requirement IDs | Failure condition summary | Failure state summary | Visible summary | Retry summary |
|---|---|---|---|---|
| DAMAGE-01, RESPAWN-01 | Receive one valid hit outside dash invulnerability. | Enter the applicable soft or global respawn route. | Death and the resulting bonds, room, enemy, and position state agree. | Continue from the current room entrance or latest activated bench as defined by RESPAWN-01. |

### 7.3 Multi-stage flow

| Stage | Requirement IDs | Stage summary | Requirement IDs that prevent premature completion |
|---|---|---|---|
| Opening | FLOW-01, WORLD-01, MOVE-01 | Start cleanly and establish movement and the first readable Anda encounter. | SUCCESS-01 |
| Middle | WORLD-01, RESPAWN-01, OBSER-01 | Reach the Room 3 bench and learn the Obser warning and laser sequence. | SUCCESS-01 |
| Late | WORLD-01, ANDA-01, OBSER-01, COMBAT-01, DASH-01 | Resolve combined threats while managing attack and dash opportunities. | SUCCESS-01 |
| Final | WORLD-01, SUCCESS-01 | Complete the final mixed encounter and final exit. | None |

## 8. Interface and feedback

| Requirement IDs | Information or state | Appearance and update summary | What the player distinguishes |
|---|---|---|---|
| FLOW-01, UI-01 | Menu title, controls summary, and Start | Visible before a fresh run begins. | Menu versus active gameplay. |
| UI-01, DASH-01, RESPAWN-01 | Current room, bonds, and dash charges | Visible and synchronized during the run. | Current progress and remaining recovery or dash resources. |
| ANDA-01, OBSER-01, UI-01 | Patrol, alert, lock warning, and active laser states | Update when enemy state changes. | Safe, warning, chase, and active danger phases. |
| PAUSE-01, UI-01 | Pause title, Resume, and Restart | Visible while the run is paused. | Paused versus simulating gameplay. |
| DAMAGE-01, RESPAWN-01, UI-01 | Death and respawn feedback | Appears across the applicable recovery flow. | Death, soft recovery, and global recovery. |
| SUCCESS-01, UI-01 | Completion message and follow-up controls | Visible after valid final completion. | Success versus active gameplay. |
| AV-01 | Coordinated visual and audio presentation | Responds across movement, combat, threats, death, recovery, and success. | Player, threats, effects, room structure, and action feedback. |

## 9. Restart, reopen, and persistence

| Scenario | Requirement ID | Reset summary | Retained summary | Final state summary |
|---|---|---|---|---|
| Restart the current run | RESTART-01 | Reset dirty room, resource, enemy, pause, death, success, timer, warning, laser, and object state. | Nothing from the dirty run is retained. | One clean menu; the next Start creates the defined Room 1 baseline. |
| Fully close and reopen | REOPEN-01 | Discard room progress, pause, success, bonds loss, enemy defeat, and dash use. | No persistent progression is required. | The clean menu is the first player-facing state in a different process. |

## 10. Existing functionality to preserve

This is a reconstruction task, so no separate legacy gameplay feature is required by implication. All retained player-facing outcomes are defined by `FLOW-01` through `AV-01` in Section 6.2.

## 11. Asset and content requirements

| Requirement ID | Asset or content | Hard requirement | Player-facing use | Equivalent replacement allowed |
|---|---|---|---|---|
| AV-01 | Supplied player, Anda, Obser, room, effect, animation, material, and audio media | Yes | Form the recognizable characters, rooms, danger effects, action feedback, and sound of the final noir presentation. | No replacement placeholder for supplied major media; presentation adjustments allowed only within the AV-01 boundary. |

## 12. Implementation freedom and observation boundary

- Section 6.2 contains the complete game-specific behavior requirements.
- Player-visible results and runtime state define completion, not a particular class name, object hierarchy, algorithm, data structure, or component combination.
- Read-only observation may report the game state but does not perform actions, change gameplay, or declare success.
- Supported engine operation, player-input transport, scene-entry facts, and observation compatibility are documented outside this GDD in the public tool documents.

## 13. Task coverage summary

- [x] Every required or forbidden player-facing result is defined in Section 6.2 under a requirement ID.
- [x] All other sections summarize and reference Section 6.2 rather than defining additional game requirements.
- [x] Core flow, controls, combat boundaries, success, death, recovery, restart, and genuine reopen are covered by numbered requirements.
- [x] Exact counts, order, controls, state boundaries, and presentation roles are in Section 6.2.
- [x] Asset paths, import facts, engine commands, and implementation structures are documented outside this GDD or left to the implementer.
- [x] Equivalent implementations and readable layouts remain possible where the numbered requirements permit them.
