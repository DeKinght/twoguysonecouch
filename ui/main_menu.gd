extends Control
## Menu: Host / Join (Steam albo IP) -> lobby z listą graczy -> Start (tylko host).
## Interfejs budowany w kodzie.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _lobby_id_edit: LineEdit
var _lobby_list: ItemList
var _lobby_ids: Array[int] = []
var _status: Label
var _main_box: VBoxContainer
var _lobby_box: VBoxContainer
var _players_label: Label
var _start_button: Button
var _level_select: OptionButton
var _wait_label: Label
var _steam_box: HBoxContainer
var _lobby_code_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(420, 0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var title := Label.new()
	title.text = "PRZEPROWADZKA Z PIEKŁA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_build_main_box(root)
	_build_lobby_box(root)

	Net.player_list_changed.connect(_refresh_lobby)
	Net.connected.connect(_show_lobby)
	Net.lobby_ready.connect(_show_lobby)
	Net.connection_failed.connect(_on_connection_failed)
	Net.lobby_list_received.connect(_fill_lobby_list)

	_status.text = Net.status_message
	Net.status_message = ""
	Net.input_locked = false

	# Powrót z gry: połączenie nadal trwa, więc od razu pokazujemy lobby.
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_show_lobby()
	elif Net.steam_ready:
		Net.request_lobby_list()


func _build_main_box(parent: Control) -> void:
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 8)
	parent.add_child(_main_box)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Twoja nazwa"
	_name_edit.text = Net.local_name if Net.steam_ready else "Gracz%d" % randi_range(1, 99)
	_main_box.add_child(_name_edit)

	# --- Steam ---
	if Net.steam_ready:
		_main_box.add_child(_heading("Steam"))
		var host_steam := Button.new()
		host_steam.text = "Hostuj grę (Steam)"
		host_steam.pressed.connect(_on_host_steam_pressed)
		_main_box.add_child(host_steam)

		_lobby_list = ItemList.new()
		_lobby_list.custom_minimum_size = Vector2(0, 90)
		_lobby_list.item_activated.connect(func(_i: int) -> void: _on_join_selected_pressed())
		_main_box.add_child(_lobby_list)

		var row := HBoxContainer.new()
		_main_box.add_child(row)
		var refresh := Button.new()
		refresh.text = "Odśwież listę"
		refresh.pressed.connect(func() -> void: Net.request_lobby_list())
		row.add_child(refresh)
		var join_selected := Button.new()
		join_selected.text = "Dołącz do wybranego"
		join_selected.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		join_selected.pressed.connect(_on_join_selected_pressed)
		row.add_child(join_selected)

		var id_row := HBoxContainer.new()
		_main_box.add_child(id_row)
		_lobby_id_edit = LineEdit.new()
		_lobby_id_edit.placeholder_text = "ID lobby od znajomego"
		_lobby_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		id_row.add_child(_lobby_id_edit)
		var join_id := Button.new()
		join_id.text = "Dołącz po ID"
		join_id.pressed.connect(_on_join_by_id_pressed)
		id_row.add_child(join_id)
	else:
		var info := Label.new()
		info.text = Net.steam_status + "\nMożesz grać przez IP."
		info.modulate = Color(1.0, 0.8, 0.5)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_main_box.add_child(info)

	# --- IP ---
	_main_box.add_child(_heading("Przez IP (LAN / Tailscale)"))
	var host_button := Button.new()
	host_button.text = "Hostuj grę (IP)"
	host_button.pressed.connect(_on_host_pressed)
	_main_box.add_child(host_button)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "IP hosta"
	_ip_edit.text = "127.0.0.1"
	_main_box.add_child(_ip_edit)

	var join_button := Button.new()
	join_button.text = "Dołącz (IP)"
	join_button.pressed.connect(_on_join_pressed)
	_main_box.add_child(join_button)


func _build_lobby_box(parent: Control) -> void:
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 8)
	_lobby_box.visible = false
	parent.add_child(_lobby_box)

	var header := Label.new()
	header.text = "Lobby (max %d graczy):" % Net.MAX_PLAYERS
	_lobby_box.add_child(header)

	_players_label = Label.new()
	_lobby_box.add_child(_players_label)

	# Steam: ID lobby do przekazania znajomym + zaproszenia.
	_steam_box = HBoxContainer.new()
	_lobby_box.add_child(_steam_box)
	_lobby_code_label = Label.new()
	_lobby_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steam_box.add_child(_lobby_code_label)
	var copy := Button.new()
	copy.text = "Kopiuj ID"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(str(Net.lobby_id)))
	_steam_box.add_child(copy)
	var invite := Button.new()
	invite.text = "Zaproś"
	invite.pressed.connect(func() -> void: Net.invite_friends())
	_steam_box.add_child(invite)

	_level_select = OptionButton.new()
	for level_name: String in Net.LEVELS:
		_level_select.add_item("Mapa: " + level_name)
	_level_select.selected = maxi(0, Net.LEVELS.values().find(Net.level_scene))
	_level_select.item_selected.connect(
		func(index: int) -> void: Net.level_scene = Net.LEVELS.values()[index])
	_lobby_box.add_child(_level_select)

	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.pressed.connect(func() -> void: Net.start_game())
	_lobby_box.add_child(_start_button)

	_wait_label = Label.new()
	_wait_label.text = "Czekaj, aż host rozpocznie grę..."
	_lobby_box.add_child(_wait_label)

	var back := Button.new()
	back.text = "Wróć"
	back.pressed.connect(_on_back_pressed)
	_lobby_box.add_child(back)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.7, 0.8, 1.0)
	return label


func _apply_name() -> void:
	var n: String = _name_edit.text.strip_edges()
	Net.local_name = n if n != "" else "Gracz"


# --- Przyciski ----------------------------------------------------------------------

func _on_host_steam_pressed() -> void:
	_apply_name()
	if not Net.host_game_steam():
		_status.text = "Steam jest niedostępny."
		return
	_status.text = "Tworzenie lobby Steam..."


func _on_join_selected_pressed() -> void:
	var selected: PackedInt32Array = _lobby_list.get_selected_items()
	if selected.is_empty():
		_status.text = "Wybierz lobby z listy."
		return
	_join_steam_lobby(_lobby_ids[selected[0]])


func _on_join_by_id_pressed() -> void:
	var text: String = _lobby_id_edit.text.strip_edges()
	if not text.is_valid_int():
		_status.text = "ID lobby to liczba."
		return
	_join_steam_lobby(text.to_int())


func _join_steam_lobby(id: int) -> void:
	_apply_name()
	if Net.join_lobby(id):
		_status.text = "Łączenie z lobby..."
	else:
		_status.text = "Nie można dołączyć do lobby."


func _on_host_pressed() -> void:
	_apply_name()
	var err: Error = Net.host_game()
	if err != OK:
		_status.text = "Nie można uruchomić hosta (kod %d). Czy port %d jest wolny?" % [err, Net.DEFAULT_PORT]
		return
	_show_lobby()


func _on_join_pressed() -> void:
	_apply_name()
	var err: Error = Net.join_game(_ip_edit.text.strip_edges())
	if err != OK:
		_status.text = "Nieprawidłowy adres (kod %d)." % err
		return
	_status.text = "Łączenie..."


func _on_connection_failed() -> void:
	_status.text = Net.status_message
	Net.status_message = ""


func _on_back_pressed() -> void:
	Net.leave()
	_lobby_box.visible = false
	_main_box.visible = true
	_status.text = ""
	if Net.steam_ready:
		Net.request_lobby_list()


# --- Odświeżanie widoku -----------------------------------------------------------------

func _fill_lobby_list(lobbies: Array) -> void:
	if _lobby_list == null:
		return
	_lobby_list.clear()
	_lobby_ids.clear()
	for l: Dictionary in lobbies:
		_lobby_list.add_item("%s  (%d/%d)" % [l["name"], l["members"], Net.MAX_PLAYERS])
		_lobby_ids.append(l["id"])
	if lobbies.is_empty():
		_lobby_list.add_item("(brak lobby - odśwież albo wpisz ID)", null, false)


func _show_lobby() -> void:
	_main_box.visible = false
	_lobby_box.visible = true
	_status.text = ""
	_refresh_lobby()


func _refresh_lobby() -> void:
	var lines: PackedStringArray = []
	for id: int in Net.names:
		var tag: String = " (host)" if id == 1 else ""
		lines.append("- %s%s" % [Net.names[id], tag])
	_players_label.text = "\n".join(lines)
	var is_host: bool = multiplayer.is_server()
	_start_button.visible = is_host
	_level_select.visible = is_host
	_wait_label.visible = not is_host
	_steam_box.visible = Net.lobby_id != 0
	_lobby_code_label.text = "ID lobby: %d" % Net.lobby_id
