class_name CharacterModel
extends Node3D
## Postać tragarza: szkielet (Skeleton3D, 17 kości), gładka siatka ze skinningiem i animacje.
##
## Siatki (assets/characters/*.res) są wyrzeźbione skryptem tools/characters/sculpt.py
## (miękko łączone kształty + marching cubes, wagi kości płynnie przechodzą na stawach)
## i zamienione na zasoby Godota przez tools/characters/build_meshes.gd.
## Pozycje kości poniżej muszą się zgadzać z BONES w sculpt.py.
##
## Postać stoi stopami w (0, 0, 0) i patrzy w -Z (jak Player).
## Stan ustawia Player co klatkę: update_state(...) - model sam wybiera animację.

const VARIANTS: Array[Dictionary] = [
	{"name": "Bartek", "mesh": "res://assets/characters/bartek.res"},
	{"name": "Ola", "mesh": "res://assets/characters/ola.res"},
	{"name": "Dawid", "mesh": "res://assets/characters/dawid.res"},
]

## Kości: nazwa, rodzic, położenie względem rodzica (poza spoczynkowa bez rotacji).
const BONES: Array = [
	["Root", "", Vector3.ZERO],
	["Hips", "Root", Vector3(0, 0.72, 0)],
	["Spine", "Hips", Vector3(0, 0.2, 0)],
	["Chest", "Spine", Vector3(0, 0.22, 0)],
	["Neck", "Chest", Vector3(0, 0.22, 0)],
	["Head", "Neck", Vector3(0, 0.08, 0)],
	["UpperArm.L", "Chest", Vector3(-0.31, 0.15, 0)],
	["LowerArm.L", "UpperArm.L", Vector3(-0.05, -0.26, 0)],
	["Hand.L", "LowerArm.L", Vector3(-0.03, -0.22, 0)],
	["UpperArm.R", "Chest", Vector3(0.31, 0.15, 0)],
	["LowerArm.R", "UpperArm.R", Vector3(0.05, -0.26, 0)],
	["Hand.R", "LowerArm.R", Vector3(0.03, -0.22, 0)],
	["UpperLeg.L", "Hips", Vector3(-0.14, -0.04, 0)],
	["LowerLeg.L", "UpperLeg.L", Vector3(0, -0.3, 0)],
	["Foot.L", "LowerLeg.L", Vector3(0, -0.27, 0)],
	["UpperLeg.R", "Hips", Vector3(0.14, -0.04, 0)],
	["LowerLeg.R", "UpperLeg.R", Vector3(0, -0.3, 0)],
	["Foot.R", "LowerLeg.R", Vector3(0, -0.27, 0)],
]
const HIPS_REST: Vector3 = Vector3(0, 0.72, 0)

## Prędkość [m/s], przy której animacja chodu ma tempo 1.0, i próg biegu.
const WALK_ANIM_SPEED: float = 3.2
const RUN_ANIM_SPEED: float = 6.0
const RUN_THRESHOLD: float = 5.6

var variant: int = 0
var skeleton: Skeleton3D
var anim: AnimationPlayer

var _mesh_instance: MeshInstance3D
var _state: String = ""


func setup(variant_index: int) -> void:
	variant = posmod(variant_index, VARIANTS.size())
	_build_skeleton()
	_build_mesh(VARIANTS[variant]["mesh"])
	_build_animations()
	play_state("idle")


## Warstwa renderowania (np. własna postać niewidoczna dla własnej kamery FPP).
func set_render_layers(mask: int) -> void:
	if _mesh_instance != null:
		_mesh_instance.layers = mask


## speed: prędkość pozioma [m/s], crouch: 0..1, holding: niesie coś, seated: siedzi w aucie.
func update_state(speed: float, crouch: float, on_floor: bool, down: bool, holding: bool, seated: bool) -> void:
	var state: String
	if down:
		state = "fall"
	elif seated:
		state = "sit"
	elif not on_floor:
		state = "jump"
	elif crouch > 0.5:
		state = "crouch_walk" if speed > 0.4 else "crouch"
	elif holding:
		state = "carry_walk" if speed > 0.4 else "carry"
	elif speed > RUN_THRESHOLD:
		state = "run"
	elif speed > 0.4:
		state = "walk"
	else:
		state = "idle"
	play_state(state)
	match state:
		"walk", "carry_walk", "crouch_walk":
			anim.speed_scale = clampf(speed / (WALK_ANIM_SPEED * (0.5 if state == "crouch_walk" else 1.0)), 0.5, 1.8)
		"run":
			anim.speed_scale = clampf(speed / RUN_ANIM_SPEED, 0.8, 1.4)
		_:
			anim.speed_scale = 1.0


func play_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	anim.play(state, 0.2)


func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b: Array in BONES:
		var idx: int = skeleton.add_bone(b[0])
		if b[1] != "":
			skeleton.set_bone_parent(idx, skeleton.find_bone(b[1]))
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, b[2]))
	skeleton.reset_bone_poses()


func _build_mesh(path: String) -> void:
	var mesh := (load(path) as ArrayMesh).duplicate() as ArrayMesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true  # kolory z palety są w sRGB
	mat.roughness = 0.85
	mat.metallic_specular = 0.25
	mat.rim_enabled = true  # lekka poświata na krawędziach - "miękki", bajkowy wygląd
	mat.rim = 0.25
	mat.rim_tint = 0.6
	mesh.surface_set_material(0, mat)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Body"
	_mesh_instance.mesh = mesh
	skeleton.add_child(_mesh_instance)
	_mesh_instance.skeleton = NodePath("..")
	_mesh_instance.skin = skeleton.create_skin_from_rest_transforms()


# --- Animacje ----------------------------------------------------------------------------
# Kąty w stopniach (X, Y, Z). Konwencja: +X na udzie/ramieniu = do przodu,
# -X na łydce = zgięcie kolana, +X na przedramieniu = zgięcie łokcia,
# -X na kręgosłupie/klatce = pochylenie do przodu.

func _build_animations() -> void:
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _anim_idle())
	lib.add_animation("walk", _anim_walk(0.8, 28.0, 1.0, false))
	lib.add_animation("run", _anim_walk(0.55, 48.0, 1.6, false))
	lib.add_animation("carry", _anim_carry(false))
	lib.add_animation("carry_walk", _anim_carry(true))
	lib.add_animation("crouch", _anim_crouch(false))
	lib.add_animation("crouch_walk", _anim_crouch(true))
	lib.add_animation("sit", _anim_sit())
	lib.add_animation("jump", _anim_jump())
	lib.add_animation("fall", _anim_fall())
	anim.add_animation_library("", lib)


## Animacja z kluczy: rots = {kość: [[czas, Vector3(stopnie)], ...]}, hips = [[czas, przesunięcie]].
## Kości bez kluczy dostają rotację zerową (żeby poprzednia animacja ich nie "zostawiła").
func _make(length: float, rots: Dictionary, hips: Array = [], loop: bool = true) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for b: Array in BONES:
		var bone: String = b[0]
		if bone == "Root":
			continue
		var t: int = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:" + bone))
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		var keys: Array = rots.get(bone, [[0.0, Vector3.ZERO]])
		for k: Array in keys:
			var e: Vector3 = k[1]
			a.rotation_track_insert_key(t, k[0], Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))))
	var tp: int = a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tp, NodePath("Skeleton3D:Hips"))
	a.track_set_interpolation_type(tp, Animation.INTERPOLATION_CUBIC)
	if hips.is_empty():
		hips = [[0.0, Vector3.ZERO]]
	for k: Array in hips:
		a.position_track_insert_key(tp, k[0], HIPS_REST + (k[1] as Vector3))
	return a


## Klucze okresowe: wartości v równo rozłożone w czasie, ostatni klucz = pierwszy (pętla).
func _cycle(length: float, values: Array) -> Array:
	var out: Array = []
	var n: int = values.size()
	for i in n:
		out.append([length * i / n, values[i]])
	out.append([length, values[0]])
	return out


func _anim_idle() -> Animation:
	var L: float = 2.4
	return _make(L, {
		"Chest": _cycle(L, [Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0)]),
		"Head": _cycle(L, [Vector3(-2, 3, 0), Vector3(1, -3, 0)]),
		"UpperArm.L": _cycle(L, [Vector3(0, 0, -6), Vector3(2, 0, -8)]),
		"UpperArm.R": _cycle(L, [Vector3(0, 0, 6), Vector3(2, 0, 8)]),
		"LowerArm.L": [[0.0, Vector3(12, 0, 0)]],
		"LowerArm.R": [[0.0, Vector3(12, 0, 0)]],
	}, _cycle(L, [Vector3(0, 0, 0), Vector3(0, -0.012, 0)]))


## Chód / bieg: amp = wymach ud [°], k = mnożnik dla rąk, kolan i podskoku.
func _anim_walk(L: float, amp: float, k: float, carry_arms: bool) -> Animation:
	var a: float = amp
	var leg_l: Array = [Vector3(a, 0, 0), Vector3(0, 0, 0), Vector3(-a, 0, 0), Vector3(0, 0, 0)]
	var leg_r: Array = [leg_l[2], leg_l[3], leg_l[0], leg_l[1]]
	var knee_l: Array = [Vector3(-8, 0, 0), Vector3(-15 * k, 0, 0), Vector3(-25 * k, 0, 0), Vector3(-55 * k, 0, 0)]
	var knee_r: Array = [knee_l[2], knee_l[3], knee_l[0], knee_l[1]]
	var foot_l: Array = [Vector3(-10, 0, 0), Vector3(0, 0, 0), Vector3(15, 0, 0), Vector3(20, 0, 0)]
	var foot_r: Array = [foot_l[2], foot_l[3], foot_l[0], foot_l[1]]
	var lean: float = -6.0 * k
	var rots: Dictionary = {
		"UpperLeg.L": _cycle(L, leg_l), "UpperLeg.R": _cycle(L, leg_r),
		"LowerLeg.L": _cycle(L, knee_l), "LowerLeg.R": _cycle(L, knee_r),
		"Foot.L": _cycle(L, foot_l), "Foot.R": _cycle(L, foot_r),
		"Spine": _cycle(L, [Vector3(lean, 6, 0), Vector3(lean, 0, 0), Vector3(lean, -6, 0), Vector3(lean, 0, 0)]),
		"Head": [[0.0, Vector3(-lean * 0.6, 0, 0)]],
	}
	if carry_arms:
		_add_carry_arms(rots)
	else:
		var arm: float = a * 0.9
		rots["UpperArm.L"] = _cycle(L, [Vector3(-arm, 0, -8), Vector3(0, 0, -8), Vector3(arm, 0, -8), Vector3(0, 0, -8)])
		rots["UpperArm.R"] = _cycle(L, [Vector3(arm, 0, 8), Vector3(0, 0, 8), Vector3(-arm, 0, 8), Vector3(0, 0, 8)])
		rots["LowerArm.L"] = [[0.0, Vector3(25 * k, 0, 0)]]
		rots["LowerArm.R"] = [[0.0, Vector3(25 * k, 0, 0)]]
	var bob: float = 0.03 * k
	return _make(L, rots, _cycle(L, [Vector3(0, 0, 0), Vector3(0, bob, 0), Vector3(0, 0, 0), Vector3(0, bob, 0)]))


func _add_carry_arms(rots: Dictionary) -> void:
	rots["UpperArm.L"] = [[0.0, Vector3(72, 0, 10)]]
	rots["UpperArm.R"] = [[0.0, Vector3(72, 0, -10)]]
	rots["LowerArm.L"] = [[0.0, Vector3(25, 0, 0)]]
	rots["LowerArm.R"] = [[0.0, Vector3(25, 0, 0)]]
	rots["Chest"] = [[0.0, Vector3(6, 0, 0)]]  # odchylenie do tyłu pod ciężarem


func _anim_carry(walking: bool) -> Animation:
	if walking:
		return _anim_walk(0.9, 20.0, 0.8, true)
	var rots: Dictionary = {}
	_add_carry_arms(rots)
	rots["Head"] = _cycle(2.0, [Vector3(0, 0, 0), Vector3(2, 0, 0)])
	return _make(2.0, rots)


func _anim_crouch(walking: bool) -> Animation:
	var L: float = 1.0
	var base: Dictionary = {
		"Spine": [[0.0, Vector3(-22, 0, 0)]],
		"Head": [[0.0, Vector3(15, 0, 0)]],
		"UpperArm.L": [[0.0, Vector3(30, 0, -10)]],
		"UpperArm.R": [[0.0, Vector3(30, 0, 10)]],
		"LowerArm.L": [[0.0, Vector3(40, 0, 0)]],
		"LowerArm.R": [[0.0, Vector3(40, 0, 0)]],
	}
	var thigh: float = 72.0
	var knee: float = -112.0
	var foot: float = 40.0
	if walking:
		base["UpperLeg.L"] = _cycle(L, [Vector3(thigh + 15, 0, 0), Vector3(thigh, 0, 0), Vector3(thigh - 15, 0, 0), Vector3(thigh, 0, 0)])
		base["UpperLeg.R"] = _cycle(L, [Vector3(thigh - 15, 0, 0), Vector3(thigh, 0, 0), Vector3(thigh + 15, 0, 0), Vector3(thigh, 0, 0)])
	else:
		base["UpperLeg.L"] = [[0.0, Vector3(thigh, 0, 0)]]
		base["UpperLeg.R"] = [[0.0, Vector3(thigh, 0, 0)]]
	base["LowerLeg.L"] = [[0.0, Vector3(knee, 0, 0)]]
	base["LowerLeg.R"] = [[0.0, Vector3(knee, 0, 0)]]
	base["Foot.L"] = [[0.0, Vector3(foot, 0, 0)]]
	base["Foot.R"] = [[0.0, Vector3(foot, 0, 0)]]
	return _make(L, base, [[0.0, Vector3(0, -0.27, 0)]])


## Siedzenie: staw biodrowy na wysokości siedziska, 0,25 m nad punktem postaci (Van.seat_transform).
func _anim_sit() -> Animation:
	return _make(2.0, {
		"UpperLeg.L": [[0.0, Vector3(88, 0, -4)]],
		"UpperLeg.R": [[0.0, Vector3(88, 0, 4)]],
		"LowerLeg.L": [[0.0, Vector3(-78, 0, 0)]],
		"LowerLeg.R": [[0.0, Vector3(-78, 0, 0)]],
		"UpperArm.L": [[0.0, Vector3(40, 0, -6)]],
		"UpperArm.R": [[0.0, Vector3(40, 0, 6)]],
		"LowerArm.L": [[0.0, Vector3(45, 0, 0)]],
		"LowerArm.R": [[0.0, Vector3(45, 0, 0)]],
		"Head": _cycle(3.0, [Vector3(0, 4, 0), Vector3(0, -4, 0)]),
	}, [[0.0, Vector3(0, 0.29 - HIPS_REST.y, 0.05)]])


func _anim_jump() -> Animation:
	return _make(1.0, {
		"UpperArm.L": [[0.0, Vector3(20, 0, -55)]],
		"UpperArm.R": [[0.0, Vector3(20, 0, 55)]],
		"LowerArm.L": [[0.0, Vector3(30, 0, 0)]],
		"LowerArm.R": [[0.0, Vector3(30, 0, 0)]],
		"UpperLeg.L": [[0.0, Vector3(35, 0, 0)]],
		"UpperLeg.R": [[0.0, Vector3(5, 0, 0)]],
		"LowerLeg.L": [[0.0, Vector3(-60, 0, 0)]],
		"LowerLeg.R": [[0.0, Vector3(-30, 0, 0)]],
	})


## Przewrócenie: rozrzucone ręce i nogi, wymachy (cała postać kładzie się w Player).
func _anim_fall() -> Animation:
	var L: float = 0.6
	return _make(L, {
		"UpperArm.L": _cycle(L, [Vector3(30, 0, -80), Vector3(-20, 0, -100)]),
		"UpperArm.R": _cycle(L, [Vector3(-20, 0, 100), Vector3(30, 0, 80)]),
		"LowerArm.L": [[0.0, Vector3(30, 0, 0)]],
		"LowerArm.R": [[0.0, Vector3(30, 0, 0)]],
		"UpperLeg.L": _cycle(L, [Vector3(30, 0, -15), Vector3(10, 0, -25)]),
		"UpperLeg.R": _cycle(L, [Vector3(10, 0, 25), Vector3(30, 0, 15)]),
		"LowerLeg.L": [[0.0, Vector3(-40, 0, 0)]],
		"LowerLeg.R": [[0.0, Vector3(-40, 0, 0)]],
		"Head": _cycle(L, [Vector3(-10, 15, 0), Vector3(-10, -15, 0)]),
	})
