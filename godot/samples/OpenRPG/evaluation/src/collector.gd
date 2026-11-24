extends SceneTree

## Generic engine-level checkpoint producer.  It executes the authored script
## through public dashboard targets and normal InputEvent delivery only.
## Game-specific movement is deliberately conservative and fail-closed.

var evaluation_path := ""
var output_path := ""
var scene_path := ""
var script_data: Dictionary = {}
var events: Array = []
var sessions: Array = []
var seq := 0
var game_scene: Node
var current_session := ""
var current_trajectory := ""
var current_pid := 0
var failed_infrastructure := false
var trajectory_filter := ""
var adapter = null
var trajectory_blocked := false
var allow_system_mouse := false
var reopen_verified := false
var start_step := 0
var stop_step := -1
var last_sample_ms := 0
var observations: Array = []
var input_trace: Array = []
var naming_data: Dictionary = {}
var interactive_seconds := 0.0

class WindowInputTrace extends Node:
	var sink
	func _input(event: InputEvent) -> void:
		sink._record_window_input(event)

func _record_window_input(event: InputEvent) -> void:
	var item := {"at_ms":Time.get_ticks_msec(),"source":"window_input"}
	if event is InputEventKey:
		item.merge({"type":"key","keycode":event.physical_keycode,"pressed":event.pressed})
	elif event is InputEventMouseButton:
		item.merge({"type":"mouse_button","button":event.button_index,"pressed":event.pressed,"position":[event.position.x,event.position.y]})
	elif event is InputEventMouseMotion:
		item.merge({"type":"mouse_motion","position":[event.position.x,event.position.y]})
	else:
		return
	input_trace.append(item)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("ENGINE_DRIVER_ARGS=", args)
	for i in range(args.size() - 1):
		if args[i] == "--evaluation": evaluation_path = args[i + 1]
		elif args[i] == "--output": output_path = args[i + 1]
		elif args[i] == "--scene": scene_path = args[i + 1]
		elif args[i] == "--trajectory": trajectory_filter = args[i + 1]
		elif args[i] == "--start-step": start_step = int(args[i + 1])
		elif args[i] == "--stop-step": stop_step = int(args[i + 1])
		elif args[i] == "--interactive-seconds": interactive_seconds = float(args[i + 1])
		elif args[i] == "--reopen-verified": reopen_verified = args[i + 1] == "true"
	if evaluation_path == "":
		print("ENGINE_DRIVER_NO_EVALUATION")
		_finish(3, {"valid": false, "reason": "evaluation_path_missing"}); return
	# Continuous aiming is enabled only for the FourShot input policy.
	allow_system_mouse = false
	root.unfocusable = not allow_system_mouse and interactive_seconds <= 0
	var f := FileAccess.open(evaluation_path.path_join("checkpoint-script.json"), FileAccess.READ)
	if f == null:
		print("ENGINE_DRIVER_SCRIPT_OPEN_FAILED=", evaluation_path.path_join("checkpoint-script.json"))
		_finish(3, {"valid": false, "reason": "checkpoint_script_missing"}); return
	script_data = JSON.parse_string(f.get_as_text())
	allow_system_mouse = str(script_data.get("game", "")) == "four_shot"
	root.unfocusable = not allow_system_mouse and interactive_seconds <= 0
	# The naming tables are the only source of truth for which selector fields a
	# task actually published; they are loaded up front so target resolution can
	# refuse to demand a state the candidate was never told to report.
	var naming_file := FileAccess.open(evaluation_path.path_join(str(script_data.get("naming_tables", ""))), FileAccess.READ)
	if naming_file != null:
		var naming_parsed = JSON.parse_string(naming_file.get_as_text())
		if naming_parsed is Dictionary: naming_data = naming_parsed
	if not script_data is Dictionary:
		_finish(3, {"valid": false, "reason": "checkpoint_script_invalid"}); return
	var adapter_path := evaluation_path.path_join("evaluator/engine_adapter.gd")
	if FileAccess.file_exists(adapter_path):
		var adapter_script = load(adapter_path)
		if adapter_script != null: adapter = adapter_script.new()
	scene_path = str(ProjectSettings.get_setting("application/run/main_scene", "")) if scene_path == "" else scene_path
	call_deferred("_run")

func _state() -> Dictionary:
	if game_scene != null:
		var d := _find_dashboard(game_scene)
		if d != null and d.has_method("capture"):
			var live = d.call("capture")
			if live is Dictionary: return live
	var p := ProjectSettings.globalize_path("user://benchmark_dashboard.json")
	if not FileAccess.file_exists(p): return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _find_dashboard(node: Node) -> Node:
	if node.has_method("capture"): return node
	for child in node.get_children():
		var found := _find_dashboard(child)
		if found != null: return found
	return null

func _settle(frames := 8) -> void:
	for _i in frames: await process_frame

func _declared_target_states(kind: String) -> Array:
	for item in naming_data.get("targets", []):
		if typeof(item) == TYPE_DICTIONARY and str(item.get("kind", "")) == kind:
			var states = item.get("states", [])
			if states is Array and not states.is_empty(): return states
	return []

func _selector_kinds(selector: Dictionary) -> Array:
	var kinds: Array = []
	var alternatives = selector.get("kind_any", null)
	if alternatives is Array and not alternatives.is_empty():
		for alternative in alternatives: kinds.append(str(alternative))
	else:
		kinds.append(str(selector.get("kind", "")))
	return kinds

func _targets(selector: Dictionary, allow_relax := true) -> Array:
	var out: Array = []
	var wanted_kinds := _selector_kinds(selector)
	var wanted_state := str(selector.get("state", ""))
	var snapshot := _state()
	var matching_ids := {}
	var entity_kind := str(selector.get("entity_kind", ""))
	if entity_kind != "":
		var owner := str(selector.get("entity_owner", ""))
		for entity in snapshot.get("entities", []):
			if entity.get("kind", "") != entity_kind or not entity.has("id"): continue
			if owner != "" and entity.get("owner", "") != owner: continue
			matching_ids[entity["id"]] = true
	for t in snapshot.get("targets", []):
		if entity_kind != "" and not matching_ids.has(t.get("id")): continue
		var kind := str(t.get("kind", ""))
		if not wanted_kinds.has(kind): continue
		# Stateful selectors must resolve the exact public semantic state.  A
		# stateless fallback can silently choose the wrong card or destination,
		# so it is only allowed for drag endpoints, only when the naming tables
		# never declared target states for that kind, and only because
		# `_inject_drag` verifies the drop through the public revision.
		if wanted_state != "" and str(t.get("state", "")) != wanted_state and (not allow_relax or not _declared_target_states(kind).is_empty()): continue
		if t.get("visible", false) and t.get("interactable", false): out.append(t)
	return out

func _revision() -> int:
	return int(_state().get("revision", -1))

func _send(event: InputEvent, local := false) -> void:
	var receipt := {"at_ms":Time.get_ticks_msec(),"step":seq}
	if event is InputEventKey:
		receipt.merge({"type":"key","keycode":event.physical_keycode,"pressed":event.pressed})
	elif event is InputEventMouseButton:
		receipt.merge({"type":"mouse_button","button":event.button_index,"pressed":event.pressed,"position":[event.position.x,event.position.y]})
	elif event is InputEventMouseMotion:
		receipt.merge({"type":"mouse_motion","position":[event.position.x,event.position.y]})
	input_trace.append(receipt)
	if local:
		root.push_input(event, true)
	else:
		Input.parse_input_event(event)

func _inject_click(selector: Dictionary, button := MOUSE_BUTTON_LEFT) -> bool:
	# Resolve the visible target once and deliver one click.
	var items := _targets(selector)
	if items.is_empty(): return false
	var r: Array = items[0].get("rect", [])
	if r.size() != 4 or float(r[2]) <= 0.0 or float(r[3]) <= 0.0: return false
	var point := Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
	await _settle(2)
	return await _inject_click_point(point, button)

func _inject_click_point(point: Vector2, button := MOUSE_BUTTON_LEFT) -> bool:
	if allow_system_mouse:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		_send(motion)
		await process_frame
	var down := InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = button
	down.button_mask = MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	_send(down, not allow_system_mouse)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = point
	up.global_position = point
	up.button_index = button
	_send(up, not allow_system_mouse)
	await process_frame
	await _settle(12)
	return true

func _inject_drag(from_selector: Dictionary, to_selector: Dictionary) -> bool:
	# Resolve both endpoints from the current public dashboard.  A drag is a
	# genuine press -> held motion sequence -> release; it never calls a game
	# method or invents a coordinate when a public target is unavailable.
	var starts := _targets(from_selector, true)
	var ends := _targets(to_selector, true)
	if starts.is_empty() or ends.is_empty(): return false
	# Ambiguous endpoints (no published target state to disambiguate them) are
	# tried in order and the first drop the dashboard reflects wins; the common
	# baseline forbids illegal actions from mutating authoritative state, so the
	# other attempts are no-ops.  A single unambiguous pair keeps the historical
	# single-shot drag.
	var ambiguous := starts.size() > 1 or ends.size() > 1
	var start_range := starts.size() if ambiguous else 1
	var end_range := ends.size() if ambiguous else 1
	for start_index in range(mini(start_range, 4)):
		for end_index in range(mini(end_range, 6)):
			var revision_before := _revision()
			if not await _drag_once(starts[start_index], ends[end_index]): continue
			if not ambiguous: return true
			if _revision() != revision_before: return true
	return false

func _drag_once(start_target: Dictionary, end_target: Dictionary) -> bool:
	var sr: Array = start_target.get("rect", [0, 0, 0, 0])
	var tr: Array = end_target.get("rect", [0, 0, 0, 0])
	if float(sr[2]) <= 0.0 or float(sr[3]) <= 0.0 or float(tr[2]) <= 0.0 or float(tr[3]) <= 0.0: return false
	var start := Vector2(float(sr[0]) + float(sr[2]) / 2.0, float(sr[1]) + float(sr[3]) / 2.0)
	var finish := Vector2(float(tr[0]) + float(tr[2]) / 2.0, float(tr[1]) + float(tr[3]) / 2.0)
	if allow_system_mouse:
		var motion := InputEventMouseMotion.new(); motion.position = start; motion.global_position = start
		_send(motion); await process_frame
		var down := InputEventMouseButton.new(); down.position = start; down.global_position = start; down.button_index = MOUSE_BUTTON_LEFT; down.button_mask = MOUSE_BUTTON_MASK_LEFT; down.pressed = true
		_send(down); await process_frame
		for i in range(1, 9):
			var p := start.lerp(finish, float(i) / 8.0)
			var held := InputEventMouseMotion.new(); held.position = p; held.global_position = p; held.button_mask = MOUSE_BUTTON_MASK_LEFT
			_send(held); await process_frame
		var up := InputEventMouseButton.new(); up.position = finish; up.global_position = finish; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
		_send(up)
	else:
		# Touch drag is window-local and cannot steer the operator's OS mouse.
		var touch_down := InputEventScreenTouch.new(); touch_down.index = 0; touch_down.position = start; touch_down.pressed = true
		root.push_input(touch_down, true); await process_frame
		for i in range(1, 9):
			var p := start.lerp(finish, float(i) / 8.0)
			var touch_drag := InputEventScreenDrag.new(); touch_drag.index = 0; touch_drag.position = p; touch_drag.relative = (finish - start) / 8.0
			root.push_input(touch_drag, true); await process_frame
		var touch_up := InputEventScreenTouch.new(); touch_up.index = 0; touch_up.position = finish; touch_up.pressed = false
		root.push_input(touch_up, true)
	await _settle(12)
	return true

func _keycode(name: String) -> int:
	var n := name.to_upper()
	if n == "SHIFT": return KEY_SHIFT
	if n == "ESCAPE": return KEY_ESCAPE
	if n == "SPACE": return KEY_SPACE
	if n == "TAB": return KEY_TAB
	if n == "ENTER": return KEY_ENTER
	if n.length() == 1:
		var c := n.unicode_at(0)
		if c >= 48 and c <= 57: return KEY_0 + c - 48
		if c >= 65 and c <= 90: return KEY_A + c - 65
	return KEY_NONE

func _inject_key(name: String, seconds := 0.0) -> bool:
	var key := _keycode(name)
	if key == KEY_NONE: return false
	var e := InputEventKey.new(); e.keycode = key; e.physical_keycode = key; e.pressed = true; _send(e)
	if seconds > 0.0:
		await create_timer(seconds).timeout
	else:
		await process_frame
	e = InputEventKey.new(); e.keycode = key; e.physical_keycode = key; e.pressed = false; _send(e)
	await _settle(6); return true

func _inject_move_fire(keys: Array, seconds: float, point: Vector2) -> void:
	for name in keys:
		var key := InputEventKey.new(); key.keycode = _keycode(name); key.physical_keycode = key.keycode; key.pressed = true
		_send(key)
	await process_frame
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	_send(motion)
	var down := InputEventMouseButton.new(); down.position = point; down.global_position = point; down.button_index = MOUSE_BUTTON_LEFT; down.button_mask = MOUSE_BUTTON_MASK_LEFT; down.pressed = true
	_send(down)
	await create_timer(seconds).timeout
	var up := InputEventMouseButton.new(); up.position = point; up.global_position = point; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
	_send(up)
	for name in keys:
		var key := InputEventKey.new(); key.keycode = _keycode(name); key.physical_keycode = key.keycode; key.pressed = false
		_send(key)
	await _settle(2)

func _inject_movement_dash(name: String) -> bool:
	var move_key := _keycode(name)
	if move_key == KEY_NONE: return false
	var e := InputEventKey.new(); e.keycode = move_key; e.physical_keycode = move_key; e.pressed = true; _send(e)
	await process_frame
	var dash := InputEventKey.new(); dash.keycode = KEY_SHIFT; dash.physical_keycode = KEY_SHIFT; dash.pressed = true; _send(dash)
	await create_timer(0.02).timeout
	dash = InputEventKey.new(); dash.keycode = KEY_SHIFT; dash.physical_keycode = KEY_SHIFT; dash.pressed = false; _send(dash)
	await create_timer(0.16).timeout
	e = InputEventKey.new(); e.keycode = move_key; e.physical_keycode = move_key; e.pressed = false; _send(e)
	await _settle(4); return true

func _player_cell() -> Vector2:
	for e in _state().get("entities", []):
		if e.get("kind", "") == "player":
			var c: Array = e.get("cell", [0,0]); return Vector2(float(c[0]), float(c[1]))
	return Vector2.ZERO

func _move_toward(selector: Dictionary, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var attempts := 0
	while Time.get_ticks_msec() < deadline and attempts < 40:
		attempts += 1
		var items := []
		for e in _state().get("entities", []):
			if e.get("kind", "") == selector.get("kind", "") and (str(selector.get("state", "")) == "" or e.get("state", "") == selector.get("state", "")): items.append(e)
		if items.is_empty(): return false
		var c: Array = items[0].get("cell", [0,0]); var delta := Vector2(float(c[0]),float(c[1])) - _player_cell()
		if delta.length() < 24.0: return true
		var key := "D" if delta.x > 0 else "A"
		if absf(delta.y) > absf(delta.x): key = "S" if delta.y > 0 else "W"
		if adapter != null and adapter.has_method("movement_key"):
			var adapted = adapter.call("movement_key", delta, _state())
			if adapted is String and adapted != "": key = adapted
		await _inject_key(key, 0.05)
	return false

func _entity_x(entity: Dictionary) -> Variant:
	var cell = entity.get("cell", [])
	if cell is Array and cell.size() >= 2 and (cell[0] is int or cell[0] is float):
		return cell[0]
	return null

func _align_horizontal(selector: Dictionary, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var snapshot := _state()
		if snapshot.get("phase") == "won": return true
		if snapshot.get("phase") != "playing": return false
		var entities = snapshot.get("entities", [])
		var player_x: Variant = null
		for entity in entities:
			if entity.get("kind") == "player":
				player_x = _entity_x(entity)
				break
		if player_x == null: return false
		var delta := INF
		for entity in entities:
			if entity.get("kind") != selector.get("kind"): continue
			if selector.has("state") and entity.get("state") != selector["state"]: continue
			var target_x: Variant = _entity_x(entity)
			if target_x != null and absf(float(target_x) - float(player_x)) < absf(delta):
				delta = float(target_x) - float(player_x)
		if is_inf(delta): return false
		if absf(delta) <= 12.0: return true
		await _inject_key("D" if delta > 0.0 else "A", clampf(absf(delta) / 900.0, 0.02, 0.12))
	return false

func _condition_value(path: String, snapshot: Dictionary) -> Variant:
	if path == "phase": return snapshot.get("phase")
	if snapshot.get("phase", "not_ready") == "not_ready": return null
	if path.begins_with("slots."):
		var slots = snapshot.get("slots")
		return slots.get(path.trim_prefix("slots.")) if slots is Dictionary else null
	var parts := path.split(".")
	if parts.size() != 3 or parts[0] != "entities": return null
	var entities = snapshot.get("entities")
	if not entities is Array: return null
	var count := 0
	for entity in entities:
		if not entity is Dictionary or entity.get("kind") != parts[1]: continue
		if parts[2] == "x": return _entity_x(entity)
		count += 1
	return count if parts[2] == "count" else null

func _condition(cond: String, snapshot: Dictionary) -> bool:
	for op in [">=", "<=", "!=", "==", ">", "<"]:
		var parts := cond.split(op)
		if parts.size() != 2: continue
		var lhs := parts[0].strip_edges()
		var rhs := parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		var value: Variant = _condition_value(lhs, snapshot)
		if lhs == "phase":
			if not value is String or rhs.is_empty(): return false
			return (op == "==" and value == rhs) or (op == "!=" and value != rhs)
		if not rhs.is_valid_float() or not (value is int or value is float): return false
		var a := float(value)
		var b := float(rhs)
		if op == "==": return a == b
		if op == "!=": return a != b
		if op == ">=": return a >= b
		if op == "<=": return a <= b
		if op == ">": return a > b
		if op == "<": return a < b
	return false

func _reached_opposite_terminal(cond: String) -> bool:
	# Won and lost are mutually exclusive.  Once the opposite terminal appears,
	# continuing a long terminal wait cannot recover and only wastes calibration.
	var compact := cond.replace(" ", "")
	var phase := str(_state().get("phase", ""))
	return (compact == "phase==won" and phase == "lost") or (compact == "phase==lost" and phase == "won")

func _new_scene() -> bool:
	if game_scene != null: game_scene.queue_free(); game_scene = null; await _settle(4)
	var packed := load(scene_path) as PackedScene
	if packed == null: return false
	game_scene = packed.instantiate(); root.add_child(game_scene); current_scene = game_scene; await _settle(15); return true

func _snapshot() -> Dictionary:
	var s := _state(); var raw := JSON.stringify(s)
	return {"snapshot":s, "raw_json":raw, "bytes":raw.to_utf8_buffer().size(), "sha256":_sha(raw)}

func _sha(raw: String) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(raw.to_utf8_buffer()); return h.finish().hex_encode()

func _file_sha(path: String) -> String:
	if not FileAccess.file_exists(path): return ""
	var f := FileAccess.open(path, FileAccess.READ); if f == null: return ""
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256)
	while not f.eof_reached(): h.update(f.get_buffer(1048576))
	return h.finish().hex_encode()

func _run_step(tid: String, i: int, st: Dictionary) -> void:
	print("ENGINE_DRIVER_STEP=", tid, ":", i, " action=", st.get("do", "check"))
	var started_ms := Time.get_ticks_msec()
	var before := _snapshot(); var status := "ok"; var error_class := ""; var action := {}
	for k in st.keys():
		if k != "check": action[k] = st[k]
	var do_action := str(st.get("do", "")); var ok := true; var consumed := false; var adapter_trace = null
	# Evidence capture remains meaningful after a failed prerequisite: it records
	# the candidate's actual blocked state and is required by the transcript
	# protocol.  Only gameplay-mutating/further waiting actions are short-circuited.
	var skipped_by_prerequisite := trajectory_blocked and do_action != "" and do_action not in ["capture", "snapshot"]
	var skip_condition := str(st.get("skip_if", ""))
	if not skip_condition.is_empty() and _condition(skip_condition, before["snapshot"]):
		consumed = true
		status = "skipped"
	elif skipped_by_prerequisite:
		consumed = true
		ok = false
	elif adapter != null and adapter.has_method("prepare"):
		adapter_trace = await adapter.call("prepare", st, self)
		if adapter_trace is Dictionary:
			consumed = bool(adapter_trace.get("consumed", false)); ok = bool(adapter_trace.get("ok", true))
	if not consumed:
		match do_action:
			"start": await _settle(10)
			"click":
				var button := MOUSE_BUTTON_RIGHT if st.get("button", "left") == "right" else MOUSE_BUTTON_LEFT
				ok = await _inject_click(st.get("target", {}), button)
			"drag": ok = await _inject_drag(st.get("from", {}), st.get("to", {}))
			"press": ok = await _inject_key(str(st.get("key", "")))
			"hold": ok = await _inject_key(str(st.get("key", "")), float(st.get("seconds", 0.0)))
			"move_toward":
				var timeout_s := float(st.get("timeout_s", 10.0))
				if st.get("axis") == "x":
					ok = await _align_horizontal(st.get("target", {}), timeout_s)
				else:
					ok = await _move_toward(st.get("target", {}), timeout_s)
			"wait_until":
				# Apply the configured timeout with a 30-minute upper bound.
				var deadline := Time.get_ticks_msec() + mini(int(float(st.get("timeout_s", 10.0)) * 1000.0), 1800000); ok = false
				while Time.get_ticks_msec() < deadline:
					if _condition(str(st.get("cond", "")), _state()): ok = true; break
					if _reached_opposite_terminal(str(st.get("cond", ""))): break
					await _settle(4)
			"restart": ok = await _inject_click({"kind":"restart_button"})
			"reopen":
				# Parent runner resumes this step in a new OS process.
				ok = reopen_verified
			"capture": await _settle(1)
			"snapshot": await _settle(1)
			"": pass
			_: ok = false
	if not ok and do_action != "":
		if skipped_by_prerequisite:
			status = "candidate_rejected"; error_class = "prerequisite_not_reached"
		else:
			status = "candidate_timeout"
			error_class = "condition_not_met" if do_action == "wait_until" else "public_target_unavailable"
		# Every failed gameplay action is a failed prerequisite for later gameplay
		# in the same trajectory.  Continuing after an unavailable click/press can
		# spend the full timeout waiting for a state the candidate had no route to
		# reach and may accidentally exercise unrelated controls.  Evidence-only
		# capture/snapshot steps remain executable through skipped_by_prerequisite.
		if do_action not in ["capture", "snapshot"]:
			trajectory_blocked = true
	print("ENGINE_DRIVER_STEP_DONE=", tid, ":", i, " ok=", ok)
	var after := _snapshot(); var e := {"seq":seq + 1, "trajectory":tid, "step":i, "action":action, "route":"godot_engine_input", "session_id":current_session, "pid":current_pid, "started_ms":started_ms, "ended_ms":Time.get_ticks_msec(), "before":before, "after":after, "status":status}
	if adapter_trace != null: e["adapter_trace"] = adapter_trace
	if do_action == "capture":
		# Evidence belongs beside the isolated transcript, never inside the
		# candidate's res:// tree (which would mutate Gold/Input during scoring).
		# Include the transcript basename so Gold/Input and diagnostic reruns do
		# not overwrite one another's PNG while leaving stale hashes in receipts.
		var image_path := output_path.get_base_dir().path_join("%s-capture-%s-%d.png" % [output_path.get_file().get_basename(), tid, i])
		var image: Image = null
		var viewport_texture = root.get_texture() if DisplayServer.get_name() != "headless" else null
		if viewport_texture != null: image = viewport_texture.get_image()
		if image != null and image.save_png(image_path) == OK:
			e["screenshot"] = {"capture_source":"candidate_viewport", "sha256":_file_sha(ProjectSettings.globalize_path(image_path)), "path":image_path}
	if not error_class.is_empty(): e["error_class"] = error_class
	if st.has("check"):
		var check: Dictionary = st["check"]
		e["check_id"] = check.get("id", "")
		if check.has("condition"):
			var condition := str(check["condition"])
			var passed: Variant = null
			if status == "ok":
				passed = _condition(condition, after["snapshot"])
			elif error_class == "condition_not_met" and condition == st.get("cond", ""):
				passed = false
			e["check_result"] = {"condition": condition, "passed": passed}
	events.append(e); seq += 1

func _run() -> void:
	root.size = Vector2i(1280, 720); current_pid = OS.get_process_id()
	print("ENGINE_DRIVER_PID=",current_pid," USER_DIR=",OS.get_user_data_dir())
	process_frame.connect(_sample_public)
	for t in script_data.get("trajectories", []):
		if trajectory_filter != "" and str(t.get("id", "")) != trajectory_filter: continue
		trajectory_blocked = false
		current_trajectory = str(t.get("id", ""))
		current_session = "engine-%d-%s-%d" % [current_pid, str(Time.get_ticks_msec()), sessions.size() + 1]
		sessions.append({"session_id":current_session, "pid":current_pid, "executor":"godot_engine_input"})
		if not await _new_scene(): failed_infrastructure = true; break
		if interactive_seconds > 0:
			var observer := WindowInputTrace.new()
			observer.sink = self
			observer.process_mode = Node.PROCESS_MODE_ALWAYS
			root.add_child(observer)
			await _run_step(str(t.get("id", "")), 0, {"do":"capture"})
			var end_at := Time.get_ticks_msec() + int(interactive_seconds * 1000.0)
			while Time.get_ticks_msec() < end_at:
				await create_timer(2.0).timeout
				await _run_step(str(t.get("id", "")), seq, {"do":"capture"})
			break
		for i in range(start_step, t.get("steps", []).size()):
			if stop_step >= 0 and i >= stop_step: break
			await _run_step(str(t.get("id", "")), i, t["steps"][i])
		if game_scene != null: game_scene.queue_free(); game_scene = null; await _settle(3)
	var naming_path := evaluation_path.path_join(str(script_data.get("naming_tables", "")))
	var adapter_path := evaluation_path.path_join("evaluator/engine_adapter.gd")
	var engine_runtime_path := evaluation_path.path_join("evaluator/engine_driver.gd")
	var tr := {"protocol":"godot-checkpoint-driver/v1", "driver_version":"0.4.10-engine-runner", "engine_version":Engine.get_version_info().get("string", ""), "executor_version":"godot-engine-input", "script_sha256":_file_sha(evaluation_path.path_join("checkpoint-script.json")), "naming_sha256":_file_sha(naming_path), "adapter_sha256":_file_sha(adapter_path), "engine_runtime_sha256":_file_sha(engine_runtime_path), "sessions":sessions, "observations":observations, "input_trace":input_trace, "events":events, "health":{"rendered_capture":DisplayServer.get_name() != "headless","all_inputs_released":true,"exact_pid_cleanup":false,"output_isolated":false}, "execution":{"actual_scene":scene_path,"infrastructure_error":failed_infrastructure,"system_mouse_allowed":allow_system_mouse}}
	var f := FileAccess.open(output_path, FileAccess.WRITE); if f != null: f.store_string(JSON.stringify(tr, "  ") + "\n"); f.flush()
	print("ENGINE_DRIVER_WROTE=", output_path, " events=", events.size())
	quit(0 if not failed_infrastructure else 3)

func _sample_public() -> void:
	if game_scene == null or Time.get_ticks_msec() - last_sample_ms < 500: return
	last_sample_ms = Time.get_ticks_msec()
	var s := _snapshot()
	observations.append({"time_ms":last_sample_ms,"step":seq,"state":s})
	# Publish a live diagnostic so navigation can be inspected while playing.
	var live := FileAccess.open(output_path + ".live.json", FileAccess.WRITE)
	if live != null: live.store_string(JSON.stringify(s))

func _finish(code: int, report: Dictionary) -> void:
	var f := FileAccess.open(output_path, FileAccess.WRITE); if f != null: f.store_string(JSON.stringify(report, "  ") + "\n"); f.flush()
	quit(code)
