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

const SUB: String = "res://assets/models/suburban/%s.glb"
const COM: String = "res://assets/models/commercial/%s.glb"
const IND: String = "res://assets/models/industrial/%s.glb"

## Dzielnice. Każdy moduł dostaje ocenę dla każdej z nich (odległość od "centrum" dzielnicy
## + płynny szum) i wygrywa najlepsza - granice są nieregularne, a w pasie przejściowym
## budynki obu dzielnic mieszają się (drobny szum na poziomie modułu).
enum { SUBURBAN, COMMERCIAL, INDUSTRIAL }
const CATALOG: Dictionary = {
	SUBURBAN: {"path": SUB, "min_scale": 6.0, "max_scale": 8.5,
		"models": ["building-type-a", "building-type-b", "building-type-c", "building-type-d", "building-type-e",
			"building-type-g", "building-type-h", "building-type-i", "building-type-j", "building-type-k", "building-type-l",
			"building-type-o", "building-type-p", "building-type-q", "building-type-r", "building-type-s", "building-type-u"]},
	COMMERCIAL: {"path": COM, "min_scale": 6.0, "max_scale": 9.5,
		"models": ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g",
			"building-h", "building-i", "building-j", "building-k", "building-l", "building-m", "building-skyscraper-a",
			"building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-e"],
		"tall": ["building-m", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-d", "building-skyscraper-e"]},
	INDUSTRIAL: {"path": IND, "min_scale": 4.8, "max_scale": 7.5,
		"models": ["building-a", "building-b", "building-d", "building-e", "building-g", "building-h", "building-i",
			"building-j", "building-k", "building-m", "building-o", "building-p", "building-r", "building-s", "building-t"],
		"tall": ["building-a", "building-b", "building-e", "building-f", "building-l", "building-m"]},
}
const PAIR_CHANCE: Dictionary = {SUBURBAN: 0.55, COMMERCIAL: 0.3, INDUSTRIAL: 0.55}
## Szansa, że działka zostanie pusta (ogród / parking / plac) - przerywa monotonne pierzeje.
const VACANT_CHANCE: Dictionary = {SUBURBAN: 0.07, COMMERCIAL: 0.06, INDUSTRIAL: 0.1}
## Alternatywne palety kolorów z paczek Kenney (te same modele, inne dachy i elewacje).
const VARIATIONS: Dictionary = {
	"suburban": ["variation-a", "variation-b", "variation-c"],
	"commercial": ["variation-a", "variation-b"],
	"industrial": ["variation-a", "variation-b", "variation-c"],
}
## [cofnięcie od ulicy: min, max udziału wolnego miejsca], przesunięcie w bok, maks. obrót [°]
const PLACEMENT: Dictionary = {
	SUBURBAN: [0.25, 1.0, 0.6, 4.0],
	COMMERCIAL: [0.0, 0.25, 0.3, 1.2],
	INDUSTRIAL: [0.1, 0.8, 0.6, 2.5],
}
const PAVING: Dictionary = {COMMERCIAL: Color(0.68, 0.68, 0.7), INDUSTRIAL: Color(0.5, 0.5, 0.52)}
const HQ_CENTER: Vector2 = Vector2(10, 5)

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
var _district: Dictionary = {}   ## Vector2i(moduł) -> dzielnica
var _edge: CityEdge              ## port / obwodnica / wzgórza na krawędzi miasta
var _recent: Dictionary = {}     ## pierzeja (ulica + strona) -> ostatnie modele [ścieżka|wariant]
var _downtown: Vector2
var _industry: Vector2
var _noise: Array[FastNoiseLite] = []
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
	_setup_districts()
	_edge = CityEdge.new(self)
	_edge.prepare()  # typy krawędzi + zamknięte wyloty ulic (przed budową dróg)
	_pick_target()

	_build_ground()
	_build_roads()
	_build_blocks()
	_build_hq_fence()
	_build_bounds()
	_edge.build()
	_flush_batches()
	_apply_atmosphere()
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


func _setup_districts() -> void:
	var a: float = _rng.randf() * TAU
	_downtown = HQ_CENTER + Vector2.from_angle(a) * _rng.randf_range(70.0, 140.0)
	_industry = HQ_CENTER + Vector2.from_angle(a + PI + _rng.randf_range(-0.9, 0.9)) * _rng.randf_range(160.0, 220.0)
	for k in 4:
		var n := FastNoiseLite.new()
		n.seed = _rng.randi()
		n.frequency = 0.012 if k < 3 else 0.08  # 3 płynne pola + drobny szum przejść
		_noise.append(n)


func _district_of(m: Vector2i) -> int:
	if not _district.has(m):
		_district[m] = _district_at(_center2(m))
	return _district[m]


## Dzielnica w dowolnym punkcie (także w panoramie za murem - tło pasuje do miasta przed nim).
func _district_at(p: Vector2) -> int:
	var scores: Array[float] = [
		0.55 + _noise[0].get_noise_2dv(p) * 0.3,
		1.25 * exp(-pow(p.distance_to(_downtown) / 150.0, 2.0)) + _noise[1].get_noise_2dv(p) * 0.3,
		1.2 * exp(-pow(p.distance_to(_industry) / 125.0, 2.0)) + _noise[2].get_noise_2dv(p) * 0.3,
	]
	# Pas przejściowy: drobny szum przemiesza budynki dwóch dzielnic na ich styku.
	var fine: float = _noise[3].get_noise_2dv(p) * 0.12
	scores[COMMERCIAL] += fine
	scores[INDUSTRIAL] -= fine
	var best: int = SUBURBAN
	for k in 3:
		if scores[k] > scores[best]:
			best = k
	return best


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


## Dom docelowy: dwa sąsiednie moduły przy tej samej ulicy, daleko od Siedziby,
## najchętniej na przedmieściu (to dom jednorodzinny).
func _pick_target() -> void:
	var suburban: Array[Vector2i] = []
	var any: Array[Vector2i] = []
	var keys: Array = _type.keys()
	keys.sort()
	for m: Vector2i in keys:
		if _type[m] != BUILDING:
			continue
		var d: int = _face[m]
		var other: Vector2i = m + (Vector2i(1, 0) if d in [N, S] else Vector2i(0, 1))  # sąsiad wzdłuż ulicy
		if _type.get(other, EMPTY) != BUILDING or _face.get(other, 0) != d:
			continue
		if _center2(m).distance_to(HQ_CENTER) < 110.0:
			continue
		any.append(m)
		if _district_of(m) == SUBURBAN and _district_of(other) == SUBURBAN:
			suburban.append(m)
	var options: Array[Vector2i] = suburban if not suburban.is_empty() else any
	if options.is_empty():
		push_warning("WorldGenerator: brak miejsca na dom docelowy")
		return
	var m: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
	var d: int = _face[m]
	var other: Vector2i = m + (Vector2i(1, 0) if d in [N, S] else Vector2i(0, 1))
	_type[m] = TARGET
	_type[other] = TARGET
	_face[other] = d
	_build_target_house((_center(m) + _center(other)) * 0.5, d)


# --- 4. Budowa ---------------------------------------------------------------------------

## Ziemia tylko pod miastem - dookoła jest teren z CityEdge (wzgórza, woda, nabrzeże).
func _build_ground() -> void:
	var r: Rect2 = _city_rect()
	var size := Vector3(r.size.x, 1.0, r.size.y)
	var center := Vector3(r.get_center().x, -0.5, r.get_center().y)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size + Vector3(4, 0, 4)
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
		if tile == "road_straight" and not _edge.stubs.has(m):
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
	var used: Dictionary = {}
	var keys: Array = _type.keys()
	keys.sort()
	for m: Vector2i in keys:
		if used.has(m):
			continue
		match _type[m]:
			BUILDING:
				var district: int = _district_of(m)
				var d: int = _face[m]
				var along := Vector2i(1, 0) if d in [N, S] else Vector2i(0, 1)
				var other: Vector2i = m + along
				if _rng.randf() < VACANT_CHANCE[district]:
					_place_yard(m, district)  # pusta działka: ogród / parking / plac
				# Działka na dwa moduły wzdłuż ulicy (większe domy, hale, biurowce).
				elif _rng.randf() < PAIR_CHANCE[district] and not used.has(other) \
						and _type.get(other, EMPTY) == BUILDING and _face.get(other, 0) == d \
						and _district_of(other) == district:
					used[other] = true
					_place_lot((_center(m) + _center(other)) * 0.5, d, 2, district, false, _street_key(m, d))
				else:
					_place_lot(_center(m), d, 1, district, false, _street_key(m, d))
			BOUNDARY:
				_edge.build_module(m)
			PARK:
				_place_yard(m, _district_of(m))
		used[m] = true


## Pierzeja = ulica, przy której stoi działka, i strona ulicy (żeby sąsiedzi się nie powtarzali).
func _street_key(m: Vector2i, d: int) -> String:
	var road: Vector2i = m + DIRS[d]
	return "%d:%d" % [d, road.y if d in [N, S] else road.x]


## Budynek na działce: `width` modułów wzdłuż ulicy, front w stronę `d`.
func _place_lot(center: Vector3, d: int, width: int, district: int, boundary: bool, street: String = "") -> void:
	var dir: Vector2i = DIRS[d]
	var lot := Vector2(M * width - 1.2, M - 0.6)
	if district == COMMERCIAL or district == INDUSTRIAL:
		_flat_box(center, Vector2(M * width, M) if d in [N, S] else Vector2(M, M * width),
				PAVING[district], 0.012)
	# Stare kamienice KayKit (z podstawą 9 x 9 m) w śródmieściu i na obrzeżu.
	var kaykit_chance: float = 0.3 if district == COMMERCIAL else 0.0
	if boundary:
		kaykit_chance = [0.45, 0.35, 0.15][district]
	if width == 1 and _rng.randf() < kaykit_chance:
		var letter: String = BUILDINGS[_rng.randi_range(0, BUILDINGS.size() - 1)]
		var recent_k: Array = _recent.get(street, [])
		if ("kaykit|" + letter) in recent_k:
			letter = BUILDINGS[(BUILDINGS.find(letter) + _rng.randi_range(1, BUILDINGS.size() - 1)) % BUILDINGS.size()]
		recent_k.append("kaykit|" + letter)
		_recent[street] = recent_k.slice(-2)
		_place_kaykit(center, d, letter)
		return
	# Na obrzeżu przedmieść: niskie kamienice i domy z paczki Commercial (zwarta, ale różna pierzeja).
	var pick_district: int = COMMERCIAL if boundary and district == SUBURBAN else district
	var choice: Array = _pick_model(pick_district, lot, boundary and district != SUBURBAN, _recent.get(street, []))
	if choice.is_empty():
		return
	var path: String = choice[0]
	var s: float = choice[1]
	var variant: int = choice[2]
	var recent: Array = _recent.get(street, [])
	recent.append("%s|%d" % [path, variant])
	_recent[street] = recent.slice(-2)

	# Nie od linijki: cofnięcie od ulicy, przesunięcie w bok i lekki obrót w granicach działki.
	var rule: Array = PLACEMENT[district] if not boundary else [0.0, 0.25, 0.4, 2.0]
	var box: AABB = _model_aabb(path)
	var size: Vector3 = box.size * s
	var to_road := Vector3(dir.x, 0, dir.y)
	var along := Vector3(-to_road.z, 0, to_road.x)
	var slack_depth: float = maxf(lot.y - size.z, 0.0)
	var slack_side: float = maxf(lot.x - size.x, 0.0)
	var setback: float = slack_depth * _rng.randf_range(rule[0], rule[1])
	var place: Vector3 = center + to_road * (slack_depth * 0.5 - setback) \
			+ along * slack_side * 0.5 * rule[2] * _rng.randf_range(-1.0, 1.0)
	var yaw: float = deg_to_rad(rule[3]) * _rng.randf_range(-1.0, 1.0)
	var rot: float = atan2(-float(dir.x), -float(dir.y)) + yaw  # front modeli Kenney = lokalne -Z
	var basis := Basis(Vector3.UP, rot)
	var c := box.get_center()
	var pos: Vector3 = place - basis * Vector3(c.x * s, 0.0, c.z * s) + Vector3(0, 0.012, 0)
	_add(path, Transform3D(basis.scaled(Vector3.ONE * s), pos), variant)
	_box_collider(place + Vector3(0, size.y * 0.5, 0), size, rot)
	if district == INDUSTRIAL and (boundary or _rng.randf() < 0.3):
		# Komin za halą - charakterystyczna sylwetka dzielnicy przemysłowej.
		var back: Vector3 = center - to_road * (lot.y * 0.5 - 1.2) + along * lot.x * 0.3 * (1 if _rng.randf() < 0.5 else -1)
		var ch: String = IND % ["chimney-medium", "chimney-basic", "chimney-small"][_rng.randi_range(0, 2)]
		var hs: float = _rng.randf_range(5.5, 8.0)
		_add(ch, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * hs), back), _rng.randi_range(0, 3))
		_box_collider(back + Vector3(0, 4, 0), Vector3(1.5, 8, 1.5), 0.0)
	if district == SUBURBAN and not boundary:
		_suburban_garden(center, d, lot, setback)


func _place_kaykit(center: Vector3, d: int, letter: String) -> void:
	var dir: Vector2i = DIRS[d]
	var rot: float = atan2(float(dir.x), float(dir.y))  # front KayKit = lokalne +Z
	var basis := Basis(Vector3.UP, rot)
	# Różna wysokość kondygnacji: ta sama podstawa 9 x 9 m, budynek od 85% do 120% wysokości.
	var tall: float = _rng.randf_range(0.85, 1.2)
	_add(CITY % ("building_" + letter), Transform3D(basis.scaled(Vector3(S_CITY, S_CITY * tall, S_CITY)), center + Vector3(0, -BASE_SINK * tall + 0.006, 0)))
	var box: AABB = _model_aabb(CITY % ("building_" + letter + "_withoutBase"))
	var lc := box.get_center() * S_CITY
	var h: float = box.size.y * S_CITY * tall
	_box_collider(center + basis * Vector3(lc.x, 0, lc.z) + Vector3(0, h * 0.5, 0), Vector3(box.size.x * S_CITY, h, box.size.z * S_CITY), rot)


## Losuje model danej dzielnicy, który zmieści się na działce w rozsądnej skali.
## Zwraca [ścieżka, skala] albo [].
func _pick_model(district: int, lot: Vector2, boundary: bool, avoid: Array = []) -> Array:
	var spec: Dictionary = CATALOG[district]
	var names: Array = spec["tall"] if boundary and spec.has("tall") else spec["models"]
	var options: Array = []
	for n: String in names:
		var path: String = spec["path"] % n
		var size: Vector3 = _model_aabb(path).size
		var fit: float = minf(spec["max_scale"], minf(lot.x / size.x, lot.y / size.z))
		if fit >= spec["min_scale"] * 0.85:
			options.append([path, fit])
	if options.is_empty():
		return []
	var kit: String = _kit_of(options[0][0])
	var variants: int = 1 + (VARIATIONS[kit] as Array).size() if VARIATIONS.has(kit) else 1
	# Kilka prób, żeby nie powtórzyć modelu ani koloru dwóch ostatnich sąsiadów z pierzei.
	for attempt in 6:
		var pick: Array = options[_rng.randi_range(0, options.size() - 1)]
		var variant: int = _rng.randi_range(0, variants - 1)
		var same_model: bool = false
		for a: String in avoid:
			if a.begins_with(pick[0] + "|"):
				same_model = true
		if same_model and attempt < 5:
			continue
		var fit: float = pick[1]
		var scale: float = _rng.randf_range(maxf(spec["min_scale"] * 0.85, fit * 0.82), fit)
		return [pick[0], scale, variant]
	return []


func _kit_of(path: String) -> String:
	for kit: String in VARIATIONS:
		if path.contains("/" + kit + "/"):
			return kit
	return ""


## Ogródek przed i za domem: płotek, drzewka, donice, ścieżka do drzwi.
func _suburban_garden(center: Vector3, d: int, lot: Vector2, setback: float) -> void:
	var dir: Vector2i = DIRS[d]
	var to_road := Vector3(dir.x, 0, dir.y)
	var along := Vector3(-to_road.z, 0, to_road.x)
	var rot: float = atan2(-float(dir.x), -float(dir.y))
	var tree_side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	if setback >= 5.4 and _rng.randf() < 0.35:
		# Podjazd przed domem z autem (po przeciwnej stronie niż drzewko).
		var drive: Vector3 = center + to_road * (lot.y * 0.5 - setback * 0.5) - along * tree_side * lot.x * 0.28
		_flat_box(drive, Vector2(3.0, setback) if d in [N, S] else Vector2(setback, 3.0), Color(0.6, 0.59, 0.56), 0.014)
		var heading: float = atan2(to_road.x, to_road.z) + (PI if _rng.randf() < 0.5 else 0.0)
		var car_pos: Vector3 = drive + Vector3(0, 0.29, 0)
		_add(CITY % CARS[_rng.randi_range(0, CARS.size() - 1)], Transform3D(Basis(Vector3.UP, heading).scaled(Vector3.ONE * S_CITY), car_pos))
		_box_collider(car_pos + Vector3(0, 0.6, 0), Vector3(1.9, 1.5, 4.2), heading)
	if _rng.randf() < 0.7:
		var p: Vector3 = center + along * (lot.x * 0.5 - 0.8) * tree_side + to_road * (lot.y * 0.5 - 0.7)
		_add(SUB % ("tree-large" if _rng.randf() < 0.5 else "tree-small"), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 8.0), p))
		_box_collider(p + Vector3(0, 1.5, 0), Vector3(0.5, 3.0, 0.5), 0.0)
	if _rng.randf() < 0.5:
		var p2: Vector3 = center - along * (lot.x * 0.5 - 1.2) * (1 if _rng.randf() < 0.5 else -1) + to_road * (lot.y * 0.5 - 0.5)
		_add(SUB % "planter", Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * 4.0), p2))
	if setback > 1.6 and _rng.randf() < 0.35:
		# Niski żywopłot wzdłuż chodnika z przerwą na wejście (bez kolizji - to tylko krzaki).
		var n: int = int(lot.x / 0.9)
		for k in n:
			var t: float = (k + 0.5) / n - 0.5
			if absf(t) < 0.12:
				continue
			var p3: Vector3 = center + to_road * (lot.y * 0.5 - 0.3) + along * t * lot.x
			_add(NATURE % "Bush_2_A_Color1", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(1.6, 2.0)), p3))


## Wnętrze kwartału zależnie od dzielnicy.
func _place_yard(m: Vector2i, district: int) -> void:
	var c: Vector3 = _center(m)
	match district:
		INDUSTRIAL:
			_flat_box(c, Vector2(M, M), PAVING[INDUSTRIAL], 0.012)
			var roll: float = _rng.randf()
			if roll < 0.5:  # kontenery w rzędach
				var rot: float = PI * 0.5 * _rng.randi_range(0, 1)
				for k in _rng.randi_range(1, 3):
					var off := Vector3(-2.6 + k * 2.6, 0, 0).rotated(Vector3.UP, rot)
					var stack: int = _rng.randi_range(1, 2)
					for level in stack:
						var name: String = "shipping-container-" + ["a", "b", "c"][_rng.randi_range(0, 2)]
						_add(IND % name, Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * 6.0), c + off + Vector3(0, level * 2.1, 0)))
					_box_collider(c + off + Vector3(0, stack * 1.05, 0), Vector3(2.3, stack * 2.1, 5.0), rot)
			elif roll < 0.8:
				var name: String = ["detail-tank-large", "detail-tank", "water-tower"][_rng.randi_range(0, 2)]
				var s: float = 5.0 if name == "detail-tank-large" else 6.0
				_add(IND % name, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), c))
				var b: AABB = _model_aabb(IND % name)
				_box_collider(c + Vector3(0, b.size.y * s * 0.5, 0), Vector3(b.size.x, b.size.y, b.size.z) * s * 0.8, 0.0)
			else:
				_add(IND % "solar-panel-landscape-group", Transform3D(Basis(Vector3.UP, PI * 0.5 * _rng.randi_range(0, 3)).scaled(Vector3.ONE * 5.0), c))
		COMMERCIAL:
			_flat_box(c, Vector2(M, M), PAVING[COMMERCIAL], 0.012)
			var roll: float = _rng.randf()
			if roll < 0.3:  # parking: rząd miejsc z kilkoma autami
				var along_x: bool = _rng.randf() < 0.5
				var lane := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
				var nose := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
				for k in 4:
					var spot: Vector3 = c + lane * (-3.45 + k * 2.3)
					_visual_box(spot + lane * 1.15 + Vector3(0, 0.013, 0), Vector3(0.12, 0.02, 4.6) if along_x else Vector3(4.6, 0.02, 0.12), 0.0, Color(0.92, 0.92, 0.9))
					if _rng.randf() < 0.7:
						var heading: float = atan2(nose.x, nose.z) + (PI if _rng.randf() < 0.5 else 0.0)
						var cp: Vector3 = spot + Vector3(0, 0.29, 0)
						_add(CITY % CARS[_rng.randi_range(0, CARS.size() - 1)], Transform3D(Basis(Vector3.UP, heading).scaled(Vector3.ONE * S_CITY), cp))
						_box_collider(cp + Vector3(0, 0.6, 0), Vector3(1.9, 1.5, 4.2), heading)
			elif roll < 0.6:  # ogródek kawiarni
				for k in _rng.randi_range(2, 3):
					var p: Vector3 = c + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
					_add(COM % ("detail-parasol-" + ["a", "b"][_rng.randi_range(0, 1)]), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 6.0), p))
			else:
				for k in 2:
					var p2: Vector3 = c + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
					_add(NATURE % TREES[_rng.randi_range(0, TREES.size() - 1)], Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 1.4), p2))
					_box_collider(p2 + Vector3(0, 1.5, 0), Vector3(0.6, 3.0, 0.6), 0.0)
				_add(CITY % "bench", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * S_CITY), c))
		_:
			_place_park(m)


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
	else:  # skwer: krzewy wokół ławki i niskie drzewko
		for k in _rng.randi_range(3, 5):
			var p3: Vector3 = c + Vector3(_rng.randf_range(-3.8, 3.8), 0, _rng.randf_range(-3.8, 3.8))
			_add(NATURE % BUSHES[_rng.randi_range(0, BUSHES.size() - 1)],
					Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 2.2), p3))
		_add(CITY % "bench", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * S_CITY), c))


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


# --- Horyzont: patrz CityEdge (port, obwodnica, wzgórza) -------------------------------

## Mgła z perspektywą powietrzną i dopasowane niebo - kraniec mapy znika w oddali.
func _apply_atmosphere() -> void:
	var env_node: WorldEnvironment = null
	for c in get_parent().get_children():
		if c is WorldEnvironment:
			env_node = c
	if env_node == null or env_node.environment == null:
		return
	var env: Environment = env_node.environment
	var haze := Color(0.74, 0.8, 0.86)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = haze
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_horizon_color = haze
		sky.ground_horizon_color = haze
		sky.ground_bottom_color = Color(0.5, 0.5, 0.48)  # neutralny: to światło odbija się na sufity


# --- 5. Dom docelowy ------------------------------------------------------------------------

func _build_target_house(center: Vector3, d: int) -> void:
	var dir: Vector2i = DIRS[d]
	var house := TargetHouse.new()
	house.name = "TargetHouse"
	house.position = center
	house.rotation.y = atan2(-float(dir.x), -float(dir.y))  # front domu (-Z) do ulicy
	add_child(house)
	house.build()
	target_position = center
	target_items = house.items
	# Ścieżka od chodnika do drzwi, trawnik przed domem.
	var to_road := Vector3(dir.x, 0, dir.y)
	var path_size := Vector2(1.6, 1.2) if d in [N, S] else Vector2(1.2, 1.6)
	_flat_box(center + to_road * 4.0, path_size, Color(0.66, 0.63, 0.58), 0.015)
	_build_beacon(center)
	# Host: przedmioty dodane w trakcie gry trzeba "pokazać" graczom, którzy już są na poziomie.
	if multiplayer.is_server():
		for item in target_items:
			for id: int in Net.ready_peers:
				if id != 1:
					item.net_sync.set_visibility_for(id, true)


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
	beam.position = at + Vector3(0, 41.0, 0)  # zaczyna się 6 m nad ziemią - nad dachem, nie w salonie
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


## Modele grupujemy w kwadraty (CHUNK m), a nie w jedną paczkę na całe miasto: Godot pomija
## wtedy kwadraty poza kadrem i poza zasięgiem każdej warstwy cienia, a dla dalekich kwadratów
## sam używa uproszczonych siatek (LOD generowane przy imporcie modeli).
const CHUNK: float = 72.0            ## miasto (8 x 8 modułów)
const BACKDROP_CHUNK: float = 150.0  ## daleka panorama za murem
## Drobiazgi znikają z odległości płynnie (dithering) - w tle i tak ich nie widać, a są w mgle.
## [fragment ścieżki, koniec zasięgu, szerokość przejścia]
const FADE_RULES: Array = [
	["bench", 110.0, 30.0], ["firehydrant", 90.0, 25.0], ["trash_", 90.0, 25.0], ["planter", 110.0, 30.0],
	["detail-parasol", 120.0, 30.0], ["Bush_", 130.0, 30.0], ["dumpster", 130.0, 30.0],
	["car_", 170.0, 40.0], ["shipping-container", 190.0, 40.0], ["streetlight", 170.0, 40.0],
	["solar-panel", 170.0, 40.0],
]


func _add(path: String, t: Transform3D, variant: int = 0) -> void:
	var p: Vector3 = t.origin
	var backdrop: bool = not _city_rect().grow(2.0).has_point(Vector2(p.x, p.z))
	var size: float = BACKDROP_CHUNK if backdrop else CHUNK
	var key := "%s|%d|%d|%d|%d" % [path, int(backdrop), floori(p.x / size), floori(p.z / size), variant]
	if not _batches.has(key):
		_batches[key] = []
	(_batches[key] as Array).append(t)


func _city_rect() -> Rect2:
	var lo: Vector2 = _center2(Vector2i(_amin, _bmin)) - Vector2(M, M) * 0.5
	var hi: Vector2 = _center2(Vector2i(_amax, _bmax)) + Vector2(M, M) * 0.5
	return Rect2(lo, hi - lo)


func _flush_batches() -> void:
	var keys: Array = _batches.keys()
	keys.sort()
	var models: Dictionary = {}  ## ścieżka -> [[siatka, transform lokalny, materiał], ...]
	for key: String in keys:
		var parts: PackedStringArray = key.split("|")
		var path: String = parts[0]
		var backdrop: bool = parts[1] == "1"
		var variant: int = int(parts[4])
		if not models.has(path):
			if not ResourceLoader.exists(path):
				push_warning("WorldGenerator: brak modelu %s" % path)
				models[path] = []
			else:
				var model: Node3D = (load(path) as PackedScene).instantiate()
				var list: Array = []
				for mi: MeshInstance3D in _meshes(model):
					list.append([mi.mesh, _relative(mi, model), mi.material_override])
				model.free()
				models[path] = list
		var transforms: Array = _batches[key]
		var fade: Array = _fade_rule(path)
		for entry: Array in models[path]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = entry[0]
			mm.instance_count = transforms.size()
			for k in transforms.size():
				mm.set_instance_transform(k, (transforms[k] as Transform3D) * (entry[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if entry[2] != null:
				mmi.material_override = entry[2]
			if variant > 0:
				var vm: Material = _variant_material(path, entry[0], variant)
				if vm != null:
					mmi.material_override = vm
			if path.contains("low-detail"):
				mmi.material_override = _haze_material()  # dalekie miasto: matowe, w kolorze mgły
			if backdrop:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # za mgłą cienie są zbędne
			elif not fade.is_empty():
				mmi.visibility_range_end = fade[1]
				mmi.visibility_range_end_margin = fade[2]
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)
	_batches.clear()
	_flush_merged()


var _variant_mats: Dictionary = {}


## Materiał modelu z podmienioną paletą (variation-a/b/c z paczki Kenney).
func _variant_material(path: String, mesh: Mesh, variant: int) -> Material:
	var kit: String = _kit_of(path)
	if kit == "" or mesh == null or mesh.get_surface_count() == 0:
		return null
	var list: Array = VARIATIONS[kit]
	var tex_path: String = "res://assets/models/%s/Variations/%s.png" % [kit, list[(variant - 1) % list.size()]]
	var key: String = "%s|%d|%s" % [kit, variant, str(mesh.surface_get_material(0).get_instance_id()) if mesh.surface_get_material(0) else "-"]
	if _variant_mats.has(key):
		return _variant_mats[key]
	var base := mesh.surface_get_material(0) as BaseMaterial3D
	if base == null or not ResourceLoader.exists(tex_path):
		_variant_mats[key] = null
		return null
	var mat := base.duplicate() as BaseMaterial3D
	mat.albedo_texture = load(tex_path)
	_variant_mats[key] = mat
	return mat


func _fade_rule(path: String) -> Array:
	for rule: Array in FADE_RULES:
		if path.contains(rule[0]):
			return rule
	return []


var _haze_mat: StandardMaterial3D


func _haze_material() -> StandardMaterial3D:
	if _haze_mat == null:
		_haze_mat = StandardMaterial3D.new()
		_haze_mat.albedo_color = Color(0.5, 0.56, 0.64)
		_haze_mat.roughness = 1.0
		_haze_mat.metallic_specular = 0.0
	return _haze_mat


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


## Statyczne bryły nie są osobnymi węzłami: trafiają do zbiorczej siatki swojego kwadratu
## (72 m) - jedno wywołanie rysowania na kwadrat zamiast setek. Kolor = kolor wierzchołków.
func _visual_box(center: Vector3, size: Vector3, rot_y: float, color: Color) -> void:
	_merge_box(Transform3D(Basis(Vector3.UP, rot_y), center), size, color)


func _merge_box(t: Transform3D, size: Vector3, color: Color, shadow: bool = true) -> void:
	var key := Vector3i(floori(t.origin.x / CHUNK), floori(t.origin.z / CHUNK), 1 if shadow else 0)
	var acc: _MeshAcc = _merged.get(key)
	if acc == null:
		acc = _MeshAcc.new()
		_merged[key] = acc
	acc.box(t, size, color)


## Belka między dwoma punktami (słupy, odciągi, liny).
func _beam(a: Vector3, b: Vector3, thick: float, color: Color, shadow: bool = true) -> void:
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 0.01:
		return
	var up: Vector3 = Vector3.RIGHT if absf(d.normalized().y) > 0.99 else Vector3.UP
	_merge_box(Transform3D(Basis.looking_at(d / length, up), (a + b) * 0.5), Vector3(thick, thick, length), color, shadow)


var _merged: Dictionary = {}
var _merged_mat: StandardMaterial3D


func _flush_merged() -> void:
	if _merged_mat == null:
		_merged_mat = StandardMaterial3D.new()
		_merged_mat.vertex_color_use_as_albedo = true
		_merged_mat.vertex_color_is_srgb = true
		_merged_mat.roughness = 0.85
	var keys: Array = _merged.keys()
	keys.sort()
	for key: Vector3i in keys:
		var mesh: ArrayMesh = (_merged[key] as _MeshAcc).commit(_merged_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if key.z == 0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_merged.clear()


class _MeshAcc:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# [normalna, u, v] - u x v = normalna; wierzchołki zgodnie z ruchem wskazówek (front Godota).
	const FACES: Array = [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]

	func box(t: Transform3D, size: Vector3, color: Color) -> void:
		var h: Vector3 = size * 0.5
		for f: Array in FACES:
			var n: Vector3 = f[0]
			var u: Vector3 = (f[1] as Vector3) * h
			var v: Vector3 = (f[2] as Vector3) * h
			var c: Vector3 = n * h
			var wn: Vector3 = (t.basis * n).normalized()
			var base: int = verts.size()
			for corner: Vector3 in [c - u - v, c - u + v, c + u + v, c + u - v]:
				verts.append(t * corner)
				norms.append(wn)
				cols.append(color)
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func commit(material: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		return mesh


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
