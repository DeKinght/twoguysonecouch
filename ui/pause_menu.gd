class_name PauseMenu
extends CanvasLayer
## Menu pod Esc w trakcie gry: wróć, ustawienia, wyjdź do menu, wyjdź z gry.
## Gra sieciowa się NIE zatrzymuje - blokujemy tylko sterowanie lokalnego gracza.

var _panel: PanelContainer
var _main_page: VBoxContainer
var _settings_page: VBoxContainer
var _leave_button: Button
var _leave_confirm: bool = false


func _ready() -> void:
	layer = 15
	visible = false

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(UITheme.BG_DARK, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	center.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)

	_main_page = _build_main_page()
	box.add_child(_main_page)
	_settings_page = _build_settings_page()
	box.add_child(_settings_page)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not visible:
		open()
	elif _settings_page.visible:
		_show_main()
	else:
		close()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if visible:  # tylko otwarte menu zdejmuje blokadę (np. przy zmianie sceny)
		Settings.menu_open = false


func open() -> void:
	visible = true
	Settings.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * 0.94
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.2)


func close() -> void:
	visible = false
	Settings.menu_open = false
	if not Net.input_locked:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_main_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(480, 0)
	page.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = "PRZERWA NA KAWĘ"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Gra leci dalej - ekipa nie czeka!"
	subtitle.theme_type_variation = "MutedLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(subtitle)

	page.add_child(_button("WRÓĆ DO GRY", "PrimaryButton", close))
	page.add_child(_button("USTAWIENIA", "", _show_settings))
	_leave_button = _button("WYJDŹ DO MENU", "", _on_leave_pressed)
	page.add_child(_leave_button)
	page.add_child(_button("WYJDŹ Z GRY", "DangerButton", _on_quit_pressed))
	return page


func _build_settings_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "USTAWIENIA"
	title.theme_type_variation = "TitleLabel"
	page.add_child(title)
	page.add_child(SettingsPanel.wrap_in_scroll(540.0))
	page.add_child(_button("WRÓĆ", "", _show_main))
	return page


func _button(text: String, variation: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	if variation != "":
		button.theme_type_variation = variation
	button.pressed.connect(on_pressed)
	UITheme.juice(button)
	return button


func _show_main() -> void:
	_main_page.visible = true
	_settings_page.visible = false
	_leave_confirm = false
	_leave_button.text = "WYJDŹ DO MENU"
	_leave_button.theme_type_variation = ""


func _show_settings() -> void:
	_main_page.visible = false
	_settings_page.visible = true


func _is_hosting() -> bool:
	return multiplayer.is_server() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func _on_leave_pressed() -> void:
	# Host wychodzi = gra kończy się dla wszystkich, więc pytamy drugi raz.
	if _is_hosting() and not _leave_confirm:
		_leave_confirm = true
		_leave_button.text = "NA PEWNO? KOŃCZY GRĘ WSZYSTKIM"
		_leave_button.theme_type_variation = "DangerButton"
		return
	Settings.menu_open = false
	Net.leave()
	get_tree().change_scene_to_file(Net.MENU_SCENE)


func _on_quit_pressed() -> void:
	Net.leave()
	get_tree().quit()
