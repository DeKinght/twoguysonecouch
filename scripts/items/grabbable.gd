class_name Grabbable
extends RigidBody3D
## Mebel / przedmiot, który można złapać.
##
## SIEĆ: fizykę liczy wyłącznie host. Na klientach ciało jest "zamrożone"
## (kinematyczne), a jego pozycję ustawia interpolacja do wartości
## `net_position` / `net_rotation` replikowanych przez MultiplayerSynchronizer.
##
## CHWYT: gracz (Grabber) woła request_* - na hoście wykonują się od razu,
## na kliencie idą RPC do hosta. Host co klatkę fizyki liczy siłę sprężyny
## dla każdego trzymającego (parametry bierze ze swojej kopii postaci tego gracza).

@export var item_name: String = "Karton"
@export var size: Vector3 = Vector3(0.5, 0.5, 0.5)
@export var color: Color = Color(0.72, 0.55, 0.35)
## Wartość w zł - w etapie 3 będzie spadać przy uderzeniach.
@export var value: float = 100.0
## Wytrzymałość - w etapie 3 określa odporność na uderzenia.
@export var durability: float = 100.0

## Ile sekund bez aktualizacji od klienta, zanim host uzna chwyt za zerwany.
const HOLD_TIMEOUT: float = 0.6
const NET_SMOOTHING: float = 18.0
const MAX_PUSH_IMPULSE: float = 5.0

## Replikowane z hosta do klientów:
var net_position: Vector3
var net_rotation: Quaternion = Quaternion.IDENTITY
var holder_count: int = 0

## Tylko host: peer_id -> {point: Vector3, target: Vector3, stamp: float}
var holders: Dictionary = {}
## peer_id ostatniego trzymającego (do rozliczenia szkód per gracz w etapie 3).
var last_holder_id: int = 0

var net_sync: MultiplayerSynchronizer
var _base_angular_damp: float


func _ready() -> void:
	add_to_group("grabbables")
	collision_layer = 4  # items
	collision_mask = 7   # world + players + items
	continuous_cd = true
	_base_angular_damp = angular_damp
	if get_child_count() == 0:
		_build_placeholder()

	net_position = global_position
	net_rotation = global_basis.get_rotation_quaternion()
	_setup_sync()

	if multiplayer.is_server():
		Net.peer_left.connect(server_end_hold)
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_apply_holds()
		net_position = global_position
		net_rotation = global_basis.get_rotation_quaternion()
	else:
		var t: float = 1.0 - exp(-NET_SMOOTHING * delta)
		global_position = global_position.lerp(net_position, t)
		var q: Quaternion = global_basis.get_rotation_quaternion().slerp(net_rotation, t)
		global_basis = Basis(q)


# --- API dla Grabbera (działa na hoście i na kliencie) -------------------------

func request_begin_hold(local_point: Vector3, target: Vector3) -> void:
	if multiplayer.is_server():
		_server_begin_hold(multiplayer.get_unique_id(), local_point, target)
	else:
		rpc_begin_hold.rpc_id(1, local_point, target)


func request_update_hold(target: Vector3) -> void:
	if multiplayer.is_server():
		_server_update_hold(multiplayer.get_unique_id(), target)
	else:
		rpc_update_hold.rpc_id(1, target)


func request_end_hold() -> void:
	if multiplayer.is_server():
		server_end_hold(multiplayer.get_unique_id())
	else:
		rpc_end_hold.rpc_id(1)


func request_push(impulse: Vector3) -> void:
	if multiplayer.is_server():
		apply_central_impulse(impulse.limit_length(MAX_PUSH_IMPULSE))
	else:
		rpc_push.rpc_id(1, impulse)


# --- RPC (wykonują się na hoście) ----------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_begin_hold(local_point: Vector3, target: Vector3) -> void:
	if multiplayer.is_server():
		_server_begin_hold(multiplayer.get_remote_sender_id(), local_point, target)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_update_hold(target: Vector3) -> void:
	if multiplayer.is_server():
		_server_update_hold(multiplayer.get_remote_sender_id(), target)


@rpc("any_peer", "call_remote", "reliable")
func rpc_end_hold() -> void:
	if multiplayer.is_server():
		server_end_hold(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "unreliable")
func rpc_push(impulse: Vector3) -> void:
	if multiplayer.is_server():
		apply_central_impulse(impulse.limit_length(MAX_PUSH_IMPULSE))


# --- Logika hosta ---------------------------------------------------------------

func _server_begin_hold(peer_id: int, local_point: Vector3, target: Vector3) -> void:
	holders[peer_id] = {
		"point": local_point,
		"target": target,
		"stamp": Time.get_ticks_msec() / 1000.0,
	}
	last_holder_id = peer_id
	holder_count = holders.size()
	angular_damp = 4.0  # trzymany przedmiot mniej się kręci
	sleeping = false


func _server_update_hold(peer_id: int, target: Vector3) -> void:
	if not holders.has(peer_id):
		return
	var h: Dictionary = holders[peer_id]
	h["target"] = target
	h["stamp"] = Time.get_ticks_msec() / 1000.0


func server_end_hold(peer_id: int) -> void:
	if not holders.erase(peer_id):
		return
	holder_count = holders.size()
	if holders.is_empty():
		angular_damp = _base_angular_damp


func _server_apply_holds() -> void:
	if holders.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for peer_id: int in holders.keys():
		var h: Dictionary = holders[peer_id]
		var player: Player = Net.get_player(peer_id)
		if player == null or (peer_id != multiplayer.get_unique_id() and now - float(h["stamp"]) > HOLD_TIMEOUT):
			server_end_hold(peer_id)
			continue

		var grip: Grabber = player.grabber
		var point_world: Vector3 = to_global(h["point"])
		var error: Vector3 = (h["target"] as Vector3) - point_world
		var r: Vector3 = point_world - global_position
		var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(r)
		var force: Vector3 = error * grip.stiffness - point_velocity * grip.damping
		apply_force(force.limit_length(grip.max_force), r)


# --- Pomocnicze -------------------------------------------------------------------

func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop: String in [":net_position", ":net_rotation", ":holder_count"]:
		var path := NodePath(prop)
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	net_sync = MultiplayerSynchronizer.new()
	net_sync.name = "NetSync"
	net_sync.replication_config = cfg
	net_sync.replication_interval = 1.0 / 30.0
	# Host włącza widoczność dla danego peera dopiero, gdy ten wczyta poziom.
	# Klient MUSI mieć widoczność włączoną - od niej zależy, czy może wysyłać RPC do hosta.
	net_sync.public_visibility = not multiplayer.is_server()
	add_child(net_sync)


func _build_placeholder() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box_mesh.material = mat
	mesh_instance.mesh = box_mesh
	add_child(mesh_instance)
