class_name Door
extends Node3D
## Drzwi / brama otwierane klawiszem "Użyj" (domyślnie E).
##
## Ten węzeł to ZAWIAS: skrzydło (AnimatableBody3D - popycha graczy i przedmioty)
## jest jego dzieckiem, a otwieranie obraca zawias o `open_rotation`.
## Stan trzyma host i rozsyła wszystkim. Węzeł musi mieć tę samą nazwę/ścieżkę
## u każdego gracza (tworzymy go deterministycznie w skrypcie poziomu).

@export var open_rotation: Vector3 = Vector3(0.0, deg_to_rad(-100.0), 0.0)
@export var duration: float = 0.45
@export var label_closed: String = "Otwórz drzwi"
@export var label_open: String = "Zamknij drzwi"

var is_open: bool = false
var panel: AnimatableBody3D

var _closed_rotation: Vector3
var _tween: Tween


func _ready() -> void:
	_closed_rotation = rotation


## Buduje skrzydło: prostopadłościan `size` przesunięty o `offset` od zawiasu.
## model_path: opcjonalny model (.glb) dopasowany do rozmiaru skrzydła.
func build_panel(size: Vector3, offset: Vector3, material: Material, model_path: String = "") -> AnimatableBody3D:
	panel = AnimatableBody3D.new()
	panel.name = "Panel"
	panel.position = offset
	panel.collision_layer = 1  # świat: blokuje graczy i przedmioty, widać go w raycastach
	panel.collision_mask = 0
	add_child(panel)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	panel.add_child(shape)

	if not _add_model(model_path, size):
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh.mesh = box_mesh
		mesh.material_override = material
		panel.add_child(mesh)
	return panel


func interact_text() -> String:
	return label_open if is_open else label_closed


func interact() -> void:
	if multiplayer.is_server():
		_server_toggle()
	else:
		_rpc_request_toggle.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_toggle() -> void:
	if multiplayer.is_server():
		_server_toggle()


func _server_toggle() -> void:
	var open: bool = not is_open
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_rpc_set_open(open)
	else:
		_rpc_set_open.rpc(open)


@rpc("authority", "call_local", "reliable")
func _rpc_set_open(open: bool) -> void:
	is_open = open
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation", _closed_rotation + (open_rotation if open else Vector3.ZERO), duration)


## Wstawia model i rozciąga go do rozmiaru skrzydła. Zwraca false, jeśli modelu nie ma.
func _add_model(model_path: String, size: Vector3) -> bool:
	if model_path == "" or not ResourceLoader.exists(model_path):
		return false
	var visual: Node3D = (load(model_path) as PackedScene).instantiate()
	panel.add_child(visual)
	var bounds: AABB = _mesh_aabb(visual)
	if bounds.size.x < 0.001 or bounds.size.y < 0.001 or bounds.size.z < 0.001:
		visual.queue_free()
		return false
	# Najdłuższy poziomy wymiar modelu = szerokość skrzydła (oś Z zawiasu).
	var model_width_is_x: bool = bounds.size.x >= bounds.size.z
	if model_width_is_x:
		visual.rotation.y = PI / 2.0
		bounds = _mesh_aabb(visual)
	visual.scale = Vector3(size.x / bounds.size.x, size.y / bounds.size.y, size.z / bounds.size.z)
	bounds = _mesh_aabb(visual)
	visual.position -= bounds.get_center()
	return true


func _mesh_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first: bool = true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var t := Transform3D.IDENTITY
			var n: Node = node
			while n != panel and n is Node3D:
				t = (n as Node3D).transform * t
				n = n.get_parent()
			var box: AABB = t * (node as MeshInstance3D).get_aabb()
			result = box if first else result.merge(box)
			first = false
		stack.append_array(node.get_children())
	return result
