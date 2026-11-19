# Night Sky Duel Lab

## 1. One-Sentence Task

Create a direct-entry side-view fighting duel in which the player repositions, jumps, uses a close strike and an energy bolt, blocks a telegraphed rival pulse, and reaches a stable win or loss state (`CONTENT-01`, `INPUT-01`, `INPUT-02`, `COMBAT-01` through `COMBAT-03`, `DEFENSE-01`, `DEFENSE-02`, `TERMINAL-01`, `TERMINAL-02`).

## 2. Scope

### 2.1 Included Work

| Requirement ID | Summary |
|---|---|
| `CONTENT-01` | Present one readable, bounded side-view arena with two distinct facing fighters and a direct playable entry. |
| `ASSET-01`, `ASSET-02` | Use the supplied Manny 3D model for both fighters and the eight supplied animations for their specified visible roles. |
| `INPUT-01`, `INPUT-02` | Support bounded horizontal movement and a grounded jump. |
| `COMBAT-01` through `COMBAT-03` | Support a close strike, a cooldown-limited energy bolt, and truthful miss/rejection behavior. |
| `DEFENSE-01`, `DEFENSE-02` | Run the rival's deterministic telegraphed pulse and allow a held block to negate its damage. |
| `RULE-01`, `RULE-02` | Keep health, damage, object counts, and the stationary-rival contract deterministic. |
| `INTERFACE-01`, `INTERFACE-02` | Keep HUD values and short-lived combat feedback visible and synchronized. |
| `TERMINAL-01`, `TERMINAL-02` | Resolve KO outcomes once and keep the terminal state locked. |
| `LIFECYCLE-01`, `LIFECYCLE-02` | Support an in-process restart and a clean fresh-process reopen. |
| `QUALITY-01` through `QUALITY-06` | Meet the shared playability and stability baseline. |

### 2.2 Excluded Work

| Related Requirement IDs | Excluded Content |
|---|---|
| None | Main menus, character select, teams, throws, crouching, air dashes, supers, combo counters, multiple rounds, replay, rollback networking, online services, save progress, and configurable controls are outside this slice. |
| `LIFECYCLE-02` | Persistent match progress is outside this slice. |

## 3. Starting State

| Item | Starting State | Requirement IDs When Evaluated |
|---|---|---|
| Engine identity | The task is bound to the validated local Unreal Engine 5.7.4 build. | None; this is an environment fact. |
| Project and entry | The common start is a source-only Blank project that opens an English health screen. | `QUALITY-01`, `CONTENT-01` |
| Gameplay | The common start contains no fighter pawn, rival, arena, gameplay input, attack, defense, health, KO, or gameplay restart implementation. | All task-specific requirements |
| Observation bridge | The common start publishes a read-only task envelope with `bridge_ready=true`, `provider_ready=false`, and `game_state=null`. | None; this is public evaluator interoperability, not gameplay acceptance. |
| Supplied assets | One preimported Manny skeletal model and eight animation sequences are available under `/Game/Provided/Manny/`, with stable asset IDs and object paths. They are not assembled into gameplay in the starter. | `ASSET-01`, `ASSET-02` |
| Intended fresh round | The requested implementation begins with both fighters at 100 health, separated by at least two fighter widths, with no projectile, no telegraph, and no result state. | `CONTENT-01`, `RULE-01`, `RULE-02`, `LIFECYCLE-02` |

## 4. Player Goal and Complete Flow

### 4.1 Player Goal

The player manages spacing and defense, reduces the rival from 100 health to 0, and reaches the stable player-win state before the rival's repeated pulses reduce the player to 0 (`COMBAT-01`, `COMBAT-02`, `DEFENSE-01`, `DEFENSE-02`, `TERMINAL-01`).

### 4.2 Complete Player Flow

```text
Enter the game
-> [CONTENT-01, RULE-01] identify the arena, both fighters, health, and controls
-> [INPUT-01, INPUT-02] reposition or jump
-> [COMBAT-01, COMBAT-02, COMBAT-03] choose a valid attack and read its result
-> [DEFENSE-01, DEFENSE-02] react to the rival telegraph by blocking or accepting damage
-> [INTERFACE-01, INTERFACE-02] read synchronized health, cooldown, telegraph, hit, guard, and result feedback
-> [TERMINAL-01, TERMINAL-02] reach and hold one KO result
-> [LIFECYCLE-01] press R for a fresh round
```

### 4.3 Core Loop

```text
[INPUT-01, INPUT-02] choose position
-> [COMBAT-01 or COMBAT-02] commit one attack
-> [COMBAT-03, INTERFACE-02] read hit, miss, or cooldown feedback
-> [DEFENSE-01, DEFENSE-02] respond to the next rival telegraph
-> [INTERFACE-01, TERMINAL-01] read health and continue or finish
```

## 5. Player Controls

| Requirement IDs | Player Action | Context | Response Summary |
|---|---|---|---|
| `INPUT-01` | Hold `A` or `D`, then release | Active round while not blocking or in another committed action | Move left or right within the arena and return to idle after release. |
| `INPUT-02` | Press `W` | Grounded during an active round | Begin one jump and return to grounded state after landing. |
| `COMBAT-01` | Press `J` | Active round | Attempt one close strike. |
| `COMBAT-02`, `COMBAT-03` | Press `K` | Active round | Fire one energy bolt when ready, or show a cooldown rejection without creating another bolt. |
| `DEFENSE-02` | Hold `S`, then release | Active round | Enter block while held and leave block after release. |
| `LIFECYCLE-01` | Press `R` once | Active or terminal round | Start a fresh round in the same process. |

## 6. Numbered Requirements: Sole Acceptance Authority

This section is the only source of gameplay acceptance requirements. Other sections summarize these IDs.

### 6.1 Requirement Granularity

Each row defines one independently judgeable result. Exact values, timing, ordering, required text, and prohibited behavior used for acceptance appear in this section.

### 6.2 Task-Specific Requirements

| Requirement ID | Preconditions | Player Action or Trigger | Required Result | Prohibited Result | Player-Visible Feedback | Failure, Repetition, Restart, or Other Boundary |
|---|---|---|---|---|---|---|
| `CONTENT-01` | The game process has started. | Natural entry. | Within 2 seconds of the first stable rendered frame, enter one bounded side-view arena with exactly one player fighter on the left and one visually distinct rival fighter on the right. Both fighters are simultaneously visible, stand on the same readable floor, face each other, and begin separated by at least two fighter widths. | Do not require a menu, character select, console command, network service, or hidden answer control before the round is playable. | Show both fighters, arena bounds or walls, the floor, the control legend `A/D Move  W Jump  J Strike  K Bolt  S Block  R Restart`, and the HUD required by `INTERFACE-01`. | Restart and Reopen return to the same direct playable arrangement. Side-view 2.5D or stylized 3D presentation is allowed, using the supplied 3D fighters and animations under `ASSET-01` and `ASSET-02`. |
| `INPUT-01` | Phase is active; the player is grounded and not in block, hit reaction, or an attack commitment. | Hold `A` or `D`, then release. | Move continuously left or right while held, remain inside the arena, stop horizontal movement after release, and always face toward the rival. | The player cannot pass through the rival, cross an arena wall, continue sliding after release, or turn away from the rival. | Movement must visibly change position; the fighter returns to an idle presentation after release. | Opposite-direction input reverses movement without leaving the arena. Restart restores the initial position. |
| `INPUT-02` | Phase is active and the player is grounded. | Press `W`. | Begin one visible jump, become airborne, then land on the arena floor and return to grounded state. | A second `W` press while airborne cannot create an additional jump or reset upward motion. | Show a distinct airborne pose or vertical displacement and a visible landing. | Repeated grounded presses may create later jumps. Restart removes any airborne motion. |
| `COMBAT-01` | Phase is active. | Press `J`. | Attempt one forward close strike. If the rival is in close range at the strike's single impact moment, reduce rival health by exactly 25 and resolve exactly one rival hit reaction. | One press cannot deal damage more than once, cannot damage from outside close range, and cannot reduce health below 0. | Show a visible strike action. On hit, show rival hit reaction plus the hit feedback required by `INTERFACE-02`; on miss, show the miss feedback required by `COMBAT-03`. | Further strikes may be attempted after the visible strike commitment ends. Restart cancels an in-progress strike and restores health. |
| `COMBAT-02` | Phase is active and the bolt is ready. | Press `K`. | Create exactly one visible player energy bolt moving toward the rival, mark the bolt unavailable for 1.0 second, and keep at most one player bolt active. A bolt that reaches the rival reduces rival health by exactly 15 once, resolves one hit reaction, and is removed. | The bolt cannot damage more than once, cannot persist after impact or leaving the arena, cannot pass through the rival and later damage again, and cannot reduce health below 0. | Show the travelling bolt, a visible ready/cooldown state, and hit feedback when it connects. | A new bolt may be fired only after no earlier player bolt remains and the 1.0-second cooldown has expired. Restart removes every bolt and makes the action ready. |
| `COMBAT-03` | Phase is active. | A close strike reaches its impact moment outside close range, or `K` is pressed while a bolt is active or its cooldown has not expired. | Preserve both fighters' health and object counts except for the normal removal of a missed bolt at the arena boundary. A rejected `K` press creates no new bolt and does not reset or extend the existing cooldown. | Misses and rejected inputs cannot cause hidden damage, duplicate projectiles, or false hit reactions. | A close miss shows a brief `WHIFF` indication; a rejected bolt shows a brief `COOLDOWN` indication. Neither indication may claim a hit. | Repeated rejected presses remain side-effect free. Restart clears both indications. |
| `DEFENSE-01` | Phase is active. | Natural time progression. | The stationary rival begins its first pulse telegraph 3.0 seconds after the round becomes active and begins each later telegraph 3.0 seconds after the previous pulse resolves. Each telegraph lasts 0.75 seconds, then one pulse resolves against the player. An unblocked pulse reduces player health by exactly 20 once. | The rival cannot chase, jump, fire extra pulses, deal damage before the telegraph finishes, deal multiple damage from one pulse, or continue its cadence after a terminal result. | During the full telegraph, show a clearly visible warning on or around the rival. On an unblocked hit, show player hit reaction and the feedback required by `INTERFACE-02`. | Timing tolerance is plus or minus 0.15 seconds for the 3.0-second interval and plus or minus 0.10 seconds for the 0.75-second telegraph. Restart begins a new cadence with no inherited pulse. |
| `DEFENSE-02` | Phase is active. | Hold `S` before a rival pulse impact and keep it held through the impact. | Enter a visible blocking state while held. A pulse resolved during that state deals exactly 0 health damage, produces one guard resolution, and then continues the normal rival cadence. Releasing `S` returns the player to idle if no other state applies. | Blocking cannot heal, damage the rival, create a projectile, move the player, or remain active after `S` is released. A press begun after pulse impact cannot retroactively block that pulse. | Show an unmistakable block pose while held and a brief guard flash plus `BLOCKED` feedback when the pulse resolves. | Holding block across multiple later pulses may block each pulse. Restart clears block even if the key was held before restart. |
| `RULE-01` | A fresh round begins. | Natural round initialization and later damage. | Set player health and rival health to exactly 100. Apply only the damage values defined by `COMBAT-01`, `COMBAT-02`, and `DEFENSE-01`; clamp both health values to the inclusive range 0 through 100; and update health truth and HUD in the same visible update. | Health cannot become negative, exceed 100, change without a defined damage event or restart, or disagree with the visible HUD. | Show numeric health and proportional bars for both fighters. | Repetition remains deterministic under the same input timing. Restart and Reopen restore both values to 100. |
| `RULE-02` | Phase is active. | Natural update. | Keep exactly one player fighter and one rival fighter. The rival remains at its initial horizontal position except for a short visual hit reaction; the player cannot push it to a new resting position. | Do not spawn replacement fighters, helper fighters, or hidden damage actors that persist as additional fighters. | Both fighters remain identifiable and visible except for momentary effects that do not hide the duel. | Restart removes transient combat objects and restores the same two-fighter arrangement. |
| `INTERFACE-01` | A round exists. | Natural state changes. | Continuously show player health, rival health, and bolt state as `READY` or a remaining cooldown indication. During a terminal result, continue showing the final health values. | The HUD cannot display stale, rounded-to-a-different-damage-step, or fabricated values. | Use readable labels and bars that distinguish player from rival at 1280 x 720. | Restart immediately restores `100`, `100`, and `READY`. Reopen shows the same fresh values. |
| `INTERFACE-02` | Phase is active or has just become terminal. | A strike, bolt, pulse, block, miss, cooldown rejection, or KO resolves. | Provide feedback matching the resolution: visible hit flash/reaction for damage, guard flash plus `BLOCKED` for a block, `WHIFF` for an out-of-range close strike, `COOLDOWN` for a rejected bolt, and a result banner for KO. Short-lived nonterminal text remains visible for at least 0.30 seconds and no longer than 1.25 seconds. | Feedback cannot claim damage, block, or KO when the corresponding state transition did not occur. | Feedback is readable without opening logs or developer tools. | Later feedback may replace earlier short-lived feedback. Restart clears every transient and terminal message. |
| `TERMINAL-01` | Phase is active and at least one fighter has positive health. | A defined damage event reduces one fighter to 0. | Resolve exactly one result: rival health 0 and player health above 0 produces player win; player health 0 and rival health above 0 produces rival win. If both reach 0 in the same update, produce `DRAW`. Show the matching banner `PLAYER WINS`, `RIVAL WINS`, or `DRAW`. | The result cannot contradict final health and cannot fire more than once for the same round. | Keep final health visible and show the result banner within 0.5 seconds of the decisive damage update. | `R` remains available through `LIFECYCLE-01`. Reopen follows `LIFECYCLE-02`. |
| `TERMINAL-02` | A result from `TERMINAL-01` has resolved. | Natural time progression and any `A`, `D`, `W`, `J`, `K`, or `S` input. | Keep both health values, result, fighter count, and final positions stable until `R` is pressed or the process closes. Remove active bolts and cancel the rival cadence. | Movement, jump, attack, block, damage, healing, new projectile creation, or a second result cannot occur during the terminal state. | The result banner remains visible; fighters may hold a win, loss, or draw pose. | Waiting at least 3.5 seconds after the result must not permit an old rival pulse to change the terminal state. |
| `LIFECYCLE-01` | A process is running in an active or terminal round. | Press `R` once. | Within 1.0 second, create a new round identity and restore the direct playable state: both health values 100, initial positions, grounded idle player, stationary idle rival, bolt ready, no projectile, no telegraph, no block, no transient feedback, no result, and a fresh 3.0-second rival cadence. | The new round cannot inherit health, motion, held block, cooldown, projectile, telegraph, result, or delayed damage from the old round. | The HUD and arena visibly return to the fresh state. | Repeated `R` presses create later clean rounds. Old delayed events remain unable to affect them. |
| `LIFECYCLE-02` | The game process has been closed normally after any active or terminal progress. | Start a new process using the documented runtime entry. | Enter a fresh round with the same state listed in `LIFECYCLE-01`, a new process identity, and no retained match progress. | A new process cannot restore prior health, positions, cooldown, projectile, telegraph, result, or round identity. | The first playable view is the fresh arena and HUD rather than a resume prompt. | This task has no save-progress requirement. |
| `ASSET-01` | The arena is visible. | Natural entry and continued play. | Both fighters visibly use the supplied `SKM_Manny` 3D skeletal character model, with its recognizable body shape and articulated limbs. Keep the player and rival visually distinct through color or material treatment. | Primitives, sprites, flat images, unrelated meshes, or hidden/off-screen instances of the supplied model cannot substitute for either visible fighter. Merely importing or referencing the model is not sufficient. | The supplied model is the visible body of each fighter throughout the duel. | Reuse the same model for both fighters. Color changes, uniform scaling, and supplemental effects are allowed; replacing its recognizable shape is not. Restart and Reopen preserve this presentation. |
| `ASSET-02` | A fighter is visible in a state already required by this section. | Idle; player movement, jump, strike, bolt, or block; either fighter receiving a hit. | Visibly animate the supplied model with `AS_manny_stand` for idle, `AS_manny_fwalk` for movement toward the rival, `AS_manny_bwalk` for movement away from the rival, `AS_manny_jump` for jumping, `AS_manny_5a` for the close strike, `AS_manny_fireball` for bolt casting, `AS_manny_standblock` for standing guard, and `AS_manny_hitstun` for hit reaction. All eight supplied clips must be used for these roles. | A static model, unrelated replacement animation, or clips that are imported but never visibly played do not satisfy this requirement. Damage-free whiffs and rejected actions cannot trigger a false hit reaction. | The supplied clips make the corresponding existing actions or states recognizable on screen. | Blending, looping, pose holds, and playback-rate adjustment are allowed when they preserve the recognizable motion and existing numbered rules. Clip duration does not set gameplay timing, damage, collision, or cooldown. Restart cancels an old action presentation and restores idle; Reopen retains the same asset use. |

### 6.3 Shared Quality Requirements

| Requirement ID | Formal Requirement |
|---|---|
| `QUALITY-01` | The project can start, run, exit, and start again by following the public instructions. |
| `QUALITY-02` | The main flow uses normal player input and does not depend on an answer button, cheat entry, or direct gameplay-result call. |
| `QUALITY-03` | Critical entries, text, controls, and feedback are visible, discoverable, readable, and operable. |
| `QUALITY-04` | Player actions produce perceptible feedback, and visible feedback remains consistent with true game state. |
| `QUALITY-05` | No severe error blocks the main flow. |
| `QUALITY-06` | Repeated runs from the same initial conditions produce substantially stable results. |

## 7. Success, Failure, and Multi-Stage Flow

### 7.1 Success

| Requirement IDs | Summary Before Success | Success Condition Summary | Post-Success Summary | Feedback Summary |
|---|---|---|---|---|
| `COMBAT-01`, `COMBAT-02`, `TERMINAL-01`, `TERMINAL-02` | Use valid attacks while surviving rival pulses. | Rival reaches 0 while player remains above 0. | Lock the round until restart. | Final health plus `PLAYER WINS`. |

### 7.2 Failure

| Requirement IDs | Failure Condition Summary | Post-Failure Summary | Feedback Summary | Retry Summary |
|---|---|---|---|---|
| `DEFENSE-01`, `TERMINAL-01`, `TERMINAL-02` | Unblocked rival pulses reduce the player to 0 while the rival remains above 0. | Lock the round until restart. | Final health plus `RIVAL WINS`. | Press `R` under `LIFECYCLE-01`. |

### 7.3 Multi-Stage Flow

| Stage | Requirement IDs | Stage Summary | Cannot Appear Early |
|---|---|---|---|
| Spacing | `INPUT-01`, `INPUT-02`, `RULE-02` | Establish position while both fighters remain active. | `TERMINAL-01` result banner |
| Attack or defend | `COMBAT-01` through `COMBAT-03`, `DEFENSE-01`, `DEFENSE-02` | Resolve one truthful hit, miss, rejection, or block. | A KO result before decisive health reaches 0 |
| Terminal | `TERMINAL-01`, `TERMINAL-02` | Show and hold exactly one health-consistent result. | New combat changes before `LIFECYCLE-01` |

## 8. Interface and Feedback

| Requirement IDs | Information or State | Appearance and Update Summary | Player Distinction |
|---|---|---|---|
| `INTERFACE-01` | Player health, rival health, bolt readiness | Visible throughout a round and synchronized with truth. | Which fighter has which health and whether `K` is ready. |
| `DEFENSE-01`, `DEFENSE-02` | Rival telegraph and player block | Visible during their active windows. | Incoming danger versus successful guard. |
| `INTERFACE-02` | Hit, block, whiff, cooldown rejection, result | Brief nonterminal feedback or persistent terminal banner. | What actually resolved and whether health changed. |

## 9. Restart, Reopen, and Save Behavior

| Scenario | Requirement IDs | Reset Summary | Preserved Summary | Final State Summary |
|---|---|---|---|---|
| Restart current duel | `LIFECYCLE-01` | All gameplay progress, transient objects, timers, messages, held state, and result. | Process remains open. | New clean round. |
| Close and reopen | `LIFECYCLE-02` | All duel progress and process-local identities. | No match progress. | New process and clean round. |

## 10. Legacy Functionality to Preserve

No legacy functionality is required for this task.

## 11. Asset and Content Summary

| Requirement IDs | Asset or Content | Hard Requirement | Gameplay Use | Equivalent Replacement |
|---|---|---:|---|---|
| `ASSET-01`, `CONTENT-01` | `SKM_Manny`: Manny 3D skeletal fighter model | Yes, for both visible fighters | Preserve the supplied character shape while distinguishing player and rival | No model replacement; color/material changes and uniform scaling are allowed under `ASSET-01`. |
| `ASSET-02` | Eight named Manny animation clips listed below | Yes, for the listed existing action/state roles | Show idle, forward/backward movement, jump, strike, bolt casting, standing guard, and hit reaction | No unrelated replacement clips; presentation adjustments follow `ASSET-02`. |
| `CONTENT-01`, `RULE-02` | One readable arena | No supplied arena is mandated | Communicate the floor and bounds | Yes; engine primitives, Paper2D content, or implementation-created scenery are allowed. |
| `COMBAT-02`, `INTERFACE-02` | Energy bolt, telegraph, hit, and guard effects | No external asset is mandated | Make combat phases and resolutions visible | Yes, if the numbered feedback requirements remain satisfied. |

Exact delivery, dependency, license, and package facts are in `ASSET_MANIFEST.json`, `assets/ASSET_CATALOG.json`, and `tools/TOOLCHAIN.md`. The following lookup summarizes `ASSET-01` and `ASSET-02`; it does not prescribe gameplay logic.

| Asset ID | Meaning / Visible Role | FBX Reference | Preimported Object |
|---|---|---|---|
| `SKM_Manny` | Manny skeletal character model, used by both fighters | `assets/files/Manny/SKM_Manny.fbx` | `/Game/Provided/Manny/SKM_Manny.SKM_Manny` |
| `AS_manny_stand` | Standing idle | `assets/files/Manny/AS_manny_stand.fbx` | `/Game/Provided/Manny/Animations/AS_manny_stand.AS_manny_stand` |
| `AS_manny_fwalk` | Forward walk, toward the rival | `assets/files/Manny/AS_manny_fwalk.fbx` | `/Game/Provided/Manny/Animations/AS_manny_fwalk.AS_manny_fwalk` |
| `AS_manny_bwalk` | Backward walk, away from the rival | `assets/files/Manny/AS_manny_bwalk.fbx` | `/Game/Provided/Manny/Animations/AS_manny_bwalk.AS_manny_bwalk` |
| `AS_manny_jump` | Jump motion | `assets/files/Manny/AS_manny_jump.fbx` | `/Game/Provided/Manny/Animations/AS_manny_jump.AS_manny_jump` |
| `AS_manny_5a` | Standing close strike | `assets/files/Manny/AS_manny_5a.fbx` | `/Game/Provided/Manny/Animations/AS_manny_5a.AS_manny_5a` |
| `AS_manny_fireball` | Projectile-casting motion, used for the energy bolt | `assets/files/Manny/AS_manny_fireball.fbx` | `/Game/Provided/Manny/Animations/AS_manny_fireball.AS_manny_fireball` |
| `AS_manny_standblock` | Standing guard | `assets/files/Manny/AS_manny_standblock.fbx` | `/Game/Provided/Manny/Animations/AS_manny_standblock.AS_manny_standblock` |
| `AS_manny_hitstun` | Receiving a hit | `assets/files/Manny/AS_manny_hitstun.fbx` | `/Game/Provided/Manny/Animations/AS_manny_hitstun.AS_manny_hitstun` |

The preimported packages contain the model, skin weights, bind Skeleton, and bone motion, without gameplay Blueprints, animation graphs, event tracks, custom curves, combat data, or assembled scenes.

## 12. Implementation Freedom

Unless Section 6 states otherwise, the implementation may freely choose code organization, Blueprint or C++ usage, classes, components, data structures, algorithms, camera implementation, art style within `ASSET-01`, animation orchestration within `ASSET-02`, collision representation, and whether restart resets actors or reloads a level. The public read-only observation bridge may be extended or replaced inside the writable project as long as it remains schema-valid and cannot mutate gameplay.

## 13. Pre-Submission Self-Check

- [ ] Every acceptance-affecting required or prohibited result is defined in Section 6.
- [ ] Other sections only summarize and reference Section 6 IDs.
- [ ] The direct-entry flow, success, failure, rejection, terminal lock, restart, and reopen are covered.
- [ ] Exact damage, health, cooldown, telegraph, timing tolerance, feedback duration, and reset values are in Section 6.
- [ ] No engine command, evaluator checkpoint, score, reference architecture, private coordinate, or implementation path is treated as gameplay acceptance.
- [ ] Both visible fighters use the supplied model and all eight supplied clips serve their specified roles (`ASSET-01`, `ASSET-02`).
- [ ] Different reasonable side-view 2.5D/3D, Blueprint, and C++ architectures remain possible without replacing required character assets.
