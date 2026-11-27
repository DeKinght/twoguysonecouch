class_name Player
extends CharacterBody3D
## Postać FPP: ruch, sprint, skok, kucanie, kamera, przewracanie. Chwytanie jest w Grabber.
##
## SIEĆ: każdy gracz symuluje SWOJĄ postać (jest jej autorytetem), więc sterowanie
## nie ma opóźnienia. Stan (net_*) leci do pozostałych przez MultiplayerSynchronizer,
## a cudze postacie wygładzamy interpolacją.
##
## PRZEWRACANIE ("ragdoll" w wersji FPP): przez `down_duration` sekund gracz nie może
## sterować, kamera opada i przechyla się, a cudza kapsuła leży na boku.
## Przewrócić może uderzenie ciężkiego przedmiotu, upadek z wysoka albo popchnięcie (B).

const STEP_SOUND: String = "res://assets/audio/footsteps/footstep.mp3"

@export_group("Ruch")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.0
@export var crouch_speed: float = 2.2
@export var ground_accel: float = 14.0
@export var air_accel: float = 3.0
@export var jump_velocity: float = 4.5

@export_group("Kamera")
## Bazowa czułość; gracz mnoży ją suwakiem w ustawieniach (Settings.sensitivity_mult).
@export var mouse_sensitivity: float = 0.0025

@export_group("Kucanie")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.1
@export var eye_offset: float = 0.2  ## odległość oczu od czubka głowy

@export_group("Fizyka")
## Siła, z jaką gracz popycha luźne przedmioty, na które wpada.
@export var push_force: float = 1.5

@export_group("Przewracanie")
@export var down_duration: float = 2.5
## Prędkość lądowania [m/s], od której upadek przewraca.
@export var fall_knockdown_speed: float = 9.0
## Zasięg popchnięcia (klawisz B) i czas leżenia popchniętego.
@export var shove_reach: float = 2.0
@export var shove_down_duration: float = 2.0
@export var shove_cooldown: float = 1.0
@export var shove_impulse: float = 5.0

@export_group("Dźwięk kroków")
## Odstęp między krokami [s]: sprint szybciej, kucanie wolniej.
@export var step_interval_walk: float = 0.45
@export var step_interval_sprint: float = 0.3
@export var step_interval_crouch: float = 0.62
## Szybkość odtwarzania dźwięku kroku (1.0 = oryginał; wyżej = szybciej i wyżej).
@export var step_pitch_walk: float = 1.0
@export var step_pitch_sprint: float = 1.2
@export var step_pitch_crouch: float = 0.82
@export var step_volume_db: float = -4.0
## Ciszej przy kucaniu.
@export var crouch_step_volume_db: float = -12.0
## Lądowanie po skoku/upadku jest głośniejsze o tyle dB.
@export var landing_volume_boost_db: float = 5.0

@export_group("Sieć")
@export var remote_smoothing: float = 20.0

## Replikowane do pozostałych graczy:
var net_position: Vector3
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_height: float = 1.8
var net_down: bool = false
var net_on_floor: bool = true

var is_local: bool = true
## "Użyj" (E) - tylko u lokalnego gracza.
var interactor: Interactor = null

var _pitch: float = 0.0
var _crouching: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _body_mesh: MeshInstance3D

var _down_timer: float = 0.0
var _down_blend: float = 0.0
var _shove_cd: float = 0.0
## Tylko host (kopia cudzej postaci): kiedy ostatnio zlecono przewrócenie.
var _last_knock_request: float = -100.0

# Kroki (liczone lokalnie u każdego - także dla cudzych postaci, z ich ruchu).
var _step_player: AudioStreamPlayer3D
var _step_timer: float = 0.0
var _last_step_pos: Vector3
var _ground_speed: float = 0.0  ## wygładzona prędkość pozioma (też dla cudzych postaci)
var _sfx_on_floor: bool = true
var _air_time: float = 0.0

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
	_setup_footsteps()

	if is_local:
		interactor = Interactor.new()
		interactor.name = "Interactor"
		interactor.player = self
		camera.add_child(interactor)
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


func is_down() -> bool:
	return _down_timer > 0.0 if is_local else net_down


func _unhandled_input(event: InputEvent) -> void:
	# Esc obsługuje menu pauzy (ui/pause_menu.gd), tutaj tylko kamera.
	if Settings.input_blocked():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _down_timer > 0.0:
			return
		var sens: float = mouse_sensitivity * Settings.sensitivity_mult
		rotate_y(-event.relative.x * sens)
		_pitch = clampf(_pitch - event.relative.y * sens, -1.5, 1.5)
		head.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_local:
		_remote_update(delta)
		return

	_read_input()
	_update_down(delta)
	_shove_cd = maxf(0.0, _shove_cd - delta)
	if Input.is_action_just_pressed("shove") and _down_timer <= 0.0 and _shove_cd <= 0.0 \
			and not Settings.input_blocked():
		_try_shove()

	_update_crouch(delta)

	var was_on_floor: bool = is_on_floor()
	if not was_on_floor:
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
	if _down_timer > 0.0:
		speed = 0.0  # leżymy: hamujemy do zera
		accel = ground_accel * 0.5
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta * maxf(speed, 4.0))
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta * maxf(speed, 4.0))

	var vy_before: float = velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor() and vy_before < -fall_knockdown_speed:
		knock_down(Vector3.ZERO, down_duration)
	_push_bodies()

	net_position = global_position
	net_yaw = rotation.y
	net_pitch = _pitch
	net_height = _capsule.height
	net_down = _down_timer > 0.0
	net_on_floor = is_on_floor()
	_update_footsteps(delta, net_on_floor)


func _read_input() -> void:
	if _down_timer > 0.0 or Settings.input_blocked():
		_move_input = Vector2.ZERO
		_jump_pressed = false
		_sprint_held = false
		_crouch_held = false
		return
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


## Pozycja głowy/kapsuły zależy od wzrostu i od tego, jak bardzo jesteśmy "przewróceni".
func _apply_height(height: float) -> void:
	_capsule.height = height
	collision.position.y = height * 0.5
	head.position.y = lerpf(height - eye_offset, 0.35, _down_blend)
	head.rotation.z = _down_blend * 1.2
	if _body_mesh != null:
		(_body_mesh.mesh as CapsuleMesh).height = height
		_body_mesh.position.y = lerpf(height * 0.5, 0.4, _down_blend)
		_body_mesh.rotation.z = _down_blend * PI * 0.5


func _push_bodies() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var item := col.get_collider() as Grabbable
		if item != null and item != grabber.held:
			item.request_push(-col.get_normal() * push_force)


# --- Przewracanie ---------------------------------------------------------------

func _update_down(delta: float) -> void:
	if _down_timer > 0.0:
		_down_timer -= delta
	_down_blend = move_toward(_down_blend, 1.0 if _down_timer > 0.0 else 0.0, 3.0 * delta)


## Wykonuje się na kliencie-właścicielu tej postaci.
func knock_down(impulse: Vector3, duration: float) -> void:
	if not is_local or _down_timer > 0.0:
		return
	_down_timer = duration
	net_down = true
	velocity += impulse.limit_length(8.0)
	grabber.release()


## Wołane na HOŚCIE (z uderzenia przedmiotu lub z popchnięcia): przekazuje
## przewrócenie do właściciela postaci.
func request_knockdown(impulse: Vector3, duration: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_knock_request < duration + 0.5:
		return  # już leży (lub dopiero wstał)
	_last_knock_request = now
	var owner_id: int = get_multiplayer_authority()
	if owner_id == multiplayer.get_unique_id():
		knock_down(impulse, duration)
	else:
		rpc_knockdown.rpc_id(owner_id, impulse, duration)


@rpc("any_peer", "call_remote", "reliable")
func rpc_knockdown(impulse: Vector3, duration: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return  # przewracać może tylko host
	knock_down(impulse, duration)


# --- Popchnięcie (B) ----------------------------------------------------------------

func _try_shove() -> void:
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best_id: int = -1
	var best_dist: float = shove_reach
	for id: int in Net.players:
		var other: Player = Net.players[id]
		if other == self:
			continue
		var to_other: Vector3 = other.global_position - global_position
		to_other.y = 0.0
		var dist: float = to_other.length()
		if dist < best_dist and dist > 0.01 and forward.dot(to_other / dist) > 0.5:
			best_dist = dist
			best_id = id
	if best_id == -1:
		return
	_shove_cd = shove_cooldown
	if multiplayer.is_server():
		_server_shove(multiplayer.get_unique_id(), best_id)
	else:
		rpc_shove.rpc_id(1, best_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_shove(target_id: int) -> void:
	if multiplayer.is_server():
		_server_shove(multiplayer.get_remote_sender_id(), target_id)


func _server_shove(sender_id: int, target_id: int) -> void:
	var sender: Player = Net.get_player(sender_id)
	var target: Player = Net.get_player(target_id)
	if sender == null or target == null or sender == target:
		return
	var offset: Vector3 = target.global_position - sender.global_position
	offset.y = 0.0
	if offset.length() > shove_reach + 1.0:  # zapas na opóźnienie sieci
		return
	target.request_knockdown(offset.normalized() * shove_impulse, shove_down_duration)


# --- Sieć -----------------------------------------------------------------------

func _setup_footsteps() -> void:
	if not ResourceLoader.exists(STEP_SOUND):
		return
	# Randomizer z jednym dźwiękiem: każdy krok brzmi minimalnie inaczej.
	var variants := AudioStreamRandomizer.new()
	variants.add_stream(-1, load(STEP_SOUND) as AudioStream)
	variants.random_pitch = 1.06           # ±6% wysokości przy każdym kroku
	variants.random_volume_offset_db = 1.5
	_step_player = AudioStreamPlayer3D.new()
	_step_player.stream = variants
	_step_player.position = Vector3(0, 0.05, 0)  # przy stopach
	_step_player.unit_size = 4.0
	_step_player.max_distance = 25.0
	_step_player.max_polyphony = 3  # kroki mogą na siebie lekko nachodzić
	add_child(_step_player)
	_last_step_pos = global_position


## Kroki w rytmie zależnym od chodu (chód / sprint / kucanie) + głośniejsze lądowanie.
## Działa dla własnej postaci i dla cudzych - chód rozpoznajemy z prędkości ruchu,
## więc nie trzeba przesyłać przez sieć, czy ktoś sprintuje.
func _update_footsteps(delta: float, on_floor: bool) -> void:
	if _step_player == null or delta <= 0.0:
		return
	var moved: Vector3 = global_position - _last_step_pos
	moved.y = 0.0
	_last_step_pos = global_position
	var speed: float = moved.length() / delta
	if speed > 30.0:
		speed = 0.0  # teleport/spawn, nie ruch
	_ground_speed = lerpf(_ground_speed, speed, 0.2)

	var lying: bool = is_down()
	if not on_floor:
		_air_time += delta
	elif not _sfx_on_floor and _air_time > 0.25 and not lying:
		_play_step(_gait(), landing_volume_boost_db)  # lądowanie
		_step_timer = 0.0
	if on_floor:
		_air_time = 0.0
	_sfx_on_floor = on_floor

	if not on_floor or lying or _ground_speed < 0.6:
		_step_timer = 999.0  # po ruszeniu z miejsca pierwszy krok od razu
		return
	var gait: int = _gait()
	var interval: float = [step_interval_walk, step_interval_sprint, step_interval_crouch][gait]
	# Powoli (np. z lodówką w rękach) - kroki rzadsze.
	if gait == 0:
		interval *= clampf(walk_speed * 0.7 / _ground_speed, 1.0, 1.8)
	_step_timer += delta
	if _step_timer >= interval:
		_step_timer = 0.0
		_play_step(gait, 0.0)


## 0 = chód, 1 = sprint, 2 = kucanie.
func _gait() -> int:
	if _capsule.height < stand_height - 0.2:
		return 2
	if _ground_speed > (walk_speed + sprint_speed) * 0.5:
		return 1
	return 0


func _play_step(gait: int, extra_db: float) -> void:
	_step_player.pitch_scale = [step_pitch_walk, step_pitch_sprint, step_pitch_crouch][gait]
	_step_player.volume_db = (crouch_step_volume_db if gait == 2 else step_volume_db) + extra_db
	_step_player.play()


func _remote_update(delta: float) -> void:
	var t: float = 1.0 - exp(-remote_smoothing * delta)
	global_position = global_position.lerp(net_position, t)
	rotation.y = lerp_angle(rotation.y, net_yaw, t)
	head.rotation.x = lerpf(head.rotation.x, net_pitch, t)
	_down_blend = move_toward(_down_blend, 1.0 if net_down else 0.0, 3.0 * delta)
	_apply_height(lerpf(_capsule.height, net_height, t))
	_update_footsteps(delta, net_on_floor)


func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop: String in [":net_position", ":net_yaw", ":net_pitch", ":net_height", ":net_down", ":net_on_floor"]:
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
