extends "res://scripts/levels/level.gd"
## Siedziba firmy (baza między zleceniami). Budowana w kodzie według rzutu z góry:
##
##   z=0  ┌── WC ──┬───────── okno ────── TV ──────── regał ─── okno ── biurko(PC) ──┐
##        │ toaleta drzwi                  kanapa      │                            │
##        ├────────┘                                   regał                  regał │
##        │ regał────────                                                    │      │
##  BRAMA │  ┌──────────────┐  warsztat  ┌──────── drzwi ───────────────────┘      │
## (x=0)  │  │ miejsce auta │  (stół)    │ SKLEP: regał            okno            │
##        │  └──────────────┘            │ półka z przedmiotami do kupienia         │
## z=10.8 └────── okno ──────────────────┴──────────────────────────────────────────┘
##        x=0                                                                   x=20
##
## Skala: 1 px rzutu = 0,01465 m (budynek 20 x 10,8 m). +X w prawo, +Z w dół rzutu.
## Tekstury i plakaty są opcjonalne - jeśli pliki istnieją, podpinają się same:
##   res://assets/textures/hq_floor.(png|jpg)   beton podłogi
##   res://assets/textures/hq_wall.(png|jpg)    ściany
##   res://assets/textures/garage_door.(png|jpg) brama garażowa
##   res://assets/posters/poster_1..9.(png|jpg) plakaty (pionowe 2:3)

const ITEM_SCENE: PackedScene = preload("res://scenes/items/grabbable.tscn")
const FURNITURE: String = "res://assets/models/furniture/%s.glb"

const W: float = 20.0          ## szerokość budynku (X)
const D: float = 10.77         ## głębokość budynku (Z)
const WALL_H: float = 3.5      ## wysokość ścian = sufit
const T: float = 0.2           ## grubość ścian
const DOOR_H: float = 2.1
const SILL: float = 1.0        ## parapet okna
const WIN_TOP: float = 2.3

const COL_WALL: Color = Color(0.86, 0.84, 0.79)
const COL_FLOOR: Color = Color(0.56, 0.56, 0.54)
const COL_CEILING: Color = Color(0.78, 0.78, 0.76)
const COL_GROUND: Color = Color(0.33, 0.5, 0.29)
const COL_ASPHALT: Color = Color(0.2, 0.2, 0.22)
const COL_GARAGE: Color = Color(0.55, 0.12, 0.12)
const COL_RACK: Color = Color(0.95, 0.72, 0.15)      ## żółte regały (jak na rzucie)
const COL_RACK_SHELF: Color = Color(0.42, 0.42, 0.45)
const COL_WOOD: Color = Color(0.55, 0.38, 0.22)
const COL_PAINT: Color = Color(1.0, 0.85, 0.2)
## Jak gęsto stoją kartony na regałach (0..1).
const RACK_FILL: float = 0.28
## Jak często zamiast pustego miejsca na regale stoi drobiazg (0..1).
const RACK_DECOR: float = 0.18
## Dekoracje mają losową wielkość z tego zakresu (1.0 = 100 %, 2.0 = 200 %).
const DECOR_SCALE_MIN: float = 1.4
const DECOR_SCALE_MAX: float = 2.0

## Kolor świetlówek (ciepły, żółtawy) i ich losowe mruganie.
const LAMP_COLOR: Color = Color(1.0, 0.82, 0.52)
const FLICKER_MIN: float = 3.0
const FLICKER_MAX: float = 7.0
const FLICKER_OFF: float = 0.5

## Plakaty: [pozycja środka, obrót Y (w stronę pokoju), roboczy tytuł]
const POSTERS: Array = [
	[Vector3(4.9, 1.7, 0.12), 0.0, "Lift with your back"],
	[Vector3(9.52, 2.45, 0.12), 0.0, "Days without an incident"],
	[Vector3(16.2, 2.35, 0.12), 0.0, "Employee of the month"],
	[Vector3(19.88, 1.7, 2.8), -PI / 2.0, "Fragile is just a suggestion"],
	[Vector3(1.3, 1.7, 10.65), PI, "Wanted: pivot"],
	[Vector3(6.6, 1.7, 10.65), PI, "The Stairs 2"],
	[Vector3(2.5, 1.6, 0.12), 0.0, "Restroom"],
	[Vector3(4.08, 1.7, 2.45), PI / 2.0, "Your back belongs to the company"],
	[Vector3(12.3, 1.7, 6.82), 0.0, "Shop"],
]

var _geo: Node3D
var _materials: Dictionary = {}
## Świetlówki: [OmniLight3D, siatka oprawy] - do mrugania.
var _lamps: Array = []
## Dekoracje-przedmioty (Decor1, Decor2... - stałe nazwy dla sieci).
var _decor_root: Node3D
var _decor_count: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1337  # ten sam wystrój u wszystkich graczy
	_geo = Node3D.new()
	_geo.name = "Geometry"
	add_child(_geo)
	_decor_root = Node3D.new()
	_decor_root.name = "Decor"
	add_child(_decor_root)

	_build_ground()
	_build_walls()
	_build_lights()
	_build_lounge()
	_build_office()
	_build_racks()
	_build_garage()
	_build_shop()
	_build_toilet()
	_build_decor()
	_build_posters()
	_build_items()
	super()
	if multiplayer.is_server():
		_schedule_flicker()


# --- Budynek --------------------------------------------------------------------------

func _build_ground() -> void:
	_aabb(Vector3(-40, -0.5, -30), Vector3(60, 0, 40), COL_GROUND)                     # trawa
	_box(Vector3(-5.0, 0.003, 7.58), Vector3(10.0, 0.006, 5.0), COL_ASPHALT, 0.0, false)  # podjazd
	_box(Vector3(W * 0.5, 0.004, D * 0.5), Vector3(W, 0.008, D), COL_FLOOR, 0.0, false,
			"res://assets/textures/hq_floor", 0.5)                                       # posadzka
	# Sufit / dach
	_aabb(Vector3(-T, WALL_H, -T), Vector3(W + T, WALL_H + 0.25, D + T), COL_CEILING)


func _build_walls() -> void:
	# Zewnętrzne: [od, do, dół otworu, góra otworu]
	_wall(true, 0.0, -T * 0.5, W + T * 0.5, [[5.61, 7.03, SILL, WIN_TOP], [13.85, 15.09, SILL, WIN_TOP]])
	_wall(true, D, -T * 0.5, W + T * 0.5, [[2.64, 4.59, SILL, WIN_TOP]])
	_wall(false, 0.0, 0.0, D, [[5.49, 9.67, 0.0, 3.0]])              # brama garażowa
	_wall(false, W, 0.0, D, [[7.62, 8.94, SILL, WIN_TOP]])

	# WC (lewy górny róg) z drzwiami do hali.
	_wall(false, 3.96, 0.0, 3.0, [[0.9, 1.9, 0.0, DOOR_H]])
	_wall(true, 3.0, 0.0, 3.96 + T * 0.5)

	# Sklep (prawy dolny róg) z drzwiami do hali.
	_wall(true, 6.7, 11.06, W, [[13.4, 14.6, 0.0, DOOR_H]])
	_wall(false, 11.06, 6.7, D)

	# Szyby w oknach (z kolizją, żeby nic nie wyleciało).
	_glass(true, 0.0, 5.61, 7.03)
	_glass(true, 0.0, 13.85, 15.09)
	_glass(true, D, 2.64, 4.59)
	_glass(false, W, 7.62, 8.94)


func _build_lights() -> void:
	var main_lights: Array[Vector3] = [
		Vector3(6.0, 0, 2.2), Vector3(9.5, 0, 2.2), Vector3(14.5, 0, 2.5), Vector3(17.6, 0, 3.4),
		Vector3(4.4, 0, 7.5), Vector3(9.0, 0, 7.8),
	]
	for i in main_lights.size():
		_ceiling_light(main_lights[i], 8.0, 1.25, i < 2)
	_ceiling_light(Vector3(2.0, 0, 1.5), 4.0, 0.8, false)    # WC
	_ceiling_light(Vector3(13.5, 0, 8.7), 6.0, 1.0, false)   # sklep
	_ceiling_light(Vector3(17.5, 0, 8.7), 6.0, 1.0, false)


# --- Strefy z rzutu ------------------------------------------------------------------

## Kanapa naprzeciw telewizora stojącego na kartonach.
func _build_lounge() -> void:
	_prop("rugRectangle", Vector3(9.6, 0.0, 2.3), 0.0, 3.2, false)
	_wersalka(Vector3(9.6, 0.0, 3.7), PI)  # przodem do telewizora

	var box_top: float = 0.0
	for x: float in [8.75, 9.52, 10.29]:
		var box := _prop(BoxCatalog.path(["box_bedroom", "box_basement", "box_arrows"][int(x * 10) % 3]),
				Vector3(x, 0.0, 0.0), _rng.randf_range(-0.08, 0.08), 0.75)
		_back_to_wall(box, 0.0, 0.0)
		box_top = _size(box).y
	var tv := _prop("televisionModern", Vector3(9.52, box_top, 0.0), 0.0, 1.9)
	_back_to_wall(tv, 0.0, 0.0)


## Klasyczna wersalka z PRL-u: kanciasta, z boczkami i dwiema poduchami.
## Każda część ma własny hitbox, więc da się na niej usiąść/wskoczyć i nic nie wisi w powietrzu.
## Lokalnie: szerokość wzdłuż X, przód w stronę +Z (obrót rot_y odwraca ją do telewizora).
func _wersalka(pos: Vector3, rot_y: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Wersalka"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = rot_y
	_geo.add_child(body)

	var fabric := Color(0.58, 0.34, 0.2)       # brązowo-rudy plusz
	var cushion := Color(0.66, 0.4, 0.24)
	var base := Color(0.32, 0.2, 0.13)
	var half_w: float = 0.95                   # pół szerokości bez boczków
	var arm: float = 0.16
	var depth: float = 0.9
	var back_d: float = 0.22                   # grubość oparcia

	# Skrzynia (podstawa na pościel) i nóżki.
	_part(body, Vector3(0, 0.23, 0), Vector3(half_w * 2.0, 0.3, depth), base)
	for x: float in [-half_w - arm * 0.5, half_w + arm * 0.5]:
		for z: float in [-depth * 0.5 + 0.06, depth * 0.5 - 0.06]:
			_part(body, Vector3(x, 0.04, z), Vector3(0.06, 0.08, 0.06), Color(0.15, 0.1, 0.07), false)
	# Siedzisko: dwie poduchy.
	var seat_d: float = depth - back_d
	for side: float in [-1.0, 1.0]:
		_part(body, Vector3(side * half_w * 0.5, 0.45, back_d * 0.5), Vector3(half_w - 0.02, 0.14, seat_d), cushion)
	# Oparcie: skrzynia + dwie poduchy.
	_part(body, Vector3(0, 0.62, -depth * 0.5 + back_d * 0.5), Vector3(half_w * 2.0, 0.5, back_d), fabric)
	for side: float in [-1.0, 1.0]:
		_part(body, Vector3(side * half_w * 0.5, 0.66, -depth * 0.5 + back_d + 0.06),
				Vector3(half_w - 0.04, 0.34, 0.12), cushion)
	# Boczki.
	for side: float in [-1.0, 1.0]:
		_part(body, Vector3(side * (half_w + arm * 0.5), 0.36, 0), Vector3(arm, 0.56, depth), fabric)


## Część mebla: siatka + (opcjonalnie) jej własny hitbox w tym samym ciele.
func _part(body: StaticBody3D, center: Vector3, size: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	mesh.position = center
	body.add_child(mesh)
	if collide:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = center
		body.add_child(shape)


## Biurko z komputerem (tu będzie wybór zleceń).
func _build_office() -> void:
	var desk_a := _prop("desk", Vector3(16.45, 0.0, 0.0), 0.0, 2.0)
	var desk_b := _prop("desk", Vector3(18.5, 0.0, 0.0), 0.0, 2.0)
	_back_to_wall(desk_a, 0.0, 0.0)
	_back_to_wall(desk_b, 0.0, 0.0)
	var top: float = _size(desk_a).y
	var z: float = desk_a.position.z if desk_a != null else 0.6

	_prop("computerScreen", Vector3(16.1, top, z - 0.15), 0.12, 0.7, false)
	_prop("computerScreen", Vector3(16.85, top, z - 0.15), -0.12, 0.7, false)
	_prop("computerKeyboard", Vector3(16.45, top, z + 0.2), 0.0, 0.5, false)
	_prop("computerMouse", Vector3(16.95, top, z + 0.22), 0.0, 0.1, false)
	_prop("laptop", Vector3(18.2, top, z), 0.3, 0.45, false)
	_prop("radio", Vector3(19.0, top, z - 0.1), -0.2, 0.4, false)
	_prop("chairDesk", Vector3(16.45, 0.0, z + _size(desk_a).z * 0.5 + 0.35), PI + 0.15, 0.7)
	_prop("pottedPlant", Vector3(19.55, 0.0, 2.6), 0.0, 0.6)
	# Drobiazgi na biurkach.
	_decor("mug", Vector3(17.25, top, z + 0.05), 0.4)
	_decor("plant_succulent", Vector3(15.65, top, z - 0.15), 0.0)
	_decor("photo_frame", Vector3(18.75, top, z - 0.2), -0.25)
	_decor("plant_cactus", Vector3(19.35, top, z + 0.15), 0.0)

	_marker("JobComputer", Vector3(16.45, 0.0, 2.3))
	_sign("COMPUTER\njob board (soon)", Vector3(16.5, 2.0, 1.4))


## Żółte regały dekoracyjne pełne kartonów.
func _build_racks() -> void:
	_rack(0.34, 4.73, 3.52, 4.69)      # przy WC
	_rack(12.38, 13.48, 0.56, 4.64)    # środkowy, pionowy
	_rack(18.71, 19.66, 3.44, 6.33)    # przy prawej ścianie
	_rack(15.09, 18.83, 6.89, 7.62)    # w sklepie, pod ścianą


## Brama, miejsce na auto i stół warsztatowy (ulepszenia pojazdu).
func _build_garage() -> void:
	# Brama garażowa: zawias u góry otworu, na E skrzydło unosi się pod sufit (do środka).
	var gate := Door.new()
	gate.name = "GarageDoor"
	gate.position = Vector3(0.0, 3.0, 7.58)
	gate.open_rotation = Vector3(0.0, 0.0, PI * 0.48)
	gate.duration = 1.4
	gate.label_closed = "Otwórz bramę"
	gate.label_open = "Zamknij bramę"
	add_child(gate)
	# Tekstura bramy przyczepiona do skrzydła (nie do świata), żeby nie "pływała" przy otwieraniu.
	var gate_mat := StandardMaterial3D.new()
	var gate_tex: Texture2D = UITheme.load_texture("res://assets/textures/garage_door.png")
	if gate_tex != null:
		gate_mat.albedo_texture = gate_tex
		gate_mat.uv1_triplanar = true
		gate_mat.uv1_scale = Vector3.ONE / 3.0  # tekstura co 3 m = żeberka ~19 cm
	else:
		gate_mat.albedo_color = COL_GARAGE
	var gate_panel := gate.build_panel(Vector3(0.1, 3.0, 4.18), Vector3(0.0, -1.5, 0.0), gate_mat)
	for i in (0 if gate_tex != null else 7):  # przetłoczenia tylko bez tekstury (ona ma własne)
		var groove := MeshInstance3D.new()
		var groove_mesh := BoxMesh.new()
		groove_mesh.size = Vector3(0.02, 0.05, 4.1)
		groove.mesh = groove_mesh
		groove.material_override = _material(COL_GARAGE.darkened(0.3))
		groove.position = Vector3(0.06, 0.4 + i * 0.4 - 1.5, 0.0)
		gate_panel.add_child(groove)

	# Drzwi do WC i do sklepu (zawias przy jednej krawędzi otworu, otwierają się do pokoju).
	_door("DoorWC", Vector3(3.96, 0.0, 0.9), 0.0, 1.0)
	_door("DoorShop", Vector3(13.4, 0.0, 6.7), PI / 2.0, 1.2)

	# Miejsce na auto: żółte linie na posadzce.
	var x0: float = 0.88
	var x1: float = 7.84
	var z0: float = 5.82
	var z1: float = 9.23
	for line: Array in [[x0, z0, x1, z0 + 0.1], [x0, z1 - 0.1, x1, z1], [x1 - 0.1, z0, x1, z1]]:
		_box(Vector3((line[0] + line[2]) * 0.5, 0.012, (line[1] + line[3]) * 0.5),
				Vector3(line[2] - line[0], 0.01, line[3] - line[1]), COL_PAINT, 0.0, false)
	_marker("CarSpot", Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5))
	var floor_label := Label3D.new()
	floor_label.text = "VAN PARKING"
	floor_label.font = TextFit.font(false)
	floor_label.pixel_size = 0.01
	floor_label.modulate = Color(COL_PAINT, 0.85)
	floor_label.rotation = Vector3(-PI / 2.0, PI / 2.0, 0.0)
	floor_label.position = Vector3(6.9, 0.02, 7.52)
	_geo.add_child(floor_label)

	# Stół warsztatowy: blat na nogach + półka, tablica na narzędzia na ścianie.
	var bx0: float = 9.7
	var bx1: float = 10.81
	var bz0: float = 6.81
	var bz1: float = 10.62
	_aabb(Vector3(bx0, 0.88, bz0), Vector3(bx1, 0.96, bz1), COL_WOOD)
	_aabb(Vector3(bx0 + 0.08, 0.2, bz0 + 0.08), Vector3(bx1 - 0.08, 0.24, bz1 - 0.08), COL_WOOD.darkened(0.2))
	for corner: Vector2 in [Vector2(bx0 + 0.08, bz0 + 0.08), Vector2(bx1 - 0.08, bz0 + 0.08),
			Vector2(bx0 + 0.08, bz1 - 0.08), Vector2(bx1 - 0.08, bz1 - 0.08)]:
		_aabb(Vector3(corner.x - 0.04, 0.0, corner.y - 0.04), Vector3(corner.x + 0.04, 0.88, corner.y + 0.04),
				Color(0.25, 0.25, 0.27))
	_box(Vector3(10.94, 1.75, 8.7), Vector3(0.03, 1.2, 3.4), Color(0.78, 0.66, 0.48), 0.0, false)  # tablica
	for i in 9:  # zarysy narzędzi na tablicy
		var tz: float = 7.25 + i * 0.36
		var tool_h: float = _rng.randf_range(0.25, 0.55)
		_box(Vector3(10.92, 1.75 + _rng.randf_range(-0.2, 0.2), tz), Vector3(0.03, tool_h, 0.07),
				Color(0.18, 0.18, 0.2), 0.0, false)
	# Skrzynka narzędziowa i imadło na blacie.
	_aabb(Vector3(9.95, 0.96, 7.1), Vector3(10.45, 1.2, 7.65), Color(0.8, 0.15, 0.12))
	_aabb(Vector3(10.1, 0.96, 9.7), Vector3(10.4, 1.15, 10.0), Color(0.3, 0.35, 0.42))
	_marker("Workbench", Vector3(9.2, 0.0, 8.7))
	_sign("WORKSHOP\nvan upgrades (soon)", Vector3(10.2, 2.55, 8.7))


## Sklep: długa drewniana półka z przedmiotami do kupienia (na razie zapychacze).
func _build_shop() -> void:
	var x0: float = 11.65
	var x1: float = 19.56
	var z0: float = 9.74
	var z1: float = 10.48
	var levels: Array[float] = [0.1, 0.65, 1.2, 1.75]
	for y in levels:
		_aabb(Vector3(x0, y - 0.04, z0), Vector3(x1, y, z1), COL_WOOD)
	for i in 6:
		var px: float = lerpf(x0 + 0.03, x1 - 0.03, i / 5.0)
		_aabb(Vector3(px - 0.03, 0.0, z0), Vector3(px + 0.03, 2.0, z1), COL_WOOD.darkened(0.25))

	var goods: Array[String] = ["lampSquareTable", "radio", "speakerSmall", "plantSmall1", "toaster",
			"kitchenBlender", "books", "kitchenCoffeeMachine", "plantSmall2", "laptop", "plantSmall3"]
	var zc: float = (z0 + z1) * 0.5
	var gi: int = 0
	for li in 3:
		var y: float = levels[li]
		var x: float = x0 + 0.55
		while x < x1 - 0.4:
			var prop := _prop(goods[gi % goods.size()], Vector3(x, y, zc), PI + _rng.randf_range(-0.2, 0.2), 0.42, false)
			gi += 1
			if prop != null:
				var tag := Label3D.new()
				tag.text = "PRICE ???"
				tag.font = TextFit.font(false)
				tag.pixel_size = 0.0025
				tag.modulate = COL_PAINT
				tag.rotation.y = PI
				tag.position = Vector3(x, y + 0.05, z0 - 0.01)
				_geo.add_child(tag)
			x += 0.95
	_marker("Shop", Vector3(15.6, 0.0, 9.0))
	_sign("SHOP\n(soon)", Vector3(15.6, 2.4, 9.9))


func _build_toilet() -> void:
	var toilet := _prop("toilet", Vector3(0.0, 0.0, 1.51), PI / 2.0, 0.55)
	if toilet != null:
		toilet.position.x = T * 0.5 + _size(toilet).z * 0.5  # plecami do lewej ściany
	var sink := _prop("bathroomSink", Vector3(2.6, 0.0, 0.0), 0.0, 0.6)
	_back_to_wall(sink, 0.0, 0.0)
	_prop("trashcan", Vector3(3.55, 0.0, 2.6), 0.0, 0.3)


## Dekoracje (scenes/props/decor): narzędzia na warsztacie, półki ścienne z drobiazgami,
## rośliny, pachołki przy miejscu na busa, kula dyskotekowa nad kanapą.
func _build_decor() -> void:
	# Warsztat: narzędzia na blacie (y 0,96) i na dolnej półce (y 0,24).
	_decor("tool_hammer", Vector3(10.2, 0.96, 8.25), 0.3)
	_decor("tool_wrench", Vector3(10.3, 0.96, 8.75), -0.4)
	_decor("tool_screwdriver", Vector3(10.2, 0.96, 9.15), 0.2)
	_decor("tool_drill", Vector3(10.3, 0.96, 9.45), PI)
	_decor("tool_tape_measure", Vector3(10.55, 0.96, 7.95), 0.5)
	_decor("thermos", Vector3(10.65, 0.96, 8.45), 0.0)
	_decor("hard_hat", Vector3(10.32, 0.96, 10.35), 0.6)
	_decor("tool_saw", Vector3(10.25, 0.24, 9.9), PI / 2.0)
	_decor("paint_can_red", Vector3(9.98, 0.24, 7.3), 0.0)
	_decor("paint_can_blue", Vector3(10.45, 0.24, 7.35), 1.0)
	_decor("paint_can_white", Vector3(10.2, 0.24, 8.3), 2.0)

	# Półki ścienne: [drobiazg, przesunięcie wzdłuż półki]
	_wall_shelf(Vector3(19.79, 1.57, 1.1), -PI / 2.0,                    # nad biurkiem
			[["globe", -0.35], ["trophy", 0.0], ["alarm_clock", 0.35]])
	_wall_shelf(Vector3(7.7, 1.37, 0.21), 0.0,                            # obok telewizora
			[["rubik_cube", -0.35], ["snow_globe", 0.0], ["lava_lamp", 0.35]])
	_wall_shelf(Vector3(0.21, 1.25, 2.4), PI / 2.0,                       # w WC
			[["duck_rubber", -0.25], ["flowers_vase", 0.25]])
	_wall_shelf(Vector3(11.27, 1.32, 7.7), PI / 2.0,                      # w sklepie
			[["piggy_bank", -0.35], ["book_stack", 0.0], ["bowling_pin", 0.35]])

	# Podłoga.
	_decor("plant_monstera", Vector3(11.55, 0.0, 4.3), 0.0)        # przy kanapie
	_decor("plant_fern", Vector3(12.85, 0.0, 6.2), 0.0)            # przy drzwiach do sklepu
	_decor("plant_fern", Vector3(0.42, 0.0, 0.42), 1.0)            # w rogu WC
	_decor("traffic_cone", Vector3(8.3, 0.0, 6.1), 0.3)            # przy miejscu na busa
	_decor("traffic_cone", Vector3(8.3, 0.0, 9.9), -0.2)
	_decor("pizza_boxes", Vector3(11.2, 0.0, 2.7), 0.4)            # obok kanapy
	_decor("dumbbell", Vector3(7.95, 0.0, 4.45), 1.2)
	_decor("garden_gnome", Vector3(4.55, 0.0, 0.4), 0.3)           # pilnuje drzwi do WC
	var ball_scale: float = _rng.randf_range(1.0, 1.3)  # większa wisiałaby za nisko nad głowami
	# Kula (0,34 m) + sznurek (0,8 m), oba w skali - sznurek ma sięgać sufitu. Wisi, aż ktoś ją zerwie.
	_decor("disco_ball", Vector3(9.6, WALL_H - 1.14 * ball_scale, 2.3), 0.0, true, ball_scale)


## Dekoracja jako przedmiot do noszenia (bez wartości) w losowej skali 100-140 %.
## pos = środek podstawy. frozen = przyczepiona (półka, kula), spada dopiero po złapaniu.
func _decor(decor_name: String, pos: Vector3, rot_y: float, frozen: bool = false, fixed_scale: float = -1.0) -> Grabbable:
	var s: float = fixed_scale if fixed_scale > 0.0 else _rng.randf_range(DECOR_SCALE_MIN, DECOR_SCALE_MAX)
	var item := ITEM_SCENE.instantiate() as Grabbable
	_decor_count += 1
	item.name = "Decor%d" % _decor_count  # stała nazwa = ta sama ścieżka sieciowa u każdego
	item.item_name = DecorCatalog.display_name(decor_name)
	item.model = DecorCatalog.scene(decor_name)
	item.model_scale = s
	item.mass = DecorCatalog.mass(decor_name) * s * s * s
	item.value = 0.0
	item.spawn_from_bottom = true
	item.start_frozen = frozen
	item.position = pos + Vector3(0, 0.005, 0)
	item.rotation.y = rot_y
	_decor_root.add_child(item)
	return item


## Półka ścienna (tył przy ścianie, zawsze 100 %, przyczepiona) z drobiazgami ustawionymi wzdłuż niej.
func _wall_shelf(pos: Vector3, rot_y: float, items: Array) -> void:
	_decor("wall_shelf", pos, rot_y, true, 1.0)
	var along := Vector3(cos(rot_y), 0.0, -sin(rot_y))
	for entry: Array in items:
		var at: Vector3 = pos + along * float(entry[1]) + Vector3(0, Decor.SHELF_TOP + 0.01, 0)
		_decor(entry[0], at, rot_y + _rng.randf_range(-0.3, 0.3))


## Plakaty: obrazek z assets/posters, a bez niego kolorowa zaślepka z tytułem.
func _build_posters() -> void:
	for i in POSTERS.size():
		var entry: Array = POSTERS[i]
		_poster(i + 1, entry[0], entry[1], entry[2])

	# Logo firmy na ścianie między telewizorem a regałem.
	var logo: Texture2D = UITheme.load_texture(UITheme.LOGO_PATH)
	if logo != null:
		var logo_sign := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.7, 1.7 * logo.get_height() / logo.get_width())
		logo_sign.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = logo
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		logo_sign.material_override = mat
		logo_sign.position = Vector3(11.6, 2.2, 0.12)
		_geo.add_child(logo_sign)


## Kartony do noszenia (i rzucania w kumpli) między zleceniami.
## Nie są ze zleceń, więc nie mają wartości: nie liczą się do szkód i się nie niszczą.
## [wariant, nazwa w grze, masa, środek na podłodze]
const HQ_ITEMS: Array = [
	["box_kitchen", "Karton (kuchnia)", 6.0, Vector3(1.0, 0.0, 5.15)],
	["box_kuba", "Rzeczy Kuby", 5.0, Vector3(1.75, 0.0, 5.15)],
	["box_mystery", "Tajemniczy karton", 7.0, Vector3(2.5, 0.0, 5.15)],
	["box_fragile", "Karton ze szkłem", 5.0, Vector3(3.4, 0.0, 5.15)],
	["box_books", "Książki", 14.0, Vector3(8.0, 0.0, 4.95)],
	["box_wardrobe", "Karton na szafę", 9.0, Vector3(15.0, 0.0, 4.6)],
	["box_painting", "Obraz w kartonie", 6.0, Vector3(16.3, 0.0, 4.6)],
	["box_tv", "Telewizor w kartonie", 16.0, Vector3(17.6, 0.0, 4.6)],
]


func _build_items() -> void:
	var items := Node3D.new()
	items.name = "Items"
	add_child(items)
	for i in HQ_ITEMS.size():
		var entry: Array = HQ_ITEMS[i]
		var scene: PackedScene = BoxCatalog.scene(entry[0])
		var item := ITEM_SCENE.instantiate() as Grabbable
		item.name = "Karton%d" % (i + 1)
		item.item_name = entry[1]
		item.model = scene
		item.model_scale = 1.0  # kartony proceduralne mają już prawdziwe wymiary
		item.mass = entry[2]
		item.value = 0.0
		# Grabbable centruje model na środku ciała, więc stawiamy go na połowie wysokości.
		var probe := scene.instantiate() as CardboardBox
		var height: float = probe.size.y
		probe.free()
		item.position = (entry[3] as Vector3) + Vector3(0, height * 0.5 + 0.02, 0)
		items.add_child(item)


# --- Elementy wielokrotnego użytku --------------------------------------------------

## Ściana wzdłuż X (z = fixed) albo Z (x = fixed), z otworami [od, do, dół, góra].
func _wall(along_x: bool, fixed: float, from: float, to: float, openings: Array = []) -> void:
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cursor: float = from
	for o: Array in cuts:
		if o[0] > cursor:
			_wall_piece(along_x, fixed, cursor, o[0], 0.0, WALL_H)
		if o[2] > 0.0:
			_wall_piece(along_x, fixed, o[0], o[1], 0.0, o[2])       # pod oknem
		if o[3] < WALL_H:
			_wall_piece(along_x, fixed, o[0], o[1], o[3], WALL_H)    # nadproże
		cursor = o[1]
	if cursor < to:
		_wall_piece(along_x, fixed, cursor, to, 0.0, WALL_H)


func _wall_piece(along_x: bool, fixed: float, a: float, b: float, y0: float, y1: float) -> void:
	var tex: String = "res://assets/textures/hq_wall"
	if along_x:
		_aabb(Vector3(a, y0, fixed - T * 0.5), Vector3(b, y1, fixed + T * 0.5), COL_WALL, tex, 0.5)
	else:
		_aabb(Vector3(fixed - T * 0.5, y0, a), Vector3(fixed + T * 0.5, y1, b), COL_WALL, tex, 0.5)


func _glass(along_x: bool, fixed: float, a: float, b: float) -> void:
	var key: String = "glass"
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		# Przydymione szkło: ciemne, mało przezroczyste, z lekkim połyskiem.
		mat.albedo_color = Color(0.12, 0.14, 0.17, 0.72)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.08
		mat.metallic = 0.3
		mat.metallic_specular = 0.8
		_materials[key] = mat
	var size := Vector3(b - a, WIN_TOP - SILL, 0.03) if along_x else Vector3(0.03, WIN_TOP - SILL, b - a)
	var center := Vector3((a + b) * 0.5, (SILL + WIN_TOP) * 0.5, fixed) if along_x \
			else Vector3(fixed, (SILL + WIN_TOP) * 0.5, (a + b) * 0.5)
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _materials[key]
	body.add_child(mesh)
	_geo.add_child(body)


## Regał: żółte słupki, szare półki, kartony na każdej półce (losowo, ale tak samo u wszystkich).
func _rack(x0: float, x1: float, z0: float, z1: float, height: float = 2.2, levels: int = 4) -> void:
	var long_x: bool = (x1 - x0) >= (z1 - z0)
	var length: float = (x1 - x0) if long_x else (z1 - z0)
	var depth: float = (z1 - z0) if long_x else (x1 - x0)
	var segments: int = maxi(1, ceili(length / 1.8))
	for i in segments + 1:
		var t: float = float(i) / segments
		for side in 2:
			var px: float
			var pz: float
			if long_x:
				px = lerpf(x0 + 0.04, x1 - 0.04, t)
				pz = z0 + 0.04 if side == 0 else z1 - 0.04
			else:
				px = x0 + 0.04 if side == 0 else x1 - 0.04
				pz = lerpf(z0 + 0.04, z1 - 0.04, t)
			_aabb(Vector3(px - 0.04, 0.0, pz - 0.04), Vector3(px + 0.04, height, pz + 0.04), COL_RACK)

	var gap: float = (height - 0.2) / (levels - 1)
	var rows: int = 2 if depth > 1.0 else 1
	for l in levels:
		var y: float = 0.12 + l * gap
		_aabb(Vector3(x0, y - 0.04, z0), Vector3(x1, y, z1), COL_RACK_SHELF)
		if l == levels - 1:
			break
		for r in rows:
			var across: float = (r + 0.5) / rows  # 0..1 w poprzek regału
			var cursor: float = 0.08
			while cursor < length - 0.45:
				var w: float = _rng.randf_range(0.38, 0.55)
				if cursor + w > length - 0.05:
					break
				var roll: float = _rng.randf()
				if roll < RACK_FILL + RACK_DECOR:
					var along: float = cursor + w * 0.5
					var pos: Vector3
					if long_x:
						pos = Vector3(x0 + along, y, lerpf(z0, z1, across))
					else:
						pos = Vector3(lerpf(x0, x1, across), y, z0 + along)
					if roll < RACK_FILL:  # karton
						var model: String = BoxCatalog.path(BoxCatalog.SHELF[_rng.randi() % BoxCatalog.SHELF.size()])
						var rot: float = (0.0 if long_x else PI / 2.0) + _rng.randf_range(-0.12, 0.12) \
								+ (PI if _rng.randf() < 0.5 else 0.0)  # napisy raz z jednej, raz z drugiej strony
						_prop(model, pos, rot, w * 0.92, false)
					else:  # drobiazg (kaczka, globus, puszka farby...) w prawdziwej skali
						var trinket: String = DecorCatalog.SHELF_TRINKETS[_rng.randi() % DecorCatalog.SHELF_TRINKETS.size()]
						_decor(trinket, pos, _rng.randf_range(0.0, TAU))
				cursor += w + 0.06


func _poster(index: int, pos: Vector3, rot_y: float, title: String) -> void:
	var tex: Texture2D = UITheme.load_texture("res://assets/posters/poster_%d.png" % index)
	var size := Vector2(0.9, 1.35)  # pionowy 2:3 (bez obrazka)
	if tex != null:  # wysokość stała, szerokość z proporcji obrazka
		size.x = size.y * tex.get_width() / tex.get_height()
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	_geo.add_child(holder)

	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(size.x + 0.08, size.y + 0.08, 0.02)
	frame.mesh = frame_mesh
	frame.material_override = _material(Color(0.12, 0.1, 0.1))
	frame.position.z = -0.012
	holder.add_child(frame)

	var picture := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	picture.mesh = quad
	var mat := StandardMaterial3D.new()
	if tex != null:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = Color.from_hsv(fmod(index * 0.13, 1.0), 0.45, 0.75)
		var label := Label3D.new()
		label.text = "POSTER %d\n%s" % [index, title]
		label.pixel_size = 0.004
		label.position.z = 0.01
		label.modulate = Color(0.1, 0.08, 0.06)
		label.outline_size = 0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = size.x / label.pixel_size * 0.9
		holder.add_child(label)
	picture.material_override = mat
	holder.add_child(picture)


## Drzwi na zawiasie w `hinge`. Skrzydło idzie od zawiasu wzdłuż lokalnego +Z
## (base_rot_y = PI/2 obraca je na oś +X). Otwierają się o -100° (do pokoju).
func _door(door_name: String, hinge: Vector3, base_rot_y: float, width: float) -> void:
	var door := Door.new()
	door.name = door_name
	door.position = hinge
	door.rotation.y = base_rot_y
	add_child(door)
	door.build_panel(Vector3(0.06, DOOR_H - 0.03, width - 0.04), Vector3(0.0, (DOOR_H - 0.03) * 0.5, width * 0.5),
			_material(Color(0.42, 0.3, 0.2)), "res://assets/models/building/door-rotate-square-a.glb")


func _ceiling_light(at: Vector3, light_range: float, energy: float, shadows: bool) -> void:
	var fixture: Node3D = _box(Vector3(at.x, WALL_H - 0.03, at.z), Vector3(1.3, 0.05, 0.18), Color(1, 1, 1),
			0.0, false, "", 1.0, true)
	var light := OmniLight3D.new()
	light.position = Vector3(at.x, WALL_H - 0.35, at.z)
	light.omni_range = light_range
	light.light_energy = energy
	light.light_color = LAMP_COLOR
	light.shadow_enabled = shadows
	_geo.add_child(light)
	_lamps.append([light, fixture])


# --- Mruganie świetlówek --------------------------------------------------------------
# Host co losowe 3-7 s gasi jedną losową lampę na 0,5 s i rozsyła to graczom,
# więc wszyscy widzą to samo.

func _schedule_flicker() -> void:
	get_tree().create_timer(randf_range(FLICKER_MIN, FLICKER_MAX)).timeout.connect(_flicker_random)


func _flicker_random() -> void:
	if _lamps.is_empty():
		return
	var index: int = randi() % _lamps.size()
	_rpc_flicker(index)
	for id in Net.ready_peers:
		if id != multiplayer.get_unique_id():
			_rpc_flicker.rpc_id(id, index)
	_schedule_flicker()


@rpc("authority", "call_remote", "reliable")
func _rpc_flicker(index: int) -> void:
	if index < 0 or index >= _lamps.size():
		return
	var light: OmniLight3D = _lamps[index][0]
	var fixture: MeshInstance3D = _lamps[index][1]
	var on_material: Material = fixture.material_override
	light.visible = false
	fixture.material_override = _material(Color(0.55, 0.53, 0.5))  # zgaszona świetlówka
	get_tree().create_timer(FLICKER_OFF).timeout.connect(func() -> void:
		light.visible = true
		fixture.material_override = on_material)


func _sign(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = TextFit.font(false)
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = UITheme.TAPE
	label.outline_modulate = UITheme.TEXT_DARK
	label.outline_size = 14
	label.font_size = 48
	label.position = pos
	_geo.add_child(label)


func _marker(marker_name: String, pos: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = pos
	add_child(marker)


# --- Modele -------------------------------------------------------------------------

## Wstawia model z Kenney Furniture Kit tak, że środek jego podstawy stoi w `pos`.
## fit_width > 0 skaluje model, by miał taką szerokość (oś X modelu, przed obrotem).
## Zwraca uchwyt (StaticBody3D z kolizją-pudełkiem albo Node3D bez kolizji), meta "size".
func _prop(model_name: String, pos: Vector3, rot_y: float = 0.0, fit_width: float = 0.0,
		collide: bool = true) -> Node3D:
	# Nazwa z Kenney Furniture Kit albo pełna ścieżka do sceny (np. karton z BoxCatalog).
	var path: String = model_name if model_name.begins_with("res://") else FURNITURE % model_name
	if not ResourceLoader.exists(path):
		push_warning("Brak modelu: %s" % path)
		return null
	var holder: Node3D
	if collide:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	_geo.add_child(holder)

	var visual: Node3D = (load(path) as PackedScene).instantiate()
	visual.scale = Vector3.ONE * (1.0 if model_name.begins_with("res://") else 2.0)  # Kenney ~1:2
	holder.add_child(visual)
	var box: AABB = _mesh_aabb(visual, holder)
	if fit_width > 0.0 and box.size.x > 0.01:
		visual.scale *= fit_width / box.size.x
		box = _mesh_aabb(visual, holder)
	visual.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	holder.set_meta("size", box.size)

	if collide:
		var body := holder as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size
		shape.shape = box_shape
		shape.position.y = box.size.y * 0.5
		body.add_child(shape)
	return holder


func _size(node: Node3D) -> Vector3:
	return node.get_meta("size", Vector3.ZERO) if node != null else Vector3.ZERO


## Dosuwa przedmiot (obrócony o 0 lub PI) tyłem do ściany wzdłuż X na wysokości wall_z.
func _back_to_wall(node: Node3D, wall_z: float, gap: float) -> void:
	if node == null:
		return
	var depth: float = _size(node).z
	if wall_z < D * 0.5:
		node.position.z = wall_z + T * 0.5 + gap + depth * 0.5
	else:
		node.position.z = wall_z - T * 0.5 - gap - depth * 0.5


func _mesh_aabb(root: Node3D, relative_to: Node) -> AABB:
	var result := AABB()
	var first: bool = true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# skip_bounds: elementy, które nie powinny powiększać hitboxa (np. odchylone klapy kartonu).
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and not node.has_meta("skip_bounds"):
			var mi := node as MeshInstance3D
			var box: AABB = _transform_between(mi, relative_to) * mi.get_aabb()
			result = box if first else result.merge(box)
			first = false
		stack.append_array(node.get_children())
	return result


func _transform_between(node: Node3D, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != ancestor and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# --- Bryły -----------------------------------------------------------------------------

func _material(color: Color, texture_base: String = "", uv_scale: float = 1.0, emissive: bool = false) -> StandardMaterial3D:
	var key: String = "%s|%s|%s|%s" % [color, texture_base, uv_scale, emissive]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if texture_base != "":
		var tex: Texture2D = UITheme.load_texture(texture_base + ".png")
		if tex != null:
			mat.albedo_color = Color.WHITE
			mat.albedo_texture = tex
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true
			mat.uv1_scale = Vector3.ONE * uv_scale
	if emissive:
		mat.emission_enabled = true
		mat.emission = LAMP_COLOR
		mat.emission_energy_multiplier = 2.5
	_materials[key] = mat
	return mat


func _aabb(min_p: Vector3, max_p: Vector3, color: Color, texture_base: String = "",
		uv_scale: float = 1.0) -> StaticBody3D:
	return _box((min_p + max_p) * 0.5, max_p - min_p, color, 0.0, true, texture_base, uv_scale) as StaticBody3D


func _box(center: Vector3, box_size: Vector3, color: Color, rot_x: float = 0.0, solid: bool = true,
		texture_base: String = "", uv_scale: float = 1.0, emissive: bool = false) -> Node3D:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color, texture_base, uv_scale, emissive)
	if not solid:
		mesh.position = center
		mesh.rotation.x = rot_x
		_geo.add_child(mesh)
		return mesh
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
	return body
