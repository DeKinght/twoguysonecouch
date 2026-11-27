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
##
## SZKODY (tylko host): w _integrate_forces mierzymy zmianę prędkości przy
## kontakcie (impuls / masa). Powyżej progu odejmujemy wartość i zapisujemy
## winowajcę (kto trzymał) w Ledgerze.

@export var item_name: String = "Karton"
## Model 3D (.glb). Puste = zwykły kolorowy prostopadłościan z `size` i `color`.
## Z modelem kolizja (box) i `size` liczą się same z jego wymiarów.
@export var model: PackedScene
## Skala modelu. Modele Kenney Furniture Kit są w skali ~1:2, więc 2.0.
@export var model_scale: float = 2.0
@export var size: Vector3 = Vector3(0.5, 0.5, 0.5)
@export var color: Color = Color(0.72, 0.55, 0.35)
## Napis na ściankach (np. "SZKŁO"). Puste = brak.
@export var label_text: String = ""
## Pozycja węzła to środek PODSTAWY (a nie środek bryły) - w _ready przesuwamy się
## w górę o pół wysokości modelu. Wygodne przy stawianiu rzeczy na blatach i półkach.
@export var spawn_from_bottom: bool = false
## Przyczepiony (np. półka na ścianie, kula pod sufitem): nie spada, dopóki ktoś go nie złapie.
@export var start_frozen: bool = false

@export_group("Szkody")
## Wartość w zł - spada przy uderzeniach.
@export var value: float = 100.0
## Wytrzymałość: im niższa, tym większe szkody od tego samego uderzenia (100 = norma).
@export var durability: float = 100.0
## Zmiana prędkości [m/s] przy kontakcie, poniżej której nic się nie dzieje.
@export var hit_speed_threshold: float = 2.5
## Ile zł strat na każdy m/s ponad próg (przy durability = 100).
@export var damage_scale: float = 6.0

@export_group("Przewracanie graczy")
## Przedmiot uderzający gracza musi lecieć szybciej niż to [m/s]...
@export var knock_speed: float = 3.0
## ...i mieć pęd (masa * prędkość) większy niż to.
@export var knock_momentum: float = 30.0

## Ile sekund bez aktualizacji od klienta, zanim host uzna chwyt za zerwany.
const HOLD_TIMEOUT: float = 0.6
const NET_SMOOTHING: float = 18.0
const MAX_PUSH_IMPULSE: float = 5.0
const HIT_COOLDOWN: float = 0.25
## Przez ile sekund po puszczeniu przedmiotu szkody nadal liczą się trzymającemu.
const BLAME_WINDOW: float = 3.0

## Replikowane z hosta do klientów:
var net_position: Vector3
var net_rotation: Quaternion = Quaternion.IDENTITY
var holder_count: int = 0

## Tylko host: peer_id -> {point: Vector3, target: Vector3, stamp: float}
var holders: Dictionary = {}
## peer_id ostatniego trzymającego (do rozliczenia szkód per gracz).
var last_holder_id: int = 0

var net_sync: MultiplayerSynchronizer

var _base_angular_damp: float
var _max_value: float
var _shown_value: float = -1.0
var _material: StandardMaterial3D
## Przy modelu: półprzezroczysta czerń nakładana na model, ciemnieje ze szkodami.
var _overlay: StandardMaterial3D
var _prev_velocity: Vector3 = Vector3.ZERO
var _last_hit_time: float = -10.0
var _last_release_time: float = -10.0
var _destroyed: bool = false
var _had_value: bool = true


func _ready() -> void:
	add_to_group("grabbables")
	collision_layer = 4  # items
	collision_mask = 7   # world + players + items
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	_base_angular_damp = angular_damp
	_max_value = maxf(value, 1.0)
	_had_value = value > 0.0
	if get_child_count() == 0:
		if model != null:
			_build_from_model()
		else:
			_build_placeholder()
	if spawn_from_bottom:
		position.y += size.y * 0.5

	net_position = global_position
	net_rotation = global_basis.get_rotation_quaternion()
	_setup_sync()

	if multiplayer.is_server():
		Net.peer_left.connect(server_end_hold)
		if start_frozen:
			freeze = true  # wisi/stoi przyczepiony, aż ktoś go złapie
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

	if value != _shown_value:
		_shown_value = value
		_update_visual()


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


# --- Logika hosta: chwyt ------------------------------------------------------------

func _server_begin_hold(peer_id: int, local_point: Vector3, target: Vector3) -> void:
	if _destroyed:
		return
	if freeze:
		freeze = false  # zerwany ze ściany / sufitu
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
	_last_release_time = Time.get_ticks_msec() / 1000.0
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


# --- Logika hosta: uderzenia i szkody ---------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not multiplayer.is_server():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var max_dv: float = 0.0
	for i in state.get_contact_count():
		var other: Object = state.get_contact_collider_object(i)
		if other is Player:
			_try_knock_player(other as Player)
		else:
			max_dv = maxf(max_dv, state.get_contact_impulse(i).length() / mass)
	if max_dv > hit_speed_threshold:
		_apply_damage(max_dv - hit_speed_threshold, now)
	_prev_velocity = state.linear_velocity


func _apply_damage(excess_speed: float, now: float) -> void:
	if _destroyed or value <= 0.0 or now - _last_hit_time < HIT_COOLDOWN:
		return
	_last_hit_time = now
	var loss: float = excess_speed * damage_scale * (100.0 / maxf(durability, 1.0))
	var loss_int: int = mini(roundi(loss), roundi(value))
	if loss_int <= 0:
		return
	value -= loss_int
	Ledger.record(_blame_id(now), item_name, loss_int)
	if value <= 0.0:
		# Poza callbackiem fizyki - tam nie wolno zmieniać kolizji ani usuwać ciała.
		_server_destroy.call_deferred()


## Host: przedmiot stracił całą wartość - znika u wszystkich (z efektem i dźwiękiem).
func _server_destroy() -> void:
	if _destroyed:
		return
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_rpc_destroy()
	else:
		_rpc_destroy.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	DestroyEffect.spawn(get_tree().current_scene, global_position, color, size)
	if not multiplayer.is_server():
		queue_free()
		return
	# Host: od razu chowamy i wyłączamy ciało, ale usuwamy je chwilę później,
	# żeby polecenie zniszczenia zdążyło dojść do klientów przed zniknięciem węzła.
	holders.clear()
	holder_count = 0
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	remove_from_group("grabbables")
	_stop_syncing.call_deferred()  # po wysłaniu RPC (niewidoczny węzeł blokuje też RPC)
	get_tree().create_timer(0.5).timeout.connect(queue_free)


func _stop_syncing() -> void:
	for peer_id: int in multiplayer.get_peers():
		net_sync.set_visibility_for(peer_id, false)


## Czy przedmiot ma jakąkolwiek wartość od początku (przedmioty ze zleceń).
## Bez wartości: nie liczą się do szkód, nie ciemnieją, nie niszczą się.
func has_value() -> bool:
	return _had_value


func _blame_id(now: float) -> int:
	var id: int = _holder_blame_id(now)
	if id != 0:
		return id
	# Nikt nie trzymał, ale przedmiot jedzie w pace - winny kierowca.
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		id = vehicle.blame_for_item(self)
		if id != 0:
			return id
	return 0


func _holder_blame_id(now: float) -> int:
	if not holders.is_empty():
		return holders.keys()[0]
	if now - _last_release_time < BLAME_WINDOW:
		return last_holder_id
	return 0


func _try_knock_player(player: Player) -> void:
	var speed: float = _prev_velocity.length()
	if speed < knock_speed or speed * mass < knock_momentum:
		return
	if holders.has(player.get_multiplayer_authority()):
		return  # własny przedmiot nie przewraca trzymającego
	player.request_knockdown(_prev_velocity.normalized() * 4.0, player.down_duration)


# --- Pomocnicze -------------------------------------------------------------------

func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop: String in [":net_position", ":net_rotation", ":holder_count", ":value"]:
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


func _update_visual() -> void:
	if not has_value():
		return  # przedmioty bez wartości (np. w siedzibie) nie ciemnieją
	var damaged: float = 1.0 - clampf(value / _max_value, 0.0, 1.0)
	if _material != null:
		_material.albedo_color = color.darkened(0.6 * damaged)
	if _overlay != null:
		_overlay.albedo_color = Color(0, 0, 0, 0.6 * damaged)


## Wstawia model wyśrodkowany na środku ciała i dopasowuje do niego kolizję (box).
func _build_from_model() -> void:
	var visual: Node3D = model.instantiate()
	visual.name = "Model"
	visual.scale = Vector3.ONE * model_scale
	add_child(visual)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(visual, meshes)
	var bounds := AABB()
	var first: bool = true
	for mi in meshes:
		var box: AABB = _transform_to_self(mi) * mi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		push_warning("%s: model bez siatek, używam placeholdera" % name)
		visual.queue_free()
		_build_placeholder()
		return

	var center: Vector3 = bounds.get_center()
	visual.position -= center  # środek modelu = środek ciała (i środek masy)
	size = bounds.size

	var shape := CollisionShape3D.new()
	var collision_box := BoxShape3D.new()
	collision_box.size = size
	shape.shape = collision_box
	add_child(shape)

	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(0, 0, 0, 0)
	for mi in meshes:
		mi.material_overlay = _overlay

	_add_labels()


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	# skip_bounds: np. odchylone klapy kartonu - widać je, ale nie powiększają hitboxa.
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and not node.has_meta("skip_bounds"):
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


## Transformacja węzła potomnego względem tego ciała (bez zależności od global_transform).
func _transform_to_self(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != self and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _build_placeholder() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	box_mesh.material = _material
	mesh_instance.mesh = box_mesh
	add_child(mesh_instance)
	_add_labels()


func _add_labels() -> void:
	if label_text != "":
		for side in [1.0, -1.0]:
			# Dopasowany do ścianki (80 % szerokości, 35 % wysokości) - nie wystaje poza nią.
			var label: Label3D = TextFit.make(label_text, size.x * 0.8, size.y * 0.35, Color(0.1, 0.1, 0.1))
			label.position = Vector3(0, 0, side * (size.z * 0.5 + 0.005))
			label.rotation.y = 0.0 if side > 0.0 else PI
			add_child(label)
