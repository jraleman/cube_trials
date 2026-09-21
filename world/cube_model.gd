extends Node3D

## The imported Blender car follows the unchanged side-view suspension simulation.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const MODEL = preload("res://games/cube_trials/assets/models/nissan_cube.glb")
const S := Art.WORLD_SCALE
const HALF_WIDTH := 42.0 * S
const WHEEL_Z := 43.0 * S
const TIRE_RADIUS := State.WHEEL_RADIUS * S
const SOURCE_TIRE_RADIUS := 0.324
const BODY_SCALE := Vector3(106.0 * S / 2.53, 77.0 * S / 1.457, HALF_WIDTH / 0.85)
const BODY_OFFSET := Vector3(0, -15.0 * S - 0.218 * BODY_SCALE.y, 0)
const WHEEL_NODES := [
	["RearLeftWheel", "RearRightWheel"], ["FrontLeftWheel", "FrontRightWheel"],
]
const WHEEL_PREFIXES := [["LR", "RR"], ["LF", "RF"]]

var chassis: Node3D
var axles: Array[Node3D] = []
var wheels: Array[Node3D] = []
var springs: Array[MeshInstance3D] = []
var _parts: Array[MeshInstance3D] = []
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
	for index in 2:
		var mount := Vector3(State.AXLES[index].x, -State.AXLES[index].y, 0) * S
		axles[index].position = mount + Vector3.DOWN * State.REST_LENGTH * S
		_pose_suspension(index, mount, axles[index].position)
	_built = true


## Pitch, wheel travel and wheel rotation remain essential under reduced motion.
func apply_state(state: State, braking := false) -> void:
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
	_brake_material.albedo_color = Color("ff5c3f") if braking else _brake_color
	_brake_material.emission_energy_multiplier = 0.35 if braking else 0.0


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
	# The game is lifted: fit the stock body to its existing belly/roof envelope.
	var body_fit := Transform3D(Basis.from_scale(BODY_SCALE), BODY_OFFSET)
	for child: Node3D in body.get_children():
		body.remove_child(child)
		chassis.add_child(child)
		child.transform = body_fit * child.transform
		if child is MeshInstance3D:
			_register_mesh(child)
	_paint_sample = chassis.get_node("BodyPaintSample") as Node3D
	var lamps := chassis.get_node("RearBrakeLights") as MeshInstance3D
	assert(lamps.mesh.get_surface_count() == 1,
		"The exported brake lights need their own single material surface.")
	_brake_material = lamps.get_active_material(0).duplicate() as StandardMaterial3D
	assert(_brake_material != null, "The Cube needs a portable brake-light material.")
	_brake_color = _brake_material.albedo_color
	_brake_material.emission_enabled = true
	_brake_material.emission = Color("ff301b")
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
	imported.free()


func _register_mesh(instance: MeshInstance3D) -> void:
	_parts.append(instance)
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if instance.name in ["WraparoundGlazing", "LampGlazing"]:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _pose_suspension(index: int, mount: Vector3, center: Vector3) -> void:
	for side in 2:
		var depth := 0.72 if side == 0 else -0.72
		var a := mount + Vector3(0, 0, depth)
		var b := center + Vector3(0, 0, depth)
		var strut := springs[index * 2 + side]
		strut.position = (a + b) * 0.5
		strut.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		strut.scale = Vector3(1, a.distance_to(b), 1)


func _build_suspension() -> void:
	var shaft := Builder.new()
	shaft.cylinder(Vector3.ZERO, 0.045, 1.0, Color("bfc8b8"), Vector3.ZERO, 12)
	for ring in 9:
		shaft.torus(Vector3(0, -0.40 + ring * 0.1, 0), 0.060, 0.083, Art.COPPER)
	var mesh := shaft.finish()
	var finish := Art.material(0.36, 0.45)
	for index in 4:
		var strut := MeshInstance3D.new()
		strut.name = "Suspension%d" % index
		strut.mesh = mesh
		strut.material_override = finish
		add_child(strut)
		springs.append(strut)
		_parts.append(strut)
