# Ape Tower Defense Fixed v4: Grassland Boss and Tower Repair Task

> Red Dino and Green Dino attack range is fixed at `102 px`, matching the Level 1 Explosive range. This document defines only the behavior, feedback, and experience the player should ultimately receive; it does not prescribe nodes, scripts, algorithms, collision schemes, route data, or other implementation details.

## 1. Task in One Sentence

Create a Grassland tower defense game that retains the core experience of the original while adding an attack-and-repair layer: the player drags and drops four types of towers onto continuous open grass outside the stone road, maintains towers that can be damaged by Red Dinos and the final Green Dino boss, and survives ten automatic waves before the larger boss is resolved.

## 2. Scope of This Task

### 2.1 Required

| Requirement IDs | Content |
|---|---|
| `ENTRY-01`–`STATE-02` | Menu, Grassland entry, and initial state |
| `MAP-01`–`ROUTE-02` | Consistent map, route, and build space |
| `BUILD-01`–`BUILD-06` | True dragging and free placement on continuous grass |
| `TOWER-01`–`TOWER-04`, `TOWER_HP-01`–`TOWER_HP-03`, `ECON-01`–`ECON-02` | Four tower roles, prices, tower HP, health bars, destruction, and build economy |
| `WAVE-01`–`WAVE-05`, `ENEMY-01`, `BOSS-01` | Ten automatic waves, exact Dino compositions, and the Wave 10 Green Dino boss |
| `COMBAT-01`–`COMBAT-05`, `ENEMY_ATTACK-01`–`ENEMY_ATTACK-04` | Movement, attacks in both directions, projectiles, damage, kills, and leaks |
| `MANAGE-01`, `UPGRADE-01`, `SELL-01`, `REPAIR-01`–`REPAIR-02` | Selection, upgrading, selling, and the 20-Gold repair operation |
| `FAIL-01`–`REOPEN-01` | Victory and defeat, freezing, retrying, returning to the menu, and closing/reopening |
| `HUD-01`–`ASSET-05` | Interface, feedback, and in-game/procedural visual assets |
| `QUALITY-01`–`QUALITY-06` | General playability and stability |

### 2.2 Excluded

| Scope | Description |
|---|---|
| Desert map | Only Grassland is completed in this task; a two-map campaign is not part of the requirements |
| Online features and persistent progression | No accounts, leaderboards, achievements, store, advertisements, in-app purchases, or battle saves |
| Non-core presentation | Audio, complex particles, and pixel-perfect replication of the original UI are not required |

## 3. Starting State

| Item | Starting State | Corresponding Requirement |
|---|---|---|
| Project | Launchable Godot showcase project | `QUALITY-01` |
| Gameplay | No playable target tower-defense flow yet | All gameplay requirements in this task |
| Public content | GDD, tool instructions, task assets, procedural-effect mapping, and licenses | `ASSET-01`–`ASSET-05` |
| Entry | Only a placeholder screen that does not constitute a proper menu | `ENTRY-01` |

## 4. Player Goal and Complete Flow

### 4.1 Player Goal

The player protects the base on the left side of Grassland, placing different towers in grass areas of their choice, watching their HP as Red Dinos and the Green Dino boss shoot at them, and spending `20 Gold` to repair damaged towers. If base HP reaches zero, the player loses; if the exact tenth wave, ending with its single larger Green Dino boss, is fully resolved while the base remains alive, the map is completed (`BUILD-02`, `TOWER_HP-01`–`TOWER_HP-03`, `WAVE-03`, `BOSS-01`, `REPAIR-01`, `FAIL-01`, `SUCCESS-01`).

### 4.2 Complete Player Flow

```text
Open the game and click Start
→ Select Grassland
→ See 200 Gold, 30/30 HP, and a 15-second first-wave countdown
→ Hold down on a tower type in the shop, drag it onto open grass, and release
→ The first wave starts automatically
→ Enemies move along the stone road, towers attack automatically, and kills produce Gold
→ Red Dinos keep walking while shooting small red projectiles at nearby towers; each hit removes 1 tower HP
→ Select a damaged tower and spend 20 Gold to restore it to full HP, or continue building, upgrading, and selling
→ Automatically proceed through ten exact waves
→ Resolve the single, larger Green Dino boss at the end of Wave 10 while it keeps walking and shoots large red projectiles that remove 5 tower HP per hit
→ Map Complete when the base survives and the tenth wave has been fully resolved
```

Corresponds to: `ENTRY-01`, `ENTRY-02`, `STATE-01`, `STATE-02`, `BUILD-01`, `TOWER_HP-01`–`TOWER_HP-03`, `WAVE-01`–`WAVE-05`, `ENEMY-01`, `BOSS-01`, `COMBAT-01`–`COMBAT-05`, `ENEMY_ATTACK-01`–`ENEMY_ATTACK-04`, `REPAIR-01`, `SUCCESS-01`.

Failure recovery flow:

```text
Insufficient defenses
→ An enemy reaches the base and reduces HP
→ Game Over when HP reaches zero, and combat stops
→ Click Restart
→ Return to a clean Grassland with 200 Gold, 30/30 HP, the first-wave countdown, no towers, and no enemies
```

Corresponds to: `COMBAT-05`, `FAIL-01`, `TERMINAL-01`, `RESTART-01`, `RESTART-02`.

### 4.3 Core Loop

```text
Observe the road and defenses
→ Drag and drop new towers or manage existing towers
→ Automatic waves progress
→ Enemies are killed or leak through
→ Gold, base HP, tower HP, wave, and remaining enemy count update
→ Repair damaged towers for 20 Gold or adjust the defenses
```

Corresponds to: `BUILD-01`–`BUILD-06`, `TOWER_HP-01`–`TOWER_HP-03`, `WAVE-01`–`WAVE-05`, `COMBAT-01`–`COMBAT-05`, `ENEMY_ATTACK-01`–`ENEMY_ATTACK-04`, `MANAGE-01`, `UPGRADE-01`, `SELL-01`, `REPAIR-01`–`REPAIR-02`, `HUD-01`–`HUD-03`.

## 5. Player Controls

| Action | Where Used | Result Summary | Corresponding Requirement |
|---|---|---|---|
| Left-click | Start, Grassland, a placed tower, Upgrade, Sell, Repair (20 Gold), Restart, Main Menu | Completes one explicit interface or management action | `ENTRY-01`, `ENTRY-02`, `MANAGE-01`, `UPGRADE-01`, `SELL-01`, `REPAIR-01`, `RESTART-01`, `MENU-01` |
| Hold the left mouse button, move continuously, and release | Drag a tower from a tower card to the battlefield | Builds or rejects the tower at the release position | `BUILD-01`–`BUILD-06` |
| Wait | Countdowns, waves, movement, and combat | The game progresses automatically | `WAVE-01`–`WAVE-03`, `COMBAT-01`–`COMBAT-05` |

The keyboard is not required to complete the main flow.

## 6. Numbered Requirements: Sole Acceptance Criteria

### 6.1 Entry and Initial State

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| ENTRY-01 | Open a new process; the player clicks the visible Start | Enter map selection and show Grassland | Remain on an unresponsive placeholder screen | Start and Grassland are visible, readable, and clickable; a new process begins at the menu |
| ENTRY-02 | Click Grassland in map selection | Enter a fully playable Grassland | Show only a static preview or open another map | The map, shop, HUD, base, and first-wave countdown are all available at the same time |
| STATE-01 | Immediately after entering or after Restart | Current Gold is exactly `200` | Display it late or carry over Gold from the previous game | The HUD immediately displays the same value |
| STATE-02 | Immediately after entering or after Restart | Base HP is exactly `30/30`, with no towers, no enemies, and the first wave not yet started | Show a different maximum only after the first damage; retain objects from the previous game | The HUD immediately displays `30/30` and the first-wave countdown |

### 6.2 Map, Route, and Continuous Build Space

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| MAP-01 | Observe Grassland | The provided Grassland image is the complete main battlefield visual and retains recognizable proportions; the relationships among the stone road, grass, and base are clear | Obvious nonuniform distortion, mirroring, rotation, misalignment, or use only as a background unrelated to gameplay | The route, enemies, towers, and build feedback are consistent with the same map |
| MAP-02 | Observe spatial relationships on the battlefield | The visible stone road corresponds to the enemy route and the road's no-build area; clearly open grass corresponds to continuous buildable space | The map, route, and no-build space are globally offset from one another; only a few fixed tower positions are allowed | The relationships remain consistent before and after Restart |
| ROUTE-01 | Observe one enemy's complete journey | The enemy passes through, in order: the lower entrance, the lower road to the right, the loop on the right, the middle road to the left, the lower-left loop, the central vertical road upward, the upper loop, the road to the left, and the base on the left | Cut straight across grass, skip major road sections, join the wrong road section at intersections, teleport, or disappear early | The journey is continuously visible; the route direction is always the same |
| ROUTE-02 | An enemy approaches the endpoint | A leak is resolved only after the enemy actually reaches the base on the left | Deduct HP early in the middle of the road, deduct HP repeatedly after arrival, or grant a kill reward for a leak | The enemy disappears and HP updates in sync |
| BUILD-01 | The player holds the left mouse button on a tower card, moves at least `7 px`, and releases | A recognizable tower preview follows the pointer after the movement threshold; success/rejection is determined only at release | Build by merely clicking the card/destination, before release, or through a hidden entry point | Continuously show green valid/red invalid placement feedback and clear preview/input state after release |
| BUILD-02 | An affordable tower is released on open grass; its circular `32 px` radius footprint is entirely on the battlefield and touches no road, base, obstruction, or tower | Build exactly one Level 1 tower of the dragged type with its center within `4 px` of release; in the default viewport a valid center is within `x=[32,1120]`, `y=[96,522]` | Snap to a distant preset point, build the wrong type, or duplicate multiple towers | The full-HP placed tower, attached bar, and Gold update immediately |
| BUILD-03 | The player tests multiple scattered clear grass locations | At least three valid centers separated pairwise by at least `150 px` work; within one continuous grass area, separate clean runs can build at two valid release points `20–60 px` apart without snapping both to one anchor | Allow only a few anchors, slots, pads, or fixed grid points | The same visible conditions produce consistent results before and after Restart |
| BUILD-04 | A tower's `32 px` radius footprint touches any straight section, turn, intersection, or loop of the stone road | Reject the build; tower count and Gold remain unchanged | Check only the center point and allow the tower body to overlap any road section | Feedback while dragging or upon release is clear; the entire road consistently forbids building |
| BUILD-05 | A new tower center would be less than `67.2 px` from an existing living tower center | Reject the overlap; existing tower state, tower count, and Gold remain unchanged | Stack/replace towers or deduct a cost | A footprint freed by destruction or sale becomes eligible again |
| BUILD-06 | The center is less than `76 px` from the base; the footprint intersects a visible tree/rock/bush body; Gold is insufficient; release is outside the battlefield/on UI; or the `7 px` drag threshold was not completed | Do not build or deduct Gold; never allow negative Gold; clear preview/input state | Partially deduct, leave a preview stuck, or spawn on UI/outside the field | The next complete valid drag still works |

### 6.3 Four Towers and Build Economy

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| TOWER-01 | The shop is visible; the player purchases Gatling Gun | Gatling costs `50` and provides steady, rapid, single-target attacks at medium range | Use the wrong price, rename it Heavy, or merely reskin it without a single-target role | The card, placed tower, details, and attack behavior are consistent |
| TOWER-02 | The shop is visible; the player purchases Flamethrower | Flamethrower costs `70` and provides high-frequency piercing attacks that can affect multiple valid enemies along the same road section | Use the wrong price or reduce it to an ordinary slow single-target tower | Flame/projectile or equivalent feedback makes its role recognizable |
| TOWER-03 | The shop is visible; the player purchases Raygun | Raygun costs `30` and provides slower but longer-range ray attacks | Use the wrong price, omit a visible ray, or give it the same role as Gatling | The ray and long-distance hit are recognizable |
| TOWER-04 | The shop is visible; the player purchases Explosive | Explosive costs `70` and provides short-range area attacks that can damage multiple valid enemies within the area | Use the wrong price or reduce it to a long-range single-target tower | An explosion or equivalent area-effect feedback is recognizable |
| TOWER_HP-01 | A tower is built or upgraded | Set its current/maximum HP from the fixed table below. On upgrade, increase current HP by exactly the increase in maximum HP, preserving all damage already taken | Give towers infinite health, silently reset a damaged tower to full on upgrade, or use a maximum inconsistent with its type and level | The tower details and its world-space health bar immediately agree with the same current/maximum HP values |
| TOWER_HP-02 | A living tower is visible or takes damage | Show a health bar directly above it whose fill is `current HP / maximum HP`, clamped from empty to full and updated on the same frame as damage, repair, or upgrade | Show only an enemy health bar, let the fill lag behind the real value, display a negative fill, or associate the bar with another tower | A dark backing and a green fill are visible; the fill changes toward empty as tower HP falls |
| TOWER_HP-03 | A tower's HP reaches `0` | Destroy and remove that tower exactly once, clear its selection and range indicator, cancel projectiles targeting it, award no refund, and make its former grass footprint buildable again | Leave an operational zero-HP tower, allow repair/sell after destruction, deduct Gold, or damage another tower | The tower and health bar disappear together and any open details panel for it closes |
| ECON-01 | `BUILD-02` succeeds | Deduct the exact listed price of the built tower exactly once | Deduct the cost repeatedly after a delay or deduct the wrong tower's price | The Gold HUD updates immediately |
| ECON-02 | Any of `BUILD-04`–`BUILD-06` is rejected | Do not build a tower or deduct a cost, and Gold does not become negative | Charge for a rejected placement or generate an inoperable object | The balance and tower count remain correct, and the player can continue operating |

Tower durability is fixed as follows:

| Tower | Level 1 max HP | Level 2 max HP | Level 3 max HP |
|---|---:|---:|---:|
| Gatling Gun | 80 | 110 | — |
| Flamethrower | 100 | 130 | 160 |
| Raygun | 70 | 95 | 120 |
| Explosive | 120 | 160 | 200 |

To remain aligned with the `game-6/PublicStartPacH` baseline, tower offense is also fixed. Values are listed from Level 1 through maximum level; attack frequency is `1 / attack interval`:

| Tower | Damage | Range (px) | Attack interval (s) | Additional area |
|---|---|---|---|---|
| Gatling Gun | `1.20 / 1.75` | `145 / 153` | `0.32 / 0.30` | Single target |
| Flamethrower | `0.62 / 0.82 / 0.92` | `132 / 142 / 150` | `0.18 / 0.17 / 0.165` | Piercing flame half-width `24 / 26 / 27 px` |
| Raygun | `3.20 / 4.10 / 5.00` | `220 / 234 / 248` | `1.05 / 1.00 / 0.95` | Single target |
| Explosive | `3.10 / 3.90 / 4.70` | `102 / 110 / 118` | `1.08 / 1.02 / 0.96` | Explosion radius `62 / 66 / 70 px` |

The four towers' prices, level caps, offensive values, maximum HP, and player-recognizable combat roles are fixed. Implementations may choose internal data structures but may not substitute different player-observable values.

### 6.4 Automatic Waves and Enemies

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| WAVE-01 | Immediately after entering Grassland | Display a `15`-second first-wave countdown, after which Wave 1 starts automatically | Require clicking Start Wave; fail to start when the countdown ends | The HUD displays the countdown, then switches to the current wave and remaining enemy count |
| WAVE-02 | All enemies in the current wave have been killed or leaked, the base remains alive, and Wave 10 has not been completed | Display an `8`-second between-wave countdown, after which the next wave starts automatically | Overlap waves, skip wave numbers, or start a wave repeatedly | Towers can still be built and managed between waves |
| WAVE-03 | Play through a complete campaign | There are exactly `10` waves; total enemy counts per wave remain, in order, `8, 11, 14, 16, 19, 22, 25, 28, 30, 33`; enemies in the same wave appear one by one approximately every `0.35` seconds | Complete before Wave 10, spawn enemies infinitely, or differ from a published total | The HUD's remaining count includes enemies allocated to the current wave that have not yet spawned, including the unspawned boss |
| WAVE-04 | Enemy types progress by stage | Use the fixed per-wave Dino composition and deterministic ordering below. Waves 1–3 contain only Red; Waves 4–6 contain Red and Blue; Waves 7–9 contain Red, Blue, and Yellow; Wave 10 contains exactly 32 regular Dinos followed by exactly one Green Dino boss | Show Green before Wave 10, spawn more than one Green, omit the Wave 10 boss, or substitute a different per-wave count/order | The HUD and enemy visuals make each type, the single boss, and the current wave composition recognizable |
| WAVE-05 | During the first-wave countdown, between waves, or while combat is underway | The player can always continue building towers, selecting, upgrading, selling, and repairing eligible towers; opening details does not pause waves | Force a pause, lock the shop/Repair control, or allow operations only before waves | All normal operations remain available except in a terminal state |
| ENEMY-01 | All four enemy types appear | Red: `10` HP, speed `68`, leak damage `5`, kill reward `10`; Blue: `5` HP, speed `88`, leak damage `5`, kill reward `10`; Yellow: `10` HP, speed `106`, leak damage `1`, kill reward `10`; Green boss: `100` HP, speed `78`, leak damage `10`, kill reward `10` | Make the displayed identity, HP, relative speed, leak damage, or reward contradict these fixed values | Red is slower than the Green boss, the boss is slower than Blue, and Yellow remains the fastest |
| BOSS-01 | The last enemy allocated to Wave 10 spawns | Spawn the only Green Dino in the campaign as the boss, using `dino4.png` at `1.6×` the normal Dino linear display scale with a proportionally larger hit area and a clearly readable `Boss` identity/health bar | Spawn a regular-size Green Dino, more than one Green Dino, a Green Dino before Wave 10, or an ordinary enemy after the boss | The larger Green Dino is visibly distinct while remaining recognizable as the mapped Green Dino asset |

The exact number of each Dino allocated to every wave is fixed for deterministic testing:

| Wave | Total | Red Dino | Blue Dino | Yellow Dino | Green Dino |
|---:|---:|---:|---:|---:|---:|
| 1 | 8 | 8 | 0 | 0 | 0 |
| 2 | 11 | 11 | 0 | 0 | 0 |
| 3 | 14 | 14 | 0 | 0 | 0 |
| 4 | 16 | 10 | 6 | 0 | 0 |
| 5 | 19 | 12 | 7 | 0 | 0 |
| 6 | 22 | 14 | 8 | 0 | 0 |
| 7 | 25 | 12 | 6 | 7 | 0 |
| 8 | 28 | 14 | 7 | 7 | 0 |
| 9 | 30 | 15 | 7 | 8 | 0 |
| 10 | 33 | 20 | 6 | 6 | 1 |

For deterministic spawn-order checks, Waves 4–6 repeat `Blue, Red, Red`; Waves 7–9 repeat `Yellow, Red, Blue, Red`; Wave 10 repeats `Red, Red, Blue, Red, Yellow` six times (18 Red, 6 Blue, 6 Yellow), then spawns two additional Red Dinos, and finally spawns the single Green Dino boss as enemy 33. The boss is always last.

### 6.5 Movement, Combat, and Resolution

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| COMBAT-01 | A living enemy exists | The enemy advances along `ROUTE-01` over continuous time and passes through intermediate positions | Jump to a distant position, leave the road, or keep moving in a terminal state | Movement direction/animation is broadly consistent with the journey |
| COMBAT-02 | One or more living enemies are within a tower's current-level range | Target the eligible enemy furthest along the route and apply exactly the current-level damage/interval in the offense table; switch targets when the current target dies, leaks, or leaves range | Only change Remaining, directly clear an enemy without damage, target an out-of-range/dead enemy, or prefer an enemy less advanced on the route | Visible attack feedback and enemy HP update consistently with the hit |
| COMBAT-03 | The four tower types are in situations where their fixed roles can be exercised | Gatling damages only its primary target; Flamethrower damages all enemies within its range and directional flame half-width; Raygun damages only its primary target with a visible ray; Explosive damages all valid enemies within its explosion radius | Make all four towers equivalent, ignore the fixed areas, or use values different from the offense table | The four roles and current-level value changes are observable in actual combat |
| COMBAT-04 | An enemy's HP reaches zero due to tower attacks | Resolve that enemy as a kill exactly once, remove it from the battlefield, and award `10` Gold exactly once | Let it leak afterward, award repeatedly, or continue attacking it | The enemy and HP feedback disappear, and Gold updates in sync |
| COMBAT-05 | An enemy actually reaches the base | Apply that type's leak damage exactly once and remove it, do not award Gold, and clamp base HP to a minimum of `0` | Deduct HP repeatedly, award Gold at the same time, or show negative HP | HP updates in sync; after a nonfatal leak, other objects continue |
| ENEMY_ATTACK-01 | A Red Dino is alive and at least one living tower is within `102 px` center-to-center | Keep that Red Dino moving along the route, target the nearest eligible tower, and after each full `1.50 s` attack interval launch one small red circular projectile toward that target; ties select the earliest-built tower | Stop or slow route movement because of attacking, attack beyond range, attack the base as though it were a tower, or fire immediately without the first full interval | Walking and attacking are visibly simultaneous while a target remains in range |
| ENEMY_ATTACK-02 | The Green Dino boss is alive and at least one living tower is within `102 px` center-to-center | Keep the boss moving along the route, target the nearest eligible tower, and after each full `1.00 s` attack interval launch one large red circular projectile toward that target; ties select the earliest-built tower | Stop or slow route movement because of attacking, use the Red Dino's small projectile/interval, or attack beyond range | Walking and attacking are visibly simultaneous; the boss attack is visibly larger and more threatening than the Red Dino attack |
| ENEMY_ATTACK-03 | A Dino projectile is in flight | Red Dino projectiles are filled red circles `8 px` in diameter, travel at `260 px/s`, and deal exactly `1` tower damage on contact; Green Dino boss projectiles are filled red circles `20 px` in diameter, travel at `220 px/s`, and deal exactly `5` tower damage on contact | Damage a tower at launch time, damage multiple towers, damage the firing Dino/base, persist after impact, or use identical visual sizes or damage for both attacks | Each projectile visibly travels from its Dino to the target; the corresponding damage and tower health bar update together only on impact |
| ENEMY_ATTACK-04 | A projectile's target is sold, destroyed, or otherwise ceases to be valid before impact; or the game enters a terminal state | Remove that projectile without applying damage. Blue and Yellow Dinos never attack towers | Retarget an in-flight projectile, apply delayed hidden damage, let combat continue behind a terminal overlay, or give Blue/Yellow the Red attack | No orphaned projectile remains, and tower HP stays unchanged from the cancelled shot |

Both attacking Dino types therefore have the same fixed `102 px` attack range, exactly matching the Level 1 Explosive range. Explosive upgrades still increase its range to `110 px` at Level 2 and `118 px` at Level 3. Their attack timing and projectile presentation differ, but neither enemy pauses or loses route speed while attacking.

### 6.6 Selection, Upgrading, and Selling

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| MANAGE-01 | The player clicks a living placed tower | Display the selected tower's name, Level, current/maximum HP, current combat attributes, range indicator, Upgrade, Sell, `Repair — 20 Gold`, and a close control | Display another tower's data, omit HP/Repair, prevent switching selection, or let the details obstruct necessary operations | Values update while the panel is open; selecting another tower switches the details; a destroyed or sold tower cannot continue to be operated |
| UPGRADE-01 | The selected tower is not at max level and there is enough Gold; click Upgrade | Increase only the selected tower by one level, deduct “Level before upgrade × 50,” strengthen its actual combat attributes, and adjust HP according to `TOWER_HP-01`; max Level is `2` (Gatling) or `3` (other towers) | Skip levels, erase existing damage, upgrade another tower, deduct repeatedly, or succeed when Gold is insufficient/at max level | Details, health bar, and Gold update immediately; a failed upgrade does not change HP or Gold |
| SELL-01 | Click Sell | Remove only the selected tower, refund `70%` of that tower's cumulative purchase and upgrade spending excluding all repair spending, clear its health bar/range/details, cancel shots targeting it, and make the original grass area buildable again | Remove another tower, refund repair fees, refund repeatedly, or continue operating the old selection after selling | Gold updates immediately; the player can continue building towers |
| REPAIR-01 | A selected living tower has current HP below maximum HP and Gold is at least `20`; click `Repair — 20 Gold` | Deduct exactly `20 Gold` once and immediately restore that tower to its full current-level maximum HP | Repair another tower, heal only partially, exceed maximum HP, charge more than once, or count repair spending toward a later sale refund | Gold, HP text, and the world-space health bar update on the same frame |
| REPAIR-02 | The selected tower is already at full HP, Gold is below `20`, the tower was sold/destroyed, or no tower is selected | Disable or reject Repair without changing Gold or any HP | Permit negative Gold, heal a missing tower, or charge for a rejected operation | The unavailable state is visually clear, and a later valid repair still works exactly once |

### 6.7 Success, Failure, Retry, and Session

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| BALANCE-01 | The player uses an ordinary strategy, including Repair when useful | At least one way to survive all ten fixed waves and the Green Dino boss exists without cheating, hidden operations, pixel-perfect placement, or extreme execution speed | Make unavoidable tower destruction or the boss's fixed HP/attacks render the campaign unwinnable | A normal player can observe damage, earn and spend Gold, repair towers, and complete the entire success flow |
| BALANCE-02 | The player makes only a very small number of defensive decisions at arbitrary positions and ignores damaged towers | Completing all ten waves is not guaranteed; normal completion should require several of continuous placement, adding towers, different tower roles, upgrades, and repairs | Allow a single casually placed, never-repaired Level 1 tower to reliably defeat all ten waves and the boss | Enemy attacks and tower destruction materially affect defense planning without forcing one pixel-perfect solution |
| FAIL-01 | Base HP falls to `0` | Enter Game Over exactly once; HP stops at `0/30` | Continue below zero or later display completion | Game Over, Restart, and Main Menu are visible and usable |
| SUCCESS-01 | All 33 enemies allocated to Wave 10, including its final single Green Dino boss, have been killed or resolved as leaks, and base HP is greater than `0` | Enter Map Complete exactly once; a nonfatal boss leak is allowed | Complete before the boss resolves, while any enemy/projectile remains, or after failure | Map Complete, Restart, and Main Menu are visible and usable |
| TERMINAL-01 | Game Over or Map Complete appears | Spawning, countdowns, movement, attacks, projectiles, damage, leaks, wave progression, and economic/repair operations all stop; clear any in-flight projectiles; the two terminal states are mutually exclusive | Continue gameplay behind the terminal state or display both outcomes at once | The corresponding terminal state remains visible until the player chooses the next step |
| RESTART-01 | Click Restart in either terminal state | Return within the same process to a clean Grassland: `200` Gold, `30/30` base HP, the first-wave countdown, no towers, health bars, enemies, projectiles, selection, or terminal overlay | Retain old tower damage, old projectiles, old enemies, dragging, countdown, or economic state | The player can immediately drag a full-HP tower normally again and enter Wave 1 |
| RESTART-02 | The player repeats Restart and subsequent operations any number of times | Each time there is only one set of input, countdown, waves, rewards, and UI responses | Duplicate building, cost deductions/rewards, overlapping waves, or multiple terminal overlays | Representative behavior remains consistent under the same initial conditions |
| MENU-01 | Click Main Menu in either terminal state | Return to the initial menu; entering Grassland again starts a clean new game | Remain on the old battlefield or retain objects/progress from the old game | Start and Grassland are available again |
| REOPEN-01 | Completely close the process in any session state and reopen it | Return to the initial menu without restoring towers, Gold, HP, wave, or terminal progress | Automatically continue the previous game | This task has no persistent battle save |

### 6.8 HUD, Interaction Feedback, and Asset Results

| ID | Preconditions and Action | Must Happen | Must Not Happen | Player Feedback and Boundaries |
|---|---|---|---|---|
| HUD-01 | Grassland is active | Gold, base current/maximum HP, current Wave/10 or countdown, and the current wave's remaining count stay synchronized with the true state | Confuse base HP with tower HP, show a false maximum, negative resources, an outdated wave, or an incorrect remaining count | Clearly readable in the default `1152 × 648` viewport |
| HUD-02 | Controls related to the main flow appear | Start, Grassland, all four tower cards, tower details, Upgrade, Sell, `Repair — 20 Gold`, the terminal state, Restart, and Main Menu are on-screen and can be hit with normal mouse input | Make Repair visible but unclickable when valid, hide its price, block it with decoration, or clip it off-screen | No unique layout or text component is required |
| HUD-03 | Towers, Red Dinos, or the Green boss are visible | Tower health bars remain spatially attached to their towers; Red and boss projectiles are visibly distinguishable by their fixed sizes; the boss is visibly larger and identified as `Boss` | Attach a bar to the wrong object, let a bar remain after destruction, conceal projectiles behind the map, or present the boss at ordinary scale | All combat information remains readable without exposing debug-only state |
| FEEDBACK-01 | Dragging, rejection, attacking, taking damage, repairing, upgrading, selling, or destruction occurs | The player can understand from the screen whether the action succeeded and how HP/Gold changed | Change only internal values with no perceptible feedback; show development debug labels or markers on-screen | Feedback may use color, opacity, text, animation, floating values, or equivalent means |
| ASSET-01 | The menu is visible | The provided menu image is the clearly recognizable main menu background | Use only a solid-color background or something unrelated to the provided image | Proportional scaling, cropping, and darkening are allowed |
| ASSET-02 | Grassland is visible | The provided Grassland image is the clearly recognizable main battlefield visual and satisfies `MAP-01` and `MAP-02` | Keep it only in a hidden node, or use something other than that map as the main visual | Proportional scaling and cropping that do not break the relationships are allowed |
| ASSET-03 | The four tower cards, drag previews, placed towers, or details are visible | Each tower type uses its corresponding provided asset, the asset is clearly recognizable at normal gameplay scale, and it serves as the tower's primary visual | Make plain squares/circles the primary visual; place the correct image only off-screen, transparently, behind an obstruction, or as a tiny decoration | Supporting bases, outlines, rotation, animation, and effects must not obscure the asset as the primary visual |
| ASSET-04 | Living enemies of all four types are visible | Each enemy type uses its corresponding provided dinosaur asset; Green uses `dino4.png` as the single boss at `1.6×` the normal Dino linear scale | Use plain geometric enemies, use the same incorrect image for all types, use another Dino for the boss, or make the assets unrecognizable | Frame extraction, animation, flipping, and proportional scaling are allowed, subject to `BOSS-01` |
| ASSET-05 | Enemy-to-tower attacks and tower durability are visible | Small/large red circular projectiles, tower health-bar backing/fill, HP text, and the Repair control may use engine-native procedural shapes and UI; no additional bitmap is required | Substitute an unrelated provided bitmap as the projectile or omit the required visual feedback | Procedural visuals supplement the mapped tower/Dino sprites and must not obscure their identity |

## 7. Success, Failure, and Multi-Stage Flows (Numbered Summary)

| Flow | IDs | Summary |
|---|---|---|
| Success | `WAVE-01`–`WAVE-05`, `ENEMY-01`, `BOSS-01`, `TOWER_HP-01`–`TOWER_HP-03`, `REPAIR-01`–`REPAIR-02`, `BALANCE-01`, `BALANCE-02`, `SUCCESS-01`, `TERMINAL-01` | Maintain the defenses, resolve the single last-wave boss, and enter the sole completion state if the base survives |
| Failure | `ROUTE-02`, `COMBAT-05`, `ENEMY_ATTACK-01`–`ENEMY_ATTACK-04`, `FAIL-01`, `TERMINAL-01` | Towers may be destroyed without directly ending the run; Game Over occurs only when a leak causes base HP to reach zero |
| Retry | `RESTART-01`, `RESTART-02` | Return to a clean current map from either terminal state |

Outcomes that must not appear early are governed by `SUCCESS-01`, `FAIL-01`, and `TERMINAL-01`.

## 8. Interface and Feedback (Numbered Summary)

| Content | IDs |
|---|---|
| Menu, map selection, return | `ENTRY-01`, `ENTRY-02`, `MENU-01` |
| Battlefield state | `HUD-01`–`HUD-03` |
| Dragging and rejection | `BUILD-01`, `BUILD-04`–`BUILD-06`, `FEEDBACK-01` |
| Combat, projectiles, and HP | `COMBAT-01`–`COMBAT-05`, `ENEMY_ATTACK-01`–`ENEMY_ATTACK-04`, `TOWER_HP-01`–`TOWER_HP-03`, `FEEDBACK-01` |
| Tower details, economy, and repair | `MANAGE-01`, `UPGRADE-01`, `SELL-01`, `REPAIR-01`, `REPAIR-02` |
| Asset results | `ASSET-01`–`ASSET-05` |

## 9. Restart, Close/Reopen, and Saving (Numbered Summary)

| Scenario | IDs | Result |
|---|---|---|
| Restart current map | `RESTART-01`, `RESTART-02` | Clear the current battle and restart Grassland |
| Return to the menu and re-enter | `MENU-01` | Create a clean Grassland |
| Completely close and reopen | `REOPEN-01` | Return to the initial menu without saving the battle |

## 10. Core Features of the Original That Must Be Preserved (Numbered Summary)

| Core Feature | IDs |
|---|---|
| Four-tower shop and distinct roles | `TOWER-01`–`TOWER-04`, `COMBAT-03` |
| Destructible towers and paid repair | `TOWER_HP-01`–`TOWER_HP-03`, `ENEMY_ATTACK-01`–`ENEMY_ATTACK-04`, `REPAIR-01`, `REPAIR-02` |
| Free dragging and dropping on continuous grass | `BUILD-01`–`BUILD-06` |
| Grassland's main route order | `MAP-01`, `MAP-02`, `ROUTE-01`, `ROUTE-02` |
| Ten automatic waves and final Green boss | `WAVE-01`–`WAVE-05`, `ENEMY-01`, `BOSS-01` |
| Management, economy, repair, victory/defeat, and retry | `ECON-01`, `ECON-02`, `MANAGE-01`, `UPGRADE-01`, `SELL-01`, `REPAIR-01`–`REPAIR-02`, `FAIL-01`–`RESTART-02` |

## 11. Asset and Content Requirements (Path Mapping)

This section only maps the asset IDs in Section 6 to public source files and does not add new player rules. Asset copying, importing, and binding steps are described in the README/tool instructions and are not part of the GDD.

| ID | Content | Public Source Path | Player Use |
|---|---|---|---|
| ASSET-01 | Menu background | `Asserts/menu/bg.png` | Initial menu |
| ASSET-02 | Grassland map | `Asserts/maps/map1.webp` | Battlefield, road, and grass |
| ASSET-03 | Gatling Gun | `Asserts/turrets/technoturret.png` | Shop, dragging, placed tower, details |
| ASSET-03 | Flamethrower | `Asserts/turrets/laserturret.png` | Shop, dragging, placed tower, details |
| ASSET-03 | Raygun | `Asserts/turrets/reallaser.png` | Shop, dragging, placed tower, details |
| ASSET-03 | Explosive card/dragging | `Asserts/turrets/dynamite.png` | Shop, dragging, and details |
| ASSET-03 | Explosive placed state | `Asserts/turrets/dynamite-pack.png` | Primary visual of the placed tower |
| ASSET-04 | Red Dino | `Asserts/enemies/dino1.png` | Living Red enemy that fires the small red projectile |
| ASSET-04 | Blue Dino | `Asserts/enemies/dino2.png` | Living Blue enemy |
| ASSET-04 | Yellow Dino | `Asserts/enemies/dino3.png` | Living Yellow enemy |
| ASSET-04 | Green Dino boss | `Asserts/enemies/dino4.png` | The only Green enemy, spawned last in Wave 10 and displayed at `1.6×` normal Dino scale |
| ASSET-05 | Red Dino projectile | Procedural; no source bitmap | Filled red circle, `8 px` diameter |
| ASSET-05 | Green boss projectile | Procedural; no source bitmap | Filled red circle, `20 px` diameter |
| ASSET-05 | Tower HP and Repair UI | Procedural/UI; no source bitmap | Attached tower health bars, HP text, and `Repair — 20 Gold` control |

Proportional scaling, rotation, flipping, tinting, atlas-region extraction, animation, and additional effects are allowed, but the final result must continue to satisfy `MAP-01`, `MAP-02`, and `ASSET-01`–`ASSET-05`. The fixed boss scale and projectile diameters are exceptions that must remain measurable. Enemy projectiles and tower durability UI are deliberately procedural and do not require new bitmap assets.

## 12. Dashboard Naming Tables and Control Scheme

This section mirrors `sp/benchmark/naming-tables.json` in human-readable form. It names only concepts already required in Section 6 and adds no gameplay requirement.

### 12.1 Numeric slots

| Slot | Meaning | Existing requirement source |
|---|---|---|
| `gold` | Current player Gold | `STATE-01`, `ECON-*`, `HUD-01` |
| `base_hp`, `base_max_hp` | Current and maximum base HP | `STATE-02`, `COMBAT-05`, `HUD-01` |
| `wave`, `wave_total` | Current wave and fixed campaign wave total | `WAVE-01`–`WAVE-05`, `HUD-01` |
| `remaining_enemies` | Current wave's remaining allocated enemies | `WAVE-03`, `HUD-01` |
| `tower_count` | Current living placed-tower count | `BUILD-*`, `TOWER_HP-03` |

### 12.2 Entities and clickable targets

| Kind | Meaning | Allowed states or role | Existing requirement source |
|---|---|---|---|
| `tower` | A placed tower | `living`, `selected`, `destroyed`; clickable | `TOWER-*`, `MANAGE-01` |
| `red_dino` | Red Dino enemy | `moving`, `moving_and_attacking`, `dead` | `ENEMY-01`, `ENEMY_ATTACK-01` |
| `blue_dino` | Blue Dino enemy | `moving`, `dead` | `ENEMY-01`, `WAVE-04` |
| `yellow_dino` | Yellow Dino enemy | `moving`, `dead` | `ENEMY-01`, `WAVE-04` |
| `green_boss` | Final Green Dino boss | `moving`, `moving_and_attacking`, `dead` | `BOSS-01`, `ENEMY_ATTACK-02` |
| `start_button`, `grassland_button` | Menu and map-select entries | clickable targets | `ENTRY-01`–`ENTRY-02` |
| `tower_card` | One of the four tower purchase cards | draggable target; publish the matching semantic state `gatling_gun`, `flamethrower`, `raygun`, or `explosive` | `BUILD-01`, `TOWER-01`–`TOWER-04` |
| `build_surface` | A visible open-grass destination receiving a tower drag; publish semantic states `open_grass_1`...`open_grass_8` for eight separated valid centers, never preset slots | draggable destination target; report only while Grassland is active | `BUILD-01`–`BUILD-06`, `MAP-02` |
| `upgrade_button`, `sell_button`, `repair_button` | Selected-tower management controls | clickable targets | `UPGRADE-01`, `SELL-01`, `REPAIR-*` |
| `restart_button`, `main_menu_button` | Terminal navigation controls | clickable targets | `RESTART-*`, `MENU-01` |

### 12.3 Controls

All main-flow navigation and management use ordinary visible mouse clicks. Building uses a complete left-button drag from a visible tower card to a visible battlefield point, including press, motion, and release. No keyboard input is required for the main flow.

## 13. Implementation Freedom

Except for the player-observable results specified in Section 6—including exact Wave 10 composition, boss scale/stats, attack ranges/intervals, projectile sizes/speeds/damage, tower HP, and repair price/results—the implementer may freely choose scene organization, object hierarchy, route representation, collision and spatial checks, input handling, state management, restart method, data structures, rendering techniques, UI components, text, and algorithms.

No specific project's nodes, curves, coordinates, class names, functions, signals, or data structures need to be copied.

## 14. Pre-Submission Self-Check

- [ ] `BUILD-02`, `BUILD-03`: Towers can be built at the release positions on multiple scattered grass points, rather than at fixed tower positions.
- [ ] `BUILD-04`, `BUILD-05`: The entire stone road and the footprint of existing towers reject placement without deducting a cost.
- [ ] `ROUTE-01`, `ROUTE-02`: Enemies travel the full main road sequence without taking shortcuts across the grass.
- [ ] `MAP-01`, `MAP-02`: The map, route, and no-build space are aligned with one another.
- [ ] `TOWER-01`–`TOWER-04`, `TOWER_HP-01`–`TOWER_HP-03`, `ASSET-03`: The four fixed tower roles/stats/assets are recognizable; maximum HP follows the type/level table; health bars track damage, upgrade, repair, and destruction.
- [ ] `WAVE-01`–`WAVE-05`, `ENEMY-01`, `BOSS-01`, `BALANCE-01`, `BALANCE-02`: Ten fixed waves progress automatically; Wave 10 has 20 Red, 6 Blue, 6 Yellow, then the only Green Dino at `1.6×` scale; an ordinary strategy can survive the boss.
- [ ] `ENEMY_ATTACK-01`–`ENEMY_ATTACK-04`, `ASSET-05`: Red and Green keep walking while attacking towers within the same fixed `102 px` range, exactly matching the Level 1 Explosive range; their small/large red projectiles deal exactly `1`/`5` damage on impact; cancelled shots cause no damage; Blue and Yellow never attack towers.
- [ ] `MANAGE-01`, `UPGRADE-01`, `SELL-01`, `REPAIR-01`–`REPAIR-02`: Details show tower HP and `Repair — 20 Gold`; valid repair restores full HP for exactly 20 Gold, while full-HP, insufficient-Gold, and missing-tower attempts cost nothing.
- [ ] `FAIL-01`, `SUCCESS-01`, `TERMINAL-01`: Victory and defeat are mutually exclusive and freeze gameplay.
- [ ] `RESTART-01`, `RESTART-02`, `MENU-01`, `REOPEN-01`: Repeated retries and new-process states are correct.

