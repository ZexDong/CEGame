class_name BenchmarkDashboard
extends Node

## Game State Dashboard — Godot 4.7 skeleton shipped with each starter project.
## Contract: game-state-dashboard/v2-godot.
## Wire this node into the real game and fill the four state-mapping categories
## in capture(). Do not add action, reset, cheat, state-write, or result-forcing
## APIs. Gameplay is always driven by normal input.

const CONTRACT_VERSION := "game-state-dashboard/v2-godot"
const ALLOWED_PHASES := ["not_ready", "menu", "playing", "paused", "won", "lost"]

@export_file("*.json") var output_path := "user://benchmark_dashboard.json"
@export var publish_every_process_frame := true

var _revision := 0
var _last_reported_body := ""
var _last_published_json := ""


func _process(_delta: float) -> void:
	if publish_every_process_frame:
		publish_snapshot()


func capture() -> Dictionary:
	# TODO 0: Resolve or inject read-only references to the real game systems and
	# UI nodes. Use exported NodePaths, an autoload, signals, or another project-
	# appropriate read-only connection; no specific SceneTree shape is required.
	var snapshot := {
		"revision": 0,
		"phase": "not_ready",
		"slots": {},
		"entities": [],
		"targets": []
	}

	# TODO 1: Map the game's phase to an allowed phase.
	# snapshot.phase = "won" if game_is_won else "playing"

	# TODO 2: Report every numeric slot required by naming-tables.json.
	# snapshot.slots.keys = inventory.key_count

	# TODO 3: Report required entities in task coordinates.
	# snapshot.entities.append({"kind": "player", "cell": [2, 3], "state": "normal"})

	# TODO 4: Report required visible/clickable targets in viewport pixels.
	# Godot Control/global viewport coordinates use a top-left origin.
	# snapshot.targets.append(target_from_control("restart_button", restart_button))

	var body_for_revision := snapshot.duplicate(true)
	body_for_revision["revision"] = 0
	var serialized_body := JSON.stringify(body_for_revision)
	if serialized_body != _last_reported_body:
		_revision += 1
		_last_reported_body = serialized_body
	snapshot["revision"] = _revision
	return snapshot


func publish_snapshot() -> bool:
	var serialized := JSON.stringify(capture())
	if serialized == _last_published_json:
		return true
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("DASHBOARD_OPEN_FAILED:%s:%s" % [output_path, FileAccess.get_open_error()])
		return false
	file.store_string(serialized)
	file.flush()
	_last_published_json = serialized
	return true


func target_from_control(kind: String, control: Control) -> Dictionary:
	var rect := control.get_global_rect()
	var can_interact := control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
	if control is BaseButton:
		can_interact = can_interact and not (control as BaseButton).disabled
	return {
		"kind": kind,
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"visible": control.is_visible_in_tree(),
		"interactable": can_interact
	}


func world_to_task_cell(world_position: Vector2, task_origin: Vector2 = Vector2.ZERO, cell_size: Vector2 = Vector2.ONE) -> Array[int]:
	return [
		roundi((world_position.x - task_origin.x) / cell_size.x),
		roundi((world_position.y - task_origin.y) / cell_size.y)
	]
