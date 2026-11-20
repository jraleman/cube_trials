extends RefCounted

## Copper Creek's actual car and pine, staged for a trail-poster silhouette.
const Helpers = preload("res://tools/cover_art_helpers.gd")
const Gallery = preload("res://games/cube_trials/gallery_stage.gd")


## A climbing diagonal and bold rally typography, with the original copper palette.
static func design() -> Dictionary:
	return {
		"paper": Color("ead9b8"), "ink": Color("243e3c"), "accent": Color("d98651"),
		"motif": "racing", "camera": Vector3(55, 13, -9),
		"photo": Rect2(-42, 305, 1110, 580),
		"lettering": [
			{"text": "CUBE", "at": Vector2(52, 220), "size": 210, "angle": -3},
			{"text": "TRIALS", "at": Vector2(59, 367), "size": 155, "angle": -3},
			{"text": "SMALL CAR. BIG CLIMB.", "at": Vector2(55, 994),
				"size": 34, "font": "mono"},
		],
	}


## Gallery factories reuse the playable GLB, tires and suspension assemblies.
static func build(parent: Node) -> Node:
	var root := Helpers.group(parent)
	var gallery := Gallery.new()
	Helpers.place(root, gallery.build_exhibit("cube_car"), Vector3(0, 0.2, 0),
		Vector3(0, 0, -13))
	gallery.free()
	return root
