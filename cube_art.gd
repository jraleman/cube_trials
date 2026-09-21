extends RefCounted

## Copper Creek's paint, scale and daylight are shared by play and its 3D portraits.

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
static func light_stage(parent: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.name = "CopperDaylight"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b8c9c9")
	settings.ambient_light_energy = 0.44
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("648ea5")
	sky_material.sky_horizon_color = Color("eed7b4")
	sky_material.ground_bottom_color = Color("665841")
	sky_material.ground_horizon_color = Color("eed7b4")
	sky_material.sun_angle_max = 7.0
	sky.sky_material = sky_material
	settings.sky = sky
	environment.environment = settings
	parent.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_color = Color("ffe4c2")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.25
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_color = Color("b4d4e4")
	fill.light_energy = 0.14
	parent.add_child(fill)
