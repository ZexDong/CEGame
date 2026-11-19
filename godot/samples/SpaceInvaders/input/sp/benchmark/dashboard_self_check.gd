extends SceneTree
## Optional public shape/vocabulary check; no gameplay journey or scoring logic.
const PHASES := ["not_ready", "menu", "playing", "paused", "won", "lost"]
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Cannot load configured main scene"); quit(1); return
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	for frame in range(12): await process_frame
	var reporter := find_reporter(main)
	if reporter == null:
		push_error("Read-only dashboard absent"); quit(1); return
	var names: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://benchmark/naming-tables.json"))
	var pair := sample_pair(reporter)
	var errors := validate(pair.snapshot, names)
	if not pair.stable: errors.append("Consecutive read-only observations changed")
	if not errors.is_empty():
		for error in errors: push_error(error)
		quit(1); return
	print("DASHBOARD_SELF_CHECK_PASS")
	quit(0)

static func reporter_candidates(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node.has_method("capture"):
		var script := node.get_script() as Script
		while script != null:
			if script.get_script_constant_map().get("CONTRACT_VERSION", "") == "game-state-dashboard/v2-godot":
				found.append(node)
				break
			script = script.get_base_script()
	for child in node.get_children():
		found.append_array(reporter_candidates(child))
	return found

static func find_reporter(node: Node) -> Node:
	var found := reporter_candidates(node)
	return found[0] if found.size() == 1 else null

static func sample_pair(reporter: Node) -> Dictionary:
	# No frame or input advances between observations. Compare detached copies.
	var first: Variant = reporter.call("capture")
	if first is Dictionary: first = first.duplicate(true)
	var second: Variant = reporter.call("capture")
	if second is Dictionary: second = second.duplicate(true)
	return {"snapshot": first, "stable": first == second}

func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func validate(state: Variant, names: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not state is Dictionary or not names is Dictionary:
		return PackedStringArray(["Snapshot and vocabulary must be objects"])
	if not state.has_all(["revision", "process_id", "phase", "slots", "entities", "targets"]):
		return PackedStringArray(["Missing snapshot fields"])
	if not numeric(state.revision) or state.revision < 0 or state.revision != floor(state.revision): errors.append("Invalid revision")
	if not numeric(state.process_id) or state.process_id != OS.get_process_id(): errors.append("Wrong process identity")
	if not state.phase is String or state.phase not in PHASES: errors.append("Invalid phase")
	if not state.slots is Dictionary or not state.entities is Array or not state.targets is Array:
		return PackedStringArray(["Invalid snapshot collections"])
	for slot in names.get("slots", []):
		if not numeric(state.slots.get(slot)): errors.append("Missing/nonnumeric slot: " + slot)
	var entity_rules := {}
	for rule in names.get("entities", []): entity_rules[rule.kind] = rule.states
	for entity in state.entities:
		if not entity is Dictionary or not entity.has_all(["kind", "state", "cell"]):
			errors.append("Invalid entity shape"); continue
		if not entity.kind is String or not entity.state is String or not entity_rules.has(entity.kind) or entity.state not in entity_rules.get(entity.kind, []):
			errors.append("Invalid entity vocabulary")
		var cell: Variant = entity.cell
		if not cell is Array or cell.size() != 2:
			errors.append("Invalid entity coordinates"); continue
		if not numeric(cell[0]) or not numeric(cell[1]):
			errors.append("Nonnumeric coordinates"); continue
		if cell[0] < 0 or cell[1] < 0 or cell[0] >= names.level_width_cells or cell[1] >= names.level_height_cells:
			errors.append("Entity outside task bounds")
	var kinds := []
	for rule in names.get("targets", []): kinds.append(rule.kind)
	var viewport := root.get_visible_rect().size
	for target in state.targets:
		if not target is Dictionary or not target.has_all(["kind", "rect", "visible", "interactable"]):
			errors.append("Invalid target shape"); continue
		if not target.kind is String or target.kind not in kinds: errors.append("Invalid target kind")
		if not target.visible is bool or not target.interactable is bool:
			errors.append("Invalid target flags"); continue
		if target.interactable and not target.visible: errors.append("Hidden target is interactable")
		var rect: Variant = target.rect
		if not rect is Array or rect.size() != 4 or not rect.all(numeric):
			errors.append("Invalid target rect"); continue
		if rect[0] < 0 or rect[1] < 0 or rect[2] < 0 or rect[3] < 0 or (target.visible and (rect[2] <= 0 or rect[3] <= 0)) or rect[0]+rect[2] > viewport.x or rect[1]+rect[3] > viewport.y:
			errors.append("Target outside viewport")
	if not JSON.parse_string(JSON.stringify(state)) is Dictionary: errors.append("JSON roundtrip failed")
	return errors
