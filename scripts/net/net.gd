extends Node
## Autoload "Net": połączenie ENet (host-klient), lista graczy w lobby, start gry.
##
## Cała reszta gry pyta o sieć przez ten węzeł i przez wbudowane `multiplayer`.
## Przy późniejszym dodaniu GodotSteam wymienia się tylko host_game()/join_game()
## (inny MultiplayerPeer) - reszta kodu zostaje bez zmian.

signal player_list_changed
signal connected                  ## klient połączył się z hostem
signal connection_failed
signal disconnected_from_host
signal peer_left(peer_id: int)    ## tylko host
signal peer_ready(peer_id: int)   ## tylko host: peer wczytał poziom
signal all_ready                  ## tylko host: wszyscy wczytali poziom

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 3
const MENU_SCENE: String = "res://ui/main_menu.tscn"
const LEVEL_SCENE: String = "res://scenes/levels/house.tscn"

var local_name: String = "Gracz"
var status_message: String = ""
## peer_id -> nazwa gracza
var names: Dictionary = {}
## peer_id -> Player (rejestrowane przez same postacie)
var players: Dictionary = {}
var game_started: bool = false
var ready_peers: Array[int] = []

var _all_ready_emitted: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Łączenie -----------------------------------------------------------------

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	names = {1: local_name}
	player_list_changed.emit()
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	names.clear()
	players.clear()
	ready_peers.clear()
	game_started = false
	_all_ready_emitted = false


func get_player_name(peer_id: int) -> String:
	return names.get(peer_id, "Gracz %d" % peer_id)


# --- Rejestr postaci ----------------------------------------------------------

func register_player(player: Node) -> void:
	players[player.get_multiplayer_authority()] = player


func unregister_player(player: Node) -> void:
	var id: int = player.get_multiplayer_authority()
	if players.get(id) == player:
		players.erase(id)


func get_player(peer_id: int) -> Player:
	return players.get(peer_id) as Player


# --- Start gry ----------------------------------------------------------------

## Tylko host.
func start_game() -> void:
	if not multiplayer.is_server() or game_started:
		return
	_rpc_load_level.rpc()


## Każdy peer woła to po wczytaniu poziomu.
func notify_level_ready() -> void:
	_rpc_level_ready.rpc_id(1)


@rpc("authority", "call_local", "reliable")
func _rpc_load_level() -> void:
	game_started = true
	ready_peers.clear()
	_all_ready_emitted = false
	Ledger.reset()
	get_tree().change_scene_to_file(LEVEL_SCENE)


@rpc("any_peer", "call_local", "reliable")
func _rpc_level_ready() -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1  # wywołanie lokalne hosta
	if id in ready_peers:
		return
	ready_peers.append(id)
	peer_ready.emit(id)
	_check_all_ready()


func _check_all_ready() -> void:
	if _all_ready_emitted or not (1 in ready_peers):
		return  # host musi mieć wczytany poziom, żeby ktokolwiek mógł się spawnować
	if ready_peers.size() >= multiplayer.get_peers().size() + 1:
		_all_ready_emitted = true
		all_ready.emit()


# --- Lista graczy -------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	names[multiplayer.get_remote_sender_id()] = player_name.substr(0, 20)
	_rpc_set_names.rpc(names)


@rpc("authority", "call_local", "reliable")
func _rpc_set_names(new_names: Dictionary) -> void:
	names = new_names
	player_list_changed.emit()


# --- Zdarzenia sieci ----------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and game_started:
		multiplayer.multiplayer_peer.disconnect_peer(id)  # brak dołączania w trakcie gry (MVP)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	names.erase(id)
	ready_peers.erase(id)
	_rpc_set_names.rpc(names)
	peer_left.emit(id)
	if game_started:
		_check_all_ready()


func _on_connected_to_server() -> void:
	_rpc_register_name.rpc_id(1, local_name)
	connected.emit()


func _on_connection_failed() -> void:
	leave()
	status_message = "Nie udało się połączyć z hostem."
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	status_message = "Utracono połączenie z hostem."
	disconnected_from_host.emit()
	get_tree().change_scene_to_file(MENU_SCENE)
