# Captain's Key Run

## 1. One-Sentence Task

Build the supplied single-room captain platformer with movement, sword combat, damage, traps, a key, a spring, the fixed room map and one green pig patrolling the lower-right corridor (`CONTENT-01`, `CONTENT-02`, `ENEMY-01`, `ENEMY-02`).

## 2. Scope

### 2.1 Included Work

| Requirement IDs | Summary |
|---|---|
| `CONTENT-01`, `CONTENT-02` | Reconstruct the fixed supplied room and object composition. |
| `INPUT-01`, `INPUT-02`, `COMBAT-01` | Preserve movement, jumping and source sword actions. |
| `TRAVERSAL-01`, `TRAVERSAL-02` | Recreate the spring and three one-way ledges. |
| `ENEMY-01`, `ENEMY-02` | One green pig patrols the lower-right corridor and fights the nearby captain. |
| `HAZARD-01`, `HAZARD-02` | Preserve health damage, hit reaction, death and retry. |
| `OBJECTIVE-01` through `OBJECTIVE-04`, `TERMINAL-01` | Collect one key, enter the opened exit and hold room completion. |
| `INTERFACE-01`, `LIFECYCLE-01`, `LIFECYCLE-02` | Preserve health/key/death feedback and clean resets. |
| `ASSET-01` through `ASSET-05` | Use the supplied original art and map material. |
| `QUALITY-01` through `QUALITY-06` | Shared playability and stability. |

### 2.2 Excluded Work

No menus, save games, online play, extra abilities, additional enemy types, loot system or audio is requested. The complete game is the single room specified here.

## 3. Starting State

The supplied Unreal Engine source project renders an English health screen. It has no gameplay pawn, imported art, collision layout, controls, enemy, spring, key, exit or gameplay implementation. The implementer must import and process the clean material independently. The read-only bridge starts with `provider_ready=false` and `game_state=null`; it is infrastructure, not a gameplay solution.

The requested game starts on the lower-left floor, with health 100, keys 0/1, deaths 0, a closed upper-left exit and one live pig on the lower-right corridor (`CONTENT-02`, `ENEMY-01`, `HAZARD-01`, `INTERFACE-01`).

## 4. Player Goal and Complete Flow

### 4.1 Player Goal

Obtain the single key and enter the upper-left exit while surviving the supplied room (`OBJECTIVE-01` through `OBJECTIVE-04`).

### 4.2 Complete Player Flow

Start on the lower-left floor -> traverse the divider and lower corridor -> avoid or fight the pig -> use the spring and right-side ledges while avoiding spikes -> obtain the central key -> enter the open upper-left exit -> remain in room completion or restart with R. This describes the room's affordances; it does not require one exact sequence of movements (`CONTENT-01`, `TRAVERSAL-01`, `TRAVERSAL-02`, `ENEMY-01`, `OBJECTIVE-04`).

### 4.3 Core Loop

Move, jump and attack -> read health and key feedback -> continue after nonfatal damage -> retry after death or finish through the unlocked exit (`INPUT-01`, `INPUT-02`, `COMBAT-01`, `HAZARD-01`, `HAZARD-02`, `OBJECTIVE-04`).

## 5. Player Controls

| Action | Input | Requirement IDs |
|---|---|---|
| Move and face left/right | A / D | `INPUT-01` |
| Grounded jump | Space | `INPUT-02` |
| Sword attack | Z | `COMBAT-01` |
| Restart this room | R | `LIFECYCLE-01` |

These keyboard controls are required. Equivalent optional controller bindings may coexist without changing the rules.

## 6. Numbered Requirements: Sole Acceptance Authority

### 6.1 Requirement Splitting Rule

The rows below are the sole gameplay acceptance authority. Each specifies an observable player result. Other sections, asset catalogs and engineering contracts summarize or map these concepts without adding gameplay. The room composition reference and static tile layout are normative visual content under `CONTENT-01` and `ASSET-03`; they contain no gameplay code or prescribed implementation. Source art pixels provide the distance unit below; uniform scaling is allowed.

### 6.2 Task-Specific Requirements

| Requirement ID | Preconditions | Player Action or Trigger | Required Result | Prohibited Result | Player-Visible Feedback | Failure, Repeat, Restart, or Other Boundary |
|---|---|---|---|---|---|---|
| `CONTENT-01` | Fresh launch or restart. | Begin play. | Reconstruct the supplied room art layout, preserving its tile arrangement, wall boundaries, platform widths, gaps, heights, central hollow masonry column, short lower divider, and decoration composition. Use the room composition reference for the environment and object arrangement. Uniform scaling is allowed; the topology and relative placements are fixed. | No redesigned route, added shortcut, rearranged terrain, or flat screenshot standing in for the world. | Readable side-view pixel-art room with the captain, route and objects distinct. | The same room is restored on every retry. |
| `CONTENT-02` | An active fresh attempt. | Observe and traverse the room. | Start the captain on the lower-left floor by the decorative doorway. Place one collectible key in the central open gap, one functional closed exit on the upper-left shelf, one spring at the lower-right end, three alternating one-way ledges in the right shaft, and two fixed spike groups: downward under the upper-right overhang and rightward on the lower-right face of the hollow column. Preserve the positions and orientations shown in the reference. | No missing or additional key, exit, spring, spike group or one-way ledge. Decorative doors, barrels, bottles and chains do not become objectives or movable obstacles. | The silhouettes, positions and facing of the functional objects match the reference. | The captain starts beside the lower-left decorative doorway. The lower-left doorway is decorative. |
| `INPUT-01` | Alive, active, and not executing a sword swing. | Hold A or D; release it. | Move left/right and face that direction; stop intentional movement after release. Preserve the source movement scale: maximum horizontal speed 250 art pixels/second, with responsive acceleration and airborne steering. A uniform scene scale must scale distances and speeds together. | No reversed controls, drift after release, or walking through solid room boundaries. | Idle and run animations change with actual movement and facing. | Movement resumes after attacks and nonfatal hit feedback; repeated input remains responsive. |
| `INPUT-02` | Alive in the active room. | Press Space while grounded; steer while airborne; land. | Perform a grounded jump, rising then falling under gravity, and land on a valid surface. Preserve the source jump height and timing (initial upward speed 370 art pixels/second, gravity 980 art pixels/second squared). Show jump, fall and landing states. | No air jump, flight, ceiling penetration or missed landing through a solid floor. | The captain uses distinct ascent, descent and brief landing art. | A new jump is possible after landing. Holding Space must not grant unlimited ascent. |
| `COMBAT-01` | Alive in the active room. | Press Z, facing a nearby enemy, or swing into empty space. | Play a sword swing in the current facing direction, choosing among the three supplied source swing variants without a fixed combo order. Suppress horizontal walking and additional swing starts while that swing is active; then restore control. A connected strike applies one source damage value, 25 or 45, to the enemy at the visible sword impact. | No damage outside sword reach or through masonry; a miss causes no damage. Repeated input must not stack hits for one swing. | Visible sword motion; a connected hit produces enemy hit feedback. | Successive completed swings work. Swing variation and damage may vary within the stated source choices; no extra attack ability or reward is introduced. |
| `TRAVERSAL-01` | Alive and able to reach the lower-right spring. | Contact the spring from the playable floor. | The spring visibly compresses/extends, then launches the captain upward with the source boost of 500 art pixels/second, replacing downward speed while preserving horizontal steering. The boost makes the right-shaft ascent usable. | No spring damage, teleport, permanent flight, or launch from a distant position. | The supplied spring animation and a visibly higher ascent than an ordinary jump. | The spring returns to its resting state and can be used again after a distinct contact. |
| `TRAVERSAL-02` | Alive near any of the three right-shaft ledges. | Jump upward through a ledge; fall onto its top. | Allow passage upward from below and support a landing from above. Preserve the ledges' source positions, lengths and orientation so the shaft can be climbed. | No solid underside blocking ascent, fall through the supporting top, or moving ledge behavior. | The captain passes through from below, then visibly stands on the ledge. | Repeated landings and departures behave consistently on all three ledges. |
| `ENEMY-01` | An active fresh attempt. | Wait or enter the lower-right corridor. | Exactly one green pig patrols the long ground-floor corridor in the lower-right part of the room, beneath the hollow masonry structure. The corridor extends from the right face of the short lower divider to the inner face of the room's right wall, with the spring at its far-right end. The pig begins on this floor, clear of the captain and spring. It walks back and forth at 50 art pixels/second, turns at either corridor boundary or a blocked edge, and stays on this floor. | No stationary placeholder, extra monster, airborne patrol, escaping onto the divider or ledges, walking through walls, or obstructing use of the spring permanently. | An animated small green pig visibly walks and turns along this corridor. | There is one live monster initially and after retry. Its exact initial horizontal position is free within the corridor, clear of the captain and spring; the illustrated position is representative. No respawn during the same attempt after it is defeated. |
| `ENEMY-02` | The monster is alive with initial health 50. | Approach its attack range, or strike it with Z. | The pig faces and attacks the nearby captain, inflicting 55 health damage for a connected attack; player sword strikes reduce its health by the damage in COMBAT-01. Show its attack, hit and death states. At zero health it dies and ceases collision, patrol and damage. | No unavoidable room-wide damage, damage from a dead monster, duplicate damage from one attack, or progress/loot granted by killing it. | The source pig attack/hit/death animations and matching player health feedback. | Defeating the monster is optional for unlocking the exit; the single key remains the objective. Restore the monster on death/restart. |
| `HAZARD-01` | Captain is alive with health initially 100. | Touch either spike group, or receive a connected monster attack. | Each distinct effective spike contact removes 50 health; monster damage follows ENEMY-02. Nonfatal hits play the source hit reaction, reduce the health bar, and leave the attempt active. Spike contact pushes the captain away from the spikes. | No instant death from a single spike contact at full health, healing on impact, per-frame damage stacking for a single contact, or incrementing deaths on a nonfatal hit. | A visible hit reaction and truthful health decrease. | Both spike groups are fixed hazards. A later distinct contact can damage again; hit handling must not leave permanent invulnerability or a trapped player. |
| `HAZARD-02` | Health reaches zero during an active attempt. | The lethal hit resolves. | Play death feedback once, increment the session death count once, then respawn safely at the lower-left start with health 100, key 0/1, one collectible, a locked exit, the live monster restored, and the spring and ledges restored. | No negative-health play, multiple deaths from one lethal event, stale collected key/open exit, duplicated objects, or old hit/attack effects damaging the new attempt. | Death animation, restored room and full health bar; the new death count stays visible. | Each later lethal event repeats this reset. A nonfatal hit does not reset progress. |
| `OBJECTIVE-01` | The key is present and progress is 0/1. | Overlap the key through normal traversal. | Collect it once, remove it from the world, update progress to 1/1, show the source pickup feedback, and start the exit opening. | No repeated collection, extra progress, or completion just from touching the key. | The key resolves visibly, its HUD count updates, and the exit starts opening. | Revisiting the pickup point has no further effect. |
| `OBJECTIVE-02` | Progress is 0/1 and the exit is closed. | Touch the upper-left exit. | Keep it closed and keep gameplay active with unchanged progress. The closed door and 0/1 display communicate that the key is still needed. | No early completion, invented key, irreversible lockout or trap. | The visibly closed source door remains distinguishable from the open state. | Repeated early attempts remain harmless. Additional locked text is optional. |
| `OBJECTIVE-03` | The key has been collected in this attempt. | Observe the exit, then approach it. | Play the supplied door-opening sequence, leave the exit visibly open and enterable, and keep it open until a reset. | No completion before entering; no invisible opening or blocked open doorway. | The original closed-to-open door presentation. | Nonfatal damage does not relock the exit. |
| `OBJECTIVE-04` | Progress is 1/1 and the exit is open. | Enter the open upper-left exit. | Complete this room once and show a stable completion message containing ROOM CLEARED and an R restart hint. | No map transition, scene-number display, stage selection, or further destination. | A readable completion message over the room. | The resulting terminal state follows TERMINAL-01. |
| `INTERFACE-01` | Active, dying, respawning or completed. | Observe the HUD before and after gameplay changes. | Show the original-style heart health bar, key count out of one, skull death count and an R restart hint. Keep all values synchronized with health, objective progress and session deaths. | No room/stage number, navigation selector, stale values, duplicated HUD, or a bar that stays full after damage. | Pixel-art health/key/skull indicators remain readable during normal play. | Initial health 100, keys 0/1 and deaths 0; reset behavior follows HAZARD-02 and LIFECYCLE-01/02. |
| `LIFECYCLE-01` | The process is active, dying, respawned or completed. | Press R once. | Restart the same room at its clean initial attempt: safe player start, health 100, key 0/1, closed exit, live monster, reset spring and ledges, cleared hit/attack/completion feedback. Preserve the current session death count. | No extra death for a manual restart, duplicated actors/HUD, retained key, missing monster, stuck input or stale pending damage. | The room visibly returns to its initial presentation with full health and preserved deaths. | Consecutive R presses stay stable, including during an attack, spring bounce or death transition. |
| `LIFECYCLE-02` | The old process has been closed. | Launch a new process. | Start a clean active room with all initial objects and health restored, key 0/1 and session deaths 0. | No saved progress, retained death count or terminal state from the previous process. | The same initial room and HUD. | Every true process reopen follows this rule. |
| `TERMINAL-01` | The room has been completed. | Wait or send movement, jump or attack input. | Keep completion and all gameplay values stable; prevent further player/enemy/hazard interactions until R. | No new death, health loss, movement through new gameplay, monster attack, key pickup or repeated completion. | ROOM CLEARED remains visible. | R starts a fresh attempt under LIFECYCLE-01. |
| `ASSET-01` | Supplied captain art is available. | Render idle, run, jump, fall, land, all three sword swings, hit and death. | Use the corresponding supplied source captain-with-sword frames, preserving their silhouettes, colors and pixel scale. | No missing action, substitute character, primitives, redrawn replacement or static sprite for every state. | Original captain animation and facing changes are recognizable. | Import, slicing and animation assembly are implementation work. |
| `ASSET-02` | Supplied objective art is available. | Render the key, pickup feedback and exit closed/opening/open. | Use the supplied original key and door frames in the corresponding states. | No replacement objective icons, missing pickup state or permanently closed-looking unlocked exit. | Objective state changes remain visually clear. | Sprite assembly is free; replacement artwork is not. |
| `ASSET-03` | Supplied map, tiles and world art are available. | Render the room and its traversal objects. | Use the supplied static room tile data and original terrain, back-wall, platform, spike, spring and decoration art. Preserve the room composition shown in the reference, including decorative barrels/bottles, chains, candle and doorway. | No generic redesigned room, missing decor, flattened gameplay screenshot, replacement tiles, or imported source gameplay logic. | Original warm ship-interior pixel art with distinct solid surfaces and dangers. | Build collision, live objects, spring behavior and one-way behavior yourself from the clean material. |
| `ASSET-04` | Supplied green pig art is available. | Render patrol, facing changes, attack, hit and death. | Use the original green pig frames for their matching states, at the source small-monster scale relative to the captain. | No unrelated enemy, primitive placeholder, missing animation or oversized replacement. | The small green pig is visually distinct from the captain. | The same source presentation is restored on restart. |
| `ASSET-05` | Supplied UI art is available. | Render the HUD. | Use the original heart/bar and skull art, and the source key art, for the matching health, death and objective indicators. Preserve their recognizable pixel presentation. | No unrelated icon set, missing required indicator or decorative fake health bar. | The HUD uses the supplied pixel-art indicators and remains readable in the client viewport. | Text layout and font choice may adapt to viewport readability without introducing a scene number. |

### 6.3 Shared Quality Requirements

| Requirement ID | Formal Requirement |
|---|---|
| `QUALITY-01` | The project launches, runs, exits and reopens through the documented entry. |
| `QUALITY-02` | Required gameplay uses normal player input without answer buttons, cheats or direct result calls. |
| `QUALITY-03` | Critical objects, controls, paths, UI and text remain visible, discoverable and operable. |
| `QUALITY-04` | Player actions give perceptible feedback consistent with actual game state. |
| `QUALITY-05` | No severe error blocks the complete player flow. |
| `QUALITY-06` | Repeated runs from the same starting conditions remain stable within the stated source attack variation. |

## 7. Success, Failure, and Objective Flow Summary

### 7.1 Success

Collect the key, observe the door opening, enter it and hold ROOM CLEARED until R (`OBJECTIVE-01` through `OBJECTIVE-04`, `TERMINAL-01`).

### 7.2 Failure

Nonfatal damage reduces health and permits continued play. Zero health causes one death, then restores the room and attempt state while preserving the session death count (`HAZARD-01`, `HAZARD-02`).

### 7.3 Objective Flow

The room changes from key missing / door locked to key collected / door open, then completed. These are objective states within the same room (`OBJECTIVE-01` through `OBJECTIVE-04`).

## 8. Interface and Feedback Summary

Show health, keys, deaths and restart instructions; show source movement, sword, hit, death, spring, enemy and door animation. The play screen contains no scene number (`INTERFACE-01`, `ASSET-01` through `ASSET-05`).

## 9. Restart, Reopen, and Persistence Summary

| Event | Reset | Preserved | Requirement IDs |
|---|---|---|---|
| Nonfatal damage | Hit feedback resolves; play continues | Current room and objective state | `HAZARD-01` |
| Death | Full room attempt, including player health and live pig | Incremented session death count | `HAZARD-02` |
| R | Full room attempt | Current session death count | `LIFECYCLE-01` |
| New process | Entire room and session | Nothing | `LIFECYCLE-02` |

## 10. Existing Features to Preserve

The starter has no gameplay to retain. Section 6 specifies the complete game: captain movement, jumping and sword combat; the patrolling green pig; health, damage and death; the key and door; fixed spikes, one-way ledges and spring; room composition, supplied art and room completion. Implement all of these from the public requirements and clean materials.

## 11. Asset and Content Summary

| Requirement IDs | Public source | Use / replacement boundary |
|---|---|---|
| `CONTENT-01`, `ENEMY-01` | `references/room-reference.png` | Room composition design illustration, including the captain, green pig and traversal objects. Patrol boundaries are specified by the room landmarks in ENEMY-01. The illustration is not runtime evidence or a HUD layout specification. |
| `CONTENT-01`, `ASSET-03` | `assets/files/map/room-layout.json`, `assets/files/map/room-art-preview.png` | Required original static room art data; implement collision and live actors separately. |
| `ASSET-01` | Exact files under `assets/files/treasure-hunters/player/`, enumerated in `assets/ASSET_CATALOG.json` | Required captain idle/run/jump/fall/land/sword/hit/death art; no replacement. |
| `ASSET-02` | Exact files under `assets/files/treasure-hunters/objectives/`, enumerated in `assets/ASSET_CATALOG.json` | Required key/pickup/door art; no replacement. |
| `ASSET-03` | Exact files under `assets/files/treasure-hunters/world/`, enumerated in `assets/ASSET_CATALOG.json` | Required original tiles, platforms, spikes, spring and decor; no replacement. |
| `ASSET-04` | Exact files under `assets/files/treasure-hunters/enemy/`, enumerated in `assets/ASSET_CATALOG.json` | Required green pig art; no replacement. |
| `ASSET-05` | Exact files under `assets/files/treasure-hunters/ui/`, enumerated in `assets/ASSET_CATALOG.json` | Required health/skull UI art, with key art above; no replacement. |

Every file, frame size, timing fact, dependency and hash is individually listed in `assets/ASSET_CATALOG.json` and its readable companion. `assets/files/map/README.md` explains the static data format. These are clean presentation materials: no Unreal map package, imported sprite, flipbook, actor, Blueprint, collision, AI, input mapping or importer is supplied.

## 12. Implementation Freedom

Choose any engine-supported architecture, project organization, asset importer, collision construction, sprite/animation assembly and state handling that satisfies Section 6. The supplied room layout and original art are mandatory; they are not layout-design freedom. UI text placement and camera framing may adapt for readability while preserving a side view and room proportions. The read-only observation contract describes semantic state only and must not write gameplay.

## 13. Pre-Submission Self-Check

Use normal controls to check the fixed room, all player actions, both spike groups, repeated spring use, all three one-way ledges, pig patrol/combat/death, nonfatal and lethal damage, key/door flow, terminal stability, R during transient actions and true process reopen. Verify all original art roles and honest read-only state. Report checks actually performed and any unresolved requirement IDs; do not invent verification results.
