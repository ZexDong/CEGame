class_name BenchmarkDashboardSelfCheck
extends SceneTree

## Dependency-free format/completeness check for Godot 4.7.
## This mirrors DashboardSelfCheck.cs: one frame/settled snapshot, required
## slots, allowed entity kinds/states and bounded cells, bounded target rects,
## and a JSON round-trip. It validates the public observation contract, not gameplay.

const ALLOWED_PHASES := ["not_ready", "menu", "playing", "paused", "won", "lost"]
const CONTRACT_VERSION := "game-state-dashboard/v2-godot"
const DEFAULT_NAMING_TABLES_PATH := "res://benchmark/naming-tables.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path.is_empty():
		_fail(PackedStringArray(["application/run/main_scene is not configured"]))
		return
	var packed_scene := load(main_scene_path) as PackedScene
	if packed_scene == null:
		_fail(PackedStringArray(["Cannot load main scene: %s" % main_scene_path]))
		return
	var main_scene := packed_scene.instantiate()
	root.add_child(main_scene)
	await process_frame

	var dashboard := _find_dashboard(main_scene)
	if dashboard == null:
		_fail(PackedStringArray(["No BenchmarkDashboard implementation found in the loaded main scene"]))
		return
	var naming_tables_path := _command_line_value("--naming-tables=", DEFAULT_NAMING_TABLES_PATH)
	var errors := validate(dashboard, load_json_object(naming_tables_path), Vector2(root.size))
	if not errors.is_empty():
		_fail(errors)
		return
	print("DASHBOARD_SELF_CHECK_PASS")
	quit(0)


func _fail(errors: PackedStringArray) -> void:
	for error in errors:
		push_error("DASHBOARD_SELF_CHECK_FAILED:%s" % error)
	quit(1)


static func _command_line_value(prefix: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


static func _find_dashboard(node: Node) -> Node:
	if node.has_method("capture"):
		return node
	for child in node.get_children():
		var found: Node = _find_dashboard(child)
		if found != null:
			return found
	return null


static func _contract_version(dashboard: Node) -> String:
	var script := dashboard.get_script() as Script
	if script == null:
		return ""
	return String(script.get_script_constant_map().get("CONTRACT_VERSION", ""))


static func load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Cannot open JSON file: %s" % path)
	var value = JSON.parse_string(file.get_as_text())
	assert(typeof(value) == TYPE_DICTIONARY, "Expected a JSON object: %s" % path)
	return value


static func validate(dashboard: Node, naming_tables: Dictionary, viewport_size: Vector2) -> PackedStringArray:
	var errors := PackedStringArray()
	var actual_contract := _contract_version(dashboard)
	if actual_contract != CONTRACT_VERSION:
		errors.append("Wrong contract version: %s" % actual_contract)
	var snapshot: Variant = dashboard.call("capture")
	if typeof(snapshot) != TYPE_DICTIONARY:
		errors.append("capture() did not return a Dictionary")
		return errors

	for field in ["revision", "phase", "slots", "entities", "targets"]:
		if not snapshot.has(field):
			errors.append("Missing snapshot field: %s" % field)
	if not errors.is_empty():
		return errors

	if snapshot.revision < 0:
		errors.append("revision must be non-negative")
	if snapshot.phase not in ALLOWED_PHASES:
		errors.append("Unsupported phase: %s" % snapshot.phase)

	for required_slot in naming_tables.get("slots", []):
		if not snapshot.slots.has(required_slot):
			errors.append("Missing required slot: %s" % required_slot)
		elif typeof(snapshot.slots[required_slot]) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("Slot must be numeric: %s" % required_slot)

	var entity_rules := {}
	for rule in naming_tables.get("entities", []):
		entity_rules[rule.kind] = rule.get("states", [])
	for entity in snapshot.entities:
		if not entity_rules.has(entity.kind):
			errors.append("Unknown entity kind: %s" % entity.kind)
			continue
		var allowed_states: Array = entity_rules[entity.kind]
		if not allowed_states.is_empty() and entity.state not in allowed_states:
			errors.append("Invalid state '%s' for entity '%s'" % [entity.state, entity.kind])
		if not entity.has("cell") or typeof(entity.cell) != TYPE_ARRAY or entity.cell.size() != 2:
			errors.append("Entity '%s' cell must contain exactly two coordinates" % entity.kind)
		else:
			var width := _level_dimension(naming_tables, "level_width_cells")
			var height := _level_dimension(naming_tables, "level_height_cells")
			if width >= 0 and height >= 0 and (entity.cell[0] < 0 or entity.cell[0] >= width or entity.cell[1] < 0 or entity.cell[1] >= height):
				errors.append("Entity '%s' cell is outside the level (%dx%d)" % [entity.kind, width, height])
	if entity_rules.has("player") and not snapshot.entities.any(func(entity): return entity.kind == "player"):
		errors.append("Required entity 'player' is not reported")

	var target_kinds := {}
	for rule in naming_tables.get("targets", []):
		target_kinds[rule.kind] = true
	for target in snapshot.targets:
		if not target_kinds.has(target.kind):
			errors.append("Unknown target kind: %s" % target.kind)
		if target.rect.size() != 4:
			errors.append("Target rect must be [x,y,width,height]: %s" % target.kind)
			continue
		var rect := Rect2(target.rect[0], target.rect[1], target.rect[2], target.rect[3])
		if rect.size.x < 0 or rect.size.y < 0 or rect.position.x < 0 or rect.position.y < 0 or rect.end.x > viewport_size.x or rect.end.y > viewport_size.y:
			errors.append("Target rect is outside the viewport: %s" % target.kind)
	# As in the Unity self-check, target entries are validated when reported;
	# naming tables describe allowed kinds but do not require every target to
	# exist in every phase (for example, a menu button can be absent in play).

	var round_trip = JSON.parse_string(JSON.stringify(snapshot))
	if typeof(round_trip) != TYPE_DICTIONARY:
		errors.append("Snapshot JSON did not round-trip as an object")
	return errors


static func _level_dimension(naming_tables: Dictionary, key: String) -> int:
	if not naming_tables.has(key):
		return -1
	var value = naming_tables[key]
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT:
		return int(value)
	if typeof(value) == TYPE_STRING and String(value).is_valid_int():
		return int(value)
	return -1


static func assert_valid(dashboard: Node, naming_tables_path: String, viewport_size: Vector2) -> void:
	var errors := validate(dashboard, load_json_object(naming_tables_path), viewport_size)
	assert(errors.is_empty(), "Dashboard self-check failed:\n%s" % "\n".join(errors))
