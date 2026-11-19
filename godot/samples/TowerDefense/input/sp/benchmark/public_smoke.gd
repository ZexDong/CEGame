extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if scene_path.is_empty():
		push_error("PUBLIC_SMOKE_FAILED: application/run/main_scene is not configured")
		quit(1)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("PUBLIC_SMOKE_FAILED: cannot load %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	await process_frame
	await process_frame
	print("PUBLIC_SMOKE_PASS:%s" % scene_path)
	quit(0)

