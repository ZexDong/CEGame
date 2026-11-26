# BoneMaze

## 1. One-sentence task

Guide a spectral bone mage through a persistent dungeon maze,
use scarce scrolls to locate a pursuing monster, collect three coloured keys and
escape through the final portal (MAZE-01 through MAZE-05, MONSTER-01 through
MONSTER-06, SPELL-01 through SPELL-03, KEY-01, EXIT-01, EXIT-02).

## 2. Scope

### 2.1 Included

| Requirements | Experience |
| --- | --- |
| ENTRY-01, ENTRY-02, MAZE-01 through MAZE-05 | Three complete seeded maze difficulties and varied chambers |
| MOVE-01 through MOVE-03, PORTAL-01 through PORTAL-03 | Continuous 3D movement and persistent portal traversal |
| MONSTER-01 through MONSTER-06, SPELL-01 through SPELL-03 | Turn-driven pursuit, danger, reveals and recovery |
| KEY-01, DOOR-01 through DOOR-04, PICKUP-01 through PICKUP-04, ECON-01, ECON-02 | Keys, animated gates, collectible economy |
| EXIT-01, EXIT-02, LIFE-01, LIFE-02, RESET-01 through RESET-04 | Win, lose, pause, restart and clean reopening |
| UI-01 through UI-03, VISUAL-01 through VISUAL-06, AUDIO-01, AUDIO-02 | Complete audiovisual presentation |
| ASSET-01 through ASSET-07, OBSERVATION-01, QUALITY-01 through QUALITY-06 | Supplied art, observations and basic quality |

### 2.2 Excluded

No multiplayer, online services, combat/weapon system, crafting, permanent upgrades,
save-game progression, mobile/controller support or extra campaign is requested.
Decorative trap models do not imply an additional trap-damage system.

## 3. Starting state

| Item | Supplied state | Completed-game requirement |
| --- | --- | --- |
| Project entry | An independent empty Unreal Engine native starter, opening an unfinished health screen | ENTRY-01 |
| Art/audio | Individual imported presentation packages in the UE Content directory | ASSET-01 through ASSET-07 |
| Gameplay | No assembled maze, player controller, monster turns, doors or pickups | Section 6 |
| UI | Health text and a Space input probe only | UI-01 through UI-03, VISUAL-06 |
| Observation | Honest not_ready snapshot with empty entities and zero slots | OBSERVATION-01 |
| Final fresh-run values | Defined by the completed game's start requirement | ENTRY-02 |

## 4. Player goal and complete flow

### 4.1 Goal

Avoid losing all lives while obtaining every coloured key and reaching the exit
(KEY-01, MONSTER-04, LIFE-01, EXIT-01, EXIT-02).

### 4.2 Complete flow

ENTRY-01 choose difficulty/seed -> ENTRY-02 spawn -> MAZE-01/MAZE-05 explore ->
KEY-01 obtain keys and DOOR-01/DOOR-03 open gates -> EXIT-02 escape or LIFE-01 lose ->
RESET-01 restart or RESET-03 return to menu.

### 4.3 Repeated loop

MOVE-01 inspect a room -> SPELL-01/SPELL-02 decide whether to reveal ->
DOOR-01/PORTAL-01 choose and cross an exit -> MONSTER-02/MONSTER-04 resolve danger ->
PICKUP-02/KEY-01 collect useful resources -> choose the next route.

## 5. Player controls

| Input | Context and response | Requirements |
| --- | --- | --- |
| Mouse click | Menu, seed entry and visible controls | ENTRY-01, MAZE-04, UI-03 |
| W/A/S/D, including held diagonal pairs | Continuous view-relative movement | MOVE-01, MOVE-02 |
| Walk across open threshold | Travel to paired chamber | PORTAL-01 |
| E | Interact with a nearby gate | DOOR-01 through DOOR-03 |
| Q | Spend one scroll to reveal the monster | SPELL-01 through SPELL-03 |
| Touch a pickup | Collect it once | KEY-01, PICKUP-02 through PICKUP-04, ECON-01 |
| Walk into final portal | Attempt escape | EXIT-01, EXIT-02 |
| R / Restart | Fresh run, same difficulty and seed | RESET-01, RESET-02 |
| Escape / pause controls | Pause, resume, restart or return to menu | RESET-03 |

## 6. Numbered requirements: sole acceptance authority

### 6.1 Interpretation

Each row defines a separately assessable player outcome. Other sections summarize
these rows. Visual images illustrate composition, not additional hidden rules.
The boundary tables in Section 6.4 define simultaneous events, timing, input and
content conditions for the numbered requirements named in their Owner column.
Where an exact value or implementation is not specified here, reasonable solutions
that meet the player outcome are valid.

### 6.2 Game-specific requirements

| ID | Preconditions | Player action / trigger | Required result | Forbidden result | Visible feedback | Failure, repetition and lifecycle boundaries |
| --- | --- | --- | --- | --- | --- | --- |
| ENTRY-01 | Fresh application or Main Menu. | Choose Easy, Medium or Hard; or Exit. | Show the BoneMaze title and four named clickable buttons. A difficulty starts that size; Exit closes normally. | No automatic run before a selection. | Hover/pressed states and a visible difficulty label. | A click starts one run even if repeated during loading. |
| ENTRY-02 | A difficulty has been selected. | Finish loading. | Place the mage safely in the start chamber with 5 lives, 5 scrolls, 0 coins and no keys. | No damage, pickup or room-turn charge on initial spawn. | The HUD and spawn animation agree with the initial values. | Starting from any difficulty uses these same resources. |
| MAZE-01 | A new run is starting. | Generate the dungeon. | Easy has 36 chambers labelled by coordinates 1..6 on both axes; Medium has 100 with 1..10; Hard has 225 with 1..15. Every pair identifies exactly one persistent chamber. | No difficulty implemented by changing only a label or resource amount. | Current chamber coordinates are always shown during play. | Coordinates do not change when revisiting a chamber. |
| MAZE-02 | A dungeon is generated. | Explore its exits. | Each chamber has four distinct perimeter exit slots. Pair slots into stable, bidirectional connections to different chambers; each chamber has four different neighbours. All chambers form one connected maze. Include non-geometric connections: at least one exit connects coordinate pairs more than one grid step apart. | No self-loops, dangling exits, disconnected rooms or re-randomizing an exit during a run. | Visible passage openings; arrival is inside the paired destination exit. | Coordinates identify chambers, not a promise of geometric adjacency. Returning through the paired exit returns to the chamber just left. |
| MAZE-03 | The maze is generated. | Explore and collect keys. | Use five different chambers for start, exit, red key, green key and blue key. Include at least one gate of each key colour on maze connections. Every key is reachable without requiring that same key or a circular key dependency; all chambers are reachable after collecting keys. | No key or exit in the spawn chamber, unreachable collectible or unavoidable locked-key cycle. | Distinct key chambers and a recognizable exit chamber. | Both sides of a gated connection share its lock/open state. No particular key order is prescribed. |
| MAZE-04 | Difficulty and a 32-bit unsigned seed are selected. | Start or Restart; repeat the same normal input sequence. | The same difficulty and seed reproduce room links, roles, layouts, pickups and monster decisions. Accept a seed in the start menu and the documented launch option; use 48 when omitted. Different seeds vary the generated dungeon. | No dependence of monster choices on frame rate, screenshot capture, waiting time or observation reads. | Display the active seed and difficulty in the menu/pause information. | Restart reuses the current seed. Changing the seed starts a fresh run. Exact generated layouts need not match another implementation. |
| MAZE-05 | A complete dungeon is generated. | Visit chambers. | Provide at least 20 distinguishable ordinary room arrangements plus separate start, three coloured key and exit arrangements. Every ordinary arrangement appears at least once even on Easy. Vary walkable prop placement and architectural silhouettes using pillars, coffins, grates, rubble, skulls, furnishings and floor tiles. | No set of colour swaps or identical empty rooms counted as different arrangements. | Room composition helps the player recognize previously visited locations. | All mandatory exits and collectibles remain physically reachable; props do not conceal required interactions. |
| MOVE-01 | Exploration is active. | Hold W/A/S/D or a diagonal pair, then release. | Move continuously up/left/down/right relative to the fixed view; diagonal movement has the same top speed as axial movement. Face the travel direction. | No click-only movement, grid-step-only locomotion or drifting after release. | Visible locomotion and idle poses. | Opposite directions cancel; menu/terminal input does not move the character. |
| MOVE-02 | A room contains solid boundaries or props. | Walk against them. | Walls, unopened gates and large solid props block passage; the floor supports the player. | No clipping out of the chamber, falling through the floor or walking through a closed door. | The player stops at the obstacle while controls remain responsive. | Sliding along a wall does not create a room transition unless an exit threshold is crossed. |
| MOVE-03 | Exploration is active. | Walk and change chambers. | Use an elevated, fixed-orientation three-quarter 3D camera that tracks the mage smoothly, shows the surrounding floor and exits, and settles on the destination after a transition. | No free first-person camera or flat top-down board substituting for the dungeon scene. | Readable character silhouette, depth and floor perspective. | Walls may fade or be cut away when necessary to keep the player readable. |
| PORTAL-01 | A passage is unobstructed. | Walk across its threshold. | Transfer to its connected chamber and place the mage just inside the paired arrival passage. Update chamber coordinates once. | No E press required for an already open passage; no coordinate-only change while displaying the previous room. | Short portal/scene transition feedback and destination scenery. | Arrival does not immediately send the player back without leaving and re-entering the threshold. |
| PORTAL-02 | A transfer has started. | Hold movement or press Q/E during the transition. | Complete only one room transfer and one monster turn; resolve arrival/encounter within 1 second. Without a hit, settle by then; a nonfatal hit instead enters the separate MONSTER-05 recovery interval. Accept new gameplay actions only after settlement. | No duplicate turns, pickup activation in two rooms, or stacked transitions from one crossing. | Destination and HUD become stable together. | Cancel in-flight effects and callbacks if the run is restarted. |
| PORTAL-03 | A visited chamber contains opened gates or consumed pickups. | Leave and return. | Restore that chamber with its existing gate and pickup state. | No resource respawn, duplicate key or reset door when revisiting. | The same room identity, architecture and remaining items. | Persistence lasts for this run only. |
| MONSTER-01 | A fresh run is generated. | Enter the start chamber. | There is exactly one roaming monster, initially in a different chamber at least two maze connections away from the player. | No initially unavoidable hit or simultaneous roaming duplicates. | The monster is hidden when it occupies another chamber. | No global permanent monster marker in normal gameplay. |
| MONSTER-02 | A run is active. | Wait, walk inside a room, cast, open a gate or cross a passage. | The monster takes exactly one turn per completed room crossing. Waiting, local movement, casting, pickups and door interactions take no monster turn. | No real-time pursuit between room crossings or extra turn on respawn. | Danger/reveal information reflects the settled room turn. | Failed, blocked and cancelled transfers do not move the monster. |
| MONSTER-03 | A room crossing has selected a destination different from the current monster room. | Resolve that crossing. | The monster moves to exactly one connected neighbour. On each turn, choose pursuit with probability 6/11 and wandering with probability 5/11. Pursuit selects a neighbour that shortens the minimum connection distance to the destination; wandering selects uniformly among neighbours. Locked player gates do not block the monster. | No jumping multiple edges, leaving the maze or using wall-clock randomness. | A subsequent reveal reports the resulting chamber. | Shortest-route ties may be resolved consistently by the implementation; wandering may choose a pursuit neighbour. |
| MONSTER-04 | The player crosses into the monster room, or its one movement step reaches the player destination. | Resolve the encounter. | Lose exactly 1 life. A direct entry into the occupied room resolves the hit before the monster can escape; no additional monster move occurs on that direct-entry hit. | No missed encounter, negative life count or repeated damage from a single crossing. | Visible monster/bonk reaction, impact sound and one life decrease. | If the new life count is zero, use LIFE-01. Otherwise use MONSTER-05. |
| MONSTER-05 | A hit leaves at least 1 life. | Finish the hit reaction. | Within 2 seconds of the life decrease return the mage to the start chamber, move the monster if necessary so it is at least two connections away, and restore control. Retain keys, scrolls, coin remainder, consumed pickups, opened gates and the maze. | No full run reset or recursive damage caused by recovery. | A brief hit/return transition and the start coordinates. | Recovery itself does not count as a player crossing or another monster turn. |
| MONSTER-06 | The mage is settled in a chamber. | A turn finishes or recovery completes. | Show a nearby-danger cue when the monster is exactly one maze connection away, otherwise clear it. Use a distinct safe/nearby visual state and a brief warning sound when entering danger. | No coordinate-based diagonal false positives or hidden exact position disclosure. | A conspicuous monster/warning icon or indicator. | Recompute after every settled turn, recovery and Restart. |
| SPELL-01 | Exploration is active and scroll count is positive. | Press Q once. | Consume exactly 1 scroll and cast a reveal spell. | No life/coin cost or monster turn from casting. | Mage casting action, luminous ring/sparks, cast sound and decremented scroll HUD. | A held key does not repeatedly consume scrolls; release and press again for another cast. |
| SPELL-02 | A reveal spell succeeds. | Read the reveal, wait or cross a passage. | Show the monster coordinates sampled at cast time for 3 seconds or until the next room crossing, whichever happens first. A new successful cast refreshes the information and duration. | No live tracking after the monster moves and no stale position presented as current. | Monster icon plus explicit coordinate pair below the chamber label. | Restart, recovery, terminal state and menu return clear the reveal. |
| SPELL-03 | Scroll count is zero or a transition/terminal state is active. | Press or hold Q. | Reject casting without changing resources or the monster; in active play show a brief No scrolls message when depleted. | No negative scrolls or free position reveal. | Visible rejection without a cast effect. | Rejected presses do not queue a cast for after recovery or Restart. |
| KEY-01 | An uncollected coloured key is physically reachable. | Touch it. | Acquire exactly its red, green or blue key and remove that pickup. Record at most one owned key per colour. | No other key colours granted, key consumption on door use or duplicate credit. | Coloured key glow, pickup sound and that HUD key becoming active. | Key ownership persists across rooms and nonfatal hits; Restart clears it. |
| DOOR-01 | A closed gate is within 1.5 mage body widths and unobstructed. | Press E. | Interact with the nearest eligible gate; if equally near, choose one consistently. Show an E interaction prompt in range. | No remote opening, hidden/offscreen target selection or multiple gates affected by one press. | Prompt names the gate colour or Open action. | Moving out of range removes the prompt; E elsewhere changes nothing. |
| DOOR-02 | The matching key is not owned. | Press E on a coloured gate. | Keep the gate closed and block passage; state which key colour is missing. | No spending scrolls/coins, moving the monster or opening on repeated presses. | Coloured gate/rune and explicit locked feedback. | A key of another colour never substitutes. |
| DOOR-03 | The matching key is owned and the gate is closed. | Press E. | Animate the gate from closed to open over 3 seconds, with a door sound; allow crossing after it is fully open. | No instant invisible unlock, key consumption or transition while still blocked. | Visible gate motion and an open passage. | Pressing E repeatedly during opening does not restart, reverse or duplicate it. |
| DOOR-04 | A gate has opened. | Leave, return or interact again. | Keep both sides of that connection open for the remainder of the run. | No automatic re-lock, extra resource charge or needless opening animation. | A permanently clear passage until Restart. | Restart restores the initially closed gate state. |
| PICKUP-01 | A dungeon is generated. | Explore its ordinary chambers. | Distribute at least 60 single-coin pickups, 5 scroll pickups and 3 heart pickups on Easy; scale their counts by at least the room-count ratio on larger difficulties. Put them across at least 12 ordinary chambers. | No overlap with solid props, inaccessible placement or all resources stacked in one room. | Visible rotating/bobbing collectible silhouettes with distinct colours. | All remain reachable after obtaining keys. Counts are minimum content, not starting inventory. |
| PICKUP-02 | An unconsumed pickup overlaps the mage. | Collect it, wait, then revisit. | Apply its effect once and remove its world presentation and collision for the run. | No repeated credit from sustained overlap, duplicate components or room reload. | Pickup sound/effect and matching HUD change. | A Restart recreates each pickup at its initial seeded position. |
| PICKUP-03 | An unconsumed scroll pickup is touched. | Collect it. | Increase scroll count by exactly 1, including when already at or above 5. | No implicit cap of 5 or life/coin increase. | Scroll pickup cue and updated scroll count. | A recovered scroll enables Q again immediately after settlement. |
| PICKUP-04 | An unconsumed heart pickup is touched. | Collect it. | Increase lives by exactly 1, including when already at or above 5. | No health bar subsystem or full-health rejection that makes hearts unusable. | Heart pickup cue and updated life count. | Terminal states cannot be revived by a late pickup. |
| ECON-01 | A coin pickup is touched. | Collect it. | Add exactly 1 to the coin remainder, then apply ECON-02 when the threshold is reached. | No score-only coin that fails to affect the life economy. | Coin sound and matching numeric counter. | Already consumed coins never grant credit again. |
| ECON-02 | Coin remainder reaches 50 or more. | Finish the pickup transaction. | Exchange each complete group of 50 coins for 1 life and keep the remainder; 49 plus 1 becomes 0 coins and one extra life. | No lost overflow, repeated life reward or fixed 5-life cap. | Extra-life sound and simultaneous life/coin HUD updates. | Normal settled remainder stays in 0..49. |
| EXIT-01 | The mage is at the final portal without all three keys. | Touch or interact with it. | Keep the run active and display the missing key colours. | No early victory, consumed owned keys or teleport to the ending. | The portal visibly communicates its locked state. | Any two keys are insufficient; repeated attempts remain harmless. |
| EXIT-02 | All three keys are owned, lives are positive and the player is settled in the exit chamber. | Walk into the final portal. | Enter victory exactly once. Show You escaped, difficulty, seed, and visible Restart and Main Menu controls. | No victory merely from acquiring the third key somewhere else. | A luminous portal completion effect, win sound and readable end overlay. | A lethal encounter on entry to the exit chamber resolves before exit activation. |
| LIFE-01 | An encounter removes the final life. | Finish the damage event. | Clamp lives to 0 and enter defeat once. Show You were bonked and visible Restart and Main Menu controls. | No continued exploration, negative life count or recovery to start. | Distinct defeat presentation and lose sound. | A simultaneous late pickup cannot cancel defeat. |
| LIFE-02 | Victory or defeat is active. | Wait or press movement/Q/E. | Keep maze, monster and resources fixed until Restart or Main Menu. | No post-result casts, pickups, motion, monster turns or alternate outcome. | The terminal overlay remains stable and usable. | Repeated terminal input does not dismiss or duplicate the result. |
| RESET-01 | Exploring, transitioning, recovering or on a result screen. | Press R or click Restart where shown. | Begin a new round with the same difficulty and seed, starting state ENTRY-02, restored pickups/closed gates and the seeded initial monster placement. | No retained keys, inventory, room progress, danger or old ending. | A short fresh-start transition and the initial HUD. | A repeated restart request during the reset produces one settled fresh round. |
| RESET-02 | A cast, gate animation, transfer, hit or end effect is in flight. | Restart or return to Main Menu. | Cancel all state-changing activity from the old round before the new state is exposed. | No delayed old hit, teleport, key credit, door opening, reveal or sound loop leaking into the next run. | The new state remains stable after the old effect would have finished. | Entity and round identities in observations change consistently with the new run. |
| RESET-03 | A live round is exploring, transitioning or recovering, or is already paused. | Press Escape to expose pause controls, then Resume, Restart or Main Menu. | Pause freezes gameplay and active effect/reveal timers. Resume restores the same state, including an interrupted transition or recovery. Main Menu discards the run and shows difficulty/seed selection again. | No movement/casting behind the pause UI or continued monster progress. | Readable Resume, Restart and Main Menu controls. | Escape closes the pause UI; opening/closing it does not generate a turn. Result screens keep their own Restart/Main Menu controls; Escape there changes nothing. |
| RESET-04 | The application has been closed. | Launch it again. | Show the main menu with no retained run progress. An explicitly supplied launch seed is accepted again. | No resumed maze, inventory, end state or stale observation from a former process. | Normal menu and a fresh process/session. | Persistent save-game progression is outside scope. |
| UI-01 | A run is active. | Move, collect, cast or take damage. | Show lives at upper left, chamber coordinates at top centre, scrolls and coins at upper right, and three red/green/blue key indicators at lower right. Update affected values by the next rendered frame after settlement. | No mismatch between displayed values and actual game state. | Supplied icons with legible light text and visibly different inactive/owned keys. | Values remain readable at both 1280x720 and 1920x1080. |
| UI-02 | Danger or an active spell reveal exists. | Read the HUD. | Keep nearby danger distinct from exact position reveal; show exact coordinates only while SPELL-02 is active. | No ambiguous stale coordinate text or permanent map exposing all pickups/monster. | A monster icon with clear safe/nearby/revealed meaning. | Clearing a reveal does not clear an independently valid nearby warning. |
| UI-03 | Any game/menu screen is visible. | Read controls and use buttons. | Present all player-facing text in English. Explain WASD, Q, E, R and Escape from the menu or pause UI; keep prompts and controls readable, clickable and within the 16:9 client. | No clipped labels, untranslated errors or essential controls hidden behind decorative UI. | Hover/pressed/disabled distinctions and concise rejection messages. | Keyboard focus and mouse click focus work after returning from gameplay. |
| VISUAL-01 | Exploration is visible. | View a room. | Render a three-dimensional low-poly stone dungeon: dark olive/grey walls and irregular tiled floors, thick pillars, broken masonry, skulls/coffins and scattered props. The central mage has a pale skull, dark blue robe, open book and cyan spectral flame. | No primitive-only arena, flat board or text-only scene replacing the supplied art. | Strong character silhouette within enclosed architectural depth. | Room variety remains visually coherent across all difficulties. |
| VISUAL-02 | Exploration is visible. | Walk through rooms. | Use localized cyan/white magical flames and warm pale light pools against dark corners, with restrained bloom and a dark outer vignette. Keep paths, gates, collectibles and the mage visible. | No uniform bright default lighting, unreadable black rooms or bloom that erases all silhouettes. | Animated flames, contrasting coloured keys/gates and readable floor depth. | Maintain legibility around emissive effects and in darker room variants. |
| VISUAL-03 | Gameplay is rendered. | Move and cast. | Apply a deliberate retro pixelated/dithered 3D treatment to the world while preserving clear UI text and icons. Visible low-resolution edges and textured shading remain consistent in motion. | No heavy blur replacing pixelation or pixelated HUD that becomes unreadable. | A coherent coarse world image, dark vignette and sharp HUD. | At both output resolutions the treatment keeps equivalent visual scale. |
| VISUAL-04 | The mage spawns, idles, walks, casts, takes a hit or escapes. | Perform the corresponding action. | Play distinct supplied skeletal poses/clips for spawn, idle, locomotion, casting, damage/death and a final magical flourish on escape. Blend locomotion coherently and synchronize casts/hits to their visible feedback. | No static T-pose, permanent sliding idle, interrupted loop stuck forever or attack-combat substitution. | Book/robe movement and cyan head flame remain attached to the mage. | Return to idle after nonterminal actions; death/escape may hold a final pose. Restart cancels old animation/event effects. |
| VISUAL-05 | A portal, spell, pickup or encounter occurs. | Trigger it. | Show separate spatial effects: portal glow/transition, a ground ring and rising spell sparks, pickup disappearance/glow, and a red/impact hit reaction with a visible monster manifestation. | No identical generic flash for every event or invisible effects represented only by counters. | Effects identify the affected character/object without obscuring the whole scene. | Temporary effects end; surviving room lights and portal ambience continue. |
| VISUAL-06 | Main menu or result screen is displayed. | Hover and activate a button. | Use a dark background, large light gothic title, vertically organized stone-grey beveled buttons and clear hover/pressed states. Display BoneMaze as the title. | No engine debug screen or default starter health screen left as the final interface. | Polished menu/result composition consistent with dungeon art. | Result controls remain distinct from decorative title elements. |
| AUDIO-01 | Exploration begins or resumes. | Play, pause, restart or leave the run. | Play the supplied background music as a continuous loop at a level below important cues. Pause/resume coherently and keep a single music instance across Restart. | No stacking music tracks or silent gameplay when audio is enabled. | Audible musical atmosphere. | Main Menu and application exit stop gameplay music cleanly. |
| AUDIO-02 | Cast, coin, key, heart, scroll, gate, passage, nearby warning, hit, victory or defeat occurs. | Trigger each event normally. | Use distinct supplied event sounds at the corresponding event; a rejected action does not play its success sound. | No persistent repeated one-shot cue or unrelated cue assignment. | The action is audibly identifiable. | Repeated overlap and in-flight cancellation do not multiply one-shot rewards/sounds. |
| ASSET-01 | The character is assembled. | Render its required states. | Use the supplied mage mesh, its material/texture dependencies and the required idle, run, spawn, default-attack, blast, hit and die animation clips identified in Section 11. Use default-attack as the casting gesture and blast for the escape flourish; no combat system is implied. | No substituted mannequin, generated character, flat sprite or newly drawn stand-in. | The specified mage and animations are recognizable in play. | Retargeting, blending and presentation adjustments are allowed; gameplay event bindings are implemented independently. |
| ASSET-02 | Rooms and gates are assembled. | Explore each role and ordinary-room variant. | Use the mandatory stone floor, wall, doorway, door leaf, pillar, coffin, skull and torch models in Section 11, and additional supplied environment pieces for MAZE-05. | No primitive geometry substituted for the principal dungeon architecture. | Recognizable low-poly stone surfaces and prop silhouettes. | Placement, collision, material instances and lighting may be changed while retaining mesh identity. |
| ASSET-03 | Pickups and coloured gates are rendered. | Approach/collect them. | Use the supplied key, coin and heart meshes, supplied pickup colour materials, and scroll icon on a visible pickup presentation for scrolls. | No text-only pickup markers or mismatched key colours. | Gold coin, red heart, coloured keys and distinct scroll silhouette. | A scroll may use a textured billboard; mandatory 3D key/coin/heart silhouettes remain. |
| ASSET-04 | HUD and buttons are assembled. | Play and interact. | Use the supplied heart, scroll, coin, monster, coloured key active/inactive icons and three button-state textures mapped in Section 11. | No generic engine icons or emoji replacing the required icon set. | Consistent illustrated HUD and stone-grey button states. | Scaling/cropping is permitted without changing icon meaning. |
| ASSET-05 | Effects and monster presentation are assembled. | Cast, transition or encounter the monster. | Use the supplied ghost smoke, magic circle, heal aura, lightning particle material collections and retro postprocess material for their mapped visible roles. Present the monster as a shadowy magical presence using the supplied Magic pickup material and spectral effects. | No preassembled gameplay Blueprint imported as an implementation. | Cyan spectral flame, magical geometry and a brief spectral threat during an encounter. | Emitters and material parameters may be edited; the supplied raw textures/meshes remain the visual basis. A simple volume may carry the spectral monster material. |
| ASSET-06 | Audio is integrated. | Play the game. | Use the supplied music and event SoundWave assets with the mapping in Section 11. | No silent placeholders or replacement tone generator for these cues. | AUDIO-01 and AUDIO-02 are audible. | Mix, attenuation, timing and looping configuration are free. |
| ASSET-07 | Typography is integrated. | View the menu and HUD. | Use supplied UnifrakturCook title and Grenze Gotisch main fonts in their mapped roles. | No unreadable decorative body text or replacement system-font-only presentation. | Gothic title and readable matching interface typography. | An additional font may serve accessibility/small diagnostic text; required title/HUD roles remain. |
| OBSERVATION-01 | The application is running. | Read the published observation without changing gameplay. | Publish truthful read-only state under the supplied observation contract, covering phase, round identity, live resources, maze connections, monster position, room/gate/pickup states and visible interaction targets. | No input commands, setters, fixture loaders, outcome shortcuts or fabricated success fields in that surface. | Player UI continues to reflect the same live state; hidden observation values do not appear in the gameplay HUD. | Implementations may choose their own classes, scene structure and algorithms. The unfinished starter reports not_ready only. |

### 6.3 Shared quality requirements

| ID | Requirement |
| --- | --- |
| QUALITY-01 | The project starts, runs, exits and starts again using the public instructions. |
| QUALITY-02 | The main flow uses normal player input, without answer buttons, cheats or direct outcome shortcuts. |
| QUALITY-03 | Essential entries, text and controls are visible, discoverable, understandable and operable. |
| QUALITY-04 | Player input produces perceptible feedback consistent with the actual game state. |
| QUALITY-05 | No severe error blocks the main flow. |
| QUALITY-06 | Repeated runs from identical initial conditions are substantially stable. |

### 6.4 Boundary clauses of the numbered requirements

Each Owner below refers to a numbered requirement, including its action,
feedback and forbidden-result columns. These tables specify externally observable
behavior. They do not select classes, graphs, engine nodes, data structures or algorithms.

#### 6.4.1 Terms, clocks and input

| Owner | Boundary | Required player-visible result |
| --- | --- | --- |
| `PORTAL-02`, `MONSTER-05`, `UI-01` | Settled state | Settled means that the destination/return scene, room coordinates, encounter result and resource changes agree, and normal exploration is available. A recovering or paused mage is not settled for a new passage or final-portal activation. A normal cast or an opening gate does not by itself suspend exploration. |
| `PORTAL-02`, `MONSTER-05`, `SPELL-02`, `DOOR-03`, `RESET-03` | Time units | Seconds are elapsed unpaused gameplay time at normal speed. Pause freezes passage, recovery, gate, reveal and gameplay-effect timers, including gates in other rooms. Crossing lasts at most 1 second from its accepted threshold crossing to arrival/encounter resolution; a nonfatal hit then has its separate recovery budget of at most 2 seconds from damage to restored control. Gate opening lasts 3 seconds from accepted E to passability; reveal lasts 3 seconds from accepted Q unless cleared earlier. |
| `DOOR-03`, `SPELL-02`, `UI-01`, `OBSERVATION-01` | Timing precision | A duration boundary may be presented on the first rendered frame at or after its due time. Observation sampling may add at most one publication interval (0.1 second) to a measurement; that allowance is not an extra gameplay delay. Counts, ownership, room links and event multiplicity have no numerical tolerance. UI updates by the next rendered frame after the relevant transaction is settled. |
| `MOVE-01`, `SPELL-01`, `DOOR-01`, `RESET-01` | Press versus hold | W/A/S/D are held directions. Q, E, R and Escape act on a fresh press, not operating-system key repeat. Releasing and pressing again is a new action. Held Q/E/R across a phase change does not create another press. Pointer activation requires a completed click on an enabled visible control; holding the pointer button is not repeated activation. |
| `MOVE-01`, `SPELL-03`, `PORTAL-02`, `RESET-03` | Input availability | Exploration accepts movement, Q and E. Transition and recovery suppress movement, Q, E, pickups and final-portal activation. Held movement may resume after control returns, subject to passage re-entry protection. Suppressed Q/E presses never execute later. Paused/menu/result screens accept only their enabled interface controls, R where a round exists, and Escape as specified by RESET-03. Text entry receives characters without triggering gameplay. |
| `RESET-01`, `RESET-02`, `RESET-03`, `LIFE-01` | Simultaneous lifecycle input | For actions becoming eligible together, leaving/discarding the round takes priority over its pending gameplay consequences. Main Menu takes priority over Restart if both controls activate together; Restart takes priority over pause/resume. Pause preserves the last coherent round state and suspends an in-progress crossing/recovery without completing or cancelling it. Resuming continues that state; it cannot skip a pending encounter. |
| `MONSTER-04`, `PICKUP-02`, `SPELL-01`, `DOOR-01`, `EXIT-02` | Simultaneous gameplay | A newly accepted passage crossing takes priority over local Q/E/pickup/exit actions at that boundary. Resolve its encounter before destination pickups or exit activation. Any hit cancels all destination pickups/exit activation from that arrival, even if the hit is nonfatal. Without a crossing/hit, simultaneous local pickups settle before Q/E and final-portal checks; a just-collected key or scroll is therefore available. Q and E can both succeed if each is eligible. There is no arbitrary delay that changes these priorities. |
| `QUALITY-03`, `RESET-03`, `MOVE-01` | Focus and suspended input | Losing client focus releases controlled held movement and prevents gameplay from consuming typing/clicks in another application. A focus-loss pause is permitted if visibly identified and governed by RESET-03. Focus return does not synthesize Q/E/R or an interface click. Any key still physically held may resume movement only when exploration is active. |

#### 6.4.2 Entry, seeds and maze content

| Owner | Boundary | Required player-visible result |
| --- | --- | --- |
| `ENTRY-01`, `UI-03` | Menu actions | Easy, Medium, Hard and Exit are the four required menu buttons. Seed entry and control help may be additional controls; no separate mandatory Start button is needed. One difficulty click accepts the displayed valid seed and starts one run. Further difficulty clicks during startup do not create additional rounds or replace the accepted selection. Exit requests normal application closure. |
| `MAZE-04`, `ENTRY-01` | Seed syntax and precedence | A seed is an unsigned base-10 integer from 0 through 4294967295, inclusive; leading/trailing whitespace and leading zeroes are accepted. Empty, signed, fractional, hexadecimal, nonnumeric and out-of-range values are invalid. A valid launch seed initializes the menu field; otherwise its initial value is 48. Editing the field overrides that value for the next difficulty selection, not an active run. |
| `MAZE-04`, `UI-03` | Invalid seed | Invalid menu text remains editable, visibly identifies the valid range, and prevents a difficulty selection from starting a run. An invalid launch argument produces a visible menu warning and initializes the field to 48; it never silently clamps/wraps the value or starts gameplay. If the launch argument occurs more than once, the last supplied value is used and validated. |
| `MAZE-04`, `RESET-01`, `RESET-03`, `RESET-04` | Seed lifetime | Restart uses the active run's seed/difficulty, independent of any earlier menu edit. Main Menu retains that run's seed as editable text but retains no run progress. Reopening initializes from the new launch arguments/default again. There is no persistent seed preference or resumed dungeon. |
| `MAZE-04`, `QUALITY-06` | Repeatability scope | In one implementation, the same seed/difficulty reproduces room links, roles, gate assignments, arrangements, initial collectible positions and initial monster placement. The same sequence of completed room crossings and encounter recoveries reproduces monster choices. Waiting, Q, E, observation reads, decorative motion and frame rate do not alter that sequence. Different elapsed waits may change a reveal timer, not future monster decisions. Generation varies across seeds; distinct seeds need not all produce unique dungeons or match another implementation. |
| `MAZE-01`, `MAZE-02` | Connection identity | The maze has exactly 36/100/225 unique coordinate pairs. Each room has exactly four exit slots and four different neighbours; one connection uses one slot at each end. Following either end returns through the paired opposite end, irrespective of compass labels. A non-geometric link spans more than one orthogonal coordinate step (the total absolute change in the two coordinates exceeds one). No screen direction or coordinate-based adjacency rule is implied. |
| `MAZE-03`, `KEY-01`, `EXIT-01` | Roles and locks | Exactly one start room, one exit room and one room for each of the three key colours exist, all distinct; other rooms are ordinary. Exactly one pickup of each key colour exists in its matching key room. A connection is either ungated or has one shared gate colour/state on both sides; at least one gate of each colour exists. An ungated or fully open connection is traversable in either direction. |
| `MAZE-03`, `MAZE-05` | Reachability meaning | Starting without keys, there is a physically traversable sequence that collects all keys using only keys already acquired to open gates. With all keys acquired, every room, mandatory exit and remaining collectible is reachable. This is a layout/lock condition, not a promise of survival against every random encounter. Gates may have alternate routes; a prescribed key order or a mandatory use of every gate is not required. |
| `MAZE-05` | Counting arrangements | At least 20 ordinary arrangements exist, and all appear in each generated dungeon, including Easy's 31 ordinary rooms. Start, exit and the three key arrangements are additional and do not count toward 20. Count differences in the placement/shape of architecture and substantial props; colour, lighting, collectible positions or rotations of an otherwise identical room alone do not make a new ordinary arrangement. Reusing a distinct arrangement in multiple rooms is allowed. |
| `PICKUP-01` | Content minima | The minimum ordinary-room totals are Easy: 60 coins, 5 scrolls, 3 hearts; Medium: 167 coins, 14 scrolls, 9 hearts; Hard: 375 coins, 32 scrolls, 19 hearts. These are upward-rounded room-count scaling of the Easy minima. At least 12 ordinary rooms each contain at least one of these resources; every resource type need not occupy 12 rooms. More resources are allowed. Keys are separate from these totals. |
| `ENTRY-02`, `MONSTER-05`, `PICKUP-01` | Safe placement | Fresh spawn and recovery land on walkable floor, outside passage/final-portal triggers, gates, solid props and collectible overlap. They grant no incidental pickup or crossing. All collectible interaction areas are physically accessible. Adjacent pickups may overlap a moving mage together, but each is a distinct visible item with one reward. Their number is not multiplied by particle copies or decorative meshes. |

#### 6.4.3 Movement, crossings and encounters

| Owner | Boundary | Required player-visible result |
| --- | --- | --- |
| `MOVE-01`, `MOVE-02`, `MOVE-03` | Movement measurements | Compare axial and diagonal travel on the same unobstructed floor at settled speed; diagonal speed differs by no more than 2 percent. Opposite keys cancel on their axis and the other axis may still move. Releasing all movement keys stops intentional translation by the next rendered frame. Animation blending and camera easing may continue, but may not move the mage through an obstacle or trigger a passage. Exact speed, camera offset and room scale remain artistic choices consistent with readability. |
| `PORTAL-01`, `PORTAL-02` | Arrival and re-entry | A crossing requires movement from inside the current room across an open exit's threshold. Being placed near/on the paired arrival threshold cannot trigger a return. The mage must first clear that arrival threshold toward the room interior before crossing it again. The destination is the linked room, not a newly generated substitute. Holding a direction across arrival does not bypass this protection. |
| `PORTAL-02`, `MONSTER-02`, `MONSTER-04` | A crossing's turn | Every completed crossing increments room_changes once and resolves one encounter/monster turn. Direct entry into the occupied room is that turn's encounter and performs zero ordinary monster steps; other completed crossings perform exactly one ordinary monster step, followed by the encounter check. Recovery relocation is not an ordinary step or another turn. A blocked/cancelled crossing increments neither count. |
| `MONSTER-01`, `MONSTER-03`, `MONSTER-05`, `MONSTER-06` | Distance and gates | Monster distance means the minimum number of maze connections, ignoring gate locks and visual/world-coordinate distance. The starting/recovery separation of at least two connections is measured from the mage's start room after placement. Nearby means distance exactly one. Doors cannot trap or protect the player from a monster turn; the monster uses the same stable room connections. |
| `MONSTER-03`, `MAZE-04` | Probability meaning | On each non-direct-entry turn the pursuit branch has probability 6/11 and wandering 5/11. Wandering chooses uniformly among the four neighbours, including a neighbour that also shortens the route. Therefore observing a shortening step does not identify which branch was selected. A finite run is not required to contain an exact 6:5 count. Any tie choice among shortest-route neighbours is allowed if repeatable for the same seeded action history. |
| `MONSTER-04`, `MONSTER-05`, `LIFE-01` | Encounter priority example | With 1 life, an encounter on arrival causes defeat even when a heart or the 50th coin overlaps the arrival position. With more lives, it causes exactly one lost life and recovery; those overlapping items remain available in that room. No arrival resource, key or exit reward settles before that encounter. Rewards already completed before the crossing remain owned. |
| `MONSTER-05`, `PORTAL-03`, `DOOR-03` | Recovery retention | A nonfatal hit preserves all previously completed pickup/door changes and the maze. An already opening gate continues on the unpaused gameplay clock; recovery neither resets nor instantly completes it. Place the monster at least two connections from start if its existing room violates that separation; otherwise leave its room unchanged. The relocation choice is seeded/repeatable but no particular destination is prescribed. |
| `MONSTER-06`, `UI-02`, `AUDIO-02` | Warning transitions | Recompute nearby status after a completed turn, recovery or new run. Emit one warning cue on a safe-to-nearby change, not on every frame or every continued-nearby turn. Casting or ending a reveal does not itself generate a new nearby warning. A hidden distant monster has no world presence in the current room; encounter manifestation does not create a second roaming monster. |

#### 6.4.4 Local actions, gates and resources

| Owner | Boundary | Required player-visible result |
| --- | --- | --- |
| `SPELL-01`, `SPELL-02`, `SPELL-03` | Casting availability | Every distinct eligible Q press consumes one scroll immediately; there is no additional cooldown or requirement to wait for the previous casting animation to finish. An ongoing cast does not prohibit movement or E. A second successful cast refreshes the sampled coordinates and the 3-second duration. At zero scrolls, no effect/coordinates are granted and a brief No scrolls message appears. |
| `SPELL-02`, `RESET-03`, `UI-02` | Reveal clearing | The reveal shows the monster cell sampled on the accepted cast. It clears at expiry, an accepted room crossing, a hit/recovery, Restart, menu return or either result. A blocked doorway attempt does not clear it. Pause hides it under the pause presentation if desired but preserves its remaining duration; Resume restores it. A reveal reaching zero and a new eligible Q press together leave only the newly refreshed reveal. |
| `DOOR-01`, `DOOR-02`, `DOOR-03` | Range definition | One body width is the mage torso's horizontal width in its neutral upright pose, excluding the book, flame and loose extremities. Gate distance is horizontal floor distance from the mage's feet centre to the nearest point of the gate leaf's closed-position footprint. Within 1.5 widths includes the boundary. The gate must be visibly identifiable and reachable without a solid intervening wall/prop. This measurement does not prescribe a collision component or actor origin. |
| `DOOR-01`, `DOOR-04` | Eligible target | Closed gates, whether locked or key-owned, are eligible; opening/open gates are not a new E target. Select the nearest eligible visible gate in range, with repeatable tie handling. The prompt identifies that same gate and disappears outside range or when it opens. A held E never opens a second nearby gate. E with no gate has no resource/turn effect; at an overlapping locked final portal it may repeat its missing-key feedback. |
| `DOOR-02`, `DOOR-03`, `DOOR-04` | Gate lifetime | A key only permits opening; acquiring it does not automatically open its gates. One accepted E starts the 3-second animation and sound. The passage remains blocked until full opening. Walking away, leaving through another exit or taking a nonfatal hit does not cancel opening. Both ends share the same progress/open state; loading either end neither restarts the timer nor plays a second opening sound. Pause freezes it, a result freezes gameplay progress, and Restart restores closed gates. |
| `KEY-01`, `PICKUP-02`, `PICKUP-03`, `PICKUP-04` | Pickup timing | Outside transition/recovery/pause/results, touching an available item grants its reward once without E. Only items in the current room can be collected. Several distinct items touched together each grant their reward once unless cancelled by the encounter/lifecycle priority. Consumed items remain absent on revisit. At 5 or more lives/scrolls, hearts/scrolls still grant exactly one. Neither resource has a gameplay cap. |
| `ECON-01`, `ECON-02` | Coin transaction | Each collected coin adds one; every complete group of 50 then grants one life, with remainder in 0..49 in the settled state. At 49 coins and 5 lives, collecting one coin yields 0 coins and 6 lives. Several simultaneous coins may grant several lives and retain their remainder; pickup order does not change the settled totals. The coin and extra-life cues correspond to their actual events. |
| `SPELL-03`, `DOOR-02`, `EXIT-01`, `UI-03` | Rejection feedback | Missing-scroll/key messages remain readable for at least 1 unpaused second unless replaced by a newer relevant message or cleared by a lifecycle change. Repeated distinct rejected presses may refresh the message, but cannot change resources, animate a success, produce a monster turn or queue a later action. Missing key colours are named explicitly; a final-portal rejection lists all missing colours. |

#### 6.4.5 Exit, pause, restart and end states

| Owner | Boundary | Required player-visible result |
| --- | --- | --- |
| `EXIT-01`, `EXIT-02` | Final portal entry | The final portal is a separate recognizable destination inside its room, distinct from its four passage thresholds. Arrival through a room passage is not itself victory, and E never activates victory. Without all keys, crossing the final portal's visible interaction boundary leaves the mage in the room and reports missing colours. With all keys, a fresh movement entry while settled produces victory once. Acquiring a key while already overlapping an inactive portal requires leaving/re-entering before victory. |
| `MONSTER-04`, `MONSTER-05`, `EXIT-02` | Exit versus encounter | Any encounter during entry into the exit room resolves before exit activation. A fatal hit loses; a nonfatal hit returns to start and cannot also win. Only a subsequent encounter-free settled visit and fresh movement into the final portal can win. |
| `LIFE-01`, `LIFE-02`, `VISUAL-04`, `VISUAL-05` | Terminal effects | The decisive event fixes the outcome and resources once. A one-shot death/escape pose, win/lose sound and presentation particles may finish in the result state, then end without generating gameplay changes. This visual completion is allowed even though gameplay time and unfinished gate/reveal/room activity are frozen. Movement/Q/E and automatic overlaps cannot change the outcome. |
| `RESET-03`, `LIFE-02` | Pause from each phase | Escape toggles pause during exploration, crossing and recovery; Resume returns to the exact interrupted phase and remaining timers. R or Restart is available while paused. On a result screen, Escape has no effect and there is no Resume-to-exploration action. In the main menu Escape does not start a round or substitute for Exit. |
| `RESET-01`, `RESET-02` | Restart concurrency | R works whenever a round exists, including transition, recovery, pause and results. One request accepted while a reset is already pending is coalesced into that reset; it does not create extra settled rounds. Once a fresh round has settled, a fresh R press legitimately restarts again. No old input press, timer, damage, reward, sound loop, target or effect can act on the new round. |
| `RESET-02`, `RESET-03`, `RESET-04` | Menu and close | Main Menu discards all run state, stops run sounds/effects and removes world interaction targets. Starting again from that menu uses fresh inventory and a new round identity even for the same seed. Normal application close is allowed from every phase and leaves no restored progress on Reopen. A new session cannot treat a former process's observation as its own. |

#### 6.4.6 Presentation and feedback boundaries

| Owner | Boundary | Required player-visible result |
| --- | --- | --- |
| `UI-01`, `UI-02`, `ASSET-04` | HUD meanings | Resource counters show settled nonnegative integers; coins show their remainder. Show all three key icons at all times during exploration, using inactive/active artwork for ownership. MonsterGreen means safe, MonsterYellow means nearby and MonsterRed accompanies an active exact-coordinate reveal. If nearby and revealed overlap, keep a separate visible nearby label/indicator alongside the red reveal. Clearing the reveal restores the correct green/yellow state, never stale coordinates. |
| `UI-01`, `UI-03`, `MOVE-03`, `VISUAL-02` | Legibility and framing | At both 1280x720 and 1920x1080, the whole HUD/control area stays inside the client without overlapping essential labels. Camera tracking may crop distant decorative architecture, but current exits and required objects become visibly approachable using normal movement. Occluding architecture may fade/cut away. Darkness, foreground props and effects may not hide the mage or make a required interaction indistinguishable. |
| `VISUAL-01`, `VISUAL-03`, `VISUAL-06` | Visual freedom | The reference images guide composition, palette, material appearance and effect identity, not exact pixels, room coordinates, object counts or camera transforms. Keep comparable retro world-image scale across both output sizes and sharp readable UI. Exact pixel-grid size, light intensity, camera distance and decorative placement remain free if the numbered visual outcomes hold. Menu/result titles and buttons use the specified gothic/stone styling and English wording. |
| `VISUAL-04`, `ASSET-01` | Animation roles | Use Spawn on fresh entry, Idle_Loop while idle, Run_Loop while moving, Default_Attack for a successful reveal, Hit_Front for a nonfatal hit, Die for a fatal hit and Blast for escape. These gestures do not add attacks or change damage/resource rules. Locomotion resumes coherently after a nonterminal gesture; death/escape may hold a final pose under the result overlay instead of returning to idle. |
| `VISUAL-05`, `ASSET-05` | Effects | Required effects are spatially associated with their event and visibly distinct. Particle loops belonging to room ambience may continue while that room is shown during unpaused live play; transient spell/transfer/hit/pickup effects end. Restart/menu return removes effects of the discarded round. An effect's visible duration does not extend control lock, a reveal, damage or a reward beyond its gameplay rule. |
| `AUDIO-01`, `AUDIO-02` | Sound lifecycle | Gameplay music loops once while exploring, crossing or recovering. Pause suspends it and Resume continues it; Restart keeps one instance, not a stack. A result may retain that single background instance beneath its one-shot cue. Main Menu and close stop it. Restart cancels pending old cues and stops old one-shots; the single continuing music instance is the exception. A new menu-started run begins one instance. No particular loudness number is required, but cues remain discernible and the music does not mask them. |
| `AUDIO-02`, `ASSET-06` | One-shot meanings | A_CastMagic, A_Coin, A_GetKey, A_IncreaseLives, A_TakeMagic, A_OpenDoor, A_Teleport, A_Monster, A_Bonk, A_Win and A_Lose map respectively to cast, coin, key, heart/extra life, scroll, opening start, completed passage, entry into nearby danger, hit, win and defeat. A completed encounter-producing passage may have both transfer and hit cues. A fatal hit may have hit and lose cues. They represent different events, not duplicate rewards. |

#### 6.4.7 Required assets and editable files

| Owner | Boundary | Required delivery result |
| --- | --- | --- |
| `ASSET-01`, `ASSET-02`, `ASSET-03`, `ASSET-04`, `ASSET-05`, `ASSET-06`, `ASSET-07` | Identity and paths | The catalog's required=true entries include mandatory role assets and their necessary dependencies. Keep those package and object paths in the final project. Supplied hashes/sizes describe the starting snapshot and are not a ban on the permitted edits. Do not move, rename, replace with unrelated content, or delete a required entry. Optional assets may be removed/reorganized only while required dependencies remain valid. |
| `ASSET-01`, `ASSET-02`, `ASSET-05` | Permitted editing | In-place resaving, collision adjustments, material parameters, material instances, emitters, animation retargeting/blending and presentation adjustments are permitted within each asset row. The mandatory mesh silhouette, clip identity, raw texture basis and mapped visual roles remain recognizable. New authored presentation assets may supplement them. A redirector or unused retained file does not satisfy visible use. |
| `ASSET-01`, `ASSET-02`, `ASSET-03`, `ASSET-04`, `ASSET-05`, `ASSET-06`, `ASSET-07` | Use versus storage | Each required role asset is actually used in its assigned reachable scene/event; merely shipping its file is insufficient. Environment role assets appear in the generated room set, not necessarily every room. Dependencies need not be separately displayed as objects, but must support the intended asset. Required title/HUD fonts remain in those roles; the scroll billboard allowance does not permit flat substitutes for mandatory 3D character/key/coin/heart meshes. |
| `ASSET-04`, `VISUAL-06` | Button states | Use the supplied normal/hover/pressed textures for those states. A disabled button may use a visibly dimmed normal texture and must not activate. A visible texture does not replace a working control. |
| `QUALITY-01`, `OBSERVATION-01` | Project changes | Deliver through starter-project/BoneMaze.uproject and the BoneMazeEditor target on the stated engine. Descriptor contents, the normal default map, modules and newly authored files may change as needed; no gameplay class names are prescribed. Keep supplied documents/contracts/tools/references/catalogs/manifests outside starter-project/ unchanged during implementation. Place additional asset notices in starter-project/. |

#### 6.4.8 Observation and acceptance boundaries

| Owner | Boundary | Required observable result |
| --- | --- | --- |
| `OBSERVATION-01` | Truth and publication | Publish one coherent complete JSON document on a nominal 0.1-real-second interval while the runtime is responsive, including pause/menu/results. Scheduling may defer a due publication to the next rendered frame, but no extra intentional delay is allowed. The document, visible state and process/session identity agree. Formatting is free: compact or indented UTF-8, LF/CRLF, optional final newline and optional UTF-8 BOM. Partial JSON and multiple concatenated/JSON-Lines documents are not snapshots. Reading never changes gameplay or randomness. |
| `OBSERVATION-01` | State coverage | Follow the supplied semantic contract for every room/connection, gate, pickup, mage, monster, portal and active important effect, including hidden/consumed objects. Report actual current targets and phase. Non-player-visible monster/maze information remains confined to read-only observations. Menu has no active run entities; Restart uses fresh round/entity identities. No success verdict, hidden gameplay setter or test-only outcome action belongs to this interface. |
| `QUALITY-01`, `QUALITY-06`, `OBSERVATION-01` | Checks and freedom | Public package/format/health checks do not certify gameplay or artistic correctness. A check cannot require a private room arrangement, exact seed outcome, internal class, algorithm, hidden input or pixel-perfect match. Comparisons use the public rules and permitted tolerances. Unspecified decorative choices are free; they cannot override a specified resource value, interaction boundary or lifecycle outcome. |

## 7. Success, failure and stages

### 7.1 Success

Collect all keys and physically enter the final portal (KEY-01, EXIT-01, EXIT-02).
The stable result and next actions follow LIFE-02 and RESET-01 through RESET-03.

### 7.2 Failure

A monster encounter costs one life (MONSTER-04). Remaining lives allow recovery
(MONSTER-05); zero lives show defeat (LIFE-01). Terminal input is bounded by LIFE-02.

### 7.3 Stages

| Stage | Outcome | No premature progression |
| --- | --- | --- |
| Explore | MAZE-01 through MAZE-05, PORTAL-01 | DOOR-02, EXIT-01 |
| Acquire keys and open gates | KEY-01, DOOR-03, DOOR-04 | EXIT-01 |
| Reach exit | EXIT-02 | LIFE-01, LIFE-02 |

## 8. Interface and feedback summary

| Information | Requirements |
| --- | --- |
| Lives, scrolls, coins, chamber and keys | UI-01 |
| Danger versus temporary exact reveal | MONSTER-06, SPELL-02, UI-02 |
| Interaction and missing-key/scroll feedback | DOOR-01, DOOR-02, SPELL-03, EXIT-01 |
| English instructions, seed and difficulty | UI-03, MAZE-04 |
| World, lighting, pixel treatment, animation and effects | VISUAL-01 through VISUAL-05 |
| Menu and result presentation | VISUAL-06, EXIT-02, LIFE-01 |
| Music and one-shot event feedback | AUDIO-01, AUDIO-02 |

## 9. Restart, reopening and persistence summary

| Situation | Reset / retention | Requirements |
| --- | --- | --- |
| Nonfatal hit | Retain inventory and world progress, recover to start | MONSTER-05 |
| Room revisit | Retain room/gate/pickup state | PORTAL-03, DOOR-04, PICKUP-02 |
| Restart | Fresh seeded run; no old activity survives | RESET-01, RESET-02 |
| Pause/resume | Keep the same run; freeze/resume timers | RESET-03 |
| Menu return | Discard current run | RESET-02, RESET-03 |
| Close/reopen | Main menu with no saved progress | RESET-04 |

## 10. Supplied starter behavior

Not applicable. The starter contains no completed gameplay. The public health probe
may be removed when the game is implemented; OBSERVATION-01 describes the final transport.

## 11. Required assets and content summary

Every required role below is defined by ASSET-01 through ASSET-07. Paths are relative
to starter-project/Content/; the catalog provides individual object paths and dependencies.
The required role map is exact; supplementary library pieces are available for decoration.
Path retention, replacement limits and permitted adjustments are defined in the matching
numbered rows and their Section 6.4.7 clauses. Hashes identify the starting snapshot only.

| Requirement | Required asset / path | In-game role |
| --- | --- | --- |
| ASSET-01 | PlayerCharacter/Character/SK_PlayerCharacter.uasset and its skeleton/material/texture dependencies | Mage body, skull, robe and book |
| ASSET-01 | PlayerCharacter/Animations/A_PlayerCharacter_{Idle_Loop,Run_Loop,Spawn,Default_Attack,Blast,Hit_Front,Die}.uasset (each listed clip) | Idle, movement, spawn, casting, escape flourish, hit and death |
| ASSET-02 | SimpleDungeons/Meshes/Environment/SM_Env_{Floor_Stone_01,Wall_01,Doorway_01,Pillar_Stone_01}.uasset | Principal room architecture |
| ASSET-02 | SimpleDungeons/Meshes/Environment/EnvParts/SM_Env_Door_Main_03.uasset | Opening gate leaf |
| ASSET-02 | SimpleDungeons/Meshes/Props/SM_Prop_{Stone_Coffin_01,Skull_01,Torch_01}.uasset | Required room dressing |
| ASSET-03 | Pickups/Assets/SM_{Key,Coin,Heart}.uasset and Effects/GhostEffect/MI_Pickups_{KeyRed,KeyGreen,KeyBlue,Coin,Magic}.uasset | Physical collectibles and colour identity |
| ASSET-03, ASSET-04 | UserInterface/HUD/Textures/AttemptsIcon.uasset | Scroll pickup presentation and scroll counter |
| ASSET-04 | UserInterface/HUD/Textures/{HeartImage_UI,CoinIcon,MonsterGreen,MonsterYellow,MonsterRed,KeyRedActive,KeyRedInactive,KeyGreenActive,KeyGreenInactive,KeyBlueActive,KeyBlueInactive}.uasset | HUD resource/danger/key states |
| ASSET-04 | UserInterface/Buttons/T_Button_{Normal,Hover,Pressed}.uasset | Button states |
| ASSET-05 | Effects/GhostEffect/FX_GhostSmoke.uasset | Spectral flame/smoke presentation |
| ASSET-05 | FXVarietyPack/Particles/{P_ky_magicCircle1,P_ky_healAura,P_ky_lightning1,P_ky_lightning2}.uasset and their dependencies | Portal/ring, cast aura and impact/lightning presentation |
| ASSET-05 | Effects/M_PS1_PostProcess_Inst.uasset and its material/function/collection dependencies | Retro world treatment |
| ASSET-05 | Effects/GhostEffect/MI_Pickups_Magic.uasset and its dependencies | Spectral monster manifestation |
| ASSET-06 | Sounds/A_Music.uasset | Gameplay music |
| ASSET-06 | Sounds/A_{CastMagic,Coin,GetKey,IncreaseLives,TakeMagic,OpenDoor,Teleport,Monster,Bonk,Win,Lose}.uasset | Cast, coin, key, heart/extra-life, scroll, door, transfer, warning, hit, win and defeat |
| ASSET-07 | UserInterface/Fonts/Font_Logo_Font.uasset and Font_Logo.uasset | UnifrakturCook title typography |
| ASSET-07 | UserInterface/Fonts/Font_Main_Font.uasset and Font_Main.uasset | Grenze Gotisch interface typography |

The asset catalog expands brace lists into separate exact file entries. The visual
guide in reference/tools/INPUT_GUIDE.md summarizes VISUAL-01 through VISUAL-06 and UI-01;
it does not introduce extra acceptance conditions.

## 12. Implementation freedom

Code/Blueprint organization, classes, algorithms, room construction, collision details,
UI technology and animation blending are implementation choices. Mesh placement,
material instances and artistic refinements remain free within the numbered visual
and required-asset constraints. There is no prescribed internal architecture or maze
generation algorithm. Observations use public meanings, never internal class names.

## 13. Submission self-check

- [ ] Every Section 6 row is implemented or explicitly reported unfinished.
- [ ] All three difficulty sizes and repeatable seed behavior are present.
- [ ] Exploration, encounters, keys/gates, economy, escape and defeat use normal input.
- [ ] Room persistence, in-flight Restart, pause and close/reopen obey their numbered rules.
- [ ] Required art is visibly used; animation, effects, sound and UI are integrated.
- [ ] Observations are fresh, truthful and read-only.
- [ ] Build and normal-player checks were actually run and their results recorded.
- [ ] No generated caches, machine paths or unintended implementation shortcuts are submitted.
