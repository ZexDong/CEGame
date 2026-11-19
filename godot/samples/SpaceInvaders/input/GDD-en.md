# SpaceInvaders: First-Level Victory Challenge

> Public gameplay contract. Section 6 defines gameplay outcomes; section 12 defines their read-only observation vocabulary. This document defines player-visible rules and results only; it does not prescribe scene structure, scripts, algorithms, or private evaluation logic.

## 1. Task in One Sentence

Build a complete single-level fixed shooter: move a cannon along the bottom, fire upward, clear one moving 8-by-5 enemy grid while avoiding enemy fire, then lose all lives or clear the grid to reach the appropriate result screen.

## 2. Scope

### 2.1 Required

| Requirement IDs | Summary |
|---|---|
| `ENTRY-01`–`ENTRY-02` | Playable entry, three-second level countdown, and initial state |
| `PLAYER-01`–`PLAYER-02` | Horizontal movement and firing |
| `FORMATION-01`–`FORMATION-04` | Forty-invader grid, synchronized movement, speed-up, edge reversal, and descent |
| `ATTACK-01`–`ATTACK-03` | Player and enemy projectiles, collision, and projectile cleanup |
| `SCORE-01`–`SCORE-03` | Enemy values, score updates, and one-time awards |
| `LIFE-01`–`LIFE-03` | Player hit, remaining lives, and Game Over |
| `LEVEL-01`–`LEVEL-02` | First-level success and post-victory stability |
| `PAUSE-01`–`PAUSE-02` | Pause/resume and frozen simulation |
| `HUD-01`–`HUD-03` | Score, lives, level, and remaining-enemy reporting |
| `RESTART-01`–`RESTART-02` | Restart and close/reopen behavior |
| `VISUAL-01`–`VISUAL-03` | Supplied asset identities, projectile distinction, and no broken placeholders |
| `QUALITY-01`–`QUALITY-03` | Readability, reachability, and no terminal-state gameplay leakage |

### 2.2 Excluded

| Related IDs | Not included |
|---|---|
| None | Online play, accounts, leaderboards, persistent saves, mobile-specific controls, level editor, or content beyond one completed level |
| `SCORE-03` | A separate bonus-saucer scoring system is not required |

## 3. Starting State

| Item | Starting state | Requirement |
|---|---|---|
| Project entry | A runnable Godot 4.7.1 starter with a visible placeholder screen | `ENTRY-01`, `QUALITY-01` |
| Gameplay | The target fixed-shooter flow is not implemented | All core requirements |
| Player | A bottom cannon with three lives | `ENTRY-02`, `LIFE-01` |
| Enemies | Forty active invaders arranged as five rows of eight | `FORMATION-01` |
| Score | `0` | `SCORE-02` |
| Level | `1` of `1` | `LEVEL-01`, `HUD-03` |

## 4. Player Goal And Complete Flow

### 4.1 Player Goal

Clear all forty invaders in the single level without allowing the formation to reach the bottom and without losing all three lives (`PLAYER-01`, `FORMATION-04`, `LIFE-03`, `LEVEL-01`).

### 4.2 Complete Player Flow

```text
Launch the game
-> [ENTRY-01] enter Level 1
-> [ENTRY-02] see a three-second countdown
-> [PLAYER-01/02] move and fire
-> [FORMATION-01..04] invaders move as a grid, speed up, reverse, and descend
-> [ATTACK-01..03] projectiles hit invaders, barriers, or the player
-> [SCORE-01..03] score increases as invaders are destroyed
-> [LEVEL-01] clear all forty invaders to win
-> [LEVEL-02] keep the completed state stable, or [LIFE-03] lose all lives
-> [RESTART-01/02] restart, close, and reopen
```

### 4.3 Core Loop

```text
Read the formation and incoming fire
-> move horizontally
-> fire one upward shot
-> destroy an invader or lose a projectile to a barrier
-> avoid the next enemy projectile
-> continue until the formation is cleared or a life is lost
```

## 5. Player Controls

| Requirement | Action | Context | Result |
|---|---|---|---|
| `PLAYER-01` | Hold Left/A or Right/D | During active play | Move the cannon horizontally within the battlefield |
| `PLAYER-02` | Press W, Up, Space, or Enter | During active play | Fire if no player projectile from the previous shot remains |
| `PAUSE-01` | Press Escape | During active play or pause | Pause or resume |
| `RESTART-01` | Click the visible Restart button | Game Over or Mission Complete | Start a clean game at Level 1 |

## 6. Numbered Requirements: Sole Gameplay Acceptance Criteria

### 6.1 Entry And Initial State

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| ENTRY-01 | Launch a new process | Open a playable game screen for Level 1 without requiring a hidden command or scene selection | Open the editor, remain on an unresponsive placeholder, or resume a previous game | The battlefield, cannon, invaders, score, lives, and level are visible |
| ENTRY-02 | Enter Level 1 or Restart | Show a three-second countdown before gameplay begins; keep movement, firing, enemy movement, and enemy fire inactive during it | Let enemies or projectiles move during the countdown | A visible `Level 1`/countdown state changes to active play when it ends |

### 6.2 Player Movement And Firing

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| PLAYER-01 | Hold left or right during active play | Move the cannon horizontally with continuous distance proportional to the hold time and stop it at the left/right battlefield bounds | Teleport, leave the battlefield, invert the direction, or keep moving without input | The cannon visibly changes position and remains inside the play area |
| PLAYER-02 | Press a fire key during active play | Spawn one visible player projectile above the cannon and let it travel upward through the play area | Do nothing, spawn a projectile that stays attached to the cannon, or spawn multiple simultaneous player projectiles | The projectile is visible and moves upward until it hits or leaves the area |

### 6.3 Invader Formation

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| FORMATION-01 | Begin any level | Start with exactly 40 active invaders in five rows of eight: one row of the high-value type, two rows of the middle-value type, and two rows of the low-value type | Start with fewer/more invaders, overlap rows, or omit a type | Forty readable invaders form a regular rectangular grid |
| FORMATION-02 | Active play continues | Move surviving invaders in a synchronized stepped cadence; the cadence becomes shorter as the number of surviving invaders decreases | Leave survivors frozen or move only one isolated invader forever | All surviving invaders change position together and visibly accelerate |
| FORMATION-03 | A moving invader reaches a left/right formation boundary | Reverse the formation direction and move every survivor down by one fixed step | Wrap to the opposite side, reverse only one invader, or descend repeatedly in the same edge frame | Direction changes and the whole formation moves down |
| FORMATION-04 | Any surviving invader reaches the lower danger line above the cannon | Enter Game Over immediately | Continue play, award a level clear, or allow the invader to move below the screen | The loss state is obvious while the player cannot continue firing |

### 6.4 Projectiles And Collisions

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| ATTACK-01 | A player projectile reaches an active invader | Remove that projectile, destroy that invader in one hit, and show its hit/deactivation feedback once | Pass through it, destroy multiple invaders, or leave an invisible active invader | The targeted invader disappears after its hit animation and the remaining count updates |
| ATTACK-02 | A player or enemy projectile reaches a barrier | Remove that projectile and leave the barrier visible and usable | Damage the player, destroy the barrier, or pass through it | The projectile disappears at the barrier |
| ATTACK-03 | An enemy projectile reaches the player or an enemy projectile remains after its shot is no longer valid | Apply one player hit on contact; remove projectiles when they leave the battlefield or the game resets | Apply repeated damage from one projectile, keep orphan projectiles in a terminal state, or let enemy projectiles damage invaders | The player hit/reset or projectile disappearance is visible |

### 6.5 Enemy Fire

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| ENEMY-01 | Active play continues | At regular random intervals, choose one surviving invader and fire a downward enemy projectile | Fire from a destroyed invader, fire while paused/counting down, or fire projectiles that never move | A visible projectile travels toward the player area |
| ENEMY-02 | Active play continues while invaders remain | Keep a fixed nonzero chance to fire during each enemy-fire interval; the chance must not depend on a nonexistent later level | Suppress enemy fire entirely, require a level increase, or create a second level | Enemy shots appear throughout the single level without changing the intended difficulty profile |
| ENEMY-03 | No input is given during active play | Continue only due to the designed enemy simulation; do not automatically clear invaders for the player | Play the player's movement or firing actions automatically or reach a player win without input | Enemies may advance/fire, but the player cannon remains input-controlled |

### 6.6 Score

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| SCORE-01 | Destroy the high/middle/low rows | Award `30`, `20`, and `10` displayed points respectively | Award the same value for all types, award on a miss, or award repeatedly for one invader | Score increases visibly by the exact amount |
| SCORE-02 | Start a new game | Show score `0`, lives `3`, level `1`, and 40 remaining invaders | Carry over score from a prior process or start with a different number | HUD values are immediately readable |
| SCORE-03 | Clear the level | Preserve the final score on the Mission Complete screen | Reset the score before the result appears or continue awarding points after victory | The result shows the same score reached during play |

### 6.7 Lives And Failure

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| LIFE-01 | An enemy projectile hits the player | Remove active projectiles, stop play, reduce lives by exactly one, and show the remaining life count | Reduce multiple lives for one hit or hide the loss | The hit animation, sound/visual feedback, and life indicator update |
| LIFE-02 | A life is lost but lives remain | After a three-second countdown, resume the same level with the remaining formation and preserved score | Advance the level, clear the formation, or leave controls disabled | Countdown returns to active play |
| LIFE-03 | Lives reach zero | Enter Game Over and stop movement, firing, enemy movement, and further score changes | Continue playing behind the overlay or allow a later level clear | A Game Over message and a visible Restart button appear |

### 6.8 First-Level Success

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| LEVEL-01 | Destroy all 40 invaders in Level 1 | Enter a Mission Complete state immediately and stop gameplay | Advance to Level 2, recreate the formation, enter Game Over, or allow more score changes | A clear success result and visible Restart button appear |
| LEVEL-02 | Mission Complete remains visible | Keep the terminal state stable with no active enemies or projectiles and no automatic restart | Spawn another formation, increase the level, or return to play without a player action | The result remains until Restart or process close |

### 6.9 Pause

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| PAUSE-01 | Press Escape during active play or a countdown | Freeze player movement, firing, enemy movement, enemy fire, collisions, and countdown progress; show a pause overlay with Resume | Continue simulation in the background or lose the current state | `Paused` feedback and a resume control appear |
| PAUSE-02 | Press Escape or activate Resume while paused | Resume from the same position, score, lives, and formation with the previous countdown time preserved | Restart the level, reset score, duplicate projectiles, or resume without visible feedback | Pause overlay disappears and the game continues |

### 6.10 HUD

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| HUD-01 | Any active level is visible | Show current score, remaining lives, current level, and remaining invaders; update each value with the actual state | Display negative lives, stale score, a different level, or an incorrect remaining count | All four values remain readable at `1280x720` |
| HUD-02 | Pause, Game Over, or Mission Complete appears | Keep the result/pause feedback visible and do not let the underlying HUD be mistaken for active play | Hide the reason for the stopped state or let HUD values continue changing | The overlay and HUD are distinguishable |
| HUD-03 | A new game starts | Reset/report level `1` and remaining-invader value `40` immediately | Show a prior count or imply that a later level exists | The HUD matches the visible formation from the first frame |

### 6.11 Restart And Reopen

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| RESTART-01 | Activate Restart from Game Over or Mission Complete | Return to a clean Level 1 with score `0`, lives `3`, 40 active invaders, no projectiles, and a three-second countdown | Retain terminal overlays, score, enemies, or projectiles | The initial-state HUD and formation return |
| RESTART-02 | Close the process and launch a new process | Return to a clean Level 1 with score `0`, lives `3`, and no saved gameplay progress | Resume the previous level, score, enemies, or terminal state | The new process begins at the same initial state |

### 6.12 Visual And Gameplay Quality

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| VISUAL-01 | Supplied images/audio are available | Use recognizable cannon, invader, projectile, barrier, and background identities from the supplied material | Replace a required identity with an unrelated sprite or leave a missing-resource checkerboard | The battlefield reads as a coherent fixed shooter |
| VISUAL-02 | Player and enemy projectiles are on screen | Make their direction/identity visually distinct | Use the same ambiguous marker for both sides | The player can tell incoming danger from their own shot |
| VISUAL-03 | Normal play is observed | Keep sprites and text aligned, readable, and inside the `1280x720` viewport | Stretch, crop, or cover required HUD/controls | No broken or unreadable required element |
| QUALITY-01 | Launch and play | Remain responsive and stable through the single level, hit/reset paths, pause, Restart, and Reopen | Freeze, crash, hang, or dead-end the main flow | Every required state remains reachable |
| QUALITY-02 | Play with ordinary keyboard/mouse input | Reach every required action through visible controls or documented keys | Require hidden keyboard combinations, internal calls, or debug controls | Inputs produce immediate visible feedback |
| QUALITY-03 | Game Over or Mission Complete is visible | Stop gameplay actions; only Retry/Restart and close controls remain effective | Let movement, enemy fire, scoring, or collisions continue behind the result | The terminal state is stable |

## 7. Success, Failure, And Multi-Stage Flow

### 7.1 Success

| Requirement | Steps | Condition | Result |
|---|---|---|---|
| `LEVEL-01` | Clear the initial formation | All 40 invaders in Level 1 are destroyed while at least one life remains | Mission Complete with final score and Restart |

### 7.2 Failure

| Requirement | Condition | Result | Retry |
|---|---|---|---|
| `LIFE-03`, `FORMATION-04` | Lives reach zero or a surviving invader reaches the lower danger line | Game Over, simulation stops | Restart returns to clean Level 1 |

### 7.3 Multi-Stage Flow

| Stage | Required IDs | Summary | Must not appear early |
|---|---|---|---|
| Entry | `ENTRY-01`, `ENTRY-02`, `FORMATION-01` | Initial formation and countdown | Success, Game Over |
| Active level | `PLAYER-01`–`QUALITY-03` | Play until all invaders are cleared or a failure occurs | Mission Complete before all 40 are resolved |
| Result | `LEVEL-01`, `LEVEL-02` | Mission Complete after the final invader | Level 2, resumed play |

## 8. Interface And Feedback

| Requirement | Information | Update timing | What the player must distinguish |
|---|---|---|---|
| `HUD-01` | Score, lives, level, remaining invaders | Immediately on every change and at level start | Current objective and remaining danger |
| `HUD-02` | Pause, Game Over, Mission Complete | On state transition | Whether play is active, paused, won, or lost |
| `PAUSE-01` | Pause and Resume | On Escape/Resume input | Frozen gameplay versus active gameplay |
| `VISUAL-02` | Player and enemy projectiles | While in flight | Own shot versus incoming shot |

## 9. Restart, Reopen, And Save

| Scenario | Requirement | Reset | Preserve | Final state |
|---|---|---|---|---|
| Restart after result | `RESTART-01` | Level, score, lives, formation, projectiles, overlays | Nothing gameplay-related | Clean Level 1 |
| Close and reopen | `RESTART-02` | All gameplay state | Nothing | Clean Level 1 |

## 10. Existing Functionality To Preserve

Not applicable. This is a complete reconstruction.

## 11. Material And Content Requirements

| Requirement | Material | Hard requirement | Gameplay use | Equivalent replacement |
|---|---|---|---|---|
| `VISUAL-01` | Supplied enemy, cannon, projectile, barrier, background, and sound files | Yes | Make the fixed-shooter identities and feedback recognizable | No for the supplied roles; proportional cropping/scaling and animation timing may vary |



## 12. Dashboard Naming Tables And Control Scheme

The dashboard must follow `DASHBOARD_SPEC.md`. Positions use viewport pixels in the fixed `1280x720` space, origin at top-left, x right, y down.

### 12.1 Numeric Slots

| Slot | Meaning | Requirement |
|---|---|---|
| `score` | Current displayed score | `SCORE-01`, `SCORE-02` |
| `lives` | Remaining player lives | `LIFE-01`–`LIFE-03` |
| `level` | Current level, always `1` for this task | `LEVEL-01`, `HUD-03` |
| `invaders_remaining` | Active invaders not yet destroyed | `FORMATION-01`, `HUD-01` |
| `player_projectiles` | Visible player projectiles | `PLAYER-02`, `ATTACK-01` |
| `enemy_projectiles` | Visible enemy projectiles | `ENEMY-01`, `ATTACK-03` |

### 12.2 Entities And Clickable Targets

| Kind | Meaning | Allowed states | Requirement |
|---|---|---|---|
| `player` | Player cannon | `active`, `hit`, `lost` | `PLAYER-01`, `LIFE-01` |
| `invader` | Active enemy | `active`, `hit` | `FORMATION-01`, `ATTACK-01` |
| `player_projectile` | Upward player shot | `active` | `PLAYER-02` |
| `enemy_projectile` | Downward enemy shot | `active` | `ENEMY-01` |
| `barrier` | Protective barrier | `intact` | `ATTACK-02` |
| `restart_button` | Restarts the game | — | `RESTART-01` |
| `resume_button` | Resumes from pause | — | `PAUSE-02` |
| `fullscreen_button` | Toggles fullscreen from pause | — | `PAUSE-01` |

### 12.3 Control Scheme

| Item | Value |
|---|---|
| Movement | Continuous horizontal movement while Left/A or Right/D is held |
| Fire | W, Up, Space, or Enter |
| Pause | Escape |
| Result action | Visible Restart button |

## 13. Implementation Boundaries

- Section 6 is the only source of game-specific acceptance requirements.
- The dashboard is a read-only observation surface. It must not move, fire, pause, reset, score, or force a result.
- Internal class names, scene hierarchy, algorithms, collision layers, and component choices are free.
- Exact engine entry, paths, input map, material locations, and dashboard transport are defined by `TOOLCHAIN-en.md` and `BENCHMARK_MANIFEST.json`.

## 14. Requirement Index

| ID | Summary |
|---|---|
| `ENTRY-01` | Playable entry |
| `ENTRY-02` | Three-second countdown |
| `PLAYER-01` | Horizontal movement |
| `PLAYER-02` | Fire one upward projectile |
| `FORMATION-01` | Forty-invader grid |
| `FORMATION-02` | Synchronized speed-up |
| `FORMATION-03` | Edge reversal and descent |
| `FORMATION-04` | Lower-danger-line failure |
| `ATTACK-01` | Player projectile destroys invader |
| `ATTACK-02` | Barrier blocks projectiles |
| `ATTACK-03` | Player hit and projectile cleanup |
| `ENEMY-01` | Random enemy fire |
| `ENEMY-02` | Level-based aggression |
| `ENEMY-03` | No self-playing player |
| `SCORE-01` | Exact enemy values |
| `SCORE-02` | Clean initial HUD |
| `SCORE-03` | Score/lives across levels |
| `LIFE-01` | Lose one life |
| `LIFE-02` | Resume after nonfatal hit |
| `LIFE-03` | Game Over |
| `LEVEL-01` | Mission Complete after clearing the first level |
| `LEVEL-02` | Stable post-victory state |
| `PAUSE-01` | Pause |
| `PAUSE-02` | Resume |
| `HUD-01`–`HUD-03` | HUD truth and readability |
| `RESTART-01`–`RESTART-02` | Restart and Reopen |
| `VISUAL-01`–`VISUAL-03` | Material and visual quality |
| `QUALITY-01`–`QUALITY-03` | Stability, reachability, terminal behavior |
