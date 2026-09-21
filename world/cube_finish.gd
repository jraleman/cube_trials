extends RefCounted

## What a bought paint or wheel finish actually looks like on the Cube.
##
## [ChickenPitOptions]-style catalogues say what is for sale and what it costs;
## this says what it *is*. The split matters here more than usual, because the
## car is an imported GLB rather than generated geometry: a finish cannot invent
## a new mesh, only restate two of the surfaces the exporter already batched.
##
## Nothing here touches [Store]. The shop, the round, the score portrait and the
## art capture all pass an item id in, so a headless test can dress the car
## without a wallet existing, and the framework never learns what "Signal
## Orange" means.
##
## The factory look is deliberately *absent* from both tables. A paint the
## player has not bought applies no override at all, so the exported bronze and
## its silver alloys are the materials Blender wrote rather than a transcription
## of them that could quietly drift.

## Surfaces a paint restates, by the material name the exporter batched them
## under. Matching by name rather than index survives the exporter reordering
## its batches; `cube_trials_3d_test.gd` fails loudly if a name disappears.
const BODY_COAT := "Cube Bronze metallic"
const BODY_EDGE := "Cube Bronze edge"
## The wheel's painted face and its polished lip. The hub carrier and brake disc
## keep their own materials, because a wheel finish is not a bare-metal respray.
const RIM_FACE := "Cube Silver alloy"
const RIM_LIP := "Cube Polished chrome"

## What the exporter actually painted. The two free looks apply no override, so
## the shelf shows these on their cards: the swatch and the car are then one
## fact in one place, and `cube_trials_3d_test.gd` checks both against the GLB.
const FACTORY_COAT := Color("84674a")
const FACTORY_ALLOY := Color("c7cdd1")

## How much darker the edge batch sits under the main coat, measured off the
## exported bronze pair (`#84674a` against `#795a3c`) so a new colour shades
## itself the way the authored one does.
const EDGE_DARKEN := 0.10
const EDGE_ROUGHEN := 0.07

## Body colours, keyed by the store item id that sells them. `metallic` and
## `roughness` are the exported bronze's 0.68 / 0.25 unless a finish is making a
## point of being flatter or wetter than the factory coat.
const PAINTS := {
	"cube_paint_creek": {
		"color": Color("4a5f3c"), "metallic": 0.62, "roughness": 0.30,
	},
	"cube_paint_quarry": {
		"color": Color("6d757a"), "metallic": 0.66, "roughness": 0.28,
	},
	"cube_paint_ceramic": {
		"color": Color("ded6c4"), "metallic": 0.40, "roughness": 0.34,
	},
	"cube_paint_signal": {
		"color": Color("c7601c"), "metallic": 0.55, "roughness": 0.26,
	},
	"cube_paint_midnight": {
		"color": Color("27384d"), "metallic": 0.70, "roughness": 0.22,
	},
	"cube_paint_copper": {
		"color": Color("b0642c"), "metallic": 0.92, "roughness": 0.15,
	},
	"cube_paint_gold": {
		"color": Color("d9a441"), "metallic": 0.95, "roughness": 0.12,
	},
}

## Wheel finishes. `face` is the spoke; `lip` is the polished rim edge, which a
## painted wheel keeps brighter than its face rather than losing entirely.
const RIMS := {
	"cube_rim_graphite": {
		"face": Color("4d5357"), "lip": Color("6f767a"),
		"metallic": 0.80, "roughness": 0.34,
	},
	"cube_rim_bronze": {
		"face": Color("9a6a36"), "lip": Color("c08f4d"),
		"metallic": 0.88, "roughness": 0.26,
	},
	"cube_rim_white": {
		"face": Color("e4e6e0"), "lip": Color("f2f3ef"),
		"metallic": 0.35, "roughness": 0.38,
	},
	"cube_rim_black": {
		"face": Color("1e2226"), "lip": Color("3d4449"),
		"metallic": 0.62, "roughness": 0.16,
	},
}

## Restated materials, keyed by `item id` + `surface name`. The car wears four
## wheels and the shop shelves a card per colour, so without this every wheel
## and every card would carry its own copy of the same finish.
static var _coats: Dictionary = {}


## True when [param id] names something this module can actually paint, which is
## every item the shop sells except the two free factory looks.
static func repaints(id: String) -> bool:
	return PAINTS.has(id) or RIMS.has(id)


## The colour a card, a caption or a swatch should show for [param id]. An id
## this module does not paint reports [param factory] — the exported colour of
## whatever the caller is asking about — so nobody has to special-case the look
## the car already has.
static func swatch(id: String, factory := FACTORY_COAT) -> Color:
	if PAINTS.has(id):
		return Color(PAINTS[id]["color"])
	if RIMS.has(id):
		return Color(RIMS[id]["face"])
	return factory


## Paints one body panel batch. A [param paint_id] this module does not sell
## clears any previous override, so switching back to the factory coat restores
## the exported material rather than approximating it.
static func dress_body(instance: MeshInstance3D, paint_id: String) -> void:
	var paint: Dictionary = PAINTS.get(paint_id, {})
	var coat := Color(paint["color"]) if not paint.is_empty() else Color.WHITE
	_restate(instance, paint_id, BODY_COAT, coat, paint)
	_restate(
		instance, paint_id, BODY_EDGE, coat.darkened(EDGE_DARKEN), paint, EDGE_ROUGHEN
	)


## Paints one wheel's face and lip. Applied to an `AlloyRims` instance only, so
## the same polished-chrome batch on the grille and door handles is untouched.
static func dress_rim(instance: MeshInstance3D, rim_id: String) -> void:
	var rim: Dictionary = RIMS.get(rim_id, {})
	var face := Color(rim["face"]) if not rim.is_empty() else Color.WHITE
	var lip := Color(rim["lip"]) if not rim.is_empty() else Color.WHITE
	_restate(instance, rim_id, RIM_FACE, face, rim)
	_restate(instance, rim_id, RIM_LIP, lip, rim)


## Overrides the one surface batched under [param surface_name], or clears that
## override when [param finish] is empty.
static func _restate(
	instance: MeshInstance3D,
	id: String,
	surface_name: String,
	color: Color,
	finish: Dictionary,
	extra_roughness := 0.0,
) -> void:
	var surface := _surface_index(instance.mesh, surface_name)
	if surface < 0:
		return
	if finish.is_empty():
		instance.set_surface_override_material(surface, null)
		return
	instance.set_surface_override_material(
		surface, _coat(instance.mesh, surface, id, color, finish, extra_roughness)
	)


## Builds the restated material from the exported one rather than from nothing,
## so a finish only changes the three properties it has an opinion about and
## inherits culling, transparency and everything else Blender wrote.
static func _coat(
	mesh: Mesh,
	surface: int,
	id: String,
	color: Color,
	finish: Dictionary,
	extra_roughness: float,
) -> StandardMaterial3D:
	var key := "%s/%d" % [id, surface]
	var cached: StandardMaterial3D = _coats.get(key, null)
	if cached != null:
		return cached
	var exported := mesh.surface_get_material(surface) as StandardMaterial3D
	var coat := (
		exported.duplicate() as StandardMaterial3D if exported != null
		else StandardMaterial3D.new()
	)
	coat.resource_name = key
	coat.albedo_color = color
	coat.metallic = float(finish["metallic"])
	coat.roughness = clampf(float(finish["roughness"]) + extra_roughness, 0.0, 1.0)
	_coats[key] = coat
	return coat


static func _surface_index(mesh: Mesh, surface_name: String) -> int:
	if mesh == null:
		return -1
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material != null and material.resource_name == surface_name:
			return surface
	return -1
