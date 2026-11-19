extends "res://benchmark/dashboard_self_check.gd"
## Entry and observation health only. No gameplay actions or completion assertions.
func _run() -> void:
	var path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if path != "res://main.tscn":
		push_error("Required final entry is res://main.tscn"); quit(1); return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Cannot load configured entry"); quit(1); return
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	for frame in range(12): await process_frame
	var reporter := find_reporter(main)
	if reporter == null:
		push_error("Dashboard missing"); quit(1); return
	var names: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://benchmark/naming-tables.json"))
	var pair := sample_pair(reporter)
	var errors := validate(pair.snapshot, names)
	if not pair.stable: errors.append("Consecutive read-only observations changed")
	if not errors.is_empty():
		for error in errors: push_error(error)
		quit(1); return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		if frame == null or frame.is_empty():
			push_error("No rendered frame"); quit(1); return
	print("PUBLIC_SMOKE_PASS:" + path)
	quit(0)
