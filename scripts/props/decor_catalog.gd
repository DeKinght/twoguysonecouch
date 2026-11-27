class_name DecorCatalog
extends RefCounted
## Lista gotowych dekoracji (sceny z Decor w scenes/props/decor/).

const DIR: String = "res://scenes/props/decor/"

const ALL: Array[String] = [
	"tool_hammer", "tool_wrench", "tool_screwdriver", "tool_drill", "tool_tape_measure", "tool_saw",
	"paint_can_red", "paint_can_blue", "paint_can_white",
	"plant_succulent", "plant_cactus", "plant_fern", "plant_monstera", "flowers_vase",
	"wall_shelf",
	"duck_rubber", "globe", "trophy", "mug", "alarm_clock", "lava_lamp", "garden_gnome", "bowling_pin",
	"snow_globe", "piggy_bank", "book_stack", "pizza_boxes", "traffic_cone", "hard_hat", "dumbbell",
	"rubik_cube", "photo_frame", "disco_ball", "thermos",
]

## Drobiazgi, które mieszczą się na półkach regałów (losowane między kartony).
const SHELF_TRINKETS: Array[String] = [
	"duck_rubber", "globe", "trophy", "mug", "alarm_clock", "lava_lamp", "garden_gnome", "bowling_pin",
	"snow_globe", "piggy_bank", "book_stack", "rubik_cube", "photo_frame", "thermos",
	"plant_succulent", "plant_cactus", "paint_can_red", "paint_can_blue", "hard_hat", "tool_drill",
]


static func path(decor_name: String) -> String:
	return DIR + decor_name + ".tscn"


static func scene(decor_name: String) -> PackedScene:
	return load(path(decor_name)) as PackedScene
