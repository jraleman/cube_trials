extends Node3D

## The stock-proportion Blender car follows the tuned side-view suspension simulation.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const MODEL = preload("res://games/cube_trials/assets/models/nissan_cube.glb")
const S := Art.WORLD_SCALE
const MODEL_SCALE := Tuning.UNITS_PER_METER * S
const HALF_WIDTH := Tuning.SOURCE_HALF_WIDTH * MODEL_SCALE
const WHEEL_Z := Tuning.SOURCE_HALF_TRACK * MODEL_SCALE
const TIRE_RADIUS := State.WHEEL_RADIUS * S
const SOURCE_TIRE_RADIUS := Tuning.SOURCE_TIRE_RADIUS
const BODY_SCALE := Vector3.ONE * MODEL_SCALE
const BODY_OFFSET := Vector3(0, -Tuning.BODY_ORIGIN_HEIGHT * MODEL_SCALE, 0)
const BRAKE_EMISSION := 1.8
const BRAKE_COLOR := Color("ff2820")
const WHEEL_NODES := [
	["RearLeftWheel", "RearRightWheel"], ["FrontLeftWheel", "FrontRightWheel"],
]
const WHEEL_PREFIXES := [["LR", "RR"], ["LF", "RF"]]

var chassis: Node3D
var axles: Array[Node3D] = []
var wheels: Array[Node3D] = []
var springs: Array[MeshInstance3D] = []
var brake_lights: Array[OmniLight3D] = []
var brake_level := 0.0
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
var _built := false


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
	_build_suspension()
	_build_brake_lights()
	for index in 2:
		var mount := Vector3(State.AXLES[index].x, -State.AXLES[index].y, 0) * S
		axles[index].position = mount + Vector3.DOWN * Tuning.STATIC_LENGTH * S
		_pose_suspension(index, mount, axles[index].position)
	_apply_finish()
	_built = true


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
	reduced_motion := false, intense_effects := true
) -> void:
	build()
	position = Art.world_point(state.position)
	chassis.rotation.z = -state.angle
	for index in 2:
		var center := Art.world_point(state.wheel_centers[index]) - position
		axles[index].position = center
		axles[index].rotation.z = -state.wheel_angles[index]
		var mount_2d := State.AXLES[index].rotated(state.angle)
		var mount := Vector3(mount_2d.x, -mount_2d.y, 0) * S
		_pose_suspension(index, mount, center)
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


func paint_sample() -> Vector3:
	return _paint_sample.global_position


## Use actual transformed meshes so suspension travel and pitch cannot crop the car.
func local_bounds() -> AABB:
	var inverse := global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	for part in _parts:
		var transformed := (inverse * part.global_transform) * part.mesh.get_aabb()
		bounds = transformed if first else bounds.merge(transformed)
		first = false
	return bounds


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


func _register_mesh(instance: MeshInstance3D) -> void:
	_parts.append(instance)
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if instance.name in ["WraparoundGlazing", "LampGlazing"]:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _pose_suspension(index: int, mount: Vector3, center: Vector3) -> void:
	for side in 2:
		var depth := WHEEL_Z * (0.86 if side == 0 else -0.86)
		var a := mount + Vector3(0, 0, depth)
		var b := center + Vector3(0, 0, depth)
		var strut := springs[index * 2 + side]
		strut.position = (a + b) * 0.5
		strut.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		strut.scale = Vector3(1, a.distance_to(b), 1)


func _build_suspension() -> void:
	var mesh := suspension_mesh()
	var finish := suspension_material()
	for index in 4:
		var strut := MeshInstance3D.new()
		strut.name = "Suspension%d" % index
		strut.mesh = mesh
		strut.material_override = finish
		add_child(strut)
		springs.append(strut)
		_parts.append(strut)


## One coilover, authored a unit long and stretched to the travel each wheel is
## actually taking. All four struts share this single mesh.
static func suspension_mesh() -> ArrayMesh:
	var shaft := Builder.new()
	shaft.cylinder(Vector3.ZERO, 0.022, 1.0, Color("bfc8b8"), Vector3.ZERO, 12)
	for ring in 6:
		shaft.torus(Vector3(0, -0.36 + ring * 0.144, 0), 0.038, 0.052, Art.COPPER)
	return shaft.finish()


static func suspension_material() -> StandardMaterial3D:
	return Art.material(0.36, 0.45)


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
