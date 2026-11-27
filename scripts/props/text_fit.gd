@tool
class_name TextFit
extends RefCounted
## Napisy w świecie gry (kartony, dekoracje, szyldy): wspólne czcionki i dopasowanie
## rozmiaru do prostokąta na ściance - na podstawie PRAWDZIWYCH wymiarów tekstu w danej
## czcionce, więc napis nigdy nie wystaje poza ściankę.
##
## Czcionki (podpinają się same, jeśli istnieją; bez nich - domyślna czcionka Godota):
##   res://assets/ui/fonts/label.ttf   nadruki fabryczne, szyldy, naklejki
##   res://assets/ui/fonts/marker.ttf  odręczne napisy flamastrem

const PRINT_FONT: String = "res://assets/ui/fonts/label.ttf"
const MARKER_FONT: String = "res://assets/ui/fonts/marker.ttf"
const FONT_SIZE: int = 64


static func font(marker: bool) -> Font:
	var path: String = MARKER_FONT if marker else PRINT_FONT
	if ResourceLoader.exists(path):
		return load(path) as Font
	if ResourceLoader.exists(PRINT_FONT):
		return load(PRINT_FONT) as Font
	return ThemeDB.fallback_font


## Rozmiar piksela Label3D, przy którym tekst mieści się w max_w x max_h metrów.
static func pixel_size(text: String, f: Font, max_w: float, max_h: float) -> float:
	var s: Vector2 = f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
	if s.x <= 0.0 or s.y <= 0.0:
		return 0.001
	return minf(max_w / s.x, max_h / s.y)


## Gotowy, płaski napis (nie-billboard) dopasowany do prostokąta max_w x max_h.
static func make(text: String, max_w: float, max_h: float, color: Color, marker: bool = false) -> Label3D:
	var f: Font = font(marker)
	var label := Label3D.new()
	label.text = text
	label.font = f
	label.font_size = FONT_SIZE
	label.outline_size = 0
	label.pixel_size = pixel_size(text, f, max_w, max_h)
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	return label
