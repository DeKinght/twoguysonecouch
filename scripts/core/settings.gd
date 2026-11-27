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
	["shove", "Popchnij kumpla"],
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
## Otwarte menu pauzy - gracz nie steruje postacią.
var menu_open: bool = false

## akcja -> Array[InputEvent] (stan sprzed wczytania ustawień)
var _defaults: Dictionary = {}


func _ready() -> void:
	for entry: Array in ACTIONS:
		var action: String = entry[0]
		_defaults[action] = InputMap.action_get_events(action).duplicate()
	_load()


## Czy sterowanie postacią jest zablokowane (menu pauzy albo ekran podsumowania).
func input_blocked() -> bool:
	return menu_open or Net.input_locked


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
