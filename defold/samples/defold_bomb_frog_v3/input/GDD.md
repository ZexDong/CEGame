# Bomb Frog: Twin Chambers

Public input revision: `v3-frozen-20261010`  
Benchmark ID: `defold.bomb_frog.v3`  
Status: frozen public acceptance boundary

## 1. One-sentence task

Create a two-chamber grid-action campaign in which a frog uses limited bombs to reveal treasure,
defeat patrolling enemies, survive orthogonal blasts, clear both fixed arenas in sequence, and
break then defeat an armored ghost with two separate explosions.

## 2. Scope

Create one deterministic campaign containing exactly two fixed chambers. The complete loop is
menu and instructions → chamber 1 → frozen chamber-clear transition → chamber 2 → campaign success
or failure → retry or return to menu. Random maps, online features, bosses, permanent progression,
and saved mid-campaign progress are out of scope.

This v3 task deliberately extends the v2 single-arena task with a real stage boundary, state carried
between stages, a different second layout, and a two-hit armored enemy. These are public gameplay
requirements, not private evaluator tricks.

## 3. Starting state

The public input contains a minimal buildable Defold project, normal keyboard and mouse bindings,
visual references, and the read-only Dashboard transport. It intentionally contains no target
menu, chamber, player, bombs, enemies, treasure, HUD, transition, or result. Implement the game
inside `starter_project/`.

## 4. Player goal and flow

```text
menu → optionally read instructions → start a new campaign in chamber 1
→ move one orthogonal grid cell at a time and place limited bombs
→ reveal and collect 3 treasures and defeat 2 normal enemies
→ CHAMBER CLEAR: frozen Continue / Restart Campaign / Return to Menu choice
→ Continue into a different chamber 2 with carried health and exactly 8 bombs
→ reveal and collect 3 treasures, defeat 2 normal enemies,
   and hit the armored ghost with two different explosions
→ collect 6/6 campaign treasures and defeat 5/5 campaign enemies: success
   | lose all health or exhaust the bombs still required to finish: failure
→ retry from chamber 1 or return to menu
```

## 5. Controls

| Action | Normal input | Response |
|---|---|---|
| Move | Arrow keys or WASD | Move one legal orthogonal grid cell; holding repeats legal steps |
| Place bomb | Space | Place one bomb on the current cell when allowed |
| Confirm selection | Enter or left click | Activate the selected or clicked visible choice |
| Pause / resume | Escape | Toggle pause during play; close instructions back to menu |
| Restart campaign | R or visible restart choice | Start a clean campaign in chamber 1 when available |
| Quit from menu | Q or visible quit choice | Exit from the title menu |

## 6. Numbered requirements — authoritative acceptance source

| Requirement | Formal requirement |
|---|---|
| `BF3-ENTRY-01` | Launch into a title menu showing `Bomb Frog: Twin Chambers` or an equivalent title and simultaneous visible, operable choices for Start Campaign, Instructions, and Quit. Instructions identify movement, Space, Escape, the two-chamber goal, health/resource failure, and that an armored ghost requires two separate explosions. Instructions can return without starting or changing a campaign. |
| `BF3-CHAMBER-01` | A new campaign starts in chamber 1 with `run_serial` incremented, chamber index 1/2, a fixed 7 × 5 active arena embedded in the public 9 × 7 coordinate space, exactly one player at 5 health, 6 inventory bombs, 2 normal enemies, 6 destructible obstacles, and 3 hidden treasures. Exactly three obstacles contain one treasure each. Initial positions never randomize. With accurate bombing and no wasted resources, at most 5 bombs are needed to reveal all three treasures and defeat both enemies. |
| `BF3-CHAMBER-02` | Continuing after chamber 1 creates a different fixed chamber 2 using the full 9 × 7 arena. It preserves the current health, sets inventory to exactly 8 bombs, keeps the same `run_serial`, and creates 8 destructible obstacles, 3 hidden treasures, 2 normal enemies, and 1 armored enemy. Old chamber entities and IDs disappear and are not reused. With accurate bombing and no wasted resources, at most 7 bombs are needed to reveal all treasures and defeat all three enemies. |
| `BF3-MOVE-01` | During play, one movement press changes the frog by exactly one Manhattan-adjacent cell and leaves it grid-aligned. Holding may repeat one-cell steps. The frog cannot move diagonally, skip cells, leave the active chamber, or pass through solid walls, intact obstacles, active bombs, effective explosions, or enemy-occupied cells. A blocked move leaves its cell unchanged and gives visible feedback. |
| `BF3-BOMB-01` | Pressing Space on a cell without an active bomb while inventory is above zero places exactly one bomb and immediately reduces inventory by one. The player can leave that cell. One press never places multiple bombs; an occupied cell cannot receive another bomb; zero inventory never creates a bomb or a negative count and gives visible rejection feedback. |
| `BF3-FUSE-01` | A bomb explodes after 2.0 seconds of real unpaused play and is removed. Pause, chamber-clear, success, and failure freeze all fuse time. The effective blast cells remain visibly distinguishable for a short interval. No delayed explosion or damage occurs after a frozen terminal or transition state begins. |
| `BF3-BLAST-01` | Each explosion considers exactly its own cell plus one cell up, down, left, and right, never diagonals. A solid wall blocks damage in its cell and every cell behind it on that direction. An unblocked destructible obstacle is removed. An unblocked player or enemy in an effective cell is hit once by that explosion. One explosion never damages the same object twice. Solid walls cannot be destroyed. Chain reactions are optional and receive no separate credit. |
| `BF3-TREASURE-01` | Destroying a treasure-bearing obstacle reveals one visible treasure in that cell. Entering the cell collects it once, increments both chamber and campaign progress by one, and removes it. Treasure cannot be collected while hidden, remotely, twice, while paused, during chamber-clear, or after a result. Empty obstacles reveal nothing. |
| `BF3-TREASURE-02` | In each chamber, every treasure is exactly hidden, revealed, or collected; the three counts sum to three. Chamber progress resets only when entering the next chamber or restarting the campaign. Campaign treasure progress is monotonic from 0 through 6 and equals the sum collected across completed/current chambers. HUD, arena, and Dashboard agree. |
| `BF3-ENEMY-01` | Normal enemies move along fixed, repeatable orthogonal routes and never enter blocked, occupied, or out-of-arena cells. Contact causes one damage event. One unblocked explosion kills a normal enemy once. Paused, chamber-clear, and result states stop enemies. Dead enemies no longer move, damage, appear alive, or count again. |
| `BF3-ARMOR-01` | Chamber 2 has exactly one visibly armored ghost. The first unblocked explosion instance changes it from `armored` to visibly `exposed` without reducing `enemies_alive` or campaign defeated progress. A later, different explosion instance kills the exposed ghost once. A single explosion cannot both break armor and kill it, repeated contact does not change armor, and chamber transition/restart restores its initial armored state. |
| `BF3-DAMAGE-01` | A valid enemy-contact or unblocked blast hit reduces health by exactly one and starts 1.0 second of invulnerability. Further hits during that interval do not reduce health, while movement remains available. Health never falls below zero. Pause and chamber-clear freeze invulnerability time. HUD and player feedback match the true state. The player's own bomb can damage the player. |
| `BF3-STAGE-01` | Chamber 1 enters a frozen chamber-clear state only after its treasure progress is 3/3 and remaining enemies are 0/2. It must not enter final `won`. The overlay clearly states `Chamber Clear` or equivalent and simultaneously offers Continue, Restart Campaign, and Return to Menu. While shown, movement, bombing, enemies, fuses, explosions, damage, collection, and timers do not advance. Continue performs exactly the transition in `BF3-CHAMBER-02`. |
| `BF3-WIN-01` | Final success occurs only after chamber 1 was completed and chamber 2 reaches 3/3 chamber treasures, 0/3 living enemies, 6 campaign treasures, and 5 campaign enemies defeated. Resolve the final explosion, treasure, armor, and enemy effects before judging. Success freezes gameplay, displays `Campaign Complete` or equivalent with final progress, and offers Retry and Return to Menu. Completing only one objective or only chamber 1 never wins. |
| `BF3-LOSE-01` | Before final success, failure occurs when health reaches zero, or when inventory is zero, no active bomb remains, and a living enemy or hidden treasure still requires bombing. The last active bomb always resolves before resource failure. If all enemies are dead and all treasures are revealed, zero bombs still permits movement collection. Chamber-clear and success take precedence if their conditions are completed by that final resolution. Failure freezes gameplay, shows the correct reason and progress, and offers Retry and Return to Menu. |
| `BF3-HUD-01` | During play and pause, the HUD continuously shows chamber number, health, bombs, chamber treasure progress, chamber enemies remaining, and campaign totals. In chamber 2 it also makes the armored/exposed enemy state understandable. Values update with the same real state change and never obscure the player or important cells. |
| `BF3-PAUSE-01` | Escape during either chamber opens exactly one visible pause overlay with Resume, Restart Campaign, and Return to Menu. Escape again or Resume continues. While paused, every gameplay object and timer named above is frozen. Rapid repeated Escape presses leave exactly one overlay and the phase implied by press parity. |
| `BF3-RESULT-01` | Chamber-clear, final success, and failure are visually distinct and remain until a player choice. Their outcome, required progress, and available choices are simultaneously visible and operable. Gameplay beneath any overlay does not respond. |
| `BF3-VISUAL-01` | At 1280 × 720, present a coherent pixel or arcade-style arena. Frog, solid wall, obstacle, bomb, orthogonal blast, normal enemy, armored enemy, exposed enemy, and revealed treasure have independent readable silhouettes or stable colors. The two chambers are visibly distinguishable. Do not use semantic debug labels, unstyled diagnostic boxes, or an uncropped sprite sheet as final game objects. Equivalent original artwork is allowed. |
| `BF3-RESET-01` | Restart from pause, chamber-clear, success, failure, or chamber 2 creates the exact clean chamber-1 campaign state, increments `run_serial`, clears all previous entities/effects/overlays and campaign totals, and restores 5 health and 6 bombs. Two consecutive restarts produce the same initial state. |
| `BF3-REOPEN-01` | Closing and relaunching from any state, including chamber 2, returns to the initial title menu with `run_serial` zero and no campaign entities or progress restored. |
| `BF3-DASHBOARD-01` | Implement the read-only Dashboard using the exact slots, entity kinds, states, stable IDs, cells, targets, and phase mapping in Section 9 and `naming-tables.json`. It reports the authoritative state used by movement, collision, rendering, HUD, transitions, and results. |
| `BF3-DASHBOARD-02` | Dashboard targets use the real visible click rectangles. It never reports hidden treasure positions, future enemy routes, or a precomputed solution; never accepts input; and never changes timers, objects, resources, armor, transitions, or results when observed. Revision advances only when reported payload changes. |

All games also obey `COMMON_BASELINE.md`; it is not repeated as game-specific requirements.

## 7. Outcome and lifecycle rules

- Chamber 1 completion is an intermediate frozen boundary, not final success.
- Chamber 2 continues the same campaign identity and health but uses the explicit resource reset in
  `BF3-CHAMBER-02`.
- Any restart begins a new campaign from chamber 1; a process reopen returns to the menu.
- Failure, stage transition, and final success remain stable until a normal player choice.

## 8. Visual references and permitted content

The images in `reference_images/` come from the MIT-licensed reference game and explain menu,
controls, grid readability, bombing, and result hierarchy. They are documentation references, not
importable final sprites. The v3 second chamber and armor states must be created from licensed,
original, or programmatic presentation. The formal boundary remains `BF3-VISUAL-01`.

## 9. Dashboard naming tables and control scheme

The game must implement `DASHBOARD_SPEC.md`; this section mirrors `naming-tables.json`.

### 9.1 Numeric slots

| Slot | Meaning |
|---|---|
| `run_serial` | Monotonic campaign number; zero before a campaign starts |
| `chamber_index`, `chamber_total` | Current chamber (1 or 2) and fixed total 2; zero before play |
| `chamber_width`, `chamber_height` | Active arena dimensions: 7×5 or 9×7 |
| `stage_clear` | 1 only while the chamber-1 clear overlay is active |
| `completed_chambers` | 0, 1, or 2 completed chambers |
| `hearts`, `bombs_remaining` | Current campaign health and chamber inventory |
| `active_bomb_count`, `active_explosion_count` | Currently active bombs and blast effects |
| `invulnerability_milliseconds` | Remaining protection time |
| `treasures_hidden`, `treasures_revealed`, `treasures_collected`, `treasure_total` | Current chamber treasure partition and total |
| `enemies_alive`, `enemy_total` | Current chamber living and initial enemy counts |
| `armored_enemies`, `exposed_enemies` | Current living armored and exposed counts |
| `campaign_treasures_collected`, `campaign_enemies_defeated` | Monotonic campaign totals, maxima 6 and 5 |
| `loss_reason_code` | 0 outside failure, 1 health exhaustion, 2 bomb-resource exhaustion |

### 9.2 Entities

All cells use the public 9 × 7 coordinate space with `(0,0)` at bottom-left. Chamber 1 uses only
its declared 7 × 5 active rectangle. Each entity has a stable ID within one campaign; IDs are not
reused across chambers.

| Kind | Allowed state |
|---|---|
| `player` | `normal`, `invulnerable` |
| `solid_wall` | `solid` |
| `destructible_obstacle` | `intact` |
| `bomb` | `fuse_active` |
| `explosion` | `active` |
| `enemy` | `normal`, `armored`, `exposed` |
| `treasure` | `revealed` |

Hidden treasure has no entity and no reported position. Collected treasure is no longer present.

### 9.3 Clickable targets

Existing menu, instructions, pause, and result targets remain. Chamber-clear additionally exposes
`stage_continue_button`, `stage_restart_button`, and `stage_menu_button`. Rectangles use the real
1280 × 720 game view with bottom-left origin.

### 9.4 Phase mapping

| Situation | Dashboard phase and discriminator |
|---|---|
| Loading | `not_ready` |
| Title menu or instructions | `menu` |
| Active chamber | `playing` |
| Ordinary pause | `paused`, `stage_clear == 0` |
| Chamber-clear transition | `paused`, `stage_clear == 1` |
| Campaign completed | `won` |
| Health/resource failure | `lost` |

Movement uses `discrete_keys_with_hold_repeat`. Arrow keys/WASD move, Space places a bomb, Enter
confirms, Escape pauses, and left click activates visible targets. Both layouts are deterministic.

## 10. Submission boundary and self-check

Submit the completed `starter_project/` with normal keyboard/mouse gameplay and a truthful
read-only Dashboard. Do not include a private evaluator, Gold implementation, hidden coordinates,
precomputed solution, or result-forcing command.

- Build, start, close, and reopen at the menu.
- Play both chambers to final success with normal input.
- Verify chamber-1 clear cannot become final success and that Continue preserves health/run ID.
- Verify the armored ghost needs two different explosion instances.
- Verify health failure, resource failure, pause, every restart origin, and chamber-2 reopen.
- Verify blocked movement, wall shielding, protection against a second hit, and one-time collection.
- Verify Dashboard format, visible truthfulness, hidden-information boundary, and input causality.
