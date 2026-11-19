extends "res://benchmark/dashboard_self_check.gd"

## Public package/entry smoke only. No journey solutions or private assertions.
func _run() -> void:
	var errors := PackedStringArray()
	var scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if scene_path != "res://src/main.tscn":
		errors.append("Configured main scene must be the published final entry")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		errors.append("Cannot load configured main scene")
		finish(errors, "PUBLIC_SMOKE")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(12):
		await process_frame
	var names: Variant = JSON.parse_string(FileAccess.get_file_as_string(NAMING_PATH))
	var reporter := find_dashboard(scene)
	if not names is Dictionary:
		errors.append("Naming tables are unreadable")
	elif reporter == null:
		errors.append("No read-only dashboard found")
	else:
		var pair := sample_pair(reporter)
		errors.append_array(validate(pair.snapshot, names, root.get_visible_rect().size))
		if not pair.stable: errors.append("Consecutive read-only observations changed")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		if frame == null or frame.is_empty():
			errors.append("No rendered viewport frame")
	finish(errors, "PUBLIC_SMOKE")
