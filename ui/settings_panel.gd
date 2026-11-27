class_name SettingsPanel
extends VBoxContainer
## Zawartość ustawień (wspólna dla menu głównego i menu pauzy):
## czułość myszy + przypisywanie klawiszy (kliknij przycisk, naciśnij klawisz, Esc anuluje).

var _sens_slider: HSlider
var _sens_value: Label
var _bind_buttons: Dictionary = {}  ## akcja -> Button
var _listening: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	custom_minimum_size = Vector2(560, 0)

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

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

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
		_sens_slider.set_value_no_signal(Settings.sensitivity_mult))
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
	for action: String in _bind_buttons:
		if action != _listening:
			(_bind_buttons[action] as Button).text = Settings.event_text(action)
