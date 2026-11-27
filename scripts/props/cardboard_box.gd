@tool
class_name CardboardBox
extends Node3D
## Proceduralny karton w stylu low-poly z detalami: szczelina między klapami,
## ciemniejsze narożniki, taśma zawinięta na boki, rączki, nadruki, napisy flamastrem,
## naklejki "SZKŁO", strzałki "tą stroną do góry", etykieta kurierska, otwarte klapy.
##
## Gotowe warianty to sceny w res://scenes/props/boxes/ (patrz BoxCatalog) - zwykłe
## "modele", które działają w Grabbable (model_scale = 1) i na regałach.
## Początek układu = środek podstawy (karton stoi na y = 0).
##
## Opcjonalne zasoby (podpinają się same, jeśli istnieją):
##   res://assets/textures/cardboard.(jpg|png)  tekstura tektury (bezszwowa)
##   res://assets/ui/fonts/marker.ttf           czcionka "flamastra" do odręcznych napisów

enum Tape { NONE, STRIP, CROSS, MESSY }

const CARDBOARD_TEXTURE: String = "res://assets/textures/cardboard"
const MARKER_FONT: String = "res://assets/ui/fonts/marker.ttf"
const BASE_TINT: Color = Color(0.74, 0.56, 0.36)

@export var size: Vector3 = Vector3(0.5, 0.4, 0.4)
@export var open_top: bool = false
@export var tape: Tape = Tape.STRIP
@export var tape_color: Color = Color(0.8, 0.68, 0.46)
## Napis na taśmie (np. "OSTROŻNIE").
@export var tape_text: String = ""
## Nadruk fabryczny na przodzie i tyle.
@export_multiline var print_text: String = ""
@export var print_color: Color = Color(0.14, 0.11, 0.08)
## Odręczny napis flamastrem (na górze i z boku).
@export_multiline var marker_text: String = ""
@export var marker_color: Color = Color(0.08, 0.08, 0.13)
@export var fragile: bool = false
@export var this_side_up: bool = false
@export var shipping_label: bool = false
@export var handles: bool = true
## Otwarty karton: coś z niego wystaje.
@export var contents: bool = false
@export var tint: Color = Color(0.74, 0.56, 0.36)
## 0 = nowy, 1 = stary, brudny, przetarty.
@export_range(0.0, 1.0) var wear: float = 0.0
@export var variant_seed: int = 0
## Kliknij w edytorze, żeby przebudować podgląd po zmianie parametrów.
@export var rebuild_preview: bool = false:
	set(value):
		if is_inside_tree():
			_rebuild()

static var _materials: Dictionary = {}
static var _noise_texture: Texture2D = null

var _rng := RandomNumberGenerator.new()
var _tint: Color


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()
	_rng.seed = variant_seed
	_tint = tint.darkened(_rng.randf_range(0.0, 0.06) + wear * 0.3)

	if open_top:
		_build_open()
	else:
		_build_closed()
	_build_corners()
	if handles and size.y > 0.22 and size.z > 0.22:
		_build_handles()
	if this_side_up:
		_build_arrows()
	if shipping_label:
		_build_shipping_label()
	if fragile:
		_build_fragile()
	if wear > 0.0:
		_build_wear()
	_build_texts()


# --- Bryła -------------------------------------------------------------------------

func _build_closed() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	_mesh(Vector3(w, h, d), Vector3(0, h * 0.5, 0), _cardboard(_tint))
	# Szczelina między górnymi klapami.
	_mesh(Vector3(w * 0.985, 0.0016, 0.007), Vector3(0, h + 0.0008, 0), _flat(_tint.darkened(0.55)))

	var tw: float = clampf(minf(w, d) * 0.18, 0.04, 0.075)
	match tape:
		Tape.STRIP:
			_tape_along_x(tw, 0.0)
		Tape.CROSS:
			_tape_along_x(tw, 0.0)
			_tape_along_z(tw)
		Tape.MESSY:
			_tape_along_x(tw, 0.0)
			for i in 2:
				var angle: float = _rng.randf_range(-0.7, 0.7)
				var length: float = minf(w, d) * _rng.randf_range(0.6, 0.95)
				_mesh(Vector3(length, 0.003, tw * 0.9),
						Vector3(_rng.randf_range(-w, w) * 0.15, h + 0.0025 + i * 0.0006, _rng.randf_range(-d, d) * 0.15),
						_tape_mat(), Vector3(0, angle, 0))
	if tape != Tape.NONE and tape_text != "":
		_label(tape_text, Vector3(0, h + 0.0036, 0), Vector3(-PI / 2.0, 0, 0), _contrast(tape_color),
				w * 0.9, tw * 0.6, false)


func _tape_along_x(tw: float, z: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var drop: float = minf(0.12, h * 0.4)
	_mesh(Vector3(w + 0.004, 0.003, tw), Vector3(0, h + 0.0015, z), _tape_mat())
	for side: float in [-1.0, 1.0]:
		_mesh(Vector3(0.003, drop, tw), Vector3(side * (w * 0.5 + 0.0015), h - drop * 0.5, z), _tape_mat())


func _tape_along_z(tw: float) -> void:
	var d: float = size.z
	var h: float = size.y
	var drop: float = minf(0.12, h * 0.4)
	_mesh(Vector3(tw, 0.0032, d + 0.004), Vector3(0, h + 0.0016, 0), _tape_mat())
	for side: float in [-1.0, 1.0]:
		_mesh(Vector3(tw, drop, 0.003), Vector3(0, h - drop * 0.5, side * (d * 0.5 + 0.0015)), _tape_mat())


## Otwarty karton: dno, cztery ścianki i odchylone klapy (klapy nie liczą się do kolizji).
func _build_open() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var t: float = 0.012
	var card: Material = _cardboard(_tint)
	var inner: Material = _cardboard(_tint.darkened(0.25))
	_mesh(Vector3(w, t, d), Vector3(0, t * 0.5, 0), inner)
	for side: float in [-1.0, 1.0]:
		_mesh(Vector3(w, h, t), Vector3(0, h * 0.5, side * (d * 0.5 - t * 0.5)), card)
		_mesh(Vector3(t, h, d - t * 2.0), Vector3(side * (w * 0.5 - t * 0.5), h * 0.5, 0), card)

	# Klapy: zawias na górnej krawędzi, odchylone na zewnątrz o ~120° (+ trochę losowo).
	_flap(Vector3(0, h, d * 0.5), Vector3(w * 0.98, t * 0.6, d * 0.5), Vector3(0, 0, -d * 0.25),
			Vector3(deg_to_rad(120 + _rng.randf_range(-15, 15)), 0, 0), card)
	_flap(Vector3(0, h, -d * 0.5), Vector3(w * 0.98, t * 0.6, d * 0.5), Vector3(0, 0, d * 0.25),
			Vector3(deg_to_rad(-120 + _rng.randf_range(-15, 15)), 0, 0), card)
	_flap(Vector3(w * 0.5, h, 0), Vector3(w * 0.5, t * 0.6, d * 0.96), Vector3(-w * 0.25, 0, 0),
			Vector3(0, 0, deg_to_rad(-120 + _rng.randf_range(-15, 15))), card)
	_flap(Vector3(-w * 0.5, h, 0), Vector3(w * 0.5, t * 0.6, d * 0.96), Vector3(w * 0.25, 0, 0),
			Vector3(0, 0, deg_to_rad(120 + _rng.randf_range(-15, 15))), card)

	if contents:
		_build_contents()


func _flap(hinge: Vector3, flap_size: Vector3, offset: Vector3, rot: Vector3, material: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = hinge
	pivot.rotation = rot
	pivot.set_meta("generated", true)
	add_child(pivot)
	var flap := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = flap_size
	flap.mesh = mesh
	flap.material_override = material
	flap.position = offset
	flap.set_meta("skip_bounds", true)  # klapy nie powiększają hitboxa
	pivot.add_child(flap)


## Zawartość otwartego kartonu: stosik książek i zwinięty plakat.
func _build_contents() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var y: float = 0.012
	var colors: Array[Color] = [Color(0.6, 0.15, 0.12), Color(0.15, 0.3, 0.55), Color(0.2, 0.45, 0.25),
			Color(0.85, 0.75, 0.3), Color(0.35, 0.2, 0.4)]
	var count: int = 3 + _rng.randi() % 4
	for i in count:
		var book := Vector3(w * _rng.randf_range(0.45, 0.6), _rng.randf_range(0.04, 0.07), d * _rng.randf_range(0.5, 0.65))
		_mesh(book, Vector3(_rng.randf_range(-0.03, 0.03) - w * 0.15, y + book.y * 0.5, _rng.randf_range(-0.03, 0.03)),
				_flat(colors[_rng.randi() % colors.size()]), Vector3(0, _rng.randf_range(-0.25, 0.25), 0))
		y += book.y
	var roll := CylinderMesh.new()
	roll.top_radius = 0.03
	roll.bottom_radius = 0.03
	roll.height = h * 1.3
	roll.radial_segments = 8
	var roll_node := _mesh_instance(roll, Vector3(w * 0.25, h * 0.6, -d * 0.1), _flat(Color(0.92, 0.9, 0.84)),
			Vector3(0.35, 0, -0.25))
	roll_node.set_meta("skip_bounds", true)


## Lekko ciemniejsze pionowe narożniki - karton nie wygląda jak gładka kostka.
func _build_corners() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var edge: Material = _cardboard(_tint.darkened(0.15))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_mesh(Vector3(0.012, h * 0.998, 0.012), Vector3(sx * (w * 0.5 - 0.004), h * 0.5, sz * (d * 0.5 - 0.004)), edge)


func _build_handles() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var hole: Material = _flat(Color(0.1, 0.07, 0.05))
	for side: float in [-1.0, 1.0]:
		_mesh(Vector3(0.003, 0.035, minf(0.11, d * 0.35)), Vector3(side * (w * 0.5 + 0.0015), h * 0.74, 0), hole)


## "Tą stroną do góry": dwie strzałki z kreską pod spodem, na bocznych ściankach.
func _build_arrows() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var ink: Material = _flat(print_color)
	var a: float = minf(0.14, h * 0.32)
	var base_y: float = h * 0.58
	for side: float in [-1.0, 1.0]:
		var x: float = side * (w * 0.5 + 0.0015)
		for dz: float in [-a * 0.35, a * 0.35]:
			_mesh(Vector3(0.003, a * 0.55, a * 0.12), Vector3(x, base_y + a * 0.28, dz), ink)
			var head := PrismMesh.new()
			head.size = Vector3(a * 0.38, a * 0.36, 0.003)
			_mesh_instance(head, Vector3(x, base_y + a * 0.72, dz), ink, Vector3(0, PI / 2.0, 0))
		_mesh(Vector3(0.003, a * 0.07, a * 1.1), Vector3(x, base_y - a * 0.08, 0), ink)
	if d > 0.2 and print_text == "":
		_label("TĄ STRONĄ\nDO GÓRY", Vector3(0, h * 0.35, d * 0.5 + 0.002), Vector3.ZERO, print_color, w * 0.7, h * 0.3, false)


## Etykieta kurierska z kodem kreskowym na przodzie, w prawym dolnym rogu.
func _build_shipping_label() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var lw: float = minf(0.16, w * 0.32)
	var lh: float = minf(0.11, h * 0.24)
	var center := Vector3(w * 0.5 - lw * 0.65, h * 0.28, d * 0.5 + 0.0012)
	_mesh(Vector3(lw, lh, 0.002), center, _flat(Color(0.96, 0.95, 0.92)))
	var ink: Material = _flat(Color(0.08, 0.08, 0.08))
	var grey: Material = _flat(Color(0.55, 0.55, 0.55))
	var x: float = center.x - lw * 0.42
	while x < center.x + lw * 0.42:
		var bar: float = lw * _rng.randf_range(0.012, 0.035)
		_mesh(Vector3(bar, lh * 0.38, 0.001), Vector3(x + bar * 0.5, center.y - lh * 0.22, center.z + 0.0015), ink)
		x += bar + lw * _rng.randf_range(0.012, 0.03)
	for i in 3:
		var line_w: float = lw * _rng.randf_range(0.4, 0.8)
		_mesh(Vector3(line_w, lh * 0.06, 0.001),
				Vector3(center.x - lw * 0.42 + line_w * 0.5, center.y + lh * (0.3 - i * 0.13), center.z + 0.0015), grey)


## Czerwone naklejki "SZKŁO" na przodzie i na górze.
func _build_fragile() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var red: Material = _flat(Color(0.82, 0.1, 0.08))
	var sw: float = minf(0.17, w * 0.38)
	var sh: float = minf(0.09, h * 0.22)
	var front := Vector3(-w * 0.5 + sw * 0.62, h * 0.8, d * 0.5 + 0.0012)
	_mesh(Vector3(sw, sh, 0.002), front, red)
	_label("SZKŁO!", front + Vector3(0, 0, 0.0016), Vector3.ZERO, Color.WHITE, sw * 0.85, sh * 0.7, false)
	if not open_top:
		var top := Vector3(w * 0.5 - sw * 0.6, size.y + 0.0012, d * 0.5 - sh * 0.7)
		_mesh(Vector3(sw, 0.002, sh), top, red, Vector3(0, 0.15, 0))
		_label("SZKŁO!", top + Vector3(0, 0.0016, 0), Vector3(-PI / 2.0, 0.15, 0), Color.WHITE, sw * 0.85, sh * 0.7, false)


## Przetarcia i plamy na starych kartonach.
func _build_wear() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var stain: Material = _cardboard(_tint.darkened(0.3 + wear * 0.2))
	var count: int = int(2 + wear * 5)
	for i in count:
		var face: int = _rng.randi() % 2
		var sw: float = minf(w, d) * _rng.randf_range(0.12, 0.3)
		var sh: float = h * _rng.randf_range(0.08, 0.25)
		var y: float = _rng.randf_range(sh * 0.5, h - sh * 0.5)
		if face == 0:
			var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
			_mesh(Vector3(sw, sh, 0.001), Vector3(_rng.randf_range(-w, w) * 0.3, y, side * (d * 0.5 + 0.0006)), stain)
		else:
			var side_x: float = 1.0 if _rng.randf() < 0.5 else -1.0
			_mesh(Vector3(0.001, sh, sw), Vector3(side_x * (w * 0.5 + 0.0006), y, _rng.randf_range(-d, d) * 0.3), stain)


func _build_texts() -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	if print_text != "":
		for side: float in [1.0, -1.0]:
			_label(print_text, Vector3(0, h * 0.5, side * (d * 0.5 + 0.002)), Vector3(0, 0.0 if side > 0 else PI, 0),
					print_color, w * 0.78, h * 0.42, false)
	if marker_text != "":
		var tilt: float = _rng.randf_range(-0.12, 0.12)
		if not open_top:
			# Na górze, obok taśmy.
			_label(marker_text, Vector3(0, h + 0.0034, d * 0.27), Vector3(-PI / 2.0, tilt, 0), marker_color,
					w * 0.8, d * 0.36, true)
		var y: float = h * (0.72 if print_text != "" else 0.5)
		if print_text == "" or open_top:
			_label(marker_text, Vector3(0, y, d * 0.5 + 0.0022), Vector3(0, 0, tilt), marker_color, w * 0.8, h * 0.4, true)
		_label(marker_text, Vector3(w * 0.5 + 0.0022, h * 0.5, 0), Vector3(0, PI / 2.0, -tilt), marker_color,
				d * 0.8, h * 0.4, true)


# --- Pomocnicze -----------------------------------------------------------------------

func _mesh(mesh_size: Vector3, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = mesh_size
	return _mesh_instance(mesh, pos, material, rot)


func _mesh_instance(mesh: Mesh, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.set_meta("generated", true)
	add_child(mi)
	return mi


func _label(text: String, pos: Vector3, rot: Vector3, color: Color, max_w: float, max_h: float, marker: bool) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.outline_size = 0
	label.modulate = color
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if marker and ResourceLoader.exists(MARKER_FONT):
		label.font = load(MARKER_FONT) as Font
	var lines: PackedStringArray = text.split("\n")
	var longest: int = 1
	for line in lines:
		longest = maxi(longest, line.length())
	var px_w: float = longest * 64.0 * 0.62
	var px_h: float = lines.size() * 64.0 * 1.25
	label.pixel_size = minf(max_w / px_w, max_h / px_h)
	label.position = pos
	label.rotation = rot
	label.set_meta("generated", true)
	add_child(label)


func _contrast(c: Color) -> Color:
	return Color(0.1, 0.08, 0.06) if c.get_luminance() > 0.5 else Color.WHITE


func _tape_mat() -> Material:
	var key: String = "tape_%s" % tape_color.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tape_color
		mat.roughness = 0.35  # taśma lekko błyszczy
		_materials[key] = mat
	return _materials[key]


func _flat(color: Color) -> Material:
	var key: String = "flat_%s" % color.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		_materials[key] = mat
	return _materials[key]


## Tektura: tekstura z pliku (jeśli jest) albo delikatny szum, zabarwione odcieniem kartonu.
func _cardboard(color: Color) -> Material:
	var key: String = "card_%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	var tex: Texture2D = _load_texture(CARDBOARD_TEXTURE)
	if tex != null:
		# Tekstura jest już "kartonowa" - odcień tylko lekko ją przesuwa.
		mat.albedo_color = Color(clampf(color.r / BASE_TINT.r, 0, 1.3), clampf(color.g / BASE_TINT.g, 0, 1.3),
				clampf(color.b / BASE_TINT.b, 0, 1.3))
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3.ONE * 2.0
	else:
		mat.albedo_color = color
		mat.albedo_texture = _noise()
		mat.uv1_scale = Vector3.ONE * 3.0
	mat.uv1_triplanar = true
	_materials[key] = mat
	return mat


static func _noise() -> Texture2D:
	if _noise_texture == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.06
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.noise = noise
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.86, 0.86, 0.86))
		ramp.set_color(1, Color(1, 1, 1))
		tex.color_ramp = ramp
		_noise_texture = tex
	return _noise_texture


static func _load_texture(base: String) -> Texture2D:
	for ext: String in [".jpg", ".png", ".webp"]:
		if ResourceLoader.exists(base + ext):
			return load(base + ext) as Texture2D
	return null
