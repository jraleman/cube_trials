extends SceneTree

## Geometry and animation contracts stay verifiable without a graphics driver.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const VehicleScene = preload("res://games/cube_trials/world/nissan_cube.tscn")

var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_imported_asset()
	_test_vehicle()
	_test_terrain_and_accessibility()
	if _failures.is_empty():
		print("Cube Trials 3D geometry tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_imported_asset() -> void:
	var imported := Cube.MODEL.instantiate()
	var assembly := imported.get_node("NissanCube") as Node3D
	_expect(assembly != null, "The car must come from the imported Blender assembly.")
	var triangles := 0
	var surfaces := 0
	var meshes := 0
	for node in imported.find_children("*", "", true, false):
		_expect(not (node is Camera3D or node is Light3D or node is CollisionObject3D),
			"The GLB must not import the studio or add competing collision physics.")
		if node is MeshInstance3D:
			meshes += 1
			var mesh: Mesh = node.mesh
			surfaces += mesh.get_surface_count()
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				triangles += (indices.size() if not indices.is_empty()
					else vertices.size()) / 3
				var material := mesh.surface_get_material(surface) as StandardMaterial3D
				_expect(material != null and material.albedo_texture == null,
					"The GLB must be self-contained without reference-image textures.")
			_check_mesh_normals(mesh)
	_expect(meshes == 16 and surfaces <= 48 and triangles <= 45000,
		"The exported car must stay batched within 16 meshes / 48 surfaces / 45,000 triangles.")
	var front := assembly.get_node("FrontRightWheel") as Node3D
	var rear := assembly.get_node("RearRightWheel") as Node3D
	for index in 2:
		for side in 2:
			var wheel := assembly.get_node(Cube.WHEEL_NODES[index][side])
			var prefix: String = Cube.WHEEL_PREFIXES[index][side]
			_expect(wheel.has_node(prefix + "Tires") and wheel.has_node(prefix + "AlloyRims"),
				"Re-exported wheels must retain unique, stable tire and rim node names.")
	_expect(is_equal_approx(front.position.x - rear.position.x, 2.53)
		and front.position.x > rear.position.x
		and is_equal_approx(front.position.y, 0.323),
		"The reusable GLB must retain meter scale, Y up, +X forward and authored wheel centers.")
	var glazing := assembly.get_node("Chassis/WraparoundGlazing") as MeshInstance3D
	for index in glazing.mesh.get_surface_count():
		var glass := glazing.get_active_material(index) as StandardMaterial3D
		_expect(glass.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			and glass.albedo_color.a > 0.0 and glass.albedo_color.a < 1.0
			and not glass.refraction_enabled,
			"The imported glass must use portable alpha rather than unsupported transmission.")
	imported.free()


func _test_vehicle() -> void:
	var car := VehicleScene.instantiate() as Cube
	get_root().add_child(car)
	var node_count := car.find_children("*", "", true, false).size()
	car.build()
	_expect(car.find_children("*", "", true, false).size() == node_count,
		"Repeated build calls must not duplicate the imported assembly.")
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	state.angle = -0.35
	state.wheel_angles = [0.8, 1.6]
	car.apply_state(state, true)
	_expect(car.axles.size() == 2 and car.wheels.size() == 4 and car.springs.size() == 4,
		"Two complete axles must carry four wheels and four independent suspension struts.")
	_expect(car.position.is_equal_approx(Art.world_point(state.position))
		and is_equal_approx(car.chassis.rotation.z, -state.angle),
		"The visible chassis must preserve the model's position and pitch sign.")
	for index in 2:
		_expect(car.axles[index].global_position.is_equal_approx(
			Art.world_point(state.wheel_centers[index])),
			"Wheel centers must follow suspension contacts rather than a decorative loop.")
		_expect(is_equal_approx(car.axles[index].rotation.z, -state.wheel_angles[index]),
			"Rim rotation must use the actual traveled wheel angle.")
		for side in 2:
			var wheel := car.wheels[index * 2 + side]
			var depth := Cube.WHEEL_Z * (-1.0 if side == 0 else 1.0)
			_expect(wheel.get_parent() == car.axles[index]
				and wheel.position.is_equal_approx(Vector3(0, 0, depth)),
				"All four authored wheel pivots must follow the correct axle and track width.")
			var tires := wheel.get_node("Tires") as MeshInstance3D
			var arrays := tires.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var radius := 0.0
			for vertex in vertices:
				radius = maxf(radius, Vector2(vertex.x, vertex.y).length() * wheel.scale.x)
			_expect(absf(radius - Cube.TIRE_RADIUS) < 0.004,
				"Visible tires must match the physics contact radius, not the stock Blender size.")
	var paint := car.get_node("Chassis/BrownBodywork") as MeshInstance3D
	var bounds := paint.transform * paint.mesh.get_aabb()
	_expect(bounds.size.x > 4.0 and bounds.size.y > 1.5 and bounds.size.z > 2.0,
		"The painted body must be a complete, rounded volumetric model.")
	_expect(car.get_node("Chassis/ChromeHandlesGrilleAndBadges") is MeshInstance3D
		and car.get_node("Chassis/WraparoundGlazing") is MeshInstance3D
		and car.get_node("Chassis/CabinAndDriver") is MeshInstance3D
		and car.get_node("Chassis/BodyPaintSample") is Node3D,
		"The imported Cube must preserve its glazing, chrome, cabin and exposed paint marker.")
	_expect(absf(bounds.position.y + 15.0 * Art.WORLD_SCALE) < 0.025
		and absf(bounds.end.y - 62.0 * Art.WORLD_SCALE) < 0.03,
		"The lifted body must retain the existing belly and roof envelope.")
	var envelope := car.local_bounds()
	for part in car.find_children("*", "MeshInstance3D", true, false):
		var local: AABB = (car.global_transform.affine_inverse() * part.global_transform) \
			* part.mesh.get_aabb()
		_expect(envelope.grow(0.001).encloses(local),
			"The framing envelope must contain pitched bodywork, suspension and all wheels.")
	var lamp := car.get_node("Chassis/RearBrakeLights") as MeshInstance3D
	var material := lamp.material_override as StandardMaterial3D
	var bright := material.albedo_color
	var other := Cube.new()
	get_root().add_child(other)
	var other_lamp := other.get_node("Chassis/RearBrakeLights") as MeshInstance3D
	_expect(other_lamp.material_override != material,
		"Brake feedback must not mutate shared imported materials across cars or portraits.")
	_expect(material.emission_energy_multiplier > 0.0,
		"Applied brakes must brighten the imported rear lights.")
	car.apply_state(state, false)
	_expect(material.albedo_color.r < bright.r
		and is_zero_approx(material.emission_energy_multiplier),
		"Braking must change the real rear-light material.")
	other.free()
	car.free()


func _test_terrain_and_accessibility() -> void:
	var world := Landscape.new()
	get_root().add_child(world)
	var road := world.get_node("ExactDrivingSurface") as MeshInstance3D
	var faces := road.mesh.get_faces()
	var gap_start: float = Course.ROADS[0][-1].x * Art.WORLD_SCALE
	var gap_end: float = Course.ROADS[1][0].x * Art.WORLD_SCALE
	for offset in range(0, faces.size(), 3):
		var center := (faces[offset] + faces[offset + 1] + faces[offset + 2]) / 3.0
		_expect(not (center.x > gap_start and center.x < gap_end),
			"The 3D driving surface must not bridge the model's quarry gap.")
		for index in 3:
			var vertex := faces[offset + index]
			var height := Course.ground_height(vertex.x / Art.WORLD_SCALE)
			_expect(is_finite(height) and absf(
				vertex.y - (Art.HEIGHT_ORIGIN - height) * Art.WORLD_SCALE
			) < 0.03, "Visible road geometry must agree with the collision profile.")
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	state.collected[0] = true
	state.checkpoint = 1
	state.velocity.x = 200
	world.present(state, 2.5, false, true, false)
	_expect(not world.plugs[0].visible and world.plugs[1].visible,
		"Only collected 3D spark plugs may disappear.")
	_expect(world.checkpoint_labels[0].text.contains("SAVED"),
		"Saved checkpoints must identify themselves in words, not only flag color.")
	var dust := world.get_node("OptionalTireDust") as MultiMeshInstance3D
	_expect(dust.multimesh.visible_instance_count > 0,
		"Moving tires may emit dust when both visual preferences allow it.")
	world.present(state, 0.0, true, true, false)
	_expect(dust.multimesh.visible_instance_count == 0
		and world.plugs[1].rotation == Vector3.ZERO,
		"Reduced motion must clear dust and park pickup rotation immediately.")
	world.present(state, 4.0, false, false, false)
	_expect(dust.multimesh.visible_instance_count == 0,
		"Disabling intense effects must also suppress dust.")
	state.collected.fill(true)
	world.present(state, 0.0, true, false, true)
	_expect(world.garage_label.text == "BRAKE TO PARK",
		"The physical garage must display the actual finish requirement.")
	world.free()


func _check_mesh_normals(mesh: Mesh) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_expect(vertices.size() == normals.size() and vertices.size() >= 3,
			"Every imported surface must contain geometry and authored lighting normals.")
		var valid := true
		for index in normals.size():
			if not (vertices[index].is_finite() and normals[index].is_finite()
				and absf(normals[index].length() - 1.0) < 0.001):
				valid = false
				break
		_expect(valid, "Every imported vertex must have a finite unit lighting normal.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
