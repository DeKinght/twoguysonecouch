class_name Player
extends CharacterBody3D
## Postać FPP: ruch, sprint, skok, kucanie, kamera. Chwytanie jest w Grabber.
##
## SIEĆ: każdy gracz symuluje SWOJĄ postać (jest jej autorytetem), więc sterowanie
## nie ma opóźnienia. Stan (net_*) leci do pozostałych przez MultiplayerSynchronizer,
## a cudze postacie wygładzamy interpolacją.

@export_group("Ruch")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.0
@export var crouch_speed: float = 2.2
@export var ground_accel: float = 14.0
@export var air_accel: float = 3.0
@export var jump_velocity: float = 4.5

@export_group("Kamera")
@export var mouse_sensitivity: float = 0.0025

@export_group("Kucanie")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.1
@export var eye_offset: float = 0.2  ## odległość oczu od czubka głowy

@export_group("Fizyka")
## Siła, z jaką gracz popycha luźne przedmioty, na które wpada.
@export var push_force: float = 1.5

@export_group("Sieć")
@export var remote_smoothing: float = 20.0

## Replikowane do pozostałych graczy:
var net_position: Vector3
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_height: float = 1.8

var is_local: bool = true

var _pitch: float = 0.0
var _crouching: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _body_mesh: MeshInstance3D

# Wejście z bieżącej klatki (patrz _read_input).
var _move_input: Vector2 = Vector2.ZERO
var _jump_pressed: bool = false
var _sprint_held: bool = false
var _crouch_held: bool = false

@onready var head: Node3D = $Head
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var camera: Camera3D = $Head/Camera3D
@onready var grabber: Grabber = $Head/Camera3D/Grabber
@onready var _capsule: CapsuleShape3D = collision.shape as CapsuleShape3D


func _ready() -> void:
	is_local = is_multiplayer_authority()
	Net.register_player(self)
	net_position = global_position
	net_yaw = rotation.y
	net_height = stand_height
	_setup_sync()

	if is_local:
		camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.clear_current(false)
		$HUD.queue_free()
		set_process_unhandled_input(false)
		_build_remote_visual()
	_apply_height(stand_height)


func _exit_tree() -> void:
	Net.unregister_player(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		head.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_local:
		_remote_update(delta)
		return

	_read_input()
	_update_crouch(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif _jump_pressed and not _crouching:
		velocity.y = jump_velocity

	var speed: float = walk_speed
	if _crouching:
		speed = crouch_speed
	elif _sprint_held and not grabber.is_holding():
		speed = sprint_speed
	speed *= grabber.get_speed_factor()

	var dir: Vector3 = (global_basis * Vector3(_move_input.x, 0.0, _move_input.y)).normalized()
	var accel: float = ground_accel if is_on_floor() else air_accel
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta * speed)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta * speed)

	move_and_slide()
	_push_bodies()

	net_position = global_position
	net_yaw = rotation.y
	net_pitch = _pitch
	net_height = _capsule.height


func _read_input() -> void:
	_move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_jump_pressed = Input.is_action_just_pressed("jump")
	_sprint_held = Input.is_action_pressed("sprint")
	_crouch_held = Input.is_action_pressed("crouch")


func _update_crouch(delta: float) -> void:
	var want_crouch: bool = _crouch_held
	if _crouching and not want_crouch:
		# Wstajemy tylko jeśli nad głową jest miejsce.
		var extra: float = stand_height - crouch_height
		if test_move(global_transform, Vector3.UP * extra):
			want_crouch = true
	_crouching = want_crouch

	var target_height: float = crouch_height if _crouching else stand_height
	_apply_height(move_toward(_capsule.height, target_height, 6.0 * delta))


func _apply_height(height: float) -> void:
	_capsule.height = height
	collision.position.y = height * 0.5
	head.position.y = height - eye_offset
	if _body_mesh != null:
		(_body_mesh.mesh as CapsuleMesh).height = height
		_body_mesh.position.y = height * 0.5


func _push_bodies() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var item := col.get_collider() as Grabbable
		if item != null and item != grabber.held:
			item.request_push(-col.get_normal() * push_force)


# --- Sieć -----------------------------------------------------------------------

func _remote_update(delta: float) -> void:
	var t: float = 1.0 - exp(-remote_smoothing * delta)
	global_position = global_position.lerp(net_position, t)
	rotation.y = lerp_angle(rotation.y, net_yaw, t)
	head.rotation.x = lerpf(head.rotation.x, net_pitch, t)
	_apply_height(lerpf(_capsule.height, net_height, t))


func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop: String in [":net_position", ":net_yaw", ":net_pitch", ":net_height"]:
		var path := NodePath(prop)
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / 30.0
	# Węzły dodane w kodzie nie dziedziczą autorytetu - ustawiamy go ręcznie.
	sync.set_multiplayer_authority(get_multiplayer_authority())
	add_child(sync)


## Kapsuła + "nos" pokazujący, gdzie ktoś patrzy, + nazwa nad głową.
func _build_remote_visual() -> void:
	var id: int = get_multiplayer_authority()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(id * 0.37, 1.0), 0.6, 0.9)

	_body_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = stand_height
	capsule.material = mat
	_body_mesh.mesh = capsule
	add_child(_body_mesh)

	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.15, 0.15, 0.3)
	nose_mesh.material = mat
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0, -0.4)
	head.add_child(nose)

	var label := Label3D.new()
	label.text = Net.get_player_name(id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.005
	label.position = Vector3(0, stand_height + 0.4, 0)
	add_child(label)
