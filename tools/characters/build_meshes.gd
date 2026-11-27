extends SceneTree
## Zamienia JSON-y z sculpt.py w zasoby ArrayMesh (assets/characters/<nazwa>.res).
## Użycie: godot --headless --path . -s tools/characters/build_meshes.gd -- <katalog_z_json>

func _initialize() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	for name in ["bartek", "ola", "dawid"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + name + ".json"))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vec3(data["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = _vec3(data["normals"])
		var c: Array = data["colors"]
		var colors := PackedColorArray()
		for i in range(0, c.size(), 3):
			colors.append(Color(c[i], c[i + 1], c[i + 2]))
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array(data["bones"])
		arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(data["weights"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(data["indices"])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var err := ResourceSaver.save(mesh, "res://assets/characters/%s.res" % name)
		print(name, ": ", error_string(err), " ", colors.size(), " wierzchołków")
	quit()


func _vec3(a: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, a.size(), 3):
		out.append(Vector3(a[i], a[i + 1], a[i + 2]))
	return out
