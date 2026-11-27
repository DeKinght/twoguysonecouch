class_name Grabber
extends Node3D
## Chwytanie przedmiotów (strona gracza). Dziecko Camera3D.
##
## Grabber tylko CELUJE i zgłasza przedmiotowi: "trzymam Cię w tym punkcie,
## cel jest tu". Siłę sprężyny liczy host w Grabbable (parametry poniżej są
## czytane z kopii tej postaci na hoście, więc muszą być takie same u wszystkich).
## Siła jest ograniczona `max_force`: lodówka (60 kg ~ 590 N) nie wstanie
## w jednych rękach, ale w dwóch już tak.

signal target_changed(item: Grabbable)
signal grab_started(item: Grabbable)
signal grab_ended(item: Grabbable)

@export_group("Zasięg")
@export var reach: float = 3.0
@export var min_hold_distance: float = 1.0
@export var max_hold_distance: float = 2.5
@export var scroll_step: float = 0.15
## Jeśli przedmiot oddali się od celu bardziej niż tyle (np. utknął za ścianą) - puszczamy.
@export var max_stretch: float = 2.0

@export_group("Siła chwytu")
@export var stiffness: float = 250.0   ## sztywność sprężyny [N/m]
@export var damping: float = 35.0      ## tłumienie [N*s/m] - mniej = bardziej chwiejnie
@export var max_force: float = 350.0   ## maks. siła jednego gracza [N]

@export_group("Obciążenie gracza")
@export var heavy_mass: float = 80.0       ## masa, przy której gracz zwalnia do minimum
@export var min_speed_factor: float = 0.25

var held: Grabbable = null
var looked_at: Grabbable = null

var _look_hit_position: Vector3
var _local_point: Vector3
var _hold_distance: float = 1.5

@onready var camera: Camera3D = get_parent() as Camera3D


func _ready() -> void:
	# Kopie cudzych postaci (na hoście i u innych klientów) nie celują ani nie łapią.
	var local: bool = owner == null or owner.is_multiplayer_authority()
	set_physics_process(local)
	set_process_unhandled_input(local)


func _unhandled_input(event: InputEvent) -> void:
	if held == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_hold_distance = minf(_hold_distance + scroll_step, max_hold_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_hold_distance = maxf(_hold_distance - scroll_step, min_hold_distance)


func _physics_process(_delta: float) -> void:
	if Settings.input_blocked():
		release()
		return
	var player := owner as Player
	if player != null and player.is_down():
		return  # leżący gracz niczego nie łapie (przewrócenie samo puszcza przedmiot)

	if held == null:
		_update_look_target()
		if looked_at != null and Input.is_action_just_pressed("grab"):
			_begin_grab(looked_at, _look_hit_position)
		return

	if not is_instance_valid(held) or not Input.is_action_pressed("grab"):
		release()
		return

	var point_world: Vector3 = held.to_global(_local_point)
	var target: Vector3 = _hold_target()
	if (target - point_world).length() > max_stretch:
		release()
		return
	held.request_update_hold(target)


func release() -> void:
	if held == null:
		return
	var item := held
	held = null
	if is_instance_valid(item):
		item.request_end_hold()
	grab_ended.emit(item)


## Mnożnik prędkości ruchu gracza (1.0 = bez obciążenia).
## Masa dzieli się na wszystkich trzymających (holder_count jest replikowany z hosta).
func get_speed_factor() -> float:
	if held == null or not is_instance_valid(held):
		return 1.0
	var share: float = held.mass / float(maxi(1, held.holder_count))
	return clampf(1.0 - share / heavy_mass, min_speed_factor, 1.0)


func is_holding() -> bool:
	return held != null


func _hold_target() -> Vector3:
	return global_position + (-global_basis.z) * _hold_distance


func _begin_grab(item: Grabbable, hit_position: Vector3) -> void:
	held = item
	_local_point = item.to_local(hit_position)
	_hold_distance = clampf(
		camera.global_position.distance_to(hit_position), min_hold_distance, max_hold_distance
	)
	item.request_begin_hold(_local_point, _hold_target())
	grab_started.emit(item)


func _update_look_target() -> void:
	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_basis.z) * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)  # world + items
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	var found: Grabbable = null
	if not hit.is_empty():
		found = hit["collider"] as Grabbable
		_look_hit_position = hit["position"]

	if found != looked_at:
		looked_at = found
		target_changed.emit(looked_at)
