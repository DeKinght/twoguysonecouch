class_name HighwayTraffic
extends Node3D
## Auta jadące estakadą obwodnicy (czysta dekoracja, liczona lokalnie u każdego gracza).
## Każda trasa to łamana (punkty co ~4,5 m). Auta jadą swoim pasem, na końcu trasy
## (w tunelu albo we mgle) wracają na jej początek. Kilkanaście transformacji na klatkę.

const CARS: Array[String] = ["car_sedan", "car_hatchback", "car_stationwagon", "car_taxi", "car_police"]
const LANES: Array[float] = [1.6, 4.6]   ## odległość pasa od osi jezdni [m]
const SPACING: float = 75.0              ## średnio jedno auto na tyle metrów pasa

var deck_height: float = 7.0
## [{points: PackedVector3Array, lengths: PackedFloat32Array, closed: bool}]
var _paths: Array = []
## [{node, path, dist, speed, lane, dir}]
var _cars: Array = []


func setup(paths: Array, height: float, seed: int) -> void:
	deck_height = height
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for entry: Array in paths:
		var pts: PackedVector3Array = entry[0]
		var lengths := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			lengths.append(lengths[i - 1] + pts[i].distance_to(pts[i - 1]))
		var total: float = lengths[lengths.size() - 1]
		if total < 40.0:
			continue
		_paths.append({"points": pts, "lengths": lengths, "closed": entry[1], "total": total})
	for p in _paths.size():
		var total: float = _paths[p]["total"]
		for dir: int in [1, -1]:
			for lane: float in LANES:
				var count: int = int(total / SPACING / 2.0) + 1
				for k in count:
					var car: Node3D = (load("res://assets/models/city/%s.gltf" % CARS[rng.randi_range(0, CARS.size() - 1)]) as PackedScene).instantiate()
					car.scale = Vector3.ONE * 4.5
					add_child(car)
					_cars.append({"node": car, "path": p, "dist": rng.randf() * total,
							"speed": rng.randf_range(19.0, 27.0) * (0.85 if lane > 3.0 else 1.0),
							"lane": lane * dir, "dir": dir})


func _process(delta: float) -> void:
	for car: Dictionary in _cars:
		var path: Dictionary = _paths[car["path"]]
		var total: float = path["total"]
		var dist: float = car["dist"] + car["speed"] * delta * car["dir"]
		dist = fposmod(dist, total)
		car["dist"] = dist
		var frame: Array = _sample(path, dist)
		var pos: Vector3 = frame[0]
		var tangent: Vector3 = frame[1] * float(car["dir"])
		var right: Vector3 = tangent.cross(Vector3.UP).normalized()
		var node: Node3D = car["node"]
		node.global_position = pos + right * absf(car["lane"]) + Vector3(0, deck_height + 0.3, 0)
		node.global_basis = Basis(Vector3.UP, atan2(tangent.x, tangent.z)).scaled(Vector3.ONE * 4.5)


## [punkt, kierunek] na trasie w odległości `dist` (wyszukiwanie binarne po długościach).
func _sample(path: Dictionary, dist: float) -> Array:
	var lengths: PackedFloat32Array = path["lengths"]
	var pts: PackedVector3Array = path["points"]
	var i: int = clampi(lengths.bsearch(dist) - 1, 0, pts.size() - 2)
	var seg: float = maxf(lengths[i + 1] - lengths[i], 0.001)
	var t: float = clampf((dist - lengths[i]) / seg, 0.0, 1.0)
	var a: Vector3 = pts[i]
	var b: Vector3 = pts[i + 1]
	return [a.lerp(b, t), (b - a).normalized()]
