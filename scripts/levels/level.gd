extends Node3D
## Poziom: host spawnuje graczy (MultiplayerSpawner rozsyła ich do klientów)
## i odblokowuje synchronizację przedmiotów dla peerów, którzy wczytali poziom.
## Uruchomiony bezpośrednio (F6) działa offline z jednym graczem.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawn_points: Array[Node] = $SpawnPoints.get_children()


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		Ledger.reset()
		players_root.add_child(_spawn_player({"id": 1, "pos": _spawn_pos(0)}))
		return

	if multiplayer.is_server():
		Net.peer_ready.connect(_on_peer_ready)
		Net.all_ready.connect(_spawn_all_players)
		Net.peer_left.connect(_on_peer_left)
		# Ktoś mógł wczytać poziom, zanim host skończył - nadrabiamy.
		for id in Net.ready_peers:
			_on_peer_ready(id)
	Net.notify_level_ready()


## Wykonuje się na KAŻDYM peerze (hoście i klientach) dla każdego spawnu.
func _spawn_player(data: Dictionary) -> Node:
	var player: Player = PLAYER_SCENE.instantiate()
	var id: int = data["id"]
	player.name = str(id)
	player.position = data["pos"]
	player.skin = data.get("skin", -1)
	player.set_multiplayer_authority(id)  # przed add_child, żeby _ready znało autorytet
	return player


func _spawn_all_players() -> void:
	var ids: Array[int] = [1]
	ids.append_array(multiplayer.get_peers())
	# Każdy gracz dostaje losowy wygląd postaci, bez powtórek (dopóki starczy wariantów).
	var skins: Array = range(CharacterModel.VARIANTS.size())
	skins.shuffle()
	for i in ids.size():
		spawner.spawn({"id": ids[i], "pos": _spawn_pos(i), "skin": skins[i % skins.size()]})


func _spawn_pos(index: int) -> Vector3:
	return (spawn_points[index % spawn_points.size()] as Node3D).global_position


func _on_peer_ready(id: int) -> void:
	if id == 1:
		return
	for item: Grabbable in get_tree().get_nodes_in_group("grabbables"):
		item.net_sync.set_visibility_for(id, true)
	for vehicle: Van in get_tree().get_nodes_in_group("vehicles"):
		vehicle.net_sync.set_visibility_for(id, true)


func _on_peer_left(id: int) -> void:
	var player: Node = players_root.get_node_or_null(str(id))
	if player != null:
		player.queue_free()
