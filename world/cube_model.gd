extends Node3D

## The stock-proportion Blender car follows the tuned side-view suspension simulation.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Coilover = preload("res://games/cube_trials/world/coilover.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const MODEL = preload("res://games/cube_trials/assets/models/nissan_cube.glb")
const DAMAGE_MODEL = preload("res://games/cube_trials/assets/models/nissan_cube_damage.glb")
const S := Art.WORLD_SCALE
const MODEL_SCALE := Tuning.UNITS_PER_METER * S
const HALF_WIDTH := Tuning.SOURCE_HALF_WIDTH * MODEL_SCALE
const WHEEL_Z := Tuning.SOURCE_HALF_TRACK * MODEL_SCALE
const TIRE_RADIUS := State.WHEEL_RADIUS * S
const COILOVER_MOUNT_RISE := 0.35
const COILOVER_RAKE := 0.12
const COILOVER_DEPTH := WHEEL_Z - Coilover.BOUNDS_RADIUS - 0.12
const AIRBORNE_WHEEL_DROP := 0.16
const WHEEL_DROP_DURATION := 0.14
const WHEEL_RETRACT_SECONDS := 0.08
const SOURCE_TIRE_RADIUS := Tuning.SOURCE_TIRE_RADIUS
const BODY_SCALE := Vector3.ONE * MODEL_SCALE
const BODY_OFFSET := Vector3(0, -Tuning.BODY_ORIGIN_HEIGHT * MODEL_SCALE, 0)
const BRAKE_EMISSION := 1.8
const BRAKE_COLOR := Color("ff2820")
const HEADLIGHT_MATERIAL := "Cube Bulb"
const IMPACT_DURATION := 0.55
const MAX_DRIVE_PITCH := 0.055
const JUMP_DURATION := 0.32
const LANDING_DURATION := 0.42
const DRIVER_EYE := Vector3(0.12, 1.35, -0.377)
const WHEEL_NODES := [
	["RearLeftWheel", "RearRightWheel"], ["FrontLeftWheel", "FrontRightWheel"],
]
const WHEEL_PREFIXES := [["LR", "RR"], ["LF", "RF"]]
const DAMAGE_PARTS := [
	"BrownBodywork", "CabinAndDriver", "ChromeHandlesGrilleAndBadges",
	"HeadlightsAndIndicators", "LampGlazing", "RearBrakeLights",
	"RubberTrimAndUnderbody", "WraparoundGlazing",
]
const DAMAGE_SOCKETS := [
	"BodyPaintSample", "LeftBrakeSocket", "RightBrakeSocket",
	"LeftHeadlightSocket", "RightHeadlightSocket",
]

var chassis: Node3D
var axles: Array[Node3D] = []
var wheels: Array[Node3D] = []
var springs: Array[Coilover] = []
var brake_lights: Array[OmniLight3D] = []
var brake_level := 0.0
var headlights: Array[SpotLight3D] = []
var headlight_level := 0.0
var damage_stage := 0
var steady_cabin := false
## Store item ids, or "" for the factory coat and alloys. Assigning before
## [method build] dresses the car as it is assembled; [method set_finish]
## repaints one that is already standing.
var paint_id := ""
var rim_id := ""
var _parts: Array[MeshInstance3D] = []
var _body: MeshInstance3D
var _rims: Array[MeshInstance3D] = []
var _paint_sample: Node3D
var _brake_material: StandardMaterial3D
var _brake_color := Color.WHITE
var _headlight_mesh: MeshInstance3D
var _headlight_material: StandardMaterial3D
var _headlight_surface := -1
var _damage_meshes: Array[Dictionary] = []
var _damage_points: Array[Dictionary] = []
var _shown_damage_stage := -1
var _built := false
var _drive_pitch := 0.0
var _drive_bob := 0.0
var _last_speed := 0.0
var _motion_ready := false
var _impact_time := IMPACT_DURATION
var _jump_time := JUMP_DURATION
var _landing_time := LANDING_DURATION
var _landing_strength := 0.0
var _airborne_time := 0.0
var _last_vertical_speed := 0.0
var _impact_material: StandardMaterial3D
var _cockpit_positions: Dictionary[int, Vector3] = {}


func _ready() -> void:
	build()


## Gameplay, the reusable scene, portraits and art captures share this assembly.
func build() -> void:
	if _built:
		return
	name = "BrownNissanCube"
	chassis = Node3D.new()
	chassis.name = "Chassis"
	add_child(chassis)
	_build_imported_model()
	_build_damage_library()
	_build_suspension()
	_build_brake_lights()
	_build_headlights()
	_impact_material = StandardMaterial3D.new()
	_impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_impact_material.albedo_color = Color("ffc484", 0.0)
	for index in 2:
		var mount := Vector3(State.AXLES[index].x, -State.AXLES[index].y, 0) * S
		axles[index].position = mount + Vector3.DOWN * Tuning.STATIC_LENGTH * S
		_pose_suspension(index, mount, axles[index].position)
	_built = true
	set_damage_stage(damage_stage)


## Swap immutable mesh resources on this car only; wheels and suspension stay put.
func set_damage_stage(stage: int) -> void:
	assert(stage >= 0 and stage <= State.MAX_DAMAGE_STAGE, "Invalid Cube damage stage.")
	damage_stage = stage
	if not _built or _shown_damage_stage == stage:
		return
	for part: String in DAMAGE_PARTS:
		var instance := chassis.get_node(part) as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			instance.set_surface_override_material(surface, null)
		instance.mesh = _damage_meshes[stage][part] as Mesh
	var points: Dictionary = _damage_points[stage]
	_paint_sample.position = Vector3(points["BodyPaintSample"]) * MODEL_SCALE + BODY_OFFSET
	for side in 2:
		brake_lights[side].position = Vector3(points[DAMAGE_SOCKETS[1 + side]]) \
			* MODEL_SCALE + BODY_OFFSET
		headlights[side].position = Vector3(points[DAMAGE_SOCKETS[3 + side]]) \
			* MODEL_SCALE + BODY_OFFSET
	_find_headlight_surface()
	_apply_finish()
	_update_headlights(headlight_level)
	_shown_damage_stage = stage


## Wears a bought paint and wheel finish. Empty ids restore the exported
## bronze and alloys, so this is also how a car is stripped back to factory.
func set_finish(paint := "", rim := "") -> void:
	paint_id = paint
	rim_id = rim
	if _built:
		_apply_finish()


func _apply_finish() -> void:
	if _body != null:
		Finish.dress_body(_body, paint_id)
	for wheel in _rims:
		Finish.dress_rim(wheel, rim_id)


## Pitch, wheel travel and wheel rotation remain essential under reduced motion.
func apply_state(
	state: State, braking := false, delta := 0.0,
	reduced_motion := false, intense_effects := true, night_amount := 0.0
) -> void:
	build()
	set_damage_stage(state.damage_stage)
	position = Art.world_point(state.position)
	_animate_chassis(state, delta, reduced_motion, intense_effects)
	for index in 2:
		var center := Art.world_point(state.wheel_centers[index]) - position \
			+ _airborne_wheel_offset(state, index, reduced_motion)
		axles[index].position = center
		axles[index].rotation.z = -state.wheel_angles[index]
		var mount := chassis.position + chassis.basis \
			* Vector3(State.AXLES[index].x, -State.AXLES[index].y, 0) * S
		_pose_suspension(index, mount, center)
	var airborne := state.is_airborne()
	for spring in springs:
		spring.visible = airborne
	var target := 1.0 if braking and state.crash_wait == 0.0 else 0.0
	if reduced_motion or delta <= 0.0:
		brake_level = target
	else:
		var response := 22.0 if target > brake_level else 14.0
		brake_level = lerpf(brake_level, target, 1.0 - exp(-delta * response))
	_brake_material.albedo_color = _brake_color.lerp(BRAKE_COLOR, brake_level)
	_brake_material.emission_energy_multiplier = BRAKE_EMISSION * brake_level
	for light in brake_lights:
		light.visible = intense_effects and not reduced_motion and brake_level > 0.01
		light.light_energy = brake_level * 0.7
	_update_headlights(night_amount)


func play_impact() -> void:
	_impact_time = 0.0


func play_jump() -> void:
	_jump_time = 0.0
	_landing_time = LANDING_DURATION


func reset_motion() -> void:
	_drive_pitch = 0.0
	_drive_bob = 0.0
	_motion_ready = false
	_impact_time = IMPACT_DURATION
	_jump_time = JUMP_DURATION
	_landing_time = LANDING_DURATION
	_landing_strength = 0.0
	_airborne_time = 0.0
	_last_vertical_speed = 0.0
	if _body != null:
		_body.material_overlay = null


func _animate_chassis(state: State, delta: float, reduced: bool, intense: bool) -> void:
	if reduced or state.is_over():
		reset_motion()
	elif delta > 0.0 and not get_tree().paused:
		var acceleration := (state.velocity.x - _last_speed) / delta if _motion_ready else 0.0
		var grounded := state.contacts > 0 and state.crash_wait == 0.0 and state.started
		if state.crash_wait > 0.0:
			_airborne_time = 0.0
			_jump_time = JUMP_DURATION
			_landing_time = LANDING_DURATION
		elif grounded:
			if _airborne_time >= State.DAMAGE_AIR_TIME:
				_landing_time = 0.0
				_landing_strength = clampf(_last_vertical_speed / State.JUMP_SPEED, 0.15, 1.0)
			_airborne_time = 0.0
		elif state.started:
			_airborne_time += delta
		var target := clampf(acceleration / 650.0, -1.0, 1.0) * MAX_DRIVE_PITCH \
			if grounded else 0.0
		if not grounded and state.crash_wait == 0.0 and state.started:
			target = clampf(-state.velocity.y / State.JUMP_SPEED, -1.0, 1.0) * 0.035
		_drive_pitch = lerpf(_drive_pitch, target, 1.0 - exp(-delta * 10.0))
		var speed := clampf(absf(state.velocity.x) / 420.0, 0.0, 1.0) if grounded else 0.0
		_drive_bob = sin((state.wheel_angles[0] + state.wheel_angles[1]) * 0.3) * speed * 0.035
		_impact_time = minf(IMPACT_DURATION, _impact_time + delta)
		_jump_time = minf(JUMP_DURATION, _jump_time + delta)
		_landing_time = minf(LANDING_DURATION, _landing_time + delta)
		_last_speed = state.velocity.x
		_last_vertical_speed = state.velocity.y
		_motion_ready = true
	var envelope := pow(1.0 - _impact_time / IMPACT_DURATION, 2.0)
	var recoil := sin(_impact_time * 38.0) * envelope
	var jump_phase := _jump_time / JUMP_DURATION
	var launch := -cos(jump_phase * TAU) * pow(1.0 - jump_phase, 2.0) * 0.14
	var land_phase := _landing_time / LANDING_DURATION
	var landing := -sin(land_phase * TAU) * pow(1.0 - land_phase, 2.0) * _landing_strength
	chassis.position = Vector3(0, _drive_bob + recoil * 0.09 + launch + landing * 0.24, 0)
	chassis.rotation = Vector3(recoil * 0.035, 0,
		-state.angle + _drive_pitch + recoil * 0.085 + landing * 0.045)
	# A fixed cockpit eye needs a steady cabin, not panels moving through its near plane.
	if steady_cabin:
		chassis.position = Vector3.ZERO
		chassis.rotation = Vector3(0, 0, -state.angle)
	_impact_material.albedo_color.a = envelope * 0.48
	_body.material_overlay = _impact_material if intense and not reduced and envelope > 0.001 \
		else null


func _airborne_wheel_offset(state: State, index: int, reduced: bool) -> Vector3:
	if reduced or not state.is_airborne():
		return Vector3.ZERO
	var extension := AIRBORNE_WHEEL_DROP * smoothstep(0.0, WHEEL_DROP_DURATION, _airborne_time)
	var down := Vector2.DOWN.rotated(state.angle)
	var arm := State.AXLES[index].rotated(state.angle)
	var velocity := state.velocity + Vector2(-arm.y, arm.x) * state.angular_velocity
	var reach := AIRBORNE_WHEEL_DROP / S \
		+ maxf(0.0, velocity.dot(down)) * WHEEL_RETRACT_SECONDS
	# Retract before contact, using the same tire-radius-offset road as the real suspension.
	var hit := Course.wheel_contact(state.wheel_centers[index], down, reach, State.WHEEL_RADIUS)
	if not hit.is_empty():
		var clearance := maxf(0.0, float(hit["length"]))
		extension = minf(extension * smoothstep(0.0, reach, clearance), clearance * S)
	return Vector3(down.x, -down.y, 0.0) * extension


func paint_sample() -> Vector3:
	return _paint_sample.global_position


## Keep the eye inside the actual crumpled roof without changing or replacing the cabin.
func cockpit_position() -> Vector3:
	if not _cockpit_positions.has(damage_stage):
		var eye := DRIVER_EYE
		var ceiling := -INF
		var vertices := _body.mesh.get_faces()
		var above := Vector3(eye.x, 3.0, eye.z)
		var below := Vector3(eye.x, 0.0, eye.z)
		for index in range(0, vertices.size(), 3):
			var a := vertices[index]
			var b := vertices[index + 1]
			var c := vertices[index + 2]
			if eye.x < minf(a.x, minf(b.x, c.x)) or eye.x > maxf(a.x, maxf(b.x, c.x)) \
				or eye.z < minf(a.z, minf(b.z, c.z)) or eye.z > maxf(a.z, maxf(b.z, c.z)):
				continue
			var hit: Variant = Geometry3D.segment_intersects_triangle(above, below, a, b, c)
			if hit is Vector3:
				ceiling = maxf(ceiling, hit.y)
		assert(is_finite(ceiling), "The driver's eye must be under the authored Cube roof.")
		eye.y = minf(eye.y, ceiling - 0.14)
		_cockpit_positions[damage_stage] = _body.transform * eye
	return _cockpit_positions[damage_stage]


## Use actual transformed meshes so suspension travel and pitch cannot crop the car.
func local_bounds() -> AABB:
	var inverse := global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	for part in _parts:
		var transformed := (inverse * part.global_transform) * mesh_bounds(part)
		bounds = transformed if first else bounds.merge(transformed)
		first = false
	return bounds


static func mesh_bounds(part: MeshInstance3D) -> AABB:
	return part.custom_aabb if part.custom_aabb.has_volume() else part.mesh.get_aabb()


func _build_imported_model() -> void:
	var imported := MODEL.instantiate() as Node3D
	assert(imported != null, "The Cube GLB must import as a Node3D scene.")
	for node in imported.find_children("*", "", true, false):
		node.owner = null
	var vehicle := imported.get_node("NissanCube") as Node3D
	var body := vehicle.get_node("Chassis") as Node3D
	assert(body != null, "The Cube GLB must contain its authored chassis.")
	var body_fit := Transform3D(Basis.from_scale(BODY_SCALE), BODY_OFFSET)
	for child: Node3D in body.get_children():
		body.remove_child(child)
		chassis.add_child(child)
		child.transform = body_fit * child.transform
		if child is MeshInstance3D:
			_register_mesh(child)
	_paint_sample = chassis.get_node("BodyPaintSample") as Node3D
	_body = chassis.get_node("BrownBodywork") as MeshInstance3D
	assert(_body != null, "The Cube GLB must batch its bodywork into one node.")
	var lamps := chassis.get_node("RearBrakeLights") as MeshInstance3D
	assert(lamps.mesh.get_surface_count() == 1,
		"The exported brake lights need their own single material surface.")
	_brake_material = lamps.get_active_material(0).duplicate() as StandardMaterial3D
	assert(_brake_material != null, "The Cube needs a portable brake-light material.")
	_brake_color = _brake_material.albedo_color
	_brake_material.emission_enabled = true
	_brake_material.emission = Color("ff160c")
	_brake_material.emission_energy_multiplier = 0.0
	lamps.material_override = _brake_material
	for index in 2:
		var axle := Node3D.new()
		axle.name = "RearAxle" if index == 0 else "FrontAxle"
		add_child(axle)
		axles.append(axle)
		for side in 2:
			var wheel := vehicle.get_node(WHEEL_NODES[index][side]) as Node3D
			assert(wheel != null, "The Cube GLB must preserve all four wheel pivots.")
			vehicle.remove_child(wheel)
			axle.add_child(wheel)
			wheel.position = Vector3(0, 0, WHEEL_Z * (-1.0 if side == 0 else 1.0))
			wheel.scale = Vector3.ONE * TIRE_RADIUS / SOURCE_TIRE_RADIUS
			wheels.append(wheel)
			for part: String in ["Tires", "AlloyRims"]:
				var instance := wheel.get_node(WHEEL_PREFIXES[index][side] + part) \
					as MeshInstance3D
				assert(instance != null, "Every imported wheel needs tires and alloy rims.")
				instance.name = part
				_register_mesh(instance)
				if part == "AlloyRims":
					_rims.append(instance)
	imported.free()


func _build_damage_library() -> void:
	var pristine := {}
	for part: String in DAMAGE_PARTS:
		pristine[part] = (chassis.get_node(part) as MeshInstance3D).mesh
	_damage_meshes.append(pristine)
	_damage_points.append({
		"BodyPaintSample": (_paint_sample.position - BODY_OFFSET) / MODEL_SCALE,
		"LeftBrakeSocket": Vector3(-2.045, 0.677, -0.65),
		"RightBrakeSocket": Vector3(-2.045, 0.677, 0.65),
		"LeftHeadlightSocket": Vector3(2.005, 0.837, -0.644),
		"RightHeadlightSocket": Vector3(2.005, 0.837, 0.644),
	})
	var imported := DAMAGE_MODEL.instantiate() as Node3D
	var assembly := imported.get_node("NissanCubeDamage") as Node3D
	for stage in range(1, State.DAMAGE_NAMES.size()):
		var prefix: String = State.DAMAGE_NAMES[stage]
		var variant := assembly.get_node(prefix) as Node3D
		var meshes := {}
		var points := {}
		for part: String in DAMAGE_PARTS:
			var instance := variant.get_node(prefix + part) as MeshInstance3D
			assert(instance != null and instance.transform.is_equal_approx(Transform3D.IDENTITY),
				"Damage parts must keep the pristine chassis's local coordinates.")
			meshes[part] = instance.mesh
		for socket: String in DAMAGE_SOCKETS:
			points[socket] = (variant.get_node(prefix + socket) as Node3D).position
		_damage_meshes.append(meshes)
		_damage_points.append(points)
	imported.free()


func _register_mesh(instance: MeshInstance3D) -> void:
	_parts.append(instance)
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if instance.name in ["WraparoundGlazing", "LampGlazing"]:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _pose_suspension(index: int, mount: Vector3, center: Vector3) -> void:
	for side in 2:
		var depth := COILOVER_DEPTH * (-1.0 if side == 0 else 1.0)
		var a := mount + chassis.basis * Vector3(-COILOVER_RAKE, COILOVER_MOUNT_RISE, depth)
		var b := center + Vector3(0, 0, depth)
		springs[index * 2 + side].fit_between(a, b)


func _build_suspension() -> void:
	for index in 4:
		var strut := Coilover.new()
		strut.name = "Suspension%d" % index
		strut.visible = false
		add_child(strut)
		springs.append(strut)
		_parts.append(strut)


static func suspension_display() -> Coilover:
	var strut := Coilover.new()
	strut.set_length(Vector2(COILOVER_RAKE, COILOVER_MOUNT_RISE + Tuning.STATIC_LENGTH * S).length())
	return strut


## One imported wheel on its own, scaled to the tire radius the physics contacts
## use, for anything that wants to show the alloy without the rest of the car.
## [param rim] dresses it in a bought finish; "" leaves the exported alloys.
## The assembly it was exported inside is released before returning.
static func wheel_display(rim := "") -> Node3D:
	var imported := MODEL.instantiate() as Node3D
	for node in imported.find_children("*", "", true, false):
		node.owner = null
	var vehicle := imported.get_node("NissanCube") as Node3D
	var wheel := vehicle.get_node(WHEEL_NODES[1][1]) as Node3D
	assert(wheel != null, "The Cube GLB must preserve its front wheel pivots.")
	vehicle.remove_child(wheel)
	wheel.transform = Transform3D(
		Basis.from_scale(Vector3.ONE * TIRE_RADIUS / SOURCE_TIRE_RADIUS), Vector3.ZERO
	)
	for part: String in ["Tires", "AlloyRims"]:
		var instance := wheel.get_node(WHEEL_PREFIXES[1][1] + part) as MeshInstance3D
		instance.name = part
		if part == "AlloyRims":
			Finish.dress_rim(instance, rim)
	imported.free()
	return wheel


func _build_brake_lights() -> void:
	for side: float in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.name = "LeftBrakeGlow" if side < 0 else "RightBrakeGlow"
		light.position = Vector3(-2.045, 0.677, side * 0.65) * MODEL_SCALE + BODY_OFFSET
		light.light_color = Color("ff2412")
		light.light_energy = 0.0
		light.light_specular = 0.3
		light.omni_range = 0.85
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.visible = false
		chassis.add_child(light)
		brake_lights.append(light)


func _build_headlights() -> void:
	_headlight_mesh = chassis.get_node("HeadlightsAndIndicators") as MeshInstance3D
	_find_headlight_surface()
	_headlight_material = _headlight_mesh.mesh.surface_get_material(_headlight_surface) \
		.duplicate() as StandardMaterial3D
	_headlight_material.emission_enabled = true
	_headlight_material.emission = Art.CREAM
	for side: float in [-1.0, 1.0]:
		var light := SpotLight3D.new()
		light.name = "LeftHeadlight" if side < 0 else "RightHeadlight"
		light.position = Vector3(2.005, 0.837, side * 0.644) * MODEL_SCALE + BODY_OFFSET
		light.basis = Basis.looking_at(Vector3(1, -0.17, 0))
		light.light_color = Art.CREAM
		light.spot_range = 12.0
		light.spot_angle = 33.0
		light.spot_attenuation = 1.15
		light.light_specular = 0.35
		light.shadow_enabled = false
		light.light_energy = 0.0
		light.visible = false
		chassis.add_child(light)
		headlights.append(light)


func _find_headlight_surface() -> void:
	_headlight_surface = -1
	for surface in _headlight_mesh.mesh.get_surface_count():
		var exported := _headlight_mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		if exported != null and exported.resource_name == HEADLIGHT_MATERIAL:
			_headlight_surface = surface
			break
	assert(_headlight_surface >= 0,
		"The imported headlights must retain their separate 'Cube Bulb' material.")


func _update_headlights(night_amount: float) -> void:
	headlight_level = clampf(night_amount, 0.0, 1.0)
	_headlight_material.emission_energy_multiplier = headlight_level * 2.0
	_headlight_mesh.set_surface_override_material(_headlight_surface,
		_headlight_material if headlight_level > 0.0 else null)
	for light in headlights:
		light.light_energy = headlight_level * 2.0
		light.visible = headlight_level > 0.01
