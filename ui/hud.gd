extends CanvasLayer
## Celownik i podpowiedź. Cały interfejs budowany w kodzie (bez ręcznego układania Control-i).

@onready var grabber: Grabber = get_node("../Head/Camera3D/Grabber")

var _prompt: Label


func _ready() -> void:
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(crosshair)

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -90.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)

	grabber.target_changed.connect(func(_i: Grabbable) -> void: _refresh())
	grabber.grab_started.connect(func(_i: Grabbable) -> void: _refresh())
	grabber.grab_ended.connect(func(_i: Grabbable) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	if grabber.held != null:
		_prompt.text = "Trzymasz: %s (%.0f kg) | kółko myszy: odległość | puść LPM, by upuścić" \
				% [grabber.held.item_name, grabber.held.mass]
	elif grabber.looked_at != null:
		_prompt.text = "[LPM - trzymaj] Złap: %s (%.0f kg)" \
				% [grabber.looked_at.item_name, grabber.looked_at.mass]
	else:
		_prompt.text = ""
