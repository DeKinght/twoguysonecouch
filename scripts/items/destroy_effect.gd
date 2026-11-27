class_name DestroyEffect
extends Node3D
## Jednorazowy efekt zniszczenia przedmiotu: kawałki w kolorze przedmiotu,
## obłoczek kurzu i dźwięk. Sam się usuwa po zakończeniu.
## Działa lokalnie u każdego gracza (host rozsyła polecenie przez RPC w Grabbable).

const SOUND_PATH: String = "res://assets/audio/item_destroy.wav"
const LIFETIME: float = 2.0


static func spawn(parent: Node, at: Vector3, debris_color: Color, item_size: Vector3) -> void:
	if parent == null:
		return
	var effect := DestroyEffect.new()
	parent.add_child(effect)
	effect.global_position = at
	effect._play(debris_color, item_size)


func _play(debris_color: Color, item_size: Vector3) -> void:
	var extents: Vector3 = (item_size * 0.5).max(Vector3.ONE * 0.1)
	var volume: float = clampf(item_size.x * item_size.y * item_size.z, 0.05, 3.0)
	_add_debris(debris_color, extents, volume)
	_add_dust(extents, volume)
	_add_sound(volume)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


## Kawałki: małe klocki rozrzucone na boki, spadają i maleją.
func _add_debris(debris_color: Color, extents: Vector3, volume: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(clampf(18.0 + volume * 20.0, 18.0, 60.0))
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _fade_curve(1.0, 0.0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = debris_color
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	p.emitting = true


## Kurz: jasne, półprzezroczyste kule, które rosną i znikają.
func _add_dust(extents: Vector3, volume: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = int(clampf(10.0 + volume * 8.0, 10.0, 28.0))
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	p.scale_amount_curve = _fade_curve(0.4, 1.0)

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.97, 0.9, 0.75))
	ramp.set_color(1, Color(1.0, 0.97, 0.9, 0.0))
	p.color_ramp = ramp

	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	p.emitting = true


func _add_sound(volume: float) -> void:
	if not ResourceLoader.exists(SOUND_PATH):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = load(SOUND_PATH) as AudioStream
	player.unit_size = 8.0
	player.max_distance = 40.0
	# Większe meble brzmią niżej, drobiazgi wyżej; lekka losowość, żeby się nie nudziło.
	player.pitch_scale = clampf(1.15 - volume * 0.15, 0.75, 1.2) * randf_range(0.93, 1.07)
	add_child(player)
	player.play()


func _fade_curve(start: float, end: float) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(1.0, end))
	return curve
