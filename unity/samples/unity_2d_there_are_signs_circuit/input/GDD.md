# There Are Signs - Sign Circuit

Task ID: `unity.there_are_signs.sign_circuit.v2`

Public Input revision: `v2.5-tool-guide-v5-20260825`  
GDD revision: `v2.4-player-goals-only-20260825`

Section 6 is the sole definition of acceptance conditions. Every other section is a reader-oriented summary that cites the corresponding requirement IDs.

## 1. One-sentence task

The player enters a new Sign Circuit challenge from the existing menu, configures three road signs in the STOP, UP, RIGHT sequence, passes their checkpoints, crosses the opened gate, and reaches a clearly presented success state before time expires (`CORE-01` to `CORE-04`).

## 2. Scope

### 2.1 Included outcomes

| Requirement ID | Summary |
|---|---|
| `CORE-01` to `CORE-04` | A complete menu-to-challenge-to-finish journey. |
| `CONTROL-01` to `CONTROL-06` | Keyboard movement, jumping, sign interaction, pause, and two restart routes. |
| `RULE-01` to `RULE-10` | Proximity, sign state, checkpoint order, penalty, timer, gate, success, and failure behavior. |
| `UI-01` to `UI-03` | Readable HUD, interaction feedback, terminal panels, and restart presentation. |
| `LIFECYCLE-01` to `LIFECYCLE-04` | Pause/resume, clean restart, fresh-process persistence, and best-time comparison. |
| `LEGACY-01` to `LEGACY-02` | Existing menu and Level1+2 behavior remains usable. |
| `VISUAL-01` | A coherent hand-drawn presentation assembled from the supplied game art. |
| `QUALITY-01` to `QUALITY-06` | Shared playability and stability baseline. |

### 2.2 Not included

| Related requirement ID | Outside this task |
|---|---|
| None | New combat, enemies, dialogue, extra levels, mobile builds, networking, online leaderboards, procedural generation, and a pixel-perfect remake. |
| `VISUAL-01` | Replacement of the supplied game's entire art direction or creation of a separate visual identity. |

## 3. Starting state

| Item | Starting state | Acceptance reference |
|---|---|---|
| Available entry | The supplied project contains its existing main menu and playable levels. | `CORE-01`, `LEGACY-01` |
| Player and route content | A 2D player, three reusable signs, a long challenge corridor shell, checkpoint locations, a gate location, and a finish location are supplied. | `CORE-02` to `CORE-04` |
| Initial values | The completed challenge begins as a clean timed run. | `CORE-02`, `RULE-06`, `RULE-08` |
| Existing interface | The original menu and its existing choices are present. | `LEGACY-01` |
| Existing functionality | The supplied Level1+2 level already supports horizontal movement and jumping. | `LEGACY-02` |
| Incomplete challenge work | The starter does not yet provide the completed circuit rules, challenge HUD, terminal flow, restart behavior, persistent record, menu entry, or final visual assembly. | `CORE-01` to `VISUAL-01` |

## 4. Player goal and complete flow

### 4.1 Player goal

The player reads the route, changes each nearby sign to its target state, validates the three checkpoints in order, and reaches the finish with time remaining (`CORE-03`, `CORE-04`, `RULE-02` to `RULE-10`).

### 4.2 Complete player flow

```text
Open the existing menu
-> [CORE-01] activate SIGN CIRCUIT
-> [CORE-02] begin at 30.0 seconds and 0/3 with a closed gate
-> [CORE-03, RULE-01..RULE-05] configure STOP, UP, RIGHT and pass each checkpoint
-> [CORE-04, RULE-08..RULE-09] cross the opened gate and enter the finish
-> [RULE-07, UI-03] see success, or [RULE-10, UI-03] see timeout failure
-> [LIFECYCLE-02] restart, or [LIFECYCLE-03] reopen later with the saved best time
```

### 4.3 Main loop

```text
[CONTROL-01..CONTROL-03] move to and interact with the next sign
-> [RULE-02] establish its visible target state
-> [RULE-03..RULE-05] enter the next checkpoint and receive synchronized feedback
-> [UI-01] read progress and remaining time
-> repeat until 3/3, success, failure, pause, or restart
```

## 5. Player controls

| Requirement ID | Player action | Context | Response summary |
|---|---|---|---|
| `CONTROL-01` | A/D or Left/Right arrows | Playable scenes | Horizontal movement. |
| `CONTROL-02` | Space; the existing W route may also remain available | Grounded movement | Jump. |
| `CONTROL-03`, `RULE-01` | E; the existing alternate interaction may also remain available | Near a usable sign | One sign interaction, with no remote effect. |
| `CONTROL-04`, `LIFECYCLE-01` | Escape | Active Sign Circuit run | Pause or resume the same run. |
| `CONTROL-05`, `LIFECYCLE-02` | R | Sign Circuit | Restart the run. |
| `CONTROL-06`, `LIFECYCLE-02` | Left-click the visible Restart control | Pause or terminal presentation | Restart through normal UI interaction. |

## 6. Numbered requirements: sole acceptance source

### 6.1 Requirement boundaries

Every game-specific obligation, prohibition, visible result, and lifecycle boundary used for acceptance is defined by one row in Section 6.2. Other sections only summarize these requirement IDs.

### 6.2 Task-specific requirement table

| Requirement ID | Preconditions | Player action or trigger | Required result | Forbidden result | Player-visible feedback | Failure, repetition, restart, or other boundary |
|---|---|---|---|---|---|---|
| `CORE-01` | The existing menu is open. | The player activates a visible entry labelled `SIGN CIRCUIT` through the normal menu UI. | The Sign Circuit challenge shall load into the clean running state defined by `CORE-02`. | Activation shall not skip directly to a checkpoint, open gate, or terminal result. | The entry shall be visible, readable, and usable as part of the menu. | Re-entering from the menu shall start a clean run while retaining only the saved best time. |
| `CORE-02` | A new run or restart begins. | The challenge becomes active. | The player shall start near the route origin with `30.0` seconds, progress `0/3`, all three signs in their authored initial states, no accepted checkpoints, a visibly closed blocking gate, normal time scale, active player input, and hidden pause/success/failure panels. | Prior run progress, penalties, terminal state, player position, or accepted-checkpoint feedback shall not carry into the clean run. | The initial HUD and route state shall agree with these values. | A saved best time, if one exists, shall remain visible and shall not be cleared by a new run. |
| `CONTROL-01` | A playable challenge or preserved legacy level is active and not paused or terminal. | The player holds A/D or Left/Right arrows. | The player character shall move horizontally in the corresponding direction through normal player input. | Opposite-direction or no movement caused by the requested key shall not be treated as correct. | The character's motion shall be visible to the player. | Releasing the key shall end the commanded movement without causing extra movement responses. |
| `CONTROL-02` | The player can jump and the game is not paused or terminal. | The player presses Space. | The player character shall perform a visible jump through normal player input. | A direct gameplay-result shortcut shall not substitute for the jump input. | The character shall visibly leave and return toward the ground. | After repeated restarts or level changes, one key press shall still produce at most one jump. |
| `CONTROL-03` | The run is active and the player is inside a valid sign interaction zone. | The player presses E once. | At most one interaction transition shall occur on the nearby sign. | One press shall not toggle multiple signs or cause multiple state transitions. | The affected sign shall visibly change state. | After repeated restarts or reloads, one press shall still produce at most one visible sign change. |
| `CONTROL-04` | A non-terminal run is active. | The player presses Escape. | Escape shall enter pause; a later Escape shall resume the same run as defined by `LIFECYCLE-01`. | Escape shall not erase progress, reset the run, or change a terminal result. | Pause entry and exit shall be visibly distinguishable. | Repeated alternating presses shall remain stable. |
| `CONTROL-05` | The Sign Circuit challenge is active. | The player presses R once. | The run shall restart according to `LIFECYCLE-02`. | One key press shall not create multiple overlapping resets. | The clean initial state shall be visible within one second. | The route shall remain reusable after repeated keyboard restarts. |
| `CONTROL-06` | A visible Restart control is available in pause, success, or failure presentation. | The player left-clicks the control through normal UI interaction. | The run shall restart according to `LIFECYCLE-02`. | Restart shall not occur unless the player completes a valid click on the visible control. | The control shall be visible, readable, unobscured, and clickable. | Pressing outside then releasing over it, or pressing it then releasing outside, shall not activate it; a complete press-and-release on the target shall. The UI route shall remain usable while gameplay time is frozen and after repeated restarts. |
| `RULE-01` | The player is outside every sign interaction zone, including at spawn. | The player presses E. | All sign states, progress, gate state, timer terminal state, and completed state shall remain unchanged. | Remote interaction shall not flip a sign, advance progress, open the gate, or complete the run. | A sign interaction affordance shall appear only while interaction is valid. | Moving into a valid zone afterward shall allow normal interaction. |
| `CORE-03` | A clean run is active. | The player uses normal movement and nearby sign interaction to complete the three stages. | A valid full route shall allow the player to establish the STOP, UP, RIGHT target states and advance through the corresponding checkpoints from `0/3` to `3/3`. | The route shall not require an answer button, direct result call, teleport, or non-player shortcut. | Each stage shall visibly communicate sign state, checkpoint result, and updated progress. | The same clean initial conditions shall support another valid completion after restart. |
| `RULE-02` | The run is active and the player reaches each sign. | The player interacts with the signs. | The three accepted target states shall be: STOP visibly flipped or disabled into its passable state, UP visibly pointing upward, and RIGHT visibly pointing rightward. | An ambiguous or visibly incorrect state shall not count as the matching target. | Each target state shall be distinguishable from its authored initial state. | Changing a not-yet-accepted sign away from its target shall make its checkpoint invalid until corrected. |
| `RULE-03` | The player enters a checkpoint. | The checkpoint overlap begins. | A checkpoint shall be accepted only when it is the next member of `STOP -> UP -> RIGHT` and its corresponding sign is currently in the target state from `RULE-02`. | Wrong order or wrong sign state shall not advance progress. | Acceptance or rejection shall produce synchronized feedback described by `UI-02`. | After a rejected entry, leaving and correcting the route shall allow a later valid attempt. |
| `RULE-04` | A checkpoint satisfies `RULE-03` and has not already been accepted in this run. | The player crosses it. | Progress shall advance exactly once, in order, from `0/3` to `1/3`, then `2/3`, then `3/3`; that checkpoint shall retain visible positive completion feedback. | Remaining inside, re-entering, holding input, or retoggling an accepted sign shall not add progress again. | The checkpoint and HUD shall show the accepted result. | Restart shall clear all accepted-checkpoint feedback and return to `0/3`. |
| `RULE-05` | A checkpoint fails the order or sign-state condition in `RULE-03`. | One continuous checkpoint overlap begins. | Progress shall stay unchanged, visible negative feedback shall appear briefly, and exactly `3.0` seconds shall be deducted from remaining time. | One continuous overlap shall not create repeated penalties or progress. | The penalty and rejection shall be noticeable and consistent with the timer. | After the player leaves, a later invalid re-entry may create one new penalty; a later valid entry may be accepted. |
| `CORE-04` | Progress has reached `3/3`. | The player moves through the former gate position and enters the finish area. | The gate shall be visibly open and non-blocking, and physical entry into the finish shall produce success. | Gate opening shall not teleport the player or award success before finish entry. | The open route and success presentation shall be clear. | Finish entry before the conditions in `RULE-08` and `RULE-09` shall remain non-terminal. |
| `RULE-06` | A clean run begins. | Time advances while the run is actively running. | Remaining time shall start at `30.0` seconds and decrease only while actively running, stopping at zero or at a terminal result. | Pause duration, a terminal state, or time below zero shall not reduce the displayed remaining time. | The current remaining time shall stay visible and synchronized. | Restart shall restore `30.0` seconds; penalties from `RULE-05` shall apply deterministically. |
| `RULE-07` | The run reaches success before timeout. | All success conditions in `CORE-04` occur. | Gameplay and timing shall freeze, the final elapsed time shall be shown, and the best time shall update only when this elapsed time is faster than the saved record. | Success and failure shall not be active together, and post-success movement or interaction shall not change the result. | A clear success panel and final time shall be visible with Restart available. | Restart shall preserve the saved best time and restore a clean playable run. |
| `RULE-08` | Progress is below `3/3`, or the gate is still closed. | The player reaches or overlaps the finish area. | The run shall remain non-terminal. | Premature finish overlap shall not award success or update best time. | Existing progress, timer, and route feedback shall remain truthful. | A later valid `3/3` route and physical finish entry shall still be able to succeed. |
| `RULE-09` | The run starts below `3/3`, then later reaches `3/3`. | Initial state and final checkpoint acceptance occur. | Before `3/3`, the visibly closed gate shall physically block the player from crossing the route by ordinary movement; at `3/3`, it shall visibly open and allow ordinary movement through the former gate position. | The gate shall not begin passable, open early, remain blocking after `3/3`, or teleport the player. | Closed and open states shall be visually distinguishable. | Restart shall restore the closed blocking state. |
| `RULE-10` | The run has not already succeeded. | Remaining time reaches zero. | A failure state shall appear, gameplay and timing shall freeze at zero, and Restart shall remain usable. | Failure shall not also show success, update best time, or permit further progress. | A clear failure panel and retry path shall be visible. | Restart shall return to `CORE-02`; timeout after a later run shall behave the same way. |
| `UI-01` | The challenge is visible. | The run starts and its state changes. | A readable HUD shall continuously show progress from `0/3` through `3/3`, remaining time, current status, and best time; before any record, best time shall show a clear no-record state such as `BEST --`, and after success it shall show a stable numeric value in seconds. | HUD values shall not contradict the actual run state or disappear during ordinary running play. | Labels and values shall be legible against the game view. | Restart, pause/resume, success, failure, and fresh reopen shall update or preserve each field according to the corresponding numbered requirement. |
| `UI-02` | The player approaches, interacts with, or crosses route elements. | Proximity, valid interaction, accepted checkpoint, invalid checkpoint, and gate-state changes occur. | The game shall provide distinguishable interaction affordance, positive checkpoint feedback, negative checkpoint feedback, visible sign orientation/state, and closed/open gate feedback. | Feedback shall not claim acceptance, progress, or an open gate when the underlying state is false. | Each response shall be visible during normal play. | Persistent positive checkpoint feedback shall last until restart; short negative feedback may clear after communicating the rejection. |
| `UI-03` | Pause, success, or failure is active. | The corresponding state begins. | A coherent panel shall identify the state, and a readable usable Restart control shall remain available; success and failure presentation shall be mutually exclusive. | Panels shall not obscure their own state text or click target, overlap into an unreadable result, or leave contradictory terminal messages visible. | Pause, success, failure, final time where applicable, and Restart shall be easy to distinguish. | Returning to a clean run shall hide all three panels. |
| `LIFECYCLE-01` | A run is actively running and non-terminal. | The player presses Escape, then later presses Escape again. | Pause shall show its panel and freeze countdown, horizontal movement, jumping, sign interaction, and checkpoint progress while keeping UI input active; resume shall continue the same time and progress. | Pause shall not reset the run, consume countdown time, or disable the clickable Restart route. | Pause state and resumed running state shall be clear. | Repeated pause/resume cycles shall not duplicate input responses or alter the saved best time. |
| `LIFECYCLE-02` | The Sign Circuit challenge is running, paused, successful, or failed. | `CONTROL-05` or `CONTROL-06` triggers restart. | Within one second, the player shall return near the original start with `30.0` seconds, `0/3`, authored initial sign states, cleared checkpoint feedback, a closed blocking gate, hidden pause/success/failure panels, normal timing, usable controls, and the saved best time preserved. | Stale movement, ongoing effects, penalties, terminal state, or duplicate actions from the previous run shall not survive. | The clean initial HUD and route shall be visible. | Both restart routes shall remain reliable across repeated attempts. |
| `LIFECYCLE-03` | A valid success has stored a best time. | The player fully closes the game, starts it again, reopens the challenge, and begins a new run. | The same saved best-time value shall be visible after the restart. | Closing and restarting the game shall not silently clear or replace the record. | The best-time HUD shall show the recovered numeric seconds value. | Ordinary run progress and terminal state shall not persist after the restart; only the record is retained. |
| `LIFECYCLE-04` | A faster best time already exists. | The player pauses during a run or later completes a slower run. | Pause duration shall not count toward elapsed run time, and the slower completion shall leave the faster record unchanged. | A slower value or paused wall-clock duration shall not overwrite or inflate the record. | The best-time display shall remain the faster saved value. | A later genuinely faster completion may replace it. |
| `LEGACY-01` | The supplied main menu is opened before or after the extension. | The player uses the menu. | Existing menu functions, level entries, and Continue behavior shall remain available alongside the new `SIGN CIRCUIT` entry. Selecting the supplied `Level1+2` entry shall enter that level, and after returning to the menu, Continue shall return to the most recently selected level. | The extension shall not remove, replace, block, or insert an extra confirmation step into those original menu routes. | The new entry shall read as an integrated menu choice. | Menu use after returning from or reopening the project shall remain functional. |
| `LEGACY-02` | The supplied Level1+2 level is opened. | The player uses its existing horizontal movement and jump inputs. | The level shall still open, and the original player shall still move left/right and jump. | The extension shall not break the existing level controls. | Movement and jumping shall remain visible in the original level. | Opening the challenge before or after Level1+2 shall not cause one player action to produce duplicate responses. |
| `VISUAL-01` | Menu, initial gameplay, and core route interaction are viewed at a normal 16:9 gameplay framing. | The player follows the route from spawn through finish. | The visible result shall deliberately assemble the supplied hand-drawn street/school game art into a coherent environment; player, signs, checkpoints, gate, finish, menu entry, HUD, and state panels shall remain clearly layered, proportioned, readable, consistently spaced, and stylistically integrated. | The player-facing frame shall not present a uniform empty clear color, isolated debug objects, placeholder art, debug overlays or labels, unintended stretching/cropping, or UI that hides required gameplay information. | The menu, initial route, and sign/checkpoint interaction shall each read as completed game states rather than unfinished prototypes or debug scenes. | Equivalent compositions, layouts, palettes, minor animation, and camera timing are allowed when the same visual intent and readability are preserved. |
| `QUALITY-01` | The saved project entry is available for normal player use. | The player starts the game. | A visible playable entry and coherent current state shall appear without a severe blocking error. | Import, launch, or runtime failure cannot block the player-facing entry. | The current menu or gameplay state shall be visible and understandable. | Restart and persistence behavior follow their numbered lifecycle requirements. |
| `QUALITY-02` | The main player flow is available. | The player uses the documented controls to pursue its outcomes. | The main flow shall use normal player input and shall not depend on an answer button, cheat entry, or direct gameplay-result shortcut. | An answer button, cheat entry, direct-result call, or non-player shortcut cannot replace player actions. | Visible game state changes only as a consequence of player actions and rules. | Required controls remain usable after the recovery routes defined by this task. |
| `QUALITY-03` | A required entry, label, or control is relevant to the current player state. | Locate, read, and operate it through the player-facing presentation. | Key entries, text, and controls shall be visible, discoverable, readable, and operable. | A required entry, label, or control cannot be hidden, unreadable, undiscoverable, or inoperable. | The relevant entry, label, or control is visibly identifiable and its response is understandable. | It remains usable in every required state where it applies. |
| `QUALITY-04` | A player action can change or reject game state. | Perform the action and observe the next stable state. | Player actions shall produce noticeable feedback, and interface feedback shall agree with actual game state. | Feedback cannot be absent, misleading, or inconsistent with the actual game state. | The player perceives state-consistent visual or audio feedback. | Repeated accepted and rejected actions do not expose stale feedback. |
| `QUALITY-05` | A required player-facing transition is available. | The game processes that transition. | No severe error shall block the required result. | A severe import, runtime, rendering, input, or state error cannot replace or block the result. | The current player-facing state remains visible, responsive, and understandable. | Recovery paths defined by the task remain available after non-terminal mistakes. |
| `QUALITY-06` | Equivalent clean game state and player action conditions are present. | The same player action occurs. | Substantially consistent player-visible state changes shall result. | Uncontrolled prior-state leakage or duplicate handling cannot materially change the result. | The resulting visible state remains consistent with the game rules. | Restart and persistence boundaries govern intentionally reset or retained state. |

## 7. Success, failure, and multi-stage flow

### 7.1 Success

| Requirement IDs | Steps summary | Success condition summary | Result summary | Feedback summary |
|---|---|---|---|---|
| `CORE-03`, `CORE-04`, `RULE-02` to `RULE-09` | Complete the ordered circuit, pass the opened gate, enter the finish. | Physical finish entry after valid `3/3`. | Frozen successful run and eligible best-time update. | Open gate, success panel, final time, updated HUD. |

### 7.2 Failure

| Requirement IDs | Failure condition summary | Result summary | Feedback summary | Retry summary |
|---|---|---|---|---|
| `RULE-06`, `RULE-10`, `UI-03`, `LIFECYCLE-02` | Remaining time reaches zero before success. | Frozen failed run, no record update. | Failure panel at zero with Restart. | R or left-click Restart returns to the clean run. |

### 7.3 Multi-stage flow

| Stage | Requirement IDs | Stage summary | No-early-result reference |
|---|---|---|---|
| STOP | `RULE-02` to `RULE-04` | Set STOP to its target and validate the first checkpoint. | `RULE-03`, `RULE-08`, `RULE-09` |
| UP | `RULE-02` to `RULE-04` | Set UP upward and validate the second checkpoint after STOP. | `RULE-03`, `RULE-08`, `RULE-09` |
| RIGHT | `RULE-02` to `RULE-04` | Set RIGHT rightward and validate the third checkpoint after UP. | `RULE-03`, `RULE-08` |
| Gate and finish | `CORE-04`, `RULE-07` to `RULE-09` | Cross the opened route and physically enter the finish. | `RULE-08` |

## 8. Interface and feedback

| Requirement IDs | Information or state | Appearance/update summary | Distinction the player receives |
|---|---|---|---|
| `UI-01` | Progress, timer, status, best time | Visible from run start and synchronized with state changes. | Current run versus saved record. |
| `UI-02` | Interaction validity, sign state, checkpoint result, gate state | Changes near signs and at route events. | Valid versus remote interaction; accepted versus rejected checkpoint; closed versus open gate. |
| `UI-03` | Pause, success, failure, final time, Restart | Shown only for the corresponding state. | Running versus paused versus one terminal result. |
| `VISUAL-01` | Environment and presentation | Authored across menu, initial gameplay, and core interaction. | Integrated game content versus empty/debug presentation. |

## 9. Restart, reopen, and save

| Scenario | Requirement IDs | Reset summary | Preserve summary | Final state summary |
|---|---|---|---|---|
| Pause and resume | `LIFECYCLE-01` | No run reset. | Time and progress. | Same run continues. |
| Restart current run | `LIFECYCLE-02` | Player, timer, progress, signs, checkpoints, gate, panels, input state. | Saved best time. | Clean running state within one second. |
| Close and reopen | `LIFECYCLE-03` | Current run and terminal state. | Saved best time. | Fresh run with recovered record. |
| Complete a slower run | `LIFECYCLE-04` | New run state follows normal lifecycle. | Faster record. | Best display remains unchanged. |

## 10. Preserved existing features

| Requirement ID | Existing feature | Player use | Preservation summary |
|---|---|---|---|
| `LEGACY-01` | Original main-menu routes | Activate existing entries and Continue. | Original choices remain available with SIGN CIRCUIT. |
| `LEGACY-02` | Level1+2 movement and jump | Load the level and use normal controls. | The original level remains playable. |

## 11. Art and content

| Requirement ID | Art/content | Hard requirement | Use in the game | Equivalent alternative |
|---|---|---|---|---|
| `VISUAL-01` | Supplied hand-drawn street, school, character, sign, and compatible interface art | Yes | Assemble the challenge route and integrate its menu/HUD/state presentation with the source game's visual language. | Equivalent arrangement and layout are allowed; an unrelated or empty debug presentation is not. |

Asset locations and licenses are documented in the separate public asset manifest and license material.

## 12. Implementation boundary

Section 6 is the complete source of every game-specific acceptance condition. The target is a saved, normally playable extension whose player journey and visible outcomes match those numbered requirements.

`TOOLCHAIN.md` only describes the supported way to open and operate the supplied game. It does not add gameplay goals or acceptance conditions.

## 13. Requirement ID index

This section is navigation only. It introduces no new condition and summarizes only the
player goals already defined in Section 6.

| Goal area | Section 6 requirement IDs | Player-goal summary |
|---|---|---|
| Core flow | `CORE-01`, `CORE-02`, `CORE-03`, `CORE-04` | Menu entry, active circuit run, success, and failure. |
| Controls | `CONTROL-01`, `CONTROL-02`, `CONTROL-03`, `CONTROL-04`, `CONTROL-05`, `CONTROL-06` | Normal movement, jump, configuration, pause, restart, and menu input. |
| Circuit rules | `RULE-01`, `RULE-02`, `RULE-03`, `RULE-04`, `RULE-05`, `RULE-06`, `RULE-07`, `RULE-08`, `RULE-09`, `RULE-10` | Proximity, ordered signs, checkpoint outcomes, timing, gate, and terminal behavior. |
| Interface | `UI-01`, `UI-02`, `UI-03` | Visible synchronized HUD, panels, and feedback. |
| Lifecycle | `LIFECYCLE-01`, `LIFECYCLE-02`, `LIFECYCLE-03`, `LIFECYCLE-04` | Pause continuity, restart routes, distinct-process reopen, and best-time continuity. |
| Existing-game continuity | `LEGACY-01`, `LEGACY-02`, `VISUAL-01` | Original menu and level continuity plus coherent presentation. |
| General playability | `QUALITY-01`, `QUALITY-02`, `QUALITY-03`, `QUALITY-04`, `QUALITY-05`, `QUALITY-06` | Launch, visibility, input, state coherence, feedback, and recovery baseline. |
