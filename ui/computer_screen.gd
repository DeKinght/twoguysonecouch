class_name ComputerScreen
extends CanvasLayer
## Widok ekranu komputera ze zleceniami. Tworzy go JobComputer u gracza, który usiadł.
##
## Najpierw kamera podjeżdża do monitora, potem pokazuje się "pulpit" z listą zleceń.
## Esc albo "Wyloguj" zamyka: kamera wraca, gracz znów steruje postacią.
## Na czas korzystania: własny (większy) kursor, a sterowanie postacią jest zablokowane.

signal closed

const ZOOM_TIME: float = 0.45
const CURSOR_SIZE: int = 40

var computer: JobComputer
var player: Player

var _camera: Camera3D
var _root: Control
var _list: VBoxContainer
var _accept_buttons: Dictionary = {}  ## id zlecenia -> Button
var _clock: Label
var _closing: bool = false


func _ready() -> void:
	layer = 20
	Settings.menu_open = true  # blokuje ruch, E i chwytanie
	player.grabber.release()

	# Kamera tymczasowa: start w oczach gracza, przejazd przed monitor.
	_camera = Camera3D.new()
	_camera.fov = player.camera.fov
	_camera.cull_mask = player.camera.cull_mask
	computer.get_parent().add_child(_camera)
	_camera.global_transform = player.camera.global_transform
	_camera.make_current()
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "global_transform", computer.view_transform(), ZOOM_TIME)
	tween.tween_callback(_show_desktop)

	_build_ui()
	_root.modulate.a = 0.0
	computer.state_changed.connect(_refresh)


func _exit_tree() -> void:
	Settings.menu_open = false
	_set_cursor(false)
	if is_instance_valid(_camera):
		_camera.queue_free()
	if is_instance_valid(player):
		player.camera.make_current()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	if _clock != null:
		var t: Dictionary = Time.get_time_dict_from_system()
		_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]


func close() -> void:
	if _closing:
		return
	_closing = true
	_set_cursor(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_root, "modulate:a", 0.0, 0.12)
	if is_instance_valid(player):
		tween.tween_property(_camera, "global_transform", player.camera.global_transform, ZOOM_TIME * 0.8)
	tween.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _show_desktop() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_cursor(true)
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)


# --- Interfejs -------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)

	# Obudowa monitora + "szkło" ekranu.
	var bezel := Panel.new()
	bezel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bezel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.07, 0.1), 0, 0))
	bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bezel)
	var screen := PanelContainer.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		screen.set("offset_" + side, 26 if side in ["left", "top"] else -26)
	screen.add_theme_stylebox_override("panel", _box(UITheme.BG_DARK, 18, 0))
	_root.add_child(screen)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	screen.add_child(column)
	column.add_child(_build_top_bar())

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 40 if side != "top" else 28)
	column.add_child(body)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	body.add_child(content)

	var header := Label.new()
	header.text = "Dostępne zlecenia"
	header.theme_type_variation = "HeadingLabel"
	header.add_theme_font_override("font", UITheme.title_font())
	header.add_theme_font_size_override("font_size", 34)
	content.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 16)
	scroll.add_child(_list)
	for job: Dictionary in JobComputer.JOBS:
		_list.add_child(_build_job_card(job))
	var more := Label.new()
	more.text = "Więcej zleceń wkrótce..."
	more.theme_type_variation = "MutedLabel"
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(more)
	_refresh()


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(UITheme.BG_LIGHT, 18, 0, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	var logo := TextureRect.new()
	logo.texture = UITheme.load_texture(UITheme.LOGO_PATH)
	logo.custom_minimum_size = Vector2(56, 40)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_padded(logo, 14, 8))

	var app := Label.new()
	app.text = "TGOC • Giełda zleceń"
	app.add_theme_font_override("font", UITheme.title_font())
	app.add_theme_font_size_override("font_size", 24)
	app.add_theme_color_override("font_color", UITheme.TAPE)
	app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(app)

	_clock = Label.new()
	_clock.theme_type_variation = "MutedLabel"
	_clock.add_theme_font_size_override("font_size", 20)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_clock)

	var logout := Button.new()
	logout.text = "Wyloguj  [Esc]"
	logout.theme_type_variation = "SmallButton"
	logout.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	logout.pressed.connect(close)
	_hover_colour(logout, UITheme.SECONDARY, UITheme.SECONDARY_HOVER)
	row.add_child(_padded(logout, 10, 10))
	return bar


func _build_job_card(job: Dictionary) -> Control:
	var card := PanelContainer.new()
	var style := _box(UITheme.PANEL, 16, 2)
	style.border_color = UITheme.PANEL_BORDER
	card.add_theme_stylebox_override("panel", style)
	# Najechanie na kartę: lekko jaśniejsze tło i obramowanie w kolorze kartonu.
	card.mouse_entered.connect(func() -> void: _tween_style(card, style, UITheme.SECONDARY, UITheme.PRIMARY))
	card.mouse_exited.connect(func() -> void: _tween_style(card, style, UITheme.PANEL, UITheme.PANEL_BORDER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	card.add_child(_padded(row, 16, 16))

	var picture := TextureRect.new()
	picture.texture = UITheme.load_texture(job["image"])
	picture.custom_minimum_size = Vector2(260, 170)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_PASS
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(UITheme.TAPE, 10, 0))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.add_child(picture)
	row.add_child(frame)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(info)

	var title := Label.new()
	title.text = job["title"]
	title.add_theme_font_override("font", UITheme.title_font())
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", UITheme.TEXT)
	info.add_child(title)

	var stars := StarRow.new()
	stars.filled = job.get("stars", 0)
	info.add_child(stars)

	var desc := Label.new()
	desc.text = job["description"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 19)
	desc.add_theme_color_override("font_color", UITheme.MUTED)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(desc)

	var accept := Button.new()
	accept.text = "Przyjmij"
	accept.theme_type_variation = "PrimaryButton"  # kolor kartonu, jaśnieje po najechaniu
	accept.custom_minimum_size = Vector2(190, 0)
	accept.size_flags_vertical = Control.SIZE_SHRINK_END
	accept.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accept.pressed.connect(func() -> void: computer.request_accept(job["id"]))
	UITheme.juice(accept)
	row.add_child(accept)
	_accept_buttons[job["id"]] = accept

	for control: Control in [card, row, info, title, desc]:
		if control != card:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
	return card


## Stan przycisków "Przyjmij" (przyjęte zlecenie widzą wszyscy).
func _refresh() -> void:
	for job_id: String in _accept_buttons:
		var button: Button = _accept_buttons[job_id]
		if computer.accepted_job == "":
			button.disabled = false
			button.text = "Przyjmij"
			button.tooltip_text = ""
		elif computer.accepted_job == job_id:
			button.disabled = true
			button.text = "Przyjęte ✓"
			button.tooltip_text = "Przyjął: %s" % Net.get_player_name(computer.accepted_by)
		else:
			button.disabled = true
			button.text = "Niedostępne"


# --- Pomocnicze ------------------------------------------------------------------------

func _box(color: Color, radius: int, border: int, top_only: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	if top_only:
		s.corner_radius_top_left = radius
		s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.anti_aliasing = true
	return s


func _padded(control: Control, x: int, y: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", x)
	m.add_theme_constant_override("margin_right", x)
	m.add_theme_constant_override("margin_top", y)
	m.add_theme_constant_override("margin_bottom", y)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(control)
	return m


func _tween_style(owner_node: Control, style: StyleBoxFlat, bg: Color, border: Color) -> void:
	var tween := owner_node.create_tween().set_parallel()
	tween.tween_property(style, "bg_color", bg, 0.15)
	tween.tween_property(style, "border_color", border, 0.15)


## Płynna zmiana koloru tła przycisku po najechaniu.
func _hover_colour(button: Button, normal: Color, hover: Color) -> void:
	var style := _box(normal, 10, 0)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.mouse_entered.connect(func() -> void: button.create_tween().tween_property(style, "bg_color", hover, 0.12))
	button.mouse_exited.connect(func() -> void: button.create_tween().tween_property(style, "bg_color", normal, 0.12))


# --- Kursor ----------------------------------------------------------------------------

## Duży kursor w stylu gry: kremowa strzałka z ciemnym obrysem (na przyciskach - pomarańczowa).
func _set_cursor(enabled: bool) -> void:
	if enabled:
		Input.set_custom_mouse_cursor(_cursor_texture(UITheme.TEXT), Input.CURSOR_ARROW, Vector2(3, 3))
		Input.set_custom_mouse_cursor(_cursor_texture(UITheme.PRIMARY), Input.CURSOR_POINTING_HAND, Vector2(3, 3))
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


static func _cursor_texture(fill: Color) -> ImageTexture:
	var n: int = CURSOR_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	# Strzałka (wierzchołek w lewym górnym rogu) w jednostkach 0..1.
	var arrow := PackedVector2Array([
		Vector2(0.08, 0.06), Vector2(0.08, 0.84), Vector2(0.3, 0.64), Vector2(0.46, 0.96),
		Vector2(0.6, 0.9), Vector2(0.45, 0.58), Vector2(0.74, 0.58),
	])
	var scaled := PackedVector2Array()
	for p in arrow:
		scaled.append(p * n)
	var outline: Color = UITheme.TEXT_DARK
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(p, scaled):
				var edge: float = _distance_to_outline(p, scaled)
				img.set_pixel(x, y, outline if edge < 2.4 else fill)
			else:
				var d: float = _distance_to_outline(p, scaled)
				if d < 1.2:
					img.set_pixel(x, y, Color(outline, 1.0 - d / 1.2))     # wygładzenie krawędzi
				elif d < 4.0 and x > 2 and y > 2:
					img.set_pixel(x, y, Color(0, 0, 0, 0.25 * (1.0 - d / 4.0)))  # delikatny cień
	return ImageTexture.create_from_image(img)


static func _distance_to_outline(p: Vector2, poly: PackedVector2Array) -> float:
	var best: float = INF
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Pięć gwiazdek (obrys = pusta, wypełnienie = zdobyta). Bez podpisu.
class StarRow extends Control:
	var filled: int = 0
	const COUNT: int = 5
	const STAR: float = 30.0
	const GAP: float = 6.0

	func _init() -> void:
		custom_minimum_size = Vector2(COUNT * (STAR + GAP), STAR)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		for i in COUNT:
			var center := Vector2(i * (STAR + GAP) + STAR * 0.5, STAR * 0.5)
			var pts := PackedVector2Array()
			for k in 10:
				var r: float = STAR * (0.5 if k % 2 == 0 else 0.22)
				var a: float = -PI / 2.0 + k * PI / 5.0
				pts.append(center + Vector2(cos(a), sin(a)) * r)
			if i < filled:
				draw_colored_polygon(pts, UITheme.TAPE)
			var closed_pts := pts.duplicate()
			closed_pts.append(pts[0])
			draw_polyline(closed_pts, UITheme.TAPE, 2.0, true)
