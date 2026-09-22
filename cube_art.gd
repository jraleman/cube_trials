extends RefCounted

## Copper Creek's paint, scale and daylight are shared by play and its 3D portraits.

const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const INK := Color("253336")
const CREAM := Color("ffedc7")
const COPPER := Color("dda368")
const BROWN := Color("805234")
const TEAL := Color("558b87")
const WORLD_SCALE := 0.025
const HEIGHT_ORIGIN := 650.0


## Physics stays in its tested side-view plane; the renderer adds real depth.
static func world_point(point: Vector2, depth := 0.0) -> Vector3:
	return Vector3(point.x * WORLD_SCALE, (HEIGHT_ORIGIN - point.y) * WORLD_SCALE, depth)


## Vertex paint batches details without losing per-part roughness or metal response.
static func material(roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var finish := StandardMaterial3D.new()
	finish.vertex_color_use_as_albedo = true
	finish.vertex_color_is_srgb = true
	finish.roughness = roughness
	finish.metallic = metallic
	return finish


## Ordinary sky lighting and shadow maps work on desktop, web and mobile Compatibility.
static func light_stage(parent: Node3D) -> Daylight:
	return Daylight.new(parent)
