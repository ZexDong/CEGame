# Bomber Local Duel

## 1. One-Sentence Task

Build a complete two-player local Bomber duel in the supplied fixed arena: both players must move independently, place personal timed bombs, destroy crates, collect the original Bomb/Fire/Skate power-ups, use direct or chained cross explosions, and reach a stable Player 1 win, Player 2 win, or draw (`CONTENT-01` through `ASSET-04`).

## 2. Scope

### 2.1 Included Work

| Requirement IDs | Summary |
|---|---|
| `CONTENT-01`, `MATCH-01` | Assemble the supplied 11x9 arena, two players, three-second countdown, and active match. |
| `INPUT-01`, `INPUT-02` | Support independent keyboard control for Player 1 and Player 2. |
| `BOMB-01` through `BOMB-03` | Support personal bomb capacity, timed cross explosions, bomb collision, and chain reactions. |
| `RULE-01`, `RULE-02` | Apply wall and crate blocking/destruction rules. |
| `POWERUP-01` through `POWERUP-04` | Reveal and collect the supplied Bomb, Fire, and Skate power-ups. |
| `COMBAT-01`, `OBJECTIVE-01`, `DRAW-01`, `TIMER-01`, `TERMINAL-01` | Resolve death, wins, simultaneous-death draw, timeout draw, and terminal locking. |
| `INTERFACE-01`, `FEEDBACK-01` | Present synchronized duel HUD and readable action feedback. |
| `LIFECYCLE-01`, `LIFECYCLE-02` | Support clean same-process restart and clean true reopen. |
| `ASSET-01` through `ASSET-04` | Use the supplied original character, animation, arena, power-up, bomb, and marker assets in the required visible roles. |
| `QUALITY-01` through `QUALITY-06` | Meet the shared launch, input, readability, feedback, stability, and repeatability baseline. |

### 2.2 Excluded Work

AI opponents, online sessions, Steam integration, menus, character selection, difficulty settings, procedural generation, more than two players, save-game progression, multiple levels, mods, progression, settings, localization, and the original game's author/community UI are outside this task.

## 3. Starting State

| Item | Starting State | Related Requirement IDs |
|---|---|---|
| Engine | Unreal Engine 5.7.4 on Windows x64. | Toolchain fact, not scored by itself |
| Project entry | `starter-project/BomberStarter.uproject` opens a non-gameplay English health screen. | `QUALITY-01` |
| Gameplay | No duel gameplay is implemented in the starter. | `CONTENT-01` through `TERMINAL-01` |
| Arena data | `starter-project/Config/BomberArenaLayout.json` supplies the fixed 11x9 layout, two starts, fifteen crates, and three power-up contents. | `CONTENT-01`, `POWERUP-01` |
| Clean asset kit | A content-only plugin and project content supply the original character, locomotion, arena, power-up, bomb, and local marker assets. | `ASSET-01` through `ASSET-04` |
| First round | The round begins in a three-second countdown. Player 1 is at `(1,1)`, Player 2 at `(9,1)`, both are alive, each has `1/1` bombs, Fire `2`, Skate `0`, all crates are present, all power-ups are hidden, and the match clock is `45`. | `MATCH-01`, `INTERFACE-01`, `LIFECYCLE-02` |

## 4. Player Goal and Complete Flow

### 4.1 Player Goal

Each player tries to remain alive while using movement, crates, three original power-up types, and timed or chained explosions to eliminate the opponent. If both players die in the same explosion transaction or the clock expires while both remain alive, the round is a draw.

### 4.2 Complete Player Flow

```text
Launch the fixed duel arena
-> [MATCH-01] wait through 3, 2, 1, GO while gameplay input is locked
-> [INPUT-01, INPUT-02] move both players independently through the grid
-> [BOMB-01, BOMB-02, RULE-01, RULE-02] place bombs, leave their cells, and open crate routes
-> [POWERUP-01..04] reveal and collect Bomb, Fire, and Skate upgrades for the collecting player only
-> [BOMB-03] use two-bomb placement and a legal chain reaction
-> [COMBAT-01, OBJECTIVE-01, DRAW-01, TIMER-01] resolve a win or draw
-> [TERMINAL-01] keep the result stable
-> [LIFECYCLE-01] press R for a clean new countdown
```

### 4.3 Core Loop

```text
Choose a floor cell and escape route
-> place a personal bomb
-> leave the bomb cell before it becomes an obstacle
-> read the fuse, walls, crates, bombs, opponent position, and projected danger
-> collect an exposed upgrade or pressure the opponent
-> repeat until a win or draw commits
```

## 5. Player Controls

| Requirement IDs | Player | Action | Context | Response Summary |
|---|---|---|---|---|
| `INPUT-01` | Player 1 | Hold/release `W`, `A`, `S`, `D` | Active match | Move up, left, down, right; release stops intentional movement. |
| `BOMB-01` | Player 1 | Press `Space` | Active match | Place one Player 1 bomb when a personal slot is available. |
| `INPUT-02` | Player 2 | Hold/release `Up`, `Left`, `Down`, `Right` | Active match | Move up, left, down, right; release stops intentional movement. |
| `BOMB-01` | Player 2 | Press `Right Shift` | Active match | Place one Player 2 bomb when a personal slot is available. |
| `LIFECYCLE-01` | Shared | Press `R` once | Countdown, active, or terminal | Start a clean new round in the same process. |

## 6. Numbered Requirements: Sole Acceptance Authority

This section is the only source of acceptance requirements. Other sections summarize these IDs.

### 6.1 Requirement Splitting Rule

Each row describes one player-visible result that can fail independently. Exact values, text, ordering, and boundaries affect acceptance only when stated in a row below.

### 6.2 Task-Specific Requirements

| Requirement ID | Preconditions | Player Action or Trigger | Required Result | Prohibited Result | Player-Visible Feedback | Failure, Repeat, Restart, or Other Boundary |
|---|---|---|---|---|---|---|
| `CONTENT-01` | The documented default entry is launched. | The first round is created. | Present exactly the fixed 11x9 layout in `starter-project/Config/BomberArenaLayout.json`, with one Player 1 at `(1,1)`, one Player 2 at `(9,1)`, all listed indestructible walls, and all fifteen listed crates. The open vertical lanes below both starts extend through `y=4`, so either player can leave a first Fire 2 bomb's blast footprint. Every non-wall cell can become reachable after legal crate destruction. | Do not rearrange the arena, omit or duplicate a required object, add an AI player, or start either player inside a wall/crate. | Floor, walls, crates, Player 1, and Player 2 are distinguishable in the normal shared view. | Initial launch and each clean restart create exactly one fresh copy of every listed object. |
| `MATCH-01` | A fresh round has been created. | Allow the round to start without pressing `R`. | Enter a visible three-second countdown that presents `3`, then `2`, then `1`, then `GO`; each numeral remains for `0.75` through `1.25` seconds. Both players remain at their start cells and cannot place bombs during the countdown. After `GO`, enter the active match exactly once with `45` seconds remaining. | Movement, bombs, crate changes, pickups, death, or terminal results must not occur during countdown. | The countdown and transition to active play are clearly visible and audible or visually emphasized. | Restart during countdown begins a new full countdown; stale countdown events from the old round do not activate the new round early. |
| `INPUT-01` | The match is active and Player 1 is alive. | Hold/release `W`, `A`, `S`, or `D`. | Player 1 moves respectively up, left, down, or right through floor cells and can turn at passages; release ends intentional movement. | Player 1 must not move opposite the pressed direction, pass through blocked cells, continue indefinitely after release, or move Player 2. | Player 1 position and locomotion presentation respond visibly. | Repeated holds remain responsive; countdown and terminal behavior follow `MATCH-01` and `TERMINAL-01`. |
| `INPUT-02` | The match is active and Player 2 is alive. | Hold/release `Up`, `Left`, `Down`, or `Right`. | Player 2 moves respectively up, left, down, or right through floor cells and can turn at passages; release ends intentional movement. | Player 2 must not move opposite the pressed direction, pass through blocked cells, continue indefinitely after release, or move Player 1. | Player 2 position and locomotion presentation respond visibly. | Simultaneous Player 1 and Player 2 input remains independent; countdown and terminal behavior follow `MATCH-01` and `TERMINAL-01`. |
| `BOMB-01` | The match is active, the acting player is alive, and that player's `BOMBS` available value is at least one. | Press that player's bomb key once. | Place exactly one bomb on the acting player's current floor cell, assign ownership to that player, capture that player's current Fire value for this bomb, and decrease only that player's available bomb count by one. A player standing on their newly placed bomb may leave its cell. After leaving, that bomb blocks both players from entering its cell. | A press must not place multiple bombs, use the other player's resource, place in another cell, or allow any player to enter a bomb cell from another cell. A rejected press at zero available bombs must not create or move a bomb. | The bomb is visible and uses the owner's required supplied bomb presentation; a rejected attempt shows `BOMB NOT READY` for that player. | When that bomb has completed its only explosion, exactly one slot returns to its owner. Repeated rejected presses do not stack bombs or duplicate refunds. |
| `BOMB-02` | An armed bomb exists in an active match. | Let its fuse expire without a chain trigger or restart. | Detonate `1.80` seconds after placement with tolerance `±0.15` seconds. Include the bomb cell and extend in the four cardinal directions up to its captured Fire range. Show the blast for `0.35` through `0.65` seconds, then clear it. | Do not detonate immediately, extend diagonally, skip the bomb cell, exceed captured range, or leave permanent damaging blast cells. | The fuse has a perceptible armed cue and the explosion is a bright readable cross. | Each bomb follows the same timing. Restart cancels old fuses and blast visuals. |
| `BOMB-03` | At least two armed bombs exist and one bomb's legal blast reaches another bomb cell. | The first bomb detonates. | Include the reached bomb cell, stop that incoming ray at the bomb, and trigger the reached bomb immediately without waiting for its remaining fuse. Resolve all bombs reached by the same chain exactly once, using each chained bomb's own captured Fire range and owner. | A chained bomb must not ignore the trigger, wait for its old fuse, detonate twice, duplicate an owner refund, or allow the incoming ray to pass through its cell before the chained bomb resolves. | The chain is visibly readable as connected explosion crosses. | The entire connected chain resolves before `COMBAT-01`, `OBJECTIVE-01`, or `DRAW-01` commits a result. Unrelated bombs are not triggered. |
| `RULE-01` | A blast ray reaches an indestructible wall. | The explosion resolves. | The wall remains present and stops the ray before the wall cell; no cell beyond that wall is affected by that ray. | A wall must not be destroyed, entered, hidden by replacement geometry, or transmit damage. | The blast terminates visibly at the wall. | The same wall blocks later movement and explosions and is restored unchanged after restart. |
| `RULE-02` | A blast ray reaches a present destructible crate. | The explosion resolves. | Include the crate cell, destroy that crate exactly once, and stop that ray so the same explosion does not affect the next cell beyond it. The cleared crate cell becomes traversable after the blast clears. | A crate must not survive a direct blast, require multiple hits, damage a cell behind it in that ray, or be destroyed repeatedly. | The supplied crate visibly disappears or breaks and reveals readable floor or a power-up. | A destroyed crate remains absent for that round; restart restores it. |
| `POWERUP-01` | One of the three designated containing crates is present. | A legal blast destroys it. | Reveal exactly one supplied power-up on the same cell: Bomb at `(3,1)`, Fire at `(5,1)`, or Skate at `(3,3)`. It remains available until collected or restart and survives the blast that reveals it. | Do not reveal a power-up early, duplicate it, move it to another cell, reveal one from any other crate, or destroy it with its revealing blast. | Bomb, Fire, and Skate are visibly distinct using their supplied meshes. | Restart hides all three inside their restored crates. |
| `POWERUP-02` | The Bomb power-up is available and the entering player has bomb capacity `1`. | That player enters `(3,1)` through normal movement. | Collect it once for that player only, remove the pickup, increase personal bomb capacity from `1` to `2`, and immediately make the added slot available. | Do not change Fire, Skate, the other player's values, or increase capacity beyond `2`. | That player's HUD shows `BOMBS: <available>/2` and a temporary `BOMB UP` message. | Revisiting has no effect; restart restores both players to `1/1` and restores the hidden pickup. |
| `POWERUP-03` | The Fire power-up is available and the entering player has Fire `2`. | That player enters `(5,1)` through normal movement. | Collect it once for that player only, remove the pickup, and increase personal Fire from `2` to `3` for bombs placed afterward. | Do not change bomb capacity, Skate, the other player's values, exceed Fire `3`, or retroactively change an already armed bomb's captured range. | That player's HUD shows `FIRE: 3` and a temporary `FIRE UP` message. | Revisiting has no effect; restart restores Fire `2` and the hidden pickup. |
| `POWERUP-04` | The Skate power-up is available and the entering player has Skate `0`. | That player enters `(3,3)` through normal movement. | Collect it once for that player only, remove the pickup, set Skate to `1`, and make subsequent held movement observably faster: after the initial immediate step, repeated cell steps use `0.10` through `0.13` seconds instead of the base `0.16` through `0.20` seconds. | Do not change bomb capacity, Fire, the other player's values, exceed Skate `1`, or move while no direction is held. | That player's HUD shows `SKATE: 1`, a temporary `SKATE UP` message appears, and faster locomotion remains readable. | Revisiting has no effect; restart restores Skate `0` and the hidden pickup. |
| `COMBAT-01` | The match is active and one or both players are alive. | A completed direct or chained explosion transaction includes a living player's cell. | Mark every hit player dead exactly once, play a readable defeat response, make dead players non-blocking and unable to move, place bombs, or collect power-ups, then adjudicate the result from the set of survivors. | Contact, movement, a blocked blast, a cleared old blast, or repeated overlap after death must not kill a player. Result adjudication must not occur halfway through a still-connected chain. | Each death is visually clear and the HUD alive state updates. | Restart restores both players alive. |
| `OBJECTIVE-01` | `COMBAT-01` finishes an explosion transaction with exactly one survivor. | The survivor set is evaluated. | If Player 1 alone survives, enter `player1_win` once with exact overlay `PLAYER 1 WINS`; if Player 2 alone survives, enter `player2_win` once with exact overlay `PLAYER 2 WINS`. | Do not award a win while both are alive, while no one survives, or more than once in the same round. | The survivor remains identifiable and the exact winner overlay is stable. | The terminal round follows `TERMINAL-01`; `R` follows `LIFECYCLE-01`. |
| `DRAW-01` | A connected direct or chained explosion transaction begins with both players alive. | That transaction hits both players before result adjudication. | Mark both dead and enter `draw` exactly once with exact overlay `DRAW`. | Do not choose a winner based on blast iteration order, bomb owner, or which player was processed first. | Both defeat responses and the stable `DRAW` overlay are visible. | The terminal round follows `TERMINAL-01`; `R` follows `LIFECYCLE-01`. |
| `TIMER-01` | The match is active and both players remain alive. | Active match time elapses. | Decrease the displayed timer from `45` toward `0` using real elapsed seconds. At `0`, enter `draw` exactly once with exact overlay `DRAW`. | Countdown time must not consume the active match timer. The timer must not run below zero, skip directly to a win, or keep gameplay active after timeout. | The clock is continuously visible; the final ten seconds have a distinct visual or audible urgency cue. | Restart and true reopen restore `45`. Terminal behavior follows `TERMINAL-01`. |
| `INTERFACE-01` | The round is in countdown, active, or terminal phase. | Observe the HUD before and after all resource, timer, death, restart, and result events. | Continuously show `TIME: <0-45>`, `ALIVE: <0-2>`, and separate Player 1 and Player 2 panels containing exact labels `BOMBS: <available>/<capacity>`, `FIRE: <2-3>`, and `SKATE: <0-1>`. Values remain synchronized with gameplay truth. | Do not merge player resources, hide required values, display impossible values, drift from truth, or duplicate HUD layers after restart. | All labels and values are readable at 1280x720. | Clean restart/reopen show Time `45`, Alive `2`, and both players at `1/1`, Fire `2`, Skate `0`. |
| `FEEDBACK-01` | The relevant action is legal or rejected. | A player moves, places or is refused a bomb, watches a fuse/chain, destroys a crate, reveals/collects a power-up, dies, wins, or draws. | Each listed event has a distinct perceptible response; the two players and their owned bombs remain distinguishable. | Critical feedback must not exist only in logs or the read-only state files. Permanent visual effects or messages must not accumulate after repeated events. | Use readable character locomotion, bomb armed cue, cross/chain blast, crate removal, supplied power-up presentation, pickup message, defeat response, urgency cue, and terminal overlay. | Repeated events remain readable; restart removes all transients. |
| `LIFECYCLE-01` | The process is in countdown, active, or terminal phase. | Press `R` once. | Start a new three-second countdown with Player 1 `(1,1)`, Player 2 `(9,1)`, both alive, all fifteen crates present, all three power-ups hidden, no bombs/blasts, Time `45`, Alive `2`, and both players at `1/1`, Fire `2`, Skate `0`. | Do not preserve old fuses, chains, destroyed crates, pickups, deaths, results, timer progress, duplicate actors, HUD layers, or delayed callbacks. | Arena, players, HUD, and countdown visibly return to the clean composition. | Consecutive restarts remain clean after every old fuse/blast/countdown deadline would have passed. |
| `LIFECYCLE-02` | Any prior in-process progress exists and the game is closed normally. | End the old process and launch a new one through the documented entry. | Begin from the same clean countdown and initial state defined by `LIFECYCLE-01`, with a new process identity and no persistent match progress. | Do not persist resources, destroyed crates, pickups, bombs, timer, deaths, or terminal result. | The new process presents the same clean arena and HUD as a first launch. | Every later true reopen repeats this reset. |
| `TERMINAL-01` | `OBJECTIVE-01`, `DRAW-01`, or `TIMER-01` has committed. | Send both players' movement and bomb input without pressing `R`. | Keep phase, survivor/death state, resources, crates, timer, and result overlay stable. Remove or harmlessly cancel any unrelated pending bomb/fuse after current visible chain feedback completes. | Post-terminal input must not move players, place/detonate new bombs, destroy crates, collect power-ups, alter the timer, or retrigger the result. | The exact terminal overlay remains visible and normal play is clearly locked. | `R` is the only required action that leaves terminal state. |
| `ASSET-01` | The supplied character kit is present. | A round starts and either player moves. | Render both players with `/BlockoutMap/BlockoutMap/Characters/Mannequins/Meshes/SKM_Quinn_Simple`. Use `MI_Quinn_01` for Player 1 and `MI_Quinn_02` for Player 2. Use the supplied `MM_Manny_Idle` animation for the character presentation; movement must visibly translate and orient the animated character instead of replacing it with another model. | Do not replace either required player with an engine primitive, different mesh, missing material, static unanimated pose for both states, or original author/community UI. | The two supplied material variants, movement animation, and death presentation make both players readable. | Every restart recreates the required player presentation. |
| `ASSET-02` | The supplied arena meshes are present. | The arena is assembled and crates are destroyed. | Render every indestructible wall with `SM_BlockoutMap_Wall` and every destructible crate with `SM_BlockoutMap_Box`. | Do not use engine cube primitives or replacement models for required wall/crate cells. | The supplied wall and box silhouettes are recognizable throughout normal play. | Restart restores all supplied crate visuals without duplicates. |
| `ASSET-03` | The supplied power-up meshes are present. | The three containing crates reveal their pickups. | Render Bomb with `SM_BlockoutMap_Powerup_Bomb`, Fire with `SM_BlockoutMap_Powerup_Fire`, and Skate with `SM_BlockoutMap_Powerup_Skate`. | Do not swap meanings, use one mesh for all three, substitute primitives, or hide an available pickup. | Each supplied model is visible and distinguishable before collection. | Restart restores their hidden-in-crate lifecycle. |
| `ASSET-04` | The supplied bomb and marker assets are present. | Either player places a bomb and a fresh round begins. | Render bombs with `/Game/Bomber/Meshes/SM_Bomb` and supplied bomb material instances, using visibly different supplied colors for the two owners. Render `/Game/Bomber/Meshes/SM_PlayerArrowStart` with `MI_PlayerArrowStart` above Player 1 for at least `2.0` seconds after each clean round begins. | Do not use an engine primitive, replacement bomb, missing material, or place the marker above Player 2 instead of Player 1. | Bomb ownership and the local Player 1 marker are immediately readable. | The marker returns after each restart and may fade after the required interval. |

### 6.3 Shared Quality Requirements

| Requirement ID | Formal Requirement |
|---|---|
| `QUALITY-01` | The project can be launched, run, exited, and launched again by following the public instructions. |
| `QUALITY-02` | The complete main flow uses normal player input and does not depend on a cheat, answer button, or direct gameplay-result invocation. |
| `QUALITY-03` | Critical entrances, text, controls, players, arena objects, and power-ups are visible, discoverable, readable, and operable. |
| `QUALITY-04` | Player actions produce perceptible feedback and the interface remains consistent with true game state. |
| `QUALITY-05` | No severe error blocks the main flow. |
| `QUALITY-06` | Repeated runs from the same initial conditions produce substantially stable results. |

## 7. Success, Failure, and Multi-Stage Flow Summary

### 7.1 Success

| Requirement IDs | Pre-Success | Success | Post-Success | Feedback |
|---|---|---|---|---|
| `COMBAT-01`, `OBJECTIVE-01`, `TERMINAL-01` | A complete explosion transaction leaves exactly one player alive. | The correct player wins once. | Gameplay locks until `R`. | Exact `PLAYER 1 WINS` or `PLAYER 2 WINS` overlay. |

### 7.2 Failure and Draw

| Requirement IDs | Outcome | Post-Outcome | Feedback | Retry |
|---|---|---|---|---|
| `COMBAT-01`, `OBJECTIVE-01` | The local player may lose when only the opponent survives. | Stable opponent win. | Exact winner overlay and defeat response. | Press `R`. |
| `DRAW-01`, `TIMER-01` | Both die in one chain transaction, or time reaches zero with both alive. | Stable draw. | Exact `DRAW` overlay. | Press `R`. |

### 7.3 Multi-Stage Flow

| Stage | Requirement IDs | Summary | Prevents Early Result |
|---|---|---|---|
| Countdown | `MATCH-01` | Lock gameplay through 3, 2, 1, GO. | `BOMB-01`, `COMBAT-01`, `TIMER-01` |
| Opening | `INPUT-01`, `INPUT-02`, `BOMB-01`, `BOMB-02`, `RULE-01`, `RULE-02` | Open fixed crate lanes with safe timed bombs. | `OBJECTIVE-01`, `DRAW-01` |
| Upgrade | `POWERUP-01` through `POWERUP-04` | Reveal and collect all three original upgrade types. | `BOMB-03` requires Bomb capacity two for a normal player-created chain. |
| Duel | `BOMB-03`, `COMBAT-01` | Use direct and chained explosions against the opponent. | `OBJECTIVE-01` and `DRAW-01` wait for the whole chain transaction. |
| Terminal | `OBJECTIVE-01`, `DRAW-01`, `TIMER-01`, `TERMINAL-01` | Present one stable result and lock play. | Only `R` may leave. |

## 8. Interface and Feedback Summary

| Requirement IDs | Required Visible Information |
|---|---|
| `MATCH-01`, `TIMER-01` | Countdown, `GO`, clock, final-ten-second urgency. |
| `INTERFACE-01` | Time, alive count, and separate resource panels for both players. |
| `FEEDBACK-01` | Locomotion, bomb ready/refusal, fuse, cross/chain explosion, crate/pickup transitions, death, winner, draw. |
| `ASSET-01` through `ASSET-04` | Supplied original character, arena, power-up, bomb, and marker visuals in their defined roles. |

## 9. Restart, Reopen, and Save Summary

| Requirement IDs | Summary |
|---|---|
| `LIFECYCLE-01` | `R` creates a clean countdown and complete initial duel state in the same process. |
| `LIFECYCLE-02` | A true process reopen discards all match progress. |
| None | This task has no save-game progress. |

## 10. Original Features That Must Be Preserved

| Requirement IDs | Original Feature Preserved in This Slice |
|---|---|
| `CONTENT-01`, `INPUT-01`, `INPUT-02` | Local grid duel with two independently controlled players. |
| `MATCH-01`, `TIMER-01` | Game-start countdown, active match clock, and end-game phase. |
| `BOMB-01` through `RULE-02` | Personal bombs, cross explosions, walls, crates, bomb blocking, and chain reactions. |
| `POWERUP-01` through `POWERUP-04` | Original Bomb, Fire, and Skate upgrade types. |
| `COMBAT-01`, `OBJECTIVE-01`, `DRAW-01` | Player death, winner resolution, and draw resolution. |

## 11. Asset and Content Requirements

`ASSET_MANIFEST.json` and `assets/ASSET_CATALOG.json` are the path and hash authorities. The required visible roles are:

| Requirement ID | Required Supplied Content | Replacement Boundary |
|---|---|---|
| `ASSET-01` | Quinn mesh, two Quinn material instances, and the supplied idle animation under the documented logical paths. | Required character mesh, materials, and idle animation cannot be replaced. |
| `ASSET-02` | BlockoutMap wall and box meshes. | Required wall and crate models cannot be replaced. |
| `ASSET-03` | BlockoutMap Bomb, Fire, and Skate power-up meshes. | Required power-up models cannot be replaced or swapped. |
| `ASSET-04` | Bomber bomb mesh/material instances and Player 1 arrow marker mesh/material. | Required bomb and marker models cannot be replaced; supplied color selection remains free within `ASSET-04`. |

The clean kit contains no original gameplay Blueprint, AI, input mapping, game mode, StateTree, data registry, map, menu, save, evaluator, or answer implementation.

## 12. Implementation Freedom

Any Blueprint, C++, component, actor, data, state-machine, UI, or material-assembly architecture is allowed if every Section 6 result is met. You may use engine primitives only for non-required floor, lighting, debug-free explosion geometry, and other supporting presentation. Internal class names, source layout, algorithms, actor hierarchy, interpolation, and animation control are not prescribed. The read-only public observation schema must be populated honestly, but it must not be used to trigger gameplay outcomes.

## 13. Submission Self-Check

- [ ] The project uses Unreal Engine 5.7.4 and the documented default entry.
- [ ] The starter's health screen has been replaced by a playable two-player duel.
- [ ] Countdown, both control schemes, personal bomb resources, three power-ups, chain reaction, win/draw, timer, restart, and reopen all work through normal input.
- [ ] Both player resource panels remain synchronized and readable at 1280x720.
- [ ] Every required supplied character, arena, power-up, bomb, and marker asset is used in its required visible role.
- [ ] No original gameplay logic, author/community UI, evaluator content, cheat, or answer shortcut has been copied into the candidate.
- [ ] Terminal input is locked and restart clears every pending timer, bomb, blast, callback, and duplicate presentation layer.

