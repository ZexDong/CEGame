# Read-only observation contract

This interface implements OBSERVATION-01, including the boundary clauses in GDD
Section 6.4. The JSON schema requires schema_version="bonemaze-observation-1.0.0"
to identify the runtime data format. Phase, identity and publication meanings follow.

## Single interface

Launch with optional -ObservationPath=<absolute-output-file>. The default is
starter-project/Saved/Benchmark/state.json. Publish a complete UTF-8 JSON document on a nominal
0.1-real-second interval, including in menus, pause and terminal states. A due publication
may wait until the next rendered frame; no extra intentional delay is allowed. Atomically
replace the file from a temporary sibling. Each live process uses a different path.
Reading/publishing a snapshot never changes the world, random stream or simulation.

The file contains exactly one complete JSON object, not JSON Lines. Compact and
indented formatting, LF/CRLF, an optional trailing newline and an optional UTF-8 BOM
are equivalent. Property/array order has no meaning. Integer fields contain integral
numeric values; all numbers, including nested attributes, must be finite. Property
names in each object are unique. Whitespace is not readiness or a publication.

An unwritable path produces a logged observation I/O error. Readers retry transient
sharing conflicts for up to 1 second and otherwise report the I/O fault. Never treat
an old file as readiness: bind the process_id/session_id, increasing snapshot_id and
file modification freshness (no more than 1 second old during active use).

## Identity and schema

contracts/observation.schema.json defines shape. naming-tables.json defines names,
allowed phases/states, units, coordinate conventions, controls and seed input.

- session_id is unique to the process; process_id identifies that publishing process.
- round_id changes on every new run/Restart; a menu without a run has a separate ID.
- snapshot_id starts at 1 and increases each publication, including unchanged state.
- monotonic_seconds is a monotonic real clock. simulation_seconds is round-active
  time, frozen during pause and terminal states and reset for a new round.
- slots contains the 16 named integer values from the naming table. Hidden monster
  coordinates are observation truth, not a requirement to reveal them in the HUD.
- entities contains persistent IDs for all rooms, gates, pickups, the mage, monster,
  final portal and currently active important effects. IDs are never reused for a
  different entity in one session. Hidden rooms/consumed pickups remain observable
  with visible=false; this transport is not a player cheat UI.
- targets contains only actual player controls and current-room interactions.
  visible/interactable and normalized rect reflect the current client view, including
  occlusion and disabled controls. No invisible click target or offscreen answer action
  is exposed. World interactions may report a target rect for movement guidance;
  passage entry still uses movement and gates still use E, as specified by the GDD.

## Phase and boundary meanings

These are semantic observations of the GDD's existing states, not a required internal
state-machine design. A snapshot never combines inventory from one round with rooms,
targets or effects from another.

| Phase | Meaning and observations |
| --- | --- |
| not_ready | The unfinished health screen or initial startup before a usable menu. All 16 slots are zero and entities/targets are empty. It is not a completed menu or a playable round. |
| menu | No active round. All slots, including round_seed, are zero; entities is empty. Targets describe the visible difficulty, Exit and seed controls. The selected menu seed is represented by seed_input attributes.value as its actual text, not by a fictitious round. |
| exploring | A live room accepts normal movement and local actions. Casting or an opening gate can coexist with exploration. Slots describe the actual current room/resources, and all persistent round entities remain represented. |
| transition | One accepted crossing is in progress. room_changes increases once on completion, including an encounter-producing crossing. room_x/room_y describe where the mage actually is at that sample, changing together with its entity cell and scene. No fabricated intermediate room or extra crossing is reported. |
| recovering | A nonfatal encounter has already reduced lives and the mage is returning to start. Report the actual current room until the return is made, then start. Recovery changes no passage count; the monster entity retains its ID through any safety relocation. |
| paused | A live round is suspended, including any interrupted transition/recovery. Resources, positions and gameplay timers retain their interrupted values. Entity action states may retain that interrupted state; the phase identifies the suspension. UI target visibility reflects the actual pause view. |
| won / lost | A round has reached its fixed result. Keep the round, maze and persistent entities observable; won shows the final portal completed, lost shows zero lives and the dead mage. Transient result presentation may finish/remove its effect entities. Gameplay time and resources remain fixed. |

simulation_seconds starts at zero with a new round and advances through exploration,
transition and recovery. It stops in paused/won/lost and is zero outside a round.
monotonic_seconds is process-local elapsed real time from a monotonic clock; its
absolute origin is free. It and snapshot_id continue during pause/results. A new
round does not reset snapshot_id, and a new process may restart it at 1.

A new round assigns fresh entity IDs, even when its seed recreates identical rooms.
Returning to menu assigns a new menu round_id, clears all run entities and targets,
and publishes menu controls only. A paused/result round keeps its round_id. Ending a
transient effect removes its entity; that ID cannot later identify a new effect.
Reordering arrays or hiding/unloading a room never changes its persistent identity.

## Entity semantic attributes

Attributes describe live public concepts. They never contain verdicts or commands.
The following mapping makes the required state inspectable without internal names:

| Kind | Mapping |
| --- | --- |
| room | cell=[x,y]; state is its role; attributes.layout_id identifies the selected visual arrangement. attributes.exits contains four entries with slot (north/east/south/west), destination_cell, destination_slot and optional gate_id. Slot names are room-local identities, not screen directions or geometric adjacency promises. |
| player | cell is the current room; optional position/local_position aid continuous motion. attributes.revealed_cell and reveal_remaining_seconds describe only the currently visible spell reveal. |
| monster | cell is its true room, state hidden or manifesting. Its ID survives room changes and recovery within a round. |
| gate | attributes.key_color is red/green/blue; connection_id is a stable public connection identity; opening_remaining_seconds reports current animation time; cell identifies one side. One shared gate entity may serve both exit references. |
| pickup | attributes.pickup_kind is coin/scroll/heart/key; key_color is present for keys; cell identifies its room. available/consumed reflects actual persistence. |
| exit | cell identifies the final portal room; locked/ready/completed is its actual state. |
| effect | attributes.effect_kind is spawn/cast/transfer/hit/pickup/win/lose; optional owner_id identifies its affected entity. Remove ended transient effects. |

For a live round, cell is required on room/player/monster/gate/pickup/exit entities.
The named attributes in the table are required except those explicitly called optional.
For an unrevealed player, revealed_cell is absent and reveal_remaining_seconds is 0;
when revealed, the cell is the sampled coordinate pair and the remaining time is
positive and at most 3. An opening gate reports its remaining time in 0..3, with a
positive value while opening and 0 in all other states. locked means the required
key is missing; closed means the matching key is owned but E has not started opening.
Gate state cannot revert from open during a round. A gate cell is one stable endpoint;
its shared entity may be visible from the other endpoint without changing that cell.

Each room exit entry names a room-local slot, a valid destination_cell and its paired
destination_slot. gate_id is present exactly when that connection is gated. Both
ends refer to the same gate entity and its stable connection_id. A room's layout_id
describes its arrangement identity, not a file path or a required generated layout.
Pickup key_color is required for a key and absent for non-key items. Consumed pickups
remain in entities with consumed state and visible=false, retaining their room/ID.
The final portal is locked without all keys, ready with all keys before victory, and
completed after victory. Its presence alone does not assert a win.

visible describes actual on-screen presentation, not whether an object exists in
memory. An offscreen/occluded object may omit its optional rect; a provided rect is
the clipped client rectangle, or [0,0,0,0] when not visible. A currently shown room is
visible while hidden rooms are false. Pausing does not falsely mark fully covered
world objects visible. position/local_position remain optional; they never prescribe
an internal actor origin. World position uses UE centimetres; local_position measures
right/forward across that room's floor bounds, with zero at each axis's minimum edge.

Targets use the same normalized [left,top,width,height] convention. Visible targets
have nonzero rectangles entirely inside the current client. Hidden targets may be
omitted or have visible=false, interactable=false and a zero rect. A disabled visible
button is not interactable. World targets reference their entity_id: gate uses the
shared gate entity, passage the room containing its threshold (attributes.slot names
the local slot), and final_portal the exit entity. A gate is interactable when E can
produce an in-range response, including a missing-key rejection. A passage is
interactable only when crossing is currently allowed; a final portal may be
interactable while locked because entry produces its rejection response. In paused,
transition, recovery and result phases, world targets are not interactable. Seed
input attributes.value is a string and preserves invalid text while it is being edited.

Arrays and IDs have no required order. Candidate-specific object names, C++ classes,
Blueprint paths and hidden fixture hooks are not part of this contract. The full room
graph is a read-only description, never a means to change links or teleport the player.

## Starter and self-check

The unfinished starter reports not_ready, zero slots and empty entities/targets. Its
starter_health.input_pulses counts a Space input diagnostic only. Replace the unfinished
mapping with actual live game state during implementation; the Space probe may be removed.

Run <python> tools/check_observation.py <snapshot.json>. Optional --previous <file>
checks identity/time progression; --max-age 1 rejects a stale file. Exit 0 means
conformant format, 1 means invalid data, and 2 means usage/I/O failure. Output is JSON.
The checker is passive. It checks generic JSON/schema fields and identity/range
consistency, not complete entity coverage, connection reciprocity, live-world truth,
gameplay or visual correctness. A conformant report does not certify those outcomes.
Use actual input and simultaneous state/on-screen observations to assess them.
