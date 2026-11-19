class_name BenchmarkDashboard
extends Node

## Public read-only skeleton and truthful adapter for the supplied forest starter.
## Extend the state mapping when implementing gameplay; never add action APIs.
const CONTRACT_VERSION := "game-state-dashboard/v2-godot"
const NAMES_PATH := "res://benchmark/naming-tables.json"

@export var player_path: NodePath
@export var dialogue_path: NodePath
@export_file var output_path := "user://benchmark_dashboard.json"

var _revision := 0
var _previous_body := ""
var _published := ""
var _default_slots: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var names: Variant = JSON.parse_string(FileAccess.get_file_as_string(NAMES_PATH))
	if names is Dictionary:
		for definition in names.get("slot_definitions", []):
			_default_slots[definition.name] = definition.starter_value
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dashboard-output="):
			output_path = argument.trim_prefix("--dashboard-output=")

func _process(_delta: float) -> void:
	publish_snapshot()

func capture() -> Dictionary:
	# Replace only this mapping with read-only access to your actual systems.
	# The remaining adventure does not exist in the starter: it has no completed
	# objectives, inventory rewards, battles, or ending to report.
	var slots := _default_slots.duplicate(true)
	var entities: Array = []
	var targets: Array = []
	var player := get_node_or_null(player_path) as Node2D
	var dialogue := get_node_or_null(dialogue_path) as CanvasLayer
	var dialogue_open := dialogue != null and dialogue.visible
	slots["dialogue_open"] = int(dialogue_open)
	slots["opening_line"] = int(dialogue.get("current_line")) + 1 if dialogue_open else 0
	slots["opening_complete"] = int(not dialogue_open and dialogue != null)
	if player != null and player.is_visible_in_tree() and not dialogue_open:
		var sprite := player.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			var rect := sprite.get_global_transform_with_canvas() * sprite.get_rect()
			rect = rect.intersection(get_viewport().get_visible_rect())
			if rect.has_area():
				entities.append({"kind": "player", "id": "gobot", "state": "normal", "rect": rect_array(rect)})
	if dialogue_open:
		var surface := dialogue.get_node_or_null("Shade/DialogBox") as Control
		if surface != null:
			targets.append({"kind": "dialogue_continue", "id": "opening_continue", "rect": rect_array(surface.get_global_rect()), "visible": true, "interactable": true})
	return stamp({"phase": "playing", "slots": slots, "entities": entities, "targets": targets})

func stamp(body: Dictionary) -> Dictionary:
	body["process_id"] = OS.get_process_id()
	body.erase("revision")
	var serialized := JSON.stringify(body)
	if serialized != _previous_body:
		_revision += 1
		_previous_body = serialized
	body["revision"] = _revision
	return body

func publish_snapshot() -> bool:
	var serialized := JSON.stringify(capture())
	if serialized == _published:
		return true
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("DASHBOARD_OPEN_FAILED: %s" % output_path)
		return false
	file.store_string(serialized)
	file.flush()
	file.close()
	_published = serialized
	return true

static func rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
