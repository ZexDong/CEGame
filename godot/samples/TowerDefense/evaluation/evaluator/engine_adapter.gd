extends RefCounted

## TowerDefense input adapter. Runtime decisions use only the public dashboard:
## exact semantic selectors, their visible/interactable flags, and their rects.
## Gameplay is driven only through normal window-local mouse events.

func _center(target: Dictionary) -> Vector2:
	var rect: Array = target.get("rect", [])
	if rect.size() != 4: return Vector2(-1, -1)
	return Vector2(float(rect[0]) + float(rect[2]) * 0.5, float(rect[1]) + float(rect[3]) * 0.5)

func _drag_points(driver, start: Vector2, finish: Vector2) -> bool:
	if start.x < 0.0 or finish.x < 0.0: return false
	# Window.push_input is explicitly permitted by the shared tool guide. Do not
	# call Input.parse_input_event: TowerDefense never uses the system mouse.
	var down := InputEventMouseButton.new()
	down.position = start; down.global_position = start
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	driver.root.push_input(down, true)
	await driver.process_frame
	for i in range(1, 13):
		var position := start.lerp(finish, float(i) / 12.0)
		var motion := InputEventMouseMotion.new()
		motion.position = position; motion.global_position = position
		motion.relative = (finish - start) / 12.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		driver.root.push_input(motion, true)
		await driver.process_frame
	var up := InputEventMouseButton.new()
	up.position = finish; up.global_position = finish
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	driver.root.push_input(up, true)
	await driver._settle(12)
	return true

func prepare(action: Dictionary, driver) -> Dictionary:
	if str(action.get("do", "")) != "drag": return {"prepared": false}
	var from_selector: Dictionary = action.get("from", {})
	var to_selector: Dictionary = action.get("to", {})
	var starts: Array = driver._targets(from_selector)
	var ends: Array = driver._targets(to_selector)
	if starts.is_empty() or ends.is_empty():
		# Leave the action to the generic strict resolver. It will record an
		# unavailable public target without guessing state, ordering, or position.
		return {"prepared": false}
	var before_count := int(driver._state().get("slots", {}).get("tower_count", -1))
	var sent := await _drag_points(driver, _center(starts[0]), _center(ends[0]))
	var after_count := int(driver._state().get("slots", {}).get("tower_count", -1))
	var built := after_count > before_count
	return {"consumed": true, "ok": sent and built, "route": "dashboard_exact_mouse_drag", "effect_observed": built}
