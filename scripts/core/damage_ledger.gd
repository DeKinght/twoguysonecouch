extends Node
## Autoload "Ledger": rachunek strat. Host zgłasza szkodę (record), a każdy peer
## dostaje ją przez RPC i dopisuje do własnej kopii - dzięki temu ekran
## podsumowania (etap 4) może działać lokalnie u każdego.

signal damage_recorded(peer_id: int, item_name: String, loss: int)

## Wpisy: {peer: int, item: String, loss: int}
var records: Array[Dictionary] = []


func reset() -> void:
	records.clear()


## Tylko host. peer_id = 0 oznacza "nikt nie trzymał" (wypadek).
func record(peer_id: int, item_name: String, loss: int) -> void:
	if not multiplayer.is_server() or loss <= 0:
		return
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_rpc_damage(peer_id, item_name, loss)
	else:
		_rpc_damage.rpc(peer_id, item_name, loss)


@rpc("authority", "call_local", "reliable")
func _rpc_damage(peer_id: int, item_name: String, loss: int) -> void:
	records.append({"peer": peer_id, "item": item_name, "loss": loss})
	damage_recorded.emit(peer_id, item_name, loss)


func total_lost() -> int:
	var sum: int = 0
	for r in records:
		sum += int(r["loss"])
	return sum


## peer_id -> suma strat
func totals_by_peer() -> Dictionary:
	var totals: Dictionary = {}
	for r in records:
		var id: int = r["peer"]
		totals[id] = int(totals.get(id, 0)) + int(r["loss"])
	return totals


func display_name(peer_id: int) -> String:
	if peer_id == 0:
		return "Wypadek"
	return Net.get_player_name(peer_id)
