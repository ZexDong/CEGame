# Open RTS: Economy, Production And Command

## 1. Task
Build an offline human-versus-AI 3D strategy match: gather two resources, construct a base, produce and command ground/air units, and destroy the enemy command centers while protecting your own (MAIN-01, ECON-01, BUILD-01, PROD-01, COMBAT-01, END-01).

## 2. Scope
Section 6 is the complete gameplay contract. Multiplayer, custom/skirmish setup, edge scrolling, camera rotation and enemy offensive-unit production are excluded.

## 3. Starting package
The runnable starter contains a visible notice, source models and read-only dashboard skeleton. Gameplay is absent. Scene and material paths are in TOOLCHAIN-en.md and the manifest.

## 4. Player journey
MAIN-01 Quick play → ECON-01 gather → BUILD-01 construct → PROD-01 produce → COMBAT-01 attack → END-01/02 result → LIFE-02 restart or LIFE-03 menu. Poor commands can lead to losing the last friendly base.

## 5. Player operations
Left click/drag and Shift select (SELECT-01/02); right click orders gathering, movement, attack or rally (ECON-01, COMBAT-01, RALLY-01). Worker controls choose blueprints; R rotates and right click cancels (BUILD-01/03). Factory controls add or cancel entries (PROD-01/02). WASD/wheel move the camera (VIEW-01); Ctrl+1–9 and 1–9 manage groups (GROUP-01). Home, I, F1 and Escape perform SHORTCUT-01 and LIFE-01.

## 6. Numbered requirements: sole gameplay acceptance contract

### 6.1 Reading the contract
Each row defines an observable result. Tables below are part of their named requirements. Unspecified damage, movement speed, health, construction duration and layout are implementation choices; ordinary play must permit both outcomes. Common delivery expectations are in COMMON_BASELINE.md.

### 6.2 Requirements

| ID | Preconditions and action | Required result | Forbidden result | Visible feedback and boundary |
|---|---|---|---|---|
| MAIN-01 | Launch, choose Quick play | Show a menu, then the fixed two-side Plain and Simple match | Require custom setup or hidden actions | Menu changes to 3D battlefield |
| MAIN-02 | Start or restart | Each side starts with one completed Command Center, two Workers, one Drone; player has 10 blue and 10 red resources | Retain prior units/resources | Initial units and HUD |
| MAP-01 | Enter match | Flat bounded ground 0–50 on both axes; friendly base (10,7), enemy base (40,43); blue/red deposits near each with reserves sufficient to build every structure/unit type | Block every route or change layout on restart | Ownership/minerals distinguishable; deposit arrangement is free |
| SELECT-01 | Left click friendly unit/building or empty ground | Select object and show health/context controls, or clear on empty ground | Control enemies | Selection marker |
| SELECT-02 | Drag; Shift-select | Rectangle selects friendly mobiles inside it; Shift adds/removes without clearing others | Select enemies or outside objects | Group markers |
| ECON-01 | Worker right-clicks blue/red minerals | Travel, gather, return to completed friendly Command Center and credit the correct resource; repeat | Credit before deposit or duplicate delivery | Movement and HUD update |
| ECON-02 | Source empty or no completed destination | Stop invalid gathering safely | Generate resources from nothing | Idle/unavailable state |
| BUILD-01 | Worker places valid affordable blueprint | Charge listed cost once, construct over visible nonzero duration, become usable on completion | Produce/fire while unfinished | Progress and completed appearance |
| BUILD-02 | Placement outside bounds, overlapping solids, or unaffordable | Reject without resource/object changes | Charge invalid placement | Invalid preview/reason |
| BUILD-03 | R or right click during preview | R rotates a quarter-turn; right click cancels without charge | Build on cancel | Rotated/removed preview |
| BUILD-04 | Selected building destroyed | Remove selection, controls, queues, minimap/fog presence; discard pending production without refund | Stale controls or post-destruction output | Other units remain controllable |
| PROD-01 | Unit chosen at completed compatible producer | Charge once, append FIFO entry, max five including active; produce after listed simulation time | Unfinished/incompatible production or sixth entry | Ordered queue/progress |
| PROD-02 | Click queued or blocked entry | Remove it and refund full cost once | Double refund or cancelled output | Queue/resources update |
| PROD-03 | Completed first ground entry has no free output space | Wait at front with blocked label; after space clears spawn once without charge, then continue | Lose/overlap output or pass later entries ahead | Automatic unblock |
| AIR-01 | Helicopter/Drone finishes | Spawn at flight altitude in free nearby in-bounds airspace; occupied airspace waits as PROD-03 | Aircraft overlap or remain stuck after clearing | Aircraft and queue update |
| RALLY-01 | Factory right-clicks ground/friendly unit | Set visible rally destination; new output moves there or toward living target | Move factory or change old unit commands | Destroyed target falls back to last valid position |
| COMBAT-01 | Mobiles right-click terrain | Move toward destination inside bounds; ground avoids solids, aircraft flies above terrain | Teleport or ignore a new valid order | Travel then stop |
| COMBAT-02 | Armed unit right-clicks supported visible enemy | Approach and attack with nonzero cadence; remove at zero HP | Damage friendly/unsupported targets | Attack, health and destruction |
| COMBAT-03 | Unsupported target/unarmed unit ordered to attack | Reject without damage | Worker/Drone attack or ground weapon damages aircraft | Movement remains usable |
| COMBAT-04 | Enemy enters completed turret range | Attack supported domain automatically | Fire unfinished or at unsupported targets | Distinct ground/air turret roles |
| AI-01 | Match progresses | Enemy may gather and build defenses; initial completed anti-ground turret covers its base approach | Produce offensive mobiles such as Tanks/Helicopters | Defensive construction/fire |
| AI-02 | Enemy economy left uninterrupted | Enemy Workers can advance and construct anti-ground defenses within range of friendly base, enabling defeat through ordinary play | Require debug controls to lose | Visible construction precedes damage; player can prevent it |
| END-01 | No completed enemy base remains, friendly base remains | Victory freezes match | Remaining non-command units prevent victory | Restart/Main Menu |
| END-02 | No completed friendly base remains | Defeat freezes match; priority on simultaneous final-base loss | Unfinished bases or surviving units prevent defeat | Restart/Main Menu |
| LIFE-01 | Escape during play/pause or Resume | Pause/resume preserving state and freezing simulation timers | Background orders/timers | Resume/Restart/Main Menu panel |
| LIFE-02 | Restart from pause/result | Clean MAIN-02 state; clear queues/groups/selection | Retain paused/result state | Fresh battlefield |
| LIFE-03 | Main Menu from pause/result | End match and return to menu; Quick play starts fresh | Background simulation | Usable menu |
| LIFE-04 | Close/reopen | Menu with no saved match | Resume unfinished match | Initial menu |
| VIEW-01 | Hold WASD, use wheel | Continuous pan, bounded zoom | Edge scroll or Q/E/middle-mouse rotation | Useful battlefield view |
| GROUP-01 | Ctrl+1–9 then 1–9 | Store selection and recall surviving members | Recall destroyed/enemy objects | Selection markers |
| SHORTCUT-01 | Home, I, F1 | Focus friendly base, cycle idle Workers, toggle controls help respectively | Select destroyed Workers | Camera/selection/help update |
| HUD-01 | Match state changes | Show resources, elapsed simulation time, mobile count, idle Workers, selected health, construction/queue progress, blocked output, events | Stale totals or progress during pause | Immediate readable changes |
| FOG-01 | Units explore | Hide enemies outside friendly vision; retain explored terrain; minimap shows currently visible enemy locations | Minimap reveals unseen enemies | Fog/minimap agree; radius is free |
| ART-01 | Battlefield visible | Use supplied model identities for Workers, Tanks, Helicopters, Drones, factories, turrets, minerals; assemble recognizable bases from supplied structures | Unrelated replacement identities | Ownership and ground/air distinction |

Prices and production values (BUILD-01, PROD-01, AIR-01):

| Item | Blue | Red | Duration | Producer |
|---|---:|---:|---|---|
| Worker | 2 | 0 | 3 s | Command Center |
| Tank | 3 | 1 | 6 s | Vehicle Factory |
| Helicopter | 1 | 3 | 6 s | Aircraft Factory |
| Drone | 2 | 0 | 3 s | Aircraft Factory |
| Command Center | 8 | 8 | Visible construction | Worker |
| Vehicle Factory | 6 | 0 | Visible construction | Worker |
| Aircraft Factory | 4 | 4 | Visible construction | Worker |
| Anti-Ground Turret | 2 | 2 | Visible construction | Worker |
| Anti-Air Turret | 2 | 2 | Visible construction | Worker |

Domains (COMBAT-02–04): Tank/Anti-Ground Turret attack ground units/buildings; Helicopter attacks ground/air; Anti-Air Turret attacks aircraft; Worker/Drone are unarmed.

## 7. Success and failure
END-01 is victory; END-02 is defeat including simultaneous final-base loss. Intermediate construction and production cannot trigger victory.

## 8. Interface
HUD-01 covers information, FOG-01 minimap/vision, SELECT-01/02 selection, BUILD-03 preview. Layout is free.

## 9. Lifecycle
LIFE-01 preserves paused state; LIFE-02 resets; LIFE-03 returns to menu; LIFE-04 discards match progress across process close.

## 10. Existing functionality
Reconstruction: no gameplay implementation is supplied.

## 11. Materials
ART-01 defines identities. Catalog lists paths, dimensions, dependencies and licenses. Terrain, selection circles, fog, projectiles and UI may be procedural.

## 12. Dashboard naming table and operations
The machine-readable table is the vocabulary. Ground coordinates are map x/z in [0,51); targets use viewport pixels. Visible entities carry stable instance `id`, `owner` (`friendly`, `enemy`, `neutral`), `hp`, `max_hp`, and `selected` where applicable. Omit hidden entities. These observations do not command gameplay.

| Slots | Meaning / source |
|---|---|
| `resource_a`, `resource_b` | Blue/red inventory, ECON-01 |
| `elapsed_seconds`, `unit_count`, `idle_workers`, `selected_hp`, `selected_max_hp` | HUD-01; absent selection is zero |
| `queue_length`, `queue_progress`, `output_blocked` | Selected queue count, first progress [0,1], blocked 0/1; zero without producer, PROD-01/03 |
| `friendly_command_centers`, `enemy_command_centers` | Completed-base counts, END-01/02; aggregate count does not locate hidden enemies |

| Entity kinds | Allowed states | Source |
|---|---|---|
| `command_center` | under_construction, complete | BUILD-01 |
| `worker` | idle, moving, gathering, constructing | ECON-01 |
| `tank`, `helicopter` | idle, moving, attacking | COMBAT-01/02 |
| `drone` | idle, moving | AIR-01 |
| `vehicle_factory`, `aircraft_factory` | under_construction, complete, blocked | PROD-01/03 |
| `anti_ground_turret`, `anti_air_turret` | under_construction, complete, attacking | COMBAT-04 |
| `resource_a_pile`, `resource_b_pile` | available, depleted | ECON-01/02 |

| Target kinds | Meaning / source |
|---|---|
| `quick_play`, `restart`, `main_menu`, `resume` | MAIN-01, LIFE-01–03 |
| `build_command_center`, `build_vehicle_factory`, `build_aircraft_factory`, `build_ground_turret`, `build_air_turret` | BUILD-01 blueprint controls |
| `produce_worker`, `produce_tank`, `produce_helicopter`, `produce_drone` | PROD-01 controls |
| `queue_entry` | PROD-02 cancellable entry; stable id and FIFO index |
| `unit_target`, `resource_target` | Visible world rectangles matching entity id; SELECT-01, ECON-01, COMBAT-02 |
| `battlefield` | Ground input area; BUILD-01, COMBAT-01 |

Section 5 and TOOLCHAIN-en.md define normal keyboard/mouse operations. Dashboard has no action endpoint.

## 13. Implementation boundaries
Scene architecture, node names, navigation, grouping and rendering details are free. Public technical contract defines entry, seed, transport and writable boundaries.

## 14. Requirement index
MAIN/MAP setup; SELECT/GROUP selection; ECON/BUILD/PROD/AIR/RALLY economy; COMBAT/AI/END interaction/outcomes; LIFE lifecycle; VIEW/SHORTCUT/HUD/FOG controls/presentation; ART identities. Definitions are exclusively in section 6.
