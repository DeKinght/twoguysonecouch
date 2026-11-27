extends Node3D
## Podgląd modelu postaci: tło, światło, podłoga i kamera krążąca wokół (F6).
## Tryb zrzutów (do sprawdzania modelu bez klikania):
##   Godot --path <projekt> res://scenes/characters/worker_preview.tscn -- --shot=<folder>
## zapisuje front/bok/tył/3-4 jako PNG w <folder> i kończy działanie.
## Z --anims dodatkowo robi zrzuty z boku i 3/4 z kilku chwil każdej animacji (anim_<nazwa>_<n>.png).

@export var model_scene: PackedScene
@export var orbit_radius: float = 3.2
@export var look_height: float = 0.95

var _camera: Camera3D
var _angle: float = 0.0
var _shot_dir: String = ""
var _shot_anims: bool = false
var _model: Node


func _ready() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.82, 0.82, 0.84)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.7, 0.7, 0.72)
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	if model_scene != null:
		_model = model_scene.instantiate()
		add_child(_model)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.make_current()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_dir = arg.trim_prefix("--shot=")
		elif arg == "--anims":
			_shot_anims = true
	if _shot_dir != "":
		_take_shots()


func _process(delta: float) -> void:
	if _shot_dir != "":
		return
	_angle += delta * 0.4
	_place_camera(_angle, orbit_radius)


## Kąt 0 = widok z przodu (postać patrzy w -Z, więc kamera stoi po stronie -Z).
func _place_camera(angle: float, radius: float, height: float = 1.1) -> void:
	_camera.position = Vector3(sin(angle) * radius, height, -cos(angle) * radius)
	_camera.look_at(Vector3(0, look_height, 0))


func _take_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var views: Array = [["front", 0.0, orbit_radius, 1.1], ["side", PI / 2.0, orbit_radius, 1.1],
			["back", PI, orbit_radius, 1.1], ["three_quarter", PI / 4.0, orbit_radius, 1.3],
			["face", 0.25, 1.1, 1.5]]
	for view: Array in views:
		_place_camera(view[1], view[2], view[3])
		if view[0] == "face":
			_camera.look_at(Vector3(0, 1.55, 0))
		for i in 4:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, view[0]])
	if _shot_anims:
		await _take_anim_shots()
	get_tree().quit()


func _take_anim_shots() -> void:
	var player: AnimationPlayer = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		push_warning("Brak AnimationPlayera w modelu")
		return
	for anim_name: String in player.get_animation_list():
		var length: float = player.get_animation(anim_name).length
		for n in 3:
			player.play(anim_name)
			player.seek(length * (0.25 + 0.375 * n) if n < 2 else length, true)
			player.pause()
			for view: Array in [["side", PI / 2.0], ["tq", PI / 4.0]]:
				_place_camera(view[1], orbit_radius, 1.2)
				for i in 3:
					await get_tree().process_frame
				var img: Image = get_viewport().get_texture().get_image()
				img.resize(img.get_width() / 3, img.get_height() / 3)
				img.save_png("%s/anim_%s_%d_%s.png" % [_shot_dir, anim_name, n, view[0]])
