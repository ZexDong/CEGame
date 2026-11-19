# Dungeon Four Shot — Game Design Document

> Version: v0.24  
> Sections 1–5 and 7–9 are explanatory guidance only and create no independent requirements. The numbered identifiers in Section 6 are the complete game-specific contract. If any summary conflicts with Section 6, Section 6 prevails.

## 1. One-Sentence Task (Non-Normative)

From the level-select screen, the player enters six independent short levels and experiences movement, two firearms, a three-bomb-per-level tool, slime room clears, exploration and upgrades, the four original boss stages, and a new four-room Level 6 route that ends in a boss fight.

## 2. Scope Summary (Non-Normative)

| Requirement group | Summary |
|---|---|
| Entry | Main menu, controls page, level select, briefing, and common initial state |
| Level | Scenes, objectives, and results for six independent levels |
| Rules | Two firearms, bombs, dash, slimes, rooms, map, upgrades, and the boss state machine |
| UI | HUD, feedback, modal pages, results, and usability |
| Restart and Persistence | Retry, next level, level switching, exit, and close/reopen |
| Assets | Character, enemy, room, weapon, upgrade, font, background, and audio mapping |

The scope excludes the original FourShot design's 12–15 random rooms, random 5×5 world map, random starting room, boss leaf room 5–7 steps from the start, one continuous long exploration run, unseeded gameplay randomness, networking, accounts, story, metagame progression, continuation saves, controller support, and mobile support. This paragraph is only a scope summary and creates no additional prohibitions; the binding boundaries are in Section 6.

## 3. Initial-State Summary (Non-Normative)

The main menu appears first after launch, and all six levels are unlocked by default. The common initial state is 200/200 health, level 1, 0/100 XP, both guns fully loaded, HK-67 selected, and 3 bombs. Level 3 starts at 40/100 XP; Levels 4 and 5 use their respective boss progress; Level 5 also has preset progression; Level 6 uses its fixed four-room route. See ENTRY-05a–05p, LEVEL-03a, LEVEL-04a–04s, LEVEL-06a–06p, and BOMB-01a–01o for exact requirements.

## 4. Flow Summary (Non-Normative)

```text
Main menu → Controls page or level select → Level briefing → Normal play
→ Level Complete / Victory / Defeat
→ Next Level, Retry, Level Select, or Main Menu
```

## 5. Control Summary (Non-Normative)

| Input | Summary |
|---|---|
| W/A/S/D | Eight-direction movement; every nonzero movement direction also becomes the persistent shooting direction |
| Mouse movement, left button | Mouse movement does not aim; left-button input fires in the last nonzero WASD movement direction |
| Space | Place a bomb |
| Shift, R, 1/2 | Dash, reload, switch conventional weapon |
| Tab | Toggle the three-room map during non-combat states in Level 3 |
| Esc | Close the map, pause/resume, or perform the return action defined for the current modal state |
| Visible buttons | Menu, briefing, upgrade, pause, and result actions |

## 6. Sole Normative Specification and Public Acceptance Contract

### 6.0 Requirement Interpretation and Public Tolerances

- Identifiers with a letter suffix describe independently observable outcomes. Unsuffixed identifiers group related outcomes and add no extra behavior.
- Fixed enums, state tuples, and numeric values stated in this section are public gameplay rules; equivalent implementation details are allowed.
- Required outcomes must be reachable through ordinary keyboard/mouse input and visible to the player. Internal organization, unpublished paths, and unspecified events are not requirements.
- Health, ammunition, XP, level, enemy count, objective count, and boss progress are checked as exact integers. Angle tolerance is ±1°; position tolerance is ±4 pixels; speed, range, and distance thresholds use the larger of ±5% of the nominal value and ±4 pixels; time values no greater than 1 second allow ±0.05 seconds, and time values greater than 1 second allow ±0.15 seconds.
- All time is measured in engine seconds accumulated during normal gameplay and is independent of render frame rate. Gameplay timers do not advance while paused or while the map, upgrade, briefing, or result modal is open. Allowed error includes at most one normal update step; no additional hidden tolerance may be used.
- Intervals use left-closed, right-open notation: `[start, end)` includes the start and excludes the end. Screen coordinates use the 1280×720 viewport as their basis; room-local coordinates use the top-left of the playable room as `(0,0)`.
- No external reference image is part of the public contract. Visual acceptance is defined by the numbered UI and asset outcomes in Sections 6.4 and 6.6 at the public 1280×720 viewport.
- An outcome is established only after its corresponding normal player journey has actually run and the result is visible. A partial journey or source inspection does not establish completion of the journey.

### 6.1 Entry, Briefing, and Common Initial State

| ID | Atomic observable result |
|---|---|
| ENTRY-01a | A new process first displays the main menu and does not automatically enter any level. |
| ENTRY-01b | The main menu displays an available “Start Game” entry. |
| ENTRY-01c | The main menu displays an available “Controls” entry. |
| ENTRY-01d | The main menu displays an available “Exit Game” entry. |
| ENTRY-01e | The controls page displays an available entry for returning to the main menu. |
| ENTRY-01f | Clicking “Exit Game” closes the current process without displaying a confirmation dialog. |
| ENTRY-02a | Clicking “Start Game” opens the level-select screen. |
| ENTRY-02b | The level-select screen simultaneously shows the names of Levels 1–6. |
| ENTRY-02c | Every level card shows that level's core objective and a clickable entry control. |
| ENTRY-02d | All six levels are unlocked from the first launch; completing a previous level is not required. |
| ENTRY-03a | Clicking a level entry opens only the selected level's briefing and never briefly enters another level. |
| ENTRY-03b | Exactly one player for the current level exists at any moment. |
| ENTRY-03c | Exactly one HUD for the current level exists at any moment. |
| ENTRY-03d | Exactly one set of level objects for the current level exists at any moment. |
| ENTRY-03e | Exactly one input response layer for the current level exists at any moment. |
| ENTRY-03f | Exactly one BGM track matching the current page or level plays at any moment. |
| ENTRY-03g | At 1280×720, each of the six levels can be entered independently from the level-select screen using a normal mouse click. |
| ENTRY-04a | Each level briefing displays the level number. |
| ENTRY-04b | Each level briefing displays the level name. |
| ENTRY-04c | Each level briefing displays the level objective. |
| ENTRY-04d | Each level briefing displays the level completion condition. |
| ENTRY-04e | The briefing displays a “Start Level” entry. |
| ENTRY-04f | The briefing displays a “Back to Level Select” entry. |
| ENTRY-04g | All gameplay objects and gameplay timers are frozen during the briefing. |
| ENTRY-04h | Gameplay keys do not change level state during the briefing. |
| ENTRY-04i | Pressing Esc during the briefing returns to level select. |
| ENTRY-04j | The first controllable frame of the level is entered only by clicking “Start Level.” |
| ENTRY-04k | The first controllable frame is `t=0` for the level's gameplay timers. |
| ENTRY-04l | In direct boss Levels 4–5, the boss's first summon and first attack are timed from the `t=0` defined by ENTRY-04k; in Level 6, their timer origin is the first controllable frame after entering the boss room. |
| ENTRY-04m | Briefing text does not directly mark any objective complete. |
| ENTRY-04n | Briefing text does not directly trigger completion, victory, or defeat. |
| ENTRY-05a | Health is 200/200 on every new level entry or retry. |
| ENTRY-05b | Level is 1 on every new level entry or retry except in Levels 5 and 6. |
| ENTRY-05c | XP is 0/100 on every new level entry or retry except in Levels 3, 5, and 6. |
| ENTRY-05d | HK-67 is the selected conventional weapon. |
| ENTRY-05e | HK-67 starts with 30/30 ammunition. |
| ENTRY-05f | Glock-21 starts with 8/8 ammunition. |
| ENTRY-05g | Neither gun has a reserve-ammunition limit. |
| ENTRY-05h | No reload is in progress in the initial state. |
| ENTRY-05i | No special sniper rifle exists in the initial state. |
| ENTRY-05j | No player projectiles exist in the initial state. |
| ENTRY-05k | No enemy projectiles exist in the initial state. |
| ENTRY-05l | No old objective-completion state remains in the initial state. |
| ENTRY-05m | No old enemies remain in the initial state. |
| ENTRY-05n | No old upgrade choice or result state remains in the initial state. |
| ENTRY-05o | Levels 3–6 apply only the initial-state exceptions specified by LEVEL-03a, LEVEL-04a, 04d–04o, and LEVEL-06a–06p. |
| ENTRY-05p | Every fresh level entry and retry starts with exactly 3 available bombs and no placed bomb or pending explosion. |

### 6.2 Six Independent Levels

#### Level 1 — “Firearms Training Ground”

| ID | Atomic observable result |
|---|---|
| LEVEL-01a | Level 1 contains exactly one clearly bounded training room. |
| LEVEL-01b | The training room always displays four training targets that do not move, attack, or deal damage. |
| LEVEL-01c | The training room provides enough space for eight-direction movement and dashing. |
| LEVEL-01d | Objective 1 is marked complete only after the player actually moves at least 32 pixels away from the starting point using WASD. |
| LEVEL-01e | Objective 2 is marked complete only after the player actually performs one dash. |
| LEVEL-01f | Objective 3 is marked complete only after an HK-67 projectile actually hits a training target. |
| LEVEL-01g | Objective 4 is marked complete only after at least 4 HK-67 rounds have been spent and one reload has fully completed. |
| LEVEL-01h | Objective 5 is marked complete only after switching to Glock-21 and hitting a target different from the target used for Objective 3. |
| LEVEL-01i | Objective 6 is marked complete only after Space places a bomb and that bomb's explosion overlaps at least one training target; training targets remain non-hostile and the player receives 0 damage. |
| LEVEL-01j | The six objectives must be completed in Objective 1→6 order; performing a later action early does not pre-complete later objectives. |
| LEVEL-01k | “Level Complete” appears exactly once after all six objectives are marked complete. |

#### Level 2 — “Slime Blockade”

| ID | Atomic observable result |
|---|---|
| LEVEL-02a | Level 2 is one normal combat room and displays at least two distinguishable exit doors. |
| LEVEL-02b | The initial state always spawns 1 normal slime. |
| LEVEL-02c | The initial state always spawns 1 elite slime. |
| LEVEL-02d | Both slimes spawn in a visible walkable area without overlapping the player, walls, doors, or obstacles. |
| LEVEL-02e | Both exit doors display as locked from the first controllable frame. |
| LEVEL-02f | While either slime is alive, the player cannot cross an exit door or complete the level. |
| LEVEL-02g | The two doors express only this room's locked/unlocked state and do not transport the player to another room. |
| LEVEL-02h | The room-clear result is applied exactly once when both slimes are dead. |
| LEVEL-02i | Both doors change to the open state when the room is cleared. |
| LEVEL-02j | Current health increases by 20 when the room is cleared, without exceeding maximum health. |
| LEVEL-02k | Below full health, feedback shows the actual amount restored; at full health, feedback says “Health Full” or “+0” and must not falsely report an actual increase of 20. |
| LEVEL-02l | The open-door and health feedback remains visible for at least 0.90 seconds before the completion layer appears. |
| LEVEL-02m | “Level Complete” appears exactly once after the 0.90-second feedback period. |
| LEVEL-02n | Tab does not open the world map in Level 2. |

#### Level 3 — “Exploration and Growth”

| ID | Atomic observable result |
|---|---|
| LEVEL-03a | Level 3 starts at level 1 and 40/100 XP; all other player initial state follows ENTRY-05. |
| LEVEL-03b | The world-map topology contains exactly three formal rooms: the safe starting room, one combat room, and the exit room. |
| LEVEL-03c | The three rooms form exactly one connected path: `safe starting room ↔ combat room ↔ exit room`. |
| LEVEL-03d | First entry into the combat room always spawns 1 normal slime. |
| LEVEL-03e | First entry into the combat room always spawns 1 elite slime. |
| LEVEL-03f | The two slimes award 60 XP in total, so clearing the room reaches exactly 100 XP and triggers one upgrade. |
| LEVEL-03g | After the combat room is cleared, it does not respawn enemies or heal again, and its obstacle layout remains the same on revisits. |
| LEVEL-03h | Outside combat, continuing to move into an open doorway enters the adjacent room. |
| LEVEL-03i | After a room transition, the player appears just inside the corresponding opposite doorway and is not immediately sent back. |
| LEVEL-03j | Locked doors cannot be crossed, and non-doorway wall areas cannot trigger a room transition. |
| LEVEL-03k | Every connection is traversable both ways, and the route from start to exit must pass through the combat room. |
| LEVEL-03l | The HUD formally lists four objectives: “Clear the combat room,” “View the map,” “Complete an upgrade,” and “Reach the exit room.” |
| LEVEL-03m | “Clear the combat room” is marked complete when the sole combat room is first cleared. |
| LEVEL-03n | “View the map” is marked complete after the complete map has been displayed for at least one rendered frame. |
| LEVEL-03o | “Complete an upgrade” is marked complete after the player chooses and applies one upgrade. |
| LEVEL-03p | “Reach the exit room” is marked complete only while the player is in the exit room and the first three objectives are complete. |
| LEVEL-03q | The four objectives may be completed in any order; reaching the exit room early does not lose the player's exit-room state. |
| LEVEL-03r | If the player is already in the exit room and completes the last of the first three objectives, the level can complete in place after the corresponding modal closes; leaving and re-entering is not required. |
| LEVEL-03s | “Level Complete” appears exactly once while all four objectives are complete and the player remains in the exit room. |

#### Levels 4/5 — “Golem Trial”

| ID | Atomic observable result |
|---|---|
| LEVEL-04a | Level 4 enters an independent boss room directly and starts with boss progress at 4/4. |
| LEVEL-04b | Level 4 handles only the 4/4 and 3/4 stages. |
| LEVEL-04c | When Level 4 reaches 2/4 progress, it immediately displays “Level Complete” and does not start the 2/4 stage. |
| LEVEL-04d | Level 5 enters an independent boss room directly and starts with boss progress at 2/4. |
| LEVEL-04e | Level 5 starts at 200/200 health. |
| LEVEL-04f | Level 5 starts at level 3. |
| LEVEL-04g | Level 5 starts at 0/500 XP. |
| LEVEL-04h | Level 5 starts with exactly one damage upgrade already applied. |
| LEVEL-04i | Level 5 starts with exactly one speed upgrade already applied. |
| LEVEL-04j | HK-67 starts Level 5 with 26 damage per shot. |
| LEVEL-04k | Glock-21 starts Level 5 with 41 damage per shot. |
| LEVEL-04l | Normal movement speed starts Level 5 at 180 pixels/second. |
| LEVEL-04m | Dash speed remains 450 pixels/second in Level 5. |
| LEVEL-04n | Both conventional guns start Level 5 with full magazines. |
| LEVEL-04o | No special sniper rifle exists in Level 5's initial state. |
| LEVEL-04p | Level 5 handles only the 2/4 and 1/4 stages. |
| LEVEL-04q | Level 5 immediately displays “Victory” when progress reaches 0/4. |
| LEVEL-04r | Levels 4 and 5 cannot complete or win before reaching their respective target progress. |
| LEVEL-04s | Hits on the boss from normal conventional weapons or bombs do not change boss progress. |

#### Level 6 — “Slime Citadel”

| ID | Atomic observable result |
|---|---|
| LEVEL-06a | Level 6 starts in a safe room at coordinate `(0,0)` with only its right doorway available and with the clean 3-bomb state from ENTRY-05p. |
| LEVEL-06b | The right room at `(1,0)` spawns exactly 2 normal slimes on first entry and locks its exits while either is alive. |
| LEVEL-06c | Defeating both normal slimes clears `(1,0)` exactly once and opens its upper doorway. |
| LEVEL-06d | The upper room at `(1,-1)` spawns exactly 1 elite slime on first entry and locks its exits while it is alive. |
| LEVEL-06e | Defeating the elite slime clears `(1,-1)` exactly once and opens its left doorway. |
| LEVEL-06f | The left room at `(0,-1)` is the boss room and contains exactly one Spire Golem boss encounter. |
| LEVEL-06g | The only route to the boss is `(0,0) → (1,0) → (1,-1) → (0,-1)`; non-doorway boundaries and unopened exits cannot be crossed. |
| LEVEL-06h | Revisiting either cleared slime room does not respawn enemies, repeat XP/healing, or restore bomb count. |
| LEVEL-06i | Level 6's boss encounter begins at boss progress 2/4 and uses the 2/4 and 1/4 stages from RULE-11–13. |
| LEVEL-06j | The boss room locks its exit until progress reaches 0/4. |
| LEVEL-06k | Level 6 displays Victory exactly once when boss progress reaches 0/4 and cannot win while the boss remains undefeated. |
| LEVEL-06l | Level 6 starts at level 3, 0/500 XP, with one damage and one speed upgrade already applied. |
| LEVEL-06m | HK-67 starts Level 6 at 26 damage, Glock-21 at 41 damage, and normal movement speed at 180 pixels/second; dash remains 450 pixels/second. |
| LEVEL-06n | Both conventional guns start Level 6 full and no special sniper exists before the boss-stage rules create one. |
| LEVEL-06o | Bomb count is shared across all four Level 6 rooms; room changes never reset it. |
| LEVEL-06p | The HUD shows the current room, the ordered four-room objective, living enemies, and the remaining bomb count. |

### 6.3 Gameplay Rules

#### Two Firearms, Reloading, and Facing

| ID | Atomic observable result |
|---|---|
| RULE-01a | HK-67 magazine capacity is 30. |
| RULE-01b | HK-67 base damage is 25. |
| RULE-01c | HK-67 firing interval is 0.15 seconds. |
| RULE-01d | During normal play, holding the left mouse button fires the selected HK-67 once every 0.15 seconds in the persistent shooting direction established by the last nonzero WASD movement input; before the first movement input, the initial right-facing direction is used. |
| RULE-01e | HK-67 reload time is 0.60 seconds. |
| RULE-01f | HK-67 projectile speed is 600 pixels/second. |
| RULE-01g | HK-67 maximum travel distance is 210 pixels. |
| RULE-02a | Glock-21 magazine capacity is 8. |
| RULE-02b | Glock-21 base damage is 40. |
| RULE-02c | Glock-21 firing interval is 0.60 seconds. |
| RULE-02d | During normal play, each left-button press fires at most one selected Glock-21 round in the persistent shooting direction established by the last nonzero WASD movement input; before the first movement input, the initial right-facing direction is used. |
| RULE-02e | Glock-21 reload time is 0.80 seconds. |
| RULE-02f | Glock-21 projectile speed is 300 pixels/second. |
| RULE-02g | Glock-21 maximum travel distance is 150 pixels. |
| RULE-03a | Pressing R starts a reload when the selected conventional gun's magazine is not full and no reload is in progress. |
| RULE-03b | Ammunition does not increase before reload completion; on completion, the magazine is filled to capacity at once. |
| RULE-03c | When a left-button firing attempt occurs with an empty magazine, reloading starts automatically; pressing R with a full magazine changes no state. |
| RULE-03d | Firing attempts and pressing R again during a reload are ignored and do not cancel or reset the reload. |
| RULE-03e | Movement and dashing are allowed during a reload and do not cancel it. |
| RULE-03f | Switching with 1/2 preserves each gun's ammunition and cancels the current incomplete reload. |
| RULE-03g | Opening the map, pausing, or opening the upgrade modal freezes remaining reload time; normal play resumes from the previous progress. |
| RULE-03h | Neither conventional gun uses reserve-ammunition limits. |
| RULE-03i | The player initially shoots right. Each nonzero resultant WASD movement input updates the persistent shooting direction to the same one of eight movement directions: Up, Down, Left, Right, Up-Left, Up-Right, Down-Left, or Down-Right. Releasing one or all movement keys preserves the last nonzero direction; an input combination whose opposing axes cancel to zero does not replace it. Mouse position and arrow-key input never change the shooting direction. |
| RULE-03j | Every conventional and special shot travels in the persistent direction established by the last nonzero WASD movement input. The gun body, muzzle flash, and actual projectile initial direction agree with that direction while moving and after the player stops. |
| RULE-03k | Shooting left flips the weapon correctly without turning it upside down. |
| RULE-03l | R and 1/2 are ignored while holding the special sniper rifle. |
| RULE-03m | Merely moving the mouse, pressing or releasing WASD, or pressing or releasing an arrow key without a left-button firing attempt never creates a projectile; left-button input is the only normal-play firing trigger. |

#### Movement, Dash, and Damage Immunity

| ID | Atomic observable result |
|---|---|
| RULE-04a | The player's normal base speed is 150 pixels/second, with equal resultant speed for axial and diagonal movement. |
| RULE-04b | With movement input, Shift dashes in the normalized movement direction. |
| RULE-04c | Without movement input, Shift dashes from the player toward the mouse. |
| RULE-04d | Dash speed is 450 pixels/second over `[t0,t0+0.15)`. |
| RULE-04e | Dash cooldown begins at dash start and occupies `[t0,t0+0.80)`; further Shift presses in that interval are ignored. |
| RULE-04f | The damage-immunity interval is `[t0,t0+0.35)`, covering the dash and 0.20 seconds after it ends. |
| RULE-04g | Enemy projectiles that hit during immunity deal 0 damage and are removed immediately; damage is not applied later when immunity ends. |
| RULE-04h | Golem contact during immunity deals 0 damage, but that contact still starts that golem's 0.80-second contact cooldown. |
| RULE-04i | Continuous contact with the same golem does not require exit and re-entry; it can deal damage again after its contact cooldown ends if the player is no longer immune. |

#### Bombs

| ID | Atomic observable result |
|---|---|
| BOMB-01a | Each level starts or retries with exactly 3 available bombs; the inventory is per level and is never replenished by room clears, pickups, upgrades, or room transitions. |
| BOMB-01b | During normal play, one Space press with at least 1 bomb available places exactly one stationary bomb centered at the player's current legal position and immediately decreases the available count by 1. |
| BOMB-01c | A placed bomb has a visible fuse state and detonates exactly once 1.50 seconds after placement. |
| BOMB-01d | The explosion is a circle of radius 48 pixels, so its 96-pixel diameter is approximately three times the player's 32-pixel body width; the visible blast matches that collision area. |
| BOMB-01e | Each normal slime, elite slime, lesser golem, or elite golem whose hit area intersects the blast receives exactly 100 damage once from that bomb. |
| BOMB-01f | Bomb damage never changes player health, player immunity, or dash state, even when the player's hit area overlaps the blast. |
| BOMB-01g | A blast can damage multiple eligible enemies, but one enemy cannot receive more than one damage application from one bomb. |
| BOMB-01h | Walls, closed/locked doors, and obstacles block the blast between bomb and enemy; an enemy behind a blocker receives 0 bomb damage. |
| BOMB-01i | The Spire Golem boss remains immune to bomb damage and boss progress changes only through the special-sniper rules; the blast gives visible immunity feedback when it overlaps the boss. |
| BOMB-01j | Pressing Space with 0 bombs changes no bomb, enemy, projectile, player, objective, or room state and shows visible “No Bombs” feedback. |
| BOMB-01k | The available bomb count never falls below 0, and no placement creates more than one bomb or consumes more than one charge. |
| BOMB-01l | Multiple placed bombs keep independent fuses; one explosion does not trigger, remove, or duplicate another bomb. |
| BOMB-01m | Bomb fuses freeze during briefing, map, upgrade, pause, and result modals and resume with their remaining time afterward. |
| BOMB-01n | Level completion, victory, defeat, retry, level exit, or return to menu removes all placed bombs and pending blasts from the old level. |
| BOMB-01o | For Level 1 training only, training targets are valid explosion-overlap witnesses for LEVEL-01i but take no persistent damage and are not counted as living enemies. |

#### Normal and Elite Slimes

| ID | Atomic observable result |
|---|---|
| RULE-05a | Normal slime health is 80. |
| RULE-05b | A normal slime awards 20 XP on death. |
| RULE-05c | Elite slime health is 300. |
| RULE-05d | An elite slime awards 40 XP on death. |
| RULE-05e | Both slime types have a 202-pixel player-detection radius. |
| RULE-05f | At distances greater than 202, both slime types wander at 28 pixels/second. |
| RULE-05g | Without obstruction, wander direction is reselected every 0.80–2.00 seconds. |
| RULE-05h | When wandering is obstructed, direction changes on the next normal update step. |
| RULE-05i | With no obstruction during 2.20 continuous seconds of normal play, a slime cannot remain at exactly its spawn position for the entire period. |
| RULE-05j | Within detection range and farther than 170 pixels, a slime approaches the player at 60 pixels/second. |
| RULE-05k | Within detection range and closer than 125 pixels, a slime retreats at 60 pixels/second. |
| RULE-05l | Within detection range and at distance `[125,170]`, a slime strafes at 48 pixels/second. |
| RULE-05m | Neither slime type may move into walls, locked doors, obstacles, or outside room boundaries. |
| RULE-06a | After detecting the player, a normal slime attacks at most once every 0.80 seconds. |
| RULE-06b | Each normal-slime attack fires 3 projectiles. |
| RULE-06c | Normal-slime projectile angles relative to the player direction are -15°, 0°, and +15°. |
| RULE-06d | Each normal-slime projectile deals 1 damage. |
| RULE-06e | Normal-slime projectile speed is 250 pixels/second. |
| RULE-06f | Normal-slime projectile range is 600 pixels. |
| RULE-06g | After detecting the player, an elite slime attacks at most once every 0.80 seconds. |
| RULE-06h | Each elite-slime attack fires 7 projectiles. |
| RULE-06i | Elite-slime projectile angles relative to the player direction are -15°, -10°, -5°, 0°, +5°, +10°, and +15°. |
| RULE-06j | Each elite-slime projectile deals 2 damage. |
| RULE-06k | Elite-slime projectile speed is 250 pixels/second. |
| RULE-06l | Elite-slime projectile range is 600 pixels. |
| RULE-07a | The combat rooms in Levels 2 and 3 both use the fixed lineup `1 normal + 1 elite`. |
| RULE-07b | Slime spawn points are at least 150 pixels from the player. |
| RULE-07c | Slime spawn points cannot be in walls, doors, obstacles, or outside room boundaries. |
| RULE-07d | Every fresh level entry and Retry initializes the gameplay random source to decimal seed `41041`, unless an evaluator supplies another decimal seed through the public command-line entry defined in `TOOLCHAIN-en.md`. |
| RULE-07e | Slime wander choices, any selection among multiple legal spawn corrections, and any other stochastic gameplay choice use only that gameplay random source; the same seed, level, and timed player-input sequence reproduce the same choices. |

#### Room Clear, Doors, and Map

| ID | Atomic observable result |
|---|---|
| RULE-08a | All valid exits lock when combat first begins in a combat room. |
| RULE-08b | Touching a locked door while any enemy is alive leaves the player in the original room. |
| RULE-08c | The room is marked cleared exactly once after the last enemy dies. |
| RULE-08d | The first room clear opens all valid exits and applies one actual health restoration. |
| RULE-08e | Re-entering a cleared room does not spawn new enemies or repeat healing. |
| RULE-08f | Re-entering a cleared room preserves its original obstacle layout. |
| RULE-08g | After entering an adjacent room through an open door, the player is just inside the opposite door and at least 40 pixels from the boundary. |
| RULE-09a | The normal-play HUD continuously displays a minimap. |
| RULE-09b | The minimap player marker changes according to the player's room-local coordinates. |
| RULE-09c | The minimap shows red markers only for living enemies in the current room, changing according to their room-local coordinates. |
| RULE-09d | In Level 3, both player and enemy minimap markers are constrained inside the current room cell. |
| RULE-09e | Other Level 3 room cells show only unvisited, visited, or cleared state and do not show current-room entity markers. |
| RULE-09f | Pressing Tab outside combat in Level 3 opens the three-room world map. |
| RULE-09g | Tab does not open the world map during combat; if combat begins before an open map, the map cannot remain open. |
| RULE-09h | The world map shows exactly three formal rooms, two connections, visit/clear state, and the current room. |
| RULE-09i | The world-map player marker uses room-local coordinates and is constrained inside the current room box. |
| RULE-09j | “View the map” is completed only after the full world map has appeared for at least one rendered frame. |
| RULE-09k | While on the world map, Tab, Esc, or clicking a visible “Return to Game” control closes it and returns to the original room. |

#### Experience and Upgrades

| ID | Atomic observable result |
|---|---|
| RULE-10a | Reachable upgrade thresholds in these six levels are 100 at level 1 and 500 as the next threshold for preset level 3 in Levels 5 and 6; the HUD and read-only state show the current threshold. |
| RULE-10b | Reaching the current threshold subtracts that threshold exactly once and preserves overflow XP. |
| RULE-10c | Reaching the threshold immediately freezes gameplay and displays Health, Damage, and Speed upgrade choices. |
| RULE-10d | One upgrade must be chosen and the modal cannot be canceled; Esc, Tab, R, 1/2, Space, Shift, movement, and firing are ignored. |
| RULE-10e | Health upgrade applies `max_hp'=max_hp+10` and `hp'=min(max_hp',hp+10)`. |
| RULE-10f | In the reachable `n=0/1` states, HK-67 damage per shot is `25+n`; the result is an integer with no additional rounding. |
| RULE-10g | Damage upgrade does not affect slimes, golems, the boss, enemy projectiles, or the special sniper rifle. |
| RULE-10h | In the reachable `n=0/1` states, normal movement speed is `150×(1+0.2n)`. |
| RULE-10i | Speed upgrade does not affect the 450 dash speed, projectile speeds, or enemy speeds. |
| RULE-10j | A choice applies only the selected upgrade and applies it once. |
| RULE-10k | A choice increases level by 1. |
| RULE-10l | A choice updates the next upgrade threshold. |
| RULE-10m | After a choice, play resumes in the room occupied before the choice. |
| RULE-10n | In the reachable `n=0/1` states, Glock-21 damage per shot is `40+n`; the result is an integer with no additional rounding. |
| RULE-10o | Level 3's fixed 60 XP triggers exactly one upgrade and does not immediately open a second upgrade after the choice. |
| RULE-10p | Public initial states and fixed enemy rewards in the six levels do not create unreachable chained-upgrade or max-level fixtures. |

#### Boss Attacks and Per-Stage State Machine

| ID | Atomic observable result |
|---|---|
| RULE-11a | Stage kills are 0 at the start of every boss stage. |
| RULE-11b | The first summon of Level 4's 4/4 stage occurs 8.00 seconds after the first controllable frame, not from briefing load time. |
| RULE-11c | The summon interval is 8.00 seconds before the first valid special hit in the 4/4 stage; every later stage uses 4.00 seconds. |
| RULE-11d | Summon time accumulates continuously during normal play; when the interval is reached while minions from the current wave remain, summoning waits and occurs immediately after that wave is cleared. |
| RULE-11e | Each wave summons 2, 3, 4, and 5 lesser golems at progress 4/4, 3/4, 2/4, and 1/4 respectively. |
| RULE-11f | One wave spawns its full count from RULE-11e in one normal update step, not in replenishment batches. |
| RULE-11g | Every lesser-golem kill increases cumulative stage kills by 1, capped at 5. |
| RULE-11h | All subsequent normal summoning stops after cumulative stage kills reach 5. |
| RULE-11i | Exactly 1 elite golem spawns after kill 5. |
| RULE-11j | Lesser golems remaining from the same wave after kill 5 continue to exist, but do not increase the count above 5 and do not block elite spawning, rifle pickup, or a valid special hit. This is a fixed remainder-handling tuple; any mismatch fails the item. |
| RULE-11k | Exactly 1 collectible special sniper rifle spawns after the elite golem dies. |
| RULE-11l | A valid special hit reduces boss progress by exactly 1 and ends the current stage. |
| RULE-11m | Stage end removes all lesser and elite golems from the current stage. |
| RULE-11n | If target progress for the level has not been reached, the next normal-play frame after stage end starts the next stage and resets summon time to 0. |
| RULE-11o | Reaching 2/4 in Level 4 or 0/4 in Level 5 or Level 6 enters the corresponding result directly without starting another stage. |
| RULE-11p | Stage end removes all player and enemy projectiles from the current stage. |
| RULE-11q | Stage end removes all current-stage special-rifle drops, held state, and flying special projectiles. |
| RULE-11r | At the beginning of every boss stage, no lesser golem, elite golem, special sniper rifle, or projectile from the previous stage remains; any member remaining from this fixed empty-field tuple fails the item. |
| RULE-11s | Normal boss movement speed is 60 pixels/second. |
| RULE-11t | Normally, the boss chooses a new target point every 3.50 seconds. |
| RULE-11u | A normal new boss target point is nominally 300 pixels from the player. |
| RULE-11v | While the player holds the special sniper rifle, boss movement speed is 200 pixels/second. |
| RULE-11w | While the player holds the special sniper rifle, the boss chooses a new target point every 2.00 seconds. |
| RULE-11x | Boss target points are constrained to `x=90–910, y=80–480` inside the room. |
| RULE-11y | The boss cannot move outside playable boundaries. |
| RULE-11z | The boss's first attack occurs 1.50 seconds after the first controllable frame of a direct boss level, or after the first controllable frame in Level 6's boss room. |
| RULE-11aa | Subsequent boss attacks use a 1.50-second interval. |
| RULE-11ab | Each boss attack fires 1 projectile toward the player's position at attack time. |
| RULE-11ac | Every projectile fired by the boss or a boss-summoned lesser or elite golem deals 3 damage. Lesser and elite golems retain their contact attacks from RULE-12; this damage rule does not require them to gain a projectile attack. |
| RULE-11ad | Boss-projectile speed is 220 pixels/second. |
| RULE-11ae | Boss-projectile range is 700 pixels. |

#### Lesser Golems, Elite Golems, and Special Sniper Rifle

| ID | Atomic observable result |
|---|---|
| RULE-12a | Lesser-golem health is 25. |
| RULE-12b | Lesser-golem movement speed is 90 pixels/second. |
| RULE-12c | Lesser-golem contact damage is 3. |
| RULE-12d | Lesser golems award no XP on death. |
| RULE-12e | Elite-golem health is 100. |
| RULE-12f | Elite-golem movement speed is 55 pixels/second. |
| RULE-12g | Elite-golem contact damage is 7. |
| RULE-12h | Elite golems award no XP on death. |
| RULE-12i | Both golem types use the player as their movement target. |
| RULE-12j | Golem contact is detected when its distance to the player is less than 42 pixels. |
| RULE-12k | Each golem has an individual 0.80-second contact-damage cooldown. |
| RULE-12l | The same golem applies contact damage at most once in one normal update step. |
| RULE-12m | Golem movement positions are constrained to `x=24–976, y=24–536` inside the room. |
| RULE-12n | Lesser-golem spawn points are nominally 95 pixels from the boss. |
| RULE-12o | Elite-golem spawn points are nominally 75 pixels from the boss. |
| RULE-12p | Spawn points for both golem types are corrected to legal reachable positions that do not overlap walls, doors, or obstacles. |
| RULE-13a | Picking up the special sniper rifle temporarily replaces the selected conventional gun and remembers the previous conventional slot. |
| RULE-13b | Special-sniper projectile speed is 1200 pixels/second. |
| RULE-13c | Special-sniper range is 2000 pixels. |
| RULE-13d | Each special-sniper pickup allows exactly one shot, fired by the next left-button press in the persistent shooting direction established by the last nonzero WASD movement input. |
| RULE-13e | The left-button special shot immediately consumes the held state. |
| RULE-13f | Firing the special shot immediately restores the previous conventional-gun slot. |
| RULE-13g | A special projectile hit on the boss is valid only when the current stage has accumulated 5 kills, the elite has spawned, and its drop has been collected; if any member of this fixed prerequisite tuple is unmet, the shot is a miss. |
| RULE-13h | A valid special hit only reduces boss progress by 1. |
| RULE-13i | Damage upgrades do not affect the special sniper rifle. |
| RULE-13j | The three reachable terminal states in the public boss room—range exhausted, leaving the boundary, or hitting a non-boss target—all count as a miss and drop the rifle again; fixtures involving doors or obstacles absent from the boss room are not required. |
| RULE-13k | In the same normal update step as a miss, the unique same special sniper rifle drops back into the current boss room. |
| RULE-13l | The drop point is in a walkable reachable area within `x=40–960, y=40–520`. |
| RULE-13m | If the terminal point is illegal, the drop uses the nearest legal point. |
| RULE-13n | A drop after a miss does not change stage kills. |
| RULE-13o | A drop after a miss does not change elite-spawned state. |
| RULE-13p | A drop after a miss does not change boss progress. |
| RULE-13q | A drop after a miss does not create a second special-sniper instance. |
| RULE-13r | The player can collect the dropped rifle again and retry without replaying the stage. |
| RULE-13s | On player death, Retry, leaving the level, valid stage end, or entering a result layer, all held, dropped, and flying special-sniper state becomes invalid and is removed. Every path in this fixed lifecycle enum is tested; residue on any path fails the item. |

#### Projectiles, Numeric Bounds, and Atomic Same-Frame Resolution

| ID | Atomic observable result |
|---|---|
| RULE-14a | A player projectile that hits one legal target resolves exactly once and is removed immediately. |
| RULE-14b | An enemy projectile that hits the player resolves exactly once and is removed immediately. |
| RULE-14c | A player projectile is removed immediately when its swept travel path intersects a wall, door, obstacle, or room boundary and cannot tunnel through at high speed. Every member of this fixed blocker enum is tested; passing through any one fails the item. |
| RULE-14d | An enemy projectile is removed immediately when its swept travel path intersects a wall, door, obstacle, or room boundary and cannot tunnel through at high speed. Every member of this fixed blocker enum is tested; passing through any one fails the item. |
| RULE-14e | Obstacles take no damage and cannot be destroyed by projectiles. |
| RULE-14f | A projectile removed by an obstacle cannot continue to damage a target behind it. |
| RULE-14g | Health, XP, objective count, stage kills, and boss progress cannot fall below 0. Every member of this fixed numeric enum is tested; any out-of-range value fails the item. |
| RULE-14h | The same hit, death, objective, room-clear, upgrade, or stage event cannot resolve more than once. |
| RULE-14i | Within one normal update step, all valid hits and health changes resolve before checking upgrade, room clear, level completion, or victory. |
| RULE-14j | If player health is 0 at the end of the same normal update step, defeat takes priority over upgrade, room-clear completion, level completion, and victory. |
| RULE-14k | While the player is alive, state priority is: mandatory upgrade → room-clear feedback period → victory/level completion → normal play. |
| RULE-14l | After a higher-priority modal ends, still-true lower-priority states are checked and processed again; reached upgrade, room-clear, completion, or victory conditions are not lost. |
| RULE-14m | Any completion, victory, or defeat result enters the result layer exactly once. |
| RULE-14n | In the same normal update step in which a completion, victory, or defeat result becomes true, enemies, projectiles, summoning, reloading, dash, damage, and gameplay input freeze. Any member of this fixed freeze enum continuing to advance fails the item. |
| RULE-14o | After the result layer appears, old projectile or contact damage cannot change the result later. |

### 6.4 UI, Feedback, and Modal Input

#### Pages, HUD, and Distinguishability

| ID | Atomic observable result |
|---|---|
| UI-01a | The main menu and controls page display the game's objective. |
| UI-01b | The controls page explains that WASD controls both movement and the eight-direction persistent shooting direction, that stopping preserves the last nonzero movement direction for shooting, and that the left button fires; it also explains Space for bombs, Shift for dash, R, 1/2, Tab, and Esc. |
| UI-02a | All six entries on the level-select screen are visible, readable, and clickable at 1280×720. |
| UI-02b | The page clearly communicates that all six levels can be entered independently and shows no false locks or completion prerequisites. |
| UI-03a | The HUD continuously displays the current level name and current objective progress. |
| UI-03b | The HUD displays current/maximum health. |
| UI-03c | The HUD displays level, current XP, and the next threshold or MAX. |
| UI-03d | The HUD displays the selected weapon name and ammunition. |
| UI-03e | The HUD displays two distinct conventional-weapon slots and clearly highlights the selected slot. |
| UI-03f | Both conventional slots display as locked while the special sniper rifle is held. |
| UI-03g | Reloading displays visible progress from 0 to 100%. |
| UI-03h | In boss levels, the HUD displays actual boss progress from 0–4 and stage kills from 0–5. |
| UI-03i | The normal-play HUD continuously displays the exact available-bomb count from 3 to 0. |
| UI-05a | Normal and elite slimes can be distinguished reliably without reading internal names. |
| UI-05b | Lesser golems, elite golems, and the boss can be distinguished reliably without reading internal names. |
| UI-05c | Player and enemy projectiles are distinguishable. |
| UI-05d | Locked and open doors are distinguishable. |
| UI-05e | Training targets and living enemies are distinguishable. |
| UI-05f | Dropped, held, and consumed special-sniper states are distinguishable. |
| UI-05g | After a Level 3 room transition, the current room name or an equivalent room-state change is displayed. |

#### Observable Feedback Outcomes

| ID | Atomic observable result |
|---|---|
| UI-04a | A nonzero WASD movement input produces a visible held-weapon orientation change to the same one of eight directions, and that orientation persists after movement stops until a different nonzero movement direction is supplied. |
| UI-04b | Every actual shot has muzzle or equivalent instantaneous feedback. |
| UI-04c | A projectile striking a wall, door, obstacle, or boundary has disappearance feedback consistent with its removal. |
| UI-04d | A player projectile hitting a target has hit feedback. |
| UI-04e | The player has damage feedback when taking nonzero damage. |
| UI-04f | The dash-immunity interval has distinguishable immunity feedback. |
| UI-04g | Player movement has animation change consistent with movement state. |
| UI-04h | Slime wandering, approaching, strafing, or retreating produces visible position change. |
| UI-04i | Enemy death has death or disappearance feedback. |
| UI-04j | Room clear has door-opening feedback. |
| UI-04k | Room clear shows actual restored health or a health-full message. |
| UI-04l | The first completion of every objective has a checkmark or equivalent feedback. |
| UI-04m | Selecting an upgrade displays the selected stat and exact effect. |
| UI-04n | A normal weapon hitting the boss displays immunity feedback. |
| UI-04o | Elite-golem death displays feedback for one unique special-sniper drop. |
| UI-04p | Picking up the special sniper rifle displays that conventional switching is locked. |
| UI-04q | Firing the special sniper displays its consumption and restoration of the conventional gun. |
| UI-04r | Missing with the special shot displays that the weapon dropped back into the arena. |
| UI-04s | A valid special hit on the boss displays boss progress decreasing by 1. |
| UI-04t | “Level Complete” has explicit result feedback. |
| UI-04u | “Victory” has explicit result feedback distinct from level completion. |
| UI-04v | “Defeat” has explicit result feedback distinct from completion or victory. |
| UI-04w | Placing a bomb visibly creates its fuse object, and detonation visibly shows a blast approximately three player widths across. |
| UI-04x | Bomb hits, blocked blasts, boss immunity, and an attempted placement at 0 bombs each have feedback consistent with the resolved state. |

#### Modal Priority and Result Pages

| ID | Atomic observable result |
|---|---|
| UI-06a | At most one of briefing, map, upgrade, pause, and result modal layers is displayed at one time. |
| UI-06b | Pressing Esc during normal play opens the pause layer; it displays Resume, Retry, Level Select, and Main Menu. |
| UI-06c | Pressing Esc or clicking Resume in the pause layer resumes the same level and prior gameplay state. |
| UI-06d | All gameplay timers, movement, attacks, damage, and spawning freeze while paused. |
| UI-06e | While the map is open, Esc/Tab closes the map with priority and does not open pause. |
| UI-06f | While the upgrade modal is open, only the three upgrade choices are usable; Esc, Tab, and other gameplay inputs are ignored. |
| UI-06g | While the result layer is open, only its visible buttons can change the page; gameplay keys and Esc are ignored. |
| UI-07a | Completion pages for Levels 1–4 display “Level Complete,” the level name, and completed objectives. |
| UI-07b | Completion pages for Levels 1–4 provide Next Level, Retry This Level, and Back to Level Select. |
| UI-07c | Level 5 and Level 6 victory pages display “Victory.” |
| UI-07d | Level 5 and Level 6 victory pages provide Retry This Level, Back to Level Select, and Back to Main Menu. |
| UI-08a | The defeat page displays “Defeat,” the health-depleted reason, and the current level name. |
| UI-08b | The defeat page provides Retry This Level, Back to Level Select, and Back to Main Menu. |
| UI-08c | The defeat page does not display a victory, next-level, or continue-failed-gameplay entry. |

### 6.5 Retry, Level Switching, Exit, and Close/Reopen

| ID | Atomic observable result |
|---|---|
| SESSION-01a | Clicking Retry from pause or result re-enters the same level's briefing. |
| SESSION-01b | Retry applies the initial state specified by ENTRY-05 and that level's exceptions. |
| SESSION-01c | Retry preserves no old objectives, enemies, projectiles, upgrades, boss state, drops, audio playback position, or input response. |
| SESSION-02a | Clicking Next Level after completing Levels 1–4 enters only the briefing for level number +1. |
| SESSION-02b | The next level inherits no health, ammunition, XP, upgrades, objects, or boss progress from the previous level. |
| SESSION-03a | Returning to level select or the main menu from pause or result immediately stops the old level. |
| SESSION-03b | Selecting any level again produces a fresh initial state for that level. |
| SESSION-04a | Across two consecutive `enter level → change state → leave level → enter another level` cycles, there is always exactly one current-level player, HUD, object set, music track, and input response. |
| SESSION-05a | Clicking “Exit Game” on the main menu and clicking the window close button both end the process. |
| SESSION-05b | Neither normal close path saves level, objective, health, weapon, XP, upgrade, boss, or result state. |
| SESSION-05c | Relaunch after a normal close first enters the main menu with all six levels still unlocked. |
| SESSION-05d | Normal close during level loading, briefing, play, a modal, or before a result appears also follows SESSION-05b–05c. |
| SESSION-05e | OS force-kill, process crash, power loss, and file corruption are abnormal termination and outside acceptance; the submission must not claim to restore gameplay state from before these abnormal terminations. |

### 6.6 Asset Use

`MaterialMapping-en.md` provides paths, summaries, and licensing information. The identifiers below describe the visible asset outcomes. Except for the observable semantics below, sprite-sheet frame choice, row/column, playback order, frame rate, on-screen scale, horizontal flip, and equivalent animation pacing are implementation choices.

| ID | Atomic observable result |
|---|---|
| ASSET-01a | Player idle/movement uses individual 32×32 frames from `Player.png`. |
| ASSET-01b | One player rendering does not cross into adjacent frames or compress the full multi-frame sheet into one character. |
| ASSET-02a | Normal and elite slimes use individual 32×32 frames from `Enemies/slime.png`. |
| ASSET-02b | Slime movement plays a distinguishable multi-frame change, and one rendering does not cross frame boundaries. |
| ASSET-02c | Normal and elite slimes remain distinguishable by at least two of size, tint, marker, text, or outline. |
| ASSET-02d | If a training target reuses a slime frame, it has a target marker and cannot be confused with a living enemy. |
| ASSET-03a | The boss uses an individual 16×16 character from `Golem (Shading).png`. |
| ASSET-03b | Lesser/elite golems use individual 16×16 frames from the mapped golem idle, movement, and death sheets. |
| ASSET-03c | Boss, lesser-golem, and elite-golem character semantics are not interchanged, and a full sheet is not compressed into one character. |
| ASSET-04a | Room floors are continuously tiled with `atlas_floor-16x16.png`, not represented only by isolated corner patches. |
| ASSET-04b | Room walls, doors, and obstacles use the mapped Tileset sheets, with distinguishable boundaries, passages, and doors. |
| ASSET-04c | Obstacles are assembled continuously from complete brick-wall/low-wall cells, and their visible silhouette covers the actual blocking area. |
| ASSET-05a | HK-67, Glock-21, hotbar, and special sniper rifle each use their corresponding mapped weapon assets and are not interchanged. |
| ASSET-05b | Player/enemy projectiles and muzzle flash use their corresponding mapped assets. |
| ASSET-05c | The current world weapon and muzzle flash orient in sync with the persistent shooting direction established by the last nonzero WASD movement input, including after movement stops. |
| ASSET-06a | Health, Damage, and Speed upgrades use `fa1042.png`, `fa157.png`, and `fa1056.png` respectively and are not interchanged. |
| ASSET-06b | Beside the three upgrade icons, exact textual effects from RULE-10e, 10f, 10h, and 10n are displayed respectively. |
| ASSET-07a | Primary Latin characters in menus, level select, HUD, objectives, upgrades, pause, and results use `Minecraft.ttf`. |
| ASSET-07b | Characters missing from that font may fall back to another readable font and do not display missing-glyph boxes. |
| ASSET-08a | Main menu, controls, and level-select pages use `audio/lobby.mp3`. |
| ASSET-08b | Levels 1–3 use `audio/dungeon.mp3`. |
| ASSET-08c | Levels 4–5 use `audio/boss.mp3`; Level 6 uses it after entering the boss room. |
| ASSET-08d | The victory result layer uses `audio/silent-partner.mp3`. |
| ASSET-08e | The defeat result layer uses `audio/somebody-that-i-used-to-know-trap-by-velvetcasca-extended-version.mp3`. |
| ASSET-08f | Player firing uses `audio/laser.mp3`. |
| ASSET-08g | Exactly one BGM track plays at any moment. |
| ASSET-08h | BGM pauses or reduces volume while the game is paused. |
| ASSET-08i | On page or level change, old BGM stops and does not overlap the new BGM. |
| ASSET-08j | The defeat result layer uses `images/7gc52d.png` as a visible background. |
| ASSET-08k | Level 6 uses `audio/dungeon.mp3` in its first three rooms and switches once to `audio/boss.mp3` on entering its boss room, without overlap. |
| ASSET-09a | Bombs, fuses, and explosions use a clearly recognizable runtime-drawn visual distinct from bullets, muzzle flashes, upgrade icons, and actors; no unrelated mapped bitmap is relabeled as a bomb asset. |
| ASSET-09b | The visible explosion diameter and collision diameter agree at 96 pixels on the 1280×720 gameplay canvas. |

### 6.7 Public launch and interaction boundaries

| Boundary | Player-visible condition |
|---|---|
| Launch | The project opens to the main menu using the public instructions. |
| Normal input | All six levels can be entered and attempted through visible controls and ordinary player input. |
| Offline operation | Gameplay does not require an account, server, runtime download, or external service. |
| Observation | Any optional state report is read-only and cannot change level, spawn, ammunition, upgrades, damage, or results. |

## 7. Result Summary (Non-Normative)

| Result | Summary |
|---|---|
| Level 1 complete | Six training objectives completed in order, ending with bomb placement and target overlap |
| Level 2 complete | Both fixed slimes dead and feedback period finished |
| Level 3 complete | Sole combat room cleared, map viewed, upgrade chosen, and player in exit room |
| Level 4 complete | Progress reaches 2/4 after two boss stages |
| Level 5 victory | Progress reaches 0/4 after the final two boss stages |
| Level 6 victory | Two normal slimes, one elite slime, and the final boss are defeated along the right/up/left room route |
| Defeat | Health is 0 after same-step resolution in a damaging level, taking priority over other results |

## 8. Implementation Freedom Summary (Non-Normative)

Satisfying the observable results in Section 6 is sufficient. Internal scene organization, data structures, equivalent wording, nonessential decoration, and exact obstacle coordinates are implementation choices. No old dungeon-generation algorithm or unpublished implementation is required.

## 9. Contract Publication Self-Check (Non-Normative)

The checks below mean only that the document's public requirements and optional observation notes were reviewed; they are not additional gameplay requirements.

- [x] Public outcomes are decomposed into independently observable identifiers.
- [x] Time, speed, distance, position, angle, and integer tolerances are public.
- [x] Input and timing rules for briefing, reload, dash, map, upgrade, pause, and result are public.
- [x] The four boss stages are numbered step by step through start, summon, cumulative kills, elite, drop, hit branches, cleanup, and transition.
- [x] Attack forms, intervals, damage, projectile speed/range, or contact conditions for the boss, slimes, and golems are public.
- [x] Every special-sniper miss terminal state, legal re-drop, unique-instance rule, and cleanup rule is public.
- [x] Upgrade formulas, affected objects, actual Level 5/6 values, and same-frame result priority are public.
- [x] Normal exit, window close, and explicitly excluded abnormal termination are distinguished.
- [x] Asset-animation freedom and the hard defeat-background requirement are public.
- [x] Launch, offline, and read-only observation boundaries are public.
- [x] Unpublished references and internal state are outside the design requirements.

## 12. Dashboard Naming Tables and Control Scheme

This section mirrors `sp/benchmark/naming-tables.json` in human-readable form. It names only concepts already required in Section 6 and adds no gameplay requirement.

### 12.1 Numeric slots

| Slot | Meaning | Existing requirement source |
|---|---|---|
| `level`, `room` | Current level and room | `ENTRY-*`, `LEVEL-*` |
| `player_hp`, `player_max_hp` | Current and maximum player HP | `ENTRY-04*`, `UI-03*` |
| `hk_ammo`, `glock_ammo` | Current conventional-weapon ammunition | `RULE-01*`–`RULE-03*`, `UI-03*` |
| `bombs` | Available bomb count | `BOMB-*` |
| `objective_progress` | Current ordered objective progress | `LEVEL-01*`, `UI-03*` |
| `boss_progress`, `stage` | Boss target progress and stage | `LEVEL-04*`, `RULE-11*` |
| `stage_kills` | Cumulative lesser-golem kills in the current boss stage, capped at 5 | `RULE-11g`–`RULE-11j` |
| `selected_weapon` | Current weapon slot: 1 HK-67, 2 Glock-21, 3 special sniper | `RULE-02*`, `RULE-13a`–`RULE-13f` |
| `reload_progress` | Read-only percentage of the active conventional reload, or 0 when idle | `RULE-03a`–`RULE-03g`, `UI-03*` |
| `hk_damage`, `glock_damage`, `movement_speed`, `player_level`, `xp`, `xp_threshold` | Current public combat and progression values | `RULE-04*`, `RULE-10*`, `LEVEL-04*`, `LEVEL-06*` |
| `enemy_count` | Current living-enemy count | `RULE-05*`–`RULE-07*`, `UI-03*` |
| `rng_seed` | Decimal seed of the current level's gameplay random source | `RULE-07d`–`RULE-07e` |

### 12.2 Entities and interaction targets

| Kind | Meaning | Allowed states or role | Existing requirement source |
|---|---|---|---|
| `player` | Player character | `alive`, `dead`, `dashing`, `immune` | `RULE-04*`, `UI-03*` |
| `enemy` | Normal, elite, or boss enemy | `living`, `dead`, `elite`, `boss`; directional combat target, not clickable | `RULE-05*`–`RULE-14*` |
| `training_target` | Level 1 target | `active`, `complete`; directional combat target, not clickable | `LEVEL-01*`, `BOMB-01o` |
| `special_rifle` | The unique dropped/held special sniper instance | `available`, `held`; public world entity and clickable pickup target only when available; never an action API | `RULE-11k`, `RULE-13a`–`RULE-13s`, `UI-04o`–`UI-04r` |
| `upgrade_choice` | A presented upgrade | `available`, `selected`; clickable | `RULE-10*`, `UI-04*` |
| `start_button`, `controls_button` | Main-menu entries | clickable targets | `ENTRY-01*` |
| `level_1_button`, `level_2_button`, `level_3_button`, `level_4_button`, `level_5_button`, `level_6_button` | Six level-select entries | clickable targets | `ENTRY-02*`, `UI-02a` |
| `retry_button`, `next_level_button`, `back_button`, `main_menu_button` | Result and navigation entries | clickable targets | `UI-06*`–`UI-08*`, `SESSION-*` |

### 12.3 Controls

W/A/S/D provides continuous eight-direction movement and sets the persistent shooting direction to the same last nonzero movement direction. Stopping preserves that direction. During normal play, left-button input fires the held firearm along it: holding fires HK-67 at its stated interval, while each press fires at most one Glock-21 or special-sniper shot. Arrow keys and mouse position never aim; mouse clicks operate visible UI controls, and mouse position supplies only the no-movement dash direction defined by RULE-04c. Shift dashes; Space places a bomb; R reloads; 1/2 selects a conventional weapon; Tab toggles the allowed map; Escape cancels, closes, pauses, or resumes according to the visible modal.

## 13. Implementation Boundary

Section 6 remains the sole source of game-specific acceptance requirements. The dashboard only reports the public names above and cannot execute actions or declare completion. Internal node names, scene hierarchy, scripts, algorithms, and data structures remain implementation choices. Technical paths and engine behavior are defined by `TOOLCHAIN-en.md` and `BENCHMARK_MANIFEST.json`.
