class_name Van
extends VehicleBody3D
## Dostawczak do przeprowadzek (model "delivery" z Kenney Car Kit).
##
## - 4 miejsca: kierowca, pasażer i półka do siedzenia na 2 osoby w pace.
## - Tylne drzwi otwierają się w dół i robią za rampę (E, patrząc na drzwi).
## - Paka to strefa załadunku dla JobManagera (`cargo_zone`).
##
## SIEĆ (tak jak przedmioty): fizykę jazdy liczy wyłącznie host. Kierowca wysyła
## hostowi swoje wejście (gaz, skręt, ręczny), host jedzie i rozsyła pozycję, a klienci
## tylko interpolują. Miejsca i stan drzwi też zmienia tylko host (gracze proszą RPC).
##
## Wszystko (koła, kolizja, drzwi, półka) budujemy w kodzie z modelu, więc scena
## pojazdu to tylko ten skrypt na VehicleBody3D.

const MODEL: PackedScene = preload("res://assets/models/cars/delivery.glb")
## Skala modelu: 1 jednostka Car Kit = 2,3 m, żeby w pace stanął dorosły (2,3 m wysokości).
const S: float = 2.3

enum { SEAT_DRIVER, SEAT_PASSENGER, SEAT_BENCH_L, SEAT_BENCH_R }
const SEAT_COUNT: int = 4
const SEAT_LABELS: Array[String] = ["za kierownicę", "jako pasażer", "na półkę", "na półkę"]

@export_group("Napęd")
@export var vehicle_mass: float = 2500.0
## Siła silnika na każde z dwóch tylnych kół [N] (razem ~3,4 m/s² na pusto).
@export var engine_force_max: float = 4200.0
@export var max_speed_kmh: float = 70.0
@export var reverse_speed_kmh: float = 15.0
## Hamulec (wartość Godota ~ impuls na koło na klatkę; 60 ≈ 5-6 m/s² przy 2,5 t).
@export var brake_strength: float = 60.0
@export var handbrake_strength: float = 90.0
## Hamowanie silnikiem, gdy nic nie wciskamy.
@export var engine_braking: float = 3.0
## Opór powietrza F = c·v² i toczenia F = c·m·g.
@export var drag_coefficient: float = 2.0
@export var rolling_resistance: float = 0.015

@export_group("Skręt")
@export var max_steer: float = 0.6
## Maks. skręt przy prędkości maksymalnej (żeby nie wywracać się na zakrętach).
@export var high_speed_steer: float = 0.18
@export var steer_rate: float = 1.6  ## rad/s
@export var steer_return_rate: float = 2.4

@export_group("Inne")
## Od tej prędkości [m/s] potrącony gracz się przewraca.
@export var knock_speed: float = 3.0
@export var door_open_time: float = 0.9
## Po ilu sekundach bez wejścia od kierowcy host uznaje, że puścił pedały.
@export var input_timeout: float = 0.4

## Replikowane z hosta:
var net_position: Vector3
var net_rotation: Quaternion = Quaternion.IDENTITY
var net_speed: float = 0.0  ## prędkość do przodu [m/s] (koła, prędkościomierz)
var net_steer: float = 0.0
var net_door_open: bool = false
## peer_id na każdym miejscu (0 = wolne).
var net_seats: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

var net_sync: MultiplayerSynchronizer
var cargo_zone: Area3D

var _door: AnimatableBody3D
var _door_angle: float = 0.0  ## 0 = zamknięte, 1 = otwarte
var _wheels: Array[VehicleWheel3D] = []
var _wheel_meshes: Array[Node3D] = []
var _wheel_spin: float = 0.0
var _bump_area: Area3D
var _bump_timer: float = 0.0

# Tylko host: ostatnie wejście kierowcy.
var _in_throttle: float = 0.0
var _in_steer: float = 0.0
var _in_handbrake: bool = false
var _in_stamp: float = -100.0

# Wymiary w jednostkach modelu (mnożone przez S). Oś +Z = przód auta.
const WHEEL_RADIUS_U: float = 0.3
const SUSP_REST: float = 0.3
const SUSP_STIFFNESS: float = 30.0
const CARGO_FLOOR_U: float = 0.5
const CARGO_CEIL_U: float = 1.5
const CARGO_HALF_W_U: float = 0.55
const CARGO_BACK_U: float = -1.6
const CARGO_FRONT_U: float = 0.2
const HINGE_U: Vector3 = Vector3(0.0, 0.5, -1.55)
const BENCH_HEIGHT: float = 0.45  ## [m] nad podłogą paki
const BENCH_DEPTH: float = 0.45


func _ready() -> void:
	add_to_group("vehicles")
	process_physics_priority = -1  # przed graczami, żeby siedzący brali aktualną pozycję auta
	mass = vehicle_mass
	collision_layer = 1      # jak świat: gracze i przedmioty się od nas odbijają
	collision_mask = 1 | 4   # świat + przedmioty (graczy wykrywa _bump_area)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.75, 0.2)  # nisko, żeby nie przewracać się na zakrętach
	can_sleep = false

	var visual: Node3D = MODEL.instantiate()
	visual.name = "Model"
	visual.scale = Vector3.ONE * S
	add_child(visual)
	_build_wheels(visual)
	_build_door(visual)
	_build_collision()
	_build_bench()
	_build_zones()

	net_position = global_position
	net_rotation = global_basis.get_rotation_quaternion()
	_setup_sync()

	if multiplayer.is_server():
		Net.peer_left.connect(_server_free_seats_of)
		_set_brakes(engine_braking * 4.0, engine_braking * 4.0)  # zaparkowany stoi na hamulcu
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_drive(delta)
		_server_knock_players(delta)
		net_position = global_position
		net_rotation = global_basis.get_rotation_quaternion()
		net_speed = linear_velocity.dot(global_basis.z)
		net_steer = steering
	else:
		var t: float = 1.0 - exp(-18.0 * delta)
		global_position = global_position.lerp(net_position, t)
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(net_rotation, t))
		_client_wheel_visuals(delta)
	_animate_door(delta)


# --- API dla graczy ---------------------------------------------------------------

## Miejsce danego gracza albo -1.
func seat_of(peer_id: int) -> int:
	return net_seats.find(peer_id) if peer_id != 0 else -1


func driver_id() -> int:
	return net_seats[SEAT_DRIVER]


func speed_kmh() -> float:
	return absf(net_speed) * 3.6


## Gdzie stoją stopy siedzącego gracza i w którą stronę patrzy (forward = -Z bazy).
func seat_transform(seat: int) -> Transform3D:
	var local: Transform3D
	match seat:
		SEAT_DRIVER, SEAT_PASSENGER:
			var side: float = 1.0 if seat == SEAT_DRIVER else -1.0  # kierowca po lewej (+X)
			local = Transform3D(Basis(Vector3.UP, PI), Vector3(0.32 * S * side, 1.12 * S - 0.9, 0.72 * S))
		_:
			var side: float = 1.0 if seat == SEAT_BENCH_L else -1.0
			var seat_top: float = CARGO_FLOOR_U * S + BENCH_HEIGHT
			var z: float = CARGO_FRONT_U * S - BENCH_DEPTH * 0.5
			local = Transform3D(Basis.IDENTITY, Vector3(0.6 * side, seat_top + 0.75 - 0.9, z))
	return global_transform * local


## Punkty wysiadania (kilka, na wypadek gdyby pierwszy był zastawiony).
func exit_points(seat: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	match seat:
		SEAT_DRIVER, SEAT_PASSENGER:
			var side: float = 1.0 if seat == SEAT_DRIVER else -1.0
			pts.append(Vector3((0.75 * S + 0.6) * side, 0.1, 0.75 * S))
			pts.append(Vector3((0.75 * S + 0.6) * side, 0.1, -0.3 * S))
			pts.append(Vector3((0.75 * S + 0.6) * -side, 0.1, 0.75 * S))
			pts.append(Vector3(0, 0.1, 1.65 * S + 0.8))
		_:
			var side: float = 1.0 if seat == SEAT_BENCH_L else -1.0
			pts.append(Vector3(0.6 * side, CARGO_FLOOR_U * S + 0.05, CARGO_FRONT_U * S - BENCH_DEPTH - 0.6))
			pts.append(Vector3(0, CARGO_FLOOR_U * S + 0.05, -0.7 * S))
			pts.append(Vector3(0, 0.1, CARGO_BACK_U * S - 3.2))  # za rampą
	var out: Array[Vector3] = []
	for p in pts:
		out.append(global_transform * p)
	return out


## Najbliższa akcja w promieniu wzroku: {id, text, distance} albo pusty słownik.
func find_interaction(from: Vector3, dir: Vector3, reach: float, peer_id: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF
	for entry: Dictionary in _interaction_points(peer_id):
		var p: Vector3 = global_transform * (entry["pos"] as Vector3)
		var along: float = (p - from).dot(dir)
		if along < 0.0 or along > reach:
			continue
		var off: float = (from + dir * along).distance_to(p)
		if off > float(entry["radius"]):
			continue
		var score: float = off + along * 0.1
		if score < best_score:
			best_score = score
			best = {"id": entry["id"], "text": entry["text"], "distance": along}
	return best


func request_interact(action: String) -> void:
	if multiplayer.is_server():
		_server_interact(multiplayer.get_unique_id(), action)
	else:
		rpc_interact.rpc_id(1, action)


func request_exit() -> void:
	request_interact("exit")


## Kierowca woła co klatkę fizyki.
func send_drive_input(throttle: float, steer: float, handbrake: bool) -> void:
	if multiplayer.is_server():
		_server_set_input(multiplayer.get_unique_id(), throttle, steer, handbrake)
	else:
		rpc_drive_input.rpc_id(1, throttle, steer, handbrake)


## Kogo obciążyć za szkodę przedmiotu, którego nikt nie trzyma: kierowcę, jeśli
## przedmiot jedzie w pace. 0 = nikogo.
func blame_for_item(item: Node3D) -> int:
	if driver_id() == 0 or cargo_zone == null:
		return 0
	return driver_id() if cargo_zone.overlaps_body(item) else 0


## Czy punkt (np. stopy gracza) jest w pace.
func is_in_cargo(world_point: Vector3) -> bool:
	var p: Vector3 = global_transform.affine_inverse() * world_point
	return absf(p.x) < CARGO_HALF_W_U * S + 0.1 and p.z > CARGO_BACK_U * S - 0.2 \
			and p.z < CARGO_FRONT_U * S and p.y > CARGO_FLOOR_U * S - 0.5


# --- RPC (wykonują się na hoście) -------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_interact(action: String) -> void:
	if multiplayer.is_server():
		_server_interact(multiplayer.get_remote_sender_id(), action)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_drive_input(throttle: float, steer: float, handbrake: bool) -> void:
	if multiplayer.is_server():
		_server_set_input(multiplayer.get_remote_sender_id(), throttle, steer, handbrake)


func _server_interact(peer_id: int, action: String) -> void:
	var seats := net_seats.duplicate()
	if action == "exit":
		var i: int = seats.find(peer_id)
		if i >= 0:
			seats[i] = 0
	elif action == "door":
		net_door_open = not net_door_open
	elif action.begins_with("seat"):
		var i: int = int(action.substr(4))
		if i >= 0 and i < SEAT_COUNT and seats[i] == 0 and seats.find(peer_id) == -1:
			seats[i] = peer_id
	net_seats = seats


func _server_set_input(peer_id: int, throttle: float, steer: float, handbrake: bool) -> void:
	if peer_id != driver_id():
		return
	_in_throttle = clampf(throttle, -1.0, 1.0)
	_in_steer = clampf(steer, -1.0, 1.0)
	_in_handbrake = handbrake
	_in_stamp = Time.get_ticks_msec() / 1000.0


func _server_free_seats_of(peer_id: int) -> void:
	var seats := net_seats.duplicate()
	var i: int = seats.find(peer_id)
	if i >= 0:
		seats[i] = 0
		net_seats = seats


# --- Jazda (host) ---------------------------------------------------------------------

func _server_drive(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var has_driver: bool = driver_id() != 0
	if not has_driver or now - _in_stamp > input_timeout:
		_in_throttle = 0.0
		_in_steer = 0.0
		_in_handbrake = false

	var forward: Vector3 = global_basis.z
	var speed: float = linear_velocity.dot(forward)  # + do przodu, - do tyłu
	var max_fwd: float = max_speed_kmh / 3.6
	var max_rev: float = reverse_speed_kmh / 3.6

	var force: float = 0.0
	var brake_value: float = 0.0
	if _in_throttle > 0.05:
		if speed < -0.5:
			brake_value = brake_strength * _in_throttle  # jedziemy do tyłu - W hamuje
		else:
			force = engine_force_max * _in_throttle * _torque_curve(speed / max_fwd)
	elif _in_throttle < -0.05:
		if speed > 0.5:
			brake_value = brake_strength * -_in_throttle  # jedziemy do przodu - S hamuje
		else:
			force = -engine_force_max * 0.6 * -_in_throttle * _torque_curve(-speed / max_rev)
	else:
		brake_value = engine_braking if has_driver else engine_braking * 4.0
	engine_force = force
	# Ręczny blokuje tylne koła (przy prędkości zarzuca tyłem).
	_set_brakes(brake_value, maxf(brake_value, handbrake_strength if _in_handbrake else 0.0))

	# Skręt: im szybciej, tym mniejszy maksymalny kąt; powrót do zera szybszy.
	var speed_ratio: float = clampf(absf(speed) / max_fwd, 0.0, 1.0)
	var steer_limit: float = lerpf(max_steer, high_speed_steer, speed_ratio)
	var target: float = _in_steer * steer_limit
	var rate: float = steer_rate if absf(target) > absf(steering) else steer_return_rate
	steering = move_toward(steering, target, rate * delta)

	# Opory: powietrze (rośnie z kwadratem prędkości) i toczenie.
	var v: Vector3 = linear_velocity
	v.y = 0.0
	if v.length() > 0.1:
		var resist: float = drag_coefficient * v.length_squared() + rolling_resistance * mass * 9.8
		apply_central_force(-v.normalized() * resist)


func _set_brakes(front: float, rear: float) -> void:
	for wheel in _wheels:
		wheel.brake = front if wheel.use_as_steering else rear


## Silnik ciągnie najmocniej przy małej prędkości i słabnie do zera przy maksymalnej.
func _torque_curve(ratio: float) -> float:
	ratio = clampf(ratio, 0.0, 1.0)
	return clampf(1.0 - ratio * ratio, 0.0, 1.0)


## Potrącenie: gracz w pobliżu jadącego auta (nie w środku) się przewraca.
func _server_knock_players(delta: float) -> void:
	_bump_timer -= delta
	if _bump_timer > 0.0:
		return
	_bump_timer = 0.1
	var vel: Vector3 = linear_velocity
	if vel.length() < knock_speed:
		return
	for body in _bump_area.get_overlapping_bodies():
		var player := body as Player
		if player == null or seat_of(player.get_multiplayer_authority()) >= 0:
			continue
		if is_in_cargo(player.global_position):
			continue
		var away: Vector3 = player.global_position - global_position
		away.y = 0.0
		if away.normalized().dot(vel.normalized()) < 0.2:
			continue  # auto od niego odjeżdża
		var push: Vector3 = vel + away.normalized() * 2.0 + Vector3.UP * 2.0
		player.request_knockdown(push, player.down_duration)


# --- Wygląd u klientów -------------------------------------------------------------

func _client_wheel_visuals(delta: float) -> void:
	_wheel_spin += net_speed / (WHEEL_RADIUS_U * S) * delta
	for i in _wheel_meshes.size():
		var steer: float = net_steer if _wheels[i].use_as_steering else 0.0
		_wheel_meshes[i].rotation = Vector3(_wheel_spin, steer, 0.0)


func _animate_door(delta: float) -> void:
	_door_angle = move_toward(_door_angle, 1.0 if net_door_open else 0.0, delta / door_open_time)
	# Otwarte drzwi opierają się końcem o ziemię (kąt zależy od wysokości zawiasu).
	var length: float = 1.0 * S
	var hinge_h: float = _door.global_position.y - _ground_height_below(_door.global_position)
	var down: float = asin(clampf((hinge_h - 0.04) / length, 0.0, 1.0))
	var open_angle: float = PI * 0.5 + down
	var eased: float = _door_angle * _door_angle * (3.0 - 2.0 * _door_angle)
	_door.rotation = Vector3(-open_angle * eased, 0.0, 0.0)


func _ground_height_below(p: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.1, p + Vector3.DOWN * 4.0, 1)
	query.exclude = [get_rid(), _door.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else p.y - CARGO_FLOOR_U * S


# --- Budowa ---------------------------------------------------------------------------

func _interaction_points(peer_id: int) -> Array[Dictionary]:
	var pts: Array[Dictionary] = []
	if seat_of(peer_id) >= 0:
		return pts
	for side: int in [SEAT_DRIVER, SEAT_PASSENGER]:
		var x: float = (0.76 if side == SEAT_DRIVER else -0.76) * S
		pts.append({"id": "seat%d" % side, "pos": Vector3(x, 1.0 * S, 0.78 * S), "radius": 1.0,
				"text": _seat_text(side)})
	var door_pos: Vector3 = Vector3(0, 1.0 * S, CARGO_BACK_U * S) if not net_door_open \
			else Vector3(0, CARGO_FLOOR_U * S, CARGO_BACK_U * S - 0.4)
	pts.append({"id": "door", "pos": door_pos, "radius": 1.2,
			"text": "Zamknij pakę" if net_door_open else "Otwórz pakę"})
	for side: int in [SEAT_BENCH_L, SEAT_BENCH_R]:
		var t: Transform3D = global_transform.affine_inverse() * seat_transform(side)
		pts.append({"id": "seat%d" % side, "pos": t.origin + Vector3(0, 0.4, 0), "radius": 0.5,
				"text": _seat_text(side)})
	return pts


func _seat_text(seat: int) -> String:
	if net_seats[seat] != 0:
		return "Zajęte (%s)" % Net.get_player_name(net_seats[seat])
	return "Wsiądź " + SEAT_LABELS[seat]


func _build_wheels(visual: Node3D) -> void:
	var sag: float = 9.8 / (2.0 * SUSP_STIFFNESS)  # ugięcie zawieszenia pod ciężarem (zmierzone)
	var names: Dictionary = {"wheel-front-left": "WheelFL", "wheel-front-right": "WheelFR",
			"wheel-back-left": "WheelBL", "wheel-back-right": "WheelBR"}
	for wheel_name: String in names:
		var mesh := visual.get_node(wheel_name) as MeshInstance3D
		var mesh_center: Vector3 = mesh.get_aabb().get_center()  # środek siatki w jej układzie
		var center: Vector3 = (mesh.position + mesh_center) * S
		var front: bool = wheel_name.begins_with("wheel-front")

		var wheel := VehicleWheel3D.new()
		wheel.name = names[wheel_name]
		wheel.use_as_steering = front
		wheel.use_as_traction = not front  # napęd na tył
		wheel.wheel_radius = WHEEL_RADIUS_U * S
		wheel.wheel_rest_length = SUSP_REST
		wheel.suspension_travel = 0.25
		wheel.suspension_stiffness = SUSP_STIFFNESS
		wheel.suspension_max_force = vehicle_mass * 9.8 * 3.0
		wheel.damping_compression = 0.45
		wheel.damping_relaxation = 0.6
		wheel.wheel_friction_slip = 2.6
		wheel.wheel_roll_influence = 0.12
		# Koło (ośka zawieszenia) wyżej o tyle, ile auto osiądzie - wtedy stoi jak w modelu.
		wheel.position = center + Vector3.UP * ((SUSP_REST - sag) if multiplayer.is_server() else 0.0)
		add_child(wheel)
		_wheels.append(wheel)

		# Siatka pod pomocniczym węzłem: u klientów obracamy go ręcznie (skręt i toczenie),
		# u hosta obraca się samo VehicleWheel3D. Środek siatki = oś koła.
		var holder := Node3D.new()
		holder.name = "Visual"
		wheel.add_child(holder)
		mesh.reparent(holder, false)
		mesh.scale = Vector3.ONE * S
		mesh.position = -mesh_center * S
		_wheel_meshes.append(holder)


func _build_door(visual: Node3D) -> void:
	_door = AnimatableBody3D.new()
	_door.name = "RearDoor"
	_door.collision_layer = 1
	_door.collision_mask = 0
	# Bez tego drzwi (ciało kinematyczne) nie jadą razem z autem, tylko zostają w miejscu.
	_door.sync_to_physics = false
	_door.position = HINGE_U * S
	add_child(_door)
	add_collision_exception_with(_door)
	var mesh := visual.get_node("door") as Node3D
	mesh.reparent(_door, true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.0, 0.09) * S
	shape.shape = box
	# Pudło od zawiasu na zewnątrz: po otwarciu wewnętrzna strona drzwi (po której się
	# wchodzi) leży równo z podłogą paki i dotyka ziemi - bez progu na końcu rampy.
	shape.position = Vector3(0, 0.5 * S, -box.size.z * 0.5)
	_door.add_child(shape)


func _build_collision() -> void:
	# Pudła [min, max] w jednostkach modelu. Paka jest pusta w środku.
	var boxes: Array = [
		[Vector3(-0.72, 0.22, -1.55), Vector3(0.72, 0.5, 1.58)],    # podwozie + podłoga (do zawiasu)
		[Vector3(0.55, 0.5, -1.62), Vector3(0.74, 1.62, 0.45)],     # lewa ściana paki
		[Vector3(-0.74, 0.5, -1.62), Vector3(-0.55, 1.62, 0.45)],   # prawa ściana paki
		[Vector3(-0.74, 1.5, -1.62), Vector3(0.74, 1.64, 0.45)],    # dach paki
		[Vector3(-0.74, 0.5, 0.2), Vector3(0.74, 1.5, 0.45)],       # ściana przy kabinie
		[Vector3(-0.74, 0.5, 0.45), Vector3(0.74, 1.38, 1.2)],      # kabina
		[Vector3(-0.66, 0.22, 1.2), Vector3(0.66, 0.72, 1.62)],     # maska
		[Vector3(0.275, 0.5, -0.9), Vector3(0.55, 0.7, 0.2)],       # nadkole lewe
		[Vector3(-0.55, 0.5, -0.9), Vector3(-0.275, 0.7, 0.2)],     # nadkole prawe
	]
	for b: Array in boxes:
		_add_box(b[0] * S, b[1] * S)


func _add_box(min_p: Vector3, max_p: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = max_p - min_p
	shape.shape = box
	shape.position = (min_p + max_p) * 0.5
	add_child(shape)


## Półka do siedzenia dla 2 osób przy ścianie kabiny (twarzą do drzwi).
func _build_bench() -> void:
	var floor_y: float = CARGO_FLOOR_U * S
	var front_z: float = CARGO_FRONT_U * S
	var half_w: float = CARGO_HALF_W_U * S - 0.05
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.45, 0.3)
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(0.25, 0.32, 0.4)

	var top := Vector3(half_w, floor_y + BENCH_HEIGHT, front_z)
	var seat_min := Vector3(-half_w, floor_y + BENCH_HEIGHT - 0.06, front_z - BENCH_DEPTH)
	_add_visual_box(seat_min, top, wood)
	_add_box(seat_min, top)
	# Wsporniki i oparcie (sama grafika).
	for x: float in [-half_w + 0.1, 0.0, half_w - 0.1]:
		_add_visual_box(Vector3(x - 0.03, floor_y, front_z - BENCH_DEPTH + 0.05),
				Vector3(x + 0.03, floor_y + BENCH_HEIGHT - 0.06, front_z - BENCH_DEPTH + 0.11), wood)
	_add_visual_box(Vector3(-half_w, floor_y + BENCH_HEIGHT + 0.15, front_z - 0.08),
			Vector3(half_w, floor_y + BENCH_HEIGHT + 0.6, front_z), pad)


func _add_visual_box(min_p: Vector3, max_p: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = max_p - min_p
	mesh.material = material
	mi.mesh = mesh
	mi.position = (min_p + max_p) * 0.5
	add_child(mi)


func _build_zones() -> void:
	cargo_zone = Area3D.new()
	cargo_zone.name = "CargoZone"
	cargo_zone.collision_layer = 0
	cargo_zone.collision_mask = 4  # przedmioty
	cargo_zone.monitorable = false
	var min_p := Vector3(-CARGO_HALF_W_U, CARGO_FLOOR_U, CARGO_BACK_U) * S
	var max_p := Vector3(CARGO_HALF_W_U, CARGO_CEIL_U, CARGO_FRONT_U) * S
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = max_p - min_p
	shape.shape = box
	shape.position = (min_p + max_p) * 0.5
	cargo_zone.add_child(shape)
	add_child(cargo_zone)

	_bump_area = Area3D.new()
	_bump_area.name = "BumpArea"
	_bump_area.collision_layer = 0
	_bump_area.collision_mask = 2  # gracze
	_bump_area.monitorable = false
	var bump_shape := CollisionShape3D.new()
	var bump_box := BoxShape3D.new()
	bump_box.size = Vector3(1.7, 1.7, 3.4) * S
	bump_shape.shape = bump_box
	bump_shape.position = Vector3(0, 0.85, 0) * S
	_bump_area.add_child(bump_shape)
	add_child(_bump_area)


func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop: String in [":net_position", ":net_rotation", ":net_speed", ":net_steer", ":net_door_open", ":net_seats"]:
		var path := NodePath(prop)
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	net_sync = MultiplayerSynchronizer.new()
	net_sync.name = "NetSync"
	net_sync.replication_config = cfg
	net_sync.replication_interval = 1.0 / 30.0
	# Jak przy przedmiotach: host włącza widoczność dla peera, gdy ten wczyta poziom.
	net_sync.public_visibility = not multiplayer.is_server()
	add_child(net_sync)
