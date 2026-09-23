extends MultiMeshInstance3D

## Bounded, course-space particles leave the wheels behind without touching driving physics.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const DUST_COUNT := 96
const DIRT_COUNT := 40
const EMISSION_STEP := 1.0 / 24.0
const DUST_LIFETIME := 0.8
const DIRT_LIFETIME := 0.6

var _scenery: Course.Scenery
var _clods: MultiMeshInstance3D
var _origins := PackedVector3Array()
var _velocities := PackedVector3Array()
var _ages := PackedFloat32Array()
var _sizes := PackedFloat32Array()
var _colors := PackedColorArray()
var _dust_cursor := 0
var _dirt_cursor := 0
var _serial := 0
var _emission_clock := EMISSION_STEP
var _air_time := 0.0
var _landing_speed := 0.0
var _run_id := 0
var _recoveries := 0
var _last_position := Vector2.ZERO


func _init(scenery := Course.Scenery.MOUNTAIN) -> void:
	_scenery = scenery


func _ready() -> void:
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE
	multimesh = _batch(puff, DUST_COUNT)
	var finish := Art.material()
	finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	finish.albedo_texture = Art.soft_particle_texture()
	finish.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	finish.billboard_keep_scale = true
	material_override = finish
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var count := DUST_COUNT
	if _scenery == Course.Scenery.MOUNTAIN:
		_clods = MultiMeshInstance3D.new()
		_clods.name = "DirtClods"
		var pebble := SphereMesh.new()
		pebble.radius = 0.5
		pebble.height = 1.0
		pebble.radial_segments = 6
		pebble.rings = 2
		_clods.multimesh = _batch(pebble, DIRT_COUNT)
		_clods.material_override = Art.material(1.0)
		_clods.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_clods.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_clods)
		count += DIRT_COUNT
	_origins.resize(count)
	_velocities.resize(count)
	_ages.resize(count)
	_sizes.resize(count)
	_colors.resize(count)
	reset()


func _batch(mesh: Mesh, count: int) -> MultiMesh:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = count
	batch.visible_instance_count = 0
	return batch


func reset() -> void:
	_ages.fill(-1.0)
	_dust_cursor = 0
	_dirt_cursor = 0
	_serial = 0
	_emission_clock = EMISSION_STEP
	_air_time = 0.0
	_landing_speed = 0.0
	multimesh.visible_instance_count = 0
	if _clods != null:
		_clods.multimesh.visible_instance_count = 0


func present(state: State, delta: float, enabled: bool) -> void:
	if state.get_instance_id() != _run_id or state.recoveries != _recoveries \
		or state.position.distance_to(_last_position) > 650.0:
		reset()
	_run_id = state.get_instance_id()
	_recoveries = state.recoveries
	_last_position = state.position
	if not enabled or state.crash_wait > 0.0 or state.is_over():
		reset()
		return
	if delta <= 0.0 or get_tree().paused:
		return
	for index in _ages.size():
		if _ages[index] >= 0.0:
			_ages[index] += delta
	if state.is_airborne():
		_air_time += delta
		_landing_speed = maxf(0.0, state.velocity.y)
		_emission_clock = EMISSION_STEP
	elif state.contacts > 0:
		if _air_time >= State.DAMAGE_AIR_TIME:
			_emit_from_tires(state, clampf(_landing_speed / State.JUMP_SPEED, 0.25, 1.0), true)
		_air_time = 0.0
		_landing_speed = 0.0
		var speed := absf(state.velocity.x)
		if speed > 70.0:
			var strength := clampf(speed / 650.0, 0.0, 1.0)
			_emission_clock += minf(delta, 0.1) * lerpf(0.35, 1.0, strength)
			while _emission_clock >= EMISSION_STEP:
				_emission_clock -= EMISSION_STEP
				_emit_from_tires(state, strength, false)
		else:
			_emission_clock = EMISSION_STEP
	_draw_particles(state.course)


func _emit_from_tires(state: State, strength: float, landing: bool) -> void:
	var down := Vector2.DOWN.rotated(state.angle)
	for axle in 2:
		var anchor := state.position + state.vehicle.axles[axle].rotated(state.angle)
		var hit := state.course.wheel_contact(anchor, down, State.REST_LENGTH,
			state.vehicle.wheel_radius)
		if hit.is_empty():
			continue
		var normal: Vector2 = hit["normal"]
		var up := Vector3(normal.x, -normal.y, 0)
		var tangent := Vector3(-normal.y, -normal.x, 0)
		var contact: Vector2 = hit["point"] - normal * state.vehicle.wheel_radius
		for side: float in [-1.0, 1.0]:
			var at := Art.world_point(contact, side * state.vehicle.half_track * State.Tuning.UNITS_PER_METER \
				* Art.WORLD_SCALE) + up * 0.08
			for puff in (3 if landing else 1):
				_spawn(at, up, tangent, side, signf(state.velocity.x), strength, false)
			if _clods != null and (landing or _dust_cursor % 3 == 0):
				_spawn(at, up, tangent, side, signf(state.velocity.x), strength, true)


func _spawn(
	at: Vector3, up: Vector3, tangent: Vector3, side: float,
	direction: float, strength: float, clod: bool
) -> void:
	var index := DUST_COUNT + _dirt_cursor if clod else _dust_cursor
	if clod:
		_dirt_cursor = (_dirt_cursor + 1) % DIRT_COUNT
	else:
		_dust_cursor = (_dust_cursor + 1) % DUST_COUNT
	var variation := fposmod(_serial * 0.618034, 1.0)
	_serial += 1
	var spread := direction if direction != 0.0 else (variation * 2.0 - 1.0)
	_origins[index] = at
	_velocities[index] = up * (1.0 + variation) * (1.6 if clod else 0.65) \
		- tangent * spread * (0.6 + strength * 1.8) * (1.5 if clod else 1.0) \
		+ Vector3(0, 0, side * (0.2 + variation * 0.7))
	_ages[index] = 0.0
	_sizes[index] = lerpf(0.08, 0.16, variation) if clod else lerpf(0.32, 0.5, variation)
	var color := Color("bd9c70")
	if clod:
		color = Color("6f4930").lerp(Color("ba8857"), variation)
	elif _scenery == Course.Scenery.BEACH:
		color = Color("e4c690")
	elif _scenery == Course.Scenery.SNOW:
		color = Color("d8e9f2")
	_colors[index] = color


func _draw_particles(course: Course) -> void:
	var dust_count := 0
	var dirt_count := 0
	for index in _ages.size():
		var age := _ages[index]
		var clod := index >= DUST_COUNT
		var lifetime := DIRT_LIFETIME if clod else DUST_LIFETIME
		if age < 0.0 or age >= lifetime:
			_ages[index] = -1.0
			continue
		var at := _origins[index] + _velocities[index] * age \
			+ Vector3.DOWN * (4.9 if clod else 0.15) * age * age
		var remaining := 1.0 - age / lifetime
		var size := _sizes[index] * (smoothstep(0.0, 0.2, remaining) if clod else 1.0 + age * 2.4)
		var color := _colors[index]
		var batch := _clods.multimesh if clod else multimesh
		if clod:
			var ground := course.ground_height(at.x / Art.WORLD_SCALE)
			if is_finite(ground) and at.y < Art.world_point(Vector2(0, ground)).y:
				_ages[index] = -1.0
				continue
		else:
			color.a = pow(remaining, 1.5) * 0.55
		var instance := dirt_count if clod else dust_count
		batch.set_instance_transform(instance, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
		batch.set_instance_color(instance, color)
		if clod:
			dirt_count += 1
		else:
			dust_count += 1
	multimesh.visible_instance_count = dust_count
	if _clods != null:
		_clods.multimesh.visible_instance_count = dirt_count
