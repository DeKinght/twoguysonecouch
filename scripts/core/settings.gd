extends Node
## Autoload "Settings": czułość myszy, przypisania klawiszy, stan menu.
## Zapisywane w user://settings.cfg (na Windows: %APPDATA%\Godot\app_userdata\<nazwa gry>).
## Musi być w autoloadach PO InputSetup, bo zapamiętuje jego domyślne klawisze.

signal changed

const PATH: String = "user://settings.cfg"

## Akcje do przypisania w ustawieniach: [nazwa akcji, opis].
const ACTIONS: Array = [
	["move_forward", "Do przodu"],
	["move_back", "Do tyłu"],
	["move_left", "W lewo"],
	["move_right", "W prawo"],
	["jump", "Skok"],
	["sprint", "Sprint"],
	["crouch", "Kucanie"],
	["grab", "Chwyć / trzymaj"],
	["interact", "Użyj (drzwi, brama, auto)"],
	["shove", "Popchnij kumpla"],
	["camera_toggle", "Kamera w aucie (1. / 3. osoba)"],
]

const KEY_NAMES: Dictionary = {
	"Space": "Spacja",
	"Escape": "Esc",
	"Up": "↑",
	"Down": "↓",
	"Left": "←",
	"Right": "→",
}

## Mnożnik czułości myszy (1.0 = domyślna).
var sensitivity_mult: float = 1.0
## Głośność całej gry (0.0 - 1.0), szyna audio "Master".
var master_volume: float = 1.0
## Limit klatek na sekundę (0 = bez limitu). Mniej klatek = chłodniejszy, cichszy laptop.
var max_fps: int = 60
const FPS_OPTIONS: Array[int] = [30, 60, 90, 120, 144, 0]
## Otwarte menu pauzy - gracz nie steruje postacią.
var menu_open: bool = false

## akcja -> Array[InputEvent] (stan sprzed wczytania ustawień)
var _defaults: Dictionary = {}


func _ready() -> void:
	for entry: Array in ACTIONS:
		var action: String = entry[0]
		_defaults[action] = InputMap.action_get_events(action).duplicate()
	_load()
	_apply_volume()
	_apply_fps()
	_build_perf_overlay()


## Czy sterowanie postacią jest zablokowane (menu pauzy albo ekran podsumowania).
func input_blocked() -> bool:
	return menu_open or Net.input_locked


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	_save()
	changed.emit()


func _apply_volume() -> void:
	var bus: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.001)))


func set_max_fps(value: int) -> void:
	max_fps = value if value in FPS_OPTIONS else 60
	_apply_fps()
	_save()
	changed.emit()


func _apply_fps() -> void:
	Engine.max_fps = max_fps


static func fps_text(value: int) -> String:
	return "Bez limitu" if value == 0 else "%d FPS" % value


# --- Licznik wydajności (F3) ---------------------------------------------------------

var _perf_layer: CanvasLayer
var _perf_label: Label


func _build_perf_overlay() -> void:
	_perf_layer = CanvasLayer.new()
	_perf_layer.layer = 100
	_perf_layer.visible = false
	add_child(_perf_layer)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(16, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perf_layer.add_child(panel)
	_perf_label = Label.new()
	_perf_label.add_theme_font_size_override("font_size", 16)
	_perf_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	panel.add_child(_perf_label)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_perf_layer.visible = not _perf_layer.visible


func _process(_delta: float) -> void:
	if _perf_layer == null or not _perf_layer.visible:
		return
	var fps: float = Engine.get_frames_per_second()
	_perf_label.text = "FPS: %d   (%.1f ms)   limit: %s\nObiekty: %d   Wywołania rysowania: %d\nTrójkąty: %.0f tys.   Pamięć wideo: %d MB" % [
		fps, 1000.0 / maxf(fps, 1.0), fps_text(max_fps),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]


func set_sensitivity(value: float) -> void:
	sensitivity_mult = clampf(value, 0.1, 3.0)
	_save()
	changed.emit()


## Przypisuje akcji nowy klawisz / przycisk myszy. Ten sam klawisz znika z innych akcji.
func rebind(action: String, event: InputEvent) -> void:
	var clean: InputEvent = _clean(event)
	if clean == null:
		return
	for entry: Array in ACTIONS:
		var other: String = entry[0]
		if other != action and InputMap.action_has_event(other, clean):
			InputMap.action_erase_event(other, clean)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	_save()
	changed.emit()


func reset_defaults() -> void:
	for action: String in _defaults:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _defaults[action]:
			InputMap.action_add_event(action, ev)
	sensitivity_mult = 1.0
	master_volume = 1.0
	max_fps = 60
	_apply_volume()
	_apply_fps()
	_save()
	changed.emit()


## Czytelna nazwa pierwszego klawisza przypisanego do akcji, np. "W", "LPM", "Spacja".
func event_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return "—"
	return _event_name(events[0])


func _event_name(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var key := ev as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var text: String = OS.get_keycode_string(code)
		return KEY_NAMES.get(text, text)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LPM"
			MOUSE_BUTTON_RIGHT:
				return "PPM"
			MOUSE_BUTTON_MIDDLE:
				return "ŚPM"
			_:
				return "Mysz %d" % (ev as InputEventMouseButton).button_index
	return "?"


func _clean(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey:
		var src := ev as InputEventKey
		var key := InputEventKey.new()
		key.physical_keycode = src.physical_keycode if src.physical_keycode != KEY_NONE else src.keycode
		return key
	if ev is InputEventMouseButton:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = (ev as InputEventMouseButton).button_index
		return mouse
	return null


# --- Zapis / odczyt ---------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("mouse", "sensitivity", sensitivity_mult)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "max_fps", max_fps)
	for entry: Array in ACTIONS:
		var action: String = entry[0]
		var parts: PackedStringArray = []
		for ev: InputEvent in InputMap.action_get_events(action):
			var s: String = _serialize(ev)
			if s != "":
				parts.append(s)
		cfg.set_value("input", action, ",".join(parts))
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sensitivity_mult = clampf(float(cfg.get_value("mouse", "sensitivity", 1.0)), 0.1, 3.0)
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	var fps: int = int(cfg.get_value("video", "max_fps", 60))
	max_fps = fps if fps in FPS_OPTIONS else 60
	for entry: Array in ACTIONS:
		var action: String = entry[0]
		if not cfg.has_section_key("input", action):
			continue
		var events: Array[InputEvent] = []
		for s: String in str(cfg.get_value("input", action)).split(",", false):
			var ev: InputEvent = _deserialize(s)
			if ev != null:
				events.append(ev)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for ev: InputEvent in events:
			InputMap.action_add_event(action, ev)


func _serialize(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var key := ev as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d" % code
	if ev is InputEventMouseButton:
		return "mouse:%d" % (ev as InputEventMouseButton).button_index
	return ""


func _deserialize(s: String) -> InputEvent:
	var parts: PackedStringArray = s.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var n: int = parts[1].to_int()
	match parts[0]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = n as Key
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = n as MouseButton
			return mouse
	return null
