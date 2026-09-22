extends RefCounted

## The trail can advance this shared studio light rig without using wall-clock time.

const CYCLE_SECONDS := 240.0
const START_PHASE := 0.34
const DAY_TOP := Color("648ea5")
const DAY_HORIZON := Color("eed7b4")
const DAY_GROUND := Color("665841")
const DAY_AMBIENT := Color("b8c9c9")
const DAY_SUN := Color("ffe4c2")
const DAY_FILL := Color("b4d4e4")

var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var night_amount := 0.0
var phase := START_PHASE
var _last_seconds := -1.0


func _init(parent: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "CopperDaylight"
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 7.0
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	parent.add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.25
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	fill = DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(fill)
	set_elapsed(0.0)


## Zero is the same late afternoon used by the gallery, store and share portrait.
func set_elapsed(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0.0:
		push_error("Copper Creek daylight requires a finite, nonnegative time.")
		return
	if seconds == _last_seconds:
		return
	_last_seconds = seconds
	phase = fposmod(START_PHASE + seconds / CYCLE_SECONDS, 1.0)
	var height := sin(phase * TAU)
	var daylight := smoothstep(-0.22, 0.26, height)
	var warmth := 1.0 - smoothstep(0.10, 0.72, height)
	var darkness := 1.0 - daylight
	night_amount = 1.0 - smoothstep(-0.10, 0.32, height)
	sun.rotation_degrees.x = -42.0 * height / sin(START_PHASE * TAU)
	sun.light_color = DAY_SUN.lerp(Color("ffac70"), warmth)
	sun.light_energy = 0.85 * smoothstep(-0.08, 0.50, height)
	sun.visible = sun.light_energy > 0.001
	fill.light_color = DAY_FILL.lerp(Color("96b5e1"), darkness)
	fill.light_energy = lerpf(0.14, 0.34, darkness)
	environment.ambient_light_color = DAY_AMBIENT.lerp(Color("a3b9d8"), darkness)
	environment.ambient_light_energy = lerpf(0.44, 0.35, darkness)
	sky_material.sky_top_color = DAY_TOP.lerp(Color("a4829b"), warmth * 0.7) \
		.lerp(Color("172b48"), darkness)
	var horizon := DAY_HORIZON.lerp(Color("efa575"), warmth) \
		.lerp(Color("526b87"), darkness)
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = DAY_GROUND.lerp(Color("293448"), darkness)
