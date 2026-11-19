extends Node2D

func _ready() -> void:
	var player := get_node_or_null("Player")
	if player:
		player.global_position = Vector2(200, 40)
		player.input_enabled = true
