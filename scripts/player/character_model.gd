class_name CharacterModel
extends Node3D
## Postać tragarza: szkielet (Skeleton3D, 17 kości), siatka ze skinningiem i animacje.
## Wszystko budowane w kodzie, więc nie ma plików .glb do importu.
##
## Wygląd: krępi, zabawni tragarze z dużą głową i krótkimi nogami. Wariant (`VARIANTS`)
## zmienia kolory ubrania, nakrycie głowy i dodatki (wąsy, broda, okulary, brzuch...).
##
## Postać stoi stopami w (0, 0, 0) i patrzy w -Z (jak Player). Każdy element siatki
## jest przypięty w 100% do jednej kości (sztywne części jak u figurki).
##
## Stan ustawia Player co klatkę: update_state(...) - model sam wybiera animację.

const VARIANTS: Array[Dictionary] = [
	{"name": "Rudy", "skin": Color(0.96, 0.78, 0.64), "shirt": Color(0.95, 0.5, 0.12), "pants": Color(0.95, 0.5, 0.12),
		"shoes": Color(0.25, 0.18, 0.12), "gloves": Color(0.98, 0.82, 0.2), "hat": "cap", "hat_color": Color(0.85, 0.15, 0.15),
		"hair": Color(0.8, 0.35, 0.12), "extras": ["freckles"], "scale": Vector3(1.0, 1.0, 1.0)},
	{"name": "Zenek", "skin": Color(0.9, 0.7, 0.58), "shirt": Color(0.2, 0.35, 0.7), "pants": Color(0.25, 0.3, 0.42),
		"shoes": Color(0.15, 0.15, 0.17), "gloves": Color(0.45, 0.3, 0.2), "hat": "beanie", "hat_color": Color(0.55, 0.55, 0.58),
		"hair": Color(0.2, 0.15, 0.1), "extras": ["mustache", "belly"], "scale": Vector3(1.08, 0.97, 1.08)},
	{"name": "Ola", "skin": Color(0.98, 0.84, 0.72), "shirt": Color(0.75, 0.95, 0.15), "pants": Color(0.2, 0.22, 0.26),
		"shoes": Color(0.6, 0.3, 0.15), "gloves": Color(0.3, 0.3, 0.32), "hat": "helmet", "hat_color": Color(1.0, 0.82, 0.1),
		"hair": Color(0.45, 0.25, 0.12), "extras": ["ponytail", "vest_stripes"], "scale": Vector3(0.95, 0.98, 0.95)},
	{"name": "Bonzo", "skin": Color(0.62, 0.42, 0.3), "shirt": Color(0.5, 0.25, 0.7), "pants": Color(0.5, 0.25, 0.7),
		"shoes": Color(0.95, 0.95, 0.95), "gloves": Color(0.95, 0.95, 0.95), "hat": "bucket", "hat_color": Color(0.85, 0.78, 0.6),
		"hair": Color(0.1, 0.08, 0.07), "extras": ["sunglasses", "stripes"], "scale": Vector3(1.0, 1.03, 1.0)},
	{"name": "Wiesiek", "skin": Color(0.94, 0.76, 0.66), "shirt": Color(0.5, 0.52, 0.5), "pants": Color(0.4, 0.42, 0.4),
		"shoes": Color(0.3, 0.2, 0.12), "gloves": Color(0.75, 0.6, 0.4), "hat": "none", "hat_color": Color(0, 0, 0),
		"hair": Color(0.75, 0.72, 0.68), "extras": ["beard", "bald"], "scale": Vector3(1.0, 1.06, 1.0)},
	{"name": "Kaśka", "skin": Color(0.85, 0.64, 0.5), "shirt": Color(0.9, 0.2, 0.4), "pants": Color(0.18, 0.32, 0.6),
		"shoes": Color(0.9, 0.9, 0.92), "gloves": Color(0.2, 0.6, 0.55), "hat": "headband", "hat_color": Color(0.2, 0.75, 0.7),
		"hair": Color(0.12, 0.08, 0.06), "extras": ["bun"], "scale": Vector3(0.94, 0.96, 0.94)},
]

## Kości: nazwa, rodzic, położenie względem rodzica (pozycja spoczynkowa, "T" bez rotacji).
const BONES: Array = [
	["Root", "", Vector3.ZERO],
	["Hips", "Root", Vector3(0, 0.95, 0)],
	["Spine", "Hips", Vector3(0, 0.15, 0)],
	["Chest", "Spine", Vector3(0, 0.25, 0)],
	["Neck", "Chest", Vector3(0, 0.2, 0)],
	["Head", "Neck", Vector3(0, 0.08, 0)],
	["UpperArm.L", "Chest", Vector3(-0.3, 0.14, 0)],
	["LowerArm.L", "UpperArm.L", Vector3(0, -0.28, 0)],
	["Hand.L", "LowerArm.L", Vector3(0, -0.25, 0)],
	["UpperArm.R", "Chest", Vector3(0.3, 0.14, 0)],
	["LowerArm.R", "UpperArm.R", Vector3(0, -0.28, 0)],
	["Hand.R", "LowerArm.R", Vector3(0, -0.25, 0)],
	["UpperLeg.L", "Hips", Vector3(-0.13, -0.05, 0)],
	["LowerLeg.L", "UpperLeg.L", Vector3(0, -0.42, 0)],
	["Foot.L", "LowerLeg.L", Vector3(0, -0.4, 0)],
	["UpperLeg.R", "Hips", Vector3(0.13, -0.05, 0)],
	["LowerLeg.R", "UpperLeg.R", Vector3(0, -0.42, 0)],
	["Foot.R", "LowerLeg.R", Vector3(0, -0.4, 0)],
]
const HIPS_REST: Vector3 = Vector3(0, 0.95, 0)

## Prędkość [m/s], przy której animacja chodu ma tempo 1.0, i próg biegu.
const WALK_ANIM_SPEED: float = 3.6
const RUN_ANIM_SPEED: float = 6.5
const RUN_THRESHOLD: float = 5.6

var variant: int = 0
var skeleton: Skeleton3D
var anim: AnimationPlayer

var _mesh_instance: MeshInstance3D
var _bone_global: Dictionary = {}  ## nazwa -> pozycja spoczynkowa w układzie postaci
var _state: String = ""


func setup(variant_index: int) -> void:
	variant = posmod(variant_index, VARIANTS.size())
	var v: Dictionary = VARIANTS[variant]
	scale = v["scale"]
	_build_skeleton()
	_build_mesh(v)
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
			anim.speed_scale = clampf(speed / (WALK_ANIM_SPEED * (0.5 if state == "crouch_walk" else 1.0)), 0.5, 1.7)
		"run":
			anim.speed_scale = clampf(speed / RUN_ANIM_SPEED, 0.8, 1.4)
		_:
			anim.speed_scale = 1.0


func play_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	anim.play(state, 0.18)


# --- Szkielet ----------------------------------------------------------------------

func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b: Array in BONES:
		var idx: int = skeleton.add_bone(b[0])
		if b[1] != "":
			skeleton.set_bone_parent(idx, skeleton.find_bone(b[1]))
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, b[2]))
		_bone_global[b[0]] = (_bone_global.get(b[1], Vector3.ZERO) as Vector3) + (b[2] as Vector3)
	skeleton.reset_bone_poses()


# --- Siatka ---------------------------------------------------------------------------

func _build_mesh(v: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin: Color = v["skin"]
	var shirt: Color = v["shirt"]
	var pants: Color = v["pants"]
	var shoes: Color = v["shoes"]
	var gloves: Color = v["gloves"]
	var extras: Array = v["extras"]
	var dark := Color(0.08, 0.08, 0.1)

	# Tułów
	_box(st, "Hips", Vector3(0, 0.94, 0), Vector3(0.44, 0.24, 0.3), pants)
	var belly: bool = "belly" in extras
	_box(st, "Spine", Vector3(0, 1.14, 0), Vector3(0.46, 0.26, 0.32), shirt)
	if belly:
		_sphere(st, "Spine", Vector3(0, 1.12, -0.1), Vector3(0.3, 0.26, 0.24), shirt)
	_box(st, "Chest", Vector3(0, 1.38, 0), Vector3(0.54, 0.3, 0.34), shirt)
	if "vest_stripes" in extras:
		for y: float in [1.2, 1.36]:
			_box(st, "Chest" if y > 1.3 else "Spine", Vector3(0, y, -0.005), Vector3(0.56, 0.04, 0.35), Color(0.85, 0.88, 0.9))
	if "stripes" in extras:
		for x: float in [-0.29, 0.29]:
			_box(st, "Chest", Vector3(x, 1.38, 0), Vector3(0.02, 0.28, 0.35), Color(0.95, 0.95, 0.95))
	_cylinder(st, "Neck", Vector3(0, 1.57, 0), 0.08, 0.1, skin)

	# Głowa (duża, lekko spłaszczona kula)
	var head_c := Vector3(0, 1.78, 0)
	_sphere(st, "Head", head_c, Vector3(0.42, 0.4, 0.4), skin)
	_sphere(st, "Head", head_c + Vector3(0, -0.03, -0.2), Vector3(0.08, 0.07, 0.08), skin.darkened(0.08))   # nos
	for side: float in [-1.0, 1.0]:
		_sphere(st, "Head", head_c + Vector3(0.08 * side, 0.05, -0.185), Vector3(0.05, 0.06, 0.03), dark)   # oczy
		_sphere(st, "Head", head_c + Vector3(0.205 * side, 0.0, 0), Vector3(0.05, 0.08, 0.06), skin)        # uszy
	if "sunglasses" in extras:
		_box(st, "Head", head_c + Vector3(0, 0.05, -0.19), Vector3(0.3, 0.07, 0.04), dark)
	if "freckles" in extras:
		for p: Vector2 in [Vector2(-0.11, -0.01), Vector2(-0.07, -0.03), Vector2(0.11, -0.01), Vector2(0.07, -0.03)]:
			_sphere(st, "Head", head_c + Vector3(p.x, p.y, -0.19), Vector3(0.018, 0.018, 0.01), Color(0.75, 0.45, 0.3))
	if "mustache" in extras:
		_box(st, "Head", head_c + Vector3(0, -0.09, -0.19), Vector3(0.18, 0.04, 0.04), v["hair"])
	if "beard" in extras:
		_sphere(st, "Head", head_c + Vector3(0, -0.13, -0.11), Vector3(0.3, 0.24, 0.2), v["hair"])
	var hair: Color = v["hair"]
	if not ("bald" in extras):
		_sphere(st, "Head", head_c + Vector3(0, 0.12, 0.06), Vector3(0.42, 0.3, 0.38), hair)  # czupryna: góra i tył głowy
	if "ponytail" in extras:
		_sphere(st, "Head", head_c + Vector3(0, 0.0, 0.22), Vector3(0.1, 0.22, 0.1), hair)
	if "bun" in extras:
		_sphere(st, "Head", head_c + Vector3(0, 0.2, 0.12), Vector3(0.14, 0.14, 0.14), hair)
	_build_hat(st, v["hat"], v["hat_color"], head_c)

	# Ręce
	for side: String in ["L", "R"]:
		var sx: float = -1.0 if side == "L" else 1.0
		_capsule(st, "UpperArm." + side, Vector3(0.31 * sx, 1.37, 0), 0.08, 0.34, shirt)
		_capsule(st, "LowerArm." + side, Vector3(0.31 * sx, 1.11, 0), 0.07, 0.3, skin)
		_sphere(st, "Hand." + side, Vector3(0.31 * sx, 0.93, 0), Vector3(0.17, 0.17, 0.17), gloves)
		# Nogi
		_capsule(st, "UpperLeg." + side, Vector3(0.13 * sx, 0.7, 0), 0.1, 0.46, pants)
		_capsule(st, "LowerLeg." + side, Vector3(0.13 * sx, 0.3, 0), 0.09, 0.42, pants.darkened(0.08))
		_box(st, "Foot." + side, Vector3(0.13 * sx, 0.055, -0.05), Vector3(0.16, 0.11, 0.3), shoes)

	var mesh: ArrayMesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.metallic_specular = 0.2
	mesh.surface_set_material(0, mat)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Body"
	_mesh_instance.mesh = mesh
	skeleton.add_child(_mesh_instance)
	_mesh_instance.skeleton = NodePath("..")
	_mesh_instance.skin = skeleton.create_skin_from_rest_transforms()


func _build_hat(st: SurfaceTool, hat: String, color: Color, head_c: Vector3) -> void:
	match hat:
		"cap":
			_sphere(st, "Head", head_c + Vector3(0, 0.13, 0.01), Vector3(0.44, 0.28, 0.43), color)
			_box(st, "Head", head_c + Vector3(0, 0.13, -0.25), Vector3(0.3, 0.03, 0.18), color.darkened(0.15))
		"beanie":
			_sphere(st, "Head", head_c + Vector3(0, 0.14, 0.01), Vector3(0.44, 0.3, 0.43), color)
			_sphere(st, "Head", head_c + Vector3(0, 0.3, 0.01), Vector3(0.1, 0.1, 0.1), color.lightened(0.3))
		"helmet":
			_sphere(st, "Head", head_c + Vector3(0, 0.15, 0.0), Vector3(0.46, 0.3, 0.46), color)
			_cylinder(st, "Head", head_c + Vector3(0, 0.12, 0.0), 0.25, 0.03, color.darkened(0.1))
		"bucket":
			_cylinder(st, "Head", head_c + Vector3(0, 0.2, 0.0), 0.2, 0.18, color)
			_cylinder(st, "Head", head_c + Vector3(0, 0.13, 0.0), 0.3, 0.03, color.darkened(0.1))
		"headband":
			_cylinder(st, "Head", head_c + Vector3(0, 0.12, 0.0), 0.2, 0.06, color)


func _add(st: SurfaceTool, bone: String, arrays: Array, xform: Transform3D, color: Color) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis: Basis = xform.basis.inverse().transposed()  # poprawne normalne przy skalowaniu
	var bones := PackedInt32Array([skeleton.find_bone(bone), 0, 0, 0])
	var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	for i in range(0, idx.size(), 3):
		for k in 3:
			st.set_normal((normal_basis * normals[idx[i + k]]).normalized())
			st.set_color(color)
			st.set_bones(bones)
			st.set_weights(weights)
			st.add_vertex(xform * verts[idx[i + k]])


func _box(st: SurfaceTool, bone: String, center: Vector3, size: Vector3, color: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(st, bone, m.get_mesh_arrays(), Transform3D(Basis.IDENTITY, center), color)


func _sphere(st: SurfaceTool, bone: String, center: Vector3, size: Vector3, color: Color) -> void:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 14
	m.rings = 8
	_add(st, bone, m.get_mesh_arrays(), Transform3D(Basis.from_scale(size), center), color)


func _capsule(st: SurfaceTool, bone: String, center: Vector3, radius: float, height: float, color: Color) -> void:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 4
	_add(st, bone, m.get_mesh_arrays(), Transform3D(Basis.IDENTITY, center), color)


func _cylinder(st: SurfaceTool, bone: String, center: Vector3, radius: float, height: float, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 14
	_add(st, bone, m.get_mesh_arrays(), Transform3D(Basis.IDENTITY, center), color)


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
	return _make(L, base, [[0.0, Vector3(0, -0.4, 0)]])


## Siedzenie: biodra na wysokości 0,25 m nad punktem postaci (tak ustawia Van.seat_transform).
func _anim_sit() -> Animation:
	return _make(2.0, {
		"UpperLeg.L": [[0.0, Vector3(88, 0, -4)]],
		"UpperLeg.R": [[0.0, Vector3(88, 0, 4)]],
		"LowerLeg.L": [[0.0, Vector3(-85, 0, 0)]],
		"LowerLeg.R": [[0.0, Vector3(-85, 0, 0)]],
		"UpperArm.L": [[0.0, Vector3(40, 0, -6)]],
		"UpperArm.R": [[0.0, Vector3(40, 0, 6)]],
		"LowerArm.L": [[0.0, Vector3(45, 0, 0)]],
		"LowerArm.R": [[0.0, Vector3(45, 0, 0)]],
		"Head": _cycle(3.0, [Vector3(0, 4, 0), Vector3(0, -4, 0)]),
	}, [[0.0, Vector3(0, 0.25 - HIPS_REST.y, 0.05)]])


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
