class_name StaticProp
extends StaticBody3D
## Nieruchomy element mapy z modelu .glb (ściany, zabudowa kuchni, dywany...).
## Kolizję buduje z siatki modelu (trimesh), więc otwory drzwi i okien działają same.

@export var model: PackedScene
## Modele Kenney Furniture Kit są w skali ~1:2, więc 2.0.
@export var model_scale: float = 2.0
## Wyłącz dla dekoracji, przez które można przechodzić (np. dywan).
@export var collide: bool = true


func _ready() -> void:
	collision_layer = 1  # world
	collision_mask = 0
	if model == null:
		return
	var visual: Node3D = model.instantiate()
	visual.name = "Model"
	visual.scale = Vector3.ONE * model_scale
	add_child(visual)
	if not collide:
		return
	for mi: MeshInstance3D in _meshes(visual):
		var shape := CollisionShape3D.new()
		var trimesh: ConcavePolygonShape3D = mi.mesh.create_trimesh_shape()
		# Ściany mają 10 cm: bez tego coś, co wjedzie w środek ściany, przez nią przelatuje.
		trimesh.backface_collision = true
		shape.shape = trimesh
		shape.transform = _transform_to_self(mi)
		add_child(shape)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _transform_to_self(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != self and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
