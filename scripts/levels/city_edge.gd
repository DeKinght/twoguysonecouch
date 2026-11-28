class_name CityEdge
extends RefCounted
## Krawędź miasta - każda strona inna, zależnie od dzielnicy, która do niej dochodzi:
##  - PRZEMYSŁ  -> PORT: nabrzeże z pachołkami, kontenery, suwnice, statek, woda, daleki brzeg;
##  - ŚRÓDMIEŚCIE -> OBWODNICA: estakada z ekranami akustycznymi i ruchem aut, na końcach
##    skręca od miasta i znika w tunelu we wzgórzu (albo we mgle);
##  - PRZEDMIEŚCIE -> WZGÓRZA: ogródki działkowe, potem teren wznosi się w zalesione wzgórza.
## Wyloty niektórych ulic są zamknięte (szlaban + tablica) i prowadzą dalej jako droga
## leśna / asfalt pod estakadą / brama portu.
##
## Oszczędność zasobów: cała geometria z prostych brył idzie do zbiorczych siatek
## (WorldGenerator._merge_box - jedna siatka na kwadrat 72 m), teren to jedna siatka,
## woda jedna płaszczyzna, las daleko - MultiMesh prostych drzewek bez cieni.
## Wszystko zależy tylko od ziarna miasta (te same wyniki u każdego gracza).

enum { PORT, HIGHWAY, HILLS }
const DECK_H: float = 7.0        ## wysokość jezdni estakady
const DECK_W: float = 13.0
const DECK_OFF: float = 5.5      ## oś estakady od krawędzi miasta (na zewnątrz)
const WATER_Y: float = -0.7
const SEABED: float = -5.0
const MIN_RUN: int = 4           ## najkrótszy odcinek jednego typu krawędzi (w modułach)

const C_CONCRETE := Color(0.62, 0.61, 0.58)
const C_CONCRETE_DARK := Color(0.45, 0.45, 0.44)
const C_ASPHALT := Color(0.24, 0.24, 0.26)
const C_WHITE := Color(0.92, 0.92, 0.9)
const C_YELLOW := Color(0.95, 0.78, 0.15)
const C_RED := Color(0.82, 0.18, 0.16)
const C_CRANE := Color(0.93, 0.5, 0.14)
const C_PANEL := Color(0.52, 0.66, 0.7)
const C_WOOD := Color(0.5, 0.34, 0.2)

var gen: WorldGenerator
var rect: Rect2
var types: Dictionary = {}       ## moduł brzegowy -> PORT / HIGHWAY / HILLS
var ring: Array[Vector2i] = []   ## moduły brzegowe w kolejności obwodu
var stubs: Dictionary = {}       ## moduł zamkniętego wylotu ulicy -> kierunek na zewnątrz

var _noise := FastNoiseLite.new()
var _rng: RandomNumberGenerator
var _port_count: int = 0
var _tree_mesh: Array[Mesh] = []
## Odcinki portu jako zakresy kątów od środka miasta: [kąt środka, połowa rozpiętości].
## Z nich rośnie wachlarz otwartego morza (szerszy im dalej od miasta).
var _sea_arcs: Array = []


func _init(generator: WorldGenerator) -> void:
	gen = generator
	_rng = gen._rng


## Przed budową dróg: typy krawędzi i zamknięte wyloty ulic (zmieniają kafle skrzyżowań).
func prepare() -> void:
	rect = gen._city_rect()
	_noise.seed = _rng.randi()
	_noise.frequency = 0.006
	_build_ring_order()
	var raw: Array[int] = []
	for m in ring:
		raw.append(_type_for(gen._district_at(gen._center2(_inner_neighbor(m)))))
	var smooth: Array[int] = _smooth_runs(raw)
	for i in ring.size():
		types[ring[i]] = smooth[i]
	_build_sea_arcs(smooth)
	_choose_stubs()


## Po budowie miasta: teren, woda, las, estakady, statki, zamknięte wyloty.
func build() -> void:
	_build_terrain()
	_build_water()
	_build_highways()
	_build_ships()
	_build_stubs()
	_build_forest()


## Zawartość modułu brzegowego (wołane z WorldGenerator._build_blocks).
func build_module(m: Vector2i) -> void:
	var outs: Array[int] = _outward_dirs(m)
	match types.get(m, HILLS):
		PORT:
			_port_module(m, outs)
		HIGHWAY:
			_highway_module(m, outs)
		_:
			_hills_module(m, outs)


# --- Typy krawędzi ------------------------------------------------------------------------

func _type_for(district: int) -> int:
	match district:
		WorldGenerator.INDUSTRIAL:
			return PORT
		WorldGenerator.COMMERCIAL:
			return HIGHWAY
	return HILLS


func _build_ring_order() -> void:
	for a in range(gen._amin, gen._amax + 1):
		ring.append(Vector2i(a, gen._bmin))
	for b in range(gen._bmin + 1, gen._bmax + 1):
		ring.append(Vector2i(gen._amax, b))
	for a in range(gen._amax - 1, gen._amin - 1, -1):
		ring.append(Vector2i(a, gen._bmax))
	for b in range(gen._bmax - 1, gen._bmin, -1):
		ring.append(Vector2i(gen._amin, b))


## Krótkie odcinki (< MIN_RUN modułów) wchłania sąsiedni typ - bez migotania typów.
func _smooth_runs(raw: Array[int]) -> Array[int]:
	var t: Array[int] = raw.duplicate()
	var n: int = t.size()
	for guard in 200:
		var runs: Array = _runs(t)
		if runs.size() <= 1:
			break
		var shortest: Array = runs[0]
		var idx: int = 0
		for k in runs.size():
			if runs[k][1] < shortest[1]:
				shortest = runs[k]
				idx = k
		if shortest[1] >= MIN_RUN:
			break
		var prev: Array = runs[(idx - 1 + runs.size()) % runs.size()]
		var next: Array = runs[(idx + 1) % runs.size()]
		var fill: int = prev[2] if prev[1] >= next[1] else next[2]
		for k in shortest[1]:
			t[(shortest[0] + k) % n] = fill
	return t


## [[start, długość, typ], ...] po obwodzie (cyklicznie).
func _runs(t: Array[int]) -> Array:
	var n: int = t.size()
	var start: int = -1
	for i in n:
		if t[i] != t[(i - 1 + n) % n]:
			start = i
			break
	if start == -1:
		return [[0, n, t[0]]]
	var out: Array = []
	var i: int = start
	var count: int = 0
	while count < n:
		var len: int = 0
		var typ: int = t[i]
		while len < n - count and t[(i + len) % n] == typ:
			len += 1
		out.append([i, len, typ])
		i = (i + len) % n
		count += len
	return out


func _build_sea_arcs(t: Array[int]) -> void:
	var c: Vector2 = rect.get_center()
	for run: Array in _runs(t):
		if run[2] != PORT:
			continue
		var mid_m: Vector2i = ring[(run[0] + run[1] / 2) % ring.size()]
		var mid: float = (gen._center2(mid_m) - c).angle()
		var half: float = 0.0
		for k in run[1]:
			var a: float = (gen._center2(ring[(run[0] + k) % ring.size()]) - c).angle()
			half = maxf(half, absf(angle_difference(mid, a)))
		_sea_arcs.append([mid, half])


## 0..1: na ile punkt leży na otwartym morzu przed portem. Wachlarz zaczyna się dokładnie
## na szerokości nabrzeża i rozszerza o 45° w każdą stronę ku horyzontowi.
func _sea(p: Vector2, d: float) -> float:
	if _sea_arcs.is_empty():
		return 0.0
	var ang: float = (p - rect.get_center()).angle()
	var best: float = 0.0
	for arc: Array in _sea_arcs:
		var diff: float = absf(angle_difference(ang, arc[0]))
		var width: float = arc[1] + deg_to_rad(45.0) * smoothstep(20.0, 420.0, d)
		var margin: float = deg_to_rad(4.0) + deg_to_rad(6.0) * smoothstep(0.0, 300.0, d)
		best = maxf(best, 1.0 - smoothstep(width - margin, width + margin, diff))
	return best * smoothstep(12.0, 50.0, d)  # przy samej krawędzi decyduje moduł (nabrzeże)


func _outward_dirs(m: Vector2i) -> Array[int]:
	var out: Array[int] = []
	if m.y == gen._bmin:
		out.append(WorldGenerator.N)
	if m.x == gen._amax:
		out.append(WorldGenerator.E)
	if m.y == gen._bmax:
		out.append(WorldGenerator.S)
	if m.x == gen._amin:
		out.append(WorldGenerator.W)
	return out


func _inner_neighbor(m: Vector2i) -> Vector2i:
	var r: Vector2i = m
	for d: int in _outward_dirs(m):
		r -= WorldGenerator.DIRS[d]
	return r


func _dir3(d: int) -> Vector3:
	var v: Vector2i = WorldGenerator.DIRS[d]
	return Vector3(v.x, 0, v.y)


## Środek zewnętrznej krawędzi modułu w danym kierunku.
func _edge_mid(m: Vector2i, d: int) -> Vector3:
	return gen._center(m) + _dir3(d) * (WorldGenerator.M * 0.5)


# --- Zamknięte wyloty ulic ----------------------------------------------------------------

func _choose_stubs() -> void:
	var sides: Array = [
		[gen._zl, 0, WorldGenerator.N, true], [gen._xl, gen._xl.size() - 1, WorldGenerator.E, false],
		[gen._zl, gen._zl.size() - 1, WorldGenerator.S, true], [gen._xl, 0, WorldGenerator.W, false],
	]
	for side: Array in sides:
		var line_val: int = (side[0] as Array)[side[1]]
		var cross: Array = gen._xl if side[3] else gen._zl
		var made: int = 0
		for k in range(1, cross.size() - 1):
			var node := Vector2i(cross[k], line_val) if side[3] else Vector2i(line_val, cross[k])
			var mask: int = gen._road_mask.get(node, 0)
			var out: int = side[2]
			var inward: int = {WorldGenerator.N: WorldGenerator.S, WorldGenerator.S: WorldGenerator.N,
					WorldGenerator.E: WorldGenerator.W, WorldGenerator.W: WorldGenerator.E}[out]
			if not (mask & inward) or (mask & out) or made >= 2 or _rng.randf() > 0.4:
				continue
			var stub: Vector2i = node + WorldGenerator.DIRS[out]
			gen._road_mask[node] = mask | out
			gen._type[stub] = WorldGenerator.ROAD
			gen._road_mask[stub] = out | inward
			stubs[stub] = out
			made += 1


func _build_stubs() -> void:
	var keys: Array = stubs.keys()
	keys.sort()
	for m: Vector2i in keys:
		var d: int = stubs[m]
		var out: Vector3 = _dir3(d)
		var side: Vector3 = out.cross(Vector3.UP)
		var edge: Vector3 = _edge_mid(m, d)
		var typ: int = types.get(m, HILLS)
		var yaw: float = atan2(side.x, side.z)
		var bar_pos: Vector3 = edge - out * 1.2
		# Zapora z biało-czerwonych desek na słupkach w poprzek jezdni.
		for k in 9:
			var x: float = -3.6 + k * 0.9
			var col: Color = C_RED if k % 2 == 0 else C_WHITE
			gen._merge_box(Transform3D(Basis(Vector3.UP, yaw), bar_pos + side * x + Vector3(0, 0.95, 0)), Vector3(0.08, 0.28, 0.9), col)
			gen._merge_box(Transform3D(Basis(Vector3.UP, yaw), bar_pos + side * x + Vector3(0, 0.45, 0)), Vector3(0.08, 0.22, 0.9), C_WHITE if k % 2 == 0 else C_RED)
		for x: float in [-3.7, 0.0, 3.7]:
			gen._merge_box(Transform3D(Basis(Vector3.UP, yaw), bar_pos + side * x + Vector3(0, 0.6, 0)), Vector3(0.12, 1.2, 0.12), C_CONCRETE_DARK)
		gen._box_collider(bar_pos + Vector3(0, 1.0, 0), Vector3(0.4, 2.0, 8.0), yaw)
		# Tablica przy zaporze.
		var text: String = {PORT: "PORT\nWSTĘP WZBRONIONY", HIGHWAY: "ROBOTY DROGOWE\nOBJAZD", HILLS: "DROGA LEŚNA\nZAKAZ WJAZDU"}[typ]
		var sign_pos: Vector3 = bar_pos - out * 0.6 + side * 3.0
		gen._merge_box(Transform3D(Basis(Vector3.UP, yaw), sign_pos + Vector3(0, 1.0, 0)), Vector3(0.1, 2.0, 0.1), C_CONCRETE_DARK)
		gen._merge_box(Transform3D(Basis(Vector3.UP, yaw), sign_pos + Vector3(0, 2.2, 0)), Vector3(0.06, 1.0, 2.4), C_YELLOW if typ != PORT else C_WHITE)
		var label := Label3D.new()
		label.text = text
		label.font_size = 56
		label.pixel_size = 0.0055
		label.outline_size = 0
		label.modulate = Color(0.1, 0.1, 0.1)
		label.position = sign_pos + Vector3(0, 2.2, 0) - out * 0.04
		label.rotation.y = atan2(-out.x, -out.z)
		gen.add_child(label)
		_add_cones(bar_pos - out * 1.4, side)
		match typ:
			PORT:
				_quay_wall(m, d)
			HIGHWAY:
				_track(edge, out, C_ASPHALT, 7.0, 60.0)
			_:
				_track(edge, out, Color(0.45, 0.36, 0.25), 3.6, 45.0)


func _add_cones(at: Vector3, side: Vector3) -> void:
	var path: String = "res://assets/models/cars/cone.glb"
	if not ResourceLoader.exists(path):
		return
	var box: AABB = gen._model_aabb(path)
	var s: float = 0.8 / maxf(box.size.y, 0.01)
	for x: float in [-2.4, -0.8, 0.8, 2.4]:
		gen._add(path, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), at + side * x))


## Droga za zaporą: pasy jezdni po terenie (asfalt albo szuter), coraz bardziej we mgle.
func _track(start: Vector3, out: Vector3, color: Color, width: float, length: float) -> void:
	var step: float = 4.0
	var prev: Vector3 = start + Vector3(0, _height(Vector2(start.x, start.z)), 0)
	var d: float = step
	while d <= length:
		var p: Vector3 = start + out * d
		p.y = _height(Vector2(p.x, p.z))
		if p.y < WATER_Y + 0.2:
			break
		var mid: Vector3 = (prev + p) * 0.5 + Vector3(0, 0.05, 0)
		var seg: Vector3 = p - prev
		var t := Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), mid)
		gen._merge_box(t, Vector3(width, 0.1, seg.length() + 0.3), color, false)
		prev = p
		d += step


# --- Port -----------------------------------------------------------------------------------

func _port_module(m: Vector2i, outs: Array[int]) -> void:
	var c: Vector3 = gen._center(m)
	gen._flat_box(c, Vector2(WorldGenerator.M, WorldGenerator.M), Color(0.56, 0.56, 0.54), 0.013)
	for d: int in outs:
		_quay_wall(m, d)
	_port_count += 1
	if outs.size() == 1 and _port_count % 5 == 2:
		_crane(m, outs[0])
	elif outs.size() == 1 and _rng.randf() < 0.65:
		var out: Vector3 = _dir3(outs[0])
		var side: Vector3 = out.cross(Vector3.UP)
		var yaw: float = atan2(side.x, side.z)
		for k in _rng.randi_range(1, 2):
			var p: Vector3 = c + out * 0.5 + side * (-2.2 + k * 3.2 + _rng.randf_range(-0.4, 0.4))
			var levels: int = _rng.randi_range(1, 3)
			for lv in levels:
				var name: String = "shipping-container-" + ["a", "b", "c"][_rng.randi_range(0, 2)]
				gen._add(WorldGenerator.IND % name, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 6.0),
						p + Vector3(0, lv * 2.1, 0)), _rng.randi_range(0, 3))
			gen._box_collider(p + Vector3(0, levels * 1.05, 0), Vector3(2.3, levels * 2.1, 4.9), yaw)


## Ściana nabrzeża od wody (do dna), żółta krawędź i pachołki cumownicze.
func _quay_wall(m: Vector2i, d: int) -> void:
	var out: Vector3 = _dir3(d)
	var side: Vector3 = out.cross(Vector3.UP)
	var yaw: float = atan2(side.x, side.z)
	var edge: Vector3 = _edge_mid(m, d)
	var len: float = WorldGenerator.M + 0.8
	var depth: float = 0.05 - SEABED + 0.5
	gen._merge_box(Transform3D(Basis(Vector3.UP, yaw), edge + out * 0.4 + Vector3(0, 0.05 - depth * 0.5, 0)), Vector3(0.8, depth, len), C_CONCRETE)
	gen._merge_box(Transform3D(Basis(Vector3.UP, yaw), edge - out * 0.35 + Vector3(0, 0.03, 0)), Vector3(0.3, 0.03, WorldGenerator.M), C_YELLOW)
	for k in 3:
		var p: Vector3 = edge - out * 0.25 + side * (-3.0 + k * 3.0)
		gen._merge_box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.25, 0)), Vector3(0.35, 0.5, 0.35), Color(0.2, 0.2, 0.22))
		gen._merge_box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.55, 0)), Vector3(0.5, 0.1, 0.5), Color(0.2, 0.2, 0.22))


## Suwnica nabrzeżowa: brama na czterech nogach, wysięgnik nad wodą, wózek z liną.
func _crane(m: Vector2i, d: int) -> void:
	var out: Vector3 = _dir3(d)
	var side: Vector3 = out.cross(Vector3.UP)
	var o: Vector3 = _edge_mid(m, d)
	var at := func(x: float, y: float, z: float) -> Vector3:
		return o + side * x + Vector3.UP * y + out * z
	var h: float = 24.0
	for x: float in [-3.8, 3.8]:
		for z: float in [-1.0, -7.8]:
			gen._beam(at.call(x, 0, z), at.call(x, h, z), 0.9, C_CRANE)
			gen._box_collider(at.call(x, h * 0.5, z), Vector3(0.9, h, 0.9), atan2(side.x, side.z))
		gen._beam(at.call(x, h, -1.0), at.call(x, h, -7.8), 1.1, C_CRANE)
		gen._beam(at.call(x, 6.0, -1.0), at.call(x, 6.0, -7.8), 0.6, C_CRANE)
	for z: float in [-1.0, -7.8]:
		gen._beam(at.call(-3.8, h, z), at.call(3.8, h, z), 1.1, C_CRANE)
	# Wysięgnik (dwa dźwigary) od zaplecza nad wodę.
	for x: float in [-1.6, 1.6]:
		gen._beam(at.call(x, h + 2.0, -16.0), at.call(x, h + 2.0, 34.0), 1.0, C_CRANE)
	gen._merge_box(Transform3D(Basis(Vector3.UP, atan2(side.x, side.z)), at.call(0, h + 1.2, -4.4)), Vector3(8.6, 1.6, 9.0), C_CRANE)
	# Maszynownia, pylon i odciągi.
	gen._merge_box(Transform3D(Basis(Vector3.UP, atan2(side.x, side.z)), at.call(0, h + 4.4, -12.0)), Vector3(7.0, 3.4, 5.0), C_WHITE)
	for x: float in [-1.6, 1.6]:
		gen._beam(at.call(x, h + 2.0, -3.0), at.call(x, h + 12.0, -3.0), 0.8, C_CRANE)
		gen._beam(at.call(x, h + 12.0, -3.0), at.call(x, h + 2.5, 30.0), 0.3, C_CONCRETE_DARK)
		gen._beam(at.call(x, h + 12.0, -3.0), at.call(x, h + 2.5, -15.0), 0.3, C_CONCRETE_DARK)
	# Wózek z kabiną i chwytakiem nad wodą.
	var trolley: float = _rng.randf_range(6.0, 26.0)
	gen._merge_box(Transform3D(Basis(Vector3.UP, atan2(side.x, side.z)), at.call(0, h + 1.0, trolley)), Vector3(3.2, 1.6, 4.4), Color(0.25, 0.25, 0.27))
	gen._beam(at.call(0, h, trolley), at.call(0, h - 12.0, trolley), 0.12, Color(0.15, 0.15, 0.16))
	gen._merge_box(Transform3D(Basis(Vector3.UP, atan2(side.x, side.z)), at.call(0, h - 12.4, trolley)), Vector3(2.6, 0.5, 6.0), C_YELLOW)


## Statek przy każdym dłuższym odcinku portu (stoi na wodzie, dekoracja bez kolizji).
func _build_ships() -> void:
	var types_list: Array[int] = []
	for mm in ring:
		types_list.append(types[mm])
	for run: Array in _runs(types_list):
		if run[2] != PORT or run[1] < 6:
			continue
		# Środkowy, prosty fragment odcinka (bez narożnika).
		var mid_i: int = (run[0] + run[1] / 2) % ring.size()
		var m: Vector2i = ring[mid_i]
		var outs: Array[int] = _outward_dirs(m)
		if outs.size() != 1:
			continue
		var out: Vector3 = _dir3(outs[0])
		var side: Vector3 = out.cross(Vector3.UP)
		var yaw: float = atan2(side.x, side.z)
		var length: float = minf(run[1] * WorldGenerator.M - 24.0, 92.0)
		var c: Vector3 = _edge_mid(m, outs[0]) + out * 13.0
		var basis := Basis(Vector3.UP, yaw)
		var t := func(x: float, y: float, z: float) -> Transform3D:
			return Transform3D(basis, c + side * x + Vector3.UP * y + out * z)
		gen._merge_box(t.call(0, -2.4, 0), Vector3(14.0, 3.2, length), Color(0.55, 0.16, 0.14), false)
		gen._merge_box(t.call(0, 0.9, 0), Vector3(14.0, 3.4, length), Color(0.16, 0.24, 0.38), false)
		gen._merge_box(t.call(length * 0.5 + 3.0, 0.4, 0), Vector3(9.0, 4.6, 6.0), Color(0.16, 0.24, 0.38), false)
		gen._merge_box(t.call(length * 0.5 + 6.5, 0.6, 0), Vector3(4.5, 4.2, 3.0), Color(0.16, 0.24, 0.38), false)
		var stern: float = -length * 0.5 + 6.0
		gen._merge_box(t.call(stern, 7.2, 0), Vector3(12.0, 9.2, 9.0), C_WHITE, false)
		gen._merge_box(t.call(stern + 0.1, 10.6, 0), Vector3(12.2, 1.2, 9.2), Color(0.15, 0.2, 0.28), false)
		gen._merge_box(t.call(stern - 2.0, 14.0, 0), Vector3(3.0, 4.0, 3.0), C_RED, false)
		var x: float = stern + 8.0
		while x < length * 0.5 - 3.0:
			for row in 5:
				var z: float = -4.8 + row * 2.4
				var levels: int = _rng.randi_range(1, 3)
				for lv in levels:
					var name: String = "shipping-container-" + ["a", "b", "c"][_rng.randi_range(0, 2)]
					var p: Vector3 = c + side * x + out * z + Vector3.UP * (2.6 + lv * 2.1)
					gen._add(WorldGenerator.IND % name, Transform3D(basis.scaled(Vector3.ONE * 6.0), p), _rng.randi_range(0, 3))
			x += 5.2


# --- Obwodnica ------------------------------------------------------------------------------

func _highway_module(m: Vector2i, outs: Array[int]) -> void:
	var c: Vector3 = gen._center(m)
	var inward: Vector3 = -_dir3(outs[0])
	if outs.size() == 1 and _rng.randf() < 0.45:
		# Parking pod estakadą.
		gen._flat_box(c, Vector2(WorldGenerator.M, WorldGenerator.M), Color(0.3, 0.3, 0.32), 0.012)
		var side: Vector3 = inward.cross(Vector3.UP)
		for k in 4:
			var x: float = -3.4 + k * 2.3
			gen._merge_box(Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), c + side * (x - 1.15) + Vector3(0, 0.03, 0)), Vector3(0.12, 0.02, 4.6), C_WHITE)
			if _rng.randf() < 0.55:
				var car: String = ["car_sedan", "car_hatchback", "car_stationwagon", "car_taxi"][_rng.randi_range(0, 3)]
				var heading: float = atan2(inward.x, inward.z) + (PI if _rng.randf() < 0.5 else 0.0)
				var p: Vector3 = c + side * x + Vector3(0, 0.27, 0)
				gen._add(WorldGenerator.CITY % car, Transform3D(Basis(Vector3.UP, heading).scaled(Vector3.ONE * WorldGenerator.S_CITY), p))
				gen._box_collider(p + Vector3(0, 0.6, 0), Vector3(1.9, 1.5, 4.2), heading)
	else:
		# Zieleń pod estakadą i billboard frontem do ulicy.
		for k in _rng.randi_range(2, 4):
			var p: Vector3 = c + Vector3(_rng.randf_range(-3.5, 3.5), 0, _rng.randf_range(-3.5, 3.5))
			gen._add(WorldGenerator.NATURE % WorldGenerator.BUSHES[_rng.randi_range(0, WorldGenerator.BUSHES.size() - 1)],
					Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 2.0), p))
		if outs.size() == 1 and _rng.randf() < 0.5:
			_billboard(c - inward * 1.5, inward)


const SLOGANS: Array[String] = [
	"PRZEPROWADZKA?\nTGOC - NOSIMY ZA CIEBIE", "KANAPY OD 99 ZŁ\nMEBLE-MAX", "OSTROŻNIE: SZKŁO!\nZAWSZE.",
	"WINDA NIE DZIAŁA?\nMY TEŻ NIE", "PIZZA W 30 MIN\nALBO DWIE", "TWOJA REKLAMA\nTUTAJ",
]


func _billboard(at: Vector3, facing: Vector3) -> void:
	var yaw: float = atan2(facing.x, facing.z)
	var basis := Basis(Vector3.UP, yaw)
	var side: Vector3 = facing.cross(Vector3.UP)
	for x: float in [-2.2, 2.2]:
		gen._merge_box(Transform3D(basis, at + side * x + Vector3(0, 2.2, 0)), Vector3(0.25, 4.4, 0.25), C_CONCRETE_DARK)
	gen._merge_box(Transform3D(basis, at + Vector3(0, 5.6, 0)), Vector3(6.4, 3.0, 0.25), Color(0.95, 0.65, 0.25))
	gen._merge_box(Transform3D(basis, at + Vector3(0, 5.6, 0) + facing * 0.13), Vector3(6.0, 2.6, 0.02), C_WHITE)
	gen._box_collider(at + Vector3(0, 2.2, 0), Vector3(5.0, 4.4, 0.4), yaw)
	var label := Label3D.new()
	label.text = SLOGANS[_rng.randi_range(0, SLOGANS.size() - 1)]
	label.font_size = 64
	label.pixel_size = 0.012
	label.outline_size = 0
	label.modulate = Color(0.12, 0.1, 0.12)
	label.position = at + Vector3(0, 5.6, 0) + facing * 0.16
	label.rotation.y = yaw
	gen.add_child(label)


## Estakada: łamana po obwodzie (zaokrąglone narożniki), na końcach odcinka skręca od miasta
## i znika w tunelu we wzgórzu albo we mgle. Jezdnia, bariera środkowa, bariery boczne,
## ekrany akustyczne od strony miasta, filary co ~13,5 m.
func _build_highways() -> void:
	var types_list: Array[int] = []
	for mm in ring:
		types_list.append(types[mm])
	var runs: Array = _runs(types_list)
	var paths: Array = []
	for run: Array in runs:
		if run[2] != HIGHWAY:
			continue
		var pts := PackedVector3Array()
		var closed: bool = runs.size() == 1
		for k in run[1] + (1 if closed else 0):
			pts.append(_ring_point(ring[(run[0] + k) % ring.size()]))
		if not closed:
			var first: Vector3 = pts[0]
			var last: Vector3 = pts[pts.size() - 1]
			var lead: PackedVector3Array = _exit_leg(first, _ring_normal(ring[run[0]]))
			var tail: PackedVector3Array = _exit_leg(last, _ring_normal(ring[(run[0] + run[1] - 1) % ring.size()]))
			lead.reverse()
			var all := PackedVector3Array()
			all.append_array(lead)
			all.append_array(pts)
			all.append_array(tail)
			pts = all
		pts = _resample(_round_corners(pts, 18.0), 4.5)
		_deck(pts)
		paths.append([pts, closed])
	if not paths.is_empty():
		var traffic := HighwayTraffic.new()
		traffic.name = "HighwayTraffic"
		gen.add_child(traffic)
		traffic.setup(paths, DECK_H, gen.seed_value)


## Punkt osi estakady naprzeciw modułu brzegowego.
func _ring_point(m: Vector2i) -> Vector3:
	var p: Vector3 = gen._center(m)
	for d: int in _outward_dirs(m):
		p += _dir3(d) * (WorldGenerator.M * 0.5 + DECK_OFF)
	return p


func _ring_normal(m: Vector2i) -> Vector3:
	var n := Vector3.ZERO
	for d: int in _outward_dirs(m):
		n += _dir3(d)
	return n.normalized()


## Wylot estakady od miasta: prosto na zewnątrz aż teren ją przykryje (tunel) albo 380 m (mgła).
func _exit_leg(from: Vector3, normal: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var d: float = 24.0
	while d < 380.0:
		var p: Vector3 = from + normal * d
		pts.append(p)
		if _height(Vector2(p.x, p.z)) > DECK_H + 2.0:
			_portal(p, normal)
			pts.append(from + normal * (d + 30.0))
			break
		d += 12.0
	return pts


func _portal(at: Vector3, normal: Vector3) -> void:
	var basis := Basis(Vector3.UP, atan2(normal.cross(Vector3.UP).x, normal.cross(Vector3.UP).z))
	gen._merge_box(Transform3D(basis, at + Vector3(0, 6.5, 0)), Vector3(1.6, 13.0, DECK_W + 8.0), C_CONCRETE, false)
	gen._merge_box(Transform3D(basis, at + Vector3(0, DECK_H + 3.0, 0) - normal * 0.1), Vector3(1.9, 6.0, DECK_W - 1.0), Color(0.04, 0.04, 0.05), false)


func _deck(pts: PackedVector3Array) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var mid: Vector3 = (a + b) * 0.5
		var ground: float = _height(Vector2(mid.x, mid.z))
		if ground > DECK_H + 0.4:
			continue  # w tunelu - przykrywa teren
		var dir: Vector3 = (b - a).normalized()
		var right: Vector3 = dir.cross(Vector3.UP)
		var len: float = a.distance_to(b) + 0.35
		var basis := Basis.looking_at(dir, Vector3.UP)
		var shadow: bool = rect.grow(30.0).has_point(Vector2(mid.x, mid.z))
		var t := func(x: float, y: float) -> Transform3D:
			return Transform3D(basis, mid + right * x + Vector3.UP * y)
		gen._merge_box(t.call(0, DECK_H - 0.6), Vector3(DECK_W, 1.2, len), C_CONCRETE, shadow)
		gen._merge_box(t.call(0, DECK_H + 0.02), Vector3(DECK_W - 1.0, 0.05, len), C_ASPHALT, shadow)
		gen._merge_box(t.call(0, DECK_H + 0.45), Vector3(0.6, 0.9, len), C_CONCRETE, shadow)
		for x: float in [-DECK_W * 0.5 + 0.25, DECK_W * 0.5 - 0.25]:
			gen._merge_box(t.call(x, DECK_H + 0.5), Vector3(0.5, 1.0, len), C_CONCRETE, shadow)
		if i % 2 == 0:
			for x: float in [-3.1, 3.1]:
				gen._merge_box(t.call(x, DECK_H + 0.06), Vector3(0.15, 0.02, 2.2), C_WHITE, false)
		# Ekran akustyczny po stronie miasta - tylko na odcinku wzdłuż krawędzi (nie na wylotach).
		if _out_dist(Vector2(mid.x, mid.z)) < DECK_OFF + 3.0:
			var edge_x: float = DECK_W * 0.5 - 0.25
			var left: Vector3 = mid - right * edge_x
			var right_p: Vector3 = mid + right * edge_x
			var x_city: float = -edge_x if _out_dist(Vector2(left.x, left.z)) < _out_dist(Vector2(right_p.x, right_p.z)) else edge_x
			gen._merge_box(t.call(x_city, DECK_H + 2.6), Vector3(0.2, 3.2, len), C_PANEL, shadow)
			if i % 2 == 0:
				gen._merge_box(t.call(x_city, DECK_H + 2.6), Vector3(0.35, 3.4, 0.3), C_CONCRETE_DARK, shadow)
		# Filary.
		if i % 3 == 0 and ground < DECK_H - 2.0:
			var base: float = maxf(ground, SEABED) - 0.3
			var col_h: float = DECK_H - 1.4 - base
			gen._merge_box(Transform3D(basis, Vector3(mid.x, base + col_h * 0.5, mid.z)), Vector3(1.5, col_h, 1.5), C_CONCRETE, shadow)
			gen._merge_box(t.call(0, DECK_H - 1.7), Vector3(DECK_W - 2.5, 1.0, 1.8), C_CONCRETE_DARK, shadow)


func _round_corners(pts: PackedVector3Array, radius: float) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var d1: Vector3 = (b - a).normalized()
		var d2: Vector3 = (c - b).normalized()
		if d1.dot(d2) > 0.999:
			out.append(b)
			continue
		var r: float = minf(radius, minf(a.distance_to(b), b.distance_to(c)) * 0.45)
		var p0: Vector3 = b - d1 * r
		var p1: Vector3 = b + d2 * r
		for k in 7:  # krzywa Béziera przez narożnik
			var t: float = k / 6.0
			out.append(p0.lerp(b, t).lerp(b.lerp(p1, t), t))
	out.append(pts[pts.size() - 1])
	return out


func _resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size()):
		var a: Vector3 = out[out.size() - 1]
		var b: Vector3 = pts[i]
		var d: float = a.distance_to(b)
		if d < 0.01:
			continue
		var n: int = maxi(1, int(ceil(d / step)))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
	return out


# --- Wzgórza: ogródki działkowe ---------------------------------------------------------------

const SHED_COLORS: Array[Color] = [Color(0.55, 0.68, 0.5), Color(0.75, 0.55, 0.4), Color(0.5, 0.6, 0.72),
		Color(0.85, 0.78, 0.55), Color(0.65, 0.45, 0.42)]


func _hills_module(m: Vector2i, outs: Array[int]) -> void:
	var c: Vector3 = gen._center(m)
	if outs.size() != 1 or _rng.randf() < 0.35:
		# Łąka na skraju lasu.
		for k in _rng.randi_range(1, 3):
			var p: Vector3 = c + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
			gen._add(WorldGenerator.NATURE % WorldGenerator.TREES[_rng.randi_range(0, WorldGenerator.TREES.size() - 1)],
					Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(1.3, 1.8)), p))
			gen._box_collider(p + Vector3(0, 1.5, 0), Vector3(0.6, 3.0, 0.6), 0.0)
		for k in _rng.randi_range(2, 4):
			var p2: Vector3 = c + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
			gen._add(WorldGenerator.NATURE % WorldGenerator.BUSHES[_rng.randi_range(0, WorldGenerator.BUSHES.size() - 1)],
					Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 2.0), p2))
		return
	var out: Vector3 = _dir3(outs[0])
	var side: Vector3 = out.cross(Vector3.UP)
	var yaw: float = atan2(side.x, side.z)
	var basis := Basis(Vector3.UP, yaw)
	var at := func(x: float, z: float) -> Vector3:
		return c + side * x + out * z
	var half: float = 4.2
	# Płot dookoła (słupki + dwie żerdzie), furtka od ulicy, płot dzielący dwie działki.
	_fence_line(at.call(-half, -half), at.call(-0.8, -half))
	_fence_line(at.call(0.8, -half), at.call(half, -half))
	_fence_line(at.call(-half, half), at.call(half, half))
	_fence_line(at.call(-half, -half), at.call(-half, half))
	_fence_line(at.call(half, -half), at.call(half, half))
	_fence_line(at.call(0, -1.5), at.call(0, half))
	for x_sign: float in [-1.0, 1.0]:
		var sx: float = x_sign * 2.1
		# Altanka w głębi działki.
		var shed: Vector3 = at.call(sx + x_sign * 0.4, 2.6)
		var col: Color = SHED_COLORS[_rng.randi_range(0, SHED_COLORS.size() - 1)]
		gen._merge_box(Transform3D(basis, shed + Vector3(0, 1.0, 0)), Vector3(2.2, 2.0, 2.0), col)
		for r: float in [-1.0, 1.0]:
			var roof := Transform3D(basis * Basis(Vector3.BACK, -r * 0.55), shed + Vector3(0, 2.25, 0) + out * r * 0.5)
			gen._merge_box(roof, Vector3(1.35, 0.1, 2.5), Color(0.35, 0.22, 0.18))
		gen._merge_box(Transform3D(basis, shed + Vector3(0, 0.85, 0) - out * 1.01), Vector3(0.03, 1.6, 0.8), col.darkened(0.35))
		gen._box_collider(shed + Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 2.2), yaw)
		# Grządki.
		for k in 2:
			var bed: Vector3 = at.call(sx, -2.6 + k * 1.5)
			gen._merge_box(Transform3D(basis, bed + Vector3(0, 0.1, 0)), Vector3(0.9, 0.2, 2.6), Color(0.36, 0.25, 0.16))
			for j in 5:
				gen._merge_box(Transform3D(basis, bed + side * (-1.0 + j * 0.5) + Vector3(0, 0.3, 0)), Vector3(0.3, 0.22, 0.3), Color(0.3, 0.58, 0.25))
		if _rng.randf() < 0.6:
			var tp: Vector3 = at.call(sx - x_sign * 1.2, 0.6)
			gen._add(WorldGenerator.NATURE % WorldGenerator.TREES[_rng.randi_range(0, WorldGenerator.TREES.size() - 1)],
					Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.1)), tp))
	for x: float in [-2.5, 2.5]:  # płot od ulicy (między nimi furtka)
		gen._box_collider(at.call(x, -half) + Vector3(0, 0.5, 0), Vector3(0.2, 1.0, 3.4), yaw)


func _fence_line(a: Vector3, b: Vector3) -> void:
	var len: float = a.distance_to(b)
	if len < 0.2:
		return
	var dir: Vector3 = (b - a) / len
	var basis := Basis.looking_at(dir, Vector3.UP)
	for y: float in [0.35, 0.75]:
		gen._merge_box(Transform3D(basis, (a + b) * 0.5 + Vector3(0, y, 0)), Vector3(0.05, 0.07, len), C_WOOD)
	var n: int = maxi(1, int(len / 1.5))
	for k in n + 1:
		gen._merge_box(Transform3D(Basis.IDENTITY, a.lerp(b, float(k) / n) + Vector3(0, 0.45, 0)), Vector3(0.09, 0.9, 0.09), C_WOOD.darkened(0.2))


# --- Teren, woda, las -------------------------------------------------------------------------

## Odległość punktu na zewnątrz miasta (0 w środku).
func _out_dist(p: Vector2) -> float:
	var dx: float = maxf(rect.position.x - p.x, p.x - rect.end.x)
	var dz: float = maxf(rect.position.y - p.y, p.y - rect.end.y)
	if dx <= 0.0 and dz <= 0.0:
		return 0.0
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


## Wagi typów krawędzi [port, obwodnica, wzgórza] w punkcie za miastem. Przy samej krawędzi
## ostre (jak moduł naprzeciw), dalej uśrednione wzdłuż krawędzi - płynne przejścia.
func _weights(p: Vector2) -> Vector3:
	var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
	var d: float = p.distance_to(q)
	var sea: float = _sea(p, d)
	if d >= 760.0:
		return _with_sea(Vector3(0, 0, 1), sea)  # daleko ląd to wzgórza - bez liczenia
	var tangent := Vector2(0, 1) if (q.x <= rect.position.x + 0.01 or q.x >= rect.end.x - 0.01) else Vector2(1, 0)
	var spread: float = clampf(d / 45.0, 0.02, 1.0) * WorldGenerator.M * 2.5
	var w := Vector3.ZERO
	for k in range(-2, 3):
		var s: Vector2 = q + tangent * (k * spread)
		s = Vector2(clampf(s.x, rect.position.x + 0.5, rect.end.x - 0.5), clampf(s.y, rect.position.y + 0.5, rect.end.y - 0.5))
		var m := Vector2i(roundi((s.x - WorldGenerator.ORIGIN.x) / WorldGenerator.M), roundi((s.y - WorldGenerator.ORIGIN.y) / WorldGenerator.M))
		m = Vector2i(clampi(m.x, gen._amin, gen._amax), clampi(m.y, gen._bmin, gen._bmax))
		if not types.has(m):  # środek boku - najbliższy moduł brzegowy
			var to_side: Array = [absf(m.x - gen._amin), absf(m.x - gen._amax), absf(m.y - gen._bmin), absf(m.y - gen._bmax)]
			var best: int = to_side.find(to_side.min())
			m = [Vector2i(gen._amin, m.y), Vector2i(gen._amax, m.y), Vector2i(m.x, gen._bmin), Vector2i(m.x, gen._bmax)][best]
		match types.get(m, HILLS):
			PORT:
				w.x += 1.0
			HIGHWAY:
				w.y += 1.0
			_:
				w.z += 1.0
	w /= 5.0
	# Daleko od miasta ląd przechodzi we wzgórza (dolina), ale przed portem zostaje otwarte morze.
	return _with_sea(w.lerp(Vector3(0, 0, 1), smoothstep(380.0, 760.0, d)), sea)


func _with_sea(w: Vector3, sea: float) -> Vector3:
	if sea <= w.x:
		return w
	var rest: float = w.y + w.z
	if rest > 0.0001:
		w.y *= (1.0 - sea) / rest
		w.z *= (1.0 - sea) / rest
	w.x = sea
	return w


func _height(p: Vector2) -> float:
	var d: float = _out_dist(p)
	if d <= 0.0:
		return -0.3
	var w: Vector3 = _weights(p)
	var n1: float = _noise.get_noise_2dv(p)
	var n2: float = _noise.get_noise_2d(p.x * 2.7 + 311.0, p.y * 2.7 - 97.0)
	var hills: float = smoothstep(3.0, 140.0, d) * (26.0 + 20.0 * n1) + smoothstep(140.0, 620.0, d) * (34.0 + 22.0 * n2) \
			+ n2 * 2.0 * smoothstep(3.0, 40.0, d)
	var port: float = SEABED - smoothstep(20.0, 400.0, d) * 6.0  # otwarte morze, coraz głębiej
	var hwy: float = smoothstep(70.0, 460.0, d) * (26.0 + 16.0 * n1)
	# Pasmo gór na horyzoncie zamyka widok (kraniec terenu ginie za grzbietem we mgle).
	var ridge: float = smoothstep(750.0, 1350.0, d) * (95.0 + 45.0 * n2)
	return w.x * port + w.y * hwy + w.z * hills + ridge * (1.0 - w.x)


func _terrain_color(h: float, slope: float, p: Vector2, port_w: float) -> Color:
	if h < WATER_Y - 0.4:
		return Color(0.4, 0.4, 0.33).lerp(Color(0.24, 0.27, 0.25), clampf((WATER_Y - h) / 4.0, 0.0, 1.0))
	if h < WATER_Y + 1.0 and port_w > 0.05:  # plaża tylko nad wodą
		return Color(0.78, 0.72, 0.54)
	var grass := Color(0.36, 0.52, 0.29)
	var forest := Color(0.2, 0.34, 0.2)
	var f: float = clampf(_forest_density(p, h) * 1.4, 0.0, 1.0)
	var col: Color = grass.lerp(forest, f)
	if slope > 0.75:
		col = col.lerp(Color(0.5, 0.48, 0.44), clampf((slope - 0.75) * 2.5, 0.0, 0.7))
	return col


func _forest_density(p: Vector2, h: float, w: Vector3 = Vector3(-1, 0, 0)) -> float:
	if h < WATER_Y + 1.2:
		return 0.0
	if w.x < 0.0:
		w = _weights(p)
	var base: float = w.z * 0.85 + w.y * 0.3 + w.x * 0.55
	return clampf(base * (0.55 + 0.6 * _noise.get_noise_2d(p.x * 1.7 - 40.0, p.y * 1.7 + 70.0)), 0.0, 1.0)


func _axis(lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d: float = 1500.0
	var outer := PackedFloat32Array()
	var x: float = 0.0
	while x < d:
		outer.append(x)
		x += clampf(5.0 + x * 0.075, 5.0, 70.0)
	for k in range(outer.size() - 1, 0, -1):
		out.append(lo - outer[k])
	var steps: int = maxi(1, int((hi - lo) / 9.0))
	for k in steps + 1:
		out.append(lo + (hi - lo) * k / steps)
	for k in range(1, outer.size()):
		out.append(hi + outer[k])
	return out


## Jedna siatka terenu dookoła miasta (bez środka), wierzchołki z kolorami, bez kolizji.
func _build_terrain() -> void:
	var xs: PackedFloat32Array = _axis(rect.position.x, rect.end.x)
	var zs: PackedFloat32Array = _axis(rect.position.y, rect.end.y)
	var nx: int = xs.size()
	var nz: int = zs.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	cols.resize(nx * nz)
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		for i in nx:
			heights[j * nx + i] = _height(Vector2(xs[i], zs[j]))
	for j in nz:
		for i in nx:
			var k: int = j * nx + i
			var h: float = heights[k]
			var hx0: float = heights[j * nx + maxi(i - 1, 0)]
			var hx1: float = heights[j * nx + mini(i + 1, nx - 1)]
			var hz0: float = heights[maxi(j - 1, 0) * nx + i]
			var hz1: float = heights[mini(j + 1, nz - 1) * nx + i]
			var dx: float = maxf(xs[mini(i + 1, nx - 1)] - xs[maxi(i - 1, 0)], 0.01)
			var dz: float = maxf(zs[mini(j + 1, nz - 1)] - zs[maxi(j - 1, 0)], 0.01)
			var n := Vector3(-(hx1 - hx0) / dx, 1.0, -(hz1 - hz0) / dz).normalized()
			verts[k] = Vector3(xs[i], h, zs[j])
			norms[k] = n
			var p2 := Vector2(xs[i], zs[j])
			cols[k] = _terrain_color(h, 1.0 - n.y + absf((hx1 - hx0) / dx) * 0.5, p2, _weights(p2).x if h < WATER_Y + 1.0 else 0.0)
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var inside: bool = xs[i] >= rect.position.x - 0.01 and xs[i + 1] <= rect.end.x + 0.01 \
					and zs[j] >= rect.position.y - 0.01 and zs[j + 1] <= rect.end.y + 0.01
			if inside:
				continue
			var a: int = j * nx + i
			var b: int = a + 1
			var c: int = a + nx
			var e: int = c + 1
			idx.append_array([a, b, e, a, e, c])  # zgodnie z ruchem wskazówek (widok z góry)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gen.add_child(mi)


func _build_water() -> void:
	var has_port: bool = false
	for m in ring:
		if types[m] == PORT:
			has_port = true
	if not has_port:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)  # morze aż po horyzont
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	for k in 2:
		var noise := FastNoiseLite.new()
		noise.seed = 17 + k
		noise.frequency = 0.02 + k * 0.015
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 6.0
		tex.noise = noise
		mat.set_shader_parameter("waves_a" if k == 0 else "waves_b", tex)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(rect.get_center().x, WATER_Y, rect.get_center().y)
	gen.add_child(mi)


## Las: tuż przy mieście prawdziwe drzewa, dalej proste drzewka (MultiMesh, bez cieni),
## na brzegu wody kamienie.
func _build_forest() -> void:
	_tree_mesh = [_cone_tree_mesh(), _round_tree_mesh()]
	var near := Rect2(rect.position - Vector2(50, 50), rect.size + Vector2(100, 100))
	var far_batches: Dictionary = {}
	var step: float = 7.5
	var x: float = rect.position.x - 820.0
	while x < rect.end.x + 820.0:
		var z: float = rect.position.y - 820.0
		while z < rect.end.y + 820.0:
			var p := Vector2(x + _rng.randf_range(-3.0, 3.0), z + _rng.randf_range(-3.0, 3.0))
			var d: float = _out_dist(p)
			var in_near: bool = near.has_point(p)
			if d > 5.0 and (in_near or (int(x / step) % 2 == 0 and int(z / step) % 2 == 0)):
				var h: float = _height(p)
				var dens: float = _forest_density(p, h)
				if in_near:
					if h > WATER_Y - 0.6 and h < WATER_Y + 0.7 and _rng.randf() < 0.18:
						gen._add(WorldGenerator.NATURE % ["Rock_1_A_Color1", "Rock_2_A_Color1", "Rock_3_A_Color1", "Rock_1_E_Color1"][_rng.randi_range(0, 3)],
								Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(2.0, 4.0)), Vector3(p.x, h - 0.3, p.y)))
					elif _rng.randf() < dens * 0.8:
						gen._add(WorldGenerator.NATURE % WorldGenerator.TREES[_rng.randi_range(0, WorldGenerator.TREES.size() - 1)],
								Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(1.5, 2.3)), Vector3(p.x, h - 0.2, p.y)))
				elif _rng.randf() < dens:
					var key := Vector2i(floori(p.x / 150.0), floori(p.y / 150.0))
					var kind: int = 0 if _rng.randf() < 0.6 else 1
					if not far_batches.has(key):
						far_batches[key] = [[], []]
					var s: float = _rng.randf_range(7.0, 12.0)
					var tint := Color(0.85, 0.95, 0.85).lerp(Color(0.6, 0.75, 0.55), _rng.randf())
					far_batches[key][kind].append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.3), s)), Vector3(p.x, h - 0.3, p.y)), tint])
			z += step
		x += step
	for key: Vector2i in far_batches:
		for kind in 2:
			var list: Array = far_batches[key][kind]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = _tree_mesh[kind]
			mm.instance_count = list.size()
			for k in list.size():
				mm.set_instance_transform(k, list[k][0])
				mm.set_instance_color(k, list[k][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gen.add_child(mmi)


func _cone_tree_mesh() -> ArrayMesh:
	var st := _TreeBuilder.new()
	st.prism(Vector3.ZERO, 0.06, 0.25, 5, Color(0.4, 0.28, 0.18))
	st.cone(Vector3(0, 0.18, 0), 0.32, 0.55, 7, Color(0.27, 0.5, 0.3))
	st.cone(Vector3(0, 0.48, 0), 0.24, 0.52, 7, Color(0.3, 0.55, 0.32))
	return st.commit()


func _round_tree_mesh() -> ArrayMesh:
	var st := _TreeBuilder.new()
	st.prism(Vector3.ZERO, 0.06, 0.35, 5, Color(0.42, 0.3, 0.2))
	st.blob(Vector3(0, 0.62, 0), 0.34, Color(0.36, 0.58, 0.3))
	return st.commit()


## Mini-konstruktor siatek drzewek (kilkadziesiąt trójkątów na drzewko).
class _TreeBuilder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n: Vector3 = (c - a).cross(b - a).normalized()
		for v: Vector3 in [a, b, c]:
			verts.append(v)
			norms.append(n)
			cols.append(col)

	func prism(base: Vector3, r: float, h: float, sides: int, col: Color) -> void:
		for k in sides:
			var a0: float = TAU * k / sides
			var a1: float = TAU * (k + 1) / sides
			var p0: Vector3 = base + Vector3(cos(a0) * r, 0, sin(a0) * r)
			var p1: Vector3 = base + Vector3(cos(a1) * r, 0, sin(a1) * r)
			_tri(p0, p1, p1 + Vector3(0, h, 0), col)
			_tri(p0, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), col)

	func cone(base: Vector3, r: float, h: float, sides: int, col: Color) -> void:
		var top: Vector3 = base + Vector3(0, h, 0)
		for k in sides:
			var a0: float = TAU * k / sides
			var a1: float = TAU * (k + 1) / sides
			var p0: Vector3 = base + Vector3(cos(a0) * r, 0, sin(a0) * r)
			var p1: Vector3 = base + Vector3(cos(a1) * r, 0, sin(a1) * r)
			_tri(p0, p1, top, col)
			_tri(p1, p0, base, col.darkened(0.3))

	func blob(c: Vector3, r: float, col: Color) -> void:
		var rings: int = 4
		var sides: int = 7
		for i in rings:
			var t0: float = PI * i / rings
			var t1: float = PI * (i + 1) / rings
			for k in sides:
				var a0: float = TAU * k / sides
				var a1: float = TAU * (k + 1) / sides
				var p := func(t: float, a: float) -> Vector3:
					return c + Vector3(sin(t) * cos(a) * r, cos(t) * r * 0.9, sin(t) * sin(a) * r)
				_tri(p.call(t0, a0), p.call(t1, a0), p.call(t1, a1), col)
				_tri(p.call(t0, a0), p.call(t1, a1), p.call(t0, a1), col)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 1.0
		mesh.surface_set_material(0, mat)
		return mesh
