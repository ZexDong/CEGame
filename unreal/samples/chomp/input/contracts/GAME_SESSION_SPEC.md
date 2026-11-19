# Read-only observation contract

This observation contract maps GDD Section 6, principally OBSERVE-01. It is not a second gameplay specification. It prescribes no internal class, node, actor name or pathfinding structure. The engine fixture health schema is a separate engine capability probe and is not the Chomp schema.

## Transport

When `-ChompStatePath=<absolute-output-file>` is supplied, publish atomic UTF-8 JSON snapshots at least every 0.10 seconds while the process is responsive, including menus, pause and terminal screens. Write outside the protected input. Without this argument, observation may be disabled. Each snapshot follows `game-state.schema.json` and sets `schema_version` to `"1.0.0"`.

`process_id` is the real OS PID. `process_token` is a nonempty process/session token; a new process cannot reuse an old token. `snapshot_id` increases for each publication in the current world, and may reset only with a changed token. `monotonic_ms` is monotonic host time. `first_frame` becomes true only after drawing a real viewport frame. `bridge_ready` means the transport is initialized; `provider_ready` means an actual game observation is available. The untouched starter truthfully reports false/null for provider/game state, not fabricated zero-filled gameplay.

The supplied `UObservationTransport` is an optional outbound serializer. Its `PublishObservation(StateJson)` accepts the implementation's current observations only and never modifies its world. `NotifyFrameDrawn()` records a drawn frame. A completed HUD or viewport integration calls that after its first draw; the welcome HUD already does so. Replacing this transport is allowed if the same output contract is met. There are no commands, input files, fixture hooks, pass/fail fields or gameplay setters in the transport.

## Semantic mapping

| Fields | Meaning and GDD source |
|---|---|
| phase, run_id, life_index | menu/options/playing/paused/dying/won/lost; a fresh run changes run_id, recovery increments life_index (FLOW, LIFE, PAUSE, SAVE) |
| score, high_score, lives, extra_life_progress | Actual earned score, persistent best, current lives and accumulated points toward the next life (DOT, POWER, CAPTURE, LIFE, FRUIT, SAVE) |
| ordinary_consumed, ordinary_remaining, energizers_remaining | Real pickup counts, consistent with the listed remaining cells (DOT-01, POWER-01, FLOW-03..04) |
| player, ghosts | Actual positions, facing, movement/state and visible screen bounds; ghost intent_cell is the current semantic destination, not a path or algorithm (MOVE, GHOST, CAPTURE, VISUAL) |
| ordinary_cells, energizer_cells | Remaining pickups only; no stale destroyed entries (DOT-01, POWER-01) |
| fruit | Presence, F cell when present, thresholds already used or skipped, and remaining lifetime (FRUIT-01..02) |
| timers | Normal underlying wave, zero-based wave index, remainder, frightened/inactivity/death remainders; endless chase has null wave remainder (GHOST-03..04, POWER, LIFE, TIME) |
| active_seconds, seed | Run time excluding paused/menu/death time and the effective random seed (TIME-01, QUALITY-06) |
| targets | Actual menu widgets/regions, current labels and usability; not predicted coordinates (FLOW, MENU, OPTIONS, PAUSE) |
| settings | Actual applied values and pending selections in Options; pending is null elsewhere (OPTIONS-01..03) |
| hud, effects | Actually displayed text/icons and current camera/fruit effects (HUD, VISUAL-05, LIFE, FLOW) |
| viewport | Actual client pixel dimensions, excluding OS title bar (HUD-01, OPTIONS-03) |

All board coordinates use Figure 6A: x is column, y is row. `position` allows subcell motion and the half-cell seam interval during wrapping. `cell` is the nearest board cell center, modulo only at the specified wrap pair. `screen_rect` and menu `rect` are normalized client-view top-left x/y and width/height; return null when no visible rectangle exists. Keep x+width and y+height at most 1.0 after clipping. `visible`, `enabled` and `topmost` describe actual state; an obscured control cannot be topmost. Disabled controls remain listed if drawn. No private object names are required.

The ghosts array uses each semantic color ID once when a run exists; all four remain represented while waiting, returning, dying or frozen. The arrays of remaining pickups have no duplicate cells. At the main menu, including after leaving a run, run_id/player are null, ghosts/pickup arrays are empty, run counters are zero, and high_score/settings still report saved state. In Options from pause, retain the paused run and set options_origin to paused. Moving through menus does not claim a new run.

`-ChompSeed=<integer>` selects reproducible random choices; default 1337. It is an initialization parameter only, not a cheat. Identical seed and action timing reproduce tie/random choices. Deterministic implementations can report the supplied seed without consuming randomness. The seed does not change the board, speed or difficulty.

The public `tools/Test-Observation.ps1 -Path <snapshot>` validates JSON Schema and basic cross-field consistency. Success means that the record is structurally valid, not that gameplay is correct. Input receipts and contemporaneous game images remain necessary to verify behavior and honesty.

## Precise field semantics

The fields map GDD Section 6, including its Section 6.4 boundary definitions. Fields below report actual state; they do not supply behavior or require a particular class layout.

| Field | Meaning, initial value and lifecycle |
|---|---|
| run_id | Nonempty identity unique to each Start/Restart within a process. Preserve it through pause, Options, death and recovery; clear it on Main Menu. A new process has a separate process_token. |
| life_index | Number of completed nonfinal life recoveries in this run. It starts at 0, increments once on actual respawn, and is unchanged by damage, extra lives or pause. Reset to 0 on Restart or Main Menu. |
| active_seconds | Starts at 0, accumulates only in playing, and survives life recovery. It is frozen in options/paused/dying/won/lost and is 0 with no run. |
| capture_chain | Number of successful captures in the current continuous frightened period: 0 before any capture, 1 after the first, 2 after the second. It is not a score or multiplier. Reset at fright expiry, death and new run; preserve on refresh and freeze on victory. |
| extra_life_progress | Actual earned points counted toward LIFE-04 since its last reset. It may exceed 2000 at three lives; it is 0 after an extra-life grant, recovery or new run. Report the actual permitted retained value, without inventing a grant. |
| ordinary_consumed / ordinary_remaining | For a run, the number of cleared and present ordinary dots; their total is 299. At Main Menu both are 0 and the lists are empty. Energizers, captures and fruit do not change these counters. |
| player.cell / ghosts[].cell | Nearest board cell center; exact halfway ties use the entered cell in travel direction. Wrap only at the specified pair. A stopped actor keeps its last unambiguous cell. |
| player.heading | Last nonzero facing during a run, including when stopped or dying. Initial and recovered facing is right. The unused enum value none is not a replacement for a known player facing. |
| player.mouth_open / empowered | Whether the displayed mouth has an open aperture, and whether the player currently has an active frightened opportunity. They must describe the actual displayed/state condition; hidden death/terminal visuals need not fabricate a visible mouth. |
| ghosts[].state | waiting before initial release; leaving while travelling out of home; returning while a captured ghost travels home; otherwise normal or frightened while roaming. Terminal/death snapshots may retain a stopped ghost's last displayed state; phase indicates that movement and contact resolution have stopped. |
| ghosts[].intent_cell | The current semantic destination: null while waiting; R while leaving; its own home while returning; its currently selected corner/pursuit target while normal; the selected legal next center while frightened. Freeze the reported actual intent while paused or terminal. A roaming ghost with a destination cannot hide it as null. No path or private object name is reported. |
| fruit.present / cell / remaining_seconds | While present, cell is F and remaining_seconds is positive, at most 10; once absent, cell is null and remaining_seconds is 0. Do not retain an expired fruit for one more pickup. |
| fruit.spawned_thresholds | Unique values in ascending order. Record 70 or 170 once the opportunity has been reached, including a skipped opportunity because fruit was already present. Preserve through life recovery; clear on a fresh run. The name includes spent/skipped opportunities and does not mean two successful spawns. |
| timers.wave_mode / wave_index | Underlying normal schedule even during fright: indices 0..7 have Scatter, Chase, Scatter, Chase, Scatter, Chase, Scatter, Chase. Index 7 is endless Chase. A fresh/recovered life has scatter/0. With no run use none/0. |
| timers.wave_remaining_seconds | 0..5 in a finite wave, suspended during fright/pause/death; null in endless Chase or with no run. At a wave transition the next finite wave starts with 5. |
| timers.frightened_remaining_seconds | 0 when inactive, otherwise positive and at most 5. Refresh restores 5. Death clears it. Pause freezes it. A won run freezes its terminal value. |
| timers.inactivity_remaining_seconds | Time until the next forced initial departure, 0..5, while at least one ghost is waiting; 0 when no ghost waits or no run exists. Pause/death/terminal phases freeze an applicable countdown. Recovery resets it to 5 if ghosts still wait after threshold eligibility is applied. |
| timers.death_remaining_seconds | 0 outside dying; otherwise remaining time to the 3-second deadline measured from lethal contact. On final death a completed transition to lost sets it to 0. Restart immediately clears it. |
| options_origin | menu or paused only when phase is options; null otherwise. Options from pause retains the same run, characters and timers. |
| settings.applied / pending | applied is the last applied and saved logical selection. pending is the current editable selection object throughout Options, even when identical to applied; null outside Options. A temporary launch viewport override changes viewport but not applied. |
| viewport | Actual current physical client size. It can differ from settings.applied.resolution during a launch override or a resize in progress. After a successful Options Apply, it agrees with the selected supported mode/size. |
| targets | Unique semantic IDs for currently available/drawn controls; labels, rectangles and enabled/topmost flags describe the actual UI. Disabled drawn controls remain listed. Hidden controls may be omitted or listed with visible=false and rect=null. The dying Restart control uses the existing restart ID. |
| hud | Actual displayed score string and life-icon count; an absent score label uses an empty string, and hidden life icons use 0. result_title is empty off a result screen and contains the visible winning/losing heading on it. new_record is true only while that indication is displayed for a run that exceeded its pre-run saved best. |
| effects | Whether the camera impulse or fruit overlay is actually presented now. A paused visible fruit overlay can remain true while its duration is frozen. Restart/Main Menu clear run effects. |

A ready implemented game publishes provider_ready=true with a valid game_state in every phase, including the initial title menu. provider_ready=false/game_state=null is reserved for the unimplemented starter or an actual provider failure; it is not the representation of an empty main menu.

At Main Menu, including after abandoning a run, run_id and player are null; ghosts and both pickup lists are empty; run counters, life_index, active_seconds and remaining non-wave timers are 0; fruit is absent with no spent thresholds; wave_mode is none and wave_remaining_seconds is null. High Score and applied settings retain their saved values. Options entered from this menu keeps that empty run state.

On a fresh run, the first ready game snapshot records FLOW-02's state before motion, with life_index=0, capture_chain=0, extra_life_progress=0, active_seconds=0, scatter wave 0 with 5 seconds remaining, fright/death timers 0 and inactivity 5. Later snapshots report current state rather than replaying that initial snapshot. No extra ready/go phase or countdown is required.

The process_token is opaque: it may change when an observation publisher is recreated, including a world change, but cannot be reused by a later process. snapshot_id is strictly increasing for a token and may restart only with a new token. run_id carries Start/Restart identity and cannot be inferred solely from process_token. Never use token changes to disguise stale observations.

The output publisher must continue at the required rate while gameplay is paused. Time stopping in the game does not permit the observation stream to stop. JSON files are atomic complete observations; readers may miss intermediate publications and must not assume every frame is sampled. Zero remaining time at the exact deadline is a transient boundary, not an extension of an active power or fruit opportunity.
