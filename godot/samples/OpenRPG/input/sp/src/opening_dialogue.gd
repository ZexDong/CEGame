extends CanvasLayer

signal finished

const TIMELINE_PATH := "res://maps/opening_cutscene.dtl"
const FALLBACK_LINES := [
	"Help me...",
	"Please help me...",
	"How many years have I been waiting?",
	"You were programmed for ONE JOB, meet me in the woods! Did your batteries run out? Why are they working now?",
	"I'm so hungry. Should have packed a lunch. Please help me..."
]

var lines: Array[String] = []
var current_line := 0

@onready var dialogue_text: RichTextLabel = $Shade/DialogBox/DialogueText
@onready var continue_hint: Label = $Shade/DialogBox/ContinueHint


func _ready() -> void:
	_load_preserved_dialogue()
	_show_current_line()


func _input(event: InputEvent) -> void:
	# Handle modal dialogue before its Control nodes consume mouse input.
	if not visible or event.is_echo():
		return

	var advance := event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")
	if event is InputEventMouseButton:
		advance = advance or (event.button_index == MOUSE_BUTTON_LEFT and event.pressed)

	if advance:
		get_viewport().set_input_as_handled()
		current_line += 1
		if current_line >= lines.size():
			visible = false
			finished.emit()
		else:
			_show_current_line()


func _load_preserved_dialogue() -> void:
	if FileAccess.file_exists(TIMELINE_PATH):
		var source := FileAccess.get_file_as_string(TIMELINE_PATH)
		for raw_line in source.split("\n"):
			var clean_line := raw_line.strip_edges()
			if not clean_line.is_empty():
				lines.append(clean_line)

	if lines.is_empty():
		lines.assign(FALLBACK_LINES)


func _show_current_line() -> void:
	dialogue_text.text = lines[current_line]
	continue_hint.text = "Enter / Space / Click  •  %d of %d" % [current_line + 1, lines.size()]
