extends Control
## Menu: Host / Join (IP) -> lobby z listą graczy -> Start (tylko host).
## Interfejs budowany w kodzie.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _main_box: VBoxContainer
var _lobby_box: VBoxContainer
var _players_label: Label
var _start_button: Button
var _wait_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(360, 0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var title := Label.new()
	title.text = "PRZEPROWADZKA Z PIEKŁA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)

	_build_main_box(root)
	_build_lobby_box(root)

	Net.player_list_changed.connect(_refresh_lobby)
	Net.connected.connect(_show_lobby)
	Net.connection_failed.connect(_on_connection_failed)

	_status.text = Net.status_message
	Net.status_message = ""
	Net.input_locked = false

	# Powrót z gry: połączenie nadal trwa, więc od razu pokazujemy lobby.
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_show_lobby()


func _build_main_box(parent: Control) -> void:
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 8)
	parent.add_child(_main_box)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Twoja nazwa"
	_name_edit.text = "Gracz%d" % randi_range(1, 99)
	_main_box.add_child(_name_edit)

	var host_button := Button.new()
	host_button.text = "Hostuj grę"
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


func _apply_name() -> void:
	var n: String = _name_edit.text.strip_edges()
	Net.local_name = n if n != "" else "Gracz"


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
	_wait_label.visible = not is_host
