extends RefCounted

## Paint, scale and daylight are shared by the trails and their 3D portraits.

const Course = preload("res://games/cube_trials/course.gd")
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


static func soft_particle_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.4, 1.0])
	gradient.colors = PackedColorArray([
		Color.WHITE, Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


## Ordinary sky lighting and shadow maps work on desktop, web and mobile Compatibility.
static func light_stage(
	parent: Node3D, scenery: Course.Scenery = Course.Scenery.MOUNTAIN
) -> Daylight:
	return Daylight.new(parent, scenery)
