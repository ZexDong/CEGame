# PolyRace Trials — complete multi-craft hover racing campaign

## Delivery
Build the full game and mandatory `game-session/v1` service. The service is part
of automated acceptance for chapter entry, legitimate save preparation and
real actor identity; missing/incorrect capabilities block affected acceptance.
Normal racing must not require service calls.

## Source and scope
Based on vthem/PolyRace's hover movement, distinct craft dynamics, boost,
collision shield, recovery, gates, terrain and finite race modes. This is a
bounded new three-track campaign with Time Attack and Distance Sprint,
not a reproduction of the procedural endless mode or original Blender models.
No AI opponents, network mode or third-party tween/noise libraries are needed.
All supplied meshes/palette assets are newly authored and redistributable.

## Rules
- PR-01: Title has Play, track/mode/craft selection, records and instructions.
  Three tracks in CONTENT.json contain road, rails, ascending/descending ramp,
  ordered gates, obstacles and collectible charge rings. Four visibly distinct
  hovercraft have the exact speed/acceleration/steering/hover/shield parameters.
  Every selection enters the selected real course, not a single shared plane.
- PR-02: Each race begins at (0,hoverHeight,2) with full shield, speed0 and a
  visible3s countdown. W/Up accelerates, S/Down brakes (no reverse), A/D or
  Left/Right steers laterally with visible craft yaw/bank. No forward movement
  before countdown ends. With no throttle speed decays by2/s to zero.
  Acceleration/braking and position depend on elapsed time, not frame count.
- PR-03: Left Shift boosts while held: max speed*1.4, acceleration*1.5 and visible
  exhaust/boost feedback. Releasing restores normal limits smoothly. Crucially,
  boost does NOT continuously drain shield: boosted COLLISIONS cost double.
  Brake deceleration is20/s. Steering moves x at vehicle.steering units/s,
  bounded by the rails at x=+-5.5. The craft hovers above the actual road/ramp
  height and follows its rise/fall rather than clipping through the terrain.
- PR-04: Visible spatial contact with a rail or uncollected obstacle applies the
  vehicle collision cost (double when boosting), slows speed to35%, and gives
  a shield/damage effect. A0.6s contact grace prevents damage every frame.
  Shield regenerates at the vehicle rate only after2s without contact, capped
  at capacity. At shield0 enter stable defeat; controls cannot keep racing.
- PR-05: A charge ring is collected only by actually crossing within0.9 units
  of its x/z position. It disappears once, grants100 points and restores10
  shield capped at capacity. It cannot be collected twice or from another lane.
- PR-06: Three gate planes per track at30%,60%,100% of length must be crossed
  in order from below along z while inside road width. Each visibly changes to
  passed and advances next_gate. Never finish just because elapsed time passes.
  Crossing the final gate after the first two wins; crossing it with missing
  gates does not. The race timer runs only after countdown and freezes on result.
- PR-07: Time Attack records the fastest successful time for that track/craft.
  Distance Sprint additionally requires finish before its content time_limit;
  expires to defeat if unfinished, and shows points=integer forward distance+
  collected bonuses. Both modes retain full movement/collision/gate gameplay.
  Track/mode completion bits and best successful records persist between
  processes. A fresh process opens title with saved records, not a live race.
- PR-08: Escape/visible Pause freezes vehicle, countdown/timer, collisions and
  pickups; Resume continues the same race. Retry from play/pause/result resets
  selected track/mode/craft to a fresh countdown/full shield and restores all
  obstacles/pickups/gates; no leftover velocity or duplicate craft.
  Next after a win moves to the next track (track3 -> campaign result);
  Menu returns to selection without duplicate UI/listeners.
- PR-09: Use the supplied angular craft meshes, a useful follow/overhead camera,
  readable road depth, distinct raised obstacles, illuminated ordered gates,
  visible charge rings and ramp silhouette. HUD shows track/mode/craft,
  speed/shield/time/gates/points and a clear countdown. Selection, boost,
  impact, pickup, pause, result and records have visible feedback. Audio may
  use synthesized signals; no external download is required.

CONTENT.json fixes track/craft tuning. Public save semantics are authoritative
in SESSION_MODEL.json. Internal classes and implementation architecture are free.
