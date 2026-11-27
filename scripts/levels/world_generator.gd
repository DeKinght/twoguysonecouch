class_name WorldGenerator
extends Node3D
## Losowe miasto wokół Siedziby, tworzone po przyjęciu zlecenia.
##
## Całe miasto leży na siatce modułów 9 x 9 m (tyle ma kafel drogi KayKit i budynek
## z podstawą). Algorytm:
##  1. Linie ulic (X i Z) w losowych odstępach 4-6 modułów, od Siedziby na zewnątrz.
##     Kwartał Siedziby (budynek + 10 m wokół) jest zawsze otoczony ulicami, a ulica
##     po zachodniej stronie łączy się z podjazdem przed bramą garażu.
##  2. Z pełnej siatki usuwamy losowe odcinki ulic, ale tylko gdy sieć zostaje spójna
##     i nie powstaje ślepa uliczka (każde skrzyżowanie ma >= 2 wyloty).
##  3. Na każde skrzyżowanie trafia kafel pasujący do wylotów (zakręt / T / X / prosta)
##     w odpowiednim obrocie, między skrzyżowaniami - proste odcinki.
##  4. Moduł przy ulicy = budynek frontem do ulicy, moduł w głębi = park / parking.
##     Na obrzeżu pierścień wysokich budynków + niewidzialne ściany (nie da się wyjść).
##  5. Dom docelowy (z meblami do zabrania) w losowym kwartale daleko od Siedziby.
##
## Wszystko zależy tylko od `seed`, więc każdy gracz buduje identyczny świat
## (te same nazwy węzłów = te same ścieżki synchronizacji przedmiotów).

const M: float = 9.0                    ## bok modułu [m]
const ORIGIN: Vector2 = Vector2(-14.5, -14.5)  ## środek modułu (0, 0) - ulica przy Siedzibie
const LINES_PER_SIDE: int = 4           ## ile przecznic w każdą stronę od kwartału Siedziby
const REMOVE_CHANCE: float = 0.3
const CITY: String = "res://assets/models/city/%s.gltf"
const NATURE: String = "res://assets/models/nature/%s.gltf"
const S_CITY: float = 4.5               ## skala modeli KayKit City (kafel 2 j. = 9 m)
const ROAD_FLAT: float = 0.25           ## spłaszczenie kafli (krawężnik ~3 cm zamiast 11)
const BASE_SINK: float = 0.45           ## podstawa budynku (0,1 j.) chowa się w ziemi

## Prostokąt zarezerwowany na Siedzibę: budynek (20 x 10,8 m) + 10 m z każdej strony.
const HQ_RECT: Rect2 = Rect2(-10.0, -10.0, 40.0, 30.77)
const DRIVEWAY_Z: Vector2 = Vector2(5.08, 10.08)

enum { EMPTY, ROAD, HQ, BUILDING, PARK, BOUNDARY, TARGET }
const N: int = 1
const E: int = 2
const S: int = 4
const W: int = 8
const DIRS: Dictionary = {N: Vector2i(0, -1), E: Vector2i(1, 0), S: Vector2i(0, 1), W: Vector2i(-1, 0)}

const BUILDINGS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H"]
const TALL: Array[String] = ["C", "D", "G", "H"]
const TREES: Array[String] = ["Tree_1_A_Color1", "Tree_1_B_Color1", "Tree_2_A_Color1", "Tree_2_B_Color1",
		"Tree_3_A_Color1", "Tree_4_A_Color1", "Tree_4_B_Color1"]
const BUSHES: Array[String] = ["Bush_1_A_Color1", "Bush_2_A_Color1", "Bush_2_C_Color1", "Bush_4_A_Color1"]
const CARS: Array[String] = ["car_sedan", "car_hatchback", "car_stationwagon", "car_taxi"]

signal generated

var seed_value: int = 0
## Środek domu docelowego (do znacznika / nawigacji) i kierunek jego frontu.
var target_position: Vector3 = Vector3.ZERO
var target_items: Array[Grabbable] = []

var _rng := RandomNumberGenerator.new()
var _xl: Array[int] = []   ## indeksy modułów linii ulic wzdłuż X (kolumny)
var _zl: Array[int] = []
var _h: Dictionary = {}    ## Vector2i(i, j) -> true: odcinek wzdłuż X między liniami i, i+1 na linii j
var _v: Dictionary = {}    ## Vector2i(i, j) -> true: odcinek wzdłuż Z między liniami j, j+1 na linii i
var _type: Dictionary = {} ## Vector2i(moduł) -> typ
var _face: Dictionary = {} ## Vector2i(moduł) -> kierunek do ulicy (N/E/S/W)
var _road_mask: Dictionary = {}  ## Vector2i(moduł drogi) -> maska wylotów
var _batches: Dictionary = {}    ## ścieżka modelu -> Array[Transform3D]
var _collision: StaticBody3D
var _amin: int
var _amax: int
var _bmin: int
var _bmax: int


func generate(seed: int) -> void:
	seed_value = seed
	_rng.seed = seed
	_collision = StaticBody3D.new()
	_collision.name = "CityCollision"
	_collision.collision_layer = 1
	_collision.collision_mask = 0
	add_child(_collision)

	_make_lines()
	_make_edges()
	_prune_edges()
	_mark_roads()
	_mark_blocks()
	_pick_target()

	_build_ground()
	_build_roads()
	_build_blocks()
	_build_hq_fence()
	_build_bounds()
	_flush_batches()
	generated.emit()


# --- 1. Linie ulic -------------------------------------------------------------------

func _make_lines() -> void:
	# Kwartał Siedziby: kolumny 0..6 (ulice x = -14,5 i 39,5), wiersze 0..5 (z = -14,5 i 30,5).
	_xl = [0, 6]
	_zl = [0, 5]
	for k in LINES_PER_SIDE:
		_xl.push_front(_xl[0] - _rng.randi_range(4, 6))
		_xl.append(_xl[-1] + _rng.randi_range(4, 6))
		_zl.push_front(_zl[0] - _rng.randi_range(4, 6))
		_zl.append(_zl[-1] + _rng.randi_range(4, 6))
	_amin = _xl[0] - 1
	_amax = _xl[-1] + 1
	_bmin = _zl[0] - 1
	_bmax = _zl[-1] + 1


# --- 2. Sieć ulic ----------------------------------------------------------------------

func _make_edges() -> void:
	for j in _zl.size():
		for i in _xl.size() - 1:
			_h[Vector2i(i, j)] = true
	for i in _xl.size():
		for j in _zl.size() - 1:
			_v[Vector2i(i, j)] = true


func _prune_edges() -> void:
	var hq_i: int = _xl.find(0)  # linia ulicy przy bramie garażu (x = -14,5)
	var hq_j: int = _zl.find(0)
	var candidates: Array = []
	for key: Vector2i in _h:
		if key.y != 0 and key.y != _zl.size() - 1:  # zewnętrzny pierścień zostaje
			candidates.append(["h", key])
	for key: Vector2i in _v:
		if key.x != 0 and key.x != _xl.size() - 1:
			if key == Vector2i(hq_i, hq_j):
				continue  # ulica przy wjeździe do garażu
			candidates.append(["v", key])
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] + str(a[1])) < (b[0] + str(b[1])))  # stała kolejność przed tasowaniem
	for k in range(candidates.size() - 1, 0, -1):
		var r: int = _rng.randi_range(0, k)
		var tmp: Array = candidates[k]
		candidates[k] = candidates[r]
		candidates[r] = tmp
	for c: Array in candidates:
		if _rng.randf() > REMOVE_CHANCE:
			continue
		var dict: Dictionary = _h if c[0] == "h" else _v
		dict.erase(c[1])
		var ends: Array = _edge_nodes(c[0], c[1])
		if _degree(ends[0]) < 2 or _degree(ends[1]) < 2 or not _connected():
			dict[c[1]] = true  # cofamy: ślepa uliczka albo rozspójnienie


func _edge_nodes(kind: String, key: Vector2i) -> Array:
	if kind == "h":
		return [key, key + Vector2i(1, 0)]
	return [key, key + Vector2i(0, 1)]


func _node_mask(n: Vector2i) -> int:
	var mask: int = 0
	if _h.has(n):
		mask |= E
	if _h.has(n - Vector2i(1, 0)):
		mask |= W
	if _v.has(n):
		mask |= S
	if _v.has(n - Vector2i(0, 1)):
		mask |= N
	return mask


func _degree(n: Vector2i) -> int:
	var m: int = _node_mask(n)
	return int(m & N > 0) + int(m & E > 0) + int(m & S > 0) + int(m & W > 0)


func _connected() -> bool:
	var start := Vector2i(0, 0)
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var n: Vector2i = queue.pop_back()
		var m: int = _node_mask(n)
		for d: int in DIRS:
			if m & d:
				var nb: Vector2i = n + DIRS[d]
				if not seen.has(nb):
					seen[nb] = true
					queue.append(nb)
	return seen.size() == _xl.size() * _zl.size()


# --- 3. Moduły ---------------------------------------------------------------------------

func _mark_roads() -> void:
	for i in _xl.size():
		for j in _zl.size():
			var node := Vector2i(_xl[i], _zl[j])
			var mask: int = _node_mask(Vector2i(i, j))
			_type[node] = ROAD
			_road_mask[node] = mask
	for key: Vector2i in _h:
		for a in range(_xl[key.x] + 1, _xl[key.x + 1]):
			var m := Vector2i(a, _zl[key.y])
			_type[m] = ROAD
			_road_mask[m] = E | W
	for key: Vector2i in _v:
		for b in range(_zl[key.y] + 1, _zl[key.y + 1]):
			var m := Vector2i(_xl[key.x], b)
			_type[m] = ROAD
			_road_mask[m] = N | S


func _mark_blocks() -> void:
	for a in range(_amin, _amax + 1):
		for b in range(_bmin, _bmax + 1):
			var m := Vector2i(a, b)
			if _type.has(m):
				continue
			if _module_rect(m).intersects(HQ_RECT):
				_type[m] = HQ
				continue
			var outer: bool = a < _xl[0] or a > _xl[-1] or b < _zl[0] or b > _zl[-1]
			var roads: Array[int] = []
			for d: int in DIRS:
				if _type.get(m + DIRS[d], EMPTY) == ROAD:
					roads.append(d)
			if outer:
				_type[m] = BOUNDARY
				_face[m] = roads[0] if not roads.is_empty() else _inward(m)
			elif not roads.is_empty():
				_type[m] = BUILDING
				_face[m] = roads[_rng.randi_range(0, roads.size() - 1)]
			else:
				_type[m] = PARK


func _inward(m: Vector2i) -> int:
	if m.x < _xl[0]:
		return E
	if m.x > _xl[-1]:
		return W
	if m.y < _zl[0]:
		return S
	return N


func _module_rect(m: Vector2i) -> Rect2:
	var c: Vector2 = _center2(m)
	return Rect2(c - Vector2(M, M) * 0.5 + Vector2(0.01, 0.01), Vector2(M, M) - Vector2(0.02, 0.02))


func _center2(m: Vector2i) -> Vector2:
	return ORIGIN + Vector2(m) * M


func _center(m: Vector2i) -> Vector3:
	var c: Vector2 = _center2(m)
	return Vector3(c.x, 0.0, c.y)


## Dom docelowy: dwa sąsiednie moduły przy tej samej ulicy (dom + podwórko), daleko od Siedziby.
func _pick_target() -> void:
	var options: Array[Vector2i] = []
	var hq_center := Vector2(10, 5)
	var keys: Array = _type.keys()
	keys.sort()
	for m: Vector2i in keys:
		if _type[m] != BUILDING:
			continue
		var d: int = _face[m]
		var other: Vector2i = m + (Vector2i(1, 0) if d in [N, S] else Vector2i(0, 1))  # sąsiad wzdłuż ulicy
		if _type.get(other, EMPTY) != BUILDING or _face.get(other, 0) != d:
			continue
		if _center2(m).distance_to(hq_center) < 110.0:
			continue
		options.append(m)
	if options.is_empty():
		push_warning("WorldGenerator: brak miejsca na dom docelowy")
		return
	var m: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
	var d: int = _face[m]
	var other: Vector2i = m + (Vector2i(1, 0) if d in [N, S] else Vector2i(0, 1))
	_type[m] = TARGET
	_type[other] = TARGET
	_face[other] = d
	# Dom stoi na pierwszym module, podwórko (miejsce na auto) na drugim.
	_build_target_house(m, other, d)


# --- 4. Budowa ---------------------------------------------------------------------------

func _build_ground() -> void:
	var lo: Vector2 = _center2(Vector2i(_amin - 3, _bmin - 3))
	var hi: Vector2 = _center2(Vector2i(_amax + 3, _bmax + 3))
	var size := Vector3(hi.x - lo.x, 1.0, hi.y - lo.y)
	var center := Vector3((lo.x + hi.x) * 0.5, -0.5, (lo.y + hi.y) * 0.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	_collision.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(Color(0.33, 0.5, 0.29))
	mesh.mesh = bm
	mesh.position = center - Vector3(0, 0.012, 0)  # pod trawą Siedziby (bez migotania)
	add_child(mesh)


func _build_roads() -> void:
	var y: float = -(0.073 * S_CITY * ROAD_FLAT) + 0.004  # asfalt 4 mm nad ziemią
	var keys: Array = _road_mask.keys()
	keys.sort()
	for m: Vector2i in keys:
		var mask: int = _road_mask[m]
		var tile: String
		var base: int
		match _bits(mask):
			4:
				tile = "road_junction"
				base = N | E | S | W
			3:
				tile = "road_tsplit"
				base = N | E | S
			2:
				if mask == (N | S) or mask == (E | W):
					tile = "road_straight"
					base = N | S
					if _is_crossing_spot(m) and _rng.randf() < 0.5:
						tile = "road_straight_crossing"
				else:
					tile = "road_corner"
					base = E | S
			_:
				tile = "road_straight"
				base = N | S
		var rot: float = _rotation_for(base, mask)
		var t := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(S_CITY, S_CITY * ROAD_FLAT, S_CITY)),
				_center(m) + Vector3(0, y, 0))
		_add(CITY % tile, t)
		if tile == "road_straight":
			_decorate_straight(m, mask)


## Kafle tuż przy skrzyżowaniu dostają czasem pasy dla pieszych.
func _is_crossing_spot(m: Vector2i) -> bool:
	for d: int in DIRS:
		if _bits(_road_mask.get(m + DIRS[d], 0)) >= 3:
			return true
	return false


## Latarnie i zaparkowane auta na prostych odcinkach.
func _decorate_straight(m: Vector2i, mask: int) -> void:
	var along_x: bool = mask == (E | W)
	var perp := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var c: Vector3 = _center(m)
	if _near_hq_entrance(c) or _type.get(m + (Vector2i(0, 1) if along_x else Vector2i(1, 0)), EMPTY) == TARGET \
			or _type.get(m - (Vector2i(0, 1) if along_x else Vector2i(1, 0)), EMPTY) == TARGET:
		return
	if _rng.randf() < 0.4:
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var pos: Vector3 = c + perp * (3.8 * side)
		var to_road: Vector3 = -perp * side
		var rot: float = atan2(to_road.z, -to_road.x)  # ramię latarni = lokalne -X
		_add(CITY % "streetlight", Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * S_CITY), pos))
		_box_collider(pos + Vector3(0, 2.0, 0), Vector3(0.25, 4.0, 0.25), 0.0)
	if _rng.randf() < 0.1:
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var pos: Vector3 = c + perp * (2.0 * side) + Vector3(0, 0.27, 0)
		var heading: float = (PI * 0.5 if along_x else 0.0) + (PI if _rng.randf() < 0.5 else 0.0)
		_add(CITY % CARS[_rng.randi_range(0, CARS.size() - 1)], Transform3D(Basis(Vector3.UP, heading).scaled(Vector3.ONE * S_CITY), pos))
		_box_collider(pos + Vector3(0, 0.6, 0), Vector3(1.9, 1.5, 4.2), heading)


func _near_hq_entrance(p: Vector3) -> bool:
	return absf(p.x - ORIGIN.x) < 1.0 and p.z > DRIVEWAY_Z.x - 12.0 and p.z < DRIVEWAY_Z.y + 12.0


func _build_blocks() -> void:
	var keys: Array = _type.keys()
	keys.sort()
	for m: Vector2i in keys:
		match _type[m]:
			BUILDING:
				_place_building(m, BUILDINGS[_rng.randi_range(0, BUILDINGS.size() - 1)])
			BOUNDARY:
				_place_building(m, TALL[_rng.randi_range(0, TALL.size() - 1)])
			PARK:
				_place_park(m)


func _place_building(m: Vector2i, letter: String) -> void:
	var d: int = _face.get(m, S)
	var dir: Vector2i = DIRS[d]
	var rot: float = atan2(float(dir.x), float(dir.y))  # front budynku = lokalne +Z
	var basis := Basis(Vector3.UP, rot)
	var pos: Vector3 = _center(m) + Vector3(0, -BASE_SINK + 0.006, 0)
	_add(CITY % ("building_" + letter), Transform3D(basis.scaled(Vector3.ONE * S_CITY), pos))
	var box: AABB = _model_aabb(CITY % ("building_" + letter + "_withoutBase"))
	var size := box.size * S_CITY
	var local_center := box.get_center() * S_CITY
	_box_collider(_center(m) + basis * Vector3(local_center.x, 0, local_center.z) + Vector3(0, size.y * 0.5, 0),
			size, rot)


func _place_park(m: Vector2i) -> void:
	var c: Vector3 = _center(m)
	var roll: float = _rng.randf()
	if roll < 0.55:  # kępa drzew
		for k in _rng.randi_range(1, 3):
			var p: Vector3 = c + Vector3(_rng.randf_range(-3.0, 3.0), 0, _rng.randf_range(-3.0, 3.0))
			var s: float = _rng.randf_range(1.3, 1.8)
			_add(NATURE % TREES[_rng.randi_range(0, TREES.size() - 1)],
					Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), p))
			_box_collider(p + Vector3(0, 1.5, 0), Vector3(0.6, 3.0, 0.6), 0.0)
	elif roll < 0.8:  # krzaki i ławka
		for k in _rng.randi_range(2, 4):
			var p: Vector3 = c + Vector3(_rng.randf_range(-3.5, 3.5), 0, _rng.randf_range(-3.5, 3.5))
			_add(NATURE % BUSHES[_rng.randi_range(0, BUSHES.size() - 1)],
					Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 2.0), p))
		_add(CITY % "bench", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * S_CITY), c))
	else:  # mały parking
		_flat_box(c, Vector2(8.6, 8.6), Color(0.27, 0.27, 0.3), 0.004)
		if _rng.randf() < 0.7:
			var heading: float = PI * 0.5 * _rng.randi_range(0, 3)
			var pos: Vector3 = c + Vector3(0, 0.27, 0)
			_add(CITY % CARS[_rng.randi_range(0, CARS.size() - 1)], Transform3D(Basis(Vector3.UP, heading).scaled(Vector3.ONE * S_CITY), pos))
			_box_collider(pos + Vector3(0, 0.6, 0), Vector3(1.9, 1.5, 4.2), heading)


## Płot wokół działki Siedziby z przerwą na wjazd (od strony ulicy przy bramie garażu).
func _build_hq_fence() -> void:
	var r: Rect2 = HQ_RECT
	var wood := Color(0.55, 0.38, 0.22)
	var h: float = 1.6
	var x0: float = r.position.x
	var x1: float = r.end.x
	var z0: float = r.position.y
	var z1: float = r.end.y
	_fence(Vector3(x0, 0, z0), Vector3(x1, 0, z0), h, wood)
	_fence(Vector3(x0, 0, z1), Vector3(x1, 0, z1), h, wood)
	_fence(Vector3(x1, 0, z0), Vector3(x1, 0, z1), h, wood)
	_fence(Vector3(x0, 0, z0), Vector3(x0, 0, DRIVEWAY_Z.x - 0.6), h, wood)
	_fence(Vector3(x0, 0, DRIVEWAY_Z.y + 0.6), Vector3(x0, 0, z1), h, wood)
	# Śmietniki przy wjeździe.
	for z: float in [DRIVEWAY_Z.x - 2.0, DRIVEWAY_Z.y + 2.0]:
		var p := Vector3(x0 + 1.4, 0, z)
		_add(CITY % "dumpster", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * S_CITY * 0.9), p))
		_box_collider(p + Vector3(0, 0.7, 0), Vector3(1.6, 1.4, 2.6), 0.0)


func _fence(a: Vector3, b: Vector3, h: float, color: Color) -> void:
	var length: float = a.distance_to(b)
	var mid: Vector3 = (a + b) * 0.5
	var rot: float = atan2(b.x - a.x, b.z - a.z)
	var basis := Basis(Vector3.UP, rot)
	_box_collider(mid + Vector3(0, h * 0.5, 0), Vector3(0.12, h, length), rot)
	for y: float in [0.45, 1.25]:  # dwie poprzeczki
		_visual_box(mid + Vector3(0, y, 0), Vector3(0.08, 0.14, length), rot, color.darkened(0.15))
	var count: int = int(length / 0.32)
	for k in count:  # sztachety
		var p: Vector3 = a.lerp(b, (k + 0.5) / count)
		_visual_box(p + Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.22), rot, color)


func _build_bounds() -> void:
	var lo: Vector2 = _center2(Vector2i(_amin, _bmin)) - Vector2(M, M) * 0.5
	var hi: Vector2 = _center2(Vector2i(_amax, _bmax)) + Vector2(M, M) * 0.5
	var c := Vector2((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5)
	var w: float = hi.x - lo.x
	var d: float = hi.y - lo.y
	for spec: Array in [[Vector3(lo.x - 1, 15, c.y), Vector3(2, 30, d + 4)], [Vector3(hi.x + 1, 15, c.y), Vector3(2, 30, d + 4)],
			[Vector3(c.x, 15, lo.y - 1), Vector3(w + 4, 30, 2)], [Vector3(c.x, 15, hi.y + 1), Vector3(w + 4, 30, 2)]]:
		_box_collider(spec[0], spec[1], 0.0)


# --- 5. Dom docelowy ------------------------------------------------------------------------

func _build_target_house(house_m: Vector2i, yard_m: Vector2i, d: int) -> void:
	var dir: Vector2i = DIRS[d]
	var rot: float = atan2(float(dir.x), float(dir.y))  # lokalne +Z = do ulicy
	var root := Node3D.new()
	root.name = "TargetHouse"
	root.position = _center(house_m)
	root.rotation.y = rot
	add_child(root)
	target_position = root.position

	var W2: String = "res://assets/models/building/%s.glb"
	var walls: Array = [  # [początek (lokalnie), oś, kafle]  dom 8 x 8 m
		[Vector3(-4, 0, 4), "x", ["wall-window-square", "wall-doorway-wide-square", "wall-window-square"]],
		[Vector3(-4, 0, -4), "x", ["wall", "wall-window-wide-square", "wall"]],
		[Vector3(-4, 0, -4), "z", ["wall", "wall-window-square", "wall-window-square", "wall"]],
		[Vector3(4, 0, -4), "z", ["wall", "wall-window-square", "wall-window-square", "wall"]],
	]
	var n: int = 0
	for run: Array in walls:
		var acc: float = 0.0
		for tile: String in run[2]:
			var length: float = 4.0 if tile.contains("wide") else 2.0
			var prop := StaticProp.new()
			prop.name = "Wall%d" % n
			n += 1
			prop.model = load(W2 % tile)
			prop.model_scale = 1.0
			if run[1] == "x":
				prop.position = run[0] + Vector3(acc + length * 0.5, 0, 0)
				prop.rotation.y = PI * 0.5
			else:
				prop.position = run[0] + Vector3(0, 0, acc + length * 0.5)
			root.add_child(prop)
			acc += length
	var floor_mat := _mat(Color(0.72, 0.55, 0.4))
	_local_box(root, Vector3(0, 0.01, 0), Vector3(8, 0.02, 8), floor_mat, false)                 # podłoga
	_local_box(root, Vector3(0, 2.55, 0), Vector3(8.6, 0.25, 8.6), _mat(Color(0.62, 0.3, 0.25)), true)  # dach
	_local_box(root, Vector3(0, 2.41, 0), Vector3(7.9, 0.02, 7.9), _mat(Color(0.95, 0.94, 0.9)), false)
	for corner: Vector3 in [Vector3(-4, 1.2, -4), Vector3(4, 1.2, -4), Vector3(-4, 1.2, 4), Vector3(4, 1.2, 4)]:
		_local_box(root, corner, Vector3(0.24, 2.4, 0.24), _mat(Color(0.93, 0.92, 0.95)), true)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.1, 0)
	light.omni_range = 7.0
	light.light_energy = 1.3
	light.light_color = Color(1, 0.9, 0.75)
	root.add_child(light)

	# Podwórko: utwardzony plac na auto + ścieżka do drzwi.
	var yard: Vector3 = _center(yard_m)
	_flat_box(yard, Vector2(8.8, 8.8), Color(0.62, 0.6, 0.57), 0.006)
	var path_size := Vector2(4.2, 0.9) if d in [N, S] else Vector2(0.9, 4.2)  # ścieżka przed drzwiami
	_flat_box(root.position + Basis(Vector3.UP, rot) * Vector3(0, 0, 4.4), path_size, Color(0.62, 0.6, 0.57), 0.006)
	var label := Label3D.new()
	label.text = "VAN PARKING"
	label.pixel_size = 0.012
	label.modulate = Color(1.0, 0.85, 0.2, 0.9)
	label.rotation = Vector3(-PI / 2.0, rot, 0.0)
	label.position = yard + Vector3(0, 0.02, 0)
	add_child(label)

	_build_beacon(root.position)
	_build_target_items(root)


## Słup światła nad celem - widać go zza budynków z całego miasta.
func _build_beacon(at: Vector3) -> void:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.8
	cyl.height = 70.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.65, 0.2, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material = mat
	beam.mesh = cyl
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = at + Vector3(0, 37.0, 0)
	add_child(beam)
	var label := Label3D.new()
	label.text = "ZLECENIE"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 40
	label.outline_size = 12
	label.modulate = Color(1.0, 0.78, 0.3)
	label.position = at + Vector3(0, 6.0, 0)
	add_child(label)


func _build_target_items(root: Node3D) -> void:
	var items := Node3D.new()
	items.name = "Items"
	root.add_child(items)
	var scene: PackedScene = load("res://scenes/items/grabbable.tscn")
	var F: String = "res://assets/models/furniture/%s.glb"
	# [nazwa węzła, model, nazwa, masa, wartość, wytrzymałość, pozycja lokalna, obrót]
	var table: Array = [
		["Kanapa", "loungeSofa", "Kanapa", 40.0, 500.0, 120.0, Vector3(-1.8, 0.5, -3.2), 0.0],
		["Fotel", "loungeChair", "Fotel", 15.0, 300.0, 100.0, Vector3(2.6, 0.5, -3.0), 0.0],
		["Stolik", "tableCoffee", "Stolik kawowy", 10.0, 150.0, 100.0, Vector3(-1.8, 0.3, -1.6), 0.0],
		["Lodowka", "kitchenFridge", "Lodówka", 60.0, 800.0, 80.0, Vector3(3.3, 0.95, 1.0), -PI * 0.5],
		["Telewizor", "televisionModern", "Telewizor", 12.0, 600.0, 40.0, Vector3(0.5, 0.5, 2.5), PI],
		["Lampa", "lampSquareFloor", "Lampa", 4.0, 120.0, 50.0, Vector3(-3.4, 0.9, 3.2), 0.0],
		["Karton1", "cardboardBoxClosed", "Karton", 5.0, 80.0, 100.0, Vector3(-3.0, 0.35, 0.5), 0.0],
		["Karton2", "cardboardBoxClosed", "Karton", 5.0, 80.0, 100.0, Vector3(-2.4, 0.35, 0.5), 0.0],
		["Karton3", "cardboardBoxClosed", "Karton (szkło)", 5.0, 250.0, 25.0, Vector3(-2.7, 0.35, 1.2), 0.0],
	]
	for row: Array in table:
		var item: Grabbable = scene.instantiate()
		item.name = row[0]
		item.model = load(F % row[1])
		item.item_name = row[2]
		item.mass = row[3]
		item.value = row[4]
		item.durability = row[5]
		if row[0] == "Karton3":
			item.label_text = "SZKŁO"
		item.position = row[6]
		item.rotation.y = row[7]
		items.add_child(item)
		target_items.append(item)
	# Host: przedmioty dodane w trakcie gry trzeba "pokazać" graczom, którzy już są na poziomie.
	if multiplayer.is_server():
		for item in target_items:
			for id: int in Net.ready_peers:
				if id != 1:
					item.net_sync.set_visibility_for(id, true)


# --- Pomocnicze ---------------------------------------------------------------------------

func _bits(mask: int) -> int:
	return int(mask & N > 0) + int(mask & E > 0) + int(mask & S > 0) + int(mask & W > 0)


## Obrót (wielokrotność 90°), który zamienia wyloty kafla `base` na `mask`.
## Obrót o +90° wokół Y: S -> E, E -> N, N -> W, W -> S.
func _rotation_for(base: int, mask: int) -> float:
	var current: int = base
	for r in 4:
		if current == mask:
			return r * PI * 0.5
		var next: int = 0
		if current & S: next |= E
		if current & E: next |= N
		if current & N: next |= W
		if current & W: next |= S
		current = next
	return 0.0


func _add(path: String, t: Transform3D) -> void:
	if not _batches.has(path):
		_batches[path] = []
	(_batches[path] as Array).append(t)


## Jeden MultiMeshInstance3D na każdą siatkę modelu - tysiące budynków bez tysięcy węzłów.
func _flush_batches() -> void:
	var paths: Array = _batches.keys()
	paths.sort()
	for path: String in paths:
		if not ResourceLoader.exists(path):
			push_warning("WorldGenerator: brak modelu %s" % path)
			continue
		var model: Node3D = (load(path) as PackedScene).instantiate()
		var transforms: Array = _batches[path]
		for mi: MeshInstance3D in _meshes(model):
			var local: Transform3D = _relative(mi, model)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mi.mesh
			mm.instance_count = transforms.size()
			for k in transforms.size():
				mm.set_instance_transform(k, (transforms[k] as Transform3D) * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if mi.material_override != null:
				mmi.material_override = mi.material_override
			add_child(mmi)
		model.free()
	_batches.clear()


var _aabb_cache: Dictionary = {}


func _model_aabb(path: String) -> AABB:
	if _aabb_cache.has(path):
		return _aabb_cache[path]
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var box := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(model):
		var b: AABB = _relative(mi, model) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	model.free()
	_aabb_cache[path] = box
	return box


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _relative(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _box_collider(center: Vector3, size: Vector3, rot_y: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(Basis(Vector3.UP, rot_y), center)
	_collision.add_child(shape)


var _mat_cache: Dictionary = {}


func _mat(color: Color) -> StandardMaterial3D:
	if not _mat_cache.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mat_cache[color] = m
	return _mat_cache[color]


func _visual_box(center: Vector3, size: Vector3, rot_y: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color)
	mi.mesh = bm
	mi.transform = Transform3D(Basis(Vector3.UP, rot_y), center)
	add_child(mi)


func _flat_box(center: Vector3, size: Vector2, color: Color, top: float) -> void:
	_visual_box(Vector3(center.x, top - 0.01, center.z), Vector3(size.x, 0.02, size.y), 0.0, color)


func _local_box(parent: Node3D, center: Vector3, size: Vector3, material: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	mi.position = center
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.position = center
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		parent.add_child(body)
