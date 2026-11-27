@tool
class_name WorkerRig
extends Node3D
## Model grywalnej postaci (robotnik) z Blendera: assets/models/characters/worker.glb.
## Źródło modelu: tools/blender/build_worker.py (przebudowa: patrz opis w tym pliku).
##
## Szkielet ma nazwy kości z humanoidalnego profilu Godota (Hips, Spine, Chest, Neck, Head,
## Left/Right Shoulder/UpperArm/LowerArm/Hand, Left/Right UpperLeg/LowerLeg/Foot), wagi
## policzone w Blenderze - animacje robi się w AnimationPlayerze na kościach Skeleton3D.
## Poza spoczynkowa: A-pose. Animacje (z Blendera): Idle, Walk, Crouch, CrouchWalk, Jump, Fall, Sit. Postać patrzy w -Z (jak gracz). Wysokość z kaskiem ~1,75 m.

const MODEL_PATH: String = "res://assets/models/characters/worker.glb"

const LOOPING: Array[String] = ["Idle", "Walk", "Crouch", "CrouchWalk", "Sit"]
## Prędkość [m/s], przy której animacja chodu leci w normalnym tempie.
const WALK_ANIM_SPEED: float = 3.2
const CROUCH_ANIM_SPEED: float = 1.8

var skeleton: Skeleton3D
var anim: AnimationPlayer
var _air_time: float = 0.0


func _ready() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			child.queue_free()
	if not ResourceLoader.exists(MODEL_PATH):
		push_warning("Brak modelu postaci: %s" % MODEL_PATH)
		return
	var model: Node3D = (load(MODEL_PATH) as PackedScene).instantiate()
	model.name = "Model"
	model.set_meta("generated", true)
	add_child(model)
	skeleton = _find_skeleton(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null:
		for anim_name: String in LOOPING:
			if anim.has_animation(anim_name):
				anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		anim.play("Idle")


## Wybiera animację ze stanu postaci (działa też dla graczy sieciowych - wszystko
## da się odczytać z prędkości, kapsuły i flag synchronizowanych przez sieć).
func update_animation(delta: float, on_floor: bool, ground_speed: float, crouching: bool,
		down: bool, seated: bool) -> void:
	if anim == null:
		return
	_air_time = 0.0 if on_floor else _air_time + delta
	var target: String = "Idle"
	var speed_scale: float = 1.0
	var blend: float = 0.2
	if seated:
		target = "Sit"
	elif down:
		target = "Fall"
		blend = 0.1
	elif _air_time > 0.12:
		target = "Jump"
		blend = 0.1
	elif crouching:
		target = "CrouchWalk" if ground_speed > 0.4 else "Crouch"
		if target == "CrouchWalk":
			speed_scale = clampf(ground_speed / CROUCH_ANIM_SPEED, 0.5, 2.0)
	elif ground_speed > 0.6:
		target = "Walk"
		speed_scale = clampf(ground_speed / WALK_ANIM_SPEED, 0.6, 2.4)
	if target == "Idle" and anim.current_animation == "Fall":
		blend = 0.45  # wstawanie
	if anim.current_animation != target:
		anim.play(target, blend)
	anim.speed_scale = speed_scale


## Pochyla głowę za wzrokiem gracza (pitch w radianach, dodatni = w górę), łagodniej niż kamera.
func set_head_pitch(pitch: float) -> void:
	if skeleton == null:
		return
	var idx: int = skeleton.find_bone("Head")
	if idx < 0:
		return
	var rest: Quaternion = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(idx, rest * Quaternion(Vector3.RIGHT, clampf(pitch, -1.2, 1.2) * 0.5))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null
