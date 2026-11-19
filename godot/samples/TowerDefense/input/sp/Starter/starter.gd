extends Node2D

# Presentation-only scaffold. It intentionally contains no target navigation,
# asset binding, route, placement, economy, waves, combat, outcomes, or restart logic.

func _ready() -> void:
    var canvas := Control.new()
    canvas.name = "StarterCanvas"
    canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(canvas)

    var background := ColorRect.new()
    background.name = "ProceduralPlaceholder"
    background.color = Color("#162033")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(background)

    var panel := Panel.new()
    panel.position = Vector2(246, 112)
    panel.size = Vector2(660, 410)
    canvas.add_child(panel)

    var title := Label.new()
    title.text = "APE TOWER DEFENSE — FIXED V2"
    title.position = Vector2(55, 48)
    title.size = Vector2(550, 60)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 30)
    panel.add_child(title)

    var start := Button.new()
    start.name = "InertStartButton"
    start.text = "START (IMPLEMENT ME)"
    start.position = Vector2(190, 170)
    start.size = Vector2(280, 72)
    start.focus_mode = Control.FOCUS_NONE
    panel.add_child(start)

    var note := Label.new()
    note.text = "Raw artwork is unbound. Read GDD.md and TOOLCHAIN.md."
    note.position = Vector2(65, 292)
    note.size = Vector2(530, 52)
    note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    panel.add_child(note)
