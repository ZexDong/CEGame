# Chomp: Neon Maze Chase

## 1. One-sentence task

Build a complete 3D neon maze-chase game in which a chomping yellow character clears a dense maze, outmaneuvers four distinct ghosts, reverses the hunt with energizers, collects timed fruit, and reaches a win or loss with restart and persistent high score (FLOW-01 through FLOW-04, GHOST-01 through GHOST-09, POWER-01, SAVE-01).

## 2. Scope

### 2.1 Required scope

| Requirements | Summary |
|---|---|
| FLOW-01..04, MAZE-01, MOVE-01..04 | Full maze, continuous steering, buffered turns, reversal, wrap, start and terminal flow |
| DOT-01, POWER-01..02, GHOST-01..09, CAPTURE-01..02 | Pickups, frightened chains, four pursuit personalities, release and return journeys |
| LIFE-01..04, FRUIT-01..02, TIME-01 | Life recovery, extra lives, timed pineapple and coherent timers |
| PAUSE-01..02, MENU-01..02, OPTIONS-01..03, SAVE-01..02 | Complete menu/settings/pause/restart/reopen lifecycle |
| HUD-01, VISUAL-01..06 | Neon 3D presentation, animated character, following camera, effects and consistent menus |
| ASSET-01..05 | Mandatory supplied character, fruit, scene and HUD art with permitted transformations |
| OBSERVE-01, QUALITY-01..06 | Honest observation and general playability |

### 2.2 Excluded scope

| Related requirements | Outside this task |
|---|---|
| FLOW-04 | Extra maze campaigns, online scores, multiplayer and accounts |
| MOVE-01 | Gamepad, touch and mobile support |
| VISUAL-01..06 | Music or a new sound-effects system |
| SAVE-02 | Restoring an unfinished run |

## 3. Starting state

| Item | Supplied state | Related requirements |
|---|---|---|
| Project | New Unreal Engine C++ Blank project; inert welcome view | QUALITY-01 |
| Gameplay | No maze actors, player, enemies, pickups, movement, menu flow or save system | All task-specific requirements |
| Presentation resources | Unassembled static meshes, materials and icon artwork; mandatory visible use under ASSET-01..05 | VISUAL-01..06, HUD-01 |
| Observation | Output-only transport reports unavailable gameplay until connected | OBSERVE-01 |
| Design data | Complete board specification as diagram and machine-readable mirror | MAZE-01 |

The welcome view is a project-health placeholder, not the requested title menu.

## 4. Player goal and complete flow

### 4.1 Goal

Clear all ordinary dots while surviving the four pursuers, increasing the high score through energizers, captures and timed fruit (DOT-01, FLOW-03..04, CAPTURE-01, FRUIT-02, SAVE-01).

### 4.2 Complete flow

Title (FLOW-01) -> Start (FLOW-02) -> steer and collect (MOVE-01..04, DOT-01) -> avoid or capture ghosts (GHOST-01..09, POWER-01..02, CAPTURE-01..02) -> recover or lose (LIFE-01..03), or clear the maze (FLOW-04) -> Restart/Main Menu/Quit (PAUSE-02, MENU-01..02).

### 4.3 Main loop

Read the local maze -> request a turn (MOVE-02) -> collect dots (DOT-01) -> respond to pursuit or frightened opportunity (GHOST-04..09, POWER-01) -> use the updated HUD and visible effects (HUD-01, VISUAL-05).

## 5. Player controls

| Requirements | Action | When | Response |
|---|---|---|---|
| MOVE-01..03 | WASD or arrow keys; press, hold or release | Playing | Continuous cardinal motion, buffered turns and prompt reversal |
| PAUSE-01 | P or Escape | Playing/paused | Pause/resume |
| FLOW-01..02, MENU-01..02, PAUSE-02 | Left-click the labeled menu action | Applicable menu or dying Restart control | Start, resume, restart, return or quit |
| OPTIONS-01..03 | Left-click selectors, Apply, Revert, Back | Options | Edit/apply/discard settings |

## 6. Numbered requirements: the sole acceptance authority

### 6.1 Interpretation

Each numbered row defines its own observable outcome. Diagrams, tables and the Section 6.4 boundary definitions are normative only for the numbered requirements that refer to them. Section 6.4 introduces no additional requirement IDs. Summaries elsewhere introduce no extra requirements. Implementation details that are not specified are free.

### 6.2 Task-specific requirements

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback | Failure, repeat, restart or boundary |
|---|---|---|---|---|---|---|
| FLOW-01 | Application opened. | Enter the default game entry. | Show the CHOMP title, saved High Score, and working Start, Options and Quit choices on a dark screen. | Do not begin a run behind the main menu. | Large white title, readable choices and hover/focus feedback. | With no save, High Score is 0; returning to this menu never silently starts a run. The relevant Section 6.4 boundaries apply. |
| FLOW-02 | Main menu, death overlay, pause menu or a terminal result screen. | Activate Start or Restart. | Begin the maze in Figure 6A with score 0, three lives, all 299 ordinary dots, four energizers, no fruit and no capture chain. The player starts at P facing and travelling right; red starts at R, cyan/pink/orange at their listed home cells. The first mode is Scatter. | No inherited pickups, active timers, input buffer or ghosts from the preceding run. | The play view and HUD replace the menu; movement begins. | A fresh run has a new run identity. Publish its initial state before motion, as defined in Section 6.4. |
| MAZE-01 | A fresh maze is displayed. | Observe and traverse its corridors. | Reproduce Figure 6A as a 30-column by 28-row maze, including all wall cells, blocked void cells, ordinary-dot cells, four energizers, the home gate and three paired wrap passages. Cells are square; scale is free. | Do not shrink the board, remove branches, open wall shortcuts or replace the playfield with a small demonstration maze. | A dense, continuous maze with recognizable central ghost home and perimeter corridors. | The full diagram is part of this requirement; rotating the entire world is allowed if controls and reported coordinates retain the diagram semantics. |
| MOVE-01 | Playing with a valid corridor ahead. | Press W/A/S/D or an arrow key. | W/Up requests up, S/Down down, A/Left left and D/Right right in the board diagram. Move smoothly along corridor centers at 6 cells per active second, within 5%. Releasing the key continues the current direction until blocked. | No diagonal movement, tile skipping, key-repeat speed changes or movement driven by observer commands. | The character visibly travels and turns to face travel. | At a wall, stop at the last legal cell center; no movement is also a valid blocked result. The relevant Section 6.4 boundaries apply. |
| MOVE-02 | Approaching an intersection. | Request a perpendicular turn before reaching it. | Take the requested turn at the first reachable corridor center while the key is held or within 0.25 seconds after release. If it is illegal there, continue the current legal direction. | No corner cutting or snapping through a wall. | A smooth center-aligned turn. | A released request expires after 0.25 active seconds; the most recently pressed direction wins. Opposite held keys use the latest press. The relevant Section 6.4 boundaries apply. |
| MOVE-03 | Travelling between centers. | Request the opposite direction. | Reverse promptly within 0.10 active seconds if the corridor behind is legal, without waiting for the next center. | No position jump, duplicate pickup or loss of alignment. | Facing and travel reverse. | Repeated reversals remain stable; a blocked request cannot cross a wall. The relevant Section 6.4 boundaries apply. |
| MOVE-04 | Player or a roaming/returning ghost reaches a T boundary. | Continue outward through that passage. | Reappear at its opposite listed T cell, preserve direction, and continue normal travel. The top and bottom T cells pair; each side T pairs with the same row on the opposite side. | No travel through other borders, across the middle of the maze, or through the home gate as the player. | The moving character exits one edge and appears at the paired edge. | Distance travelled across the seam is one cell; no long camera sweep across the board or repeated scoring on wrap. The relevant Section 6.4 boundaries apply. |
| DOT-01 | Playing with an ordinary dot at the player cell. | Cross the dot. | Remove that dot once, add 10 score, increase consumed ordinary dots by one and decrease remaining ordinary dots by one. | No points for empty cells, repeated overlap or another actor consuming the dot. | The dot disappears and the score updates. | Dots at T and F follow the same rule. P, R, home and gate start without dots. The relevant Section 6.4 boundaries apply. |
| POWER-01 | Playing with an energizer present. | Touch the energizer. | Remove it once, add 50 score and enter Frightened for 5.0 active seconds. Roaming non-returning ghosts become vulnerable and change appearance. | Energizers do not change the ordinary-dot count or alone satisfy maze completion. | The large orb disappears; frightened ghosts and the empowered player visibly change. | A returning ghost stays harmless and returning; waiting ghosts become vulnerable when they emerge during the active period. The relevant Section 6.4 boundaries apply. |
| POWER-02 | Frightened is already active. | Collect another energizer. | Add another 50 and refresh the remaining frightened duration to 5.0 seconds. Preserve the current capture-chain count until the continuous frightened period ends. | Do not stack duration, leave an earlier expiry active, or reset the capture multiplier on refresh. | Empowered appearance continues without flickering back to normal. | At expiry restore normal appearance and behavior, clear the capture chain, and resume the suspended wave remainder. The relevant Section 6.4 boundaries apply. |
| GHOST-01 | A run is playing. | Observe the pursuers. | Maintain exactly four distinct ghosts: red, cyan, pink and orange. Normal and frightened speed is 2 cells per active second; returning speed is 4, each within 5%. They navigate legal corridors and wrap passages. | No wall penetration, teleporting pursuit, extra pursuers or a single shared pursuit personality. | Each ghost remains distinguishable by its normal color and rounded silhouette. | Home/gate traversal is reserved for ghosts entering or leaving home. The relevant Section 6.4 boundaries apply. |
| GHOST-02 | Fresh run or life recovery. | Accumulate ordinary dots. | Red begins outside. Cyan must begin leaving at 30 consumed ordinary dots, pink at 60 and orange at 90, within 0.15 active seconds of reaching the threshold. At life recovery, waiting ghosts whose thresholds are already met must begin leaving within the same bound, in cyan, pink, orange order. | No premature threshold release caused by energizers, fruit or ghost points. | Waiting ghosts are visible inside home and exit through the gate. | Returning ghosts rejoin independently of the initial threshold. Already released ghosts are not returned home at a threshold. Section 6.4 defines departure start, inactivity selection and recovery eligibility. |
| GHOST-03 | At least one initial-release ghost is still waiting. | Spend 5.0 active seconds without eating an ordinary dot. | Force the next waiting ghost out in cyan, pink, orange order. Restart the inactivity clock after a forced release or ordinary-dot pickup. | Do not force all waiting ghosts out at once or use wall-clock time while paused. | One additional pursuer leaves home even if the player is stationary. | Repeat after another 5.0 seconds if a ghost still waits; fresh run and recovery restart this clock. The relevant Section 6.4 boundaries apply. |
| GHOST-04 | Normal ghost behavior is active. | Allow active play time to pass. | Use Scatter 5s, Chase 5s, Scatter 5s, Chase 5s, Scatter 5s, Chase 5s, Scatter 5s, then Chase for the rest of that life. During Scatter each ghost patrols between its two corner-region cells in Table 6B. | No wave advancement during pause, death recovery or frightened time. | Ghost motion alternates between corner patrol and pursuit. | After fright expiry continue the remaining time of the interrupted wave; recovery after a lost life starts a fresh wave sequence. The relevant Section 6.4 boundaries apply. |
| GHOST-05 | Red is roaming in Chase. | The player moves to a different corridor. | Red pursues the player's current cell, refreshing its pursuit as it reaches corridor centers. | No fixed waypoint loop presented as chasing. | Red visibly follows the player through legal routes. | Any shortest legal route, including wraps, is acceptable; equally short routes can differ. The relevant Section 6.4 boundaries apply. |
| GHOST-06 | Pink is roaming in Chase. | The player changes heading. | Pink pursues the reachable cell up to four cells ahead in the player's current direction, stopping the look-ahead at the first wall, gate or board edge. | Do not always target the current player cell when a distinct ahead cell exists. | Pink attempts to intercept ahead. | A stationary player retains the last facing; if no ahead cell is legal, the player cell is the target. The relevant Section 6.4 boundaries apply. |
| GHOST-07 | Cyan is roaming in Chase. | The player or red ghost changes position. | Cyan's pursuit destination is the reflection of red's current cell across the point up to two legal cells ahead of the player. If that reflected destination is blocked or outside, the target is a roaming cell with minimum straight-line distance to it. Equally near targets may use any reproducible choice. | No permanently identical red/pink/cyan targets when their defined destinations differ. | Cyan visibly chooses an approach affected by both player heading and red position. | Section 6.4 defines look-ahead limits, nearest-cell sampling and target-refresh boundaries; no search algorithm or data structure is prescribed. |
| GHOST-08 | Orange is roaming in Chase. | The player crosses orange's distance boundary. | At straight-line distance less than 8 cells orange pursues the current player cell; at distance 8 or greater orange patrols its corner region. | Do not retreat when closer than 8 cells or pursue the player at distance 8 cells or greater. | Orange alternates between nearby pursuit and distant retreat. | Distance uses displayed board coordinates without wrap-distance shortening; reconsider at corridor centers. The relevant Section 6.4 boundaries apply. |
| GHOST-09 | A vulnerable roaming ghost is frightened. | It reaches a corridor decision. | At a corridor center, choose a legal next center that increases shortest legal corridor distance to the player's cell when one exists. Count paired wraps as one step. If no next center increases distance, choose one with the greatest available distance. Keep the 2-cell/second speed. | No wall crossing, indefinite paralysis or hidden invulnerability. | The ghost retreats with its frightened appearance. | Section 6.4 defines the distance, target cell, reversal and tie boundaries. Equal allowed choices may differ but must be reproducible under the same seed and action timing. |
| CAPTURE-01 | Player contacts a frightened ghost. | Their collision areas overlap. | Capture that ghost once without losing a life; successive captures in one continuous frightened period award 200, 400, 800, 1600, then double again for each further capture. | Repeated overlap with the same returning ghost cannot award points. | The colored body disappears or becomes a clearly reduced returning form; score changes. | The chain resets at frightened expiry, death or fresh run, and is preserved on energizer refresh. The relevant Section 6.4 boundaries apply. |
| CAPTURE-02 | A ghost has been captured. | Allow it to return home. | Travel visibly through corridors and the gate to its home cell at returning speed, remain harmless en route, and then resume roaming. It is frightened again if the global frightened period is still active. | No instant disappearance/reappearance, permanent removal, harm or recapture while returning. | A distinct returning form moves back to home and its normal/frightened body reappears. | A new run or life recovery cancels the old return journey. The relevant Section 6.4 boundaries apply. |
| LIFE-01 | Playing and touching a dangerous ghost. | Collision occurs. | Lose exactly one life, enter a death interval, stop active play and show the death feedback. Multiple same-time dangerous contacts cause only one life loss. Show an enabled, clickable Restart control during dying within 0.15 seconds. | No further score, movement, pickup, ghost release or damage during the death interval. | The player disappears or visibly dies, accompanied by a brief camera impulse and updated lives. | Frightened and returning ghosts are not dangerous. FLOW-04 and Section 6.4 define simultaneous contacts, death timing and the normal Restart route. |
| LIFE-02 | A nonfinal life was lost. | The 3.0-second death interval ends. | Respawn the player at P facing right and reset ghost positions to their starting cells. Preserve current score, collected dots/energizers and fruit-spawn thresholds already spent. Remove any active fruit; clear fright, capture chain, turn buffer and old motion. | No board refill, score reset, duplicate actors or delayed changes from the lost life. | Normal play resumes on the partially cleared maze with one fewer life. | Restart wave and inactivity clocks and resume rightward player motion. A new run resets the whole board; Section 6.4 defines the recovery boundary. |
| LIFE-03 | A collision reduces lives to 0. | The final lethal contact starts the death interval. | At the end of the 3.0-second death interval after that lethal contact, show GAME OVER with final score, saved high score and Restart, Main Menu and Quit. TIME-01 tolerance applies to this single deadline. Keep the terminal world frozen. | No automatic respawn, negative lives, further score or resumed AI. | Clearly distinct losing result screen. | The 3-second limit includes the death feedback; no second interval follows it. Movement and pause do not dismiss the result. Restart during dying follows Section 6.4. |
| LIFE-04 | Playing after a fresh run, recovery or previous extra-life grant. | Earn score. | Track points earned since that reset. When at least 2000 have accumulated and lives are below 3, award one life and reset this progress to 0. Never exceed 3 lives. | No repeated grant from an unchanged score or negative progress on Restart. | An additional yellow life icon appears with a perceptible positive pulse. | At 3 lives do not grant; accumulated progress can remain until a later eligible positive score change, but life recovery resets it to 0. The relevant Section 6.4 boundaries apply. |
| FRUIT-01 | An ordinary-dot pickup reaches consumed count 70 or 170. | The threshold is reached exactly once. | Spawn a visible pineapple at F for 10.0 active seconds. At 170 spawn only if the earlier pineapple is absent; if one is still active, skip that second opportunity without queuing it. | No spawn from score thresholds, duplicate pineapple, delayed second spawn or repeat after death. | A small orange/gold fruit with a green crown appears in the maze. | Pause freezes its lifetime. Expiry removes it without awarding points; a new run restores both opportunities. The relevant Section 6.4 boundaries apply. |
| FRUIT-02 | A pineapple is present. | The player contacts it before expiry. | Remove it once and award 1000 score. | No repeated overlap reward or ordinary-dot count change. | Score increases, a brief pineapple-themed reward overlay appears and a short camera impulse is visible. | Fruit disappears on death or terminal transition without points. At exactly its expiry time, expiry wins. The relevant Section 6.4 boundaries apply. |
| FLOW-03 | At least one ordinary dot remains. | Play, consume energizers, fruit or ghosts. | Continue the run until all ordinary dots are gone. | No early victory from score, time, energizers or fruit. | The board remains playable and the score/lives HUD remains active. | The victory condition counts ordinary dots only. The relevant Section 6.4 boundaries apply. |
| FLOW-04 | The player collects the final ordinary dot. | Resolve the pickup. | Award its 10 points and show YOU WIN within 0.5 seconds with final score, high score, pineapple stage emblem and Restart, Main Menu and Quit. Freeze movement, damage, scoring, AI and spawning. | Do not require leftover energizers or fruit, or permit late death to replace the win. | A winning result screen distinct from GAME OVER. | If the final dot and a dangerous ghost are touched in the same simulation step, the final-dot win takes priority. There is one complete maze, not an extra hidden level. The relevant Section 6.4 boundaries apply. |
| PAUSE-01 | Active play. | Press P or Escape once. | Open a pause overlay with Resume, Restart, Options, Main Menu and Quit. Freeze positions, score, lives, wave time, fright time, fruit lifetime and release inactivity time. | No gameplay key leakage or wall-clock expiry behind the overlay. | A dimmed/blurred view remains behind readable pause choices. | Resume or a second P/Escape returns to the same state; held keys cannot trigger repeated toggles. The relevant Section 6.4 boundaries apply. |
| PAUSE-02 | Pause menu, death overlay or terminal result. | Activate Restart. | Start the complete fresh state in FLOW-02 even while frightened play, return travel, fruit expiry or a death interval was in progress. | No old effect, held/queued direction, damage, award or pickup alters the new run. | The clean maze and three lives reappear. | Repeated Restart works; high score and applied settings survive. Section 6.4 defines death-overlay access and simultaneous-event priority. |
| MENU-01 | Pause, Options or a terminal result. | Navigate Back or Main Menu as appropriate. | Back from Options returns to its originating menu; Main Menu ends the current run and returns to the title screen. | No orphan overlay, invisible modal control, active play behind the menu or lost input focus. | The requested menu and its usable controls appear. | Repeated Options navigation does not duplicate controls or resume a paused run. Main Menu discards the run while preserving high score and applied settings. The relevant Section 6.4 boundaries apply. |
| MENU-02 | A menu containing Quit. | Activate Quit. | Save the high score and applied options, then close normally. | No background game process left running. | The game window closes. | Standard OS close performs the same persistent-data save. The relevant Section 6.4 boundaries apply. |
| OPTIONS-01 | Options opened from title or pause. | Change the displayed choices. | Expose Window Mode (Windowed, Fullscreen), VSync (Enabled, Disabled), Graphics (Low, Medium, High, Epic, Cinematic) and Resolution. Offer 1280x720 and 1920x1080 when the desktop supports them; keep unsupported resolutions unavailable. | Do not show choices that cannot be changed or silently apply a pending selection. | Left/right selectors and the selected values are legible; Apply/Revert indicate whether changes are pending. | Use an explicit custom label when existing engine settings do not match a preset. The relevant Section 6.4 boundaries apply. |
| OPTIONS-02 | Options have pending changes. | Activate Revert or Back without Apply. | Discard pending choices and retain the last applied settings. | No unintended resolution, quality or VSync changes. | Revert restores the displayed applied values; Back returns to the originating menu. | With no changes, Apply and Revert are disabled or harmless. The relevant Section 6.4 boundaries apply. |
| OPTIONS-03 | Options have valid pending changes. | Activate Apply. | Apply the actual window mode, resolution, VSync and graphics preset, save them, and continue showing usable UI at the new dimensions. | No decorative-only settings or stretched/unreachable menu after resize. | The window/rendering change and selected labels agree. | Reopening the application preserves applied settings; a launch-time viewport override may temporarily override window size for a session. The relevant Section 6.4 boundaries apply. |
| SAVE-01 | A score exceeds the existing best. | Continue play, return to menu, quit and reopen normally. | High score is the maximum achieved score, visible on the title and result screens and preserved across process restart. | No decrease after a weaker run, Restart or returning to menu. | The new record is identified on the result screen. | On first launch or unreadable save, start safely at 0 without corrupting the playable flow. The relevant Section 6.4 boundaries apply. |
| SAVE-02 | A partially played run was closed. | Open the application again. | Open the main menu with the saved best and applied settings. Starting then begins a fresh run. | Do not restore partial score, lives, remaining pickups, fruit, frightened state or terminal state as a resumed run. | Title screen appears before a new clean play session. | A fresh process identity distinguishes reopening from in-process Restart. The relevant Section 6.4 boundaries apply. |
| HUD-01 | Playing or paused. | Score or lives change. | Show SCORE at the upper left and LIVES with yellow open-mouth icons at the lower left. Update both within 0.15 seconds of a change; the icon count equals current lives. | No stale number, negative count, cropped text or overlap obscuring the player near the screen center. | Large thin white labels and clearly separated yellow icons. | At 1280x720 and 1920x1080 the information stays readable; terminal screens may replace the HUD. The relevant Section 6.4 boundaries apply. |
| VISUAL-01 | Viewing active play. | Inspect the maze and move through it. | Render a real 3D perspective maze: near-black cuboid walls with thin electric-blue emissive edges, dark walkable floor, visible wall height and shaded side faces. White luminous dots sit along corridor centers; energizers are visibly larger. Retain bloom without washing out corridor boundaries. | No flat diagram, unlit debug boxes, missing materials or HUD drawing used as the entire world. | Dark neon arcade composition with visible depth and a dense full-sized maze. | Geometry and rendering technique are free within ASSET-04; keep wall height between 0.65 and 1.10 cell and dot diameter between 0.12 and 0.25 cell. The relevant Section 6.4 boundaries apply. |
| VISUAL-02 | Player moving and turning. | Travel along corridors. | Show a luminous yellow spherical character with a visibly opening/closing mouth, dark eyes and pale triangular teeth. Animate repeated chomping while moving, oriented along travel. | No static sphere, permanently closed mouth, backward-facing travel or animation detached from the character. | Readable biting silhouette and animated mouth at normal camera distance. | Body diameter is 0.55 to 0.85 cell; open mouth animation also remains readable in frightened play. The relevant Section 6.4 boundaries apply. |
| VISUAL-03 | Four ghosts are visible. | Normal, frightened and returning states occur. | Ghosts have rounded heads and short vertical rounded bodies, with distinguishable red/cyan/pink/orange glow in normal play. Frightened ghosts use a common pale-blue vulnerable appearance. Returning ghosts use a visibly reduced pale form without the normal body. | Do not distinguish these states only by observer data or text. | State and identity are readable from moving silhouettes and color. | At fright expiry restore each ghost's own normal color; returning appearance takes precedence. The relevant Section 6.4 boundaries apply. |
| VISUAL-04 | Active play. | Player moves around the maze. | Use a smoothly following, elevated perspective camera with visible top and side wall faces. Keep the player within the central half of the view and enough surroundings to read upcoming intersections; at 720p show roughly 12 to 22 cell widths. | No fixed full-board orthographic map, first-person view, wall clipping, sustained occlusion or immediate snap at ordinary turns. | The maze slides naturally beneath a readable foreground character. | A wrap may reset the follow position promptly; no multi-second flight across the maze. Menus/results may use a wider overview. The relevant Section 6.4 boundaries apply. |
| VISUAL-05 | An energizer, ghost capture, pineapple or life-loss event occurs. | Resolve the event. | Provide a short perceptible camera impulse and a distinct visual response: empowered-player change for energizer, returning-form change for ghost, pineapple overlay for fruit, and disappearance/death motion for life loss. | No missing feedback, permanent shaking, unreadable prolonged flash or camera displacement that prevents control. | A brief impulse settles within 0.5 seconds; the pineapple overlay clears within 1.5 seconds. | Repeated events remain bounded and Restart clears old effects. Exact shake curves and shader implementations are free. The relevant Section 6.4 boundaries apply. |
| VISUAL-06 | Any game menu or result is visible. | Read and use its controls. | Use a predominantly black background, large white heading and white/light-gray controls. Keep title-menu choices left aligned; Options use labeled rows with left/right selectors and Back, Revert, Apply along the bottom. Pause/result overlays preserve a dimmed or blurred world context. | No debug console as menu, clipped controls or style replaced by generic editor widgets. | The same visual language spans title, pause, options, win and loss. | Exact font family and pixel placement are free if visual hierarchy and required information remain clear. The relevant Section 6.4 boundaries apply. |
| TIME-01 | A timed rule in this contract is active. | Observe its boundary or pause/resume. | Use active game time for movement, waves, frightened duration, release inactivity and fruit lifetime; the death interval is measured from lethal contact as defined in Section 6.4. Timing acceptance tolerance is 0.15 seconds unless a rule specifies another tolerance. | No timer acceleration from render frame rate or elapsed paused time. | Paused world visuals stay still and resumed effects retain their remaining duration; menu feedback may animate. | Section 6.4 defines simultaneous-event priority, exact threshold boundaries and which clocks run in each phase. |
| OBSERVE-01 | The application is running. | Read the public observation output during normal play. | Expose truthful, current read-only observations of the visible phase, resources, actors, pickup presence, timers and usable menu targets described by the public observation contract. | No observation read may alter play, trigger a result, expose a cheat control or claim an outcome unsupported by the world. | Ordinary players use the normal game; all reported visible objects and controls match that view. | Missing gameplay remains explicitly unavailable in the untouched starter; alternative internal architectures are allowed. |
| ASSET-01 | The player is visible. | Move, turn and enter empowered play. | Use the supplied SM_Jaw mesh for the yellow upper/lower mouth, SM_Tooth for the pale teeth and SM_Eye for the dark eyes. Use MI_Player, MI_Dot and MI_Eye for those respective surfaces, with M_Neon as their material base. | Keeping unused files in the project or substituting unrelated character art does not satisfy this requirement. | The supplied curved jaws, triangular teeth and spherical eyes form the visible animated player described by VISUAL-02. | Duplicate, transform, scale and animate the supplied parts; material parameter changes and derived instances are allowed if the specified colors and state feedback remain. Retain the recognizable geometry. The relevant Section 6.4 boundaries apply. |
| ASSET-02 | Ghosts are visible. | Observe normal, frightened and returning play. | Build the four normal ghost silhouettes from the supplied SM_GhostHead and SM_GhostBody. Use MI_Red, MI_Cyan, MI_Pink and MI_Orange for their respective identities and MI_Frightened during vulnerability, retaining M_Neon as the base. | Unused resource references, generic replacement capsules or four identical normal colors do not satisfy the binding. | The supplied rounded heads and short bodies remain recognizable in normal/frightened play, with the distinctions required by VISUAL-03. | Scaling, animation and parameter changes are allowed. The returning form may hide or reduce body parts to meet CAPTURE-02 and VISUAL-03. The relevant Section 6.4 boundaries apply. |
| ASSET-03 | A pineapple is present. | Reach a fruit opportunity and collect it. | Use the supplied SM_FruitBody with MI_Fruit and SM_FruitCrown with MI_Crown as the visible maze pineapple, retaining M_Neon as their base. | A substitute primitive, unrelated model or decorative unused copy cannot replace the required fruit parts. | The faceted orange/gold fruit and green crown are visible during FRUIT-01. | Transforming, scaling, animating and tuning parameters is allowed while retaining the supplied silhouette. The reward overlay and stage emblem may use a rendered image of these parts or separately authored artwork. The relevant Section 6.4 boundaries apply. |
| ASSET-04 | The maze is visible. | Inspect active play. | Use M_Wall with its supplied T_WallEdge texture on the maze walls. Use MI_Floor on the floor, MI_Gate on the home gate and MI_Dot on ordinary dots and energizers, retaining M_Neon as the base of these instances. | A resource present only in the Content Browser or an unrelated replacement material does not satisfy visible use. | The dark surfaces, blue wall edges, cyan gate and white pickups satisfy VISUAL-01. | Geometry, UV layout and collision are free. Derived instances and shader/parameter adjustments are allowed while retaining the supplied material/texture contribution and the required colors, edge pattern and readability. The relevant Section 6.4 boundaries apply. |
| ASSET-05 | The score/lives HUD is visible. | Start a run, lose a life or gain a life. | Use the supplied T_LifeIcon texture, or a raster/vector derived from the supplied life-icon SVG or PNG, for each life icon in HUD-01. Either route fulfills the binding; using both is unnecessary. | Text-only lives, generic circles or unrelated icon art cannot replace the supplied shape; merely storing the icon is insufficient. | Yellow open-mouth icons remain recognizable and their count matches current lives. | Scale, space and animate icons to fit both required resolutions. A derived raster or vector must retain the supplied shape and yellow color. Reimporting raw files is not required. The relevant Section 6.4 boundaries apply. |

### Figure 6A: full maze (MAZE-01, FLOW-02)

Column numbers increase left to right from 0 to 29; row numbers increase downward from 0 to 27. `#` is a solid wall, `X` an inaccessible empty void, `.` an ordinary dot, `E` an energizer, `T` a boundary wrap passage with an ordinary dot, `=` the ghost-only gate, `H` home, `R` red's start, `P` the player's start and `F` fruit's location with an ordinary dot. Home, gate, P and R initially have no pickup. The exact topology is specified here; the raw diagram is not a prebuilt level.

```text
   000000000011111111112222222222
   012345678901234567890123456789
00 ##############T###############
01 #........#XXX#.#XXX#....##...#
02 #.###.##.#XXX#.#XXX#.##.##.#.#
03 #E###.##.#XXX#.#XXX#.##....#E#
04 #.###.##.#XXX#.#XXX#.##.##.#.#
05 #.###.##.#####.#####.##.##.#.#
06 #..........................#.#
07 #.###.########.#####.#######.#
08 #.###.########.#####.#######.#
09 #.###....##...R......##....#.#
10 #.###.##.##.##=##.##.##.##.#.#
11 #.###.##....#HHH#.##.##.##.#.#
12 T.....#####.#####.##....##...T
13 #####.#####...P...#####.####.#
14 #####.#####.##.##.#####.####.#
15 T.....#####.##.##.##....##...T
16 #.###.##....##.##.##.##.##.#.#
17 #.###.##.##.##.##.##.##.##.#.#
18 #E###....##...F......##....#E#
19 #.###.########.#####.#######.#
20 #.###.########.#####.#######.#
21 #..........................#.#
22 #.###.##.#####.#####.#####.#.#
23 #.###.##.#XXX#.#XXX#.#####.#.#
24 #.###.##.#XXX#.#XXX#.##....#.#
25 #.###.##.#XXX#.#XXX#.##.##.#.#
26 #........#XXX#.#XXX#....##...#
27 ##############T###############
```

### Table 6B: ghost starting and corner cells (FLOW-02, GHOST-04, CAPTURE-02)

Coordinates are `(column, row)` in Figure 6A. Red and pink share a return home cell but remain separate actors.

| Ghost | Initial cell | Return home | Scatter pair |
|---|---|---|---|
| Red | (14,9) | (14,11) | (20,6) and (28,1) |
| Cyan | (13,11) | (13,11) | (8,6) and (1,1) |
| Pink | (14,11) | (14,11) | (20,21) and (28,26) |
| Orange | (15,11) | (15,11) | (8,21) and (1,26) |

### 6.3 Shared numbered quality requirements

| ID | Requirement |
|---|---|
| QUALITY-01 | The project starts, runs, exits and starts again normally using the public instructions. |
| QUALITY-02 | The main flow uses normal player input and does not rely on answer buttons, cheats or direct calls to gameplay outcomes. |
| QUALITY-03 | Key entry points, text and controls are visible, discoverable, readable and operable. |
| QUALITY-04 | Player actions have perceptible feedback that agrees with actual game state. |
| QUALITY-05 | No severe error blocks the main flow. |
| QUALITY-06 | Repeated runs from the same initial conditions are substantially stable. |

### 6.4 Boundary definitions and permitted variation

This section refines the numbered requirements named in each paragraph. It defines player-visible results and acceptance boundaries, not an implementation architecture. A choice explicitly left free here cannot be judged against an unstated preferred choice.

#### Movement, contact and time

**FLOW-02, MOVE-01..04, OBSERVE-01:** A fresh run starts at active time 0, with the complete initial state in FLOW-02. Publish that initial state before its first movement update; do not hold the character still for an extra countdown. After a lost life the player also resumes rightward motion automatically. Directions are relative to Figure 6A even if the world is rotated. At a blocked center a legal requested direction can start motion without another key press. A failed perpendicular request remains eligible at later centers until its hold ends and its 0.25-second release window expires; an illegal intersection does not consume it. Evaluate a request at its exact expiry as expired. If opposite direction presses have the same timestamp, either may win, consistently under the same seed and input order. No new turn request is accepted while a menu, death interval or result screen owns input. Keys already held when starting, restarting or resuming must be released and pressed again to create a new request; pre-pause queued turns are discarded, while current travel direction and position are preserved.

**MOVE-01..04, DOT-01, POWER-01, CAPTURE-01, LIFE-01, FRUIT-02:** Movement and contact must remain continuous at the required speeds. Visual mouth movement, teeth and eyes do not repeatedly alter the player's contact area. Contact regions must be centered on and visually consistent with the actor bodies or pickups. An actual body overlap must not be ignored and a clearly separated object must not trigger a remote contact. Exact collider shape and the precise subcell point of first edge contact are free; no particular radius or hidden pixel threshold is required. A successful player traversal through the center of a pickup cell collects the item once even if a rendered frame skips over it. Player and ghost travel across a wrap seam must not cause contacts with intervening board cells. Ghosts may overlap one another and must not block one another's release or corridor travel. The player cannot enter either the gate or the home cells.

**TIME-01, PAUSE-01, VISUAL-05:** Active time advances only during playing. It stops in menus, Options, pause, the death interval and terminal phases. Frightened play still advances fruit, release-inactivity and movement time; only the normal Scatter/Chase wave is suspended. The death interval uses elapsed responsive application time from lethal contact; it does not advance the run's active time. P/Escape has no effect during dying. Event effects pause with active play, except that the death feedback progresses during dying. Menu hover/focus feedback may animate while the world is paused. The 0.15-second timing tolerance permits measurement/update delay, not a change to nominal durations or intentional early expiry. Threshold comparisons use the stated boundary exactly; tolerance does not change the 8-cell distance threshold or grant pickups after their expiry.

**TIME-01, FLOW-04, POWER-02, CAPTURE-01, FRUIT-01..02, LIFE-01..04:** At the same gameplay time, an activated Restart, Main Menu or Quit action ends the current run before its remaining world events can affect another run. Otherwise, expiry precedes pickups; ordinary dots precede energizers, then fruit, then ghost contacts. Final-dot victory stops all remaining world events at that time, including an energizer, fruit or ghost reward at that time. A newly spawned fruit is eligible for contact at the same time after the triggering dot, unless that dot has already ended the run. If an ordinary dot and a release-inactivity deadline coincide, the pickup restarts inactivity before a forced release can occur. If a wave boundary and energizer coincide, the wave boundary takes effect and the newly entered wave is suspended at its full duration. If fright expires at the same time as another energizer pickup, expiry ends the old chain; that energizer begins a new chain at zero. Process simultaneous ghost contacts in red, cyan, pink, orange order; returning ghosts have no effect, vulnerable contacts award one capture each, and the first dangerous contact ends contact processing with one life loss. An extra-life award caused by a valid score change takes effect before a later dangerous contact at that same time. These priorities specify outcomes and do not require any particular update loop.

#### Ghost movement and release

**GHOST-01..09, CAPTURE-02:** A roaming cell is a traversable corridor cell, including P, R, F, E and T, but excluding walls, voids, the home and the gate. A roaming ghost cannot enter home as a shortcut. Consecutive cardinal corridor cells are one cell apart; each paired wrap is also one cell apart. A ghost's corridor decision is made at a cell center. Opposite travel is a legal choice at a center, including at a dead end. Mode changes do not require an immediate reversal between centers. A ghost can complete its current edge before choosing its next direction; its vulnerable/dangerous appearance and contact status change at the actual mode boundary. Shortest-route tie choices are free and reproducible. Normal pursuit follows a shortest legal route to the declared target; shortest-route selection, internal storage and search method are unrestricted. During Scatter the ghost alternates between its two Table 6B cells when each is reached. Either member may be the first target after a new life or mode change; a particular first member or tie route is not an acceptance requirement.

**GHOST-02..03, LIFE-02:** Consumed ordinary dots are cumulative for the current run and survive life recovery. At the 30/60/90 threshold, the corresponding waiting ghost must begin leaving within 0.15 active seconds; eligibility is not permission to wait indefinitely. At recovery, all eligible waiting ghosts begin leaving within that same bound. When multiple ghosts become eligible together, their departure start order is cyan, pink, orange; starts may occur in the same update and need no artificial spacing. A departure begins when a waiting ghost visibly starts travelling from its home cell toward the gate, not when it reaches the outside. Leaving speed is 2 cells per active second and the exit is through the gate to the corridor at R, without a stationary holding delay. A ghost already leaving is no longer waiting and cannot be selected again by the inactivity rule. A forced departure starts within 0.15 active seconds after the 5-second inactivity deadline. This deadline is based on the last ordinary dot or forced departure, not on energizers, fruit, captures or a natural departure. With no waiting ghosts, the inactivity countdown is inactive. Life recovery resets release eligibility to the preserved dot count; a ghost forced out below its threshold may wait again after recovery. Returned captured ghosts are not subject to initial-release thresholds.

**GHOST-05..08, MOVE-01:** Target rules use the player's nearest cell center and last nonzero facing. At an exact halfway position, use the cell being entered in the current travel direction; a stopped actor keeps its last unambiguous cell. Pink's ahead target is the furthest legal cell along that heading, capped at four cells; cyan's ahead point uses the same definition capped at two. Neither look-ahead crosses a wall, gate, home cell or board edge, including a wrap edge. If the first ahead cell is blocked, the ahead point is the player's cell. Cyan's reflected destination has the ahead point as the midpoint between it and red's nearest cell; if invalid, the chosen roaming cell has minimum straight-line distance to that destination. Ties may choose any equally near roaming cell. Orange compares its current center to the player's nearest cell using straight-line distance in Figure 6A; it chases only below 8 cells. These straight-line distances do not shorten across a wrap. Targets are reconsidered at each ghost center, without a required mid-edge turn or private target-refresh rate.

**GHOST-09:** Escape distance is the minimum number of legal corridor steps to the player's nearest cell, including paired wraps as one step and excluding home/gate cells. At a decision center, compare the distance at the ghost's current center with the distance at each legal next center. If at least one next center is strictly farther, the next center must be one of those farther cells; the greatest increase is not required. If none is farther, choose a legal next center with the greatest available distance. Equal choices may differ consistently under the seed and input timing. Reversal at the center is allowed. This defines observable route choices, without prescribing how distances are obtained.

**CAPTURE-01..02, POWER-01..02:** Each successful capture increases the chain count by one; the count starts at zero and describes completed captures, not the next reward or a multiplier. A captured ghost travels home at 4 cells per active second, including home/gate traversal. Upon reaching its own home cell it begins leaving again within 0.15 active seconds at 2 cells per second; there is no additional waiting or threshold. It is harmless while returning and inside the inaccessible home. Once outside, it is vulnerable if fright is still active and dangerous otherwise. Waiting/leaving ghosts also acquire the current fright status upon emerging. Capturing a ghost again after a completed home journey is allowed and continues the same chain if the global frightened period has not ended.

#### Death, restart, records and menu settings

**LIFE-01..03, PAUSE-02, HUD-01, VISUAL-06:** Lethal contact is the start of the death interval. During dying show a clearly labeled, clickable Restart control within 0.15 seconds, alongside the death feedback and current score/lives. Restart immediately starts a full new run; it does not resume the lost life. This is the normal player route for restarting before the death interval ends. Without Restart, nonfinal recovery occurs after 3.0 seconds. The final death interval is also 3.0 seconds. GAME OVER appears at that deadline from lethal contact, subject to the TIME-01 tolerance; it does not receive a second 3-second allowance after feedback. P/Escape cannot pause or skip dying. A Restart click accepted at the death deadline takes precedence over recovery or GAME OVER, and a single click cannot also activate a control on the new screen. On recovery the player resumes rightward motion, the score and cleared pickups persist, active fruit is absent, and all normal initial life-level timers restart. Death clears the active fright/chain, pending turns, fruit and reward overlays; no delayed award, damage or visual effect from that life may affect recovery or a new run.

**LIFE-04, SAVE-01, FLOW-04, MENU-01..02:** Extra-life progress is earned points since the most recent fresh run, life recovery or extra-life grant. It is not total score. On a positive score change while below three lives, reaching or exceeding 2000 grants exactly one life and discards overflow by resetting progress to zero. At three lives progress may be retained until the next reset; it never causes a grant without a new positive score change. A valid final-dot award can also grant a life before the resulting winning state freezes. High Score increases with earned score and cannot decrease during a process or across normal close/reopen. A run is a new record only if its final score exceeds the high score that was saved before that run started; tying it is not a new record. Return to Main Menu discards run state after preserving the record and applied settings. Quit or normal OS close persists that same record and applied settings, including when no result screen has been reached.

**OPTIONS-01..03, SAVE-02:** Fullscreen means exclusive fullscreen; borderless mode is not an additional required choice. Graphics labels correspond to the installed engine's standard Low/Medium/High/Epic/Cinematic quality levels; a mixed configuration displays Custom rather than falsely matching a preset. Defaults may come from the installed engine and available display; no fixed first-launch resolution, preset or VSync value is required. Unsupported modes/resolutions remain unavailable. If the display changes between launches and a saved resolution is no longer supported, select a supported fallback, display its actual value and remain usable. Pending selections are discarded on Revert, Back, Main Menu or process close; only Apply persists them. Launch-time viewport arguments set the initial client size for that launch and do not change the saved setting. A later explicit Options Apply takes precedence for the rest of that launch. Observation distinguishes actual client dimensions from saved/applied menu choices when a launch override is active.

#### Presentation and required art

**VISUAL-01..06, ASSET-01..05:** The supplied art must contribute visibly in its assigned role. Using its edited or derived form is permitted within the row's restrictions; merely recreating a similar-looking unrelated asset does not count as using the supplied art. A derived form may have a different filename/object path and need not retain the supplied file's hash. For the life counter, either the supplied UE texture or a raster/vector derived from the supplied PNG/SVG fulfills ASSET-05; using both is unnecessary. The underlying geometry, colors and wall-edge pattern must remain recognizable. Temporary empowered/death effects may tint or hide required parts as described by the gameplay rows; normal appearance must recover afterward. Returning ghosts may hide their normal body. Additional effects, typography and menu artwork are free. No exact shader graph, material parameter value, animation curve or frame-by-frame image match is required.

**VISUAL-04, HUD-01, OPTIONS-03:** The central half of the client image means normalized x and y between 0.25 and 0.75 for the player's projected center during ordinary stable travel. The 12-to-22-cell camera span describes the horizontal ground-plane span through the player's position at 1280x720, not the number of visible wall faces. A brief turn/camera impulse or wrap reset may temporarily depart from the central area while settling within the relevant feedback bound; prolonged loss of the player is not acceptable. Screen-space visual tolerances are judged against the configured client viewport, never OS window borders. These checks apply with a normal usable graphics preset; a deliberately chosen Low preset may reduce bloom, while materials, actor identities and controls must remain legible. Exact pixel positions and optional embellishments remain free.

## 7. Success, failure and stages

### 7.1 Success

| Requirements | Condition | Result |
|---|---|---|
| DOT-01, FLOW-03..04 | All ordinary dots collected | YOU WIN; final state locks and result actions remain usable |

### 7.2 Failure

| Requirements | Condition | Result |
|---|---|---|
| LIFE-01..02 | Dangerous contact with lives remaining | Death feedback followed by partial-maze recovery |
| LIFE-03 | Final life lost | GAME OVER; Restart/Main Menu/Quit |

### 7.3 Stages

| Stage | Requirements | Boundary |
|---|---|---|
| Initial pursuit | GHOST-02..04 | Waiting ghosts use thresholds or inactivity release |
| Frightened opportunity | POWER-01..02, CAPTURE-01..02 | Timed vulnerability suspends the normal wave |
| Fruit opportunity | FRUIT-01..02 | Two thresholds; limited lifetime |
| Terminal | FLOW-04, LIFE-03 | No late world mutation |

## 8. Interface and feedback summary

| Requirements | Information | Update or distinction |
|---|---|---|
| HUD-01 | Score and life icons | Match current resources |
| VISUAL-01..04 | Maze depth, mouth, ghost state and camera | Readable during movement |
| VISUAL-05 | Pickup/capture/fruit/death effects | Brief and distinct |
| FLOW-01, VISUAL-06, OPTIONS-01..03 | Menus/settings | Clear hierarchy and operable choices |
| FLOW-04, LIFE-03, SAVE-01 | Win/loss and best score | Distinct terminal outcome and record |

## 9. Restart, reopen and persistence

| Situation | Requirements | Reset | Preserve |
|---|---|---|---|
| Lost life | LIFE-02, GHOST-04, PAUSE-02 | Character/ghost positions, wave and transient effects | Score and cleared ordinary dots/energizers |
| Restart | FLOW-02, PAUSE-02 | Entire run and pending effects | Best score and applied settings |
| Process reopened | SAVE-01..02, OPTIONS-03 | Run progress; return to title | Best score and applied settings |

## 10. Existing functionality to preserve

Build the game from the supplied Blank project. The starter provides an inert welcome view and no gameplay. The output-only observation boundary supports OBSERVE-01 and can be reimplemented without prescribing internal gameplay architecture.

## 11. Assets and content summary

All runtime art below is mandatory under ASSET-01 through ASSET-05. Use it visibly in the stated role; storing files alone is insufficient. The allowed transformations are defined in those numbered rows. Unrelated replacements are not allowed. Exact source bytes are not an acceptance condition for edited or derived assets.

All paths in the resource column are relative to `starter-project/Content/Art/`; the JSON catalog provides the corresponding full input-relative and Unreal object paths.

| Requirements | Required resources under starter-project/Content/Art/ | Visible use |
|---|---|---|
| ASSET-01, VISUAL-02 | `Meshes/SM_Jaw.uasset`, `Meshes/SM_Tooth.uasset`, `Meshes/SM_Eye.uasset`; `Materials/MI_Player.uasset`, `Materials/MI_Dot.uasset`, `Materials/MI_Eye.uasset` | Animated yellow mouth, pale teeth and dark eyes |
| ASSET-02, VISUAL-03 | `Meshes/SM_GhostBody.uasset`, `Meshes/SM_GhostHead.uasset`; `Materials/MI_Red.uasset`, `Materials/MI_Cyan.uasset`, `Materials/MI_Pink.uasset`, `Materials/MI_Orange.uasset`, `Materials/MI_Frightened.uasset` | Four ghost identities and vulnerable appearance |
| ASSET-03, FRUIT-01 | `Meshes/SM_FruitBody.uasset`, `Meshes/SM_FruitCrown.uasset`; `Materials/MI_Fruit.uasset`, `Materials/MI_Crown.uasset` | Maze pineapple and leaf crown |
| ASSET-04, VISUAL-01 | `Materials/M_Wall.uasset`, `Textures/T_WallEdge.uasset`; `Materials/MI_Floor.uasset`, `Materials/MI_Gate.uasset`, `Materials/MI_Dot.uasset` | Blue-edged walls, floor, gate and luminous pickups |
| ASSET-01..04 | `Materials/M_Neon.uasset` | Shared base of the required color material instances |
| ASSET-05, HUD-01 | `UI/T_LifeIcon.uasset` | Yellow open-mouth life counter |

Editable sources are also inside the project: seven OBJ files in `starter-project/SourceArt/Meshes/`, `T_WallEdge.png` in `starter-project/SourceArt/Textures/`, and `life-icon.svg` plus `T_LifeIcon.png` in `starter-project/SourceArt/UI/`. The matching `assets/files/raw/` and `assets/files/ui/` files are protected reference copies. Use the ready-to-use UE assets directly; importing each source copy again is unnecessary.

`assets/ASSET_CATALOG.json` gives per-file hashes, object paths, dimensions, dependencies and source-copy mappings. `assets/legal/NOTICES.md` gives resource-use terms. The resources are static, unassembled parts without gameplay actors or behaviors. `contracts/maze-layout.json` mirrors Figure 6A for MAZE-01 and does not supply an executable level.

## 12. Implementation freedom

Architecture, code/Blueprint split, pathfinding method, object/class names, UI technology, animation method, save format and scene reset technique are free. Only the player outcomes in Section 6 and the public observation semantics apply. Different shortest-route tie choices are allowed. Use the required supplied art under ASSET-01..05; additional artwork is allowed for roles that those requirements do not bind.

## 13. Submission self-check

- Verify each numbered requirement against the running game, including prohibited and boundary behavior.
- Check the full-sized maze and four personalities, not only the initial visible corridor.
- Exercise recovery, terminal states, active-effect Restart and a real process reopen.
- Confirm settings affect actual rendering/window state and that the high score persists.
- Keep every reported observation tied to real state and current visible controls.
- Report only checks actually run and list any unfinished requirement IDs.
