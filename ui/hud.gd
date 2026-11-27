extends CanvasLayer
## HUD w grze: celownik, podpowiedź, lista szkód, czas zlecenia, skróty klawiszy.
## Dodaje też menu pauzy (Esc). Istnieje tylko dla lokalnego gracza.

const FEED_LINES: int = 6
const FEED_SECONDS: float = 8.0
const DOT_SMALL: float = 8.0
const DOT_BIG: float = 14.0

@onready var grabber: Grabber = get_node("../Head/Camera3D/Grabber")

var _root: Control
var _crosshair: Panel
var _crosshair_style: StyleBoxFlat
var _prompt_panel: PanelContainer
var _prompt: Label
var _damage_panel: PanelContainer
var _total: Label
var _feed: Label
var _job_panel: PanelContainer
var _job: Label
var _help: Label
## Wpisy listy szkód: {text: String, expire: float}
var _feed_entries: Array[Dictionary] = []


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_build_crosshair()
	_build_prompt()
	_build_damage_panel()
	_build_job_panel()
	_build_help()
	UITheme.ignore_mouse(_root)

	add_child(PauseMenu.new())

	Ledger.damage_recorded.connect(_on_damage)
	Settings.changed.connect(_refresh_help)
	_refresh_help()


func _process(_delta: float) -> void:
	_refresh_crosshair()
	_refresh_prompt()
	_refresh_feed()
	_refresh_job()


# --- Budowa ---------------------------------------------------------------------------

func _build_crosshair() -> void:
	_crosshair = Panel.new()
	_crosshair_style = StyleBoxFlat.new()
	_crosshair_style.bg_color = UITheme.TEXT
	_crosshair_style.set_corner_radius_all(16)
	_crosshair_style.set_border_width_all(2)
	_crosshair_style.border_color = Color(0, 0, 0, 0.5)
	_crosshair.add_theme_stylebox_override("panel", _crosshair_style)
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_set_dot_size(DOT_SMALL)
	_root.add_child(_crosshair)


func _set_dot_size(size: float) -> void:
	_crosshair.offset_left = -size * 0.5
	_crosshair.offset_right = size * 0.5
	_crosshair.offset_top = -size * 0.5
	_crosshair.offset_bottom = size * 0.5


func _build_prompt() -> void:
	_prompt_panel = _pill()
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.anchor_top = 1.0
	_prompt_panel.anchor_bottom = 1.0
	_prompt_panel.offset_bottom = -120
	_prompt_panel.offset_top = -120
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_prompt_panel)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt_panel.add_child(_prompt)


func _build_damage_panel() -> void:
	_damage_panel = _pill()
	_damage_panel.position = Vector2(32, 32)
	_root.add_child(_damage_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_damage_panel.add_child(box)
	_total = Label.new()
	_total.theme_type_variation = "HeadingLabel"
	_total.add_theme_font_size_override("font_size", 24)
	box.add_child(_total)
	_feed = Label.new()
	_feed.add_theme_color_override("font_color", UITheme.DANGER_HOVER)
	_feed.add_theme_font_size_override("font_size", 18)
	box.add_child(_feed)


func _build_job_panel() -> void:
	_job_panel = _pill()
	_job_panel.anchor_left = 0.5
	_job_panel.anchor_right = 0.5
	_job_panel.offset_top = 28
	_job_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_job_panel)
	_job = Label.new()
	_job.theme_type_variation = "HeadingLabel"
	_job.add_theme_font_size_override("font_size", 26)
	_job_panel.add_child(_job)


func _build_help() -> void:
	var panel := _pill()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -32
	panel.offset_right = -32
	panel.offset_top = 32
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.modulate.a = 0.85
	_root.add_child(panel)
	_help = Label.new()
	_help.theme_type_variation = "MutedLabel"
	panel.add_child(_help)


func _pill() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "PillPanel"
	return panel


# --- Odświeżanie -------------------------------------------------------------------------

func _refresh_help() -> void:
	_help.text = "[%s] złap    [%s] popchnij    [Esc] menu" % [
		Settings.event_text("grab"), Settings.event_text("shove")]


func _refresh_crosshair() -> void:
	var active: bool = grabber.looked_at != null or grabber.held != null
	_crosshair_style.bg_color = UITheme.PRIMARY if active else UITheme.TEXT
	_set_dot_size(DOT_BIG if active else DOT_SMALL)


func _refresh_prompt() -> void:
	var text: String = ""
	if grabber.held != null and is_instance_valid(grabber.held):
		var h: Grabbable = grabber.held
		text = "Trzymasz: %s   •   %.0f kg   •   %.0f zł        kółko myszy: odległość" \
				% [h.item_name, h.mass, h.value]
	elif grabber.looked_at != null:
		var l: Grabbable = grabber.looked_at
		text = "[%s]  %s   •   %.0f kg   •   %.0f zł" \
				% [Settings.event_text("grab"), l.item_name, l.mass, l.value]
	_prompt.text = text
	_prompt_panel.visible = text != ""


func _on_damage(peer_id: int, item_name: String, loss: int) -> void:
	var text: String = "%s: %s  −%d zł" % [Ledger.display_name(peer_id), item_name, loss]
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
	_feed.visible = not lines.is_empty()
	var lost: int = Ledger.total_lost()
	_total.text = "Straty: %d zł" % lost
	_damage_panel.visible = lost > 0 or not lines.is_empty()


func _refresh_job() -> void:
	var job := get_tree().get_first_node_in_group("job") as JobManager
	_job_panel.visible = job != null
	if job == null:
		return
	var seconds: int = ceili(job.time_left)
	_job.text = "%d:%02d    •    W busie: %d / %d" % [seconds / 60, seconds % 60, job.loaded_count, job.total_count]
