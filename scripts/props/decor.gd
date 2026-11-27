@tool
class_name Decor
extends Node3D
## Proceduralne dekoracje low-poly (narzędzia, rośliny, półka, drobiazgi).
## Każdy wariant to scena w res://scenes/props/decor/ z ustawionym `kind` (patrz DecorCatalog).
## Początek układu = środek podstawy (przedmiot stoi na y = 0), rozmiary w metrach.

enum Kind {
	HAMMER, WRENCH, SCREWDRIVER, DRILL, TAPE_MEASURE, SAW, PAINT_CAN,
	PLANT_SMALL, CACTUS, FERN, TALL_PLANT, FLOWERS,
	WALL_SHELF,
	RUBBER_DUCK, GLOBE, TROPHY, MUG, ALARM_CLOCK, LAVA_LAMP, GARDEN_GNOME, BOWLING_PIN,
	SNOW_GLOBE, PIGGY_BANK, BOOK_STACK, PIZZA_BOXES, TRAFFIC_CONE, HARD_HAT, DUMBBELL,
	RUBIK_CUBE, PHOTO_FRAME, DISCO_BALL, THERMOS,
}

## Wysokość, na której stoją rzeczy położone na półce ściennej (WALL_SHELF).
const SHELF_TOP: float = 0.18

@export var kind: Kind = Kind.RUBBER_DUCK
## Kolor główny (alfa 0 = domyślny dla danego przedmiotu).
@export var color: Color = Color(0, 0, 0, 0)
@export var variant_seed: int = 0
## Obrót wokół osi Y [rad/s] w grze (np. kula dyskotekowa).
@export var spin_speed: float = 0.0
@export var rebuild_preview: bool = false:
	set(value):
		if is_inside_tree():
			_rebuild()

static var _materials: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if spin_speed != 0.0 and not Engine.is_editor_hint():
		rotation.y += spin_speed * delta


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()
	_rng.seed = variant_seed + kind * 1000
	match kind:
		Kind.HAMMER: _hammer()
		Kind.WRENCH: _wrench()
		Kind.SCREWDRIVER: _screwdriver()
		Kind.DRILL: _drill()
		Kind.TAPE_MEASURE: _tape_measure()
		Kind.SAW: _saw()
		Kind.PAINT_CAN: _paint_can()
		Kind.PLANT_SMALL: _plant_small()
		Kind.CACTUS: _cactus()
		Kind.FERN: _fern()
		Kind.TALL_PLANT: _tall_plant()
		Kind.FLOWERS: _flowers()
		Kind.WALL_SHELF: _wall_shelf()
		Kind.RUBBER_DUCK: _rubber_duck()
		Kind.GLOBE: _globe()
		Kind.TROPHY: _trophy()
		Kind.MUG: _mug()
		Kind.ALARM_CLOCK: _alarm_clock()
		Kind.LAVA_LAMP: _lava_lamp()
		Kind.GARDEN_GNOME: _garden_gnome()
		Kind.BOWLING_PIN: _bowling_pin()
		Kind.SNOW_GLOBE: _snow_globe()
		Kind.PIGGY_BANK: _piggy_bank()
		Kind.BOOK_STACK: _book_stack()
		Kind.PIZZA_BOXES: _pizza_boxes()
		Kind.TRAFFIC_CONE: _traffic_cone()
		Kind.HARD_HAT: _hard_hat()
		Kind.DUMBBELL: _dumbbell()
		Kind.RUBIK_CUBE: _rubik_cube()
		Kind.PHOTO_FRAME: _photo_frame()
		Kind.DISCO_BALL: _disco_ball()
		Kind.THERMOS: _thermos()


# --- Materiały ---------------------------------------------------------------------------

func _main(default: Color) -> Color:
	return color if color.a > 0.0 else default


func _mat(c: Color, metallic: float = 0.0, roughness: float = 0.8, emission: float = 0.0) -> Material:
	var key: String = "%s|%s|%s|%s" % [c.to_html(), metallic, roughness, emission]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = emission
	_materials[key] = m
	return m


func _metal() -> Material:
	return _mat(Color(0.62, 0.64, 0.68), 0.85, 0.3)


func _dark() -> Material:
	return _mat(Color(0.08, 0.08, 0.09), 0.0, 0.6)


func _wood(shade: float = 0.0) -> Material:
	return _mat(Color(0.52, 0.34, 0.2).darkened(shade), 0.0, 0.75)


func _terracotta() -> Material:
	return _mat(Color(0.72, 0.38, 0.24), 0.0, 0.9)


func _green(shade: float = 0.0) -> Material:
	return _mat(Color(0.24, 0.55, 0.22).darkened(shade), 0.0, 0.7)


# --- Siatki ----------------------------------------------------------------------------

func _add(mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.set_meta("generated", true)
	add_child(mi)
	return mi


func _box(s: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = s
	return _add(m, pos, mat, rot)


func _cyl(top: float, bottom: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO,
		segments: int = 16) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segments
	m.rings = 1
	return _add(m, pos, mat, rot)


func _sphere(r: float, pos: Vector3, mat: Material, scl: Vector3 = Vector3.ONE,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return _add(m, pos, mat, rot, scl)


func _torus(inner: float, outer: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 16
	m.ring_segments = 8
	return _add(m, pos, mat, rot)


func _prism(s: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = s
	return _add(m, pos, mat, rot)


func _capsule(r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return _add(m, pos, mat, rot)


## Napis dopasowany do prostokąta max_w x max_h [m] na powierzchni przedmiotu (patrz TextFit).
func _label(text: String, pos: Vector3, c: Color, max_w: float, max_h: float, rot: Vector3 = Vector3.ZERO) -> void:
	var label: Label3D = TextFit.make(text, max_w, max_h, c)
	label.position = pos
	label.rotation = rot
	label.set_meta("generated", true)
	add_child(label)


## Element wychylony od podstawy: oś Y elementu przechylona o `lean` w stronę kąta `angle`.
func _leaning(length: float, angle: float, lean: float) -> Array:
	var dir := Vector3(sin(lean) * cos(angle), cos(lean), sin(lean) * sin(angle))
	return [dir * length * 0.5, Vector3(0, -angle, -lean), dir * length]


# --- Narzędzia ---------------------------------------------------------------------------

func _hammer() -> void:
	_cyl(0.014, 0.016, 0.3, Vector3(0, 0.016, 0), _wood(), Vector3(0, 0, PI / 2.0))
	_cyl(0.018, 0.018, 0.1, Vector3(-0.09, 0.018, 0), _mat(Color(0.15, 0.15, 0.17), 0, 0.5), Vector3(0, 0, PI / 2.0))
	_box(Vector3(0.035, 0.036, 0.11), Vector3(0.14, 0.018, 0), _metal())
	_prism(Vector3(0.03, 0.04, 0.034), Vector3(0.14, 0.018, -0.07), _metal(), Vector3(PI / 2.0, 0, 0))


func _wrench() -> void:
	var m: Material = _metal()
	_box(Vector3(0.2, 0.008, 0.024), Vector3(0, 0.005, 0), m)
	_torus(0.012, 0.026, Vector3(-0.115, 0.007, 0), m)
	_box(Vector3(0.014, 0.01, 0.054), Vector3(0.106, 0.005, 0), m)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.04, 0.01, 0.012), Vector3(0.13, 0.005, side * 0.021), m)


func _screwdriver() -> void:
	var handle: Material = _mat(_main(Color(0.85, 0.15, 0.1)), 0, 0.4)
	_cyl(0.014, 0.017, 0.1, Vector3(-0.05, 0.017, 0), handle, Vector3(0, 0, PI / 2.0), 8)
	_cyl(0.004, 0.004, 0.13, Vector3(0.065, 0.017, 0), _metal(), Vector3(0, 0, PI / 2.0), 8)
	_box(Vector3(0.012, 0.002, 0.007), Vector3(0.133, 0.017, 0), _metal())


func _drill() -> void:
	var body: Material = _mat(_main(Color(0.95, 0.72, 0.1)), 0, 0.45)
	var black: Material = _mat(Color(0.12, 0.12, 0.13), 0, 0.5)
	_box(Vector3(0.08, 0.045, 0.075), Vector3(0, 0.0225, 0), black)                         # akumulator
	_box(Vector3(0.042, 0.11, 0.046), Vector3(0.005, 0.1, 0), black, Vector3(0, 0, -0.15))   # rękojeść
	_box(Vector3(0.2, 0.075, 0.062), Vector3(0.04, 0.19, 0), body)                            # korpus
	_cyl(0.03, 0.03, 0.05, Vector3(-0.07, 0.19, 0), body, Vector3(0, 0, PI / 2.0))            # silnik
	_cyl(0.017, 0.022, 0.045, Vector3(0.16, 0.19, 0), black, Vector3(0, 0, PI / 2.0))         # uchwyt
	_cyl(0.003, 0.003, 0.07, Vector3(0.215, 0.19, 0), _metal(), Vector3(0, 0, PI / 2.0), 6)  # wiertło
	_box(Vector3(0.015, 0.025, 0.02), Vector3(0.035, 0.14, 0), _mat(Color(0.8, 0.1, 0.1)))  # spust


func _tape_measure() -> void:
	_box(Vector3(0.07, 0.066, 0.036), Vector3(0, 0.033, 0), _mat(_main(Color(0.98, 0.8, 0.1)), 0, 0.4))
	_cyl(0.02, 0.02, 0.038, Vector3(0, 0.035, 0), _dark(), Vector3(PI / 2.0, 0, 0))
	_box(Vector3(0.014, 0.008, 0.026), Vector3(0.04, 0.005, 0), _metal())


func _saw() -> void:
	_box(Vector3(0.38, 0.003, 0.09), Vector3(0.06, 0.0015, 0), _metal())
	for i in 18:  # ząbki
		_prism(Vector3(0.018, 0.012, 0.003), Vector3(-0.12 + i * 0.02, 0.0015, -0.05), _metal(), Vector3(PI / 2.0, 0, PI))
	_box(Vector3(0.11, 0.022, 0.1), Vector3(-0.18, 0.011, 0.005), _mat(_main(Color(0.8, 0.15, 0.1)), 0, 0.5))
	_box(Vector3(0.05, 0.023, 0.035), Vector3(-0.18, 0.0115, 0.012), _dark())


func _paint_can() -> void:
	var paint: Color = _main(Color(0.85, 0.2, 0.15))
	_cyl(0.08, 0.08, 0.18, Vector3(0, 0.09, 0), _metal(), Vector3.ZERO, 20)
	_cyl(0.081, 0.081, 0.1, Vector3(0, 0.085, 0), _mat(paint, 0, 0.5), Vector3.ZERO, 20)
	_torus(0.07, 0.082, Vector3(0, 0.18, 0), _metal())
	_cyl(0.072, 0.072, 0.004, Vector3(0, 0.182, 0), _mat(paint, 0, 0.3))
	for i in 4:  # zacieki farby
		var a: float = _rng.randf_range(0, TAU)
		var drip: float = _rng.randf_range(0.02, 0.06)
		_box(Vector3(0.014, drip, 0.004), Vector3(cos(a) * 0.081, 0.18 - drip * 0.5, sin(a) * 0.081), _mat(paint, 0, 0.3),
				Vector3(0, -a + PI / 2.0, 0))
	_torus(0.074, 0.079, Vector3(0, 0.2, 0), _metal(), Vector3(PI / 2.0 - 0.5, 0, 0))  # pałąk


# --- Rośliny -----------------------------------------------------------------------------

func _pot(top: float, bottom: float, h: float, mat: Material) -> void:
	_cyl(top, bottom, h, Vector3(0, h * 0.5, 0), mat)
	_cyl(top * 1.08, top * 1.08, h * 0.15, Vector3(0, h - h * 0.075, 0), mat)
	_cyl(top * 0.95, top * 0.95, 0.008, Vector3(0, h - 0.004, 0), _mat(Color(0.28, 0.18, 0.11)))


func _plant_small() -> void:
	_pot(0.06, 0.045, 0.09, _terracotta())
	for ring in 2:
		var count: int = 7 - ring * 2
		for i in count:
			var a: float = TAU * i / count + ring * 0.4
			var r: float = 0.03 - ring * 0.012
			_sphere(0.028 - ring * 0.006, Vector3(cos(a) * r, 0.1 + ring * 0.015, sin(a) * r), _green(ring * 0.15),
					Vector3(1.6, 0.55, 0.7), Vector3(0, -a, 0.45 + ring * 0.3))
	_sphere(0.014, Vector3(0, 0.125, 0), _green(0.25))


func _cactus() -> void:
	_pot(0.055, 0.042, 0.08, _terracotta())
	var g: Material = _mat(Color(0.3, 0.58, 0.32), 0, 0.6)
	_capsule(0.035, 0.22, Vector3(0, 0.08 + 0.11, 0), g)
	for side: float in [-1.0, 1.0]:
		_capsule(0.019, 0.06, Vector3(side * 0.045, 0.19, 0), g, Vector3(0, 0, PI / 2.0))
		_capsule(0.019, 0.08, Vector3(side * 0.07, 0.22, 0), g)
	_sphere(0.016, Vector3(0, 0.305, 0), _mat(Color(0.95, 0.4, 0.6)))


func _fern() -> void:
	_pot(0.14, 0.1, 0.24, _mat(_main(Color(0.85, 0.85, 0.82)), 0, 0.6))
	var base := Vector3(0, 0.24, 0)
	for i in 16:
		var a: float = TAU * i / 16.0 + _rng.randf_range(-0.2, 0.2)
		var length: float = _rng.randf_range(0.32, 0.48)
		var tilt: float = _rng.randf_range(0.35, 0.95)
		var dir := Vector3(cos(a) * cos(tilt), sin(tilt), sin(a) * cos(tilt))
		_box(Vector3(length, 0.006, 0.05), base + dir * length * 0.5, _green(_rng.randf_range(0.0, 0.2)),
				Vector3(0, -a, tilt))


func _tall_plant() -> void:
	_pot(0.2, 0.15, 0.36, _mat(_main(Color(0.92, 0.9, 0.86)), 0, 0.5))
	var base := Vector3(0, 0.36, 0)
	var stem: Material = _mat(Color(0.3, 0.45, 0.2))
	for i in 8:
		var a: float = TAU * i / 8.0 + _rng.randf_range(-0.3, 0.3)
		var lean: float = _rng.randf_range(0.15, 0.55)
		var length: float = _rng.randf_range(0.5, 1.0)
		var stem_data: Array = _leaning(length, a, lean)
		_cyl(0.008, 0.01, length, base + stem_data[0], stem, stem_data[1], 6)
		# Liść monstery: duży, spłaszczony, opadający na zewnątrz.
		_sphere(0.14, base + stem_data[2], _green(_rng.randf_range(0.0, 0.15)), Vector3(1.4, 0.08, 1.0),
				Vector3(0, -a, -lean - 0.35))


func _flowers() -> void:
	_cyl(0.045, 0.035, 0.16, Vector3(0, 0.08, 0), _mat(Color(0.35, 0.6, 0.85, 0.65), 0.1, 0.1))
	var base := Vector3(0, 0.14, 0)
	var colors: Array[Color] = [Color(0.95, 0.25, 0.3), Color(0.98, 0.85, 0.2), Color(0.95, 0.55, 0.8),
			Color(0.95, 0.95, 0.95), Color(0.6, 0.35, 0.85)]
	for i in 6:
		var a: float = TAU * i / 6.0
		var lean: float = _rng.randf_range(0.1, 0.4)
		var length: float = _rng.randf_range(0.18, 0.28)
		var stem_data: Array = _leaning(length, a, lean)
		_cyl(0.003, 0.003, length, base + stem_data[0], _green(0.1), stem_data[1], 6)
		var head: Vector3 = base + stem_data[2]
		_sphere(0.028, head, _mat(colors[i % colors.size()]), Vector3(1, 0.45, 1), stem_data[1])
		_sphere(0.011, head + Vector3(0, 0.008, 0), _mat(Color(0.95, 0.75, 0.15)))


# --- Półka ścienna -----------------------------------------------------------------------

## Deska 1 m na dwóch wspornikach. Tył przy z = -0,11 (przy ścianie), blat na SHELF_TOP.
func _wall_shelf() -> void:
	_box(Vector3(1.0, 0.03, 0.22), Vector3(0, SHELF_TOP - 0.015, 0), _wood(0.1))
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.025, 0.15, 0.02), Vector3(side * 0.35, 0.075, -0.1), _dark())
		_box(Vector3(0.025, 0.02, 0.2), Vector3(side * 0.35, SHELF_TOP - 0.04, 0.0), _dark())
		_box(Vector3(0.02, 0.18, 0.02), Vector3(side * 0.35, 0.09, -0.02), _dark(), Vector3(-0.85, 0, 0))


# --- Drobiazgi ---------------------------------------------------------------------------

func _rubber_duck() -> void:
	var yellow: Material = _mat(_main(Color(1.0, 0.84, 0.1)), 0, 0.35)
	_sphere(0.05, Vector3(0, 0.04, 0), yellow, Vector3(1.25, 0.8, 1.0))
	_sphere(0.022, Vector3(-0.06, 0.06, 0), yellow, Vector3(0.6, 0.8, 0.6))
	for side: float in [-1.0, 1.0]:
		_sphere(0.025, Vector3(-0.01, 0.05, side * 0.045), yellow, Vector3(1.4, 0.6, 0.4))
	_sphere(0.032, Vector3(0.035, 0.09, 0), yellow)
	_box(Vector3(0.032, 0.012, 0.03), Vector3(0.07, 0.087, 0), _mat(Color(1.0, 0.5, 0.1), 0, 0.4))
	for side: float in [-1.0, 1.0]:
		_sphere(0.006, Vector3(0.058, 0.1, side * 0.016), _dark())


func _globe() -> void:
	var brass: Material = _mat(Color(0.8, 0.62, 0.25), 0.8, 0.3)
	_cyl(0.065, 0.075, 0.025, Vector3(0, 0.0125, 0), _wood(0.35))
	_cyl(0.008, 0.008, 0.08, Vector3(0, 0.06, 0), brass, Vector3.ZERO, 8)
	var center := Vector3(0, 0.17, 0)
	_sphere(0.1, center, _mat(Color(0.2, 0.45, 0.75), 0, 0.5))
	for i in 8:  # kontynenty
		var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.7, 0.9), _rng.randf_range(-1, 1)).normalized()
		_sphere(_rng.randf_range(0.025, 0.04), center + d * 0.08, _mat(Color(0.35, 0.6, 0.3), 0, 0.6))
	_torus(0.106, 0.113, center, brass, Vector3(PI / 2.0, 0, 0.4))


func _trophy() -> void:
	var gold: Material = _mat(Color(0.95, 0.75, 0.22), 0.9, 0.25)
	_box(Vector3(0.1, 0.05, 0.1), Vector3(0, 0.025, 0), _wood(0.6))
	_label("BEST\nMOVER", Vector3(0, 0.025, 0.0515), Color(0.95, 0.8, 0.35), 0.082, 0.036)
	_cyl(0.012, 0.022, 0.06, Vector3(0, 0.08, 0), gold)
	_cyl(0.062, 0.026, 0.1, Vector3(0, 0.16, 0), gold)
	for side: float in [-1.0, 1.0]:
		_torus(0.022, 0.03, Vector3(side * 0.066, 0.17, 0), gold, Vector3(PI / 2.0, 0, 0))
	_sphere(0.012, Vector3(0, 0.215, 0), gold)


func _mug() -> void:
	var palette: Array[Color] = [Color(0.95, 0.95, 0.93), Color(0.2, 0.4, 0.75), Color(0.85, 0.25, 0.2), Color(0.95, 0.7, 0.2)]
	var c: Material = _mat(_main(palette[_rng.randi() % palette.size()]), 0, 0.3)
	_cyl(0.04, 0.038, 0.095, Vector3(0, 0.0475, 0), c)
	_cyl(0.036, 0.036, 0.004, Vector3(0, 0.088, 0), _mat(Color(0.3, 0.17, 0.08), 0, 0.2))
	_torus(0.02, 0.029, Vector3(0.046, 0.05, 0), c, Vector3(PI / 2.0, 0, 0))
	# Płaski napis na zaokrąglonym kubku: wąski, żeby nie odstawał poza obrys.
	_label("#1\nMOVER", Vector3(0, 0.05, 0.0405), Color(0.1, 0.1, 0.1), 0.042, 0.045)


func _alarm_clock() -> void:
	var red: Material = _mat(_main(Color(0.85, 0.18, 0.15)), 0.3, 0.35)
	_cyl(0.06, 0.06, 0.04, Vector3(0, 0.08, 0), red, Vector3(PI / 2.0, 0, 0))
	_cyl(0.052, 0.052, 0.003, Vector3(0, 0.08, 0.021), _mat(Color(0.97, 0.96, 0.92)), Vector3(PI / 2.0, 0, 0))
	_box(Vector3(0.004, 0.04, 0.002), Vector3(0, 0.097, 0.024), _dark())
	_box(Vector3(0.03, 0.004, 0.002), Vector3(0.013, 0.08, 0.024), _dark())
	for side: float in [-1.0, 1.0]:
		_sphere(0.026, Vector3(side * 0.035, 0.14, 0), _metal(), Vector3(1, 0.7, 1))
		_cyl(0.007, 0.005, 0.025, Vector3(side * 0.032, 0.012, 0), _metal(), Vector3.ZERO, 8)


func _lava_lamp() -> void:
	var glow: Color = _main(Color(1.0, 0.45, 0.1))
	_cyl(0.035, 0.06, 0.09, Vector3(0, 0.045, 0), _metal())
	_cyl(0.025, 0.042, 0.2, Vector3(0, 0.19, 0), _mat(Color(0.55, 0.15, 0.6, 0.55), 0, 0.1, 0.6))
	for i in 4:
		_sphere(_rng.randf_range(0.011, 0.019), Vector3(_rng.randf_range(-0.01, 0.01), _rng.randf_range(0.12, 0.27),
				_rng.randf_range(-0.01, 0.01)), _mat(glow, 0, 0.3, 2.0))
	_cyl(0.017, 0.026, 0.05, Vector3(0, 0.315, 0), _metal())
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.2, 0)
	light.light_color = glow
	light.light_energy = 0.6
	light.omni_range = 1.3
	light.set_meta("generated", true)
	add_child(light)


func _garden_gnome() -> void:
	_cyl(0.035, 0.07, 0.14, Vector3(0, 0.07, 0), _mat(_main(Color(0.2, 0.35, 0.75)), 0, 0.5))
	_cyl(0.058, 0.062, 0.014, Vector3(0, 0.07, 0), _mat(Color(0.15, 0.1, 0.07)))
	for side: float in [-1.0, 1.0]:
		_sphere(0.022, Vector3(0.025, 0.012, side * 0.03), _mat(Color(0.25, 0.15, 0.1)), Vector3(1.4, 0.6, 1))
	_sphere(0.035, Vector3(0, 0.17, 0.008), _mat(Color(0.95, 0.75, 0.62)))
	_sphere(0.04, Vector3(0, 0.145, 0.028), _mat(Color(0.96, 0.96, 0.96)), Vector3(1, 1.2, 0.6))
	_sphere(0.012, Vector3(0, 0.172, 0.045), _mat(Color(0.95, 0.55, 0.5)))
	_cyl(0.0, 0.046, 0.15, Vector3(0, 0.27, 0), _mat(Color(0.85, 0.12, 0.1), 0, 0.5))


func _bowling_pin() -> void:
	var white: Material = _mat(Color(0.96, 0.95, 0.92), 0, 0.25)
	var red: Material = _mat(Color(0.85, 0.12, 0.1), 0, 0.3)
	_sphere(0.06, Vector3(0, 0.1, 0), white, Vector3(1, 1.6, 1))
	_cyl(0.022, 0.032, 0.08, Vector3(0, 0.22, 0), white)
	_sphere(0.033, Vector3(0, 0.28, 0), white)
	_torus(0.023, 0.031, Vector3(0, 0.205, 0), red)
	_torus(0.021, 0.029, Vector3(0, 0.228, 0), red)


func _snow_globe() -> void:
	_cyl(0.055, 0.065, 0.04, Vector3(0, 0.02, 0), _wood(0.3))
	_cyl(0.05, 0.05, 0.01, Vector3(0, 0.045, 0), _mat(Color(0.97, 0.97, 1.0)))
	_box(Vector3(0.04, 0.03, 0.035), Vector3(0, 0.065, 0), _mat(Color(0.8, 0.35, 0.25)))
	_prism(Vector3(0.05, 0.025, 0.042), Vector3(0, 0.0925, 0), _mat(Color(0.95, 0.95, 0.97)))
	for i in 12:
		_sphere(0.003, Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf_range(0.06, 0.15), _rng.randf_range(-0.04, 0.04)),
				_mat(Color.WHITE))
	_sphere(0.065, Vector3(0, 0.1, 0), _mat(Color(0.85, 0.92, 1.0, 0.22), 0, 0.05))


func _piggy_bank() -> void:
	var pink: Material = _mat(_main(Color(0.96, 0.62, 0.7)), 0, 0.35)
	var dark_pink: Material = _mat(Color(0.85, 0.45, 0.55), 0, 0.4)
	_sphere(0.07, Vector3(0, 0.085, 0), pink, Vector3(1.3, 1.0, 1.0))
	_cyl(0.026, 0.026, 0.022, Vector3(0.095, 0.088, 0), dark_pink, Vector3(0, 0, PI / 2.0))
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.002, 0.008, 0.006), Vector3(0.107, 0.088, side * 0.009), _dark())
		_prism(Vector3(0.03, 0.03, 0.008), Vector3(0.05, 0.15, side * 0.032), pink, Vector3(0, 0, -0.3))
		_sphere(0.006, Vector3(0.075, 0.115, side * 0.03), _dark())
		for front: float in [-1.0, 1.0]:
			_cyl(0.015, 0.015, 0.03, Vector3(front * 0.045, 0.015, side * 0.035), pink, Vector3.ZERO, 8)
	_box(Vector3(0.035, 0.004, 0.007), Vector3(0, 0.155, 0), _dark())
	_torus(0.006, 0.01, Vector3(-0.095, 0.1, 0), pink, Vector3(0, 0, PI / 2.0))


func _book_stack() -> void:
	var colors: Array[Color] = [Color(0.6, 0.15, 0.12), Color(0.15, 0.3, 0.55), Color(0.2, 0.45, 0.25),
			Color(0.85, 0.7, 0.25), Color(0.35, 0.2, 0.4), Color(0.1, 0.1, 0.12)]
	var pages: Material = _mat(Color(0.95, 0.92, 0.84))
	var y: float = 0.0
	for i in 4 + _rng.randi() % 3:
		var s := Vector3(_rng.randf_range(0.15, 0.22), _rng.randf_range(0.022, 0.045), _rng.randf_range(0.11, 0.15))
		var rot := Vector3(0, _rng.randf_range(-0.2, 0.2), 0)
		_box(s, Vector3(0, y + s.y * 0.5, 0), _mat(colors[_rng.randi() % colors.size()], 0, 0.6), rot)
		_box(Vector3(s.x * 0.97, s.y * 0.78, s.z * 1.01), Vector3(0.004, y + s.y * 0.5, 0), pages, rot)
		y += s.y


func _pizza_boxes() -> void:
	var card: Material = _mat(Color(0.93, 0.89, 0.8), 0, 0.85)
	for i in 3:
		var rot := Vector3(0, _rng.randf_range(-0.15, 0.15), 0)
		_box(Vector3(0.34, 0.04, 0.34), Vector3(0, 0.02 + i * 0.041, 0), card, rot)
	var top: float = 3 * 0.041
	_box(Vector3(0.26, 0.002, 0.06), Vector3(0, top + 0.001, -0.08), _mat(Color(0.85, 0.15, 0.1)))
	_label("PIZZA", Vector3(0, top + 0.003, -0.08), Color.WHITE, 0.24, 0.045, Vector3(-PI / 2.0, 0, 0))
	_cyl(0.05, 0.05, 0.002, Vector3(0.07, top + 0.001, 0.07), _mat(Color(0.75, 0.6, 0.4), 0, 0.3))  # tłusta plama


func _traffic_cone() -> void:
	var orange: Material = _mat(_main(Color(1.0, 0.42, 0.08)), 0, 0.5)
	var white: Material = _mat(Color(0.96, 0.96, 0.96), 0, 0.4)
	_box(Vector3(0.3, 0.03, 0.3), Vector3(0, 0.015, 0), orange)
	_cyl(0.025, 0.12, 0.45, Vector3(0, 0.255, 0), orange)
	for band_y: float in [0.2, 0.33]:
		var r: float = 0.12 - (0.12 - 0.025) * (band_y - 0.03) / 0.45
		_cyl(r - 0.003, r + 0.006, 0.05, Vector3(0, band_y, 0), white)


func _hard_hat() -> void:
	var yellow: Material = _mat(_main(Color(1.0, 0.82, 0.1)), 0, 0.35)
	_sphere(0.11, Vector3(0, 0.012, 0), yellow, Vector3(1, 0.9, 1.15))
	_cyl(0.14, 0.15, 0.012, Vector3(0, 0.006, 0.01), yellow)
	_box(Vector3(0.022, 0.02, 0.22), Vector3(0, 0.105, 0), yellow)
	_cyl(0.115, 0.115, 0.012, Vector3(0, 0.0, 0), _dark())  # wnętrze (zasłania dół kopuły)


func _dumbbell() -> void:
	_cyl(0.012, 0.012, 0.32, Vector3(0, 0.06, 0), _metal(), Vector3(0, 0, PI / 2.0), 10)
	var black: Material = _mat(Color(0.1, 0.1, 0.11), 0.2, 0.5)
	for side: float in [-1.0, 1.0]:
		_cyl(0.06, 0.06, 0.03, Vector3(side * 0.1, 0.06, 0), black, Vector3(0, 0, PI / 2.0), 20)
		_cyl(0.05, 0.05, 0.025, Vector3(side * 0.128, 0.06, 0), black, Vector3(0, 0, PI / 2.0), 20)


func _rubik_cube() -> void:
	var s: float = 0.057
	var c: float = s / 3.0
	_box(Vector3(s, s, s), Vector3(0, s * 0.5, 0), _dark())
	var colors: Array[Color] = [Color(0.85, 0.1, 0.1), Color(1.0, 0.5, 0.05), Color(0.97, 0.97, 0.97),
			Color(1.0, 0.85, 0.1), Color(0.1, 0.65, 0.25), Color(0.1, 0.3, 0.8)]
	var st: float = c * 0.84
	for i in [-1, 0, 1]:
		for j in [-1, 0, 1]:
			var picks: Array = []
			for f in 6:
				picks.append(_mat(colors[_rng.randi() % 6], 0, 0.3))
			_box(Vector3(st, 0.002, st), Vector3(i * c, s + 0.001, j * c), picks[0])
			_box(Vector3(st, 0.002, st), Vector3(i * c, -0.001 + 0.0, j * c), picks[1])
			_box(Vector3(0.002, st, st), Vector3(s * 0.5 + 0.001, s * 0.5 + i * c, j * c), picks[2])
			_box(Vector3(0.002, st, st), Vector3(-s * 0.5 - 0.001, s * 0.5 + i * c, j * c), picks[3])
			_box(Vector3(st, st, 0.002), Vector3(i * c, s * 0.5 + j * c, s * 0.5 + 0.001), picks[4])
			_box(Vector3(st, st, 0.002), Vector3(i * c, s * 0.5 + j * c, -s * 0.5 - 0.001), picks[5])


func _photo_frame() -> void:
	_box(Vector3(0.14, 0.18, 0.015), Vector3(0, 0.09, 0), _wood(0.2))
	_box(Vector3(0.012, 0.15, 0.012), Vector3(0, 0.075, -0.04), _wood(0.2), Vector3(0.45, 0, 0))  # podpórka
	var z: float = 0.0085
	_box(Vector3(0.11, 0.08, 0.002), Vector3(0, 0.125, z), _mat(Color(0.55, 0.75, 0.95)))  # niebo
	_box(Vector3(0.11, 0.07, 0.002), Vector3(0, 0.05, z), _mat(Color(0.4, 0.7, 0.35)))     # trawa
	_sphere(0.012, Vector3(0.035, 0.14, z), _mat(Color(1.0, 0.85, 0.2)))                  # słońce
	_box(Vector3(0.05, 0.02, 0.003), Vector3(-0.01, 0.075, z + 0.001), _mat(Color(0.9, 0.5, 0.2)))  # kanapa
	_box(Vector3(0.05, 0.015, 0.003), Vector3(-0.01, 0.09, z + 0.0005), _mat(Color(0.85, 0.45, 0.18)))


func _disco_ball() -> void:
	var length: float = 0.8
	var r: float = 0.17
	# Sznurek nie liczy się do hitboxa (inaczej kula miałaby 1 m wysokości "powietrza").
	_cyl(0.002, 0.002, length, Vector3(0, r * 2.0 + length * 0.5, 0), _dark(), Vector3.ZERO, 4) \
			.set_meta("skip_bounds", true)
	_sphere(r, Vector3(0, r, 0), _mat(Color(0.88, 0.88, 0.92), 1.0, 0.05, 0.15))
	# "Lustereczka": pierścienie płytek wokół kuli.
	for ring in 5:
		var lat: float = -1.1 + ring * 0.55
		var ring_r: float = cos(lat) * r
		var count: int = maxi(6, int(ring_r * 90.0))
		for i in count:
			var a: float = TAU * i / count
			var n := Vector3(cos(lat) * cos(a), sin(lat), cos(lat) * sin(a))
			_box(Vector3(0.028, 0.028, 0.004), Vector3(0, r, 0) + n * (r + 0.001),
					_mat(Color(0.95, 0.95, 1.0), 1.0, 0.02, 0.25), Basis.looking_at(-n).get_euler())


func _thermos() -> void:
	var body: Material = _mat(_main(Color(0.2, 0.45, 0.32)), 0.4, 0.4)
	_cyl(0.042, 0.042, 0.22, Vector3(0, 0.11, 0), body, Vector3.ZERO, 16)
	_cyl(0.043, 0.043, 0.02, Vector3(0, 0.01, 0), _metal())
	_cyl(0.043, 0.043, 0.015, Vector3(0, 0.215, 0), _metal())
	_cyl(0.036, 0.04, 0.06, Vector3(0, 0.255, 0), _mat(Color(0.12, 0.25, 0.18), 0, 0.5))
