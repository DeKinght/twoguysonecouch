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


## Nazwa w HUD i masa [kg] przy skali 100% (większe egzemplarze są cięższe).
const INFO: Dictionary = {
	"tool_hammer": ["Młotek", 1.0], "tool_wrench": ["Klucz", 0.6], "tool_screwdriver": ["Śrubokręt", 0.2],
	"tool_drill": ["Wkrętarka", 1.8], "tool_tape_measure": ["Miarka", 0.3], "tool_saw": ["Piła", 0.8],
	"paint_can_red": ["Puszka farby", 3.0], "paint_can_blue": ["Puszka farby", 3.0],
	"paint_can_white": ["Puszka farby", 3.0],
	"plant_succulent": ["Sukulent", 0.6], "plant_cactus": ["Kaktus", 0.7], "plant_fern": ["Paproć", 4.0],
	"plant_monstera": ["Monstera", 9.0], "flowers_vase": ["Wazon z kwiatami", 1.2],
	"wall_shelf": ["Półka", 4.0],
	"duck_rubber": ["Gumowa kaczka", 0.1], "globe": ["Globus", 1.2], "trophy": ["Puchar", 1.0],
	"mug": ["Kubek", 0.3], "alarm_clock": ["Budzik", 0.4], "lava_lamp": ["Lampa lava", 1.2],
	"garden_gnome": ["Krasnal", 2.5], "bowling_pin": ["Kręgiel", 1.5], "snow_globe": ["Śnieżna kula", 0.6],
	"piggy_bank": ["Świnka-skarbonka", 0.8], "book_stack": ["Książki", 3.0], "pizza_boxes": ["Kartony po pizzy", 0.6],
	"traffic_cone": ["Pachołek", 2.0], "hard_hat": ["Kask", 0.4], "dumbbell": ["Hantel", 8.0],
	"rubik_cube": ["Kostka Rubika", 0.1], "photo_frame": ["Ramka ze zdjęciem", 0.4],
	"disco_ball": ["Kula dyskotekowa", 3.0], "thermos": ["Termos", 0.8],
}


static func display_name(decor_name: String) -> String:
	return str(INFO.get(decor_name, [decor_name, 1.0])[0])


static func mass(decor_name: String) -> float:
	return float(INFO.get(decor_name, [decor_name, 1.0])[1])


static func path(decor_name: String) -> String:
	return DIR + decor_name + ".tscn"


static func scene(decor_name: String) -> PackedScene:
	return load(path(decor_name)) as PackedScene
