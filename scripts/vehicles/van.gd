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
## Wszystko (koła, kolizja, drzwi, półka, wnętrze kabiny, szyby, dźwięki) budujemy
## w kodzie z modelu, więc scena pojazdu to tylko ten skrypt na VehicleBody3D.

const MODEL: PackedScene = preload("res://assets/models/cars/delivery.glb")
## Skala modelu: 1 jednostka Car Kit = 1,84 m (paka 1,84 m wysokości - dorosły się zmieści).
const S: float = 1.84
const SOUND_DIR: String = "res://assets/audio/van/"

enum { SEAT_DRIVER, SEAT_PASSENGER, SEAT_BENCH_L, SEAT_BENCH_R }
const SEAT_COUNT: int = 4
const SEAT_LABELS: Array[String] = ["za kierownicę", "jako pasażer", "na półkę", "na półkę"]

@export_group("Napęd")
@export var vehicle_mass: float = 1800.0
## Siła silnika na każde z dwóch tylnych kół [N] (razem ~3,3 m/s² na pusto).
@export var engine_force_max: float = 3000.0
@export var max_speed_kmh: float = 70.0
@export var reverse_speed_kmh: float = 15.0
## Hamulec (wartość Godota ~ impuls na koło na klatkę; 45 ≈ 6 m/s² przy 1,8 t).
@export var brake_strength: float = 45.0
@export var handbrake_strength: float = 65.0
## Hamowanie silnikiem, gdy nic nie wciskamy.
@export var engine_braking: float = 3.0
## Opór powietrza F = c·v² i toczenia F = c·m·g.
@export var drag_coefficient: float = 2.0
@export var rolling_resistance: float = 0.015

@export_group("Skręt")
@export var max_steer: float = 0.6
## Maks. skręt przy prędkości maksymalnej (żeby nie wywracać się na zakrętach).
@export var high_speed_steer: float = 0.14
@export var steer_rate: float = 1.6  ## rad/s
@export var steer_return_rate: float = 2.4

@export_group("Inne")
## Od tej prędkości [m/s] potrącony gracz się przewraca.
@export var knock_speed: float = 3.0
@export var door_open_time: float = 0.9
## Po ilu sekundach bez wejścia od kierowcy host uznaje, że puścił pedały.
@export var input_timeout: float = 0.4

@export_group("Dźwięk")
@export var engine_volume_db: float = -4.0
## Prędkości [km/h], przy których skrzynia wrzuca wyższy bieg (do dźwięku i obrotów).
@export var gear_top_speeds: PackedFloat32Array = PackedFloat32Array([16.0, 32.0, 50.0, 72.0])

## Replikowane z hosta:
var net_position: Vector3
var net_rotation: Quaternion = Quaternion.IDENTITY
var net_speed: float = 0.0  ## prędkość do przodu [m/s] (koła, prędkościomierz)
var net_steer: float = 0.0
var net_throttle: float = 0.0  ## gaz kierowcy (-1..1) - do dźwięku silnika
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
var _steering_wheel: Node3D
var _start_transform: Transform3D

# Dźwięk (u każdego gracza, liczony z replikowanego stanu).
var _snd_idle: AudioStreamPlayer3D
var _snd_drive: AudioStreamPlayer3D
var _snd_start: AudioStreamPlayer3D
var _snd_gear: AudioStreamPlayer3D
var _snd_brake: AudioStreamPlayer3D
var _snd_door: Array[AudioStreamPlayer3D] = []  ## [lewe, prawe, tył]
var _engine_on: bool = false
var _engine_level: float = 0.0  ## 0..1, płynne wyciszanie po zgaszeniu
var _start_timer: float = 0.0
var _rpm: float = 0.0
var _gear: int = 0  ## -1 wsteczny, 0.. biegi do przodu
var _peak_speed: float = 0.0
var _prev_seats: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _prev_door_open: bool = false

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
## Poniżej tej wysokości auto uznajemy za spadnięte z mapy i stawiamy z powrotem na starcie.
const FALL_Y: float = -15.0
const BENCH_HEIGHT: float = 0.42  ## [m] nad podłogą paki
const BENCH_DEPTH: float = 0.4
const CAB_FLOOR_U: float = 0.45
const CAB_SEAT_TOP_U: float = 0.62
const CAB_SEAT_Z_U: float = 0.66


func _ready() -> void:
	add_to_group("vehicles")
	process_physics_priority = -1  # przed graczami, żeby siedzący brali aktualną pozycję auta
	mass = vehicle_mass
	collision_layer = 1      # jak świat: gracze i przedmioty się od nas odbijają
	collision_mask = 1 | 4   # świat + przedmioty (graczy wykrywa _bump_area)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.3, 0.15)  # nisko (ciężkie podwozie), żeby nie przewracać się na zakrętach
	can_sleep = false

	var visual: Node3D = MODEL.instantiate()
	visual.name = "Model"
	visual.scale = Vector3.ONE * S
	add_child(visual)
	_build_wheels(visual)
	_build_door(visual)
	_build_collision()
	_build_body_glass(visual)
	_build_cab_interior()
	_build_bench()
	_build_zones()
	_build_audio()

	net_position = global_position
	net_rotation = global_basis.get_rotation_quaternion()
	_start_transform = global_transform
	_setup_sync()

	if multiplayer.is_server():
		Net.peer_left.connect(_server_free_seats_of)
		_set_brakes(engine_braking * 4.0, engine_braking * 4.0)  # zaparkowany stoi na hamulcu
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if global_position.y < FALL_Y:
			_server_reset_position()
		_server_drive(delta)
		_server_knock_players(delta)
		net_position = global_position
		net_rotation = global_basis.get_rotation_quaternion()
		net_speed = linear_velocity.dot(global_basis.z)
		net_steer = steering
		net_throttle = _in_throttle
	else:
		var t: float = 1.0 - exp(-18.0 * delta)
		global_position = global_position.lerp(net_position, t)
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(net_rotation, t))
		_client_wheel_visuals(delta)
	_animate_door(delta)
	if _steering_wheel != null:
		# Obrót wokół osi kolumny kierowniczej (lokalne Y koła kierownicy), ~4x bardziej niż koła.
		_steering_wheel.rotation.y = net_steer * 4.0


func _process(delta: float) -> void:
	_update_audio(delta)


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
			# Oczy siedzącego ~0,65 m nad siedziskiem (postać kuca: oczy 0,9 m nad stopami).
			var feet_y: float = CAB_SEAT_TOP_U * S + 0.65 - 0.9
			local = Transform3D(Basis(Vector3.UP, PI), Vector3(0.32 * S * side, feet_y, CAB_SEAT_Z_U * S))
		_:
			var side: float = 1.0 if seat == SEAT_BENCH_L else -1.0
			var seat_top: float = CARGO_FLOOR_U * S + BENCH_HEIGHT
			var z: float = CARGO_FRONT_U * S - BENCH_DEPTH * 0.5
			local = Transform3D(Basis.IDENTITY, Vector3(0.45 * side, seat_top + 0.65 - 0.9, z))
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
			# Środkiem paki (po bokach są nadkola), od półki w stronę drzwi.
			for z: float in [-0.5, -1.0, -1.5, -2.0, -2.5]:
				pts.append(Vector3(0, CARGO_FLOOR_U * S + 0.01, CARGO_FRONT_U * S - BENCH_DEPTH + z + 0.1))
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


func _server_reset_position() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _start_transform
	net_position = global_position
	net_rotation = global_basis.get_rotation_quaternion()


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
		wheel.wheel_roll_influence = 0.04  # mniej = mniejszy przechył w zakręcie
		# Koło (ośka zawieszenia) wyżej o tyle, ile auto osiądzie - wtedy stoi jak w modelu.
		wheel.position = center + Vector3.UP * ((SUSP_REST - sag) if multiplayer.is_server() else 0.0)
		add_child(wheel)
		_wheels.append(wheel)

		# Siatka pod pomocniczym węzłem. U hosta siedzi w VehicleWheel3D (obraca się samo).
		# U klientów auto jest zamrożone i fizyka nie przesuwa kół - wtedy koła zostawałyby
		# w miejscu spawnu, więc podpinamy je pod karoserię i obracamy ręcznie.
		var holder := Node3D.new()
		holder.name = "Visual" + names[wheel_name]
		if multiplayer.is_server():
			wheel.add_child(holder)
		else:
			holder.position = center
			add_child(holder)
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


## Rozdziela karoserię na dwie części: nieprzezroczystą (widoczną też od środka - inaczej
## z kabiny widać przez ściany) i szyby (półprzezroczyste). Szyby w teksturze Kenney
## to jeden pasek koloru: u = 0.094, v = 0.77..0.98.
func _build_body_glass(visual: Node3D) -> void:
	var body := visual.get_node_or_null("body") as MeshInstance3D
	if body == null or not (body.mesh is ArrayMesh):
		return
	var src := body.mesh as ArrayMesh
	var arrays: Array = src.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var solid := PackedInt32Array()
	var glass := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var uv: Vector2 = (uvs[idx[t]] + uvs[idx[t + 1]] + uvs[idx[t + 2]]) / 3.0
		var is_glass: bool = absf(uv.x - 0.09375) < 0.004 and uv.y > 0.765 and uv.y < 0.985
		for k in 3:
			if is_glass:
				glass.append(idx[t + k])
			else:
				solid.append(idx[t + k])
	if glass.is_empty():
		return

	var mesh := ArrayMesh.new()
	var solid_arrays: Array = arrays.duplicate()
	solid_arrays[Mesh.ARRAY_INDEX] = solid
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, solid_arrays)
	var paint := (src.surface_get_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, paint)

	var glass_arrays: Array = arrays.duplicate()
	glass_arrays[Mesh.ARRAY_INDEX] = glass
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass_arrays)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.72, 0.86, 0.95, 0.18)
	glass_mat.roughness = 0.05
	glass_mat.metallic_specular = 0.9
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, glass_mat)
	body.mesh = mesh


## Wnętrze kabiny: podłoga, fotele, deska rozdzielcza, kierownica, tylna ściana.
func _build_cab_interior() -> void:
	var dark := _mat(Color(0.2, 0.21, 0.24))
	var seat := _mat(Color(0.28, 0.33, 0.42))
	var dash := _mat(Color(0.16, 0.17, 0.19))
	var trim := _mat(Color(0.55, 0.57, 0.62))
	var u := func(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> Array:
		return [Vector3(x0, y0, z0) * S, Vector3(x1, y1, z1) * S]

	var parts: Array = [
		# Wymiary dopasowane do skorupy kabiny (zmierzone w modelu): boki ~±0.53, dół przedniej
		# szyby przy z ~1.09, a nisko (y < 0.62) od z = 0.78 do przodu są nadkola - tam
		# wnętrze ma tylko ±0.33, inaczej widać je przez wycięcie na koło.
		[u.call(-0.5, CAB_FLOOR_U - 0.03, 0.47, 0.5, CAB_FLOOR_U, 0.78), dark],       # podłoga przy fotelach
		[u.call(-0.32, CAB_FLOOR_U - 0.03, 0.78, 0.32, CAB_FLOOR_U, 1.06), dark],     # podłoga między nadkolami
		# Ścianka między kabiną a paką: cofnięta do przedniej ściany paki (z = 0.2..0.22) i węższa
		# od paki (±0.54), więc z zewnątrz zasłaniają ją boki paki - nic nie wystaje.
		[u.call(-0.54, CAB_FLOOR_U, 0.2, 0.54, 1.5, 0.22), trim],
		[u.call(-0.52, 0.67, 0.98, 0.52, 0.77, 1.07), dash],                          # deska
		[u.call(-0.32, CAB_FLOOR_U, 1.0, 0.32, 0.67, 1.07), dark],                    # pod deską
		[u.call(-0.12, CAB_FLOOR_U, 0.5, 0.12, 0.6, 0.95), dark],                     # tunel
	]
	for side: float in [1.0, -1.0]:
		var x: float = 0.32 * side
		parts.append([u.call(x - 0.17, CAB_FLOOR_U, CAB_SEAT_Z_U - 0.14, x + 0.17, CAB_SEAT_TOP_U, CAB_SEAT_Z_U + 0.12), seat])
		parts.append([u.call(x - 0.17, CAB_SEAT_TOP_U, 0.48, x + 0.17, 1.12, 0.55), seat])   # oparcie
		parts.append([u.call(x - 0.1, 1.12, 0.49, x + 0.1, 1.2, 0.54), seat])                # zagłówek
	for part: Array in parts:
		_add_visual_box(part[0][0], part[0][1], part[1])

	# Zegary na desce (jasne kółka) i kierownica przed kierowcą.
	for dx: float in [-0.06, 0.06]:
		var gauge := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045 * S
		cyl.bottom_radius = 0.045 * S
		cyl.height = 0.01
		cyl.material = _mat(Color(0.85, 0.88, 0.92))
		gauge.mesh = cyl
		gauge.position = Vector3((0.32 + dx) * S, 0.772 * S, 1.02 * S)
		gauge.rotation = Vector3(deg_to_rad(-70), 0, 0)
		add_child(gauge)

	var column := Node3D.new()
	column.name = "SteeringColumn"
	column.position = Vector3(0.32 * S, 0.79 * S, 0.94 * S)
	column.rotation = Vector3(deg_to_rad(-55), 0, 0)  # kierownica pochylona do kierowcy
	add_child(column)
	_steering_wheel = Node3D.new()
	column.add_child(_steering_wheel)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.105 * S
	torus.outer_radius = 0.125 * S
	torus.material = dash
	rim.mesh = torus
	_steering_wheel.add_child(rim)
	var spoke := MeshInstance3D.new()
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(0.23 * S, 0.015 * S, 0.02 * S)
	spoke_mesh.material = trim
	spoke.mesh = spoke_mesh
	_steering_wheel.add_child(spoke)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.035 * S
	hub_mesh.bottom_radius = 0.035 * S
	hub_mesh.height = 0.04 * S
	hub_mesh.material = trim
	hub.mesh = hub_mesh
	_steering_wheel.add_child(hub)
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.02 * S
	shaft_mesh.bottom_radius = 0.025 * S
	shaft_mesh.height = 0.15 * S
	shaft_mesh.material = dash
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0, -0.075 * S, 0)
	column.add_child(shaft)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


# --- Dźwięk --------------------------------------------------------------------------

func _build_audio() -> void:
	_snd_idle = _make_player("engine_idle", Vector3(0, 0.6, 1.3) * S, true, 10.0)
	_snd_drive = _make_player("engine_drive", Vector3(0, 0.6, 1.3) * S, true, 12.0)
	_snd_start = _make_player("engine_start", Vector3(0, 0.6, 1.3) * S, false, 10.0)
	_snd_gear = _make_player("gear_shift", Vector3(0, 0.4, 0.6) * S, false, 5.0)
	_snd_brake = _make_player("brake_hiss", Vector3(0, 0.3, -0.6) * S, false, 7.0)
	_snd_door = [
		_make_player("cab_enter", Vector3(0.76, 0.8, 0.75) * S, false, 5.0),
		_make_player("cab_enter", Vector3(-0.76, 0.8, 0.75) * S, false, 5.0),
		_make_player("door_slam", HINGE_U * S + Vector3(0, 0.5, 0), false, 6.0),
	]
	_snd_idle.volume_db = -80.0
	_snd_drive.volume_db = -80.0


func _make_player(file: String, pos: Vector3, looped: bool, unit_size: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	var path: String = SOUND_DIR + file + ".ogg"
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if looped and stream is AudioStreamOggVorbis:
			stream = stream.duplicate()
			(stream as AudioStreamOggVorbis).loop = true
		player.stream = stream
	player.position = pos
	player.unit_size = unit_size
	player.max_distance = 90.0
	add_child(player)
	return player


func _play(player: AudioStreamPlayer3D, stream_file: String = "", pitch: float = 1.0) -> void:
	if stream_file != "":
		var path: String = SOUND_DIR + stream_file + ".ogg"
		if ResourceLoader.exists(path):
			player.stream = load(path)
	if player.stream == null:
		return
	player.pitch_scale = pitch
	player.play()


## Silnik i efekty liczone z replikowanego stanu - brzmi tak samo u wszystkich.
func _update_audio(delta: float) -> void:
	if _snd_idle == null:
		return
	# Wsiadanie / wysiadanie z kabiny i drzwi paki.
	for i in [SEAT_DRIVER, SEAT_PASSENGER]:
		if net_seats[i] != _prev_seats[i]:
			_play(_snd_door[i], "cab_enter" if net_seats[i] != 0 else "cab_exit")
	if net_door_open != _prev_door_open:
		_play(_snd_door[2], "door_slam", 0.8 if net_door_open else 1.0)
	_prev_door_open = net_door_open

	# Silnik: odpala się, gdy ktoś siądzie za kierownicą, gaśnie, gdy wysiądzie.
	var want_on: bool = net_seats[SEAT_DRIVER] != 0
	if want_on and not _engine_on:
		_engine_on = true
		_start_timer = 2.6  # rozruch, potem równa praca
		_play(_snd_start)
		_rpm = 0.0
	elif not want_on and _engine_on:
		_engine_on = false
	_prev_seats = net_seats.duplicate()

	_start_timer = maxf(0.0, _start_timer - delta)
	var running: bool = _engine_on and _start_timer < 0.6
	_engine_level = move_toward(_engine_level, 1.0 if running else 0.0, delta * (1.5 if running else 0.8))
	if _engine_level <= 0.0:
		if _snd_idle.playing:
			_snd_idle.stop()
			_snd_drive.stop()
		_track_brake_hiss()
		return
	if not _snd_idle.playing:
		_snd_idle.play()
		_snd_drive.play()

	# Obroty z prędkości i biegu (4 biegi + wsteczny); zmiana biegu = stuknięcie skrzyni.
	var kmh: float = absf(net_speed) * 3.6
	var gear: int = _gear
	if net_speed < -0.5:
		gear = -1
	elif gear < 0:
		gear = 0
	else:
		while gear < gear_top_speeds.size() - 1 and kmh > gear_top_speeds[gear] * 0.92:
			gear += 1
		while gear > 0 and kmh < gear_top_speeds[gear - 1] * 0.6:
			gear -= 1
	if gear != _gear:
		if _engine_on and (gear == -1 or _gear == -1 or gear > _gear):
			_play(_snd_gear, "", randf_range(0.95, 1.05))
		if gear > _gear and _gear >= 0:
			_rpm *= 0.55  # po zmianie w górę obroty spadają
		_gear = gear
	var top: float = reverse_speed_kmh if _gear < 0 else gear_top_speeds[_gear]
	var low: float = 0.0 if _gear <= 0 else gear_top_speeds[_gear - 1] * 0.6
	var target_rpm: float = clampf((kmh - low) / maxf(top - low, 1.0), 0.0, 1.0)
	var throttle: float = absf(net_throttle)
	if kmh < 3.0:
		target_rpm = maxf(target_rpm, throttle * 0.45)  # gaz na postoju - silnik wkręca się
	_rpm = move_toward(_rpm, target_rpm, delta * (2.0 if target_rpm > _rpm else 1.2))

	var engine_load: float = clampf(throttle * 0.85 + _rpm * 0.25, 0.0, 1.0)
	_snd_idle.pitch_scale = 0.9 + _rpm * 0.45
	_snd_drive.pitch_scale = 0.8 + _rpm * 0.5
	_snd_idle.volume_db = engine_volume_db + linear_to_db(maxf(0.001, _engine_level * lerpf(1.0, 0.3, engine_load)))
	_snd_drive.volume_db = engine_volume_db + linear_to_db(maxf(0.001, _engine_level * (0.15 + engine_load * 0.85)))
	_track_brake_hiss()


## Syk hamulca pneumatycznego, gdy auto zatrzyma się po jeździe.
func _track_brake_hiss() -> void:
	var speed: float = absf(net_speed)
	_peak_speed = maxf(_peak_speed, speed)
	if speed < 0.4 and _peak_speed > 4.0:
		_peak_speed = 0.0
		_play(_snd_brake, "", randf_range(0.95, 1.05))


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
	for prop: String in [":net_position", ":net_rotation", ":net_speed", ":net_steer", ":net_throttle", ":net_door_open", ":net_seats"]:
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
