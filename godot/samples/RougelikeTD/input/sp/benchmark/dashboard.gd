class_name BenchmarkDashboard
extends Node
## Read-only starter adapter. Replace capture() with observations of real gameplay.
const CONTRACT_VERSION := "game-state-dashboard/v2-godot"
@export_file var output_path := "user://benchmark_dashboard.json"
var _revision := 0
var _body := ""

func _ready() -> void:
	seed(0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dashboard-output="):
			output_path = argument.trim_prefix("--dashboard-output=")
		elif argument.begins_with("--seed="):
			seed(int(argument.trim_prefix("--seed=")))

func capture() -> Dictionary:
	var names: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://benchmark/naming-tables.json"))
	var slots := {}
	for slot in names.get("slots", []):
		slots[slot] = 0
	# The unfinished starter contains no gameplay entities or controls.
	# Zero slots in not_ready mean unavailable, not a completed initial game.
	var snapshot := {"phase": "not_ready", "slots": slots, "entities": [], "targets": []}
	var body := JSON.stringify(snapshot)
	if body != _body:
		_revision += 1
		_body = body
	snapshot["revision"] = _revision
	snapshot["process_id"] = OS.get_process_id()
	return snapshot

func _process(_delta: float) -> void:
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("DASHBOARD_OPEN_FAILED: " + output_path)
		return
	file.store_string(JSON.stringify(capture()))
	file.flush()
