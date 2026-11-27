extends Node3D
## Scena pokazowa: wszystkie warianty z katalogu w rzędach, z podpisami i obracającą się kamerą.
## Otwórz scenes/props/boxes/showcase.tscn (kartony) albo scenes/props/decor/showcase.tscn
## (dekoracje) i wciśnij F6.

## 0 = kartony (BoxCatalog), 1 = dekoracje (DecorCatalog).
@export var catalog: int = 0

var COLUMNS: int = 6
var SPACING: float = 1.6

var _camera: Camera3D
var _angle: float = 0.0
var _center: Vector3


func _ready() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.14, 0.2)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.45, 0.45, 0.47)
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	var names: Array[String] = BoxCatalog.ALL if catalog == 0 else DecorCatalog.ALL
	if catalog == 1:
		COLUMNS = 7
		SPACING = 0.9
	var rows: int = ceili(float(names.size()) / COLUMNS)
	for i in names.size():
		var box_name: String = names[i]
		var pos := Vector3((i % COLUMNS) * SPACING, 0, (i / COLUMNS) * SPACING)
		var scene: PackedScene = BoxCatalog.scene(box_name) if catalog == 0 else DecorCatalog.scene(box_name)
		var box: Node3D = scene.instantiate()
		box.position = pos
		box.rotation.y = -0.5
		add_child(box)
		var label := Label3D.new()
		label.text = box_name
		label.pixel_size = 0.003
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = pos + Vector3(0, 1.55 if catalog == 0 else 0.75, 0)
		add_child(label)

	_center = Vector3((COLUMNS - 1) * SPACING * 0.5, 0.4, (rows - 1) * SPACING * 0.5)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	_angle += delta * 0.25
	var radius: float = 7.5 if catalog == 0 else 5.5
	_camera.position = _center + Vector3(sin(_angle) * radius, 3.2, cos(_angle) * radius)
	_camera.look_at(_center)
