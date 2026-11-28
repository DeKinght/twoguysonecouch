class_name TargetHouse
extends Node3D
## Dom klienta ze zlecenia: prawdziwy dom z Kenney City Kit Suburban (building-type-h)
## przerobiony tak, żeby dało się do niego wejść.
##
## - z siatki domu wycinamy skrzydło drzwi wejściowych (otwór), szyby okien dostają
##   przezroczysty materiał, ściany rysują się z obu stron (od środka też są ściany);
## - w środku: podłoga, sufit, ścianka działowa (salon z aneksem kuchennym + sypialnia),
##   drzwi wejściowe i do sypialni otwierane na E (Door), światło, meble do zabrania;
## - kolizja: ściany zewnętrzne z otworem na drzwi, ścianka działowa, zabudowa kuchni.
##
## Układ lokalny jak w modelu: front (drzwi) w stronę -Z, 1 j. modelu = K metrów.
## Wszystko jest deterministyczne (te same nazwy węzłów u każdego gracza).

const MODEL: String = "res://assets/models/suburban/building-type-h.glb"
const FURNITURE: String = "res://assets/models/furniture/%s.glb"
const DOOR_MODEL: String = "res://assets/models/building/door-rotate-square-a.glb"
const K: float = 8.5               ## skala domu (drzwi ~2,3 m)

# Wymiary domu w metrach (z siatki modelu x K).
const X_WALL: float = 0.6 * K      ## ściany boczne x = ±5,1
const Z_FRONT: float = -0.4 * K    ## ściana frontowa z = -3,4
const Z_BACK: float = 0.41 * K     ## ściana tylna z = +3,49
const DOOR_HALF: float = 0.07 * K  ## drzwi: x = ±0,6
const DOOR_TOP: float = 0.27 * K   ## 2,3 m
const CEILING: float = 0.277 * K   ## 2,35 m - tuż pod okapem (wyżej widać od środka spód dachu)
const FLOOR_TOP: float = 0.03
const PARTITION_X: float = 1.6     ## ścianka salon / sypialnia
const T: float = 0.12              ## grubość ścian w środku

var items: Array[Grabbable] = []

var _mats: Dictionary = {}


func build() -> void:
	_build_shell()
	_build_interior()
	_build_collision()
	_build_doors()
	_build_furniture()
	for light in find_children("*", "OmniLight3D", true, false):
		RenderTuning.tune_lamp(light)
	RenderTuning.mark_interior(self, AABB(Vector3(-X_WALL + 0.1, -0.2, Z_FRONT + 0.1), Vector3(X_WALL * 2.0 - 0.2, CEILING + 0.1, Z_BACK - Z_FRONT - 0.2)))


# --- Bryła domu --------------------------------------------------------------------------

## Dzieli siatkę modelu na ściany (dwustronne) i szyby (przezroczyste), bez skrzydła drzwi.
func _build_shell() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	var src_mi: MeshInstance3D = _first_mesh(model)
	var src: ArrayMesh = src_mi.mesh as ArrayMesh
	var mesh := ArrayMesh.new()
	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.7, 0.85, 0.95, 0.22)
	glass_mat.roughness = 0.05
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for s in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var mat := src.surface_get_material(s) as BaseMaterial3D
		var tex_img: Image = null
		if mat != null and mat.albedo_texture != null:
			tex_img = mat.albedo_texture.get_image()
			if tex_img != null and tex_img.is_compressed():
				tex_img.decompress()
		var solid := PackedInt32Array()
		var glass := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var c: Vector3 = (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			# Skrzydło drzwi wejściowych (ciemny prostokąt na froncie) - wycinamy.
			if absf(c.x) < 0.075 and c.y < 0.275 and c.z < -0.36 and c.z > -0.44:
				continue
			var is_glass: bool = false
			if tex_img != null and uvs.size() > 0:
				var uv: Vector2 = (uvs[idx[t]] + uvs[idx[t + 1]] + uvs[idx[t + 2]]) / 3.0
				var px := Vector2i(clampi(int(uv.x * tex_img.get_width()), 0, tex_img.get_width() - 1),
						clampi(int(uv.y * tex_img.get_height()), 0, tex_img.get_height() - 1))
				var col: Color = tex_img.get_pixelv(px)
				is_glass = col.b > 0.78 and col.b - col.r > 0.22 and c.y < 0.3
			for k in 3:
				(glass if is_glass else solid).append(idx[t + k])
		if not solid.is_empty():
			var a: Array = arrays.duplicate()
			a[Mesh.ARRAY_INDEX] = solid
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			var m2: BaseMaterial3D = (mat.duplicate() as BaseMaterial3D) if mat != null else StandardMaterial3D.new()
			m2.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(mesh.get_surface_count() - 1, m2)
		if not glass.is_empty():
			var b: Array = arrays.duplicate()
			b[Mesh.ARRAY_INDEX] = glass
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
			mesh.surface_set_material(mesh.get_surface_count() - 1, glass_mat)
	model.free()

	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = mesh
	shell.scale = Vector3.ONE * K
	add_child(shell)


# --- Wnętrze -------------------------------------------------------------------------------

func _build_interior() -> void:
	var inner_x: float = X_WALL - 0.08
	var z0: float = Z_FRONT + 0.08
	var z1: float = Z_BACK - 0.08
	# Podłoga: deski w salonie, jaśniejsze w sypialni; płytki w kuchni (przy tylnej ścianie).
	_box(Vector3((-inner_x + PARTITION_X) * 0.5, FLOOR_TOP * 0.5, (z0 + z1) * 0.5),
			Vector3(PARTITION_X + inner_x, FLOOR_TOP, z1 - z0), Color(0.62, 0.44, 0.3))
	_box(Vector3((PARTITION_X + inner_x) * 0.5, FLOOR_TOP * 0.5, (z0 + z1) * 0.5),
			Vector3(inner_x - PARTITION_X, FLOOR_TOP, z1 - z0), Color(0.74, 0.58, 0.42))
	_box(Vector3(-3.0, FLOOR_TOP * 0.5 + 0.002, z1 - 1.0), Vector3(4.2, FLOOR_TOP, 2.0), Color(0.82, 0.82, 0.8))
	# Sufit (zasłania wnętrze dachu).
	_box(Vector3(0, CEILING, (z0 + z1) * 0.5), Vector3(inner_x * 2.0, 0.04, z1 - z0), Color(0.96, 0.95, 0.92))
	# Ścianka działowa z otworem na drzwi do sypialni (z = -0,5..0,5).
	var wall_col := Color(0.86, 0.8, 0.68)
	_box(Vector3(PARTITION_X, CEILING * 0.5, (z0 - 0.5) * 0.5), Vector3(T, CEILING, -0.5 - z0), wall_col)
	_box(Vector3(PARTITION_X, CEILING * 0.5, (z1 + 0.5) * 0.5), Vector3(T, CEILING, z1 - 0.5), wall_col)
	_box(Vector3(PARTITION_X, (CEILING + 2.15) * 0.5, 0.0), Vector3(T, CEILING - 2.15, 1.0), wall_col)
	# Listwy przypodłogowe wzdłuż ścianki (detal).
	_box(Vector3(PARTITION_X, 0.06, (z0 - 0.5) * 0.5), Vector3(T + 0.02, 0.1, -0.5 - z0), Color(0.45, 0.32, 0.22))
	_box(Vector3(PARTITION_X, 0.06, (z1 + 0.5) * 0.5), Vector3(T + 0.02, 0.1, z1 - 0.5), Color(0.45, 0.32, 0.22))
	# Wycieraczka przed drzwiami.
	_box(Vector3(0, FLOOR_TOP + 0.005, Z_FRONT + 0.55), Vector3(1.1, 0.01, 0.6), Color(0.35, 0.25, 0.2))
	# Lampy sufitowe.
	for p: Vector3 in [Vector3(-1.8, CEILING - 0.25, 0.0), Vector3(3.35, CEILING - 0.25, 0.4)]:
		var light := OmniLight3D.new()
		light.position = p
		light.omni_range = 6.5
		light.light_energy = 1.2
		light.light_color = Color(1.0, 0.88, 0.72)
		light.shadow_enabled = true
		add_child(light)
		_box(p + Vector3(0, 0.2, 0), Vector3(0.5, 0.06, 0.5), Color(0.98, 0.96, 0.88))


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var h: float = 3.0
	var t: float = 0.3
	# Front z otworem na drzwi.
	_shape(body, Vector3((-X_WALL - DOOR_HALF) * 0.5, h * 0.5, Z_FRONT), Vector3(X_WALL - DOOR_HALF, h, t))
	_shape(body, Vector3((X_WALL + DOOR_HALF) * 0.5, h * 0.5, Z_FRONT), Vector3(X_WALL - DOOR_HALF, h, t))
	_shape(body, Vector3(0, (DOOR_TOP + h) * 0.5, Z_FRONT), Vector3(DOOR_HALF * 2.0, h - DOOR_TOP, t))
	_shape(body, Vector3(0, h * 0.5, Z_BACK), Vector3(X_WALL * 2.0, h, t))
	_shape(body, Vector3(-X_WALL, h * 0.5, (Z_FRONT + Z_BACK) * 0.5), Vector3(t, h, Z_BACK - Z_FRONT))
	_shape(body, Vector3(X_WALL, h * 0.5, (Z_FRONT + Z_BACK) * 0.5), Vector3(t, h, Z_BACK - Z_FRONT))
	# Ścianka działowa.
	var z0: float = Z_FRONT
	var z1: float = Z_BACK
	_shape(body, Vector3(PARTITION_X, h * 0.5, (z0 - 0.5) * 0.5), Vector3(T, h, -0.5 - z0))
	_shape(body, Vector3(PARTITION_X, h * 0.5, (z1 + 0.5) * 0.5), Vector3(T, h, z1 - 0.5))


func _build_doors() -> void:
	var wood := _mat(Color(0.45, 0.3, 0.2))
	# Wejściowe: zawias przy lewej krawędzi otworu, skrzydło wzdłuż +X, otwiera się do środka.
	var front := Door.new()
	front.name = "FrontDoor"
	front.position = Vector3(-DOOR_HALF + 0.02, FLOOR_TOP, Z_FRONT)
	front.rotation.y = PI * 0.5
	add_child(front)
	var w: float = DOOR_HALF * 2.0 + 0.06  # zachodzi na ościeżnicę - bez szpary
	front.build_panel(Vector3(0.06, DOOR_TOP - 0.05, w), Vector3(0, (DOOR_TOP - 0.05) * 0.5, w * 0.5), wood, DOOR_MODEL)
	# Do sypialni: w ściance działowej, skrzydło wzdłuż +Z.
	var bedroom := Door.new()
	bedroom.name = "BedroomDoor"
	bedroom.position = Vector3(PARTITION_X, FLOOR_TOP, -0.48)
	add_child(bedroom)
	bedroom.build_panel(Vector3(0.05, 2.1, 0.94), Vector3(0, 1.05, 0.47), wood, DOOR_MODEL)


# --- Meble ------------------------------------------------------------------------------------

func _build_furniture() -> void:
	# Zabudowa kuchni (zostaje): szafki i zlewozmywak przy tylnej ścianie salonu.
	var x: float = -4.6
	for name: String in ["kitchenCabinet", "kitchenSink", "kitchenStove", "kitchenCabinetDrawer"]:
		_static_prop(name, Vector3(x, FLOOR_TOP, Z_BACK - 0.5), PI)
		x += 0.86
	_static_prop("rugRectangle", Vector3(-2.4, FLOOR_TOP + 0.002, -0.6), PI * 0.5, false)
	_static_prop("rugRounded", Vector3(3.4, FLOOR_TOP + 0.002, 0.6), 0.0, false)

	var box_root := Node3D.new()
	box_root.name = "Items"
	add_child(box_root)
	# [węzeł, model, nazwa, masa, wartość, wytrzymałość, x, z, obrót, na czym stoi (wysokość)]
	var table: Array = [
		["Kanapa", "loungeSofa", "Kanapa", 40.0, 500.0, 120.0, -1.2, -0.6, -PI * 0.5, 0.0],
		["Fotel", "loungeChair", "Fotel", 15.0, 300.0, 100.0, -2.6, -2.5, PI * 0.15, 0.0],
		["Stolik", "tableCoffee", "Stolik kawowy", 10.0, 150.0, 100.0, -2.7, -0.6, PI * 0.5, 0.0],
		["SzafkaRTV", "cabinetTelevision", "Szafka RTV", 20.0, 250.0, 100.0, -4.7, -0.6, PI * 0.5, 0.0],
		["Telewizor", "televisionModern", "Telewizor", 12.0, 600.0, 40.0, -4.7, -0.6, PI * 0.5, 0.62],
		["Lodowka", "kitchenFridge", "Lodówka", 60.0, 800.0, 80.0, -0.9, Z_BACK - 0.45, PI, 0.0],
		["Stol", "tableRound", "Stół", 15.0, 250.0, 100.0, -2.5, 1.5, 0.0, 0.0],
		["Krzeslo1", "chairCushion", "Krzesło", 5.0, 60.0, 100.0, -3.3, 1.5, PI * 0.5, 0.0],
		["Krzeslo2", "chairCushion", "Krzesło", 5.0, 60.0, 100.0, -1.7, 1.5, -PI * 0.5, 0.0],
		["Lampa", "lampSquareFloor", "Lampa", 4.0, 120.0, 50.0, -4.7, -2.9, 0.0, 0.0],
		["Lozko", "bedDouble", "Łóżko", 45.0, 600.0, 120.0, 3.6, Z_BACK - 1.25, PI, 0.0],
		["Komoda", "sideTableDrawers", "Komoda", 18.0, 250.0, 100.0, 4.7, -1.4, -PI * 0.5, 0.0],
		["Regal", "bookcaseClosed", "Regał", 25.0, 200.0, 100.0, 4.75, 0.35, -PI * 0.5, 0.0],
		["Biurko", "desk", "Biurko", 20.0, 300.0, 100.0, 3.2, Z_FRONT + 0.55, 0.0, 0.0],
		["Karton1", "cardboardBoxClosed", "Karton", 5.0, 80.0, 100.0, 0.7, -2.6, 0.2, 0.0],
		["Karton2", "cardboardBoxClosed", "Karton", 5.0, 80.0, 100.0, 1.15, -2.7, -0.1, 0.0],
		["Karton3", "cardboardBoxClosed", "Karton (szkło)", 5.0, 250.0, 25.0, 0.9, -2.65, 0.0, 0.58],
	]
	var scene: PackedScene = load("res://scenes/items/grabbable.tscn")
	for row: Array in table:
		var item: Grabbable = scene.instantiate()
		item.name = row[0]
		item.model = load(FURNITURE % row[1])
		item.item_name = row[2]
		item.mass = row[3]
		item.value = row[4]
		item.durability = row[5]
		if row[2] == "Karton (szkło)":
			item.label_text = "SZKŁO"
		var height: float = _furniture_size(row[1]).y
		item.position = Vector3(row[6], FLOOR_TOP + float(row[9]) + height * 0.5 + 0.02, row[7])
		item.rotation.y = row[8]
		box_root.add_child(item)
		items.append(item)


# --- Pomocnicze --------------------------------------------------------------------------

func _static_prop(model_name: String, pos: Vector3, rot: float, collide: bool = true) -> void:
	var prop := StaticProp.new()
	prop.name = "Fixed_" + model_name + str(get_child_count())
	prop.model = load(FURNITURE % model_name)
	prop.collide = collide
	add_child(prop)
	# Środek podstawy modelu w `pos` (modele Kenney mają początek w rogu).
	var size: Vector3 = _furniture_size(model_name)
	var lo: Vector3 = _furniture_aabb(model_name).position
	var center_local := Vector3(lo.x + size.x * 0.5, 0, lo.z + size.z * 0.5)
	prop.rotation.y = rot
	prop.position = pos - Basis(Vector3.UP, rot) * center_local


var _aabb_cache: Dictionary = {}


func _furniture_aabb(model_name: String) -> AABB:
	if _aabb_cache.has(model_name):
		return _aabb_cache[model_name]
	var model: Node3D = (load(FURNITURE % model_name) as PackedScene).instantiate()
	var box := AABB()
	var first: bool = true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var b: AABB = (n as MeshInstance3D).transform * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		stack.append_array(n.get_children())
	model.free()
	box = AABB(box.position * 2.0, box.size * 2.0)  # meble Kenney w skali 1:2
	_aabb_cache[model_name] = box
	return box


func _furniture_size(model_name: String) -> Vector3:
	return _furniture_aabb(model_name).size


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var m: MeshInstance3D = _first_mesh(c)
		if m != null:
			return m
	return null


func _mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		_mats[color] = m
	return _mats[color]


func _box(center: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color)
	mi.mesh = bm
	mi.position = center
	add_child(mi)


func _shape(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
