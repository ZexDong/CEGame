# RougelikeTD: Twelve-Wave Relic Defense

> Public gameplay contract. Section 6 defines gameplay outcomes; section 12 defines their read-only observation vocabulary. This document defines player-visible rules and results only; it does not prescribe scene structure, scripts, algorithms, or private evaluation logic.

## 1. Task in One Sentence

Build a compact roguelike tower-defense run: start with `100` gold and `20` base health on the supplied 18-by-10 path map, place and combine three distinct heroes, survive twelve deterministic-composition waves, and choose one relic reward after each cleared wave.

## 2. Scope

### 2.1 Required

| Requirement IDs | Summary |
|---|---|
| `ENTRY-01`–`ENTRY-02` | Menu, clean run start, fixed map, gold, health, wave state |
| `PLACE-01`–`PLACE-04` | Hero selection, continuous build-space placement, rejection, and exact cost |
| `HERO-01`–`HERO-06` | Archer, Mage, and Warrior roles, targeting, projectiles, and attack cadence |
| `WAVE-01`–`WAVE-06` | Twelve-wave progression, deterministic components, spawn cadence, and multi-path unlock |
| `ENEMY-01`–`ENEMY-07` | Basic, Runner, Tank, and Boss behavior, rewards, leaks, and boss minions |
| `REWARD-01`–`REWARD-05` | Three-choice relic reward, application, combination, and wave transition |
| `BASE-01`–`BASE-03` | Base health, defeat, and clean failure state |
| `SUCCESS-01`–`SUCCESS-02` | Wave 12 clear, victory, and restart |
| `SESSION-01`–`SESSION-03` | Main Menu, Reopen reset, and clean lifecycle |
| `HUD-01`–`HUD-04` | Gold, health, wave, enemy, hero, and reward state |
| `VISUAL-01`–`VISUAL-04` | Supplied sprites, placement feedback, path clarity, and readable rewards |
| `QUALITY-01`–`QUALITY-03` | Stability, reachable flow, and terminal-state discipline |

### 2.2 Excluded

| Related IDs | Not included |
|---|---|
| None | Other maps, Medium/Hard 60/80-wave modes, meta-progression unlocks, additional heroes, online features, accounts, and cross-run permanent upgrades |
| `REWARD-03` | Socketing or moving gems after a reward is chosen is not required; each chosen relic applies globally to all heroes |

## 3. Starting State

| Item | Starting state | Requirement |
|---|---|---|
| Project | Runnable Godot starter with a visible placeholder | `ENTRY-01`, `QUALITY-01` |
| Gameplay | No playable run yet | All requirements |
| Gold | `100` | `ENTRY-02`, `PLACE-04` |
| Base health | `20` | `ENTRY-02`, `BASE-01` |
| Wave | `0/12`, followed by a short preparation state before Wave 1 | `ENTRY-02`, `WAVE-01` |
| Heroes placed | None | `PLACE-01` |
| Relics held | None | `REWARD-01` |

## 4. Player Goal And Complete Flow

### 4.1 Player Goal

Spend gold on strategically placed heroes, use their distinct attack roles to stop every enemy from reaching the base, select one relic after each cleared wave, and survive all twelve waves (`PLACE-01`, `HERO-01`–`HERO-06`, `WAVE-06`, `SUCCESS-01`).

### 4.2 Complete Player Flow

```text
Launch
-> [ENTRY-01] click Play on the menu
-> [ENTRY-02] see 100 gold, 20/20 base health, and wave 0/12
-> [PLACE-01..04] select a hero card and place it on grass
-> [WAVE-01] Wave 1 spawns
-> [HERO-01..06] heroes target and attack enemies
-> [ENEMY-01..07] enemies advance, die, or leak
-> [REWARD-01..05] choose one of three relics after the wave
-> repeat for waves 1–11
-> [SUCCESS-01] clear Wave 12 and enter Victory
-> [SESSION-01..03] Restart, return to Main Menu, close, and reopen
```

### 4.3 Core Loop

```text
Read remaining gold, base health, wave, and path
-> buy and place a hero on a valid grass cell
-> watch heroes acquire targets and attack
-> earn gold from kills or lose base health from leaks
-> clear the wave
-> choose a relic that changes future combat
-> prepare for the next wave
```

## 5. Player Controls

| Requirement | Action | Context | Result |
|---|---|---|---|
| `PLACE-01` | Left-click a hero card | Preparation or active wave | Select that hero for placement |
| `PLACE-02` | Move the pointer and left-click a grass cell | Hero selected | Place the hero and deduct its cost, or reject without cost |
| `REWARD-01` | Left-click one reward card | Reward state | Apply exactly one relic and continue |
| `SUCCESS-02` | Left-click Restart | Victory or Defeat | Start a clean run |
| `SESSION-01` | Left-click Main Menu | Victory or Defeat | Return to the initial menu |

The keyboard is not required for the main flow.

## 6. Numbered Requirements: Sole Gameplay Acceptance Criteria

### 6.1 Entry And Initial State

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| ENTRY-01 | Launch a new process | Show a usable main menu with a visible Play control | Resume an old run, open the editor, or remain on an unresponsive placeholder | Play is readable and clickable |
| ENTRY-02 | Activate Play | Enter the fixed 18-by-10 map with exactly `100` gold, `20/20` base health, no heroes, no relics, and Wave 0/12 | Carry over gold, health, heroes, relics, or map state | The HUD and an empty buildable battlefield appear immediately |

### 6.2 Hero Selection And Placement

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| PLACE-01 | Click Archer, Mage, or Warrior card | Mark the selected hero and provide a pointer-following placement preview | Begin a wave action, select another card, or show no selection state | The card and preview identify the selected type |
| PLACE-02 | With a hero selected, click a buildable grass cell while enough gold is available | Place exactly one hero centered on that cell and deduct its displayed cost once | Snap to a distant cell, place on the path, charge without placing, or create multiple heroes | The hero appears and gold decreases on the same interaction |
| PLACE-03 | Target an occupied cell, path cell, outside battlefield, or cell with insufficient gold | Reject the placement without changing gold or battlefield objects | Deduct gold, replace an existing hero, or leave a stuck preview | A clearly invalid preview/feedback remains until a valid action |
| PLACE-04 | Place any hero | Deduct exactly Archer `75`, Mage `100`, or Warrior `80` gold | Deduct another type's price or allow negative gold | The HUD shows the resulting gold |

### 6.3 Hero Roles

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| HERO-01 | Archer is placed and an enemy enters its range | Attack the first valid in-range target with `8` damage and `1.5` attacks per second at range `90` | Attack outside range, use area damage, or change the fixed role | Archer shows a ranged attack and target HP changes |
| HERO-02 | Mage is placed and an enemy enters its range | Attack with `22` damage and `0.7` attacks per second at range `55`; on impact, deal the same damage in a `40`-radius splash to other enemies | Behave as a long-range single-target Archer or omit the splash role | A slower projectile and a visible area impact affect multiple nearby enemies |
| HERO-03 | Warrior is placed and an enemy enters its range | Attack with `12` damage and `1.2` attacks per second at range `35`; damage every enemy within `35` of the Warrior | Attack at long range or only one target | A close-range area strike is visible |
| HERO-04 | A hero acquires targets | Keep one current target and switch when it dies, leaks, or leaves range | Keep attacking a removed enemy or permanently lock an unreachable target | Shots visibly track a living in-range enemy |
| HERO-05 | Multiple enemies are in range | Allow every placed hero to attack independently on its own cooldown | Share or duplicate cooldowns across heroes | Damage cadence remains consistent per hero |
| HERO-06 | A hero is placed | It remains at its cell for the rest of the run | Wander, follow enemies, or move off the build cell | The hero stays anchored while its attacks visibly target enemies |

### 6.4 Waves And Spawns

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| WAVE-01 | Enter the battlefield or clear a previous nonfinal wave | Start Wave 1 after a short preparation state; for later waves, start the next wave after the reward choice | Skip Wave 1, overlap two waves, or wait forever | Wave HUD changes from preparation to the current wave |
| WAVE-02 | A wave is active | Spawn the exact composition from the table below in a shuffled order | Add hidden enemy types, vary the published counts, or spawn the boss before Wave 5 | Remaining-enemy count includes spawned and unspawned enemies |
| WAVE-03 | Wave number `w` is active | Use spawn interval `max(0.3, 1.0 - w * 0.05)` seconds between enemies | Use one fixed interval for all waves or spawn all enemies at once | Later waves appear faster |
| WAVE-04 | Wave 10 begins | Open the second published path; from Waves 10–12 alternate spawns between the two paths, starting with the first path each wave | Keep all enemies on one route after unlocking or open the second route before Wave 10 | The second spawn portal becomes visibly active |
| MAP-01 | Start any run | Use an 18-by-10 grid with 32-unit cells. Path 1 runs through (0,4), (4,4), (4,1), (10,1), (10,7), (14,7), (14,4), (17,4). Path 2 runs through (0,8), (4,8), (4,4), then follows Path 1. Consecutive corners join through every intervening cell. Both end at the base (17,4). All path cells, including the locked second route, are unbuildable; remaining cells are grass | Change routes between runs or let visuals and buildability disagree | Both paths are readable; the second portal is locked until WAVE-04 |
| WAVE-05 | A wave is active | Prevent the next wave's enemies from spawning until every current enemy is dead or has leaked | Overlap waves or leave a completed wave stuck | Wave completion is followed by reward selection |
| WAVE-06 | Wave 12 is cleared | Enter Victory and do not start Wave 13 | Continue spawning, leave Reward open, or enter Defeat | A clear Victory state appears |

Wave composition for this benchmark:

| Wave | Basic | Runner | Tank | Boss |
|---:|---:|---:|---:|---:|
| 1 | 5 | 0 | 0 | 0 |
| 2 | 7 | 0 | 0 | 0 |
| 3 | 9 | 1 | 0 | 0 |
| 4 | 11 | 2 | 0 | 0 |
| 5 | 13 | 3 | 1 | 1 |
| 6 | 15 | 4 | 2 | 0 |
| 7 | 17 | 5 | 2 | 0 |
| 8 | 19 | 6 | 3 | 0 |
| 9 | 21 | 7 | 3 | 0 |
| 10 | 23 | 8 | 4 | 1 |
| 11 | 25 | 9 | 4 | 0 |
| 12 | 27 | 10 | 5 | 0 |

### 6.5 Enemies And Combat

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| ENEMY-01 | A Basic enemy exists | Use `10` HP, speed `50`, and `5` gold reward | Use another type's speed/HP/reward | Its identity is distinct and a kill awards `+5` |
| ENEMY-02 | A Runner exists | Use `5` HP, speed `125`, and `8` gold reward | Be slower than Basic or award the wrong amount | It visibly moves fastest and is fragile |
| ENEMY-03 | A Tank exists | Use `40` HP, speed `25`, and `20` gold reward | Be fast or award Basic gold | It visibly endures longer and moves slowly |
| ENEMY-04 | A Boss exists | Use `80` HP, speed `30`, and `50` gold reward; at or below half HP, spawn exactly three Basic minions once | Spawn repeatedly, omit minions, or award the wrong amount | The Boss and its minion event are recognizable |
| ENEMY-05 | An enemy reaches the base | Remove it, reduce base health by exactly `1`, and award no gold | Award a kill reward, deduct repeatedly, or leave the enemy on the path | Base health updates and the enemy disappears |
| ENEMY-06 | An enemy reaches zero HP | Remove it exactly once and award the listed gold exactly once | Continue moving it, award twice, or damage the base | The kill and gold change are visible |
| ENEMY-07 | Multiple enemies follow a route | Keep each enemy's route progress independent | Teleport, overlap permanently, or cause one leak to remove unrelated enemies | Enemies advance as individual visible objects |

### 6.6 Relic Rewards

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| REWARD-01 | Cleared wave is 1–11 | Pause combat and show exactly three clickable relic cards with distinct types | Show fewer/more than three, duplicate the same type, or skip the reward | Three readable choices appear |
| REWARD-02 | Click one reward card | Add that relic exactly once to the run and resume after a short confirmation | Apply multiple choices, apply none, or charge gold | The chosen card is identifiable and the next wave starts |
| REWARD-03 | A relic is held | Apply its listed global bonus to all current and future heroes using additive stacking | Require a hidden socket operation or silently ignore the bonus | Hero damage/attack state visibly or numerically reflects the bonus |
| REWARD-04 | Two matching Cracked or Polished relics of one type are held | Automatically combine the pair into one next-tier relic, repeating for new pairs; Flawless relics do not combine further. Replace the pair's bonuses with the new tier value | Lose both without a result or apply both old and new values | The combined relic and its tier/value are visible |
| REWARD-06 | Generate the three choices | Offer three different types from the nine listed relics, all at Cracked tier; selection is reproducible with the public seed | Offer an unpublished type or tier | Choice names, tiers and values match the table |
| REWARD-07 | Bonus combat effects apply | Cap critical chance at 100% and slow at 90%. Onyx burns for its listed duration at one tick per second, each tick dealing the greater of 1 and 20% of that hit's damage rounded down; later burning hits refresh duration without parallel burns. Bounces and chains each hit additional distinct living nearby targets once per shot; extra shots target distinct enemies when available. These bonuses affect all heroes, including Warrior strikes | Repeatedly hit one enemy with the same bounce/chain or keep removed targets active | Bonus hits, slow and burn have distinguishable feedback; exact secondary-target range is an implementation choice |
| REWARD-05 | Exactly one reward is chosen | Keep the reward state from reopening until the next wave is cleared | Re-open after the next wave starts or accept a second click from the same reward | Reward overlay disappears through the next wave |

Relic values:

| Relic | Cracked | Polished | Flawless | Effect |
|---|---:|---:|---:|---|
| Ruby | +5 | +10 | +15 | Hero damage |
| Sapphire | +5% | +10% | +15% | Attack speed |
| Emerald | +10 | +20 | +30 | Attack range |
| Topaz | +4% | +8% | +12% | Critical chance; a critical deals double damage |
| Amethyst | +10% | +20% | +30% | Slow on hit for 1.5 seconds |
| Tourmaline | +1 | +2 | +3 | Projectile bounces |
| Citrine | +1 | +2 | +3 | Extra simultaneous projectiles |
| Onyx | +2 s | +4 s | +6 s | Burning duration |
| Zircon | +1 | +2 | +3 | Chain targets |

### 6.7 Base, Success, And Lifecycle

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| BASE-01 | Base health changes | Display the exact current value and never below zero | Show stale health or negative HP | HUD updates with each leak |
| BASE-02 | Base health reaches zero | Enter Defeat, stop spawning/movement/attacks/rewards, and clear in-flight projectiles | Continue combat behind the result or enter Victory | Defeat state, reached wave, Restart, and Main Menu appear |
| BASE-03 | A run is in Defeat | Do not allow placement, reward selection, or further gold/health changes | Let old buttons remain active | Only result/lifecycle controls respond |
| SUCCESS-01 | Wave 12 is fully resolved with base health above zero | Enter Victory exactly once and stop combat | Enter Defeat or continue Wave 13 | Victory state, reached wave, Restart, and Main Menu appear |
| SUCCESS-02 | Click Restart from Victory or Defeat | Start a clean run with entry state and the same fixed map | Retain heroes, relics, projectiles, reward, gold, or health | A new run begins immediately |
| SESSION-01 | Click Main Menu from Victory or Defeat | Return to the main menu; Play starts a clean run | Resume the old battlefield | Menu and Play are usable again |
| SESSION-02 | Close the process and launch it again | Start at the menu with no restored run | Resume or write a battle save | Menu appears and Play creates a clean run |
| SESSION-03 | Restart or reopen repeatedly | Keep exactly one map, spawner, reward state, and HUD active | Duplicate listeners or waves | Repeated clean starts behave the same |

### 6.8 HUD And Feedback

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| HUD-01 | A run is active | Show gold, base health, current wave/12, and total living/unspawned enemies | Confuse health with gold or omit remaining enemies | All values update immediately |
| HUD-02 | A hero card is affordable/unaffordable | Distinguish usable and insufficient-gold states | Permit a negative-gold purchase | Card state matches gold |
| HUD-03 | Reward state is active | Show the three relic names, tiers, effects, and values | Show blank or implementation-only labels | The player can compare choices |
| HUD-04 | Victory or Defeat appears | Show the reached wave and not more than one terminal result | Continue changing the run HUD | Result remains stable until exit/restart |

### 6.9 Visual And Gameplay Quality

| ID | Preconditions and action | Must happen | Must not happen | Player-visible feedback |
|---|---|---|---|---|
| VISUAL-01 | Map is visible | Show a readable continuous grass area and a distinct path from spawn to base | Let visual path differ from actual movement/build blocking | Enemies and valid placement agree with the path |
| VISUAL-02 | Hero placement is active | Show green valid and red invalid preview states | Place without feedback or cover the target cell | The target cell remains visible |
| VISUAL-03 | Three hero roles are on screen | Use distinct supplied hero/tower sprites and recognizable attack feedback | Collapse all roles into indistinguishable visuals | The player can tell Archer, Mage, and Warrior |
| VISUAL-04 | Four enemy roles are on screen | Use distinct supplied enemy sprites and readable health/damage feedback | Hide the Boss among normal enemies or use missing textures | Enemy type and remaining health are understandable |
| VISUAL-05 | Ranged hero attacks are visible | Use the supplied projectile identity, with tint/scale allowed for distinct effects | Omit visible ranged attack feedback | Projectile travel and impact remain readable |
| QUALITY-01 | Play a complete run | Remain stable through twelve waves, rewards, death, victory, restart, menu, and Reopen | Crash, freeze, dead-end, or lose required input | Complete flow is reachable |
| QUALITY-02 | Use normal mouse input | Reach all required interactions through visible controls | Require hidden keys, internal calls, or debug menus | Clicks produce immediate feedback |
| QUALITY-03 | Victory or Defeat is visible | Stop gameplay actions except Restart/Main Menu/close | Let wave simulation continue behind the result | Result is final and stable |

## 7. Success, Failure, And Multi-Stage Flow

### 7.1 Success

| Requirement | Condition | Result |
|---|---|---|
| `SUCCESS-01` | Wave 12 fully resolved and base health above zero | Victory with final wave, Restart, and Main Menu |

### 7.2 Failure

| Requirement | Condition | Result |
|---|---|---|
| `BASE-02` | Base health reaches zero | Defeat with reached wave, Restart, and Main Menu |

### 7.3 Multi-Stage Flow

| Stage | Required IDs | Summary | Must not appear early |
|---|---|---|---|
| Preparation | `ENTRY-02`, `PLACE-01`–`PLACE-04` | Buy and place heroes | Reward, Victory, Defeat |
| Waves 1–11 | `WAVE-01`–`WAVE-06`, `REWARD-01`–`REWARD-05` | Combat then one reward | Wave 12, Victory |
| Wave 12 | `WAVE-06`, `SUCCESS-01` | Final combat and Victory | Reward, Wave 13 |

## 8. Interface And Feedback

| Requirement | Information | Update timing | Player must distinguish |
|---|---|---|---|
| `HUD-01` | Gold, health, wave, remaining enemies | On every change | Resources, progress, danger |
| `HUD-02` | Hero affordability | On gold/hero-card change | Valid versus unavailable purchase |
| `HUD-03` | Three relic choices | On reward entry | Relic type, tier, effect |
| `HUD-04` | Victory/Defeat | On terminal transition | Won versus lost |

## 9. Restart, Reopen, And Save

| Scenario | Requirement | Reset | Preserve | Final state |
|---|---|---|---|---|
| Restart | `SUCCESS-02` | Gold, health, heroes, relics, wave, enemies, projectiles, UI | Nothing run-related | Clean Wave 0 run |
| Main Menu | `SESSION-01` | Active run | Nothing run-related | Menu |
| Close/reopen | `SESSION-02` | All run state | Nothing | Menu |

## 10. Existing Functionality To Preserve

Not applicable. This is a reduced reconstruction, not an extension of a public starter.

## 11. Material And Content Requirements

| Requirement | Material | Hard requirement | Use | Replacement |
|---|---|---|---|---|
| `VISUAL-01` | Supplied ground tileset and portal sprite | Yes | Grass/path and spawn identity | No for the supplied role |
| `VISUAL-03` | Supplied Archer, Mage, and Warrior source art | Yes | Distinct hero roles | No; processing is free |
| `VISUAL-04` | Supplied Basic, Runner, Tank, and Boss source art | Yes | Distinct enemy roles | No; processing is free |
| `VISUAL-05` | Supplied projectile art | Yes | Attack feedback | No for the supplied role |



## 12. Dashboard Naming Tables And Control Scheme

Positions use the fixed 18-by-10 map grid, origin top-left, x right, y down. Targets use viewport pixels in the `960x540` viewport.

### 12.1 Numeric Slots

| Slot | Meaning | Requirement |
|---|---|---|
| `gold` | Current gold | `ENTRY-02`, `PLACE-04` |
| `base_hp` | Current base health | `BASE-01` |
| `wave` | Current wave, `0` during preparation | `WAVE-01`, `HUD-01` |
| `total_waves` | Always `12` | `WAVE-06` |
| `enemies_remaining` | Living plus unspawned enemies in the current wave | `WAVE-02`, `HUD-01` |
| `heroes_placed` | Placed hero count | `PLACE-02` |
| `relics_owned` | Relics held in the run | `REWARD-02` |

### 12.2 Entities And Clickable Targets

| Kind | Meaning | Allowed states | Requirement |
|---|---|---|---|
| `hero` | Placed Archer, Mage, or Warrior | `archer`, `mage`, `warrior` | `PLACE-02`, `HERO-01`–`HERO-03` |
| `enemy` | Active enemy | `basic`, `runner`, `tank`, `boss` | `ENEMY-01`–`ENEMY-04` |
| `projectile` | Visible attack projectile | `hero`, `burning`, `slowed` | `HERO-04`, `REWARD-03` |
| `portal` | Enemy entry point | `locked`, `open` | `WAVE-04` |
| `base` | Defended destination | `healthy`, `critical` | `BASE-01` |
| `play_button` | Starts a run | — | `ENTRY-01` |
| `hero_card_archer` | Archer purchase card | — | `PLACE-01`, `HERO-01` |
| `hero_card_mage` | Mage purchase card | — | `PLACE-01`, `HERO-02` |
| `hero_card_warrior` | Warrior purchase card | — | `PLACE-01`, `HERO-03` |
| `reward_card_1`, `reward_card_2`, `reward_card_3` | Three relic choices | — | `REWARD-01` |
| `restart_button` | Starts a clean run | — | `SUCCESS-02` |
| `main_menu_button` | Returns to the menu | — | `SESSION-01` |

### 12.3 Control Scheme

| Item | Value |
|---|---|
| Movement template | Mouse click placement; no continuous player movement |
| Keys | Optional Escape may return to the menu after a result; it is not required for the main flow |
| Pointer | Left click selects cards and battlefield cells |

## 13. Implementation Boundaries

- Section 6 is the only source of game-specific acceptance requirements.
- The dashboard is read-only and cannot buy, place, attack, reward, reset, or force an ending.
- Node names, scripts, map implementation, target-selection algorithm, and projectile architecture are free.
- Exact project entry, paths, material locations, and dashboard transport are defined by `TOOLCHAIN-en.md` and `BENCHMARK_MANIFEST.json`.

## 14. Requirement Index

| ID | Summary |
|---|---|
| `ENTRY-01`–`ENTRY-02` | Menu and clean run start |
| `PLACE-01`–`PLACE-04` | Selection, placement, rejection, cost |
| `HERO-01`–`HERO-06` | Three hero roles and independent attacks |
| `WAVE-01`–`WAVE-06` | Twelve waves, composition, cadence, portals, terminal transition |
| `ENEMY-01`–`ENEMY-07` | Enemy identities, rewards, leaks, boss minions |
| `REWARD-01`–`REWARD-05` | Reward choice, application, combination |
| `BASE-01`–`BASE-03` | Health, defeat, terminal lock |
| `SUCCESS-01`–`SUCCESS-02` | Victory and restart |
| `SESSION-01`–`SESSION-03` | Menu, reopen, lifecycle |
| `HUD-01`–`HUD-04` | State and result display |
| `VISUAL-01`–`VISUAL-04` | Map, placement, heroes, enemies |
| `QUALITY-01`–`QUALITY-03` | Stability, input reachability, terminal discipline |
