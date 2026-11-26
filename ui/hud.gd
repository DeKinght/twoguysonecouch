extends CanvasLayer
## Celownik, podpowiedź, lista szkód i skrót klawiszy. Cały interfejs budowany w kodzie.

const FEED_LINES: int = 6
const FEED_SECONDS: float = 8.0

@onready var grabber: Grabber = get_node("../Head/Camera3D/Grabber")

var _prompt: Label
var _feed: Label
var _total: Label
## Wpisy listy szkód: {text: String, expire: float}
var _feed_entries: Array[Dictionary] = []


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

	_feed = Label.new()
	_feed.position = Vector2(16, 40)
	_feed.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	add_child(_feed)

	_total = Label.new()
	_total.position = Vector2(16, 12)
	add_child(_total)

	var help := Label.new()
	help.text = "LPM: złap | B: popchnij gracza | Shift: sprint | Ctrl: kucnij"
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.offset_top = 12.0
	help.offset_right = -16.0
	add_child(help)

	Ledger.damage_recorded.connect(_on_damage)


func _process(_delta: float) -> void:
	_refresh_prompt()
	_refresh_feed()


func _on_damage(peer_id: int, item_name: String, loss: int) -> void:
	var text: String = "%s: %s −%d zł" % [Ledger.display_name(peer_id), item_name, loss]
	_feed_entries.append({"text": text, "expire": Time.get_ticks_msec() / 1000.0 + FEED_SECONDS})
	if _feed_entries.size() > FEED_LINES:
		_feed_entries.pop_front()


func _refresh_feed() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_feed_entries = _feed_entries.filter(func(e: Dictionary) -> bool: return e["expire"] > now)
	var lines: PackedStringArray = []
	for e in _feed_entries:
		lines.append(e["text"])
	_feed.text = "\n".join(lines)
	_total.text = "Straty: %d zł" % Ledger.total_lost()


func _refresh_prompt() -> void:
	if grabber.held != null and is_instance_valid(grabber.held):
		var h: Grabbable = grabber.held
		_prompt.text = "Trzymasz: %s (%.0f kg, %.0f zł) | kółko myszy: odległość | puść LPM, by upuścić" \
				% [h.item_name, h.mass, h.value]
	elif grabber.looked_at != null:
		var l: Grabbable = grabber.looked_at
		_prompt.text = "[LPM - trzymaj] Złap: %s (%.0f kg, %.0f zł)" % [l.item_name, l.mass, l.value]
	else:
		_prompt.text = ""
