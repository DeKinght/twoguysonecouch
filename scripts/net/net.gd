extends Node
## Autoload "Net": połączenie (ENet po IP LUB Steam), lobby, lista graczy, start gry.
##
## Reszta gry zna tylko wbudowane `multiplayer` - transport jest wymienny.
## Steam: lobby tworzy/znajduje GodotSteam, a właściwe połączenie (RPC, spawner,
## synchronizatory) niesie SteamMultiplayerPeer. Do GodotSteam odwołujemy się
## dynamicznie (Engine.get_singleton), więc gra działa też, gdy Steam jest niedostępny.

signal player_list_changed
signal connected                  ## klient połączył się z hostem
signal connection_failed
signal disconnected_from_host
signal lobby_ready                ## host Steam utworzył lobby
signal lobby_list_received(lobbies: Array)  ## [{id, name, members}]
signal peer_left(peer_id: int)    ## tylko host
signal peer_ready(peer_id: int)   ## tylko host: peer wczytał poziom
signal all_ready                  ## tylko host: wszyscy wczytali poziom

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 3
const MENU_SCENE: String = "res://ui/main_menu.tscn"
const LEVEL_SCENE: String = "res://scenes/levels/block.tscn"

## 480 = publiczny testowy App ID Valve ("Spacewar"). Do testów bez wydawania gry.
const STEAM_APP_ID: int = 480
## Znacznik w danych lobby - odfiltrowuje lobby innych gier na tym samym App ID.
const LOBBY_TAG: String = "przeprowadzka-z-piekla-v1"

# Stałe Steama (liczby, bo odwołujemy się do singletona dynamicznie).
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_COMPARISON_EQUAL: int = 0
const LOBBY_DISTANCE_WORLDWIDE: int = 3
const ENTER_RESPONSE_SUCCESS: int = 1
const RESULT_OK: int = 1

## Blokuje sterowanie (np. gdy widać ekran podsumowania).
var input_locked: bool = false
var local_name: String = "Gracz"
var status_message: String = ""
## peer_id -> nazwa gracza
var names: Dictionary = {}
## peer_id -> Player (rejestrowane przez same postacie)
var players: Dictionary = {}
var game_started: bool = false
var ready_peers: Array[int] = []

## Steam
var steam: Object = null          ## singleton GodotSteam albo null
var steam_ready: bool = false
var steam_status: String = ""     ## powód niedostępności Steama (do pokazania w menu)
var lobby_id: int = 0

var _all_ready_emitted: bool = false
var _joining_lobby: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_steam()


func _process(_delta: float) -> void:
	if steam != null:
		steam.run_callbacks()


# --- Steam: start -------------------------------------------------------------------

func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		steam_status = "Brak dodatku GodotSteam."
		return
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		steam_status = "Brak dodatku SteamMultiplayerPeer (zrestartuj edytor)."
		return

	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))
	var api: Object = Engine.get_singleton("Steam")
	var result: Dictionary = api.steamInitEx()
	if int(result.get("status", 1)) != 0:
		steam_status = "Steam niedostępny: %s" % str(result.get("verbal", "nieznany błąd"))
		return

	steam = api
	steam_ready = true
	local_name = str(steam.getPersonaName())
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("lobby_match_list", _on_lobby_match_list)
	steam.connect("join_requested", _on_join_requested)
	steam.initRelayNetworkAccess()


# --- Łączenie: ENet po IP -------------------------------------------------------------

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


# --- Łączenie: Steam ------------------------------------------------------------------

## Host: tworzy lobby Steam; dalej zajmuje się nim _on_lobby_created.
func host_game_steam() -> bool:
	if not steam_ready:
		return false
	steam.createLobby(LOBBY_TYPE_PUBLIC, MAX_PLAYERS)
	return true


## Klient: dołącza do lobby; dalej zajmuje się nim _on_lobby_joined.
func join_lobby(id: int) -> bool:
	if not steam_ready or id <= 0:
		return false
	_joining_lobby = true
	steam.joinLobby(id)
	return true


func request_lobby_list() -> void:
	if not steam_ready:
		return
	steam.addRequestLobbyListStringFilter("game", LOBBY_TAG, LOBBY_COMPARISON_EQUAL)
	steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_WORLDWIDE)
	steam.requestLobbyList()


## Otwiera nakładkę Steam z zaproszeniem znajomych (nie działa przy uruchomieniu z edytora).
func invite_friends() -> void:
	if steam_ready and lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)


func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if result != RESULT_OK:
		status_message = "Nie udało się utworzyć lobby Steam (kod %d)." % result
		connection_failed.emit()
		return
	lobby_id = new_lobby_id
	steam.setLobbyJoinable(lobby_id, true)
	steam.setLobbyData(lobby_id, "game", LOBBY_TAG)
	steam.setLobbyData(lobby_id, "host_name", local_name)

	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: Error = peer.create_host(0)
	if err != OK:
		steam.leaveLobby(lobby_id)
		lobby_id = 0
		status_message = "Nie udało się uruchomić hosta Steam (kod %d)." % err
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	names = {1: local_name}
	player_list_changed.emit()
	lobby_ready.emit()


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if not _joining_lobby:
		return  # to samo zdarzenie dostaje host po utworzeniu lobby
	_joining_lobby = false
	if response != ENTER_RESPONSE_SUCCESS:
		status_message = "Nie udało się dołączyć do lobby (kod %d)." % response
		connection_failed.emit()
		return
	lobby_id = joined_lobby_id
	var host_steam_id: int = int(steam.getLobbyOwner(joined_lobby_id))
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: Error = peer.create_client(host_steam_id, 0)
	if err != OK:
		steam.leaveLobby(lobby_id)
		lobby_id = 0
		status_message = "Nie udało się połączyć z hostem Steam (kod %d)." % err
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer  # dalej: connected_to_server -> rejestracja nazwy


func _on_lobby_match_list(lobbies: Array) -> void:
	var list: Array = []
	for id in lobbies:
		list.append({
			"id": int(id),
			"name": str(steam.getLobbyData(id, "host_name")),
			"members": int(steam.getNumLobbyMembers(id)),
		})
	lobby_list_received.emit(list)


## Znajomy kliknął "Dołącz do gry" w nakładce Steam.
func _on_join_requested(requested_lobby_id: int, _friend_steam_id: int) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		join_lobby(requested_lobby_id)


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if steam != null and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	_joining_lobby = false
	names.clear()
	players.clear()
	ready_peers.clear()
	game_started = false
	_all_ready_emitted = false


func get_player_name(peer_id: int) -> String:
	return names.get(peer_id, "Gracz %d" % peer_id)


# --- Rejestr postaci ----------------------------------------------------------------

func register_player(player: Node) -> void:
	players[player.get_multiplayer_authority()] = player


func unregister_player(player: Node) -> void:
	var id: int = player.get_multiplayer_authority()
	if players.get(id) == player:
		players.erase(id)


func get_player(peer_id: int) -> Player:
	return players.get(peer_id) as Player


# --- Start gry ----------------------------------------------------------------------

## Tylko host.
func start_game() -> void:
	if not multiplayer.is_server() or game_started:
		return
	if steam != null and lobby_id != 0:
		steam.setLobbyJoinable(lobby_id, false)  # nikt nowy nie dołączy w trakcie gry
	_rpc_load_level.rpc()


## Każdy peer woła to po wczytaniu poziomu.
func notify_level_ready() -> void:
	_rpc_level_ready.rpc_id(1)


@rpc("authority", "call_local", "reliable")
func _rpc_load_level() -> void:
	game_started = true
	ready_peers.clear()
	_all_ready_emitted = false
	input_locked = false
	Ledger.reset()
	get_tree().change_scene_to_file(LEVEL_SCENE)


## Tylko host: wszyscy wracają do lobby (połączenie zostaje).
func return_to_lobby() -> void:
	if multiplayer.is_server():
		if steam != null and lobby_id != 0:
			steam.setLobbyJoinable(lobby_id, true)
		_rpc_back_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_back_to_lobby() -> void:
	game_started = false
	ready_peers.clear()
	_all_ready_emitted = false
	input_locked = false
	get_tree().change_scene_to_file(MENU_SCENE)


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


# --- Lista graczy -------------------------------------------------------------------

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


# --- Zdarzenia sieci ----------------------------------------------------------------

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
