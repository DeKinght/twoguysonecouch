class_name Interactor
extends Node3D
## "Użyj" (domyślnie E): patrzysz na coś z metodą interact() (drzwi, brama, później
## komputer, warsztat, sklep) i wciskasz klawisz. Dziecko Camera3D lokalnego gracza.
## Obiekt do użycia musi mieć metody interact() i interact_text() - może je mieć
## sam trafiony węzeł albo dowolny jego rodzic (np. zawias drzwi nad skrzydłem).

@export var reach: float = 2.6

var player: Player
## Na co teraz patrzymy (Node z interact()) albo null.
var looked_at: Node = null

@onready var camera: Camera3D = get_parent() as Camera3D


func _physics_process(_delta: float) -> void:
	if Settings.input_blocked() or (player != null and player.is_down()):
		looked_at = null
		return
	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_basis.z) * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)  # świat + przedmioty
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	looked_at = null if hit.is_empty() else _find_interactable(hit["collider"])

	if looked_at != null and Input.is_action_just_pressed("interact"):
		looked_at.interact()


func _find_interactable(collider: Object) -> Node:
	var node := collider as Node
	while node != null and node != get_tree().current_scene:
		if node.has_method("interact") and node.has_method("interact_text"):
			return node
		node = node.get_parent()
	return null
