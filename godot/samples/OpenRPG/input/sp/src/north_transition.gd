extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D and body.name == "Player":
		get_tree().set_meta("return_from_south", true)
		get_tree().change_scene_to_file("res://src/main.tscn")
