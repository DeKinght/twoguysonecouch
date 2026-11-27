class_name JobComputer
extends Node3D
## Komputer ze zleceniami (Siedziba, biurko). E = usiądź do komputera.
##
## Z komputera korzysta jedna osoba naraz: kto go używa, wie host (`user_id`) i rozsyła
## to wszystkim. Pozostali widzą "Komputer zajęty". Przyjęte zlecenie też trzyma host.
## Węzeł musi mieć tę samą nazwę/ścieżkę u każdego gracza (tworzy go skrypt poziomu).

signal state_changed

## Zlecenia na liście (na razie testowe).
const JOBS: Array[Dictionary] = [
	{
		"id": "test_kawalerka",
		"title": "Przeprowadzka kawalerki",
		"description": "Pani Halina przeprowadza się na drugi koniec osiedla. Kanapa, lodówka, kilkanaście kartonów i bardzo cenny serwis po babci. Winda nie działa.",
		"image": "res://assets/ui/menu_bg.jpg",
		"stars": 0,
	},
]

## Wymiary ekranu monitora (lokalnie: środek, szerokość, wysokość) - do świecenia i kamery.
var screen_center: Vector3 = Vector3(0, 0.3, 0.02)
var screen_size: Vector2 = Vector2(0.6, 0.36)

## peer_id osoby przy komputerze (0 = wolny) i przyjęte zlecenie (id + kto przyjął).
var user_id: int = 0
var accepted_job: String = ""
var accepted_by: int = 0

var _glow: StandardMaterial3D
var _screen_ui: ComputerScreen


## Wołane przez poziom po ustawieniu pozycji: strefa na E i świecący ekran.
func setup(size: Vector2, center: Vector3) -> void:
	screen_size = size
	screen_center = center
	var body := StaticBody3D.new()
	body.name = "UseArea"
	body.collision_layer = Door.INTERACT_LAYER  # widzi go tylko promień E, nie blokuje ruchu
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x + 0.1, size.y + 0.15, 0.2)
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	add_child(body)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	quad.position = center + Vector3(0, 0, 0.004)
	_glow = StandardMaterial3D.new()
	_glow.emission_enabled = true
	_glow.albedo_color = Color(0.05, 0.06, 0.1)
	mesh.material = _glow
	add_child(quad)
	_refresh_glow()

	if multiplayer.is_server():
		Net.peer_left.connect(_server_on_peer_left)


# --- Interakcja (Interactor szuka interact/interact_text w rodzicach trafionego ciała) ----

func interact_text() -> String:
	if user_id != 0 and user_id != multiplayer.get_unique_id():
		return "Komputer zajęty (%s)" % Net.get_player_name(user_id)
	return "Sprawdź zlecenia"


func interact() -> void:
	if user_id != 0:
		return  # zajęty (albo już go używamy)
	if multiplayer.is_server():
		_server_request_use(multiplayer.get_unique_id())
	else:
		_rpc_request_use.rpc_id(1)


func request_leave() -> void:
	if multiplayer.is_server():
		_server_leave(multiplayer.get_unique_id())
	else:
		_rpc_request_leave.rpc_id(1)


func request_accept(job_id: String) -> void:
	if multiplayer.is_server():
		_server_accept(multiplayer.get_unique_id(), job_id)
	else:
		_rpc_request_accept.rpc_id(1, job_id)


func get_job(job_id: String) -> Dictionary:
	for job in JOBS:
		if job["id"] == job_id:
			return job
	return {}


## Pozycja i kierunek kamery "przed ekranem" (w świecie).
func view_transform() -> Transform3D:
	var center: Vector3 = to_global(screen_center)
	var normal: Vector3 = global_basis.z.normalized()
	var distance: float = screen_size.y * 0.5 / tan(deg_to_rad(36.0)) * 1.08  # ekran wypełnia kadr
	var t := Transform3D(Basis.IDENTITY, center + normal * distance)
	return t.looking_at(center, Vector3.UP)


# --- RPC (host) -------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_use() -> void:
	if multiplayer.is_server():
		_server_request_use(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_leave() -> void:
	if multiplayer.is_server():
		_server_leave(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_accept(job_id: String) -> void:
	if multiplayer.is_server():
		_server_accept(multiplayer.get_remote_sender_id(), job_id)


func _server_request_use(peer_id: int) -> void:
	if user_id == 0:
		_broadcast(peer_id, accepted_job, accepted_by)


func _server_leave(peer_id: int) -> void:
	if user_id == peer_id:
		_broadcast(0, accepted_job, accepted_by)


func _server_accept(peer_id: int, job_id: String) -> void:
	if user_id == peer_id and accepted_job == "" and not get_job(job_id).is_empty():
		_broadcast(user_id, job_id, peer_id)


func _server_on_peer_left(peer_id: int) -> void:
	_server_leave(peer_id)


func _broadcast(user: int, job: String, by: int) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_rpc_set_state(user, job, by)
	else:
		_rpc_set_state.rpc(user, job, by)


@rpc("authority", "call_local", "reliable")
func _rpc_set_state(user: int, job: String, by: int) -> void:
	var was_me: bool = user_id == multiplayer.get_unique_id()
	user_id = user
	accepted_job = job
	accepted_by = by
	var is_me: bool = user_id != 0 and user_id == multiplayer.get_unique_id()
	if is_me and not was_me:
		_open_screen()
	_refresh_glow()
	state_changed.emit()


# --- Ekran ------------------------------------------------------------------------------

func _open_screen() -> void:
	var player: Player = Net.get_player(multiplayer.get_unique_id())
	if player == null or _screen_ui != null:
		request_leave()
		return
	_screen_ui = ComputerScreen.new()
	_screen_ui.computer = self
	_screen_ui.player = player
	_screen_ui.closed.connect(func() -> void:
		_screen_ui = null
		request_leave())
	get_parent().add_child(_screen_ui)  # do poziomu - znika razem z nim przy zmianie sceny


func _refresh_glow() -> void:
	if _glow == null:
		return
	var busy: bool = user_id != 0
	# Włączony: kolor tła aplikacji (przejazd kamery płynnie przechodzi w ekran), wyłączony: ciemny.
	_glow.emission = Color(0.2, 0.16, 0.32) if busy else Color(0.06, 0.07, 0.12)
	_glow.emission_energy_multiplier = 1.0 if busy else 0.5
