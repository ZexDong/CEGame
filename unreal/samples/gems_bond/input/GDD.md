# Gem's Bond

## 1. One-sentence task

Build a polished 3D survival tower-defense game in which players mine gold, place and upgrade defenses,
and protect a magical crystal against ground and flying monsters through the full wave schedule and
endless escalation (BUILD-01, ECONOMY-02, UPGRADE-01, WAVE-03, WAVE-05, DEFEAT-01).

## 2. Scope

### 2.1 Included requirements

| Requirements | Summary |
| --- | --- |
| START-01, SCENE-01, SCENE-02 | Fresh economy and fixed forest battlefield |
| SELECT-01 to SELECT-03, BUILD-01 to BUILD-03 | Mouse-driven selection, preview, placement and rejection |
| ECONOMY-01, ECONOMY-02, INSPECT-01, UPGRADE-01 to UPGRADE-03, SELL-01 | Scaling prices, mining, context actions and upgrades |
| HEALTH-01, HEALTH-02, ENEMY-01 to ENEMY-04 | Damage, regeneration, movement, attacks and death |
| ARCHER-01, ARCHER-02, CANNON-01, CANNON-02, COMBAT-01 | Finite-travel weapons, target eligibility and splash |
| WAVE-01 to WAVE-05, RANDOM-01 | Complete waves, rest wave, deterministic variety and endless survival |
| SPEED-01, PAUSE-01, DEFEAT-01, DEFEAT-02, RESTART-01, RESTART-02 | Speed, pause, loss and lifecycle |
| UI-01 to UI-03, VISUAL-01 to VISUAL-04, AUDIO-01 | Readable UI, animated 3D art, spatial effects and basic event audio |
| QUALITY-01 to QUALITY-06 | Common delivery and playability requirements |

### 2.2 Excluded scope

| Related requirements | Excluded content |
| --- | --- |
| WAVE-05, RESTART-02 | Campaign victory, campaign save progression and online leaderboards |
| SCENE-01 | Multiplayer, mobile controls, free camera exploration and additional maps |
| QUALITY-01 | Installer/distribution package; the delivery target is Windows independent editor_game |

## 3. Starting state

| Item | Supplied state | Related requirements |
| --- | --- | --- |
| Engine | Unreal Engine, CL configured-build, desktop; exact launch/build details are in tools/TOOLCHAIN.md | QUALITY-01 |
| Project | A native project containing a basic diagnostic screen | All task-specific requirements remain to be implemented |
| Presentation assets | Individual meshes, animations, textures, materials, font and audio; no assembled game map | VISUAL-01 to VISUAL-04, AUDIO-01 |
| Initial game state | Not implemented by the starter; the target opening is START-01 | START-01 |
| Existing gameplay | None; the Space input health probe is only starter diagnostics | QUALITY-02 |

## 4. Player goal and complete flow

### 4.1 Goal

Survive as many waves as possible by balancing mine income, additional defenses and stronger towers
(ECONOMY-01, ECONOMY-02, UPGRADE-01, WAVE-05). Losing the crystal ends the run (DEFEAT-01).

### 4.2 Complete player flow

```text
[START-01] Enter the fresh forest battlefield
-> [SELECT-01, BUILD-03, WAVE-01] Build the first mine
-> [BUILD-01, ARCHER-01, CANNON-01] Defend against the wave
-> [ECONOMY-02, UPGRADE-01, SELL-01] Reinvest, upgrade and reposition defenses
-> [WAVE-04, WAVE-05] Survive later and endless waves
-> [DEFEAT-01, DEFEAT-02] Lose the crystal and see the result
-> [RESTART-01, RESTART-02] Restart or close and reopen into a clean round
```

### 4.3 Repeated loop

Select and place (SELECT-01, BUILD-01) -> earn through mines and kills (ECONOMY-02, ENEMY-04)
-> inspect and upgrade (INSPECT-01, UPGRADE-01) -> survive the next wave (WAVE-04).

## 5. Player controls

| Requirement | Player action | Context | Response |
| --- | --- | --- | --- |
| SELECT-01, BUILD-01, BUILD-03 | Left-click icon, then board cell | Active round | Select and build |
| SELECT-02 | Move pointer | Build selection | Placement/range preview |
| INSPECT-01, UPGRADE-01, SELL-01 | Left-click structure and context control | No build selection | Inspect, upgrade or sell |
| SELECT-03 | Right-click or Escape | Selection/details open | Cancel |
| SPEED-01 | Hold/release F | Active round | Fast-forward/normal speed |
| PAUSE-01 | P or Pause/Resume | Living round | Toggle pause |
| RESTART-01 | R or Restart | Any round phase | Clean new round |
| QUALITY-01 | Exit or close window | Any phase | Close normally |

## 6. Numbered requirements: the sole gameplay acceptance source

### 6.1 Interpretation

Each row owns a separately judgeable result. Balance tables in Sections 6.2.1-6.2.3 and
the behavior boundaries in Sections 6.2.4-6.2.9 are part of the numbered rows that reference
them. Boundary sections refine those existing requirements, not separate scoring items.
All sections outside Section 6 summarize these rows.
COMBAT-01 defines shared units and numeric tolerances for the numbered rules.
Unspecified implementation details and random algorithms are free.
All appearance requirements are stated here; the supplied reference frames are illustrations,
not additional acceptance rules. Mandatory asset use in VISUAL-01 to VISUAL-03 and UI-01 means
visible use during gameplay, not merely retaining files in the project. Use the specified
asset categories and tier variants; unused alternate clips, decorative variants and support
textures do not each create a separate content requirement.

### 6.2 Task-specific requirements

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback | Edges and lifecycle |
| --- | --- | --- | --- | --- | --- | --- |
| START-01 | Fresh launch or Restart | Enter play | Begin with 170 coins, an intact 500-health crystal, four unoccupied gold deposits, zero defenses and zero completed waves. No enemy or projectile exists. Speed is 1x. | No carried-over income, purchases, damage or selection. | The coin counter and instruction to build a mine are visible. | Reopen has the same fresh progress state. Boundaries: 6.2.4. |
| SCENE-01 | Round visible | View the field | Present a fixed elevated three-quarter 3D view of a square brown clearing surrounded by bright green grass, conifers, bushes, flowers, scattered stones and a left-side dirt approach. Keep the entire build area and crystal visible at 1280 x 720 and 1920 x 1080. | No flat diagram, unlit graybox, empty background, clipped board or camera needed to find a legal build cell. | Use bright directional daylight, soft cast shadows and saturated green/brown terrain. The camera reveals both the tops and sides of structures, with the pink-red crystal prominent near the center of the clearing. | The build sidebar remains separate from actionable world space. Boundaries: 6.2.9. |
| SCENE-02 | New round | Inspect or place on the clearing | Use a 20 x 20 square logical build grid with zero-based (column, row) coordinates from 0 through 19, rows increasing toward the bottom of the screen and columns to the right. The crystal occupies (10,10). Gold deposits occupy (4,3), (12,8), (6,13), (17,17). One cell is 200 world-distance units for the balance values below. | No placements outside this clearing, on the crystal or on scenery. | The grid may be subtle or only shown during placement; the hovered cell is unambiguous. | Coordinates specify player-facing board layout, not an engine-axis convention. Boundaries: 6.2.5. |
| SELECT-01 | Preparation, countdown, combat or rest | Left-click a build icon | Select exactly one of Mine, Archer Tower, Cannon Tower or Wall. Show its name, current price and selection highlight. Selecting a different type replaces the prior selection. | Selection alone spends no coins and creates no building. | Distinct icons in a vertically arranged left build panel. | Controls work during combat without pausing the world. Boundaries: 6.2.4. |
| SELECT-02 | A build type is selected | Move the pointer over the board | Show a snapped translucent model preview at the hovered cell, with green for legal and red for illegal placement. Towers also show their attack-radius preview. | Preview objects cannot block, attack, produce income, take damage or count as buildings. | Preview follows the pointer and displays the actual footprint. | Leaving the board or hovering UI hides the world preview; colors have an additional outline or readable validity cue. Boundaries: 6.2.4. |
| SELECT-03 | Placement preview or building details open | Right-click or press Escape | Cancel the current selection and close its preview/details. | No purchase, sale, damage, refund or pause is caused by cancel. | Selection highlight, range ring and preview disappear. | Repeated cancel is harmless; Escape on a clean play view is a no-op. Boundaries: 6.2.4. |
| BUILD-01 | A selected defense has an empty legal cell and sufficient coins | Left-click that cell | Create one level-1 building, deduct its displayed current price exactly once, and begin a short rise/pop construction animation lasting 0.15-0.6 simulation seconds. | No duplicate building or second charge from a held button. | The solid model replaces the preview, coins update and a build cue plays. | The selected build type remains available for repeated placements. Boundaries: 6.2.5, 6.2.7. |
| BUILD-02 | Any placement restriction fails | Left-click an occupied, reserved, out-of-bounds or unaffordable cell | Reject the purchase while keeping coins, ownership and prices unchanged. | No overlap stacking, partial purchase or negative balance. | Show a visible placement or affordability reason within 0.2 real seconds. | Exactly enough coins permits a valid purchase; holding or repeatedly clicking an illegal cell cannot charge. Boundaries: 6.2.5, 6.2.7. |
| BUILD-03 | Mine selected | Left-click a gold deposit | Only an unoccupied deposit permits a mine. Replace its exposed rock silhouette with the built mine while preserving its board location. | No mine on ordinary soil, second mine on one deposit or unrelated defense on an exposed deposit. | The construction changes the deposit silhouette. | Selling or destroying the mine exposes its deposit again. Boundaries: 6.2.5, 6.2.7. |
| ECONOMY-01 | Any active round | Build, sell or lose a building | Current price equals base price plus increment times the number of currently living player-owned buildings of that type: Mine 0 + 600 each; Archer 20 + 15 each; Cannon 25 + 20 each; Wall 5 + 2 each. | No cross-type price changes or price below its base. | Build-panel prices update immediately after the ownership change. | Upgrading does not add a building to the count. Boundaries: 6.2.7. |
| ECONOMY-02 | An intact mine exists | Every 10 simulation seconds of that mine's life | Credit 25 + 8 times completed-wave count coins to the shared wallet. Each mine has its own cycle; the first payout is after a full interval. | No idle income before a mine exists, double payout or payout after the mine is removed. | Gold-colored floating +amount text rises above the mine and the wallet updates. | The current completed-wave count at payout determines the amount; pausing freezes the cycle. Boundaries: 6.2.6, 6.2.7, 6.2.8. |
| INSPECT-01 | A built structure is visible | Left-click it while no build type is selected | Open contextual details with type, level, current/max health, refund amount and, for towers, damage, cooldown, range and the next upgrade price or maximum-level state. | The inspection click must not build, sell or upgrade. | Place the readable detail card near the selected structure without hiding critical controls; show a tower range ring. | Selecting another building replaces the card; clicking empty ground clears it. Boundaries: 6.2.7. |
| UPGRADE-01 | A fully constructed level-1 or level-2 tower is selected and coins cover its upgrade | Left-click Upgrade | Pay 200 to reach level 2 or 600 to reach level 3; apply the corresponding balance row immediately. | No skipped level, free upgrade or duplicate charge from one click. | Change both tower body and weapon to their distinct tier meshes, play an upgrade effect and update details. | Levels are displayed as 1, 2 and 3. Boundaries: 6.2.7, 6.2.8. |
| UPGRADE-02 | A tower is damaged | Complete a legal upgrade | Preserve health percentage: new health = old health / old maximum times new maximum. | No unconditional full heal and no health above the new maximum. | Health bar and detail values reflect the new amount. | Fractional health is valid; displayed numbers may round without altering the underlying value. Boundaries: 6.2.7. |
| UPGRADE-03 | Insufficient coins, maximum tower tier, construction in progress, or a mine/wall | Attempt Upgrade | Leave balance, tier, models, health and timers unchanged. Mines and walls have no upgrades. | No invisible or unaffordable upgrade and no tier above 3. | Unavailable controls are disabled or explain the reason. | Repeated rejection remains safe. Boundaries: 6.2.7. |
| SELL-01 | A player-owned structure is selected | Left-click Sell | Remove it once and refund floor(50% of the amount paid to place that object). Upgrades are not refunded. Recompute current build prices. | No refund for the crystal, an exposed deposit, enemies, already removed structures or their upgrades. | Show the refund before sale; close details and remove its health bar and range ring after sale. | The first free mine refunds zero. A refunded mine leaves a reusable deposit. Boundaries: 6.2.7, 6.2.8. |
| HEALTH-01 | A living owned building or crystal has missing health | Simulation advances | Regenerate 2 health per simulation second, clamped to that object's maximum. Walls have 450 health, mines 1500, and the crystal 500. Tower maxima are in the table below. | No regeneration after destruction or during pause/defeat; no overheal. | World-space health bars truthfully track damage and regeneration. | Health can be fractional. Regeneration does not restore a removed object. Boundaries: 6.2.6, 6.2.7, 6.2.8. |
| HEALTH-02 | A non-crystal structure reaches zero health | Enemy damage resolves | Remove its gameplay presence, ownership count, collision and active actions; restore the deposit if it was a mine. Give no sale refund. | No lingering invisible blocker, stale attacker target, income payout or newly released tower shot after removal. Already airborne projectiles follow COMBAT-01. | Play a destruction effect and clear any details for that object. | Its former attackers can continue toward the crystal or another obstruction. Boundaries: 6.2.7, 6.2.8. |
| WAVE-01 | No mine has yet been built in a new round | Wait or place non-mine defenses | Remain in preparation indefinitely with no enemies and no wave countdown progress. Building the first mine starts a 2-second countdown to wave 1. | No wave starts merely from time, selecting Mine or an invalid mine placement. | Replace the mine instruction with a visible upcoming-wave countdown. | After the first valid mine starts the round, later mine loss does not return to the initial waiting gate. Boundaries: 6.2.4, 6.2.6. |
| WAVE-02 | The round is counting down | Countdown expires | Start the next wave, play one horn cue and emit exactly its scheduled enemies at evenly spaced times across its spawn duration. Enemies enter from its enabled grass edges and move into view. | No overspawn, skipped groups or pre-countdown spawn. | Show current wave and remaining enemies. | For N enemies over T simulation seconds, emission k occurs at k times T/N, for k from 1 to N. The first occurs at T/N and the last at T. The single enemy of wave 24 enters at 0.1 seconds; rest has no emissions. Boundaries: 6.2.4, 6.2.6. |
| WAVE-03 | A scheduled wave starts | Run that wave | Use all 25 wave compositions, enemy tiers, spawn durations and enabled sides in Section 6.2.3. North, South, West and East refer to the corresponding screen edges. | No shortened substitute campaign, omitted flying species, replaced boss wave or reduced enemy counts. | Enemy species and tiers visibly differ. | Wave 11 is an 8-second rest with no enemies, then counts as cleared. Tier labels in the tables are 1-based. Boundaries: 6.2.4, 6.2.6. |
| WAVE-04 | A combat wave is in progress | The final scheduled enemy dies | Clear the wave only after every scheduled enemy has spawned and no living enemy remains. Increment completed waves once and begin a fresh 2-second inter-wave countdown. | No clear while enemies remain unspawned, no duplicate completed-wave increment or next-wave overlap. | The HUD changes from combat to the next countdown. | The rest wave uses its own duration. A defeat on the same update takes priority over wave clearance. Boundaries: 6.2.4, 6.2.6, 6.2.8. |
| WAVE-05 | Wave 25 has been cleared | Continue survival | Continue indefinitely using wave 25's composition. For wave w > 25, each group has floor(base_count times (1 + 0.2 times (w - 25)) + 0.5) members, all at tier 3. Preserve its spawn duration and four-side attacks. | No victory screen or automatic reset after the fixed schedule. | Wave count and survival progress keep increasing. | Calculate remaining count from the actual integer group counts; no fractional or negative remaining enemies. Boundaries: 6.2.4, 6.2.6. |
| RANDOM-01 | Fresh launch with the same configured seed | Repeat the same timed player inputs | Generate the same wave group ordering and spawn locations. Default seed is 50; another nonnegative 32-bit seed may alter ordering/locations but not counts, stats, prices or the board. | No deterministic seed that changes the rules or disables ordinary play. | All spawned enemies remain legible and enter via enabled edges. | No exact random-number algorithm or exact coordinate sequence is required across different implementations. Boundaries: 6.2.6. |
| ENEMY-01 | Slime, Skeleton or Orc spawned | Simulation advances | Ground enemies travel toward the crystal; if a living structure obstructs their advance, stop and attack it until it is removed, then resume. Use the species/tier stats in Section 6.2.2. | No movement through living walls/defenses, attacking removed targets or off-map stationary mobs that prevent clearance. | Ground walk/run, attack and death animations communicate their state. | Contact with the crystal causes attacks rather than instant deletion or single-use damage. Boundaries: 6.2.5. |
| ENEMY-02 | Bat or Dragon spawned | Simulation advances | Fly visibly above the ground toward the crystal, ignoring mines, walls and towers as movement blockers. Attack the crystal when in contact. Use Section 6.2.2 stats. | No landing merely to bypass targeting rules; a cannon cannot damage either flying species. | Flying silhouettes, wing motion and height distinguish them from ground enemies. | Their movement and attacks stop during pause/defeat; dead flyers cannot attack. Boundaries: 6.2.5. |
| ENEMY-03 | A living enemy is in contact with its target | Reach an attack interval | Apply its damage immediately on first contact, then no more than once per 1.0 simulation second while contact remains. Switching targets or briefly leaving contact cannot bypass this per-enemy interval. | No frame-rate-scaled repeated hits, damage before contact, or attack by a dead enemy. | Animate the attack and update the affected health bar. | Switching targets does not multiply the attack rate; targets reaching zero resolve their removal. Boundaries: 6.2.5, 6.2.6, 6.2.8. |
| ENEMY-04 | An enemy reaches zero health | Resolve death | Award its tier's bounty once unless defeat has priority at that same simulation time. Decrement the living/remaining count once, stop its attack and targetability immediately, then remove the corpse after its visible death animation. | No repeated bounty from splash, multiple projectiles or animation completion. | Show death motion and gold-colored +bounty text. | A corpse may finish visually but cannot delay a wave that has no living enemies. Boundaries: 6.2.8. |
| ARCHER-01 | An intact archer tower has an eligible enemy within 1000 ground-plane distance units (5 cells) | Its weapon is ready | Automatically aim at the nearest living ground or flying enemy and release a visible arrow. Use the tier damage and cooldown table. | No shot at dead, nonexistent or out-of-range targets; no firing before construction completes. | The ballista turns toward its target and shows a firing/recoil motion. | A tied nearest enemy may be selected by any stable rule; idle readiness must not accumulate a burst. Boundaries: 6.2.5, 6.2.6. |
| ARCHER-02 | An arrow has been released | The projectile travels and collides | Use visibly finite travel at 3000 distance units per simulation second. Apply the tier's damage once on contact with one eligible living enemy and consume the projectile. | No damage at release, through unrelated geometry, or more than one single-target hit. | The arrow path and impact can be seen; the health change follows impact. | Leading a moving target is allowed; a miss expires safely within 4 simulation seconds. Boundaries: 6.2.5, 6.2.7. |
| CANNON-01 | A fully constructed intact cannon tower has a living ground enemy within 1000 ground-plane units | Its weapon is ready | Aim at the nearest eligible ground target and release a visible cannonball using the tier damage/cooldown table. | No targeting a Bat or Dragon, off-range enemy or corpse. | The cannon barrel aims and recoils; its projectile is visually distinct from an arrow. | No burst from accumulated idle cooldown. Boundaries: 6.2.5, 6.2.6. |
| CANNON-02 | A cannonball is in flight | It first hits ground, a blocking structure or an eligible ground target | Explode once at the impact point. Damage each living ground enemy within the tier radius once; leave enemies outside the radius and all flying enemies unchanged. Use finite travel at 3000 units per simulation second. | No repeated explosion from one impact, pre-impact damage or doubled direct-hit damage. | Show a colored burst, expanding shock ring/smoke and an explosion cue. | The radius is measured in the ground plane; an enemy exactly on its boundary is included. Misses expire within 4 seconds. Boundaries: 6.2.5, 6.2.7. |
| COMBAT-01 | Any concurrent damage, sale, construction or wave event | Resolve the event | Keep ownership, wallet, health, enemy counts and targets consistent. Projectiles already released continue after their tower is sold or destroyed, retaining release-time damage and splash radius. | No double death award, damage to a reused identity, negative enemy counts or lost enemies from an invalid target. | Visible objects and HUD remain consistent. | Upgrades preserve any remaining current cooldown. The next shot uses the new tier and starts that tier's cooldown. Times mean simulation time unless labeled real. Isolated event timing tolerance is 0.15 seconds without cumulative rate drift; movement/range tolerance is 2% of specified distance. Currency, counts, damage and tiers are exact. The tolerance does not permit damage before visible impact or skipping phase boundaries. Real-time UI limits keep their stated bounds. Boundaries: 6.2.6, 6.2.7, 6.2.8. |
| SPEED-01 | Preparation, countdown, combat or rest | Hold F, then release it | While F is held, advance game simulation at 3x; return to 1x on release. Movement, wave timers, weapons, regeneration, income and effects share the multiplier. | No permanent speed change from key repeat, separate accelerated income, or acceleration of UI input. | Display the active speed clearly. | Pause, defeat, focus loss and Restart release the fast-forward state. Boundaries: 6.2.4. |
| PAUSE-01 | A living active round | Press P or use the Pause/Resume control | Toggle a pause that freezes simulation and preserves all current progress. Resume continues the same state. | No income, movement, spawning, cooldown, damage or regeneration while paused; no build, upgrade or sale. | A readable pause overlay and Resume/Restart controls remain operable. | Restart and exiting remain possible while paused; holding P does not repeatedly toggle. Boundaries: 6.2.4, 6.2.8. |
| DEFEAT-01 | The crystal reaches zero health | Resolve lethal damage | Enter defeat once, clamp crystal health to zero and stop gameplay simulation. Display Game Over, completed waves and the wave reached. | No false victory, negative crystal health or later wave start. | Show a prominent result panel over the field and crystal destruction feedback. | Defeat has priority over simultaneous final-enemy death. Boundaries: 6.2.4, 6.2.8. |
| DEFEAT-02 | Game Over visible | Wait or attempt gameplay inputs | Keep wallet, wave progress, surviving gameplay entities and timers fixed after terminal damage/death resolution; disable building, upgrade, sale, attack and speed controls. | No in-flight projectile, delayed gameplay event or mine payout changes the result. | Restart and Exit remain visible and usable. | Repeated clicks do not create extra panels or reset progress. Boundaries: 6.2.4, 6.2.8. |
| RESTART-01 | Preparation, countdown, combat, rest, pause or defeat | Press R or click Restart | Start a fresh round matching START-01 without restarting the process. | No old buildings, enemies, corpses, projectiles, feedback text, selection, timer or queued input affecting the new round. | The fresh board and mine instruction reappear within 1 real second. | Repeated Restart, including during a projectile flight or payout boundary, still creates exactly one clean round. Boundaries: 6.2.4, 6.2.8. |
| RESTART-02 | Any round has changed progress | Close the process and launch again | Start from START-01 with no persisted run progress. | No recovered coins, purchased towers, lost crystal health, wave number or fast-forward state. | The opening screen matches a first launch. | Saving preferences is optional; it must not change required game progress. Boundaries: 6.2.8. |
| UI-01 | Any playable state | View the HUD | Show coins at top left, build choices on the left, current wave/countdown and survival progress near the top, and accessible Pause/Restart/Exit controls. All visible counters reflect actual state within 0.2 real seconds. Use the supplied Baloo font for HUD text, Icon-Coin for currency, and GoldMine, ArcherTower, CannonTower and Wall textures for their build choices. | No obscured text, placeholder counters, replacement font/build icons or click-through from UI into world placement. | Use large rounded light text with a dark outline/shadow, dark translucent panels, gold coin imagery and distinct selected/disabled states. | Health and detail cards remain readable at both supported resolutions; font size, icon framing, tint and panel layout may be adjusted. Boundaries: 6.2.4, 6.2.9. |
| UI-02 | A building or enemy has changed health | View the field or selected object | Render proportional world-space health bars for damaged enemies/structures and the crystal; keep values consistent with their current and maximum health. | No health bars attached to removed/reused objects or health bars presenting one object's health as another's. | A filled/empty contrast makes loss and regeneration visible. | Full-health bars may be hidden until hover/selection, except the living crystal's health bar stays visible. Boundaries: 6.2.9. |
| UI-03 | A legal or illegal player action occurs | Observe its immediate response | Use a distinct positive cue for build/upgrade/sale and a readable reason for invalid placement, insufficient money or unavailable upgrade. | No invisible rejection, stuck tooltip or feedback obscuring subsequent inputs. | Temporary text/effects clear; hover never spends coins. | Action feedback arrives within 0.2 real seconds; a UI click never also acts on the board beneath it. Boundaries: 6.2.9. |
| VISUAL-01 | The field is assembled | Observe the scene | Use the supplied crystal/pedestal, mine/deposit, archer bodies/ballistae, cannon bodies/barrels and wall models as the primary visible structures. Preserve all three tower tiers and their distinct silhouettes, materials and proportions. | No replacing these required models with cubes, sprites, text or identical tier skins. | The floating/spinning pink-red gem remains the focal point; structures sit on the ground and cast coherent shadows. | Material tuning, instancing, reorganization and equivalent visual effects are allowed; these are presentation assets, not prebuilt gameplay. Boundaries: 6.2.9. |
| VISUAL-02 | Enemies are present | Run their movement, attack and death states | Use the supplied Slime, Skeleton, Orc, Bat and Dragon meshes, skeletons and suitable animation clips. Preserve green slime, bone skeleton, bulky orc and winged bat/dragon identity; tiers use the supplied material/scale variation from Section 6.2.2. | No static sliding enemies, T-poses, mismatched skeletons or missing materials. | Locomotion, attack and death remain visually legible in a crowded wave. | Equivalent blends and animation timing are allowed if they preserve the specified rules. Boundaries: 6.2.9. |
| VISUAL-03 | A round is rendered | View opening, placement and combat | Assemble the supplied ground/grass textures, trees, bushes, flowers, stones and fence assets into the scene described by SCENE-01. Retain a generous green border around the central dirt field and layered vegetation. | No raw-asset gallery, featureless plane, giant background props blocking play or missing environment. | Place tall conifers along the outer edges, with lower shrubs, flower patches and stones between them and the clearing. Keep the central build cells unobstructed and the left dirt approach readable; vegetation must provide foreground and background depth. | Exact decorative instance counts/coordinates are free. Assemble the environment from pieces; no finished map is supplied. Boundaries: 6.2.9. |
| VISUAL-04 | Construction, firing, impact, income or upgrade occurs | Observe its presentation | Provide construction rise/pop, weapon aim/recoil, arrows/cannonballs, impact flashes, cannon shock/smoke, upgrade glow, floating gold text and a pulsing placement/range cue. | No full-screen flash replacing spatial effects, permanent particles or decorative effects used as false hit confirmation. | Effects occur at the correct world object and remain readable above the field. | Create these effects using the provided textures/materials or equivalent legal effects; game logic remains independent of their implementation. Boundaries: 6.2.8, 6.2.9. |
| AUDIO-01 | Normal play with audio enabled | Perform a gameplay action and use the audio toggle | Provide background music and audible event feedback. Supplied music and event-cue files are available. | Muting must not disable gameplay or its visual feedback. | The player can mute and restore audio while continuing to play. | Equivalent legally clear audio is permitted; exact cue waveforms, individual event coverage and onset latency are not acceptance criteria. Boundaries: 6.2.9. |

### 6.2.1 Tower balance (UPGRADE-01, HEALTH-01, ARCHER-01, ARCHER-02, CANNON-01, CANNON-02)

All tiers have a 1000-unit attack range. Body and weapon meshes both change with tier.

| Tower | Tier | Maximum health | Damage | Cooldown (s) | Splash radius (units) | Next upgrade cost |
| --- | --- | --- | --- | --- | --- | --- |
| Archer | 1 | 150 | 6 | 0.5 | 0 | 200 |
| Archer | 2 | 250 | 20 | 0.4 | 0 | 600 |
| Archer | 3 | 350 | 60 | 0.3 | 0 | None |
| Cannon | 1 | 150 | 8 | 2.0 | 200 | 200 |
| Cannon | 2 | 200 | 28 | 1.5 | 250 | 600 |
| Cannon | 3 | 350 | 56 | 1.0 | 300 | None |

### 6.2.2 Enemy balance (ENEMY-01 to ENEMY-04, VISUAL-02)

Speed is units per simulation second. Scale is relative to the supplied mesh. Materials
are appearance variants; their exact asset paths are listed in the asset catalog.

| Species | Tier | Health | Speed | Contact damage | Bounty | Scale | Material variant |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Slime | 1 | 12 | 150 | 5 | 1 | 0.9 | MI_Slime1 |
| Slime | 2 | 40 | 170 | 10 | 3 | 1.2 | MI_Slime2 |
| Slime | 3 | 110 | 190 | 15 | 7 | 1.4 | Default_Monster |
| Skeleton | 1 | 25 | 150 | 20 | 2 | 0.7 | MI_Skeleton3 |
| Skeleton | 2 | 90 | 170 | 30 | 5 | 1.1 | MI_Skeleton2 |
| Skeleton | 3 | 600 | 210 | 50 | 9 | 1.4 | MI_Skeleton1 |
| Orc | 1 | 150 | 120 | 25 | 6 | 0.7 | Default_Monster |
| Orc | 2 | 700 | 140 | 45 | 14 | 1 | MI_Orc2 |
| Orc | 3 | 1000 | 160 | 10 | 30 | 1.3 | MI_Orc1 |
| Bat | 1 | 10 | 170 | 7 | 1 | 0.7 | MI_Bat2 |
| Bat | 2 | 50 | 190 | 12 | 4 | 1 | Default_Monster |
| Bat | 3 | 180 | 210 | 20 | 7 | 1.3 | MI_Bat1 |
| Dragon | 1 | 110 | 160 | 20 | 6 | 0.9 | MI_Dragon1 |
| Dragon | 2 | 3500 | 80 | 40 | 400 | 2 | MI_Dragon2 |
| Dragon | 3 | 8000 | 80 | 70 | 1 | 3 | Default_Monster |

### 6.2.3 Complete wave schedule (WAVE-02 to WAVE-05)

Each group is written as `count x species tier`. All groups in a row share its total
spawn duration; ordering and exact positions may vary with seed. North is the upper
edge of the screen. The final schedule entry uses tier 3 for every species.

| Wave | Groups | Spawn duration (s) | Entry edges |
| --- | --- | --- | --- |
| 1 | 20 x Slime 1 | 5 | North |
| 2 | 15 x Slime 1; 10 x Skeleton 1 | 5 | North, West, East, South |
| 3 | 60 x Slime 1; 15 x Skeleton 1 | 10 | North, South, West, East |
| 4 | 30 x Slime 1; 40 x Bat 1 | 10 | North, West, East, South |
| 5 | 40 x Skeleton 1; 30 x Bat 1 | 10 | West, East, South, North |
| 6 | 150 x Slime 1; 20 x Slime 2 | 15 | North, South |
| 7 | 20 x Slime 2; 90 x Bat 1 | 5 | North, South, West, East |
| 8 | 20 x Orc 1 | 10 | North, South, West, East |
| 9 | 25 x Orc 1; 50 x Slime 2; 70 x Skeleton 1 | 10 | North, South |
| 10 | 120 x Skeleton 1; 30 x Skeleton 2 | 10 | North, South, West, East |
| 11 | Rest; no enemies | 8 | None |
| 12 | 100 x Bat 1; 30 x Bat 2 | 12 | North, South, West, East |
| 13 | 20 x Dragon 1; 1 x Dragon 2 | 10 | North, South |
| 14 | 50 x Skeleton 2; 30 x Slime 3 | 10 | North, South, West, East |
| 15 | 150 x Slime 1; 50 x Slime 2; 25 x Slime 3 | 10 | West, East |
| 16 | 20 x Bat 2; 30 x Dragon 1; 30 x Slime 3 | 15 | North, South, West, East |
| 17 | 50 x Bat 2; 50 x Skeleton 2 | 5 | North, South, West, East |
| 18 | 30 x Orc 2 | 10 | East, West |
| 19 | 100 x Skeleton 1; 50 x Skeleton 2; 25 x Skeleton 3 | 10 | North, South, West, East |
| 20 | 50 x Bat 3 | 10 | North, South, West, East |
| 21 | 30 x Orc 2; 50 x Skeleton 3 | 5 | South, North, West, East |
| 22 | 50 x Orc 3 | 10 | North, South, West, East |
| 23 | 30 x Skeleton 3; 20 x Orc 3 | 10 | North, South, West, East |
| 24 | 1 x Dragon 3 | 0.1 | North, South, West, East |
| 25 | 30 x Orc 3; 50 x Skeleton 3; 1 x Slime 3; 20 x Bat 3 | 10 | North, South, West, East |

### 6.2.4 Phase, controls and visible counters

The following boundaries belong to START-01, SELECT-01 to SELECT-03, WAVE-01 to WAVE-05,
SPEED-01, PAUSE-01, DEFEAT-01, DEFEAT-02, RESTART-01 and UI-01.

An active, unpaused round includes preparation, countdown, combat and rest. Building,
inspection, upgrades, selling, cancellation and holding F are available in all four phases
when their own prerequisites hold. Rest does not disable income, regeneration or construction.
P pauses any of these phases. R/Restart and Exit work in every phase, including rest, pause
and defeat. Mute remains operable in pause and defeat. Escape cancels selection/details;
it never resumes, pauses or exits the game.

| Phase | Current/upcoming wave | Completed waves | Enemy counters | Countdown | Speed |
| --- | --- | --- | --- | --- | --- |
| Preparation | 0 | 0 | All zero | 0 | 1 or 3 while F is held |
| Countdown | The next wave, completed waves + 1 | Previously cleared count | All zero | Remaining part of 2 seconds | 1 or 3 |
| Combat | The active wave | Previously cleared count | Total = scheduled count; spawned = emitted count; alive = living emitted enemies; remaining = total - spawned + alive | 0 | 1 or 3 |
| Rest | 11 | 10 until rest ends | All zero | Remaining part of 8 seconds | 1 or 3 |
| Paused | Preserve the interrupted phase's value | Preserve | Preserve every counter | Preserve the interrupted value | 0 |
| Defeated | Preserve the wave reached, including an upcoming wave if defeat occurred in countdown | Preserve the count completed before defeat | Preserve values after the terminal damage/death resolution | Preserve the value at defeat | 0 |

Pausing never changes a combat counter to zero. Resume returns to the interrupted phase
and its remaining timers; it does not restart the wave, rest period, construction or income
cycle. Entering pause closes selection, preview and context details. Resume begins at 1x;
F must be released and pressed again to re-enable 3x. Input begun before pause, defeat,
focus loss or Restart cannot cause a purchase or action after that transition.
Losing window focus cancels selection and 3x, but does not itself pause simulation. Regaining
focus requires fresh presses for gameplay actions; previously held keys/buttons are not actions.

Each press of P or R acts once until released. A purchase/upgrade/sale click requires a
press and release on the same enabled target without an intervening pause, defeat, Restart
or focus loss. Normal countdown/combat/rest transitions do not cancel an otherwise valid
click. Dragging off the target cancels that click. A UI click never also selects or purchases on
the world beneath it. If visible controls overlap, only the topmost enabled control acts.
Pointer motion, hover, selection and cancellation never spend or award currency.

### 6.2.5 Board, movement and contact boundaries

These boundaries belong to SCENE-02, BUILD-01 to BUILD-03, ENEMY-01 to ENEMY-03,
ARCHER-01, ARCHER-02, CANNON-01 and CANNON-02.

Coordinates are zero-based (column, row), each from 0 through 19. Integer coordinates
identify cell centers. A cell extends half a cell to either side of its center; the clearing
therefore extends from -0.5 through 19.5 in each coordinate. Internal cell borders belong
to the cell to their right/bottom; the far right/bottom outer border belongs to cell 19.
The projected pointer must be inside the clearing and outside blocking UI for placement.
The crystal, each deposit and each built structure occupy exactly one cell. Decorative
model overhang does not reserve adjacent cells. No structure may occupy the crystal cell;
only a mine may occupy any deposit cell, including after that mine is sold or destroyed.

All attack-range, nearest-target, splash and ground-contact distances use the ground plane,
independent of flight height or camera projection. Tower range is measured from its cell
center to the enemy's ground-projected center. A target exactly 1000 units away is in range.
Splash is measured from the impact's ground-projected center to each enemy center; its
radius boundary is included. Height alone never makes a flying enemy untargetable by an
archer. Projectile travel speed is distance along its visible 3D path per simulation second.

For movement obstruction and melee contact, a structure/crystal has its cell's 200-unit
square footprint and an enemy has a circular ground footprint of radius 40 times its tier
scale in Section 6.2.2. Contact begins when these footprints touch. Enemy attack animation
may reach toward the model, but cannot extend this gameplay contact distance. Flyers use
this ground-contact rule against the crystal while remaining visibly airborne. Ground
enemies stop at the first living structure blocking their approach, including a structure
under construction, and attack it until removed. They do not choose a longer route solely
to avoid attacking that obstruction. With no obstruction, movement advances toward the
crystal at the listed speed. Small steering adjustments are free; permanent circling or
stalling is not. Equally near simultaneous contacts may use any stable choice.

Enemies may overlap one another; they do not block, damage or displace other enemies.
Exposed deposits, corpses, feedback and decorative foliage do not block enemy movement.
Decoration must leave entry routes usable. Placement is rejected if the prospective square
footprint intersects a living ground enemy's circular footprint; flyers and corpses do not
reserve build cells. Touching without positive overlap is allowed. No purchase may trap
or displace an existing ground enemy.

### 6.2.6 Wave emission and timing boundaries

These boundaries belong to WAVE-01 to WAVE-05, RANDOM-01, ECONOMY-02, HEALTH-01,
ENEMY-03, ARCHER-01, CANNON-01 and COMBAT-01.

The first valid mine purchase starts the first 2-second countdown immediately, even while
its construction animation is running. Selling or losing that mine does not cancel it.
Every later wave, including wave 11 and wave 12, also has a 2-second preceding countdown.
Wave 11 then spends exactly 8 simulation seconds in rest, clears once, and starts the
countdown to wave 12. No enemy is emitted in rest. Clearing any wave has no separate coin
bonus; currency comes only from the specified income, bounties and sale refunds.

For a combat wave containing N enemies with spawn duration T, emissions are evenly spaced
by T/N simulation seconds. Enemy number k enters at k times T/N after the wave starts,
for k = 1 through N. There is no emission at time zero, and the last occurs at T.
For the single-enemy wave 24, its only enemy enters at 0.1 seconds; the prohibition on
instantaneous release of an entire multi-enemy wave does not forbid this case. The 8-second
rest is not a spawn schedule. The same timing applies to endless waves after their integer
group counts have been determined. Nearby scheduled times may fall within one rendered
frame, but they must not become a front-loaded or delayed batch outside the timing tolerance.

Distribute the N emissions across the enabled sides so that side totals differ by at most
one. If N is smaller than the number of enabled sides, use N distinct sides. The seed may
choose the sides receiving remainders, species order and positions along each side. A spawn
center is one cell beyond the nearest edge-cell center: north row -1, south row 20, west
column -1, or east column 20. Its other coordinate lies from 0 through 19. Never spawn in
the clearing or on a disabled side. All members of a wave share the single schedule above;
different species groups do not each receive the full emission rate.

The seed is a nonnegative integer from 0 through 4294967295, default 50 when omitted.
An explicitly supplied value outside that range or not an integer is a visible launch
configuration error; it must not silently change the seed or other rules. Restart reuses
the configured seed and begins its wave sequence afresh. Repeated identical timed player
actions in one implementation produce identical side/group/position choices. Exact random
sequences are free across different implementations. Input-free rendering and observation
must not change these choices. No minimum win rate or survival duration is imposed.

Time in gameplay rules is simulation time unless explicitly called real time. At 3x, a
10-second mine interval takes 10/3 real seconds while uninterrupted; at pause/defeat it
does not advance. Income cycles begin at the accepted purchase time, not at animation end.
Payouts occur at ages 10, 20, 30, ... simulation seconds for each living mine. Damage does
not restart the cycle. Regeneration begins whenever a living owned object has missing
health; there is no extra delay after damage. It gives exactly 2 health per simulation
second of missing health, capped at maximum, including during preparation and rest.

The first enemy hit is immediate on first contact. Later hits are at least 1.0 simulation
second apart for that enemy, including across target changes or temporary loss of contact.
An enemy ready to hit while out of contact may hit once when contact returns; it cannot
accumulate multiple hits. Newly completed towers are immediately ready for one eligible
shot. A shot begins its tier's full cooldown at release. With no eligible target the tower
may become ready, but cannot save multiple shots for later. Consecutive shots at a continuously
available target follow the listed cooldown without cumulative drift.

### 6.2.7 Transactions, construction and projectiles

These boundaries belong to BUILD-01 to BUILD-03, ECONOMY-01, ECONOMY-02, INSPECT-01,
UPGRADE-01 to UPGRADE-03, SELL-01, HEALTH-01, HEALTH-02, ARCHER-02, CANNON-02 and COMBAT-01.

A successful purchase immediately reserves its cell, joins its type's living count, charges
the price before that count increases, and has full tier-1 health. Construction takes a
consistent duration per structure type within 0.15-0.6 simulation seconds. It blocks movement,
can be damaged, and may be inspected or sold during construction. Its tower weapon cannot
fire until construction ends. Upgrade during construction is rejected without cost.
All construction timers freeze on pause. A destroyed/sold object never finishes construction.
The displayed current purchase price applies to the accepted transaction; it is not a quote
locked when the build icon was first selected. Affordability includes exact equality.

After any build, sale or destruction, prices use the current living count, including objects
still constructing. Repeated valid clicks are separate purchases only if each has a legal
unoccupied target and sufficient current funds. Selling refunds half the amount actually
paid to place that particular object, rounded down; it does not use its current replacement
price. Upgrades never increase that refund. Every exposed deposit remains reserved for a mine.
All coins, costs, refunds and bounties are nonnegative integers, with no hidden cap or overflow
within a run. Fractional health is retained; display rounding never changes actual health.

Upgrade immediately changes maximum health, health percentage, future damage and appearance.
If a cooldown is already running, its remaining simulation time stays unchanged: it is neither
restarted, shortened nor lengthened by the upgrade. The next released shot uses the new tier
and begins the new tier's cooldown. A ready tower remains ready. Multiple upgrades before
the next shot still preserve that pending cooldown. Rejected upgrades change nothing.

Every launched projectile retains its release-time damage and, for a cannonball, splash
radius, even if its tower is upgraded, sold or destroyed. Tower removal prevents new shots
but does not cancel shots already airborne. Projectiles have finite visible travel; they
cannot teleport damage to their intended target or switch to another target after release.
Aim may use the target's current position or a predicted interception point. Straight or
curved paths and exact prediction are free, but the aim destination is fixed at release.
An arrow can hit the first eligible living enemy it actually contacts, even if that enemy
was not its intended target. A cannonball explodes on its first ground, structure or living
ground-enemy impact. An explosion can affect multiple enemies, once each, with no damage
falloff inside its radius and no extra direct-hit damage. No friendly structure takes
projectile or splash damage. A cannonball passes flying enemies without affecting them.

Terrain and living structures other than the firing structure block projectiles. An arrow
hitting such a blocker disappears without damage. A cannonball explodes at that surface.
Decorative foliage, exposed deposits, corpses, previews and feedback do not block shots.
An enemy hit must agree with contact against its visible body; invisible enlarged hit areas
or hits after the enemy disappeared are invalid. A missed projectile disappears by age
4 simulation seconds; expiry without impact causes no damage or explosion. At an impact
exactly at its 4-second lifetime, impact wins. An intended target leaving tower range after
release does not cancel the projectile or make a real subsequent impact harmless.

### 6.2.8 Simultaneous events, pause, defeat and reset

These boundaries belong to COMBAT-01, ENEMY-03, ENEMY-04, HEALTH-01, HEALTH-02,
ECONOMY-02, UPGRADE-01, SELL-01, WAVE-04, PAUSE-01, DEFEAT-01, DEFEAT-02,
RESTART-01, RESTART-02 and VISUAL-04.

The following table specifies observable outcomes when the named events are due at the
same simulation time. Earlier completed events remain completed. These are behavior rules,
not a prescribed internal event system.

| Coincident events | Required outcome |
| --- | --- |
| Restart and any other action/event | One clean new round; the old round contributes no purchase, damage, reward or delayed effect to it. |
| Accepted Pause and a due gameplay event | Pause freezes before that event; it remains due once on Resume. |
| Enemy death and that enemy's next melee hit | The dead enemy does not deliver that hit. Its bounty is awarded once unless defeat also occurs. |
| Lethal damage and regeneration on the same object | Destruction/defeat occurs; regeneration cannot revive it or prevent the lethal outcome. |
| Destruction and upgrade/sale of the same structure | Destruction wins; no upgrade charge or sale refund occurs. For nonlethal damage, health changes before an accepted upgrade preserves the resulting health percentage. |
| Mine removal and its payout | No payout from that mine. |
| Wave clearance and a living mine's payout | Increment completed waves once first; that payout uses the newly completed count. |
| Crystal defeat and another bounty, payout, wave clearance or scheduled spawn | Defeat wins; no same-time reward, completed-wave increment, new wave or emission follows. Enemy deaths due at that time still update their living/remaining counts, without bounty. |
| Multiple hits on one enemy | It dies once, grants at most one bounty and stops being an eligible target; excess damage cannot affect a later entity. |

Zero health is clamped to zero. An enemy corpse may remain visible for a death animation
lasting 0.15-2 simulation seconds, but has no collision, targeting, attacks or wave-blocking
presence. Enemy health is never regenerated. Removed structures leave no gameplay blocker;
purely decorative debris may fade for at most 2 simulation seconds without occupying a cell.

Pause freezes world animation, construction, projectiles, feedback lifetimes and all
gameplay timers. UI hover, overlays, mute and normal window operations remain responsive.
Defeat freezes gameplay positions, timers and surviving-entity health. The result panel and
purely cosmetic crystal destruction effect may animate for up to 2 real seconds after defeat;
they cannot move surviving enemies, apply damage, pay rewards or change progress. Presentation
feedback may finish without implying a continuing simulation. Speed is 0 in pause/defeat.

Restart is available throughout all phases, including rest and an unfinished construction
or death effect. A fresh playable board and opening instruction appear within 1 real second
of an accepted Restart, with no automatic purchase caused by a held input. The new round
resets all gameplay timers, the configured seed's sequence, wallet, objects, counts, selection
and speed to START-01; holding R does not continuously create rounds. It does not restart
the application. A new process also begins at START-01. Only non-gameplay preferences such
as mute or window size may persist; they cannot change rules, seed, progress or initial coins.

### 6.2.9 Presentation and allowed variation

These boundaries belong to SCENE-01, UI-01 to UI-03, VISUAL-01 to VISUAL-04 and AUDIO-01.

Mandatory models, tier materials, enemy animations, HUD font and specified icons must be
visibly used in their stated roles; retaining unused files is insufficient. Different
animation blends, decorative placements, particle designs, camera angles within the fixed
elevated three-quarter view, lighting tuning and panel dimensions are permitted. Exact
pixels, incidental tree counts, random trajectories and private object names are not
acceptance targets. Both supported 16:9 resolutions must keep all build cells reachable,
the crystal discoverable, and active controls/text unclipped. UI overlays consume input
only where actually visible; they cannot leave invisible hit regions after closing.

The crystal's health bar is always visible while it is alive. Other full-health bars may
be hidden until hover/selection; damaged-object bars stay visible until full health or
removal. Health bars show the actual fraction, and numeric health may round to the nearest
integer for display. Build panels and context details must show the complete applicable
monetary amount before purchase, upgrade or sale. Rejections explain at least the first applicable reason; no order between
multiple valid rejection reasons is required. Temporary action messages appear within
0.2 real seconds and clear within 2 real seconds unless refreshed by a new action.

The selected/valid/invalid state needs an outline, shape or label as well as color. Action
effects belong to the affected object, never to an unrelated target or an entire-screen
substitute. In-world income/bounty text lasts 0.5-2 simulation seconds and stops with pause;
restart removes it immediately. Combat effects must leave enemies and health bars readable.
Audio acceptance is limited to background music, audible feedback for a representative
gameplay action, and a working mute/unmute control. Muting silences background and event
audio; restoring audio makes the background audible again. Gameplay and visual feedback
remain usable while muted. Exact onset latency, waveform matching, exhaustive per-event
cue coverage and musical quality are outside acceptance. Audio file selection, volume
and musical behavior during pause are free within these limits. The 0.2-second limits
elsewhere in this section still apply to visible UI feedback, not to audio onset.


### 6.3 Shared numbered requirements

| ID | Requirement |
| --- | --- |
| QUALITY-01 | The project can start, run, exit and start again using the public instructions. |
| QUALITY-02 | The main flow uses normal player input, without answer buttons, cheat entries or direct result shortcuts. |
| QUALITY-03 | Key entry points, text and controls are visible, discoverable, readable and operable. |
| QUALITY-04 | Player actions have perceptible feedback that agrees with the real game state. |
| QUALITY-05 | No severe error blocks the main flow. |
| QUALITY-06 | Repeated runs under the same initial conditions are substantially stable. |

## 7. Success, failure and multi-stage flow summary

### 7.1 Success

| Requirement | Preconditions | Success | Subsequent state |
| --- | --- | --- | --- |
| BUILD-01, UPGRADE-01 | Legal target and sufficient money | New defense or next tier | Continue combat/preparation |
| WAVE-04 | Scheduled spawns finished and all enemies dead | Wave cleared | Next countdown |
| WAVE-05 | Fixed schedule cleared | Continue survival | Endless escalation; no campaign victory |

### 7.2 Failure

| Requirement | Trigger | Feedback | Recovery |
| --- | --- | --- | --- |
| BUILD-02, UPGRADE-03 | Illegal or unaffordable action | Clear rejection; no transaction | Choose a legal action |
| DEFEAT-01, DEFEAT-02 | Crystal destroyed | Stable Game Over result | Restart or Exit |

### 7.3 Stage ordering

| Stage | Requirement | Result that cannot occur early |
| --- | --- | --- |
| Select, preview, confirm | SELECT-01, SELECT-02, BUILD-01 | Purchase before a legal click |
| Launch, travel, collide | ARCHER-01, ARCHER-02, CANNON-01, CANNON-02 | Damage before projectile impact |
| Countdown, emit, clear | WAVE-01, WAVE-02, WAVE-04 | Wave clearance while enemies are unspawned/alive |
| Defeat, freeze, Restart | DEFEAT-01, DEFEAT-02, RESTART-01 | Delayed events changing the final or new round |

## 8. Interface and feedback summary

| Requirements | Information | Player distinction |
| --- | --- | --- |
| UI-01, ECONOMY-01, ECONOMY-02 | Wallet, prices, wave state | Affordable actions and incoming danger |
| SELECT-02, UI-03 | Preview and rejection | Legal versus illegal placement |
| INSPECT-01, UI-02 | Selected building and health bars | Type, tier, health and next action |
| SPEED-01, PAUSE-01, DEFEAT-01 | Speed, pause and result | Running, paused and finished state |
| VISUAL-04, AUDIO-01 | Effects and audio | Build, upgrade, fire, impact, reward and loss |

## 9. Restart, reopen and saving summary

| Scenario | Requirement | Reset | Preserve |
| --- | --- | --- | --- |
| In-process Restart | RESTART-01 | Entire run, transient objects, selection and speed | Only optional preferences |
| New process | RESTART-02 | All run progress | Only optional preferences |

## 10. Existing functionality to preserve

Not applicable: this is a complete game implementation from an empty starter. The starter health
screen and its Space probe are temporary scaffolding, not gameplay to retain (START-01, QUALITY-02).

## 11. Assets and content summary

All supplied runtime visual art is already installed as native UE assets under
`starter-project/Content/`. Use these assets for the mandatory groups below; do not replace them
with newly sourced or generated substitutes. Material tuning, layout and animation blending
remain free within VISUAL-01 to VISUAL-03 and UI-01.

| Requirements | Exact supplied paths or catalog selector | Mandatory use | Purpose and replacement boundary |
| --- | --- | --- | --- |
| VISUAL-01 | `starter-project/Content/Resources/Buildings/Buildings_*.uasset`; exact model rows in assets/ASSET_CATALOG.md | Yes | Crystal, mines, three tower tiers, weapons and walls; tuning allowed, generic substitute models excluded |
| VISUAL-02 | `starter-project/Content/Resources/Characters/Monsters/Slime/`, `Skeleton/`, `Orc/`, `Bat/`, `Dragon/`; exact mesh/clip rows in assets/ASSET_CATALOG.md | Yes | Animated enemies and tier variants; animation blending is free |
| VISUAL-03 | `starter-project/Content/Resources/Environment/`; exact environment/dependency rows in assets/ASSET_CATALOG.md | Yes for the visible scene categories | Assemble the clearing/forest; decorative placement is free |
| UI-01 | `starter-project/Content/Resources/Baloo-Regular_Font.uasset` and its font face; `starter-project/Content/Resources/Icon-Coin.uasset`; `starter-project/Content/Resources/Buildings/ArcherTower.uasset`, `CannonTower.uasset`, `GoldMine.uasset`, `Wall.uasset` | Yes | Baloo HUD text, currency icon and all four build icons; size, framing and tint may be tuned |
| VISUAL-04 | Supplied textures/materials in assets/ASSET_CATALOG.md | Equivalent effects allowed | Assemble action feedback; no prebuilt gameplay effect is provided |
| AUDIO-01 | `starter-project/Content/Sounds/RoundMusic.uasset`, `assets/files/audio/*.wav` | Equivalent legal audio allowed | Background music and distinct event cues |
| SCENE-01, VISUAL-03 | `reference/01-opening.png`, `02-placement.png`, `03-combat.png` | Illustrations only | Explain the written scene requirements; not runtime art, backgrounds or additional acceptance rules |

Dependency facts, object paths, hashes, license notices and import properties are in the asset
catalog and legal directory. This section summarizes the numbered requirements only.

## 12. Implementation freedom

Any code/Blueprint structure, scene organization, input technology, renderer, targeting data
structure, animation blend and reset technique is allowed if Section 6 is satisfied. Public
board coordinates and observation names do not constrain internal class names, world axes or
object hierarchies. No source-code similarity or matching of internal object names is required.

## 13. Pre-submission self-check

- Each implemented behavior maps to Section 6, including all shared QUALITY rows.
- The opening, economy, both weapons, all species, all waves, loss and lifecycle are implemented.
- Rejections, repeated clicks, in-flight events and clean Restart/Reopen follow their own rows.
- Mandatory presentation assets are assembled into a playable scene with readable feedback.
- Runtime claims describe checks actually performed; remaining gaps identify their requirement IDs.
- Public tool and observation contracts remain readable and consistent with the completed project.
