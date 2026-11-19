# Dungeon Duel 3D — Public Game Design Document

Task ID: `unity.dungeon_duel_3d.v2`

This public GDD follows `docs/GAME_DESIGN_TEMPLATE.md`. Every acceptance-changing
obligation and prohibition is defined only by a numbered row in Section 6. Other
sections are summaries that cite those IDs. Engine commands and the public read-only
submission boundary are documented separately in `TOOLCHAIN.md`.

## 1. One-sentence task

Create a complete single-player 3D dungeon encounter in which the player moves a Tank,
defeats two Imps before a gated Boss, reaches visible Victory or enemy-owned Defeat,
and can return to a clean encounter through Restart or full close/reopen (`FLOW-01`–
`FLOW-03`, `RESTART-01`–`RESTART-02`, `REOPEN-01`).

## 2. Scope

### 2.1 In-scope features (ID summary only)

| Requirement IDs | One-sentence summary |
|---|---|
| `FLOW-01`–`FLOW-03`, `TERMINAL-01` | Complete clean start, success, failure, and frozen terminal flow. |
| `INPUT-01`, `NAV-01`, `CAMERA-01` | Reusable normal input, floor navigation, and a readable tracking camera. |
| `COMBAT-01`–`COMBAT-03`, `TUNING-01` | Player selection/approach/attacks, enemy threat, stable death, and public tuning. |
| `DASH-01`, `GATE-01`–`GATE-02` | Dash cooldown and the two-Imp prerequisite before gate/Boss activation. |
| `UI-01`–`UI-02`, `AUDIO-01`, `VISUAL-01`, `ASSET-01` | Runtime feedback and supplied fantasy Boss Room presentation. |
| `RESTART-01`–`RESTART-02`, `REOPEN-01` | Keyboard/UI Restart and a genuine fresh new-process reopen. |
| `QUALITY-01`–`QUALITY-06` | Shared objective playability and repeatability baselines. |

### 2.2 Not included

| Related requirement IDs | Content outside this task |
|---|---|
| None | Menus, multiplayer/networking, inventory, character selection, persistent progress, procedural levels, save slots, and extra enemy types. |

## 3. Starting state

| Item | Starting state | Requirement IDs when acceptance-relevant |
|---|---|---|
| Supplied authoring entry | A saved art-only dungeon Scene and Build Settings entry are supplied. | `QUALITY-01`, `ASSET-01` |
| Supplied content | Arena, Tank/Imp/Boss/gate art, materials, animation/VFX, and audio are available. | `VISUAL-01`, `ASSET-01` |
| Already completed gameplay | None of the described combat game is implemented in the public starting project. | `FLOW-01`–`REOPEN-01` |
| Target runtime start after implementation | Healthy Player, two living Imps, dormant Boss, closed blocking gate, ready Dash, battle audio, gameplay camera, and neutral HUD. | `FLOW-01`, `TUNING-01`, `UI-01`, `AUDIO-01` |
| Persistent progress | The task has no persistent gameplay progress. | `REOPEN-01` |

## 4. Player goal and complete flow

### 4.1 Player goal

Defeat both Imps, pass the opened gate, and defeat the Boss before enemy attacks reduce
the Tank to zero (`GATE-01`–`GATE-02`, `FLOW-02`–`FLOW-03`).

### 4.2 Complete player flow

```text
enter the saved game entry
→ [FLOW-01] see the clean encounter
→ [NAV-01] left-click reachable floor to move
→ [COMBAT-01] right-click a living Imp to select, approach, and attack
→ [GATE-01] first Imp dies while gate stays blocking and Boss stays dormant
→ [GATE-02] final Imp dies; gate opens and Boss activates
→ [DASH-01, COMBAT-01] move, Dash, and fight the Boss
→ [FLOW-02, TERMINAL-01] reach stable Victory and frozen play
→ [RESTART-02] click visible Restart and play again
```

Failure/lifecycle branch summary:

```text
[FLOW-01] clean encounter
→ [COMBAT-02] live enemy attacks the Player
→ [FLOW-03, TERMINAL-01] stable Defeat and frozen play
→ [RESTART-01] press R for a clean encounter
→ [REOPEN-01] fully close and start a new process with no retained progress
```

### 4.3 Main loop

```text
[INPUT-01, NAV-01, COMBAT-01, DASH-01] choose and perform a player action
→ [COMBAT-02, COMBAT-03, GATE-01, GATE-02] encounter state changes
→ [UI-01, UI-02, AUDIO-01] player reads health, progress, cooldown, and feedback
→ repeat until [FLOW-02] Victory or [FLOW-03] Defeat
```

## 5. Player actions

| Requirement IDs | Player action | When used | Game-response summary |
|---|---|---|---|
| `INPUT-01`, `NAV-01` | Full left mouse click on visible reachable floor | Active play | Set or redirect the movement destination through normal input. |
| `INPUT-01`, `COMBAT-01` | Full right mouse click on a visible living active enemy | Active play | Select the enemy, approach when needed, and attack in range/off cooldown. |
| `INPUT-01`, `DASH-01` | Point at reachable ground and tap keyboard `2` | Active play with Dash ready | Dash toward pointer/facing and begin cooldown. |
| `INPUT-01`, `RESTART-01` | Tap keyboard `R` | Active, Victory, or Defeat | Restore the complete clean encounter. |
| `INPUT-01`, `RESTART-02` | Full left-click on the visible terminal Restart control | Victory or Defeat | Consume the UI click and restore the complete clean encounter. |
## 6. Numbered requirements: sole acceptance source

### 6.1 Requirement boundaries

Every game-specific obligation, prohibition, visible result, and lifecycle boundary used for acceptance is defined by one row in Section 6.2. Other sections only summarize these requirement IDs.

### 6.2 Task-specific requirement table

| Requirement ID | Preconditions | Player action or trigger | Required result | Forbidden result | Player-visible feedback | Failure, repetition, restart, or other boundary |
|---|---|---|---|---|---|---|
| `FLOW-01` | The saved default entry finishes loading. | Start Play, complete Restart, or launch a new process. | One healthy Player, exactly two living Imps, one living dormant Boss, a closed blocking gate, ready Dash, active battle audio, active gameplay, camera, and neutral HUD are present. | No missing actor, open gate, active Boss, spent Dash, Victory, or Defeat. | Arena, actors, gate stage, HUD, and active encounter are understandable. | Repeated fresh starts reproduce these invariants. |
| `INPUT-01` | A summarized player action is available. | Complete one normal pointer click or keyboard tap. | One full click/tap creates at most one matching player intent. A visible UI click is consumed by UI only. | No duplicate intent, world action from a UI click, answer button, cheat, direct-result route, or direct gameplay-method input. | The clicked control/actor, movement, attack, Dash, or Restart response is visible. | An action may commit on press or release, but never twice; controls remain reusable after Restart. |
| `NAV-01` | Player is alive in active play; a visible reachable floor point exists. | Left-click floor target A, then a separated target B. | Player travels a meaningful distance toward each latest reachable target and settles nearby. | No UI-click movement, teleport-only travel, blocked-space traversal, or ignored redirect. | Locomotion and changing world position are visible. | Navigation remains reusable after combat and Restart. |
| `CAMERA-01` | `NAV-01` moves between both targets. | Observe the journey. | An active 3D gameplay camera keeps the living Player visibly framed at both targets with readable nearby space. | No blank view or loss of the Player during the journey. | Player, arena, gate, and nearby threats stay legible. | Reasonable follow angle, distance, FOV, and smoothing variations are accepted. |
| `COMBAT-01` | A living active enemy is visible and targetable. | Right-click that enemy. | Player selects it, approaches if needed, and applies Player-owned damage only in range and off cooldown until stable death. | No damage to dormant/dead/invalid targets, out-of-range damage, or unrelated target substitution when the pointer resolves correctly. | Approach, attack, health loss, and death are perceivable. | Repeated input follows cooldown; an empty pointer may fall back to the nearest active enemy. |
| `COMBAT-02` | Player and at least one active Imp are alive. | Begin or engage active play. | The Imp autonomously approaches and deals in-range cooldown damage; one hit can leave Player alive and continued enemy-owned hits can reach zero. | No invisible/source-less damage, inert threat, or only unavoidable instant defeat. | Enemy approach/attack and Player health loss are visible. | Combat continues after a non-terminal hit; zero health follows `FLOW-03`. |
| `COMBAT-03` | Any actor reaches zero health. | Let death resolve. | The actor stops movement, targeting, attacks, and damage; dead enemies stop accepting normal attacks and stop blocking progress. | No continued combat, normal retargeting, spontaneous revival, or wrong prerequisite advance. | Death pose, animation, effect, visibility, and HUD state clearly change. | Death is stable until Restart; Imp death also follows `GATE-01`/`GATE-02`. |
| `TUNING-01` | A fresh encounter is active. | Observe and play normal movement/combat. | Player is 120 HP, speed 7.0, range 3.2, damage 34, cooldown 0.55 s; each Imp is 62 HP, speed 3.8, range 2.1, damage 8, cooldown 1.10 s; Boss is 185 HP, speed 3.6, range 2.8, damage 17, cooldown 1.25 s. | These exact player-facing tuning values must not change during the encounter. | Health and action cadence read as a compact duel. | Restart restores the same values. |
| `DASH-01` | Player is alive, active, and Dash is ready. | Point at reachable ground and tap `2`. | Player moves at least 3 m and normally 4–6 m toward pointer/facing; feedback plays; a 3 s cooldown starts; Dash becomes reusable after recovery. | No immediate second displacement/effect, terminal Dash, or cooldown bypass. | Displacement/effect and ready/cooldown state are visible. | Edge geometry may shorten Dash; repeated taps during cooldown do not Dash. |
| `GATE-01` | One or both Imps remain alive, including exactly one dead. | Observe/fight or prematurely target the Boss. | Gate remains visibly closed and physically blocking; Boss remains dormant, unattackable, and undamaged; HUD reports locked. | No early gate opening/collision clear/Boss activation/Boss damage. | Gate and Boss readiness are distinguishable. | First Imp death alone never advances the Boss stage. |
| `GATE-02` | Exactly one Imp remains; Boss is dormant; gate is closed/blocking. | Defeat the final Imp through normal combat. | Gate visibly opens once, blocking clears, Boss activates/becomes attackable, HUD updates, and the route becomes accessible. | No still-blocking open gate, dormant Boss, unrelated activation, or repeated transition. | Gate transition, Boss readiness, route, and HUD visibly change. | State remains until Restart. |
| `FLOW-02` | Both Imps are dead; gate is open; Boss is active. | Defeat Boss through normal right-click combat. | Phase becomes one stable Victory state. | No early Victory, simultaneous Defeat, or direct-result shortcut. | Persistent Victory and appropriate audiovisual result appear. | `TERMINAL-01` freezes play; both Restart routes remain available. |
| `FLOW-03` | Player is alive and an active enemy can attack. | Let enemy-owned damage reduce Player to zero. | Phase becomes one stable Defeat state at zero health. | No Defeat above zero, simultaneous Victory, or direct-result shortcut. | Persistent Defeat and zero-health state appear. | `TERMINAL-01` freezes play; both Restart routes remain available. |
| `TERMINAL-01` | `FLOW-02` or `FLOW-03` completed. | Attempt movement, attack, Dash, or wait. | Player actions, enemy damage, gate/Boss progression, and result changes remain frozen. | No hidden ongoing attacks, health changes, movement, progression, or repeated results. | Terminal result remains readable and the encounter looks concluded. | Restart is the only route back to active play. |
| `UI-01` | Active play is visible at 1280×720. | Observe the runtime view. | HUD simultaneously shows Player health, living Imp count, gate state, Dash ready/cooldown, and move/attack/Dash/Restart controls. | No console-only/debug-only state, unreadable overlap, or missing required field. | All listed information is legible without development tools. | Layout and wording may vary within the public tool contract. |
| `UI-02` | Health, death, gate, Dash, terminal, or Restart changes. | Observe the next stable visible state. | HUD/in-world feedback agrees with real state; Victory and Defeat differ; Restart restores neutral feedback. | No stale/contradictory values or simultaneous terminal results. | Damage/death, gate, Dash, result, and recovery are perceivable. | Repeated actions/Restart do not reveal stale prior-run feedback. |
| `AUDIO-01` | Audio output is available. | Start, fight, reach Victory, and Restart. | Fresh play has one battle-music state; combat/death feedback is perceivable; Victory has an appropriate result response; Restart restores battle audio. | No absent encounter audio, contradictory battle/result playback, or duplicate stacked music. | Active battle and Victory are aurally distinguishable. | Equivalent clips/mixing are accepted when state and duplication rules hold. |
| `VISUAL-01` | A normal active or terminal state is visible. | Observe the full game view. | Presentation reads as an intentional original-inspired fantasy Boss Room with staged stone arena, Tank, two smaller Imps, larger gated Boss, warm/cool light contrast, readable silhouettes, and integrated HUD/result. | No empty graybox, primary placeholder primitives, broken materials, severe clipping, unreadable overlap, or unrelated assembly. | Encounter hierarchy, gate stage, combat, and terminal outcome are visually coherent. | Pixel-perfect matching, one hierarchy, and one exact layout are not required. |
| `ASSET-01` | Supplied content is available. | Assemble and play the encounter. | Supplied arena, Tank, Imp, Boss, gate, animation/VFX, and battle/result audio are visibly used in intended roles. | No unrelated replacement set, hidden supplied content, or placeholders as primary final presentation. | Supplied environment, characters, effects, and audio are recognizable. | Reasonable material/camera/light/UI composition changes are accepted. |
| `RESTART-01` | Encounter is active, won, or lost. | Tap keyboard `R` once. | Within 1 s, positions/health, two Imps, dormant Boss, closed blocking gate, ready Dash, battle audio, active phase, neutral HUD, and reusable input match `FLOW-01`. | No carried damage/cooldown/progress/result, duplicate actors/actions/listeners, or multiple reset from one tap. | View immediately reads as a fresh playable encounter. | Two repeated Restarts remain clean; one later input creates one intent. |
| `RESTART-02` | Victory or Defeat and visible Restart are present. | Complete one normal click on the visible Restart control. | Same complete reset/reusable input as `RESTART-01`. | No decorative/non-clickable control, partial panel-only reset, duplicate reset, or world movement from the UI click. | Control reacts and neutral active HUD returns. | Works after either terminal outcome and repeated runs. |
| `REOPEN-01` | Any active or terminal runtime state exists. | Fully close the process, launch a new process, and start the game. | A fresh `FLOW-01` encounter begins with no prior runtime progress. | No retained health/deaths/gate/result/position/Dash state or incomplete entry. | Reopened game presents the same authored starting experience. | This task has no persistent gameplay progress. |
| `QUALITY-01` | The project is available for normal player use. | Start it, play the main flow, exit, and start it again through the public instructions. | The project starts, runs, exits, and starts again through the public instructions. | Import, launch, exit, or reopen failure cannot block the required player journey. | Each start presents a visible playable entry and coherent current state. | Repeated exit and start cycles remain usable. |
| `QUALITY-02` | The main player flow is available. | Use the documented normal player controls to pursue its outcomes. | The main flow uses normal player input and contains no answer button, cheat route, or direct-result shortcut. | An answer button, cheat entry, direct-result call, or non-player shortcut cannot replace the player journey. | Visible game state changes only as a consequence of normal player actions and rules. | Repeated normal-input attempts remain usable. |
| `QUALITY-03` | A required entry, label, or control is relevant to the current player state. | Locate, read, and operate it through the player-facing presentation. | Key entry points, labels, and controls are visible, findable, readable, and operable. | A required entry, label, or control cannot be hidden, unreadable, undiscoverable, or inoperable. | The relevant entry, label, or control is visibly identifiable and its response is understandable. | It remains usable in every required state where it applies. |
| `QUALITY-04` | A player action can change or reject game state. | Perform the action and observe the next stable state. | Player actions have perceivable feedback, and visible feedback agrees with real state. | Feedback cannot be absent, misleading, or inconsistent with the actual game state. | The player perceives state-consistent visual or audio feedback. | Repeated accepted and rejected actions do not expose stale feedback. |
| `QUALITY-05` | The player follows a required main-flow journey. | Continue through its required actions and transitions. | No severe error blocks the required player flows. | A severe import, runtime, rendering, input, or state error cannot block the journey. | The player-facing flow remains visible, responsive, and understandable. | Recovery paths defined by the task remain available after non-terminal mistakes. |
| `QUALITY-06` | The same clean initial conditions and player action sequence are available. | Repeat that sequence from a fresh state. | Repeating the same initial conditions produces substantially stable results. | Uncontrolled prior-run state or duplicate handling cannot materially change the result. | The repeated journey presents substantially stable visible states and outcomes. | Restart or reopen boundaries govern the intentionally reset or retained state. |

## 7. Success, failure, and staged flow (ID summaries)

### 7.1 Success

| Requirement IDs | Steps before success | Success condition | State after success | Feedback summary |
|---|---|---|---|---|
| `GATE-01`, `GATE-02`, `FLOW-02`, `TERMINAL-01` | Defeat Imp A and Imp B before fighting the activated Boss. | Active Boss reaches zero through normal combat. | Stable Victory with gameplay frozen until Restart. | Victory result and appropriate audiovisual response. |

### 7.2 Failure

| Requirement IDs | Failure condition | State after failure | Failure feedback | Retry summary |
|---|---|---|---|---|
| `COMBAT-02`, `FLOW-03`, `TERMINAL-01` | Enemy-owned damage reduces Player to zero. | Stable Defeat with gameplay frozen. | Defeat result, zero health, and distinct audiovisual feedback. | `RESTART-01` or `RESTART-02` restores `FLOW-01`. |

### 7.3 Multi-stage flow

| Stage | Requirement IDs | Stage summary | Early result excluded by the cited IDs |
|---|---|---|---|
| Stage 1 | `COMBAT-01`, `COMBAT-03`, `GATE-01` | Defeat one Imp; gate remains closed/blocking and Boss dormant. | Gate/Boss transition and Victory. |
| Stage 2 | `GATE-02` | Defeat final Imp; gate opens and Boss activates. | Victory before Boss death. |
| Final stage | `FLOW-02`, `TERMINAL-01` | Defeat active Boss and hold stable Victory. | Defeat or continued gameplay. |

## 8. Interface and feedback (ID summary)

| Requirement IDs | Information/state | When it appears or updates | Player distinction summary |
|---|---|---|---|
| `UI-01` | Player health, living Imp count, gate, Dash, and controls | Visible during active play | Current health/progression and available actions. |
| `UI-02` | Damage, death, gate, Dash, terminal, and restored state | Updates after each corresponding stable change | Current state from stale/contradictory feedback; Victory from Defeat. |
| `AUDIO-01` | Battle, combat/death, Victory, and restored battle response | Start, combat, Victory, and Restart | Active battle from result state and one source from duplicates. |
| `VISUAL-01`, `ASSET-01` | Arena hierarchy, roles, gate stage, combat, and result | Active and terminal views | Player/Imps/Boss, locked/open stage, and final outcome. |

## 9. Restart, close/reopen, and progress (ID summary)

| Scenario | Requirement IDs | Reset summary | Preserved summary | Final-state summary |
|---|---|---|---|---|
| Keyboard Restart | `RESTART-01`, `FLOW-01` | Encounter state, positions, health, enemies, gate, Dash, phase, HUD, audio, and input reuse. | Supplied authored content only. | Clean reusable `FLOW-01`. |
| Visible UI Restart | `RESTART-02`, `FLOW-01` | Same complete reset as keyboard Restart; UI click does not leak to world input. | Supplied authored content only. | Clean reusable `FLOW-01`. |
| Full close and new process | `REOPEN-01`, `FLOW-01` | All runtime progress is discarded. | No gameplay progress. | Clean authored `FLOW-01`. |

## 10. Existing functionality to preserve (ID summary)

| Requirement IDs | Existing content | Player use | What remains usable |
|---|---|---|---|
| `ASSET-01`, `VISUAL-01`, `QUALITY-01` | Supplied art-only Scene, arena layout, camera starting composition, materials, lighting, animation/VFX, and audio dependencies. | See and play the final encounter. | Supplied content remains loadable and is assembled into the runtime roles cited by those IDs. |

## 11. Assets and content (ID summary)

| Requirement IDs | Asset/content | Hard requirement | In-game use | Equivalent replacement |
|---|---|---:|---|---|
| `ASSET-01`, `VISUAL-01` | Inventory in `ASSET_MANIFEST.json` | Yes | Arena, Tank, two Imps, Boss, gate, animation/VFX, battle/result audio. | Reasonable composition/material variants are allowed; unrelated replacement packs are not the task. |

## 12. Implementation boundary

Section 6 is the complete source of game-specific requirements. The target is a saved, normally playable encounter whose navigation, combat, Dash, gate progression, Victory, Defeat, HUD, audio, Restart and reopen behavior agree with those numbered goals. Automation observations mirror the same visible/runtime state and do not perform gameplay.

`TOOLCHAIN.md` describes the public Unity delivery/input compatibility profile used to operate the project; it is not a gameplay solution and adds no hidden gameplay requirement. Internal class names, object hierarchy, algorithms, data organization and presentation implementation are not acceptance conditions.

## 13. Requirement ID index

This section is navigation only. It introduces no new condition and summarizes only the
player goals already defined in Section 6.

| Goal area | Section 6 requirement IDs | Player-goal summary |
|---|---|---|
| Flow and terminals | `FLOW-01`, `FLOW-02`, `FLOW-03`, `TERMINAL-01` | Playable entry, active encounter, stable outcomes, and terminal presentation. |
| Input and navigation | `INPUT-01`, `NAV-01`, `CAMERA-01` | Normal player input, destination movement, and readable camera behavior. |
| Combat | `COMBAT-01`, `COMBAT-02`, `COMBAT-03`, `DASH-01`, `TUNING-01` | Multi-hit combat, enemy consequences, player defeat, Dash, and specified encounter values. |
| Gate progression | `GATE-01`, `GATE-02` | First-Imp lock and final-Imp unlock progression. |
| Lifecycle | `RESTART-01`, `RESTART-02`, `REOPEN-01` | Keyboard restart, visible restart, and clean distinct-process reopen. |
| Interface and presentation | `UI-01`, `UI-02`, `VISUAL-01`, `AUDIO-01`, `ASSET-01` | HUD, feedback, visual composition, audio, and supplied asset roles. |
| General playability | `QUALITY-01`, `QUALITY-02`, `QUALITY-03`, `QUALITY-04`, `QUALITY-05`, `QUALITY-06` | Launch, visibility, input, state coherence, feedback, and recovery baseline. |
