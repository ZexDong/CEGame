extends RefCounted

## FourShot adapter uses only public dashboard entities/rectangles and normal
## keyboard/mouse input. It contains no room coordinates, obstacle map, node
## names, or candidate method calls.
var _last_combat_goal := Vector2.ZERO
var _last_special_screen := Vector2.ZERO
var _evasion_step := 0
var _evasion_positive := true
var _level6_rooms: Array = []

# Aim discipline for the single special-sniper shot (RULE-03i / RULE-13d): the
# projectile follows the last nonzero WASD heading, so the evaluator only
# releases the shot from a published horizontal or vertical alignment.
const AIM_TOLERANCE := 16.0
const SHOT_MIN_DISTANCE := 55.0
const SHOT_MAX_DISTANCE := 600.0

func movement_key(delta: Vector2, _state: Dictionary) -> String:
	if absf(delta.x) >= absf(delta.y): return "D" if delta.x > 0 else "A"
	return "S" if delta.y > 0 else "W"

func _player(driver) -> Vector2:
	for e in driver._state().get("entities", []):
		if e.get("kind", "") == "player":
			var c: Array = e.get("cell", [0, 0]); return Vector2(float(c[0]), float(c[1]))
	return Vector2.ZERO

func _selected_entity(driver, selector: Dictionary) -> Dictionary:
	var chosen: Dictionary = {}
	var best := INF
	var origin := _player(driver)
	var progress := int(driver._state().get("slots", {}).get("objective_progress", 0))
	for e in driver._state().get("entities", []):
		if e.get("kind", "") != selector.get("kind", ""): continue
		if selector.has("state") and e.get("state", "") != selector["state"]: continue
		# Objective 5 explicitly requires a DIFFERENT target. Its public active
		# state is the semantic distinction; array order is never an identity.
		if selector.get("kind") == "training_target" and progress >= 4 and e.get("state") == "complete": continue
		var c: Array = e.get("cell", [])
		if c.size() != 2: continue
		var distance := origin.distance_to(Vector2(float(c[0]), float(c[1])))
		if e.get("state", "") == "boss": distance += 100000.0
		if distance < best:
			best = distance
			chosen = e
	return chosen

func _entity(driver, selector: Dictionary) -> Dictionary:
	var e := _selected_entity(driver, selector)
	if e.is_empty(): return {"found":false}
	var c: Array = e["cell"]
	return {"found":true,"position":Vector2(float(c[0]), float(c[1]))}

func _target_rect(driver, selector: Dictionary) -> Dictionary:
	# Movement supplies firing direction; mouse location is irrelevant to aim.
	# Any visible target rectangle of this semantic kind is a valid fire click.
	var fallback: Dictionary = {"found":false}
	for t in driver._state().get("targets", []):
		if t.get("kind", "") != selector.get("kind", "") or not t.get("visible", false): continue
		var r: Array = t.get("rect", [])
		if r.size() != 4 or float(r[2]) <= 0.0 or float(r[3]) <= 0.0: continue
		var position := Vector2(float(r[0])+float(r[2])*0.5, float(r[1])+float(r[3])*0.5)
		# Callers may ask for a published semantic state (for example the boss
		# among several `enemy` targets).  FourShot's naming tables declare a
		# target's states under `entities`, so a published target may legitimately
		# carry no state; the exact match is tried first and the kind remains a
		# valid fallback, matching the driver's target resolution rule.
		if selector.has("state") and str(t.get("state", "")) != str(selector["state"]):
			if not bool(fallback.get("found", false)):
				fallback = {"found":true,"position":position}
			continue
		return {"found":true,"position":position}
	return fallback

func _world_fire(driver, selector: Dictionary) -> bool:
	var target := _target_rect(driver, selector)
	if not bool(target.get("found", false)): return false
	return await driver._inject_click_point(target["position"])

func _axis_key(delta: Vector2, axis: int, invert := false) -> String:
	var positive := (delta.x > 0.0) if axis == 0 else (delta.y > 0.0)
	if invert: positive = not positive
	return ("D" if positive else "A") if axis == 0 else ("S" if positive else "W")

func _move_step(driver, key: String, seconds := 0.12, goal := Vector2.ZERO) -> bool:
	var before := _player(driver)
	await driver._inject_key(key, seconds)
	var after := _player(driver)
	if goal == Vector2.ZERO: return after.distance_to(before) > 1.0
	return after.distance_to(goal) + 1.0 < before.distance_to(goal)

func _face(driver, selector: Dictionary) -> bool:
	var e := _entity(driver, selector)
	if not bool(e.get("found", false)): return false
	var delta: Vector2 = e["position"] - _player(driver)
	if delta.length() < 1.0: return false
	var axis := 0 if absf(delta.x) >= absf(delta.y) else 1
	return await driver._inject_key(_axis_key(delta, axis), 0.04)

func _route_to(driver, selector: Dictionary) -> Dictionary:
	if str(selector.get("kind", "")) == "training_target":
		return await _route_training(driver, selector)
	# Feedback loop: repeatedly read public positions, try the dominant axis,
	# and change to the perpendicular axis when actual displacement is blocked.
	var deadline := Time.get_ticks_msec() + 45000
	var alternate := false
	var trace: Array = []
	var combat_route := str(selector.get("kind", "")) == "enemy"
	var starting_enemies := _enemy_count(driver)
	var route_steps := 0
	while Time.get_ticks_msec() < deadline:
		if combat_route and (driver._state().get("phase", "") == "lost" or _enemy_count(driver) < starting_enemies):
			return {"ok":_enemy_count(driver) < starting_enemies,"trace":trace}
		var e := _entity(driver, selector)
		if not bool(e.get("found", false)):
			return {"ok":combat_route and _enemy_count(driver) < starting_enemies,"trace":trace,"reason":"target_missing"}
		var delta: Vector2 = e["position"] - _player(driver)
		if combat_route: _last_combat_goal = e["position"]
		var ax := absf(delta.x); var ay := absf(delta.y)
		if combat_route and delta.length() < 150.0:
			if int(driver._state().get("slots", {}).get("bombs", 0)) > 0:
				await driver._inject_key("Space")
			var retreat_axis := 0 if ax >= ay else 1
			var retreat_key := _axis_key(delta, retreat_axis, true)
			var before_retreat := _player(driver)
			await driver._inject_movement_dash(retreat_key)
			if _player(driver).distance_to(before_retreat) < 8.0:
				var side_axis := 1 - retreat_axis
				var side_delta := Vector2(1.0 if _evasion_positive else -1.0, 1.0 if _evasion_positive else -1.0)
				await driver._inject_movement_dash(_axis_key(side_delta, side_axis))
				_evasion_positive = not _evasion_positive
			continue
		# Stand outside the target but inside the documented shot range; this also
		# guarantees the final movement key supplies the firing direction.
		if (ax <= 12.0 and ay >= 55.0 and ay <= 180.0) or (ay <= 12.0 and ax >= 55.0 and ax <= 180.0):
			return {"ok":await _face(driver, selector),"trace":trace}
		# Once one axis is aligned, close or open distance along the other axis.
		# Otherwise remove the smaller offset first to establish a cardinal line.
		var neither_aligned := ax > 12.0 and ay > 12.0
		var axis := 1 if ax <= 12.0 else (0 if ay <= 12.0 else (0 if ax < ay else 1))
		var on_axis_distance := ay if axis == 1 else ax
		var key := _axis_key(delta, axis, on_axis_distance < 55.0)
		var align_step := 0.04 if neither_aligned else 0.12
		var goal: Vector2 = e["position"]
		if combat_route and route_steps % 4 == 0:
			await driver._inject_movement_dash(key)
		if await _move_step(driver, key, align_step, goal):
			trace.append({"key":key,"moved":true})
			if combat_route:
				route_steps += 1
				# Movement establishes the candidate's eight-way firing direction.
				# Fire while navigating so a moving hostile cannot kill the player
				# during a long alignment attempt.
				await _world_fire(driver, selector)
				if delta.length() <= 72.0 and int(driver._state().get("slots", {}).get("bombs", 0)) > 0:
					await driver._inject_key("Space")
				await driver.create_timer(0.16).timeout
			continue
		alternate = not alternate
		var detour_axis := 1 - axis
		var detour := _axis_key(Vector2(1.0 if alternate else -1.0, 1.0 if alternate else -1.0), detour_axis)
		await _move_step(driver, detour, 0.18, goal)
		trace.append({"key":key,"moved":false,"detour":detour})
		if combat_route:
			await _world_fire(driver, selector)
	return {"ok":false,"trace":trace,"reason":"feedback_timeout"}

func _route_training(driver, selector: Dictionary) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 20000
	var trace: Array = []
	var detour_positive := true
	while Time.get_ticks_msec() < deadline:
		var e := _entity(driver, selector)
		if not e.get("found", false): return {"ok":false,"reason":"target_missing","trace":trace}
		var delta: Vector2 = e["position"] - _player(driver)
		var bomb_setup := int(driver._state().get("slots", {}).get("objective_progress", 0)) >= 5
		# GDD blast radius is 48, Glock range is 150. Stay inside both limits.
		if bomb_setup and delta.length() <= 35.0: return {"ok":true,"trace":trace}
		if not bomb_setup and absf(delta.x) <= 6.0 and absf(delta.y) >= 45.0 and absf(delta.y) <= 110.0:
			return {"ok":await _face(driver, selector),"trace":trace}
		var axis := 0 if absf(delta.x) > 6.0 else 1
		if bomb_setup: axis = 0 if absf(delta.x) > absf(delta.y) else 1
		var distance := absf(delta.x) if axis == 0 else absf(delta.y)
		var speed := maxf(1.0, float(driver._state().get("slots", {}).get("movement_speed", 150)))
		var key := _axis_key(delta, axis, not bomb_setup and axis == 1 and distance < 45.0)
		var before := _player(driver)
		await driver._inject_key(key, clampf(maxf(distance, 30.0) / speed * 0.6, 0.016, 0.12))
		var after := _player(driver)
		trace.append({"key":key,"before":[before.x,before.y],"after":[after.x,after.y]})
		if after.distance_to(before) < 1.0:
			var nudge := _axis_key(Vector2.ONE if detour_positive else -Vector2.ONE, 1-axis)
			await driver._inject_key(nudge, 0.12)
			detour_positive = not detour_positive
	return {"ok":false,"reason":"training_route_timeout","trace":trace}

func _enemy_count(driver) -> int:
	return int(driver._state().get("slots", {}).get("enemy_count", 0))

func _has_visible(driver, kind: String) -> bool:
	for t in driver._state().get("targets", []):
		if str(t.get("kind", "")) == kind and bool(t.get("visible", false)) and bool(t.get("interactable", false)): return true
	return false

func _seek_level6_door(driver) -> bool:
	var starting_room := int(driver._state().get("slots", {}).get("room", -1))
	if not _level6_rooms.has(starting_room): _level6_rooms.append(starting_room)
	# LEVEL-06g publishes the route right -> up -> left. Room IDs are learned
	# from observations; neither coordinates nor the candidate's node layout
	# are assumed. Probe the desired wall while sliding along it to find its door.
	var cursor := _level6_rooms.find(starting_room)
	if cursor >= 3: return false
	var forward: String = ["D", "W", "A"][cursor]
	var sides: Array = ["W", "S"] if forward in ["D", "A"] else ["A", "D"]
	var side_index := 0
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if driver._state().get("phase", "") in ["won", "lost"]: return true
		if int(driver._state().get("slots", {}).get("room", -1)) != starting_room: return true
		if _enemy_count(driver) > 0 or _has_visible(driver, "upgrade_choice"): return true
		var before := _player(driver)
		await driver._inject_key(forward, 0.25)
		if _player(driver).distance_to(before) > 1.0: continue
		before = _player(driver)
		await driver._inject_key(sides[side_index], 0.18)
		if _player(driver).distance_to(before) < 1.0: side_index = 1 - side_index
	return false

func _explore_until_encounter(driver) -> bool:
	if int(driver._state().get("slots", {}).get("level", 0)) == 6:
		return await _seek_level6_door(driver)
	# Cleared rooms may expose no world target at all. Search with ordinary
	# movement in a repeating, coordinate-free sweep and stop as soon as the
	# public dashboard reports a new encounter, modal, or terminal phase.
	var deadline := Time.get_ticks_msec() + 90000
	var keys := ["D", "S", "A", "W"]
	var index := 0
	var outward := ""
	var starting_room := int(driver._state().get("slots", {}).get("room", -1))
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = driver._state()
		if state.get("phase", "") in ["won", "lost"]: return true
		if _has_visible(driver, "upgrade_choice") or _enemy_count(driver) > 0: return true
		if int(state.get("slots", {}).get("room", -1)) != starting_room: return true
		var before := _player(driver)
		await driver._inject_key(keys[index % keys.size()], 0.45)
		var after := _player(driver)
		# Continue a sweep direction while it makes progress. Rotate only on
		# collision. While tracing the new edge, repeatedly probe outward so an
		# unlabelled doorway is crossed when the player passes its opening.
		if after.distance_to(before) < 2.0:
			outward = keys[index % keys.size()]
			index += 1
		elif outward != "":
			await driver._inject_key(outward, 0.10)
	return false

func _collect_special(driver) -> bool:
	if int(driver._state().get("slots", {}).get("selected_weapon", 0)) == 3: return true
	var rifle := _entity(driver, {"kind":"special_rifle"})
	if bool(rifle.get("found", false)):
		var pickup_deadline := Time.get_ticks_msec() + 25000
		var pickup_side := false
		while Time.get_ticks_msec() < pickup_deadline:
			if int(driver._state().get("slots", {}).get("selected_weapon", 0)) == 3: return true
			rifle = _entity(driver, {"kind":"special_rifle"})
			if not bool(rifle.get("found", false)): break
			var delta: Vector2 = rifle["position"] - _player(driver)
			var axis := 0 if absf(delta.x) >= absf(delta.y) else 1
			var key := _axis_key(delta, axis)
			var before := _player(driver)
			await driver._inject_key(key, 0.10)
			if _player(driver).distance_to(before) < 1.0:
				pickup_side = not pickup_side
				var side_delta := Vector2(1.0 if pickup_side else -1.0, 1.0 if pickup_side else -1.0)
				await driver._inject_key(_axis_key(side_delta, 1-axis), 0.18)
	var published := _target_rect(driver, {"kind":"special_rifle"})
	if bool(published.get("found", false)):
		await driver._inject_click_point(published["position"])
		await driver._settle(8)
		if int(driver._state().get("slots", {}).get("selected_weapon", 0)) == 3: return true
	# The dashboard exposes the elite's live position and the held-special slot,
	# but not a private rifle node. Walk to the last publicly observed elite
	# position and verify pickup only through selected_weapon == 3.
	var deadline := Time.get_ticks_msec() + 12000
	if _last_special_screen != Vector2.ZERO:
		await driver._inject_click_point(_last_special_screen)
		await driver._settle(8)
		if int(driver._state().get("slots", {}).get("selected_weapon", 0)) == 3: return true
	while Time.get_ticks_msec() < deadline and _last_combat_goal != Vector2.ZERO:
		if int(driver._state().get("slots", {}).get("selected_weapon", 0)) == 3: return true
		var delta := _last_combat_goal - _player(driver)
		if delta.length() <= 8.0: break
		var axis := 0 if absf(delta.x) >= absf(delta.y) else 1
		await driver._inject_key(_axis_key(delta, axis), 0.10)
	return int(driver._state().get("slots", {}).get("selected_weapon", 0)) == 3

func _chase_keys(delta: Vector2) -> Array:
	var keys: Array = []
	# Quantize the live relative direction to the public eight WASD headings.
	if absf(delta.x) >= absf(delta.y) * 0.4142: keys.append("D" if delta.x > 0 else "A")
	if absf(delta.y) >= absf(delta.x) * 0.4142: keys.append("S" if delta.y > 0 else "W")
	return keys

func _boss_entity(driver) -> Dictionary:
	# The naming tables publish `enemy` states living/dead/elite/boss, so the
	# boss is identified through the public snapshot only.
	return _entity(driver, {"kind":"enemy", "state":"boss"})

func _hostile_blocks_shot(driver, boss: Dictionary, axis: int) -> bool:
	# RULE-13j: hitting any non-boss target is a miss, so a lesser/elite golem
	# standing on the firing line has to be cleared or side-stepped first.
	var origin := _player(driver)
	var goal: Vector2 = boss["position"]
	for e in driver._state().get("entities", []):
		if e.get("kind", "") != "enemy": continue
		var state := str(e.get("state", ""))
		if state != "living" and state != "elite": continue
		var c: Array = e.get("cell", [])
		if c.size() != 2: continue
		var position := Vector2(float(c[0]), float(c[1]))
		if axis == 0:
			if absf(position.y - origin.y) > AIM_TOLERANCE: continue
			if (position.x - origin.x) * (goal.x - origin.x) <= 0.0: continue
			if absf(position.x - origin.x) < absf(goal.x - origin.x): return true
		else:
			if absf(position.x - origin.x) > AIM_TOLERANCE: continue
			if (position.y - origin.y) * (goal.y - origin.y) <= 0.0: continue
			if absf(position.y - origin.y) < absf(goal.y - origin.y): return true
	return false

func _fire_special_once(driver, boss_rect: Dictionary) -> bool:
	# A single left-button press fires the held special shot and consumes the
	# held state (RULE-13d / RULE-13e).
	if not bool(boss_rect.get("found", false)): return false
	await driver._inject_move_fire([], 0.03, boss_rect["position"])
	await driver._settle(6)
	return true

func _aligned_special_shot(driver) -> bool:
	# Only fire the special rifle from a published axis alignment with the boss,
	# with the last nonzero WASD input pointing at it (RULE-03i).  Hits and misses
	# are judged through `boss_progress` / `selected_weapon`; a miss drops the
	# unique rifle again (RULE-13k) and is collected and retried (RULE-13r).
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = driver._state()
		if state.get("phase", "") == "won": return true
		if state.get("phase", "") == "lost": return false
		var slots: Dictionary = state.get("slots", {})
		if int(slots.get("selected_weapon", 0)) != 3:
			if not await _collect_special(driver): return false
			continue
		var boss := _boss_entity(driver)
		if not bool(boss.get("found", false)): return false
		var rect := _target_rect(driver, {"kind":"enemy", "state":"boss"})
		if not bool(rect.get("found", false)):
			rect = _target_rect(driver, {"kind":"enemy"})
		var player := _player(driver)
		var delta: Vector2 = boss["position"] - player
		var horizontal := absf(delta.y) <= AIM_TOLERANCE
		var vertical := absf(delta.x) <= AIM_TOLERANCE
		if not horizontal and not vertical:
			# Align the axis that is furthest away; the pointing key is pressed
			# again immediately before the shot, so alignment never leaks aim.
			var align_axis := 1 if absf(delta.y) >= absf(delta.x) else 0
			await driver._inject_key(_axis_key(delta, align_axis), 0.08)
			continue
		var aim_axis := 0 if horizontal else 1
		var distance := absf(delta.x) if horizontal else absf(delta.y)
		if distance > SHOT_MAX_DISTANCE:
			await driver._inject_key(_axis_key(delta, aim_axis), 0.10)
			continue
		if distance < SHOT_MIN_DISTANCE:
			await driver._inject_key(_axis_key(delta, aim_axis, true), 0.08)
			continue
		if _hostile_blocks_shot(driver, boss, aim_axis):
			var side := Vector2(1.0, 1.0) if _evasion_positive else Vector2(-1.0, -1.0)
			_evasion_positive = not _evasion_positive
			await driver._inject_key(_axis_key(side, 1 - aim_axis), 0.15)
			continue
		# Establish the persistent direction towards the boss, then release the
		# one shot the pickup carries.
		await driver._inject_key(_axis_key(delta, aim_axis), 0.03)
		await driver._settle(1)
		var before_progress := int(driver._state().get("slots", {}).get("boss_progress", 0))
		if not await _fire_special_once(driver, rect):
			return false
		var after: Dictionary = driver._state()
		if after.get("phase", "") == "won": return true
		if int(after.get("slots", {}).get("boss_progress", 0)) < before_progress: return true
		# Miss: the rifle has dropped back into the room; loop, re-collect, retry.
	return false

func _combat(driver, selector: Dictionary, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var blocked := 0
	var retries := 0
	while Time.get_ticks_msec() < deadline:
		await driver._settle(1)
		var state: Dictionary = driver._state()
		if state.get("phase", "") == "won": return true
		if state.get("phase", "") == "lost":
			# A player who dies mid-level retries the same level from the published
			# defeat page (SESSION-01a/b); the failure_and_retry and lifecycle
			# trajectories keep the natural loss, so the retry is limited to the
			# level-progression trajectories and bounded.
			var retryable: bool = str(driver.current_trajectory) in ["entry_and_training", "core_levels", "boss_and_level6_success"]
			if not retryable or retries >= 2: return false
			retries += 1
			if not await driver._inject_click({"kind":"retry_button"}): return false
			await driver._settle(6)
			if _has_visible(driver, "start_button"):
				if not await driver._inject_click({"kind":"start_button"}): return false
				await driver._settle(6)
			continue
		if _has_visible(driver, "upgrade_choice"): return true
		var slots: Dictionary = state.get("slots", {})
		if _enemy_count(driver) == 0:
			await driver.create_timer(0.6).timeout
			if driver._state().get("phase", "") == "won": return true
			if not await _explore_until_encounter(driver): return false
			continue
		# A special rifle is a normal public pickup, required for boss damage.
		if int(slots.get("stage_kills", 0)) >= 5 and int(slots.get("selected_weapon", 0)) != 3 and _enemy_count(driver) == 1:
			await _collect_special(driver)
			continue
		# Boss stage while holding the rifle: the pickup carries exactly one shot
		# and the projectile follows the last WASD heading, so the shot is only
		# released from a published axis alignment instead of firing mid-chase.
		if int(slots.get("selected_weapon", 0)) == 3 and bool(_boss_entity(driver).get("found", false)):
			if await _aligned_special_shot(driver): continue
			# The disciplined shot did not convert within its own budget (the
			# rifle could not be re-collected, or the boss stayed misaligned):
			# fall through to the normal chase so the step keeps making progress.
		var target := _entity(driver, selector)
		if not target.get("found", false): return false
		var delta: Vector2 = target["position"] - _player(driver)
		var keys := _chase_keys(delta)
		var rect := _target_rect(driver, selector)
		if not rect.get("found", false): return false
		var before := _player(driver)
		# Direct chase: move toward the nearest live hostile while holding fire.
		# At close range a short movement establishes aim without crossing it.
		await driver._inject_move_fire(keys, 0.12 if delta.length() > 55.0 else 0.025, rect["position"])
		if _player(driver).distance_to(before) < 1.0:
			blocked += 1
		else: blocked = 0
		# Only detour in response to observed collision; no private obstacle map.
		if blocked >= 3:
			var side := Vector2(-delta.y, delta.x)
			await driver._inject_move_fire(_chase_keys(side), 0.22, rect["position"])
			blocked = 0
		var ammo_key := "glock_ammo" if int(slots.get("selected_weapon", 1)) == 2 else "hk_ammo"
		if int(driver._state().get("slots", {}).get(ammo_key, 0)) <= 0:
			await driver._inject_key("R")
			await driver.create_timer(0.85).timeout
	return driver._state().get("phase", "") == "won"

func _approach_without_firing(driver, selector: Dictionary) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if driver._state().get("phase", "") == "lost": return true
		var e := _entity(driver, selector)
		if not e.get("found", false): return false
		var delta: Vector2 = e["position"] - _player(driver)
		if delta.length() <= 20.0: return true
		await driver._inject_key(movement_key(delta, driver._state()), 0.1)
	return false

func prepare(action: Dictionary, driver) -> Dictionary:
	var kind := str(action.get("target", {}).get("kind", ""))
	if action.get("do", "") == "restart":
		var ok: bool = await driver._inject_click({"kind":"retry_button"})
		if ok and _has_visible(driver, "start_button"):
			ok = await driver._inject_click({"kind":"start_button"})
		return {"consumed":true,"ok":ok,"strategy":"published_retry_and_briefing"}
	if action.get("do", "") == "click" and kind in ["training_target", "enemy"]:
		if kind == "enemy":
			return {"consumed":true,"ok":await _combat(driver, action.get("target", {}), float(action.get("timeout_s", 180.0))),"strategy":"feedback_move_fire"}
		var route := await _route_to(driver, action.get("target", {}))
		if not bool(route.get("ok", false)): return {"consumed":true,"ok":false,"route":route}
		return {"consumed":true,"ok":await _world_fire(driver, action.get("target", {})),"strategy":"movement_direction_fire","route":route}
	if action.get("do", "") == "move_toward" and kind == "enemy":
		if driver.current_trajectory == "failure_and_retry":
			return {"consumed":true,"ok":await _approach_without_firing(driver, action.get("target", {})),"strategy":"approach_without_firing"}
		return {"consumed":true,"ok":await _combat(driver, action.get("target", {}), float(action.get("timeout_s", 180.0))),"strategy":"feedback_move_fire"}
	if action.get("do", "") == "move_toward" and kind == "training_target":
		var route := await _route_to(driver, action.get("target", {}))
		if not bool(route.get("ok", false)): return {"consumed":true,"ok":false,"strategy":"feedback_move","route":route}
		# The training contract requires four spent HK rounds before reload. Read
		# the public ammo/progress slots and supply only the missing real clicks.
		while int(driver._state().get("slots", {}).get("objective_progress", 0)) <= 3 and int(driver._state().get("slots", {}).get("hk_ammo", 30)) > 26:
			route = await _route_to(driver, action.get("target", {}))
			if not bool(route.get("ok", false)): return {"consumed":true,"ok":false,"strategy":"training_ammo_completion","route":route}
			if not await _world_fire(driver, action.get("target", {})): return {"consumed":true,"ok":false,"strategy":"training_ammo_completion","route":route}
			await driver._settle(6)
		return {"consumed":true,"ok":true,"strategy":"training_ammo_completion","route":route}
	return {"prepared":false}
