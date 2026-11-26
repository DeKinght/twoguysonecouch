class_name SummaryScreen
extends CanvasLayer
## Ekran podsumowania zlecenia: zapłata, straty per gracz, wynik końcowy.
## Dane wejściowe w `data` (patrz JobManager._rpc_finish); szkody z lokalnego Ledgera.

var data: Dictionary = {}


func _ready() -> void:
	layer = 20
	Net.input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var early: bool = data["early"]
	_label(box, "ZLECENIE ZAKOŃCZONE" if early else "CZAS MINĄŁ", 28, Color.WHITE, true)
	_label(box, "W busie: %d / %d przedmiotów" % [data["loaded"], data["total"]], 18, Color.WHITE, true)
	box.add_child(HSeparator.new())

	var base_pay: int = data["base_pay"]
	var damage: int = Ledger.total_lost()
	var missing_value: int = data["missing_value"]
	var missing_count: int = data["missing_count"]
	var result: int = base_pay - damage - missing_value

	_label(box, "Zapłata od klienta: %d zł" % base_pay)
	_label(box, "Szkody: −%d zł" % damage, 18, Color(1.0, 0.6, 0.5))
	if missing_count > 0:
		_label(box, "Niedowiezione (%d szt.): −%d zł" % [missing_count, missing_value], 18, Color(1.0, 0.6, 0.5))
	box.add_child(HSeparator.new())

	_label(box, "Straty wg graczy:", 18, Color(0.8, 0.8, 0.8))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 170)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_fill_damage_list(list)

	box.add_child(HSeparator.new())
	var color: Color = Color(0.5, 1.0, 0.5) if result >= 0 else Color(1.0, 0.4, 0.4)
	_label(box, "WYNIK: %d zł" % result, 30, color, true)

	_add_button(box)


func _fill_damage_list(list: VBoxContainer) -> void:
	var totals: Dictionary = Ledger.totals_by_peer()
	if totals.is_empty():
		_label(list, "Brak szkód - brawo!", 16, Color(0.6, 1.0, 0.6))
		return
	var ids: Array = totals.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return totals[a] > totals[b])
	var details: Array[Dictionary] = Ledger.breakdown()
	for id: int in ids:
		_label(list, "%s: −%d zł" % [Ledger.display_name(id), totals[id]], 18)
		for d in details:
			if d["peer"] == id:
				_label(list, "      %s (%d×)  −%d zł" % [d["item"], d["hits"], d["loss"]], 15, Color(0.8, 0.8, 0.8))


func _add_button(box: VBoxContainer) -> void:
	var offline: bool = multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	if offline or multiplayer.is_server():
		var button := Button.new()
		button.text = "Wróć do menu" if offline else "Wróć do lobby"
		button.pressed.connect(_on_back_pressed)
		box.add_child(button)
	else:
		_label(box, "Czekaj, aż host wróci do lobby...", 16, Color(0.8, 0.8, 0.8), true)


func _on_back_pressed() -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		Net.input_locked = false
		get_tree().change_scene_to_file(Net.MENU_SCENE)
	else:
		Net.return_to_lobby()


func _label(parent: Control, text: String, size: int = 18, color: Color = Color.WHITE,
		centered: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
