class_name RenderTuning
extends RefCounted
## Wspólne ustawienia świateł i cieni (wydajność bez utraty cieni).
##
## - Słońce: cienie zostają, ale 2 warstwy do 80 m (zamiast 4 do 100 m) i bez drobiazgów
##   z wnętrz budynków - dach i tak je zasłania, a każda warstwa rysowała je od nowa.
## - Lampy: wygaszanie (i ich cieni) z odległości - lampy w Siedzibie nic nie kosztują w mieście.

## Warstwa renderowania drobiazgów w budynkach: widzi je kamera i lampy, słońce ich nie cieniuje.
const INTERIOR_LAYER: int = 1 << 1


static func tune_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_split_1 = 0.15
	sun.directional_shadow_blend_splits = true
	sun.shadow_caster_mask = 0xFFFFF & ~INTERIOR_LAYER


static func tune_lamp(light: OmniLight3D) -> void:
	# Cień zostaje "cube" (6 stron): tańszy dual paraboloid gubił cienie mebli na podłodze.
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_shadow = 25.0
	light.distance_fade_length = 10.0


## Drobne obiekty (do `max_size` m) w prostokącie `inside` (lokalnie względem `root`)
## dostają warstwę wnętrz. Meble do noszenia zostają - wyniesione na dwór muszą mieć cień.
static func mark_interior(root: Node3D, inside: AABB, max_size: float = 2.6) -> int:
	var count: int = 0
	var to_root: Transform3D = root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Grabbable or node is Player:
			continue
		stack.append_array(node.get_children())
		var geo := node as GeometryInstance3D
		if geo == null or not geo.is_inside_tree():
			continue
		var box: AABB = to_root * geo.global_transform * geo.get_aabb()
		if box.size.x > max_size or box.size.z > max_size or not inside.encloses(box):
			continue
		geo.layers = INTERIOR_LAYER
		count += 1
	return count
