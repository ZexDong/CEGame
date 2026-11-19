extends CharacterBody2D

@export var move_speed := 90.0

var input_enabled := false
var south_gate_open := false
var gate_position := Vector2(56, 72)
var movement_bounds := Rect2(Vector2.ZERO, Vector2(960, 560))

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	if get_tree().has_meta("return_from_south"):
		global_position = Vector2(200, 264)
		get_tree().remove_meta("return_from_south")


func _physics_process(_delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		return

	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if not south_gate_open and global_position.distance_to(gate_position) < 28.0:
		velocity = Vector2.ZERO
		if Input.is_action_just_pressed("ui_accept"):
			south_gate_open = true
			global_position = Vector2(56, 520)
			$"../HUD/Controls".text = "SOUTHERN FOREST  •  MOVE: WASD / ARROW KEYS"
		else:
			$"../HUD/Controls".text = "A GHOST BLOCKS THE TREE PASSAGE  •  ENTER / SPACE"
		return
	velocity = direction * move_speed

	if not is_zero_approx(direction.x):
		sprite.flip_h = direction.x < 0.0

	move_and_slide()
	global_position = global_position.clamp(
		movement_bounds.position + Vector2(8, 8),
		movement_bounds.end - Vector2(8, 8)
	)


func enable_input() -> void:
	input_enabled = true
