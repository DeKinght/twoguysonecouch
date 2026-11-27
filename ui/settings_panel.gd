class_name SettingsPanel
extends VBoxContainer
## Zawartość ustawień (wspólna dla menu głównego i menu pauzy):
## czułość myszy + przypisywanie klawiszy (kliknij przycisk, naciśnij klawisz, Esc anuluje).

var _sens_slider: HSlider
var _sens_value: Label
var _volume_slider: HSlider
var _volume_value: Label
var _bind_buttons: Dictionary = {}  ## akcja -> Button
var _listening: String = ""


## Panel ustawień w przewijanym obszarze, który zajmuje dostępne miejsce w pionie.
## min_height = 0: kurczy się do miejsca, jakie zostało (menu główne);
## min_height > 0: stała wysokość (menu pauzy na środku ekranu).
static func wrap_in_scroll(min_height: float = 0.0) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, min_height)
	# Odstęp od paska przewijania, żeby nie nachodził na przyciski klawiszy.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	var panel := SettingsPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(panel)
	return scroll


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	custom_minimum_size = Vector2(560, 0)

	# --- Dźwięk ---
	var volume_row := HBoxContainer.new()
	add_child(volume_row)
	var volume_label := Label.new()
	volume_label.text = "Głośność"
	volume_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_label)
	_volume_value = Label.new()
	_volume_value.theme_type_variation = "HeadingLabel"
	volume_row.add_child(_volume_value)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = Settings.master_volume
	_volume_slider.custom_minimum_size = Vector2(0, 28)
	_volume_slider.scrollable = false
	_volume_slider.value_changed.connect(func(v: float) -> void: Settings.set_master_volume(v))
	add_child(_volume_slider)

	# --- Mysz ---
	var sens_row := HBoxContainer.new()
	add_child(sens_row)
	var sens_label := Label.new()
	sens_label.text = "Czułość myszy"
	sens_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_row.add_child(sens_label)
	_sens_value = Label.new()
	_sens_value.theme_type_variation = "HeadingLabel"
	sens_row.add_child(_sens_value)

	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.1
	_sens_slider.max_value = 3.0
	_sens_slider.step = 0.05
	_sens_slider.value = Settings.sensitivity_mult
	_sens_slider.custom_minimum_size = Vector2(0, 28)
	_sens_slider.scrollable = false  # kółko myszy przewija listę, a nie zmienia czułości
	_sens_slider.value_changed.connect(_on_sensitivity_changed)
	add_child(_sens_slider)

	add_child(HSeparator.new())

	# --- Klawisze ---
	var keys_label := Label.new()
	keys_label.text = "Sterowanie"
	keys_label.theme_type_variation = "HeadingLabel"
	add_child(keys_label)

	var hint := Label.new()
	hint.text = "Kliknij przycisk i naciśnij nowy klawisz. Esc anuluje."
	hint.theme_type_variation = "MutedLabel"
	add_child(hint)

	# Bez własnego przewijania - całość panelu przewija rodzic (SettingsPanel.wrap_in_scroll).
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)

	for entry: Array in Settings.ACTIONS:
		var action: String = entry[0]
		var label := Label.new()
		label.text = entry[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)

		var button := Button.new()
		button.theme_type_variation = "SmallButton"
		button.custom_minimum_size = Vector2(180, 0)
		button.pressed.connect(_start_listening.bind(action))
		grid.add_child(button)
		_bind_buttons[action] = button

	var reset := Button.new()
	reset.text = "PRZYWRÓĆ DOMYŚLNE"
	reset.theme_type_variation = "SmallButton"
	reset.pressed.connect(func() -> void:
		Settings.reset_defaults()
		_sens_slider.set_value_no_signal(Settings.sensitivity_mult)
		_volume_slider.set_value_no_signal(Settings.master_volume))
	add_child(reset)

	Settings.changed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_stop_listening())
	_refresh()


func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_stop_listening()
		else:
			Settings.rebind(_listening, key)
			_stop_listening()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return
		Settings.rebind(_listening, mouse)
		_stop_listening()
		get_viewport().set_input_as_handled()


func _start_listening(action: String) -> void:
	_stop_listening()
	_listening = action
	var button: Button = _bind_buttons[action]
	button.text = "Naciśnij klawisz…"
	button.theme_type_variation = "PrimaryButton"


func _stop_listening() -> void:
	if _listening == "":
		return
	var button: Button = _bind_buttons[_listening]
	button.theme_type_variation = "SmallButton"
	_listening = ""
	_refresh()


func _on_sensitivity_changed(value: float) -> void:
	Settings.set_sensitivity(value)


func _refresh() -> void:
	_sens_value.text = "%.2f×" % Settings.sensitivity_mult
	_volume_value.text = "Wyciszone" if Settings.master_volume <= 0.001 \
			else "%d%%" % roundi(Settings.master_volume * 100.0)
	for action: String in _bind_buttons:
		if action != _listening:
			(_bind_buttons[action] as Button).text = Settings.event_text(action)
