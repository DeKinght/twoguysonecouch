extends "res://scripts/levels/level.gd"
## Poziom "Blok": 3 kondygnacje, ciasna klatka schodowa (dwa biegi na piętro, półpiętro),
## mieszkanie na 3. kondygnacji i bus przed wejściem jako strefa załadunku.
##
## Geometria i przedmioty są budowane W KODZIE, deterministycznie, na każdym peerze
## (te same nazwy węzłów = te same ścieżki RPC/synchronizacji). Wymiary w stałych niżej,
## więc łatwo je stroić. Układ (widok z góry, +Z = front budynku):
##
##   z=+2   ---- front (drzwi wejściowe w klatce) ----
##          |klatka x -5..-1.9|        mieszkanie x -1.9..5       |
##   z=-8   ---- tył ----
##
## Klatka: bieg A (pas x -5..-3.5) idzie w stronę tyłu i w górę, półpiętro przy z=-8..-6,
## bieg B (pas x -3.4..-1.9) wraca ku frontowi. Na każdym piętrze korytarz przy froncie
## łączy klatkę z mieszkaniem drzwiami w ścianie x=-1.9.

const ITEM_SCENE: PackedScene = preload("res://scenes/items/grabbable.tscn")

const T: float = 0.2            ## grubość stropów i ścian
const FLOOR_H: float = 3.0      ## wysokość kondygnacji
const TOP_Y: float = 9.0        ## strop nad ostatnią kondygnacją
const STAIR_RISE: float = 1.5   ## wzniesienie jednego biegu
const DOOR_W_FRONT: Vector2 = Vector2(-4.4, -3.2)   ## drzwi wejściowe (x od-do)
const DOOR_Z_APT: Vector2 = Vector2(0.4, 1.5)       ## drzwi do mieszkania (z od-do)
const DOOR_H: float = 2.1

const COL_WALL: Color = Color(0.86, 0.83, 0.76)
const COL_FLOOR: Color = Color(0.55, 0.5, 0.45)
const COL_STAIR: Color = Color(0.45, 0.4, 0.36)
const COL_GROUND: Color = Color(0.3, 0.5, 0.28)
const COL_BUS: Color = Color(0.95, 0.8, 0.15)

var bus_zone: Area3D

var _geo: Node3D
var _materials: Dictionary = {}


func _ready() -> void:
	_geo = Node3D.new()
	_geo.name = "Geometry"
	add_child(_geo)
	_build_shell()
	_build_stairs()
	_build_bus()
	_build_lights()
	_build_items()
	_build_job()
	super()


# --- Budynek ---------------------------------------------------------------------

func _build_shell() -> void:
	_aabb(Vector3(-40, -0.5, -40), Vector3(40, 0, 40), COL_GROUND)  # teren

	# Ściany zewnętrzne.
	_aabb(Vector3(-5.2, 0, -8.2), Vector3(5.2, TOP_Y + T, -8.0), COL_WALL)   # tył
	_aabb(Vector3(-5.2, 0, -8.2), Vector3(-5.0, TOP_Y + T, 2.2), COL_WALL)   # lewa
	_aabb(Vector3(5.0, 0, -8.2), Vector3(5.2, TOP_Y + T, 2.2), COL_WALL)     # prawa
	# Front z drzwiami wejściowymi.
	_aabb(Vector3(-5.2, 0, 2.0), Vector3(DOOR_W_FRONT.x, TOP_Y + T, 2.2), COL_WALL)
	_aabb(Vector3(DOOR_W_FRONT.y, 0, 2.0), Vector3(5.2, TOP_Y + T, 2.2), COL_WALL)
	_aabb(Vector3(DOOR_W_FRONT.x, DOOR_H + 0.1, 2.0), Vector3(DOOR_W_FRONT.y, TOP_Y + T, 2.2), COL_WALL)

	# Ściana klatka/mieszkanie (x = -1.9) z drzwiami na każdym piętrze.
	_aabb(Vector3(-2.0, 0, -8.2), Vector3(-1.8, TOP_Y + T, DOOR_Z_APT.x), COL_WALL)
	_aabb(Vector3(-2.0, 0, DOOR_Z_APT.y), Vector3(-1.8, TOP_Y + T, 2.2), COL_WALL)
	for f in 3:
		var y0: float = f * FLOOR_H
		_aabb(Vector3(-2.0, y0 + DOOR_H, DOOR_Z_APT.x), Vector3(-1.8, y0 + FLOOR_H, DOOR_Z_APT.y), COL_WALL)

	# Przegroda między biegami (x = -3.5..-3.4).
	_aabb(Vector3(-3.5, 0, -6.0), Vector3(-3.4, TOP_Y + T, -0.2), COL_WALL)

	# Stropy: mieszkania, korytarze, półpiętra, dach.
	for y in [FLOOR_H, 2.0 * FLOOR_H]:
		_slab(-1.9, 5.0, -8.0, 2.0, y, COL_FLOOR)       # mieszkanie
		_slab(-5.0, -1.9, -0.2, 2.0, y, COL_FLOOR)      # korytarz przy froncie
	for y in [STAIR_RISE, FLOOR_H + STAIR_RISE]:
		_slab(-5.0, -1.9, -8.0, -6.0, y, COL_FLOOR)     # półpiętra
	_slab(-5.0, 5.0, -8.0, 2.0, TOP_Y + T, COL_WALL)    # dach


func _build_stairs() -> void:
	for f in 2:
		var y0: float = f * FLOOR_H
		# Bieg A: z=-0.2 (y0) -> z=-6 (y0+1.5), pas x -5..-3.5.
		_ramp(-4.25, 1.5, -0.2, y0, -6.0, y0 + STAIR_RISE)
		# Bieg B: z=-6 (y0+1.5) -> z=-0.2 (y0+3), pas x -3.4..-1.9.
		_ramp(-2.65, 1.5, -6.0, y0 + STAIR_RISE, -0.2, y0 + FLOOR_H)


func _build_lights() -> void:
	for f in 3:
		var y0: float = f * FLOOR_H
		_light(Vector3(1.5, y0 + 2.4, -3.0), 9.0, 1.3)    # mieszkanie
		_light(Vector3(-3.5, y0 + 2.2, -3.0), 8.0, 1.1)   # klatka


# --- Bus -------------------------------------------------------------------------

func _build_bus() -> void:
	# Wnętrze paki: x -4.7..-2.3, z od 7.5 (otwarty tył) do 12.5. Ściany mają 2,6 m.
	_aabb(Vector3(-4.9, 0, 7.5), Vector3(-4.7, 2.6, 12.7), COL_BUS)   # lewa
	_aabb(Vector3(-2.3, 0, 7.5), Vector3(-2.1, 2.6, 12.7), COL_BUS)   # prawa
	_aabb(Vector3(-4.9, 0, 12.5), Vector3(-2.1, 2.6, 12.7), COL_BUS)  # przód paki
	_aabb(Vector3(-4.9, 0, 12.7), Vector3(-2.1, 1.8, 14.5), Color(0.85, 0.65, 0.1))  # kabina
	_aabb(Vector3(-4.7, 0.0, 7.5), Vector3(-2.3, 0.02, 12.5), Color(0.5, 0.45, 0.4), false)  # podłoga

	var label := Label3D.new()
	label.text = "BUS - ZANOŚ TUTAJ"
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(-3.5, 3.1, 7.6)
	add_child(label)

	bus_zone = Area3D.new()
	bus_zone.name = "BusZone"
	bus_zone.collision_layer = 0
	bus_zone.collision_mask = 4  # tylko przedmioty
	bus_zone.position = Vector3(-3.5, 1.3, 10.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 2.6, 4.8)
	shape.shape = box
	bus_zone.add_child(shape)
	add_child(bus_zone)


# --- Przedmioty -------------------------------------------------------------------

func _build_items() -> void:
	var items := Node3D.new()
	items.name = "Items"
	add_child(items)

	var y: float = 2.0 * FLOOR_H  # podłoga mieszkania na 3. kondygnacji
	var table: Array[Dictionary] = [
		{"name": "Lodowka", "label": "Lodówka", "size": Vector3(0.8, 1.8, 0.8), "mass": 60.0,
				"value": 800.0, "dur": 80.0, "color": Color(0.9, 0.92, 0.95), "pos": Vector3(4.4, y + 0.92, -6.8)},
		{"name": "Kanapa", "label": "Kanapa", "size": Vector3(2.0, 0.8, 0.9), "mass": 40.0,
				"value": 500.0, "dur": 120.0, "color": Color(0.55, 0.25, 0.3), "pos": Vector3(1.0, y + 0.42, -7.3)},
		{"name": "Telewizor", "label": "Telewizor", "size": Vector3(1.1, 0.7, 0.12), "mass": 12.0,
				"value": 600.0, "dur": 40.0, "color": Color(0.1, 0.1, 0.12), "pos": Vector3(2.8, y + 0.37, -7.6)},
		{"name": "Lampa", "label": "Lampa", "size": Vector3(0.3, 1.6, 0.3), "mass": 3.0,
				"value": 150.0, "dur": 30.0, "color": Color(0.95, 0.9, 0.5), "pos": Vector3(4.6, y + 0.82, -2.0)},
		{"name": "Akwarium", "label": "Akwarium", "size": Vector3(1.0, 0.55, 0.45), "mass": 25.0,
				"value": 400.0, "dur": 20.0, "color": Color(0.5, 0.8, 0.9), "pos": Vector3(2.4, y + 0.3, -4.0)},
		{"name": "Pianino", "label": "Pianino", "size": Vector3(1.4, 1.2, 0.6), "mass": 95.0,
				"value": 900.0, "dur": 60.0, "color": Color(0.2, 0.12, 0.1), "pos": Vector3(4.2, y + 0.62, -3.6)},
		{"name": "Karton", "label": "Karton", "size": Vector3(0.5, 0.5, 0.5), "mass": 5.0,
				"value": 80.0, "dur": 100.0, "color": Color(0.72, 0.55, 0.35), "pos": Vector3(0.0, y + 0.27, -2.5)},
		{"name": "KartonSzklo", "label": "Karton (szkło)", "size": Vector3(0.5, 0.5, 0.5), "mass": 5.0,
				"value": 250.0, "dur": 25.0, "color": Color(0.6, 0.75, 0.85), "pos": Vector3(0.8, y + 0.27, -2.5),
				"text": "SZKŁO"},
	]
	for entry in table:
		var item := ITEM_SCENE.instantiate() as Grabbable
		item.name = entry["name"]
		item.item_name = entry["label"]
		item.size = entry["size"]
		item.mass = entry["mass"]
		item.value = entry["value"]
		item.durability = entry["dur"]
		item.color = entry["color"]
		item.label_text = entry.get("text", "")
		item.position = entry["pos"]
		items.add_child(item)


func _build_job() -> void:
	var job := JobManager.new()
	job.name = "Job"
	job.zone = bus_zone
	add_child(job)


# --- Pomocnicze do geometrii --------------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_materials[color] = mat
	return _materials[color]


func _aabb(min_p: Vector3, max_p: Vector3, color: Color, solid: bool = true) -> void:
	_box((min_p + max_p) * 0.5, max_p - min_p, color, 0.0, solid)


## Strop o górnej powierzchni na wysokości y.
func _slab(x0: float, x1: float, z0: float, z1: float, y: float, color: Color) -> void:
	_aabb(Vector3(x0, y - T, z0), Vector3(x1, y, z1), color)


## Pochylnia od (z_a, y_a) do (z_b, y_b), pas o środku x_center i szerokości width.
func _ramp(x_center: float, width: float, z_a: float, y_a: float, z_b: float, y_b: float) -> void:
	var dz: float = z_b - z_a
	var dy: float = y_b - y_a
	var length: float = Vector2(dz, dy).length()
	var angle: float = atan2(dy, absf(dz)) * -signf(dz)
	var center := Vector3(x_center, (y_a + y_b) * 0.5 - T * 0.5 * cos(angle), (z_a + z_b) * 0.5)
	_box(center, Vector3(width, T, length), COL_STAIR, angle, true)


func _box(center: Vector3, box_size: Vector3, color: Color, rot_x: float = 0.0, solid: bool = true) -> void:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	box_mesh.material = _material(color)
	mesh.mesh = box_mesh
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = center
		body.rotation.x = rot_x
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box_size
		shape.shape = box_shape
		body.add_child(shape)
		body.add_child(mesh)
		_geo.add_child(body)
	else:
		mesh.position = center
		mesh.rotation.x = rot_x
		_geo.add_child(mesh)


func _light(pos: Vector3, light_range: float, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = light_range
	light.light_energy = energy
	_geo.add_child(light)
