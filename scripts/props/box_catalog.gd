class_name BoxCatalog
extends RefCounted
## Lista gotowych wariantów kartonów (sceny z CardboardBox w scenes/props/boxes/).

const DIR: String = "res://scenes/props/boxes/"

## Wszystkie warianty.
const ALL: Array[String] = [
	"box_books", "box_kitchen", "box_bedroom", "box_painting", "box_wardrobe", "box_fragile",
	"box_open", "box_arrows", "box_small", "box_tv", "box_kuba", "box_bathroom", "box_bananas",
	"box_mystery", "box_basement", "box_gift",
]

## Kompaktowe - mieszczą się na półkach regałów (bez wysokich i płaskich).
const SHELF: Array[String] = [
	"box_books", "box_kitchen", "box_bedroom", "box_fragile", "box_open", "box_arrows", "box_small",
	"box_kuba", "box_bathroom", "box_bananas", "box_mystery", "box_basement", "box_gift",
]


static func path(box_name: String) -> String:
	return DIR + box_name + ".tscn"


static func scene(box_name: String) -> PackedScene:
	return load(path(box_name)) as PackedScene
