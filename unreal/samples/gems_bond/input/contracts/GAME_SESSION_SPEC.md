# Read-only observation contract

This interface reports the game state defined in GDD Section 6. It exposes no command,
input, fixture loader, state setter or result shortcut.
It neither fixes the candidate's class/object names nor supplies gameplay implementation.

## Interface and transport

Launch with optional `-ObservationPath=<absolute-output-file>`. Default output is
`starter-project/Saved/Benchmark/state.json`. Use a separate output file per running process.
The game publishes a complete UTF-8 JSON snapshot at least every 0.1 real seconds,
including during pause and defeat. Write a temporary sibling and replace the destination
so readers never parse a half-written document. Snapshots are passive observations;
reading, publishing or validating one never advances simulation or changes game state.

An unwritable output is a logged observation I/O error, not a gameplay action. Readers
retry transient sharing conflicts for up to 1 second and otherwise report the I/O error.
An old file is not proof that the currently launched process is ready. Bind process_id,
session_id and increasing snapshot_id; reject a file older than 1 second during active use.
The file modification time and monotonic clock are freshness evidence, not simulation time.

## Identity and fields

`contracts/observation.schema.json` defines the shape. `naming-tables.json` defines semantic
slot names, phases, entity states, target kinds, controls and coordinate conventions.

- `session_id` changes on a new process. `process_id` is the publishing process's PID.
- `round_id` changes for every Restart. Old entity IDs are never reused in the same session.
- `snapshot_id` starts at 1 and increases per publication; it is a heartbeat sequence.
- `monotonic_seconds` uses a monotonic real clock. `simulation_seconds` is elapsed time
  in this round; it stops during pause/defeat and resets on Restart.
- `phase` is preparing, countdown, combat, rest, paused or defeated in the completed game.
  `not_ready` is reserved for the truthful unfinished starter.
- `slots` reports the current values used by simulation and HUD, with the units/meaning
  in the naming table. Counters and prices are integers; health and timers can be fractional.
- `entities` reports current crystal, deposits, buildings, enemies, projectiles and visible
  transient feedback. Each has a lifetime ID, kind, state, and its ground-plane position.
  Grid-bound objects also have cell. Health-bearing entities report health/max_health;
  towers and enemies report tier. A destroyed crystal may remain with state destroyed.
  Deposits remain present with state occupied while their mine exists; their shared cell
  does not mean a second build slot. Corpses use state dead, health zero, and are excluded
  from living/remaining counters. A cosmetic effect uses kind feedback, not a living enemy.
- `targets` reports actual visible player controls and board cells using normalized
  game-client rectangles. World inspect targets refer to entity_id. Board-cell targets
  include cell. Disabled or UI-occluded targets are not interactable. Do not expose an
  invisible clickable target, offscreen hit region or internal answer action.

Optional `attributes` on entities can report public semantics: placement_price,
upgrade_price, refund, damage, cooldown_remaining_seconds, range_units,
splash_radius_units, payout_remaining_seconds, attack_remaining_seconds,
target_id, owner_id, launch_damage, flying, selected or feedback_amount.
These are live state values, not assertions that a requirement passed.
Entity state and target metadata reflect the current view, including occlusion and
pause. Exclude decorative foliage and editor actors from this observation surface.

## Phase semantics

GDD Section 6.2.4 defines the phase/counter matrix. Preparing, countdown, combat and rest
are unpaused gameplay phases. In paused, preserve the interrupted phase's wave, counters,
positions, health and remaining timers; only phase, speed and visible UI targets change.
In defeated, report the terminal damage/death result and then freeze gameplay values.
Never clear wave_total or wave_spawned just because phase changed to paused or defeated.
Speed is 0 in both. The HUD and slots use the same preserved values. Counts exclude corpses.
Defeat may finish cosmetic feedback as allowed by GDD 6.2.8, without changing gameplay.
Snapshot sequence and real-time freshness continue while simulation_seconds is frozen.

Reset wave_total and wave_spawned to zero on entering a new countdown, preparation or rest.
During combat, enemies_remaining = wave_total - wave_spawned + enemies_alive, including
unspawned enemies; the same relation holds for preserved pause/defeat values. countdown_seconds
is zero in preparation/combat, the remaining countdown in countdown/rest, and preserved
on pause/defeat. A wave-clear snapshot presents the next countdown consistently; no mixed
old enemy counters and new wave index. Restart resets the sequence of seeded choices and
all run values, while session_id stays fixed, round_id changes and snapshot_id keeps increasing.

Report each entity's ground-projected center in the public cell coordinate system, plus
height in cell units. Entry positions outside 0..19 are valid positions but never valid
build cells. Rectangles describe only the currently visible client area; board cells hidden
by UI and disabled controls are not interactable. Omit fully offscreen inspect targets.
No internal implementation names, invisible action targets or evaluation verdicts belong here.

The starter reports not_ready, zero slots and empty gameplay arrays. Its optional
starter_health.input_pulses is a Space-key diagnostic, unrelated to game progress.
Replace the unfinished mapping with actual gameplay state; this health probe may be removed.
Do not manufacture completed values to make the format checker pass.

## Self-check

`<python> tools/check_observation.py <snapshot.json>` checks shape, finite values,
names, coordinate bounds, IDs and references. Optional `--previous <snapshot.json>`
checks the next snapshot's identity/time ordering. Optional `--max-age 1` rejects stale files.
Exit 0 means conformant format, exit 1 means a readable validation failure, exit 2 means
an I/O or usage error. The checker prints a JSON report and never edits the game/file.
This is a format check, not evidence that gameplay, rendering or the reported state is correct.
