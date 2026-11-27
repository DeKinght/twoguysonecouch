class_name JobManager
extends Node
## Zlecenie: odliczanie czasu, liczenie przedmiotów w busie, koniec i rozliczenie.
##
## Host liczy wszystko (przedmioty w strefie busa, czas) i co 0,5 s wysyła
## klientom stan do HUD-a. Na koniec host rozsyła wynik, a każdy peer sam
## składa podsumowanie z lokalnej kopii Ledgera.
## Węzeł musi nazywać się tak samo na wszystkich peerach ("Job") - to ścieżka RPC.

signal finished_job

@export var base_pay: int = 3000
@export var time_limit: float = 600.0
## Tyle sekund wszystko musi leżeć w busie (nikt nie trzyma), żeby zlecenie się skończyło.
@export var finish_delay: float = 1.5

var zone: Area3D
var time_left: float = 600.0
var loaded_count: int = 0
var total_count: int = 0
var is_finished: bool = false

var _loaded_items: Array[Grabbable] = []
var _poll_timer: float = 0.0
var _broadcast_timer: float = 0.0
var _all_loaded_time: float = 0.0


func _ready() -> void:
	add_to_group("job")
	time_left = time_limit
	if multiplayer.is_server():
		total_count = get_tree().get_nodes_in_group("grabbables").size()


func _physics_process(delta: float) -> void:
	if is_finished:
		return
	if not multiplayer.is_server():
		time_left = maxf(0.0, time_left - delta)  # klient odlicza sam, host go korekuje
		return

	time_left = maxf(0.0, time_left - delta)
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = 0.25
		_count_loaded()
	if total_count > 0 and loaded_count == total_count:
		_all_loaded_time += delta
	else:
		_all_loaded_time = 0.0

	_broadcast_timer -= delta
	if _broadcast_timer <= 0.0:
		_broadcast_timer = 0.5
		for id in Net.ready_peers:
			if id != 1:
				_rpc_status.rpc_id(id, time_left, loaded_count, total_count)

	if time_left <= 0.0 or _all_loaded_time >= finish_delay:
		_finish()


func _count_loaded() -> void:
	# Zniszczone przedmioty znikają z grupy, więc zlecenie da się skończyć bez nich.
	total_count = get_tree().get_nodes_in_group("grabbables").size()
	_loaded_items.clear()
	if zone != null:
		for body in zone.get_overlapping_bodies():
			var item := body as Grabbable
			if item != null and item.holder_count == 0:
				_loaded_items.append(item)
	loaded_count = _loaded_items.size()


func _finish() -> void:
	_count_loaded()
	is_finished = true
	var missing_value: int = 0
	var missing_count: int = 0
	for node in get_tree().get_nodes_in_group("grabbables"):
		var item := node as Grabbable
		if not (item in _loaded_items):
			missing_value += roundi(item.value)
			missing_count += 1
	var early: bool = time_left > 0.0
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_rpc_finish(base_pay, missing_value, missing_count, loaded_count, total_count, early)
	else:
		_rpc_finish.rpc(base_pay, missing_value, missing_count, loaded_count, total_count, early)


@rpc("authority", "call_remote", "unreliable")
func _rpc_status(new_time_left: float, loaded: int, total: int) -> void:
	time_left = new_time_left
	loaded_count = loaded
	total_count = total


@rpc("authority", "call_local", "reliable")
func _rpc_finish(pay: int, missing_value: int, missing_count: int, loaded: int, total: int, early: bool) -> void:
	is_finished = true
	loaded_count = loaded
	total_count = total
	var screen := SummaryScreen.new()
	screen.data = {
		"base_pay": pay,
		"missing_value": missing_value,
		"missing_count": missing_count,
		"loaded": loaded,
		"total": total,
		"early": early,
	}
	get_tree().current_scene.add_child(screen)
	finished_job.emit()
