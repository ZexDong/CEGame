class_name BenchmarkDashboardSelfCheck
extends SceneTree

## Public format-only check. It accepts a truthful unfinished starter.
## This task uses viewport rectangles instead of grid coordinates.
const ALLOWED_PHASES := ["not_ready", "menu", "playing", "paused", "won", "lost"]
const CONTRACT_VERSION := "game-state-dashboard/v2-godot"
const NAMING_PATH := "res://benchmark/naming-tables.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		finish(PackedStringArray(["Cannot load configured main scene"]), "DASHBOARD_SELF_CHECK")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(4):
		await process_frame
	var names: Variant = JSON.parse_string(FileAccess.get_file_as_string(NAMING_PATH))
	if not names is Dictionary:
		finish(PackedStringArray(["Cannot read naming tables"]), "DASHBOARD_SELF_CHECK")
		return
	var reporter := find_dashboard(scene)
	if reporter == null:
		finish(PackedStringArray(["No dashboard reporting component found"]), "DASHBOARD_SELF_CHECK")
		return
	var pair := sample_pair(reporter)
	var errors := validate(pair.snapshot, names, root.get_visible_rect().size)
	if not pair.stable: errors.append("Consecutive read-only observations changed")
	finish(errors, "DASHBOARD_SELF_CHECK")

func finish(errors: PackedStringArray, label: String) -> void:
	if errors.is_empty():
		print(label + "_PASS")
		quit(0)
	else:
		for error in errors:
			push_error(label + "_FAILED: " + error)
		quit(1)

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

static func find_dashboard(node: Node) -> Node:
	var found := reporter_candidates(node)
	return found[0] if found.size() == 1 else null

static func sample_pair(reporter: Node) -> Dictionary:
	# No frame or input advances between observations. Compare detached copies.
	var first: Variant = reporter.call("capture")
	if first is Dictionary: first = first.duplicate(true)
	var second: Variant = reporter.call("capture")
	if second is Dictionary: second = second.duplicate(true)
	return {"snapshot": first, "stable": first == second}

static func number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func valid_rect(value: Variant, viewport_size: Vector2) -> bool:
	if not value is Array or value.size() != 4:
		return false
	for component in value:
		if not number(component):
			return false
	return value[0] >= 0 and value[1] >= 0 and value[2] > 0 and value[3] > 0 and value[0] + value[2] <= viewport_size.x + 0.01 and value[1] + value[3] <= viewport_size.y + 0.01

static func validate(snapshot: Variant, names: Dictionary, viewport_size: Vector2) -> PackedStringArray:
	var errors := PackedStringArray()
	if not snapshot is Dictionary:
		return PackedStringArray(["Snapshot must be an object"])
	for field in ["revision", "process_id", "phase", "slots", "entities", "targets"]:
		if not snapshot.has(field):
			errors.append("Missing snapshot field: " + field)
	if not errors.is_empty():
		return errors
	if not number(snapshot.revision) or snapshot.revision < 0 or snapshot.revision != floor(snapshot.revision):
		errors.append("revision must be a nonnegative integer")
	if not number(snapshot.process_id) or snapshot.process_id != OS.get_process_id():
		errors.append("process_id must identify the current process")
	if not snapshot.phase is String or snapshot.phase not in ALLOWED_PHASES:
		errors.append("Unknown phase")
	if not snapshot.slots is Dictionary or not snapshot.entities is Array or not snapshot.targets is Array:
		errors.append("slots/entities/targets have incorrect container types")
		return errors
	for definition in names.get("slot_definitions", []):
		var value: Variant = snapshot.slots.get(definition.name)
		if not number(value):
			errors.append("Missing or nonnumeric slot: " + definition.name)
			continue
		if definition.has("enum") and not definition.enum.any(func(candidate): return float(candidate) == float(value)):
			errors.append("Invalid enum slot: " + definition.name)
		if definition.has("min") and value < definition.min:
			errors.append("Slot below minimum: " + definition.name)
		if definition.has("max") and value > definition.max:
			errors.append("Slot above maximum: " + definition.name)
	var entity_rules := {}
	for rule in names.get("entities", []):
		entity_rules[rule.kind] = rule
	var seen_entities := {}
	for entity in snapshot.entities:
		if not entity is Dictionary:
			errors.append("Entity must be an object")
			continue
		var kind: Variant = entity.get("kind")
		if not kind is String or not entity_rules.has(kind):
			errors.append("Unknown entity kind")
			continue
		var identity: Variant = entity.get("id")
		if not identity is String or identity.is_empty() or seen_entities.has(identity):
			errors.append("Entity ID missing, invalid, or duplicated")
		else:
			seen_entities[identity] = true
		if entity.get("state") not in entity_rules[kind].states:
			errors.append("Invalid entity state: " + kind)
		if not valid_rect(entity.get("rect"), viewport_size):
			errors.append("Invalid entity viewport rect: " + kind)
		if entity_rules[kind].has("extra_fields"):
			var hp: Variant = entity.get("hp")
			var maximum: Variant = entity.get("max_hp")
			if not number(hp) or not number(maximum):
				errors.append("Combatant HP must be numeric")
			elif hp < 0 or maximum <= 0 or hp > maximum:
				errors.append("Combatant HP out of bounds")
			for flag in ["selected", "acting"]:
				if typeof(entity.get(flag)) != TYPE_BOOL:
					errors.append("Combatant flag must be boolean: " + flag)
	var target_rules := {}
	for rule in names.get("targets", []):
		target_rules[rule.kind] = true
	var seen_targets := {}
	for target in snapshot.targets:
		if not target is Dictionary:
			errors.append("Target must be an object")
			continue
		var kind: Variant = target.get("kind")
		if not kind is String or not target_rules.has(kind):
			errors.append("Unknown target kind")
			continue
		var identity: Variant = target.get("id")
		var unique := str(kind) + ":" + str(identity)
		if not identity is String or identity.is_empty() or seen_targets.has(unique):
			errors.append("Target ID missing, invalid, or duplicated")
		seen_targets[unique] = true
		if typeof(target.get("visible")) != TYPE_BOOL or typeof(target.get("interactable")) != TYPE_BOOL:
			errors.append("Target visibility/interaction flags must be boolean")
		elif target.interactable and not target.visible:
			errors.append("Hidden target cannot be interactable")
		if target.get("visible", false) and not valid_rect(target.get("rect"), viewport_size):
			errors.append("Invalid visible target rect")
		if kind == "combatant_target" and not seen_entities.has(identity):
			errors.append("Combatant target ID has no visible entity")
	if not JSON.parse_string(JSON.stringify(snapshot)) is Dictionary:
		errors.append("Snapshot must round-trip through JSON")
	return errors
