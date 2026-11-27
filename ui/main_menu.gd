extends Control
## Menu główne "Two Guys One Couch": logo, hostowanie / dołączanie, lobby, ustawienia.
##
## Gra łączy się przez Steam (lobby + SteamMultiplayerPeer w Net). W buildach
## debugowych jest dodatkowo ukryty "test lokalny" po IP - do testów kilku okien
## na jednym komputerze (jedno konto Steam nie połączy się samo ze sobą).

enum Page { MAIN, JOIN, LOBBY, SETTINGS, LAN }

const VERSION_TEXT: String = "prototyp v0.1"

var _pages: Dictionary = {}  ## Page -> Control
var _current: int = -1
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

# Dołączanie
var _lobby_list: ItemList
var _lobby_ids: Array[int] = []
var _lobby_empty: Label
var _code_edit: LineEdit

# Lobby
var _player_slots: VBoxContainer
var _map_row: HBoxContainer
var _map_select: OptionButton
var _code_row: HBoxContainer
var _code_label: Label
var _start_button: Button
var _wait_label: Label
var _wait_time: float = 0.0

# Test lokalny (IP)
var _ip_edit: LineEdit


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	Net.input_locked = false
	Settings.menu_open = false
	if not Net.steam_ready and Net.local_name == "Gracz":
		Net.local_name = "Gracz%d" % randi_range(1, 99)

	_build_background()
	_build_layout()
	_build_toast()

	Net.player_list_changed.connect(_refresh_lobby)
	Net.connected.connect(func() -> void: _show(Page.LOBBY))
	Net.lobby_ready.connect(func() -> void: _show(Page.LOBBY))
	Net.connection_failed.connect(func() -> void: _toast(Net.status_message, true))
	Net.lobby_list_received.connect(_fill_lobby_list)

	# Powrót z gry: połączenie trwa, więc od razu lobby.
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_show(Page.LOBBY)
	else:
		_show(Page.MAIN)
	if Net.status_message != "":
		_toast(Net.status_message, true)
		Net.status_message = ""


func _process(delta: float) -> void:
	if _current == Page.LOBBY and _wait_label.visible:
		_wait_time += delta
		_wait_label.text = "Czekamy, aż host odpali robotę" + ".".repeat(int(_wait_time * 2.0) % 4)


# --- Tło i układ --------------------------------------------------------------------

func _build_background() -> void:
	var image: Texture2D = UITheme.load_texture(UITheme.MENU_BG_PATH)
	if image != null:
		var bg := TextureRect.new()
		bg.texture = image
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		# Przyciemnienie od lewej, żeby menu było czytelne na obrazku.
		add_child(_gradient_rect(Color(UITheme.BG_DARK, 0.85), Color(UITheme.BG_DARK, 0.0), true))
	else:
		add_child(_gradient_rect(UITheme.BG_LIGHT, UITheme.BG_DARK, false))
		_spawn_floating_boxes()


func _gradient_rect(from: Color, to: Color, horizontal: bool) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0.75, 0.0) if horizontal else Vector2(0.0, 1.0)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Bez obrazka tła: dryfujące kartony w tle.
func _spawn_floating_boxes() -> void:
	var area: Vector2 = get_viewport_rect().size
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var box := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UITheme.PRIMARY, rng.randf_range(0.06, 0.16))
		style.set_corner_radius_all(8)
		box.add_theme_stylebox_override("panel", style)
		var side: float = rng.randf_range(50.0, 170.0)
		box.size = Vector2(side, side * rng.randf_range(0.7, 1.1))
		box.pivot_offset = box.size * 0.5
		box.position = Vector2(rng.randf_range(area.x * 0.35, area.x), rng.randf_range(-50.0, area.y))
		box.rotation = rng.randf_range(-0.5, 0.5)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)

		# Pasek "taśmy" na kartonie.
		var tape := ColorRect.new()
		tape.color = Color(UITheme.TAPE, style.bg_color.a * 0.9)
		tape.size = Vector2(box.size.x, box.size.y * 0.16)
		tape.position = Vector2(0, box.size.y * 0.42)
		tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tape)

		var tween := box.create_tween().set_loops()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var drift: float = rng.randf_range(20.0, 60.0)
		var spin: float = rng.randf_range(-0.25, 0.25)
		var duration: float = rng.randf_range(3.0, 6.0)
		tween.tween_property(box, "position:y", box.position.y - drift, duration)
		tween.parallel().tween_property(box, "rotation", box.rotation + spin, duration)
		tween.tween_property(box, "position:y", box.position.y, duration)
		tween.parallel().tween_property(box, "rotation", box.rotation, duration)


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_right", 110)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.custom_minimum_size = Vector2(640, 0)
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	column.add_child(_build_logo())

	var tagline := Label.new()
	tagline.text = "Wnosimy. Upuszczamy. Płacimy za szkody."
	tagline.theme_type_variation = "MutedLabel"
	tagline.add_theme_font_size_override("font_size", 22)
	column.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	column.add_child(spacer)

	# Strony zajmują miejsce między logo a stopką; ustawienia rozciągają się do dołu i się przewijają.
	var page_host := VBoxContainer.new()
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(page_host)
	_pages[Page.MAIN] = _build_main_page()
	_pages[Page.JOIN] = _build_join_page()
	_pages[Page.LOBBY] = _build_lobby_page()
	_pages[Page.SETTINGS] = _build_settings_page()
	_pages[Page.LAN] = _build_lan_page()
	for page: Control in _pages.values():
		page.visible = false
		page_host.add_child(page)

	var footer := Label.new()
	footer.theme_type_variation = "MutedLabel"
	footer.text = "Grasz jako: %s   •   %s" % [Net.local_name, VERSION_TEXT]
	column.add_child(footer)


func _build_logo() -> Control:
	var texture: Texture2D = UITheme.load_texture(UITheme.LOGO_PATH)
	var logo: Control
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		rect.custom_minimum_size = Vector2(620, 336)  # proporcje logo ~1.84 : 1
		logo = rect
	else:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -28)
		for line: String in ["TWO GUYS", "ONE COUCH"]:
			var label := Label.new()
			label.text = line
			label.theme_type_variation = "LogoLabel"
			box.add_child(label)
		logo = box

	# Lekkie bujanie logo - jak kanapa niesiona po schodach.
	logo.resized.connect(func() -> void: logo.pivot_offset = Vector2(logo.size.x * 0.35, logo.size.y * 0.5))
	logo.rotation = deg_to_rad(-2.5)
	var tween := logo.create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(logo, "rotation", deg_to_rad(-1.0), 1.8)
	tween.tween_property(logo, "rotation", deg_to_rad(-2.5), 1.8)
	return logo


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.theme_type_variation = "PillPanel"
	_toast_panel.anchor_left = 1.0
	_toast_panel.anchor_right = 1.0
	_toast_panel.anchor_top = 1.0
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = -48
	_toast_panel.offset_right = -48
	_toast_panel.offset_top = -48
	_toast_panel.offset_bottom = -48
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_panel.visible = false
	add_child(_toast_panel)
	_toast_label = Label.new()
	_toast_panel.add_child(_toast_label)


# --- Strony -----------------------------------------------------------------------

func _page(title: String) -> Array:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	if title != "":
		var heading := Label.new()
		heading.text = title
		heading.theme_type_variation = "TitleLabel"
		box.add_child(heading)
	return [panel, box]


func _button(text: String, variation: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	if variation != "":
		button.theme_type_variation = variation
	button.pressed.connect(on_pressed)
	UITheme.juice(button)
	return button


func _muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "MutedLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_main_page() -> Control:
	var parts: Array = _page("")
	var box: VBoxContainer = parts[1]
	box.custom_minimum_size = Vector2(460, 0)

	var host := _button("HOSTUJ GRĘ", "PrimaryButton", _on_host_pressed)
	var join := _button("DOŁĄCZ", "", func() -> void: _show(Page.JOIN))
	box.add_child(host)
	box.add_child(join)

	if not Net.steam_ready:
		host.disabled = true
		join.disabled = true
		var warning := _muted("Nie udało się połączyć ze Steamem.\n%s\nWłącz Steam i uruchom grę ponownie."
				% Net.steam_status)
		warning.add_theme_color_override("font_color", UITheme.DANGER_HOVER)
		box.add_child(warning)

	box.add_child(_button("USTAWIENIA", "", func() -> void: _show(Page.SETTINGS)))
	box.add_child(_button("WYJDŹ", "DangerButton", func() -> void: get_tree().quit()))

	if OS.is_debug_build():
		var lan := LinkButton.new()
		lan.text = "Test lokalny (IP) - tylko w wersji deweloperskiej"
		lan.pressed.connect(func() -> void: _show(Page.LAN))
		box.add_child(lan)
	return parts[0]


func _build_join_page() -> Control:
	var parts: Array = _page("DOŁĄCZ DO EKIPY")
	var box: VBoxContainer = parts[1]
	box.add_child(_muted("Wybierz lobby z listy albo wpisz kod od kumpla."))

	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 220)
	_lobby_list.item_activated.connect(func(_i: int) -> void: _on_join_selected())
	box.add_child(_lobby_list)

	_lobby_empty = _muted("Nikt teraz nie hostuje… Poproś kumpla o kod lobby.")
	box.add_child(_lobby_empty)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_button("ODŚWIEŻ", "SmallButton", func() -> void: Net.request_lobby_list()))
	var join := _button("DOŁĄCZ", "PrimaryButton", _on_join_selected)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(join)

	box.add_child(HSeparator.new())

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	box.add_child(code_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Kod lobby"
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join_by_code())
	code_row.add_child(_code_edit)
	code_row.add_child(_button("DOŁĄCZ PO KODZIE", "SmallButton", _on_join_by_code))

	box.add_child(_button("WRÓĆ", "", func() -> void: _show(Page.MAIN)))
	return parts[0]


func _build_lobby_page() -> Control:
	var parts: Array = _page("TWOJA EKIPA")
	var box: VBoxContainer = parts[1]

	_player_slots = VBoxContainer.new()
	_player_slots.add_theme_constant_override("separation", 8)
	box.add_child(_player_slots)

	_map_row = HBoxContainer.new()
	_map_row.add_theme_constant_override("separation", 12)
	box.add_child(_map_row)
	var map_label := Label.new()
	map_label.text = "Zlecenie"
	map_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_row.add_child(map_label)
	_map_select = OptionButton.new()
	_map_select.custom_minimum_size = Vector2(280, 0)
	for level_name: String in Net.LEVELS:
		_map_select.add_item(level_name)
	_map_select.selected = maxi(0, Net.LEVELS.values().find(Net.level_scene))
	_map_select.item_selected.connect(func(index: int) -> void:
		Net.level_scene = Net.LEVELS.values()[index])
	_map_row.add_child(_map_select)

	_code_row = HBoxContainer.new()
	_code_row.add_theme_constant_override("separation", 12)
	box.add_child(_code_row)
	_code_label = Label.new()
	_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.add_child(_code_label)
	_code_row.add_child(_button("KOPIUJ KOD", "SmallButton", func() -> void:
		DisplayServer.clipboard_set(str(Net.lobby_id))
		_toast("Kod lobby skopiowany - wyślij go kumplom!")))
	_code_row.add_child(_button("ZAPROŚ", "SmallButton", func() -> void: Net.invite_friends()))

	_start_button = _button("START ROBOTY", "PrimaryButton", func() -> void: Net.start_game())
	box.add_child(_start_button)

	_wait_label = Label.new()
	_wait_label.theme_type_variation = "HeadingLabel"
	box.add_child(_wait_label)

	box.add_child(_button("OPUŚĆ LOBBY", "", _on_leave_lobby))
	return parts[0]


func _build_settings_page() -> Control:
	var parts: Array = _page("USTAWIENIA")
	var panel: PanelContainer = parts[0]
	var box: VBoxContainer = parts[1]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL  # do dołu ekranu (nad stopką)
	box.add_child(SettingsPanel.wrap_in_scroll())
	box.add_child(_button("WRÓĆ", "", func() -> void: _show(Page.MAIN)))
	return panel


func _build_lan_page() -> Control:
	var parts: Array = _page("TEST LOKALNY")
	var box: VBoxContainer = parts[1]
	box.add_child(_muted("Tylko do testów kilku okien gry na jednym komputerze. W wydanej grze tego nie ma."))
	box.add_child(_button("HOSTUJ (IP)", "PrimaryButton", _on_lan_host))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "IP hosta"
	box.add_child(_ip_edit)
	box.add_child(_button("DOŁĄCZ (IP)", "", _on_lan_join))
	box.add_child(_button("WRÓĆ", "", func() -> void: _show(Page.MAIN)))
	return parts[0]


# --- Nawigacja ------------------------------------------------------------------------

func _show(page: int) -> void:
	_current = page
	for key: int in _pages:
		(_pages[key] as Control).visible = key == page
	var target: Control = _pages[page]
	target.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(target, "modulate:a", 1.0, 0.18)

	match page:
		Page.JOIN:
			_fill_lobby_list([])
			Net.request_lobby_list()
		Page.LOBBY:
			_wait_time = 0.0
			_refresh_lobby()


func _toast(message: String, is_error: bool = false) -> void:
	if message == "":
		return
	_toast_label.text = message
	_toast_label.add_theme_color_override("font_color", UITheme.DANGER_HOVER if is_error else UITheme.TEXT)
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(4.0)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)


# --- Akcje ----------------------------------------------------------------------------

func _on_host_pressed() -> void:
	if Net.host_game_steam():
		_toast("Rozkładamy kartony… tworzę lobby.")
	else:
		_toast("Nie udało się utworzyć lobby.", true)


func _on_join_selected() -> void:
	var selected: PackedInt32Array = _lobby_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _lobby_ids.size():
		_toast("Najpierw wybierz lobby z listy.", true)
		return
	_join(_lobby_ids[selected[0]])


func _on_join_by_code() -> void:
	var text: String = _code_edit.text.strip_edges()
	if not text.is_valid_int():
		_toast("Kod lobby to same cyfry.", true)
		return
	_join(text.to_int())


func _join(lobby: int) -> void:
	if Net.join_lobby(lobby):
		_toast("Dołączam do ekipy…")
	else:
		_toast("Nie można dołączyć do tego lobby.", true)


func _on_leave_lobby() -> void:
	Net.leave()
	_show(Page.MAIN)


func _on_lan_host() -> void:
	var err: Error = Net.host_game()
	if err != OK:
		_toast("Nie można uruchomić hosta (kod %d)." % err, true)
		return
	_show(Page.LOBBY)


func _on_lan_join() -> void:
	var err: Error = Net.join_game(_ip_edit.text.strip_edges())
	if err != OK:
		_toast("Nieprawidłowy adres (kod %d)." % err, true)
		return
	_toast("Łączę…")


# --- Odświeżanie ------------------------------------------------------------------------

func _fill_lobby_list(lobbies: Array) -> void:
	_lobby_list.clear()
	_lobby_ids.clear()
	for l: Dictionary in lobbies:
		_lobby_list.add_item("  %s   •   %d/%d" % [l["name"], l["members"], Net.MAX_PLAYERS])
		_lobby_ids.append(l["id"])
	_lobby_empty.visible = lobbies.is_empty()


func _refresh_lobby() -> void:
	for child in _player_slots.get_children():
		child.queue_free()

	var ids: Array = Net.names.keys()
	ids.sort()
	for i in Net.MAX_PLAYERS:
		if i < ids.size():
			_player_slots.add_child(_player_card(ids[i]))
		else:
			_player_slots.add_child(_empty_card())

	var is_host: bool = multiplayer.is_server()
	_start_button.visible = is_host
	_wait_label.visible = not is_host
	_map_row.visible = is_host
	_code_row.visible = Net.lobby_id != 0
	_code_label.text = "Kod lobby: %d" % Net.lobby_id


func _player_card(peer_id: int) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = UITheme.player_color(peer_id)
	dot_style.set_corner_radius_all(9)
	dot.add_theme_stylebox_override("panel", dot_style)
	row.add_child(dot)

	var name_label := Label.new()
	name_label.text = Net.get_player_name(peer_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	if peer_id == 1:
		var badge := PanelContainer.new()
		badge.theme_type_variation = "BadgePanel"
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var badge_label := Label.new()
		badge_label.text = "HOST"
		badge_label.theme_type_variation = "BadgeLabel"
		badge.add_child(badge_label)
		row.add_child(badge)
	return card


func _empty_card() -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.modulate.a = 0.45
	var label := _muted("Wolne miejsce na kumpla…")
	card.add_child(label)
	return card
