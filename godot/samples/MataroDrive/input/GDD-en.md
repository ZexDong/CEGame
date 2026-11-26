# MataroDrive: Story, Endless, And Garage Challenge

> Public gameplay contract. Section 6 defines gameplay outcomes; section 12 defines their read-only observation vocabulary. The task reconstructs the player-visible mechanics with independently drawn runtime visuals; no upstream code, logo, or audio is distributed.

## 1. Task in One Sentence

Build a complete 2D car-platforming shell with fifteen story levels, level selection, Endless and Hill Climb modes, collectible cash, power-ups, a six-car Garage, Settings, Trophies, and persistent profile progress.

## 2. Scope

### 2.1 Required

| Requirement IDs | Summary |
|---|---|
| `ENTRY-01`–`ENTRY-03` | Main menu, profile load, Play and mode navigation |
| `PLAYER-01`–`PLAYER-05` | Driving, jumping, collision, respawn, and visual movement feedback |
| `STORY-01`–`STORY-06` | Fifteen-level story flow, story panels, results, next level, victory, and restart |
| `LEVELSELECT-01`–`LEVELSELECT-02` | Fifteen selectable levels with stars |
| `COLLECT-01`–`COLLECT-05` | Coins, combo, air-time bonus, gems, and visual feedback |
| `OBJECT-01`–`OBJECT-07` | Cones, enemies, boosts, springs, moving platforms, shield, and magnet |
| `PROGRESS-01`–`PROGRESS-05` | Cash, stars, level completion, best distance, and persistence |
| `ENDLESS-01`–`ENDLESS-04` | Procedural runner, distance, failure, retry/menu, and best record |
| `HILL-01`–`HILL-04` | Procedural hills, gaps, failure, retry/menu, and best record |
| `GARAGE-01`–`GARAGE-04` | Six car colors, costs, purchase, equip, and persistence |
| `SETTINGS-01`–`SETTINGS-03` | Music, sound, persistence |
| `TROPHY-01`–`TROPHY-03` | Summary stats, eight achievements, and persistence |
| `HUD-01`–`HUD-04` | Cash, level, power-up, distance, and result display |
| `VISUAL-01`–`VISUAL-04` | Runtime-drawn car, terrain, themed scenes, hazards, and readable UI |
| `QUALITY-01`–`QUALITY-03` | Stability, input reachability, and terminal-state discipline |

### 2.2 Excluded

| Related IDs | Not included |
|---|---|
| None | Online leaderboards, ads, purchases, mobile export, external accounts, or use of the upstream logo/audio |
| `VISUAL-01`–`VISUAL-04` | Pixel-perfect reproduction of upstream scenes or branding is not required |

## 3. Starting State

| Item | Starting state | Requirement |
|---|---|---|
| Project | Runnable Godot starter with a visible placeholder | `ENTRY-01`, `QUALITY-01` |
| Profile | Empty or previously saved profile loaded from the public save file | `PROGRESS-05` |
| Story progress | No completed levels on a clean profile | `PROGRESS-02` |
| Cash | `0` on a clean profile | `PROGRESS-01` |
| Owned cars | Amber only | `GARAGE-02` |
| Audio | Music and sound enabled on a clean profile | `SETTINGS-01` |

## 4. Player Goal And Complete Flow

### 4.1 Player Goal

Drive through fifteen story levels, collect cash and gems, use hazards and power-ups, earn stars, unlock car colors, set an Endless or Hill Climb distance record, and preserve profile progress across Reopen (`PLAYER-01`, `OBJECT-01`, `PROGRESS-02`, `GARAGE-03`, `ENDLESS-03`, `HILL-03`).

### 4.2 Complete Player Flow

```text
Launch
-> [ENTRY-01] Main Menu
-> Play / Levels / Endless / Hill Climb / Garage / Settings / Trophies
-> [PLAYER-01..05] drive, jump, collect, avoid hazards
-> [STORY-02] reach the goal or [ENDLESS-02/HILL-02] fall to end the run
-> [STORY-04/PROGRESS-02] receive stars and profile progress
-> Next Level / Retry / Main Menu
-> [GARAGE-03/SETTINGS-02] spend cash or change preferences
-> close and reopen
-> [PROGRESS-05] restore profile progress and settings
```

### 4.3 Core Loop

```text
Read terrain and upcoming objects
-> steer and jump
-> collect cash or power-ups
-> avoid hazards or recover from a hit
-> reach the goal or continue until failure
-> bank rewards and choose the next activity
```

## 5. Player Controls

| Requirement | Action | Context | Result |
|---|---|---|---|
| `PLAYER-01` | Hold Left/A or Right/D | Story and playable modes | Move horizontally while held |
| `PLAYER-02` | Press Space or Up | On the ground | Jump |
| `HUD-04` | Left-click visible result controls | Results | Next Level, Retry, or Main Menu |
| `HUD-03` | Left-click Pause/Resume | Story levels | Pause or resume |

Touch-sized buttons may mirror the same actions but are not required in the Windows benchmark.

## 6. Numbered Requirements: Sole Gameplay Acceptance Criteria

### 6.1 Entry And Navigation

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| ENTRY-01 | Launch a new process | Load the public save and show a usable Main Menu with Play, Levels, Endless, Hill Climb, Garage, Settings, and Trophies | Resume a half-finished run or show an unresponsive placeholder | All seven mode buttons are visible and clickable |
| ENTRY-02 | Click Play | Start a clean story run at Level 1 with run cash `0`, combo `1`, and no active power-up | Resume an unfinished level or carry run cash/combo | Level 1 appears with its story/intro state |
| ENTRY-03 | Click any non-Play mode | Open that mode without altering the saved profile except through its explicit actions | Reset unrelated profile fields | The selected mode screen is immediately usable |

### 6.2 Player Movement

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| PLAYER-01 | Hold left/right on valid ground in Story | Move with a target horizontal speed of `320` units/s and obey collision surfaces; a longer hold travels farther than a tap | Ignore walls or drift without input in Story; Endless and Hill Climb instead use their automatic forward drive | Car movement, facing, wheels, and camera follow are visible |
| PLAYER-02 | Press jump while grounded | Apply an upward jump velocity of `-680` units/s once; require landing before another jump | Multi-jump, jump while airborne, or fail to leave the ground | Squash/stretch, dust, and jump feedback occur |
| PLAYER-03 | Drive onto a slope or moving platform | Follow the supporting surface and keep the car attached while the surface moves | Fall through a valid platform or remain on a removed platform | Car position and tilt match the surface |
| PLAYER-04 | Fall below the safe story-level area | Respawn at the current level spawn unless a shield/power-up rule applies | Reset the whole level or keep falling forever | Car returns to spawn while remaining run cash is preserved |
| PLAYER-05 | Moving car is visible | Animate wheels/facing and camera follow without making collisions disagree with the visible car | Display movement opposite to actual motion | Input direction and visible direction agree |

### 6.3 Story And Level Lifecycle

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| STORY-01 | Play begins | Load Level 1, then advance consecutively through all 15 levels | Skip levels, repeat Level 1, or exceed Level 15 | HUD shows Level `N/15` |
| STORY-02 | Player reaches the level goal | Stop player control, resolve the level exactly once, and show a Level Complete panel or final Victory | Award twice, let the car pass through, or leave the level active | Goal contact and result panel are obvious |
| STORY-03 | A story intro is active | Pause player physics and show title/body text with a Drive/Continue control | Let the car move or auto-dismiss the panel without player input | Story panel remains until continued |
| STORY-04 | Level 1–14 is completed | Bank the level cash, record stars/completion, and show Level Complete with Next Level and Main Menu | Advance without recording or show final Victory before Level 15 | Level result names the earned stars and cash |
| STORY-05 | Level 15 is completed | Bank the final cash/progress and show Victory with the final summary | Start Level 16 or show Level Complete | Final success screen remains until restart/menu |
| STORY-06 | Click Restart from Victory | Start a clean story run at Level 1 | Restore completed-level position in the run | Level 1 intro appears |

### 6.4 Level Selection

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| LEVELSELECT-01 | Open Levels | Show exactly 15 visible level buttons with earned-star indicators | Hide levels, show the wrong star count, or start a level from a non-button area | Saved stars and level numbers are readable |
| LEVELSELECT-02 | Click a visible level button | Start a clean run at that level with run cash/combo reset and profile progress preserved | Start another level or erase saved stars | Selected level loads and HUD shows its number |

### 6.5 Collectibles And Score

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| COLLECT-01 | Collect a coin | Add the current combo value to run cash, then increase combo by one up to `9` and restart a `2.0`-second combo window | Award zero, exceed x9, or leave the coin collected twice | Floating `+value` feedback and HUD update |
| COLLECT-02 | No coin is collected for `2.0` seconds | Reset combo to `1` | Keep combo indefinitely or reset while still collecting within the window | Combo indicator returns to x1 |
| COLLECT-03 | Land after continuous air time greater than `0.6` seconds | Award `floor(air_time * 12)` cash in addition to landing feedback | Award for short hops or penalize a valid landing | An `AIR` bonus appears and run cash updates |
| COLLECT-04 | Collect a gem | Add exactly `5` run cash and increment the profile gem count once | Award repeatedly or update the wrong profile field | Gem popup and persistent gem count update |
| COLLECT-05 | A cone is hit | Break the combo, reduce run cash by `1` with a floor of zero, and launch the cone away unless a shield absorbs the hit | Trigger a full level reset, subtract repeatedly, or allow negative cash | Bump feedback, cone flight, and cash/combo update |

### 6.6 World Objects

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| OBJECT-01 | Touch a boost pad | Apply a forward boost at `760` units/s for `0.85` seconds and show speed feedback | Stack unlimited boosts forever or fail to accelerate | Speed lines, exhaust, and camera response |
| OBJECT-02 | Touch a spring | Apply an upward launch velocity of `-1150` units/s | Treat it as a normal jump or fail to leave the ground | Strong trampoline launch and stretch feedback |
| OBJECT-03 | Collect a shield, then touch an enemy or cone | Collecting grants one shield; the next enemy/cone contact consumes it and prevents that contact's penalty; collecting again refreshes one shield without stacking | Consume without preventing the hit, retain the shield after use, or protect against falling | Shield appearance and disappearance and safe collision are visible |
| OBJECT-04 | Collect a magnet | Pull nearby coins for `6.0` seconds and show a countdown | Pull unrelated objects, persist past six seconds, or fail to pull any in range | Magnet visual/countdown and coin movement |
| OBJECT-05 | Touch a patrolling enemy without shield | Break the combo and respawn the car at the current level start | End the story level, erase banked profile cash, or apply repeated hits | Crash feedback and respawn |
| OBJECT-06 | Ride a moving platform | Move the car with the platform while contact is valid | Leave the car behind, duplicate the platform, or create a gap in its valid path | Car remains attached and visible |
| OBJECT-07 | Trigger a one-shot object more than once | Apply its effect only once per activation/contact where the object is consumed or disabled | Repeat indefinitely from a single overlap | Object animation/removal matches the applied effect |

### 6.7 Progress, Stars, And Persistence

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| PROGRESS-01 | Complete any level or endless run | Bank run cash into total profile cash and lifetime earned cash; never bank a negative value | Lose earned cash, duplicate the award, or add negative cash | Garage and result totals update |
| PROGRESS-02 | Complete a story level | Mark it complete exactly once and preserve its best star rating | Regress a higher old rating or mark another level | Level select shows completed/stars |
| PROGRESS-03 | Complete a level with level cash `0–6`, `7–13`, or `14+` | Award `1`, `2`, or `3` stars respectively, keeping only the best result | Award fewer than one, more than three, or overwrite a better score | Result panel paints the exact star count |
| PROGRESS-04 | End Endless or Hill Climb | Update the shared best distance only when the new distance is greater | Reduce the record or save the current distance when lower | Result and Trophies show the best value |
| PROGRESS-05 | Close the process and reopen | Restore stars, total/lifetime cash, owned/equipped car, completed levels, max combo, gems, achievements, best distance, and audio preferences from the profile save defined in TOOLCHAIN-en.md | Restore an unfinished level/run or lose any listed profile field | Menu, Garage, Settings, Levels, and Trophies match the saved profile |

### 6.8 Endless

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| ENDLESS-01 | Enter Endless | Auto-drive right, generate ground ahead, and remove safe ground behind | Require holding a movement key, run out of terrain, or generate gaps before the safe opening section | Car continuously advances and distance grows |
| ENDLESS-02 | Encounter a gap or cone | Falling below the safe line ends the run; cones follow `COLLECT-05` | Auto-respawn after falling or ignore cones | Failure state or bump feedback is clear |
| ENDLESS-03 | Run ends | Record the distance, bank run cash, and show Distance, Best, Retry, and Main Menu | Continue simulation or reset the profile | Game Over panel stays until an action |
| ENDLESS-04 | Click Retry | Start a clean Endless run with profile state preserved | Resume the old run or reset profile records | Distance returns to zero and terrain regenerates |

### 6.9 Hill Climb

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| HILL-01 | Enter Hill Climb | Auto-drive right over generated rolling hills with occasional jumpable gaps | Use flat Endless terrain, block the route, or require movement input | Car follows visible hills and distance grows |
| HILL-02 | Fall into a gap or below the safe line | End the run | Auto-respawn or continue below the world | Game Over appears |
| HILL-03 | Run ends | Record distance using the shared best-distance rule, bank cash, and show Retry and Main Menu | Lose earned cash or continue simulation | Result panel shows distance/best |
| HILL-04 | Click Retry | Start a clean Hill Climb run with profile preserved | Resume old terrain or reset the profile | New hills and distance-zero HUD |

### 6.10 Garage

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| GARAGE-01 | Open Garage | Show current cash and six named car colors | Hide affordability/ownership, show fewer than six, or lose the menu path | Six car controls and cash are readable |
| GARAGE-02 | Six car prices | Amber `0`, Crimson `30`, Azure `50`, Emerald `70`, Violet `90`, Graphite `120`; Amber is owned on a clean profile | Use different prices or start with another car owned | Locked cars show their price |
| GARAGE-03 | Click an owned car | Equip it and persist the selection | Charge again or allow an unowned car | Selected marker/car color changes |
| GARAGE-04 | Click an unowned affordable car | Deduct its exact cost, mark it owned, equip it, and persist | Deduct twice or equip without ownership | Cash decreases and the car becomes selected |

### 6.11 Settings, Trophies, And Audio

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| SETTINGS-01 | Open Settings | Show Music and Sound On/Off states matching the loaded profile | Reset preferences on entry or display the opposite state | Two toggles are visible |
| SETTINGS-02 | Toggle Music or Sound | Flip only that preference, apply it immediately, and persist it | Change the other setting or fail after Reopen | Button label and audio behavior update |
| SETTINGS-03 | Return from Settings | Preserve all profile values and return to Main Menu | Start/restart gameplay | Menu appears with preferences retained |
| TROPHY-01 | Open Trophies | Show completed levels/15, total stars/45, best distance, owned cars/6, gems, and lifetime cash | Display stale or invented values | Summary matches saved profile |
| TROPHY-02 | Achievement conditions | Unlock First Sale at 1 completed level, Big Spender at 2 owned cars, Full Garage at 6 owned cars, Star Collector at 10 total best stars, Long Hauler at 250 metres best distance, Combo Master at x7 maximum combo, Gem Hunter at 15 lifetime gems, and The Legend at 15 distinct completed levels; show one notification per newly unlocked achievement | Unlock twice, lose unlocked state, or use another threshold | Trophies list and toast update |
| PROFILE-01 | No valid saved profile exists | Start with zero cash, lifetime cash, gems, distance record, stars and completed levels; Amber owned/equipped, maximum combo 1, no achievements, and Music/Sound enabled | Load partial invalid progress | Menu and profile screens show these defaults |
| DISTANCE-01 | Endless or Hill Climb advances | Report nonnegative maximum forward travel from the run start in metres, with 100 world units equal to one metre | Increase distance merely by jumping or reduce recorded distance | Current distance and best record use the same unit |
| GARAGE-05 | Select an unaffordable unowned car | Preserve cash, ownership and equipped car and show insufficient cash | Charge or equip the car | Price and rejection remain readable |
| TROPHY-03 | Return from Trophies | Preserve unlocked achievements and return to Main Menu | Reset progress | Menu appears with profile unchanged |

### 6.12 HUD And Results

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| HUD-01 | Story level active | Show run cash, combo when above x1, current level/15, and active shield/magnet state | Show stale or conflicting values | Values update with the true state |
| HUD-02 | Endless or Hill Climb active | Show current distance and best distance | Show level/15 or omit distance | Distance updates continuously |
| HUD-03 | Pause is activated | Freeze driving and objects and show Resume and Main Menu | Continue simulation behind the panel | Pause overlay and controls appear |
| HUD-04 | A run ends or a level is completed | Show the correct result, earned stars/cash/distance as applicable, and only valid next/retry/menu controls | Show both Victory and Game Over or leave gameplay active | Result remains stable |

### 6.13 Visual And Gameplay Quality

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| VISUAL-01 | Story level visible | Use runtime-drawn or independently cleared terrain, car, hazards, and scenery with readable contrast | Use the upstream logo/audio or missing-resource placeholders | The scene reads as a coherent car platformer |
| VISUAL-02 | Themes appear across levels | Include day, dusk, night, sunset, dawn, rain and snow atmosphere families across the fifteen levels; the level-to-theme assignment is free | Use one flat undifferentiated background for all levels or let weather obscure gameplay | Level theme changes remain recognizable |
| VISUAL-03 | Car, coin, gem, cone, enemy, boost, spring, shield, magnet, and goal appear | Make each gameplay role visually distinct from the others | Reuse one indistinguishable marker for multiple roles | Players can identify object roles and feedback |
| VISUAL-04 | Any screen is open | Keep menu text, HUD, and result controls readable and inside `1280x720` | Crop, hide, or cover required controls | No broken text/layout at the fixed viewport |
| QUALITY-01 | Use the complete profile lifecycle | Remain stable across all modes, purchase/settings paths, results, restart, and Reopen | Crash, freeze, dead-end, or corrupt profile | All required screens remain reachable |
| QUALITY-02 | Use normal keyboard/mouse input | Reach every required control through visible UI or documented keys | Require hidden keys, internal calls, or debug menu | Inputs produce immediate feedback |
| QUALITY-03 | A result/pause panel is visible | Stop underlying gameplay except documented Retry/Menu/Resume controls | Let the old run continue or respond to unrelated input | State remains stable until the player chooses |

## 7. Success, Failure, And Multi-Stage Flow

### 7.1 Success

| Requirement | Condition | Result |
|---|---|---|
| `STORY-05` | Reach the goal in Level 15 | Victory with final cash/progress and Restart/Main Menu |

### 7.2 Failure

| Requirement | Condition | Result |
|---|---|---|
| `ENDLESS-02`, `HILL-02` | Fall/leave safe terrain in an endless mode | Mode-specific Game Over with distance, Retry, Main Menu |

Story levels use respawn rather than a run-ending failure except for an explicit pause/restart action.

### 7.3 Multi-Stage Flow

| Stage | Required IDs | Summary | Must not appear early |
|---|---|---|---|
| Menu | `ENTRY-01`–`ENTRY-03` | Mode selection | Mid-level state |
| Story 1–14 | `STORY-01`–`STORY-04` | Level, result, Next Level | Final Victory |
| Story 15 | `STORY-05` | Final level and Victory | Next Level |
| Endless/Hill | `ENDLESS-01`–`HILL-04` | Auto-run, result, Retry | Story level progression |

## 8. Interface And Feedback

| Requirement | Information | Update timing | Player must distinguish |
|---|---|---|---|
| `HUD-01` | Cash, combo, level, power-up | On every change | Run score and active power |
| `HUD-02` | Current/best distance | Continuously in endless modes | This run versus record |
| `HUD-04` | Result and stars/cash/distance | On end/complete | Success, failure, earned reward |
| `GARAGE-01` | Cash and car ownership | On entry/purchase/equip | Affordable, owned, selected |

## 9. Restart, Reopen, And Save

| Scenario | Requirement | Reset | Preserve | Final state |
|---|---|---|---|---|
| Retry current mode | `ENDLESS-04`, `HILL-04`, `HUD-03` | Run cash, combo, distance, objects | Profile/records/settings | Clean mode start |
| Restart story after victory | `STORY-06` | Story run position/cash/combo | Story stars/completion, garage, settings, records | Level 1 |
| Close/reopen | `PROGRESS-05` | Unfinished run | All profile fields listed in `PROGRESS-05` | Main Menu with profile loaded |

## 10. Existing Functionality To Preserve

Not applicable. This is a mechanics-based reconstruction with independent public presentation.

## 11. Material And Content Requirements

The upstream repository has no distribution license. Therefore the public Input intentionally supplies no upstream bitmap, logo, font, scene, or audio file.

| Requirement | Material role | Status | Requirement |
|---|---|---|---|
| `VISUAL-01`–`VISUAL-04` | Car, terrain, props, effects, UI, themes, audio | Runtime-drawn or independently supplied by the implementation | Visual roles must remain distinct and coherent; audio is optional |

`Assets/material-index.json`, `Assets/asset-coverage.json`, and `Assets/asset-contact-sheet.png` document this procedural coverage. No missing required source role exists.

## 12. Dashboard Naming Tables And Control Scheme

The dashboard reports visible on-screen positions in the fixed `1280x720` viewport, origin top-left, x right, y down.

### 12.1 Numeric Slots

| Slot | Meaning | Requirement |
|---|---|---|
| `cash` | Current run cash | `HUD-01` |
| `combo` | Current coin combo, 1–9 | `COLLECT-01` |
| `level` | Current story level, `0` outside a story level | `STORY-01` |
| `total_levels` | Always `15` | `STORY-01` |
| `completed_levels` | Saved completed story levels | `PROGRESS-02` |
| `stars` | Total earned stars | `PROGRESS-03` |
| `owned_cars` | Number of owned colors | `GARAGE-01` |
| `best_distance` | Shared saved distance record | `PROGRESS-04` |
| `distance` | Current endless-mode distance, `0` elsewhere | `ENDLESS-03`, `HILL-03` |
| `gems` | Persisted gem count | `COLLECT-04` |


Additional numeric observations of the existing profile and power-up rules:

| Slot | Meaning / source |
|---|---|
| `profile_cash` | Current banked profile cash (PROGRESS-01, GARAGE-04) |
| `lifetime_cash` | Total banked earnings before purchases (PROGRESS-01) |
| `max_combo` | Saved maximum combo (PROGRESS-05, TROPHY-02) |
| `equipped_car` | Amber 0, Crimson 1, Azure 2, Emerald 3, Violet 4, Graphite 5 (GARAGE-03) |
| `music_enabled` | Music enabled 1, disabled 0 (SETTINGS-02) |
| `sound_enabled` | Sound enabled 1, disabled 0 (SETTINGS-02) |
| `shield_active` | One carried shield 1, none 0 (OBJECT-03) |
| `magnet_seconds` | Remaining magnet duration, zero when inactive (OBJECT-04) |
| `level_1_stars` | Best stars for Level 1, 0 before completion (PROGRESS-02/03) |
| `level_2_stars` | Best stars for Level 2, 0 before completion (PROGRESS-02/03) |
| `level_3_stars` | Best stars for Level 3, 0 before completion (PROGRESS-02/03) |
| `level_4_stars` | Best stars for Level 4, 0 before completion (PROGRESS-02/03) |
| `level_5_stars` | Best stars for Level 5, 0 before completion (PROGRESS-02/03) |
| `level_6_stars` | Best stars for Level 6, 0 before completion (PROGRESS-02/03) |
| `level_7_stars` | Best stars for Level 7, 0 before completion (PROGRESS-02/03) |
| `level_8_stars` | Best stars for Level 8, 0 before completion (PROGRESS-02/03) |
| `level_9_stars` | Best stars for Level 9, 0 before completion (PROGRESS-02/03) |
| `level_10_stars` | Best stars for Level 10, 0 before completion (PROGRESS-02/03) |
| `level_11_stars` | Best stars for Level 11, 0 before completion (PROGRESS-02/03) |
| `level_12_stars` | Best stars for Level 12, 0 before completion (PROGRESS-02/03) |
| `level_13_stars` | Best stars for Level 13, 0 before completion (PROGRESS-02/03) |
| `level_14_stars` | Best stars for Level 14, 0 before completion (PROGRESS-02/03) |
| `level_15_stars` | Best stars for Level 15, 0 before completion (PROGRESS-02/03) |
| `owns_amber` | Ownership 0/1 (GARAGE-02/04) |
| `owns_crimson` | Ownership 0/1 (GARAGE-02/04) |
| `owns_azure` | Ownership 0/1 (GARAGE-02/04) |
| `owns_emerald` | Ownership 0/1 (GARAGE-02/04) |
| `owns_violet` | Ownership 0/1 (GARAGE-02/04) |
| `owns_graphite` | Ownership 0/1 (GARAGE-02/04) |
| `achievement_first_sale` | Saved unlock 0/1 (TROPHY-02) |
| `achievement_big_spender` | Saved unlock 0/1 (TROPHY-02) |
| `achievement_full_garage` | Saved unlock 0/1 (TROPHY-02) |
| `achievement_star_collector` | Saved unlock 0/1 (TROPHY-02) |
| `achievement_long_hauler` | Saved unlock 0/1 (TROPHY-02) |
| `achievement_combo_master` | Saved unlock 0/1 (TROPHY-02) |
| `achievement_gem_hunter` | Saved unlock 0/1 (TROPHY-02) |
| `achievement_legend` | Saved unlock 0/1 (TROPHY-02) |

### 12.2 Entities And Clickable Targets

| Kind | Meaning | Allowed states | Requirement |
|---|---|---|---|
| `player` | Car | `normal`, `boosted`, `shielded`, `magnetized`, `respawned` | `PLAYER-01`–`PLAYER-05` |
| `coin` | Cash collectible | `normal` | `COLLECT-01` |
| `gem` | Rare collectible | `normal` | `COLLECT-04` |
| `cone` | Bump hazard | `normal`, `hit` | `COLLECT-05` |
| `enemy` | Patrolling hazard | `normal`, `hit` | `OBJECT-05` |
| `powerup` | Magnet or shield | `magnet`, `shield` | `OBJECT-03`, `OBJECT-04` |
| `boost_pad` | Speed boost | `normal` | `OBJECT-01` |
| `spring` | High jump | `normal` | `OBJECT-02` |
| `moving_platform` | Moving support | `normal` | `OBJECT-06` |
| `goal` | Story-level finish | `normal`, `reached` | `STORY-02` |
| `play_button`, `levels_button`, `endless_button`, `hill_climb_button`, `garage_button`, `settings_button`, `trophies_button` | Main-menu targets | — | `ENTRY-01`–`ENTRY-03` |
| `continue_button` | Dismiss story intro | — | `STORY-03` |
| `level_button` | Level selection target; stable id and level_number 1–15 | — | `LEVELSELECT-01`–`LEVELSELECT-02` |
| `car_button` | Garage target; stable id and car_index 0–5 in price-table order | — | `GARAGE-01`–`GARAGE-04` |
| `music_button`, `sound_button` | Settings targets | — | `SETTINGS-02` |
| `pause_button`, `resume_button` | Pause controls | — | `HUD-03` |
| `next_button`, `retry_button`, `restart_button`, `main_menu_button` | Result/lifecycle controls | — | `STORY-04`, `ENDLESS-03`, `HILL-03` |

### 12.3 Control Scheme

| Item | Value |
|---|---|
| Movement | Continuous hold: Left/A or Right/D |
| Jump | Space or Up |
| Menus/results | Visible left-click controls |
| Optional pause | Escape may mirror the visible Pause button |

## 13. Implementation Boundaries

- Section 6 is the only source of game-specific acceptance requirements.
- The dashboard is read-only and cannot drive, jump, collect, buy, save, reset, or force a result.
- Internal scene names, scripts, drawing method, terrain generation, and architecture are free.
- Exact project entry, paths, input, save filename, and dashboard transport are defined by `TOOLCHAIN-en.md` and `BENCHMARK_MANIFEST.json`.

## 14. Requirement Index

| ID | Summary |
|---|---|
| `ENTRY-01`–`ENTRY-03` | Menu and mode entry |
| `PLAYER-01`–`PLAYER-05` | Driving, jumping, surfaces, respawn |
| `STORY-01`–`STORY-06` | Fifteen-level story lifecycle |
| `LEVELSELECT-01`–`LEVELSELECT-02` | Level selection |
| `COLLECT-01`–`COLLECT-05` | Cash, combo, air bonus, gems, cone bump |
| `OBJECT-01`–`OBJECT-07` | World interactions |
| `PROGRESS-01`–`PROGRESS-05` | Cash, stars, records, saved profile |
| `ENDLESS-01`–`ENDLESS-04` | Endless mode |
| `HILL-01`–`HILL-04` | Hill Climb mode |
| `GARAGE-01`–`GARAGE-04` | Colors, prices, purchase, equip |
| `SETTINGS-01`–`SETTINGS-03` | Audio settings |
| `TROPHY-01`–`TROPHY-03` | Summary and achievements |
| `HUD-01`–`HUD-04` | HUD, pause, result |
| `VISUAL-01`–`VISUAL-04` | Procedural visual coverage and themes |
| `QUALITY-01`–`QUALITY-03` | Stability, input, terminal discipline |
