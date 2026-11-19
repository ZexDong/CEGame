# Arrow Escape — Public Game Design Document

Task ID: `unity.arrow_escape_reconstruction.v2`

This document follows the repository `GAME_DESIGN_TEMPLATE.md`. It describes the player goal, rules, visible feedback, content scope, and lifecycle behavior. **Section 6 is the only acceptance source.** Every other section is a numbered-requirement summary.

Engine startup, workspace permissions, tool usage, asset inventory, and fixed delivery locations are documented separately in `README.md`, `TOOLCHAIN.md`, `INITIAL_AGENT_PROMPT.md`, `UNITY_OFFLINE_AGENT_MANUAL.md`, `BENCHMARK_MANIFEST.json`, and `ASSET_MANIFEST.json`.

## 1. One-sentence task

Create a playable grid puzzle in which the player clicks colored arrows, removes every arrow in a legal order before the available budget is exhausted, can visibly move among the three authored levels, receives clear success/failure feedback, and can restart or reopen into a clean playable session (`FLOW-01` through `FLOW-04`, `NAV-01`, `RESTART-01`, `REOPEN-01`).

## 2. Scope

### 2.1 Included in this task

| Requirement IDs | Summary |
|---|---|
| `FLOW-01`–`FLOW-04` | Playable entry, arrow removal, win, and loss |
| `CONTENT-01`–`CONTENT-05` | Tutorial, Hearts/Hint content, dependency chain, four-direction support, and authored AND content |
| `INPUT-01`–`INPUT-02` | Normal mouse selection and ignored-click behavior |
| `RULE-01`–`RULE-05` | Blocking, movement outcome, budget costs, and last-move priority |
| `HINT-01` | Legal, free, temporary Hint feedback |
| `NAV-01` | Visible cycling among all three authored levels |
| `DEPENDENCY-01`–`DEPENDENCY-02` | Multi-prerequisite locks and visible key/lock state |
| `UI-01`–`UI-03` | Simultaneous game information, terminal labels, and state-synchronized feedback |
| `VISUAL-01` | Original-inspired visual identity and coherent final assembly |
| `RESTART-01`, `REOPEN-01` | Clean restart and close/reopen behavior |
| `ASSET-01` | Supplied badge art used for its intended visible role |
| `QUALITY-01`–`QUALITY-06` | Shared playability baseline |

### 2.2 Not included

No numbered requirement covers advertisements, purchases, stores, theme buying, networking, leaderboards, mobile builds, elaborate particles, or a full reproduction of every upstream level. These items are outside the task scope.

## 3. Starting state

| Item | Starting fact | Related requirement IDs |
|---|---|---|
| Project | An importable Unity Starter with a bootstrap view and pinned offline tools | `QUALITY-01` |
| Gameplay | The target Arrow Escape play loop is absent | `FLOW-01`–`FLOW-04` |
| Art | Board, arrow, HUD, Hint, Restart, Next Level, key, and lock art is supplied | `UI-01`, `ASSET-01` |
| Technical delivery notes | Separate public operating documents describe non-gameplay engine and delivery facts | No gameplay requirement |
| Target content | Three player-reachable authored gameplay levels are not present yet | `CONTENT-01`–`CONTENT-05`, `NAV-01` |
| Runtime progress | No previous play session exists in the Starter | `RESTART-01`, `REOPEN-01` |

## 4. Player goal and complete flow

### 4.1 Player goal

The player studies each arrow's head direction, removes currently legal arrows, uses Hint when useful, avoids wasting Moves or Hearts on blocked/locked choices, and clears every arrow before loss (`RULE-01`–`RULE-05`, `HINT-01`, `FLOW-03`, `FLOW-04`).

### 4.2 Complete player flow

```text
Enter the game
→ [FLOW-01, UI-01] See a playable tutorial board and current budget
→ [INPUT-01, RULE-01] Click a visible arrow and resolve whether its path is clear
→ [RULE-02, RULE-03, RULE-04] Observe motion or blocked/locked feedback and budget changes
→ [HINT-01] Optionally request a legal target without spending budget
→ [NAV-01] Use visible Next Level to enter each other authored level as a fresh session
→ [FLOW-03 or FLOW-04, UI-02] Reach COMPLETED or FAILED
→ [RESTART-01] Restart the current authored level
→ [REOPEN-01] Close and reopen the game into a fresh playable session
```

### 4.3 Main loop

```text
[INPUT-01, NAV-01] Choose an arrow, Hint, Restart, or Next Level
→ [RULE-01, DEPENDENCY-01] Resolve geometry and prerequisites
→ [RULE-02, RULE-03, RULE-04] Apply movement/feedback and the current budget rule
→ [UI-03] Read the updated board, badge, budget, Hint, and terminal state
→ choose the next action until [FLOW-03] or [FLOW-04]
```

## 5. Player actions

| Requirement IDs | Player action | When it is used | Response summary |
|---|---|---|---|
| `INPUT-01`, `RULE-01`–`RULE-04` | Left-click a visible arrow | During active play | One clear, blocked, or locked selection is resolved |
| `HINT-01` | Left-click Hint | During active play | A legal target is temporarily highlighted without budget cost |
| `RESTART-01` | Left-click Restart | During active play, movement, success, or failure | The current authored level returns to its initial state |
| `NAV-01` | Left-click Next Level | During active play, movement, success, or failure | A fresh next authored level loads in the public cycle |
| `INPUT-02` | Click blank space, an exited/moving arrow, or the board after a terminal state | At any applicable time | The click is ignored |

## 6. Numbered requirements: sole acceptance source

### 6.1 Requirement boundaries

Every game-specific obligation, prohibition, visible result, and lifecycle boundary used for acceptance is defined by one row in Section 6.2. Other sections only summarize these requirement IDs.

### 6.2 Task-specific requirement table

| Requirement ID | Preconditions | Player action or trigger | Required result | Forbidden result | Player-visible feedback | Failure, repetition, restart, or other boundary |
|---|---|---|---|---|---|---|
| `FLOW-01` | The saved default play entry is opened | Start Play | Within ten stable frames or one second, a fresh `tutorial` session is active with at least one arrow available for play | A blank/non-playable entry, an already-terminal session, or no active arrows | The board, arrows, budget information, Hint, and Restart are visible | Repeating a fresh start produces the same initial authored session |
| `FLOW-02` | An active arrow is unlocked and its forward path is clear | Complete one normal left-click on that arrow | The arrow travels continuously over multiple frames in its head direction, preserves its recognizable shape/color, becomes removed only after fully leaving the logical board, and finishes within four seconds | Teleporting in a single frame; moving sideways/backward; disappearing while still inside the board; remaining logically occupied after full exit | Continuous forward motion followed by the arrow leaving the board | Further clicks on the same moving or removed arrow have no effect (`INPUT-02`) |
| `FLOW-03` | At least one active arrow remains | Legally remove every authored active arrow | Success begins only after the final arrow is fully outside; the session becomes won and displays `COMPLETED` | Success while any authored arrow remains; `FAILED` shown together with `COMPLETED` | `COMPLETED` is clearly visible and the final board state is understandable | Gameplay selections are frozen after success; Restart remains usable |
| `FLOW-04` | The current budget reaches zero without satisfying `FLOW-03` | Finish the selection that spends the last available budget unit | The session becomes lost, displays `FAILED`, and freezes further gameplay selections | Negative budget; continuing arrow actions after loss; `COMPLETED` shown together with `FAILED` | `FAILED` and zero remaining budget are clearly visible | Restart remains usable after loss |
| `CONTENT-01` | The default authored level is loaded | Start or restart `tutorial` | The level uses Moves, contains at least three arrows, initially contains both a clear arrow and a geometrically blocked arrow, and has a legal order that removes every authored arrow | An unsolvable tutorial; declaring success after only a subset of authored arrows | The player can see and distinguish the initial clear and blocked possibilities through play/feedback | The minimum is not an exact arrow count; every authored active arrow participates in completion |
| `CONTENT-02` | The authored Hearts/Hint level is loaded | Begin the level and interact with its arrows/Hint | The level uses Hearts with an initial value of at least two and simultaneously offers a successful clear, a blocked failure, and a legal Hint target | A Hearts level that cannot demonstrate both a free successful exit and a Heart-losing failed attempt | Mode, remaining Hearts, blocked feedback, and Hint highlight are visible | Repeated clean loads restore the same authored starting content |
| `CONTENT-03` | The authored dependency-chain level is loaded | Play through its dependency stages | The level contains exactly three labeled arrows with relations `key_a` → `lock_b` → `lock_c`; initially only `key_a` is available, then `lock_b`, then `lock_c`, and the full chain can reach success | Either lock becoming available before its direct predecessor is fully outside; extra arrows in this fixed chain level | Initial and updated key/lock badges make each stage distinguishable | Restart restores the initial chain and badges |
| `CONTENT-04` | The default authored `tutorial` level is freshly loaded | Within that tutorial, select clear/unlocked arrows pointing Up, Down, Left, and Right | All four cardinal directions are present in the player-reachable tutorial and follow the same continuous full-exit behavior from `FLOW-02` | A direction existing only in player-inaccessible developer-only or unconnected content; a direction-specific shortcut or unsupported direction | Head direction and forward movement are unambiguous in every direction | Direction does not change the budget, blocking, dependency, navigation, or restart rules |
| `CONTENT-05` | The authored `modes_and_hint` level is freshly loaded | Play its visible multi-prerequisite group | It contains labeled arrows `and_key_left`, `and_key_right`, and `and_lock`; `and_lock` requires both keys, remains locked after either one alone exits, becomes available after both fully exit, and can then exit regardless of key completion order | The AND group existing only in player-inaccessible developer-only or unconnected content; unlocking after one key; one completion order failing | The two unfinished keys and the locked dependent have readable key/lock badge states | Restart restores both keys and the locked dependent; unrelated Hearts/Hint content remains part of the same authored level |
| `INPUT-01` | A visible arrow, Hint, Restart, or Next Level target is unobstructed | Perform one complete normal Mouse left-click on the visible topmost target | Exactly one matching player action is committed | One click committing twice; a press committing before a same-target release; an invisible overlay receiving the action instead | The clicked target reacts and the resulting game/UI state matches that action | The same input path remains reusable after blocked feedback and Restart |
| `INPUT-02` | Blank space, a removed arrow, a moving arrow, or the gameplay area after win/loss is clicked | Perform a normal left-click | Budget, phase, occupancy, selection history, and Hint state remain unchanged | Spending budget or starting another action from ignored input | No misleading success/failure response is shown | Repeated ignored clicks remain harmless |
| `NAV-01` | Any authored level is active | Click visible Next Level | Within one second, a fresh authored level loads in the fixed cycle `tutorial` → `modes_and_hint` → `prerequisite_chain` → `tutorial`; the new level starts with its authored arrows, initial budget, active phase, badges, cleared Hint, and no terminal label | Requiring developer-only loading or any non-player control to reach a required level; carrying spent budget, old arrows, motion, Hint, or terminal state into the new level | The visible level ID, mode, budget, board, arrows, and badges update together | The same cycle works from active play, in-flight motion, win, or loss, and repeated use never duplicates one click |
| `RULE-01` | An active unlocked arrow is considered for movement | Select the arrow or request a Hint candidate | Starting at the board cell immediately in front of its head, every cell in that direction through the boundary is considered; another active arrow in any such cell blocks it | Ignoring an occupied forward cell; treating cells behind or beside the head as forward blockers | A blocked selection uses the feedback in `RULE-02` | Removed arrows no longer block later selections |
| `RULE-02` | The selected arrow is geometrically blocked | Complete one normal click on it | The arrow stays in the same board cells, does not begin exit motion, and shows target-local feedback for at least 0.15 seconds that returns to normal within one second | Position/cell changes, partial motion, exit, permanent feedback, or duplicate handling | The selected arrow itself visibly indicates the failed attempt | A later attempt can be made normally after feedback recovers; cost follows `RULE-03` or `RULE-04` |
| `RULE-03` | The current level uses Moves and is not terminal | Complete a clear, blocked, or locked attempt on an active non-moving arrow | Exactly one Move is spent; ignored input spends zero; remaining Moves never drops below zero | Different costs for clear/blocked/locked attempts; duplicate spending from one click | Remaining Moves updates with the real state | `RULE-05` governs a legal final Move; Restart restores the authored initial value |
| `RULE-04` | The current level uses Hearts and is not terminal | Complete an arrow attempt | Blocked and locked attempts spend exactly one Heart; a successful exit and ignored input spend zero; remaining Hearts never drops below zero | Charging a Heart for a successful exit; failing to charge a blocked/locked attempt; duplicate spending | Remaining Hearts updates with the real state | Zero Hearts without a win follows `FLOW-04`; Restart restores the authored initial value |
| `RULE-05` | In Moves mode, the last legal arrow starts exiting when the click reduces Moves to zero | Wait for that arrow's motion to finish | The game waits for full exit and awards `FLOW-03` success instead of losing early | Entering loss while the last legal arrow is still completing its valid exit | Zero Moves may be visible during motion, followed by `COMPLETED` after full exit | If active arrows remain when budget reaches zero, `FLOW-04` applies instead |
| `HINT-01` | The session is active | Click Hint | Hint spends no budget and highlights only an active, unlocked, non-moving arrow whose geometric path is currently clear; any legal target is acceptable; highlight lasts at least 0.5 seconds and clears or updates within 1.5 seconds | Highlighting blocked/locked/moving/removed arrows; deterministic tie-breaking as an acceptance condition; spending budget | A visible temporary highlight identifies the current suggestion | If no legal target exists, no arrow is suggested; repeated Hint use reflects the latest state |
| `DEPENDENCY-01` | An arrow declares one or more prerequisite arrows | Load/play the level and attempt the dependent arrow | The dependent arrow remains locked until every prerequisite is fully outside; a locked click does not move it and uses the failed-attempt cost of the current budget mode | Unlocking after only one of several prerequisites; unlocking when a prerequisite merely starts moving; a locked arrow moving | Locked status is visible and changes when the final prerequisite finishes | Multiple prerequisites use AND semantics and work regardless of their completion order |
| `DEPENDENCY-02` | Unfinished dependency relations exist | Observe the board before and after prerequisite exits | A locked arrow displays a lock badge; an available unfinished arrow that remains a direct prerequisite of another unfinished arrow displays a key badge; lock takes priority over key | Stale, missing, simultaneous key+lock, or prematurely updated badges | Key/lock state is visible on the relevant arrow and updates after full exit | Restart returns every badge to its initial authored state |
| `UI-01` | Game view is 1280 x 720 | Start any authored level | A centered dot-grid or square-grid board, colored arrows with clear head direction, current level, budget mode (`Moves` or `Hearts`), remaining budget, visible Hint, visible Restart, and visible Next Level appear together | Console-only status or a layout that hides a required play element | The player can find the board, status, and all three controls without opening debug tools | Reasonable layout/style variation is accepted |
| `UI-02` | The phase changes to win or loss | Complete `FLOW-03` or `FLOW-04` | `COMPLETED` is shown for win and `FAILED` for loss, never both together | Terminal text inconsistent with the actual outcome | The terminal label is readable and persistent until Restart | Restart clears terminal text and returns to active play |
| `UI-03` | Any click, motion completion, Hint, dependency update, Restart, win, or loss changes the game | Observe the next visible state | Board occupancy, arrow visibility/state, budget, badges, Hint, and terminal information agree with the actual current play state | HUD/badges/highlights reporting a different state from the board outcome | Each meaningful action has perceivable, state-consistent feedback | Repeated interactions and delayed motion do not reveal stale feedback from an earlier state |
| `VISUAL-01` | Any normal gameplay state is visible | Observe the full game view | The final assembly uses an original-inspired dark field, a centered dotted or restrained square grid, bright clean polyline arrows, a compact status area, and coordinated icon-based controls; proportions, layering, spacing, and color treatment form a coherent deliverable game screen | Placeholder/debug visuals, broken transparency, severe stretching/cropping, unreadable overlap, or a visually contradictory mixture of styles | The game reads as one intentionally assembled puzzle screen rather than disconnected test elements | Pixel-perfect matching and one unique layout are not required; reasonable equivalent composition is accepted |
| `RESTART-01` | The session is active, an arrow is moving, or the session is won/lost | Click visible Restart | Within one second, the current authored level returns to its fresh state: every arrow/cell, initial budget, active phase, dependency badge, Hint, and terminal display match a clean load | Old movement or delayed feedback altering the new run; duplicated listeners/actions; carrying terminal state or spent budget forward | The board immediately reads as a fresh playable level | One normal click still causes one action after repeated restarts |
| `REOPEN-01` | The game has been closed from any runtime state | Open the game again through the public launch instructions | A fresh, playable tutorial session begins with its authored arrows, initial budget, active phase, badges, Hint, Restart, and no terminal label | Resuming a stale partial run, opening into an unplayable/terminal state, or carrying spent budget and old motion forward | The reopened game presents the same understandable starting experience as a fresh launch | Runtime play progress is not preserved across close/reopen |
| `ASSET-01` | The supplied key and lock badge images are available | Present key/lock dependency states | The supplied key image represents key state and the supplied lock image represents locked state in normal gameplay | Swapping their meanings or leaving the badge states without visible art | The two states are visually distinguishable | Their exact placement/scale may vary while `DEPENDENCY-02` remains readable |
| `QUALITY-01` | The project is available for normal player use. | Start it, play the main flow, exit, and start it again through the public instructions. | The project starts, runs, exits, and starts again through the public operating instructions. | Import, launch, exit, or reopen failure cannot block the required player journey. | Each start presents a visible playable entry and coherent current state. | Repeated exit and start cycles remain usable. |
| `QUALITY-02` | The main player flow is available. | Use the documented normal player controls to pursue its outcomes. | The main flow uses normal player input and contains no answer button, cheat route, or shortcut that directly forces gameplay results. | An answer button, cheat entry, direct-result call, or non-player shortcut cannot replace the player journey. | Visible game state changes only as a consequence of normal player actions and rules. | Repeated normal-input attempts remain usable. |
| `QUALITY-03` | A required entry, label, or control is relevant to the current player state. | Locate, read, and operate it through the player-facing presentation. | Key entry points, labels, and controls are visible, findable, readable, and operable. | A required entry, label, or control cannot be hidden, unreadable, undiscoverable, or inoperable. | The relevant entry, label, or control is visibly identifiable and its response is understandable. | It remains usable in every required state where it applies. |
| `QUALITY-04` | A player action can change or reject game state. | Perform the action and observe the next stable state. | Player actions have perceivable feedback, and visible feedback agrees with the real game state. | Feedback cannot be absent, misleading, or inconsistent with the actual game state. | The player perceives state-consistent visual or audio feedback. | Repeated accepted and rejected actions do not expose stale feedback. |
| `QUALITY-05` | The player follows a required main-flow journey. | Continue through its required actions and transitions. | No severe error blocks the main player flow. | A severe import, runtime, rendering, input, or state error cannot block the journey. | The player-facing flow remains visible, responsive, and understandable. | Recovery paths defined by the task remain available after non-terminal mistakes. |
| `QUALITY-06` | The same clean initial conditions and player action sequence are available. | Repeat that sequence from a fresh state. | Repeating the same initial conditions produces substantially stable results. | Uncontrolled prior-run state or duplicate handling cannot materially change the result. | The repeated journey presents substantially stable visible states and outcomes. | Restart or reopen boundaries govern the intentionally reset or retained state. |

## 7. Success, failure, and staged flows

### 7.1 Success summary

| Requirement IDs | Before success | Success condition | After success | Feedback |
|---|---|---|---|---|
| `FLOW-02`, `FLOW-03`, `RULE-05` | The player removes arrows in a legal order | Every authored arrow is fully outside | Gameplay selections freeze; Restart stays available | `COMPLETED`, never `FAILED` |

### 7.2 Failure summary

| Requirement IDs | Failure condition | After failure | Feedback | Retry |
|---|---|---|---|---|
| `FLOW-04`, `RULE-03`, `RULE-04` | Budget reaches zero without a completed board | Gameplay selections freeze | `FAILED`, never `COMPLETED` | `RESTART-01` |
| `RULE-02` | A selected arrow's forward path is occupied | The arrow remains in place and the session continues unless the budget reaches zero | Temporary target-local failure feedback | The target is reusable after feedback recovery |
| `DEPENDENCY-01` | A dependent arrow is selected before all prerequisites finish | The arrow remains locked; current-mode failed-attempt cost applies | Lock badge and normal failed-attempt response | It becomes available after the final prerequisite fully exits |

### 7.3 Multi-stage dependency summary

| Stage | Stage requirement IDs | Stage summary | No-early-transition requirement IDs |
|---|---|---|---|
| Initial | `CONTENT-03`, `DEPENDENCY-02` | `key_a` is available/key-marked; both locks are locked | `DEPENDENCY-01` |
| Middle | `CONTENT-03`, `DEPENDENCY-01` | After `key_a` fully exits, `lock_b` becomes available/key-marked | `DEPENDENCY-01` keeps `lock_c` locked |
| Final | `CONTENT-03`, `FLOW-03` | After `lock_b` fully exits, `lock_c` becomes available and the chain can complete | `FLOW-03` prevents early success |

## 8. Interface and feedback summary

| Requirement IDs | Information/state | Appearance/update summary | Player distinction |
|---|---|---|---|
| `UI-01` | Board, arrows, level, mode, budget, Hint, Restart, Next Level | Present together during play | What can be selected and what resource remains |
| `RULE-02`, `HINT-01` | Blocked feedback and Hint highlight | Temporary and bounded | Failed choice versus suggested legal choice |
| `DEPENDENCY-02`, `ASSET-01` | Key and lock badges | Updates after full prerequisite exit | Available prerequisite versus locked dependent |
| `UI-02`, `UI-03` | `COMPLETED` / `FAILED` and synchronized state | Updates with the real phase | Win versus loss, never both |
| `VISUAL-01` | Whole-screen visual assembly | Present throughout gameplay | Coherent background, board, arrows, status, controls, spacing, layering, and finish |

## 9. Restart, reopen, and progress summary

| Scenario | Requirement IDs | Reset summary | Preserved summary | Final state |
|---|---|---|---|---|
| Restart current level | `RESTART-01` | Runtime arrows, budget, phase, badges, Hint, terminal state, and delayed activity | The current authored level definition | Fresh active level within one second |
| Switch authored level | `NAV-01` | Current arrows, budget, phase, badges, Hint, terminal state, and delayed activity | The next authored level in the fixed public cycle | Fresh active next level within one second |
| Close and reopen the game | `REOPEN-01`, `QUALITY-01` | Runtime play progress | The authored starting experience | Fresh tutorial session |

## 10. Existing functionality

This is a gameplay reconstruction from a gameplay-empty Starter, so there is no previous game loop to preserve. Starter/tool integrity is covered by the separate public operating and workspace documents rather than by an additional gameplay requirement.

## 11. Assets and content summary

| Requirement IDs | Asset/content | Acceptance role | In-game use | Equivalent replacement |
|---|---|---|---|---|
| `ASSET-01` | Supplied key badge image listed in `ASSET_MANIFEST.json` | Hard requirement | Visible key badge | No semantic replacement; layout/scale remain flexible |
| `ASSET-01` | Supplied lock badge image listed in `ASSET_MANIFEST.json` | Hard requirement | Visible lock badge | No semantic replacement; layout/scale remain flexible |
| `UI-01` (informational) | Optional supplied starter art collection listed in `ASSET_MANIFEST.json` | Optional supplied art | Board, arrow, HUD, Hint, Restart presentation | Equivalent readable presentation is allowed |
| `VISUAL-01` (informational) | The complete supplied visual set | Visual direction | A coordinated original-inspired game screen | Equivalent composition is allowed; broken/placeholder assembly is not |
| `CONTENT-03` (informational) | Supplied dependency-chain data-shape example listed in `ASSET_MANIFEST.json` | Data-shape example | Authoring reference only | Runtime use is outside scope |

License and distribution details are in `legal/` and `ASSET_MANIFEST.json`.

## 12. Implementation boundary

Section 6 is the complete source of game-specific requirements. The target is a saved, normally playable Arrow Escape game whose visible controls, board state, feedback, success, failure, Restart and reopen behavior agree with those numbered goals. Any read-only observation exposed for automation mirrors the same player-visible state and does not perform gameplay.

`TOOLCHAIN.md` describes the public Unity delivery/input compatibility profile used to operate the project; it is not a gameplay solution and adds no hidden gameplay requirement. Internal class names, object hierarchy, algorithms and data organization are not acceptance conditions.

## 13. Requirement ID index

This section is navigation only. It introduces no new condition and summarizes only the
player goals already defined in Section 6.

| Goal area | Section 6 requirement IDs | Player-goal summary |
|---|---|---|
| Flow | `FLOW-01`, `FLOW-02`, `FLOW-03`, `FLOW-04` | Entry, active play, success progression, and stable terminal states. |
| Content | `CONTENT-01`, `CONTENT-02`, `CONTENT-03`, `CONTENT-04`, `CONTENT-05` | Tutorial, mode examples, dependency-chain level, required labels, and authored level set. |
| Input and navigation | `INPUT-01`, `INPUT-02`, `NAV-01` | Normal pointer attempts, complete click semantics, and level navigation. |
| Rules and Hint | `RULE-01`, `RULE-02`, `RULE-03`, `RULE-04`, `RULE-05`, `HINT-01` | Legal exits, blocked and locked attempts, budgets, completion, and temporary suggestions. |
| Dependencies | `DEPENDENCY-01`, `DEPENDENCY-02` | Ordered prerequisite behavior and multi-key dependency behavior. |
| Interface and presentation | `UI-01`, `UI-02`, `UI-03`, `VISUAL-01`, `ASSET-01` | Visible state, controls, feedback, composition, and supplied asset roles. |
| Lifecycle | `RESTART-01`, `REOPEN-01` | Clean restart and clean distinct-process reopen. |
| General playability | `QUALITY-01`, `QUALITY-02`, `QUALITY-03`, `QUALITY-04`, `QUALITY-05`, `QUALITY-06` | Launch, visibility, input, state coherence, feedback, and recovery baseline. |
