class_name UITheme
extends RefCounted
## Wspólny wygląd całego interfejsu (menu, pauza, HUD).
##
## Wszystko budowane w kodzie, więc działa bez żadnych plików graficznych.
## Jeśli w projekcie pojawią się poniższe pliki, zostaną użyte automatycznie:
##   res://assets/ui/logo.png         - logo gry (przezroczyste tło)
##   res://assets/ui/menu_bg.png      - tło menu głównego (16:9)
##   res://assets/ui/fonts/title.ttf  - czcionka nagłówków i przycisków
##   res://assets/ui/fonts/body.ttf   - czcionka tekstu

const LOGO_PATH: String = "res://assets/ui/logo.png"
const MENU_BG_PATH: String = "res://assets/ui/menu_bg.png"
const TITLE_FONT_PATH: String = "res://assets/ui/fonts/title.ttf"
const BODY_FONT_PATH: String = "res://assets/ui/fonts/body.ttf"

# Paleta: "karton i taśma" na tle wieczornego fioletu.
const BG_DARK: Color = Color(0.106, 0.09, 0.149)
const BG_LIGHT: Color = Color(0.169, 0.133, 0.267)
const PANEL: Color = Color(0.141, 0.122, 0.2, 0.96)
const PANEL_BORDER: Color = Color(0.239, 0.204, 0.337)
const INPUT_BG: Color = Color(0.09, 0.078, 0.165)
const PRIMARY: Color = Color(0.949, 0.647, 0.255)          ## karton
const PRIMARY_HOVER: Color = Color(1.0, 0.725, 0.361)
const PRIMARY_PRESSED: Color = Color(0.851, 0.545, 0.169)
const SECONDARY: Color = Color(0.231, 0.2, 0.314)
const SECONDARY_HOVER: Color = Color(0.29, 0.251, 0.4)
const SECONDARY_PRESSED: Color = Color(0.188, 0.165, 0.263)
const DANGER: Color = Color(0.878, 0.353, 0.353)
const DANGER_HOVER: Color = Color(0.937, 0.443, 0.443)
const DANGER_PRESSED: Color = Color(0.776, 0.282, 0.282)
const TAPE: Color = Color(0.969, 0.843, 0.455)             ## taśma pakowa
const TEXT: Color = Color(1.0, 0.957, 0.878)
const TEXT_DARK: Color = Color(0.165, 0.114, 0.063)
const MUTED: Color = Color(0.71, 0.667, 0.784)
const SUCCESS: Color = Color(0.5, 0.9, 0.55)

static var _theme: Theme = null


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Wczytuje obrazek, jeśli istnieje - akceptuje .png, .jpg i .webp o tej samej nazwie.
static func load_texture(path: String) -> Texture2D:
	var base: String = path.get_basename()
	for candidate: String in [path, base + ".png", base + ".jpg", base + ".webp"]:
		if ResourceLoader.exists(candidate):
			return load(candidate) as Texture2D
	return null


static func title_font() -> Font:
	if ResourceLoader.exists(TITLE_FONT_PATH):
		return load(TITLE_FONT_PATH) as Font
	return ThemeDB.fallback_font


## Kolor gracza (ten sam wzór co kapsuła postaci w grze).
static func player_color(peer_id: int) -> Color:
	return Color.from_hsv(fmod(peer_id * 0.37, 1.0), 0.6, 0.9)


## "Soczysty" przycisk: lekko rośnie po najechaniu myszą.
static func juice(control: Control) -> void:
	control.resized.connect(func() -> void: control.pivot_offset = control.size * 0.5)
	control.mouse_entered.connect(func() -> void: _tween_scale(control, 1.05))
	control.mouse_exited.connect(func() -> void: _tween_scale(control, 1.0))


static func _tween_scale(control: Control, target: float) -> void:
	var tween := control.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * target, 0.15)


## Ustawia mouse_filter = IGNORE na całym poddrzewie (dla HUD-a, który nie może łapać kliknięć).
static func ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)


# --- Budowa motywu ------------------------------------------------------------------

static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	if ResourceLoader.exists(BODY_FONT_PATH):
		t.default_font = load(BODY_FONT_PATH) as Font
	var heading_font: Font = title_font()

	# Etykiety
	t.set_color("font_color", "Label", TEXT)

	t.set_type_variation("LogoLabel", "Label")
	t.set_font("font", "LogoLabel", heading_font)
	t.set_font_size("font_size", "LogoLabel", 96)
	t.set_color("font_color", "LogoLabel", PRIMARY)
	t.set_color("font_outline_color", "LogoLabel", TEXT_DARK)
	t.set_constant("outline_size", "LogoLabel", 22)
	t.set_color("font_shadow_color", "LogoLabel", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "LogoLabel", 0)
	t.set_constant("shadow_offset_y", "LogoLabel", 10)
	t.set_constant("shadow_outline_size", "LogoLabel", 22)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", heading_font)
	t.set_font_size("font_size", "TitleLabel", 44)
	t.set_color("font_color", "TitleLabel", PRIMARY)
	t.set_color("font_outline_color", "TitleLabel", TEXT_DARK)
	t.set_constant("outline_size", "TitleLabel", 12)

	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", heading_font)
	t.set_font_size("font_size", "HeadingLabel", 28)
	t.set_color("font_color", "HeadingLabel", TAPE)

	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", 17)
	t.set_color("font_color", "MutedLabel", MUTED)

	t.set_type_variation("BadgeLabel", "Label")
	t.set_font("font", "BadgeLabel", heading_font)
	t.set_font_size("font_size", "BadgeLabel", 16)
	t.set_color("font_color", "BadgeLabel", TEXT_DARK)

	# Przyciski: domyślny (fioletowy), główny (karton), niebezpieczny (czerwony), mały.
	_button_styles(t, "Button", SECONDARY, SECONDARY_HOVER, SECONDARY_PRESSED, TEXT, 24)
	t.set_font("font", "Button", heading_font)

	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", PRIMARY, PRIMARY_HOVER, PRIMARY_PRESSED, TEXT_DARK, 24)

	t.set_type_variation("DangerButton", "Button")
	_button_styles(t, "DangerButton", DANGER, DANGER_HOVER, DANGER_PRESSED, TEXT, 24)

	t.set_type_variation("SmallButton", "Button")
	_button_styles(t, "SmallButton", SECONDARY, SECONDARY_HOVER, SECONDARY_PRESSED, TEXT, 18, 16, 8)

	_button_styles(t, "OptionButton", SECONDARY, SECONDARY_HOVER, SECONDARY_PRESSED, TEXT, 20, 18, 8)
	t.set_font("font", "OptionButton", heading_font)

	t.set_color("font_color", "LinkButton", MUTED)
	t.set_color("font_hover_color", "LinkButton", TEXT)
	t.set_color("font_pressed_color", "LinkButton", PRIMARY)
	t.set_font_size("font_size", "LinkButton", 16)

	# Panele
	var panel := _flat(PANEL, 22)
	panel.set_border_width_all(3)
	panel.border_color = PANEL_BORDER
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 24
	panel.shadow_offset = Vector2(0, 8)
	panel.set_content_margin_all(32)
	t.set_stylebox("panel", "PanelContainer", panel)

	t.set_type_variation("CardPanel", "PanelContainer")
	var card := _flat(SECONDARY, 14)
	card.content_margin_left = 16
	card.content_margin_right = 16
	card.content_margin_top = 10
	card.content_margin_bottom = 10
	t.set_stylebox("panel", "CardPanel", card)

	t.set_type_variation("PillPanel", "PanelContainer")
	var pill := _flat(Color(0.07, 0.06, 0.11, 0.78), 18)
	pill.content_margin_left = 18
	pill.content_margin_right = 18
	pill.content_margin_top = 8
	pill.content_margin_bottom = 8
	t.set_stylebox("panel", "PillPanel", pill)

	t.set_type_variation("BadgePanel", "PanelContainer")
	var badge := _flat(TAPE, 8)
	badge.content_margin_left = 10
	badge.content_margin_right = 10
	badge.content_margin_top = 2
	badge.content_margin_bottom = 2
	t.set_stylebox("panel", "BadgePanel", badge)

	# Pola tekstowe
	var edit := _flat(INPUT_BG, 12)
	edit.set_border_width_all(2)
	edit.border_color = SECONDARY_HOVER
	edit.content_margin_left = 16
	edit.content_margin_right = 16
	edit.content_margin_top = 10
	edit.content_margin_bottom = 10
	var edit_focus: StyleBoxFlat = edit.duplicate()
	edit_focus.border_color = PRIMARY
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("read_only", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", PRIMARY)

	# Lista (lobby)
	var list_bg := _flat(INPUT_BG, 14)
	list_bg.set_content_margin_all(8)
	t.set_stylebox("panel", "ItemList", list_bg)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _flat(PRIMARY, 10))
	t.set_stylebox("selected_focus", "ItemList", _flat(PRIMARY, 10))
	t.set_stylebox("hovered", "ItemList", _flat(SECONDARY, 10))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT_DARK)
	t.set_constant("v_separation", "ItemList", 10)

	# Rozwijana lista (wybór mapy)
	var popup := _flat(PANEL, 12)
	popup.set_border_width_all(2)
	popup.border_color = PANEL_BORDER
	popup.set_content_margin_all(8)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _flat(PRIMARY, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT_DARK)

	# Suwak
	var track := _flat(INPUT_BG, 6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var filled := _flat(PRIMARY, 6)
	filled.content_margin_top = 5
	filled.content_margin_bottom = 5
	var filled_hover: StyleBoxFlat = filled.duplicate()
	filled_hover.bg_color = PRIMARY_HOVER
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled_hover)

	# Pasek przewijania
	t.set_stylebox("scroll", "VScrollBar", _flat(INPUT_BG, 6))
	t.set_stylebox("grabber", "VScrollBar", _flat(SECONDARY_HOVER, 6))
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(PRIMARY, 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(PRIMARY_PRESSED, 6))

	# Separator
	var line := StyleBoxLine.new()
	line.color = PANEL_BORDER
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 18)

	return t


static func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


## "Grube" przyciski z dolną krawędzią, która przy wciśnięciu się spłaszcza.
static func _button_styles(t: Theme, type: StringName, base: Color, hover: Color, pressed: Color,
		font_color: Color, font_size: int, pad_x: int = 28, pad_y: int = 12) -> void:
	var edge: Color = base.darkened(0.4)
	t.set_stylebox("normal", type, _chunky(base, edge, 6, pad_x, pad_y, false))
	t.set_stylebox("hover", type, _chunky(hover, edge, 6, pad_x, pad_y, false))
	t.set_stylebox("pressed", type, _chunky(pressed, edge, 2, pad_x, pad_y, true))
	t.set_stylebox("hover_pressed", type, _chunky(pressed, edge, 2, pad_x, pad_y, true))
	var dim: Color = base.lerp(Color(0.35, 0.35, 0.4), 0.6)
	t.set_stylebox("disabled", type, _chunky(dim, dim.darkened(0.3), 6, pad_x, pad_y, false))

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = TAPE
	focus.set_corner_radius_all(16)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	t.set_stylebox("focus", type, focus)

	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color"]:
		t.set_color(c, type, font_color)
	t.set_color("font_disabled_color", type, Color(font_color, 0.45))
	t.set_font_size("font_size", type, font_size)


static func _chunky(color: Color, edge: Color, depth: int, pad_x: int, pad_y: int,
		is_pressed: bool) -> StyleBoxFlat:
	var s := _flat(color, 14)
	s.border_width_bottom = depth
	s.border_color = edge
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	# Łączna wysokość zostaje stała, tylko tekst "wpada" w dół przy wciśnięciu.
	if is_pressed:
		s.content_margin_top = pad_y + 4
		s.content_margin_bottom = pad_y + 2
	else:
		s.content_margin_top = pad_y
		s.content_margin_bottom = pad_y + 6
	return s
