# Game Session Services

Contract revision: `game-session/v1`.

This contract describes chapter selection, in-memory save/restore, and scene identity for a
complete game. It is a delivery requirement only when the task manifest enables it.
The game must still work through its normal player controls from beginning to end.
No additional on-screen control is required unless the design document requests one.

The supplied C# package defines data types and interface signatures. It contains no game
mechanics. Implement one active `GameCreate.Session.IGameSession` component in the final
game scene. Your internal architecture, object names, rendering and storage remain yours.

## 1. Chapter entry

Publish the playable entry IDs declared in `SESSION_MODEL.json`. Opening an entry starts
that chapter with its documented normal state, using the same content and gameplay rules
as reaching it through the campaign. Entering a chapter must not disable damage, bypass
its own completion condition, replace enemies, or activate a separate simplified simulation.

Opening an entry replaces the previous session, including transient objects, listeners,
input buffers, pause, timers and overlays. It works from the menu, play, pause and result
states. Unknown IDs are rejected without changing the current game. A seed controls any
randomized layout; a game without randomness may ignore its value.

The request returns an operation object. It may complete immediately or across real Unity
frames. On completion, the scene, input, camera, displayed state and captured state agree.
Completed entry and restore operations leave gameplay suspended at the committed state.
`ResumeSimulation()` releases this loading suspension without changing the saved phase,
resources, actor state or pose. A saved paused game remains paused after release. Normal
menu Start works without using these services. Capture, UI rendering and operation polling
remain available while suspended; gameplay motion, damage and gameplay timers do not advance.

Requests must finish within the task's published operation timeout. Invalid schema and
identity requests are rejected immediately, before any state write. Overlapping requests
are rejected with `busy`; rejecting a request must not cancel or corrupt an accepted one.

## 2. Portable session state

Capture returns a detached, JSON-serializable save containing the content version, entry,
phase, declared numeric values, stable actor identities, actor poses and actor states.
Required names and ranges come from `SESSION_MODEL.json`. Coordinates are actual Unity
world coordinates. Actor IDs stay stable across capture, restore and chapter reload.

Capture does not advance the simulation, change gameplay, or keep mutable aliases to live
state. Mutating a returned save must not affect the game. Repeated captures within one
unchanged frame describe the same state. Save data cannot contain Unity object references.

Restore accepts a save produced by this content version, including legal edits to the
explicitly editable public fields. These edits describe an initial situation: chapter,
resources, progression and actor poses/states. The task specifies valid ranges and
cross-field rules. They do not invoke combat, grant a victory, or perform player actions.
Any opaque payload stores additional transient state; it must not silently override the
published editable fields. Fields not declared editable can be round-tripped but cannot
be invented or independently changed by a caller.

Restoring reconstructs the actual playable state and presentation. Active timing state,
input latches and pending events must be consistent with that saved state. An invalid
schema/content version, unknown required identity, duplicate identity, non-finite value,
out-of-range value or invalid cross-field combination is rejected without a partial write.
No disk persistence or automatic loading on process launch is required by this contract.

## 3. Scene identity and spatial description

The active scene exposes each declared actor's real root `GameObject` through its stable ID.
An actor absent from the current scene may resolve to null; an actor reported as present
must resolve uniquely to the actual gameplay object. A reporting proxy disconnected from
the player-visible actor does not satisfy the contract.

The entry description exposes its actual world bounds and named spatial landmarks from
`SESSION_MODEL.json`. Descriptions report the delivered layout; they do not prescribe how
it is constructed. A missing landmark must be reported missing, not fabricated off-screen.

## 4. Scope of acceptance

The service is part of the game, not a replacement for its controls or read-only dashboard.
Its outputs are required to match the rendered scene and subsequent player actions.
Returning `completed` with incorrect state is a service defect. Merely implementing the
interface signatures does not satisfy chapter entry or save/restore behavior.

Unavailable or incorrect required capabilities are incomplete delivery. This is judged
per capability and affected entry; unrelated working parts remain independently usable.
The provided format utilities and self-checks are optional development aids. They do not
implement the game and do not certify complete gameplay.
