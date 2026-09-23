extends SceneTree

## Geometry and animation contracts stay verifiable without a graphics driver.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Coilover = preload("res://games/cube_trials/world/coilover.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const VehicleScene = preload("res://games/cube_trials/world/nissan_cube.tscn")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const GalleryStage = preload("res://games/cube_trials/gallery_stage.gd")
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Game = preload("res://games/cube_trials/game.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const View = preload("res://games/cube_trials/course_view.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")

var _failures := PackedStringArray()
var _course := Course.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_imported_asset()
	_test_vehicle()
	_test_damage_variants()
	_test_stock_stance()
	_test_coilovers()
	_test_wheel_droop()
	_test_drive_animation()
	_test_jump_animation()
	_test_impact_animation()
	_test_brake_animation()
	_test_camera_modes()
	_test_flip_framing()
	_test_daylight()
	_test_automatic_headlights()
	_test_terrain_and_accessibility()
	_test_parking_and_night()
	_test_gallery_exhibits()
	_test_store_finishes()
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
	_expect(Cube.BODY_SCALE.is_equal_approx(Vector3.ONE * Cube.MODEL_SCALE)
		and absf(bounds.position.y - (0.218 - Tuning.BODY_ORIGIN_HEIGHT)
			* Cube.MODEL_SCALE) < 0.025,
		"The body must retain the stock proportions instead of being stretched into a truck.")
	var envelope := car.local_bounds()
	for part in car.find_children("*", "MeshInstance3D", true, false):
		var local: AABB = (car.global_transform.affine_inverse() * part.global_transform) \
			* Cube.mesh_bounds(part)
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


func _test_damage_variants() -> void:
	var library := Cube.DAMAGE_MODEL.instantiate()
	var assembly := library.get_node("NissanCubeDamage")
	_expect(assembly.get_child_count() == State.MAX_DAMAGE_STAGE,
		"The damage library must contain exactly four chassis variants, not duplicate cars.")
	for node in library.find_children("*", "", true, false):
		_expect(not (node is Camera3D or node is Light3D or node is CollisionObject3D)
			and not str(node.name).contains("Wheel"),
			"Damage assets must not contain studio nodes, wheels, or competing physics.")
	library.free()
	var car := Cube.new()
	var other := Cube.new()
	get_root().add_child(car)
	get_root().add_child(other)
	var node_count := car.find_children("*", "", true, false).size()
	var pristine := (car.chassis.get_node("BrownBodywork") as MeshInstance3D).mesh
	var pristine_bounds := pristine.get_aabb()
	var wheel_meshes: Array[Mesh] = []
	for wheel in car.wheels:
		wheel_meshes.append((wheel.get_node("Tires") as MeshInstance3D).mesh)
	var state := State.new()
	state.advance(0.5, 0.0, 0.0, 0.0)
	var previous_width := INF
	for stage in State.DAMAGE_NAMES.size():
		state.damage_stage = stage
		car.apply_state(state, true, 0.0, false, true, 1.0)
		var body := car.chassis.get_node("BrownBodywork") as MeshInstance3D
		var glass := car.chassis.get_node("WraparoundGlazing") as MeshInstance3D
		_expect(car.damage_stage == stage and body.mesh.get_aabb().size.x < previous_width,
			"Each stage must select a progressively crumpled chassis, not just recolor it.")
		previous_width = body.mesh.get_aabb().size.x
		_expect(_has_material(body.mesh, "Cube Scraped steel") == (stage > 0)
			and _has_material(glass.mesh, "Cube Glass fractures") == (stage >= 3),
			"Scuffs and cracked glazing must appear at the authored damage stages.")
		_expect(_has_material(body.mesh, Finish.BODY_COAT)
			and _has_material(body.mesh, Finish.BODY_EDGE),
			"Every damage variant must retain both named paint surfaces.")
		var triangles := 0
		var surfaces := 0
		for instance: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
			if instance is Coilover:
				continue
			surfaces += instance.mesh.get_surface_count()
			for surface in instance.mesh.get_surface_count():
				var arrays := instance.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			_check_mesh_normals(instance.mesh)
		_expect(triangles <= 48000 and surfaces <= 48
			and car.find_children("*", "", true, false).size() == node_count,
			"Only the active chassis may draw; every complete stage must fit 48k triangles / 48 surfaces.")
		for paint: String in Finish.PAINTS.keys() + [""]:
			car.set_finish(paint, "cube_rim_graphite")
			for surface in body.mesh.get_surface_count():
				var exported := body.mesh.surface_get_material(surface)
				var active := body.get_active_material(surface) as StandardMaterial3D
				if exported.resource_name == Finish.BODY_COAT:
					_expect(active.albedo_color.to_html(false) == Finish.swatch(paint).to_html(false)
						and car.damage_stage == stage,
						"Every bought or factory paint must work without repairing damage.")
				elif exported.resource_name.begins_with("Cube Exposed") \
					or exported.resource_name == "Cube Scraped steel":
					_expect(body.get_surface_override_material(surface) == null,
						"Repainting must not paint over exposed primer or bare-metal scrapes.")
		for rim: String in Finish.RIMS.keys():
			car.set_finish("", rim)
			for wheel in car.wheels:
				var alloys := wheel.get_node("AlloyRims") as MeshInstance3D
				_expect(_surface_colors(alloys).has(Finish.swatch(rim)),
					"All four wheels must retain every rim finish at every damage stage.")
		for index in car.wheels.size():
			_expect((car.wheels[index].get_node("Tires") as MeshInstance3D).mesh == wheel_meshes[index],
				"Damage must share the existing tires rather than swapping or deforming them.")
		var rear := car.chassis.get_node("RearBrakeLights") as MeshInstance3D
		var brake := rear.material_override as StandardMaterial3D
		var front := car.chassis.get_node("HeadlightsAndIndicators") as MeshInstance3D
		var bulb := front.get_active_material(int(car.get("_headlight_surface"))) as StandardMaterial3D
		_expect(is_equal_approx(brake.emission_energy_multiplier, Cube.BRAKE_EMISSION)
			and is_equal_approx(bulb.emission_energy_multiplier, Cube.HEADLIGHT_EMISSION)
			and car.headlights[0].visible,
			"Stage changes and repainting must preserve live brake and headlight emission.")
		var points: Dictionary = (car.get("_damage_points") as Array)[stage]
		_expect(car.headlights[0].position.is_equal_approx(
			Vector3(points["LeftHeadlightSocket"]) * Cube.MODEL_SCALE + Cube.BODY_OFFSET)
			and car.brake_lights[1].position.is_equal_approx(
			Vector3(points["RightBrakeSocket"]) * Cube.MODEL_SCALE + Cube.BODY_OFFSET),
			"Light emitters must follow the same authored deformation as the visible lenses.")
		car.apply_state(state, true, 0.0, true, false)
		_expect(car.damage_stage == stage and is_equal_approx(car.brake_level, 1.0)
			and not car.brake_lights[0].visible,
			"Accessibility settings must retain static damage and essential brake feedback.")
	_expect((car.chassis.get_node("BrownBodywork") as MeshInstance3D).mesh.get_aabb().end.y
		< pristine_bounds.end.y - 0.10,
		"The battered roof must visibly lose height, not leave pristine glass floating above it.")
	_expect((other.chassis.get_node("BrownBodywork") as MeshInstance3D).mesh == pristine
		and other.damage_stage == 0 and _finish_overrides(other).is_empty(),
		"Damage and repainting must not mutate another car or its shared imported resources.")
	car.apply_state(State.new())
	_expect((car.chassis.get_node("BrownBodywork") as MeshInstance3D).mesh == pristine
		and car.damage_stage == 0,
		"A fresh run must restore the exact pristine geometry on the existing assembly.")
	car.free()
	other.free()


func _has_material(mesh: Mesh, name: String) -> bool:
	for surface in mesh.get_surface_count():
		if mesh.surface_get_material(surface).resource_name == name:
			return true
	return false


func _test_stock_stance() -> void:
	var car := Cube.new()
	get_root().add_child(car)
	var state := State.new()
	state.advance(2.0, 0, 0, 0)
	car.apply_state(state)
	var envelope := car.local_bounds()
	_expect(envelope.size.y < 2.10 and Cube.TIRE_RADIUS < 0.36,
		"The complete car including aerial must be compact, with stock-sized tires.")
	var paint := car.get_node("Chassis/BrownBodywork") as MeshInstance3D
	var body_bounds := paint.global_transform * paint.mesh.get_aabb()
	var floor_height := Art.world_point(Vector2(state.position.x,
		_course.ground_height(state.position.x))).y
	var clearance := body_bounds.position.y - floor_height
	_expect(clearance > 0.20 and clearance < 0.25,
		"The body must sit about 23 cm off the road, not float over extended suspension.")
	for index in 2:
		var x := -1.265 if index == 0 else 1.265
		var arch := car.chassis.to_global(
			Vector3(x, Tuning.SOURCE_AXLE_HEIGHT, 0) * Cube.MODEL_SCALE + Cube.BODY_OFFSET
		)
		_expect(arch.distance_to(car.axles[index].global_position) < 0.015,
			"Resting wheel centers must align with the actual modeled wheel arches.")
		for side in 2:
			var wheel := car.wheels[index * 2 + side]
			var tire := wheel.get_node("Tires") as MeshInstance3D
			var bounds := tire.mesh.get_aabb()
			var outer := absf(wheel.position.z) \
				+ maxf(absf(bounds.position.z), absf(bounds.end.z)) * wheel.scale.z
			_expect(outer < Cube.HALF_WIDTH + 0.04,
				"Tires must sit under the fenders rather than outside the body like a truck.")
			var inner := absf(wheel.position.z) \
				- maxf(absf(bounds.position.z), absf(bounds.end.z)) * wheel.scale.z
			var spring := car.springs[index * 2 + side]
			var strut_bounds := spring.transform * spring.custom_aabb
			_expect(maxf(absf(strut_bounds.position.z), absf(strut_bounds.end.z)) < inner,
				"Coilovers must sit inboard of the tires, not outside the wheel wells.")
	for spring in car.springs:
		_expect(spring.scale.is_equal_approx(Vector3.ONE) and spring.length > 0.50 and spring.length < 0.65,
			"The internal coilovers must include their fixed housings without raising the stock car.")
	_check_coilover_visibility(car, false, "A parked car must not expose its coilovers.")
	car.free()


func _check_coilover_visibility(car: Cube, visible: bool, message: String) -> void:
	for spring in car.springs:
		_expect(spring.visible == visible, message)


func _check_wheel_droop(car: Cube, state: State, reduced := false) -> float:
	var down := Vector2.DOWN.rotated(state.angle)
	var direction := Vector3(down.x, -down.y, 0.0)
	var peak := 0.0
	for index in 2:
		var offset := car.axles[index].global_position - Art.world_point(state.wheel_centers[index])
		var extension := offset.dot(direction)
		# Global subtraction on the longer course loses a few float32 ULPs.
		_expect(extension >= -0.0001 and extension <= Cube.AIRBORNE_WHEEL_DROP + 0.0001
			and extension <= 0.18 and offset.distance_to(direction * extension) < 0.0001,
			"Visual wheel droop must be slight and follow chassis pitch, never widen the track.")
		if reduced or not state.is_airborne():
			_expect(offset.is_zero_approx(),
				"Ground contact, reduced motion, recovery and results must retain exact physics hubs.")
		elif extension > 0.001:
			var hit := _course.wheel_contact(state.wheel_centers[index], down,
				Cube.AIRBORNE_WHEEL_DROP / Art.WORLD_SCALE, State.WHEEL_RADIUS)
			_expect(hit.is_empty() or extension <= maxf(0.0, float(hit["length"])) \
				* Art.WORLD_SCALE + 0.0001,
				"Extra visual travel must not push an airborne tire through the sloped road.")
		_expect(is_equal_approx(car.axles[index].rotation.z, -state.wheel_angles[index]),
			"Drooping wheels must retain their real rolling angle.")
		peak = maxf(peak, extension)
	return peak


func _test_wheel_droop() -> void:
	for fps: int in [30, 60, 144]:
		var car := Cube.new()
		get_root().add_child(car)
		var state := State.new()
		state.advance(0.5, 0.0, 0.0, 0.0)
		car.apply_state(state)
		var peak := 0.0
		var before_landing := 0.0
		var landed := false
		for frame in fps * 2:
			state.advance(1.0 / fps, 0.0, 0.0, 0.0, frame == 0)
			if frame == 0:
				car.play_jump()
			var wheels := state.wheel_centers.duplicate()
			var position := state.position
			var velocity := state.velocity
			car.apply_state(state, false, 1.0 / fps)
			var extension := _check_wheel_droop(car, state)
			_expect(state.wheel_centers == wheels and state.position == position
				and state.velocity == velocity,
				"Airborne wheel droop must be presentation-only at every render frame rate.")
			peak = maxf(peak, extension)
			if frame == 0:
				_expect(extension < 0.04, "The wheels must ease outward, not pop to full droop at takeoff.")
			if state.is_airborne():
				before_landing = extension
			elif not landed and peak > 0.0:
				landed = true
				_expect(before_landing < 0.035,
					"Wheel droop must retract before touchdown instead of snapping the full travel.")
		_expect(peak >= 0.14 and peak <= 0.18 and landed,
			"A real jump must show a restrained 14-18 cm wheel drop and a clean landing at %d FPS." % fps)
		state.advance(0.25, 0.0, 0.0, 0.0, true)
		car.apply_state(state, false, 0.25, false, false)
		_expect(_check_wheel_droop(car, state) >= 0.14,
			"Disabling intense effects must not disable the airborne suspension pose.")
		car.apply_state(state, false, 0.0, true)
		_check_wheel_droop(car, state, true)
		_check_coilover_visibility(car, true,
			"Reduced motion removes extra wheel droop, not the actual airborne coilovers.")
		state.recover()
		car.reset_motion()
		car.apply_state(state)
		_check_wheel_droop(car, state)
		car.apply_state(State.new())
		_check_wheel_droop(car, State.new())
		car.free()


func _coilover_vertices(strut: Coilover) -> PackedVector3Array:
	var arrays := strut.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var shapes := (strut.mesh as ArrayMesh).surface_get_blend_shape_arrays(0)
	var compressed: PackedVector3Array = shapes[0][Mesh.ARRAY_VERTEX]
	var extended: PackedVector3Array = shapes[1][Mesh.ARRAY_VERTEX]
	var compression := strut.get_blend_shape_value(0)
	var extension := strut.get_blend_shape_value(1)
	for index in vertices.size():
		vertices[index] = vertices[index] * (1.0 - compression - extension) \
			+ compressed[index] * compression + extended[index] * extension
	return vertices


func _colored_bounds(vertices: PackedVector3Array, colors: PackedColorArray, color: Color) -> AABB:
	var bounds := AABB()
	var found := false
	for index in colors.size():
		if not colors[index].is_equal_approx(color):
			continue
		bounds = bounds.expand(vertices[index]) if found else AABB(vertices[index], Vector3.ZERO)
		found = true
	_expect(found, "The coilover must retain its separately colored mechanical components.")
	return bounds


func _test_coilovers() -> void:
	var strut := Coilover.new()
	var other := Coilover.new()
	var mesh := strut.mesh as ArrayMesh
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_expect(mesh == other.mesh and mesh.get_blend_shape_count() == 2
		and mesh.get_surface_count() == 1 and mesh.get_faces().size() / 3 < 2000,
		"Four coilovers must share one low-poly, single-surface mesh with independent travel morphs "
		+ "(%d triangles)." % (mesh.get_faces().size() / 3))
	_check_mesh_normals(mesh)
	var previous_shaft := 0.0
	for length: float in [0.38, Coilover.REFERENCE_LENGTH, 0.80]:
		strut.set_length(length)
		var vertices := _coilover_vertices(strut)
		for vertex in vertices:
			_expect(vertex.is_finite() and strut.custom_aabb.grow(0.001).has_point(vertex),
				"Deformed coilovers must stay finite and inside their current render/framing bounds.")
		var casing := _colored_bounds(vertices, colors, Coilover.CASE_COLOR)
		var shaft := _colored_bounds(vertices, colors, Coilover.SHAFT_COLOR)
		var coil := _colored_bounds(vertices, colors, Coilover.COIL_COLOR)
		_expect(absf(casing.size.y - Coilover.CASE_LENGTH) < 0.001
			and shaft.size.y > previous_shaft and absf(shaft.size.x - 0.038) < 0.001
			and absf(shaft.size.y - (length - 0.195)) < 0.001,
			"The housing must stay rigid while the chrome shaft telescopes, never scales sideways.")
		_expect(absf(coil.size.x - 2.0 * (Coilover.SPRING_RADIUS + Coilover.WIRE_RADIUS)) < 0.002,
			"Spring compression must change pitch without narrowing its round wire or coil diameter.")
		previous_shaft = shaft.size.y
	_expect(is_zero_approx(other.get_blend_shape_value(0))
		and is_zero_approx(other.get_blend_shape_value(1)),
		"Changing one strut's travel must not animate another instance of its shared mesh.")
	strut.free()
	other.free()
	var car := Cube.new()
	get_root().add_child(car)
	_check_coilover_visibility(car, false,
		"An unconfigured car, portrait or gallery car must start with its coilovers concealed.")
	var state := State.new()
	state.advance(0.5, 0.0, 0.0, 0.0)
	car.apply_state(state)
	var resting := car.springs[1].length
	var shortest := resting
	var longest := resting
	var resource := car.springs[1].mesh
	for frame in 180:
		state.advance(1.0 / 60.0, 0.0, 0.0, 0.0, frame == 0)
		if frame == 0:
			car.play_jump()
		var wheels := state.wheel_centers.duplicate()
		car.apply_state(state, false, 1.0 / 60.0)
		_check_wheel_droop(car, state)
		_check_coilover_visibility(car, state.contacts == 0,
			"Coilovers must appear only in flight and disappear as soon as a wheel lands.")
		shortest = minf(shortest, car.springs[1].length)
		longest = maxf(longest, car.springs[1].length)
		for index in 2:
			for side in 2:
				var spring := car.springs[index * 2 + side]
				var depth := Cube.COILOVER_DEPTH * (-1.0 if side == 0 else 1.0)
				var upper := car.chassis.to_global(
					Vector3(State.AXLES[index].x, -State.AXLES[index].y, 0) * Art.WORLD_SCALE
					+ Vector3(-Cube.COILOVER_RAKE, Cube.COILOVER_MOUNT_RISE, depth))
				var lower := car.axles[index].global_position + Vector3(0, 0, depth)
				_expect(spring.to_global(Vector3.UP * spring.length * 0.5).distance_to(upper) < 0.001
					and spring.to_global(Vector3.DOWN * spring.length * 0.5).distance_to(lower) < 0.001
					and spring.mesh == resource and state.wheel_centers == wheels,
					"Each coilover must stay bolted to the chassis and displayed hub without moving physics.")
		if frame == 25:
			var held_pose := car.springs[1].transform
			var held_length := car.springs[1].length
			var held_wheel := car.axles[0].transform
			paused = true
			car.apply_state(state, false, 0.5)
			_expect(car.springs[1].transform.is_equal_approx(held_pose)
				and is_equal_approx(car.springs[1].length, held_length)
				and car.axles[0].transform.is_equal_approx(held_wheel),
				"Paused redraws must freeze wheel droop, spring preload and the telescoping damper together.")
			_check_coilover_visibility(car, true,
				"Pausing in mid-flight must retain the visible suspension without advancing it.")
			paused = false
	_expect(shortest < resting - 0.05 and longest > resting + 0.10
		and absf(car.springs[1].length - resting) < 0.003,
		"A jump must visibly extend the coilovers, compress them on landing, and settle at stock height.")
	state.advance(State.STEP, 0.0, 0.0, 0.0, true)
	state.advance(0.25, 0.0, 0.0, 0.0)
	car.apply_state(state, false, 0.0, true, false)
	_expect(car.springs[1].length > resting + 0.06 and car.chassis.position == Vector3.ZERO,
		"Reduced motion must retain real airborne suspension travel without decorative body movement.")
	_check_coilover_visibility(car, true,
		"Reduced motion and disabled intense effects must retain airborne coilovers.")
	state.recover()
	car.reset_motion()
	car.apply_state(state)
	_expect(absf(car.springs[1].length - resting) < 0.003,
		"Recovery must restore the actual resting coilover length instead of leaving a stretched pose.")
	_check_coilover_visibility(car, false, "Recovery must conceal the grounded coilovers immediately.")
	car.apply_state(State.new())
	_expect(absf(car.springs[1].length - resting) < 0.003,
		"A new run must clear all old per-wheel spring compression.")
	_check_coilover_visibility(car, false, "Replay must not retain visible airborne coilovers.")
	state = State.new()
	state.advance(0.25, 0.0, 0.0, 0.0, true)
	for stage in State.DAMAGE_NAMES.size():
		state.damage_stage = stage
		car.apply_state(state, false, 0.25)
		_check_coilover_visibility(car, true, "Every damage stage must retain airborne coilovers.")
		_expect(_check_wheel_droop(car, state) >= 0.14,
			"Every damage stage must retain the same restrained airborne wheel extension.")
		state.contacts = 1
		car.apply_state(state)
		_check_wheel_droop(car, state)
		_check_coilover_visibility(car, false,
			"Even a one-wheel landing must conceal the coilovers at every damage stage.")
		state.contacts = 0
	state.crash_wait = State.CRASH_DELAY
	car.apply_state(state)
	_check_wheel_droop(car, state)
	_check_coilover_visibility(car, false, "A crash must not leave the coilovers exposed.")
	state.crash_wait = 0.0
	state.failed = true
	car.apply_state(state)
	_check_wheel_droop(car, state)
	_check_coilover_visibility(car, false, "Failed results must conceal the coilovers.")
	state.failed = false
	state.finished = true
	car.apply_state(state)
	_check_wheel_droop(car, state)
	_check_coilover_visibility(car, false, "Finished results must conceal the coilovers.")
	var exhibit := Cube.suspension_display()
	_expect(exhibit.visible and exhibit.mesh == resource and absf(exhibit.length - resting) < 0.003,
		"The standalone gallery strut must remain visible with the same geometry and parked preload.")
	exhibit.free()
	car.free()


func _test_drive_animation() -> void:
	var car := Cube.new()
	get_root().add_child(car)
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	car.apply_state(state, false, State.STEP)
	var lift := 0.0
	var bob := 0.0
	for frame in 24:
		state.advance(1.0 / 60.0, 1.0, 0.0, 0.0)
		var position := state.position
		car.apply_state(state, false, 1.0 / 60.0)
		lift = maxf(lift, car.chassis.rotation.z + state.angle)
		bob = maxf(bob, absf(car.chassis.position.y))
		_expect(state.position == position
			and car.axles[0].global_position.is_equal_approx(Art.world_point(state.wheel_centers[0])),
			"Decorative chassis motion must never move physics or wheel contacts.")
		_check_coilover_visibility(car, false,
			"Ordinary grounded acceleration must not expose the coilovers.")
	_expect(lift > 0.01 and lift <= Cube.MAX_DRIVE_PITCH and bob > 0.005,
		"Driving must visibly lift and gently rock the body in addition to turning the wheels.")
	var dive := 0.0
	for frame in 20:
		state.advance(1.0 / 60.0, 0.0, 1.0, 0.0)
		car.apply_state(state, true, 1.0 / 60.0)
		dive = minf(dive, car.chassis.rotation.z + state.angle)
		_check_coilover_visibility(car, false, "Grounded braking must keep the coilovers concealed.")
	_expect(dive < -0.005, "Actual braking must produce a short, bounded nose dive.")
	car.apply_state(state, true, 0.0, true)
	_expect(car.chassis.position == Vector3.ZERO
		and is_equal_approx(car.chassis.rotation.z, -state.angle)
		and is_equal_approx(car.axles[0].rotation.z, -state.wheel_angles[0]),
		"Reduced motion must remove body rocking without hiding essential pitch and wheel travel.")
	car.free()


func _test_jump_animation() -> void:
	var car := Cube.new()
	get_root().add_child(car)
	var state := State.new()
	state.advance(0.5, 0.0, 0.0, 0.0)
	car.apply_state(state, false, State.STEP)
	state.advance(State.STEP, 0.0, 0.0, 0.0, true)
	car.play_jump()
	car.apply_state(state, false, State.STEP)
	_expect(car.chassis.position.y < -0.04 and state.velocity.y < -490.0,
		"Takeoff must show a short spring compression while physics launches immediately.")
	var pose := car.chassis.transform
	paused = true
	car.apply_state(state, false, 0.5)
	_expect(car.chassis.transform.is_equal_approx(pose),
		"Pausing must freeze takeoff rather than spending its animation behind a menu.")
	paused = false
	var ascent := 0.0
	var descent := 0.0
	var compression := 0.0
	var rebound := 0.0
	for frame in 180:
		state.advance(1.0 / 60.0, 0.0, 0.0, 0.0)
		var position := state.position
		var velocity := state.velocity
		var wheels := state.wheel_centers.duplicate()
		car.apply_state(state, false, 1.0 / 60.0)
		var pitch := car.chassis.rotation.z + state.angle
		if state.contacts == 0:
			ascent = maxf(ascent, pitch)
			descent = minf(descent, pitch)
		else:
			compression = minf(compression, car.chassis.position.y)
			rebound = maxf(rebound, car.chassis.position.y)
		_expect(state.position == position and state.velocity == velocity and state.wheel_centers == wheels,
			"Jump and landing animation must leave the underlying physics and wheel contacts untouched.")
		_check_wheel_droop(car, state)
	_expect(ascent > 0.015 and descent < -0.015
		and compression < -0.025 and rebound > 0.005,
		"A jump must lean through its arc, compress on landing, then rebound and settle.")
	_expect(car.chassis.position.is_zero_approx() and absf(car.chassis.rotation.z) < 0.001
		and state.damage_stage == 0,
		"A normal landing must settle without leaving a permanent pose or cosmetic damage.")
	car.play_jump()
	car.apply_state(state, false, 0.04, true)
	_expect(car.chassis.position == Vector3.ZERO
		and is_equal_approx(car.chassis.rotation.z, -state.angle),
		"Reduced motion must suppress decorative jumping and landing without hiding chassis pitch.")
	car.apply_state(state, false, 0.04)
	_expect(is_equal_approx(float(car.get("_jump_time")), Cube.JUMP_DURATION),
		"Turning motion back on must not resurrect a suppressed jump.")
	car.play_jump()
	car.reset_motion()
	car.apply_state(state)
	_expect(car.chassis.position == Vector3.ZERO,
		"Replay and recovery must clear takeoff, airborne and landing transients.")
	car.steady_cabin = true
	car.play_jump()
	car.apply_state(state, false, 0.04)
	_expect(car.chassis.position == Vector3.ZERO
		and is_equal_approx(car.chassis.rotation.z, -state.angle),
		"Cockpit view must keep panels steady around its fixed eye while preserving physical pitch.")
	car.steady_cabin = false
	car.apply_state(state)
	_expect(car.chassis.position.y < -0.025,
		"Leaving Cockpit must restore the current exterior animation, not restart or discard it.")
	car.play_jump()
	state.failed = true
	car.apply_state(state, false, 0.04)
	_expect(car.chassis.position == Vector3.ZERO,
		"Jump animation must not continue behind terminal results.")
	car.free()


func _test_impact_animation() -> void:
	var car := Cube.new()
	var other := Cube.new()
	get_root().add_child(car)
	get_root().add_child(other)
	var state := State.new()
	state.damage_stage = State.MAX_DAMAGE_STAGE
	car.apply_state(state)
	other.apply_state(state)
	var body := car.chassis.get_node("BrownBodywork") as MeshInstance3D
	var other_body := other.chassis.get_node("BrownBodywork") as MeshInstance3D
	car.play_impact()
	car.apply_state(state, false, 0.04)
	_expect(car.chassis.position.length() > 0.02 and absf(car.chassis.rotation.z) > 0.02
		and body.material_overlay != null and other_body.material_overlay == null,
		"Even at maximum damage, impacts must recoil and highlight only the affected car.")
	var pose := car.chassis.transform
	var age: float = car.get("_impact_time")
	paused = true
	car.apply_state(state, false, 1.0)
	_expect(car.chassis.transform.is_equal_approx(pose) and car.get("_impact_time") == age,
		"Pausing or paused redraws must freeze, not restart or advance, an impact.")
	paused = false
	car.set_finish(Options.PAINT_SIGNAL, Options.RIM_GRAPHITE)
	car.apply_state(state, false, 0.0, false, false)
	_expect(body.material_overlay == null and car.damage_stage == State.MAX_DAMAGE_STAGE
		and car.chassis.transform.is_equal_approx(pose),
		"Disabling intense effects must clear the highlight without repairing or moving the car.")
	car.apply_state(state, false, 0.0, true)
	_expect(body.material_overlay == null and car.chassis.position == Vector3.ZERO
		and is_zero_approx(car.chassis.rotation.z),
		"Reduced motion must immediately clear decorative impact motion and highlights.")
	car.apply_state(state, false, 0.05)
	_expect(body.material_overlay == null,
		"Re-enabling animation cannot resurrect an accessibility-suppressed impact.")
	car.play_impact()
	for frame in 60:
		car.apply_state(state, false, 1.0 / 60.0)
	_expect(car.chassis.position == Vector3.ZERO and body.material_overlay == null,
		"An impact must settle completely, without an idle shake or stuck overlay.")
	car.play_impact()
	car.reset_motion()
	car.apply_state(state)
	_expect(car.chassis.position == Vector3.ZERO and body.material_overlay == null,
		"Recovery and replay resets must clear the complete transient pose.")
	car.play_impact()
	state.failed = true
	car.apply_state(state, false, 0.04)
	_expect(car.chassis.position == Vector3.ZERO and body.material_overlay == null,
		"A failed run must not keep animating behind results.")
	car.free()
	other.free()


func _test_brake_animation() -> void:
	var car := Cube.new()
	get_root().add_child(car)
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	car.apply_state(state, true, 1.0 / 60.0)
	_expect(car.brake_level > 0.0 and car.brake_level < 0.5,
		"Brakes must start a short rise rather than instantly jump to full glow.")
	for frame in 30:
		car.apply_state(state, true, 1.0 / 60.0)
	_expect(car.brake_level > 0.99 and car.brake_lights.size() == 2,
		"Holding the brake must reach full emission and both rear light spills.")
	for light in car.brake_lights:
		_expect(light.visible and light.light_energy > 0.65 and not light.shadow_enabled,
			"Brake glow must use restrained, shadow-free lights on the real rear lamps.")
	car.apply_state(state, false, 1.0 / 60.0)
	_expect(car.brake_level > 0.5 and car.brake_level < 0.99,
		"Releasing the brake must fade the live rear-light intensity.")
	for frame in 60:
		car.apply_state(state, false, 1.0 / 60.0)
	_expect(car.brake_level < 0.001 and not car.brake_lights[0].visible,
		"Released brakes must finish fading without a stuck light spill.")
	car.apply_state(state, true, 1.0 / 60.0, true, true)
	_expect(is_equal_approx(car.brake_level, 1.0) and not car.brake_lights[0].visible,
		"Reduced motion must keep immediate brake feedback while removing decorative glow.")
	car.apply_state(state, true, 0.0, false, false)
	var lamps := car.get_node("Chassis/RearBrakeLights") as MeshInstance3D
	var material := lamps.material_override as StandardMaterial3D
	_expect(is_equal_approx(material.emission_energy_multiplier, Cube.BRAKE_EMISSION)
		and not car.brake_lights[0].visible,
		"Disabling intense effects must not hide the essential emissive brake lamps.")
	state.crash_wait = 0.5
	car.apply_state(state, true)
	_expect(is_zero_approx(car.brake_level), "A recovery must clear stale brake input.")
	car.free()


func _test_camera_modes() -> void:
	var view := View.new()
	get_root().add_child(view)
	view.size = Vector2(1280, 720)
	view.set_day_night_enabled(false)
	var reference: State
	for mode in [View.CameraMode.SIDE, View.CameraMode.CHASE, View.CameraMode.COCKPIT]:
		var state := State.new()
		view.configure(state)
		view.set_camera_mode(mode)
		var positions_finite := true
		var terrain_clear := true
		var car_in_front := true
		for frame in 60 * 60:
			var input := Driver.controls(state)
			state.advance(1.0 / 60.0, input.x, input.y, input.z, Driver.jump_pressed(state))
			var position := state.position
			var clock := state.adjusted_time()
			view.present(1.0 / 60.0)
			_check_wheel_droop(view.world.car, state)
			_expect(state.position == position and state.adjusted_time() == clock,
				"A camera presentation must never move the simulation or spend race time.")
			positions_finite = positions_finite and view.world_camera.transform.is_finite()
			if mode == View.CameraMode.CHASE:
				terrain_clear = terrain_clear and _chase_sightline_clear(view)
				car_in_front = car_in_front \
					and not view.world_camera.is_position_behind(Art.world_point(state.position))
			if state.is_over():
				break
		_expect(state.finished and state.recoveries == 0 and positions_finite,
			"%s must follow a complete clean drive without invalid transforms." % view.camera_name())
		_expect(terrain_clear and car_in_front,
			"The chase camera must keep both its eye and its sight line clear of the exact road.")
		if reference == null:
			reference = state
		else:
			_expect(state.position == reference.position and state.elapsed == reference.elapsed
				and state.score() == reference.score() and state.lives_left == reference.lives_left,
				"Side, Chase and Cockpit must complete exactly the same physics and scoring run.")
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	view.configure(state)
	view.set_camera_mode(View.CameraMode.CHASE)
	var normal_eye := view.world_camera.position
	state.position.x += 30.0
	view.present(1.0 / 60.0)
	_expect(view.world_camera.position != normal_eye,
		"The chase eye must track actual movement rather than stay at its first pose.")
	var paused_pose := view.world_camera.transform
	paused = true
	view.present(2.0)
	_expect(view.world_camera.transform.is_equal_approx(paused_pose),
		"Direct paused redraws must not keep easing the chase camera.")
	paused = false
	view.set_reduced_motion(true)
	var slow_target: Vector3 = view.get("_chase_target")
	state.velocity.x = 600.0
	view.present(0.1)
	_expect((view.get("_chase_target") as Vector3).is_equal_approx(slow_target),
		"Reduced motion must remove decorative speed look-ahead.")
	view.set_reduced_motion(false)
	for frame in 30:
		view.present(1.0 / 60.0)
	_expect((view.get("_chase_target") as Vector3).x > slow_target.x + 1.0,
		"Normal chase driving must reveal more of the road ahead at speed.")
	state.recover()
	view.present(1.0 / 60.0)
	_expect(view.world_camera.position.distance_to(
		Art.world_point(state.position) + View.CHASE_OFFSET) < 0.001,
		"Recovery must snap the chase camera to the checkpoint, not interpolate across the course.")
	view.set_camera_mode(View.CameraMode.COCKPIT)
	for stage in State.DAMAGE_NAMES.size():
		state.damage_stage = stage
		view.present(0.0)
		var eye := view.world.car.cockpit_position()
		_expect(eye.is_finite() and view.world.car.local_bounds().has_point(eye)
			and view.world_camera.near < 0.05,
			"Every damage stage must retain a real cabin eye with a close dashboard clipping plane.")
		var pose := view.world_camera.transform
		view.world.car.play_impact()
		view.present(0.04)
		_expect(view.world_camera.transform.is_equal_approx(pose),
			"The cockpit must not inherit decorative impact recoil or body rocking.")
	state.angle = -0.35
	view.present(0.0)
	var forward := -view.world_camera.basis.z
	_expect(forward.x > 0.9 and forward.y > 0.25,
		"Cockpit aiming must retain essential nose-up pitch rather than point through the dashboard.")
	view.configure(State.new())
	_expect(view.camera_mode == View.CameraMode.COCKPIT,
		"Replay must retain the selected camera while resetting its follow state.")
	view.set_camera_mode(View.CameraMode.SIDE)
	_expect(view.world_camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		and not view.world.car.steady_cabin
		and not view.world.daylight.environment.fog_enabled
		and is_equal_approx(view.world_camera.near, 0.1)
		and (view.get_node("WorldImage") as TextureRect).material == null,
		"Returning to Side must restore the original projection and clear perspective haze and stale blur.")
	view.free()


func _chase_sightline_clear(view: View) -> bool:
	var at := view.world_camera.position
	var anchor := Art.world_point(view.state.position) + Vector3(0, 0.3, 0)
	for sample in range(1, 33):
		var point := anchor.lerp(at, sample / 32.0)
		var ground := _course.ground_height(point.x / Art.WORLD_SCALE)
		if is_finite(ground) and point.y < (Art.HEIGHT_ORIGIN - ground) * Art.WORLD_SCALE \
			+ View.CAMERA_CLEARANCE - 0.001:
			return false
	return true


func _test_flip_framing() -> void:
	var view := View.new()
	get_root().add_child(view)
	view.set_day_night_enabled(false)
	for id in [Profiles.CUBE, Profiles.SONATA, Profiles.CRV]:
		for dimensions in [Vector2(1280, 600), Vector2(390, 620), Vector2(2560, 520)]:
			view.size = dimensions
			for reduced: bool in [false, true]:
				var state := State.new(id)
				state.checkpoint = Course.CHECKPOINT_X.size() - 1
				state.recover()
				state.advance(0.5, 0.0, 0.0, 0.0)
				view.configure(state)
				view.set_reduced_motion(reduced)
				var visible := Rect2(Vector2.ZERO, view.size).grow(-12.0)
				var in_frame := true
				for frame in 120:
					var tilt := -1.0 if reduced else 1.0
					if frame < 10 or frame >= 60:
						tilt = 0.0
					state.advance(1.0 / 60.0, 0.0, 0.0, tilt, frame == 0)
					for event in state.take_events():
						if event["kind"] == "jump":
							view.world.car.play_jump()
					view.present(1.0 / 60.0)
					in_frame = in_frame and visible.encloses(view.car_screen_bounds())
				_expect(in_frame and state.landed_flips == 1 and state.lives_left == 5,
					"%s: takeoff, every flip angle and landing must fit at the mountain summit "
					% id + "in %s, reduced motion %s." % [dimensions, reduced])
	view.free()


func _test_daylight() -> void:
	var stage := Node3D.new()
	var lights := Art.light_stage(stage)
	var studio := Node3D.new()
	var studio_lights := Art.light_stage(studio)
	_expect(lights.sun.shadow_enabled and lights.sun.visible
		and is_equal_approx(lights.sun.light_energy, 0.85)
		and lights.sun.rotation_degrees.is_equal_approx(Vector3(-42, -38, 0))
		and lights.sky_material.sky_top_color.is_equal_approx(Daylight.DAY_TOP),
		"The cycle must begin with the same shadow-casting afternoon sun as the studios.")
	var sunset := (0.5 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS
	lights.set_elapsed(sunset)
	_expect(lights.sun.light_color.r > lights.sun.light_color.b * 1.5
		and lights.sky_material.sky_horizon_color.r
			> lights.sky_material.sky_horizon_color.b
		and lights.night_amount > 0.0 and lights.night_amount < 1.0,
		"Sunset must warm the real sky and gently bring up the evening lights.")
	var midnight := (0.75 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS
	lights.set_elapsed(midnight)
	_expect(not lights.sun.visible and is_zero_approx(lights.sun.light_energy)
		and is_equal_approx(lights.night_amount, 1.0)
		and lights.fill.light_energy >= 0.3
		and lights.environment.ambient_light_energy >= 0.3,
		"Night must remove sunlight while retaining readable moonlight and ambient fill.")
	_expect(lights.sky_material.sky_top_color.b > lights.sky_material.sky_top_color.r
		and studio_lights.sky_material.sky_top_color.is_equal_approx(Daylight.DAY_TOP)
		and studio_lights.sun.visible,
		"The blue night sky must not recolor another world's gallery or share lighting.")
	lights.set_elapsed((1.0 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS)
	_expect(lights.night_amount > 0.0 and lights.night_amount < 1.0,
		"Dawn must fade the lights back out instead of jumping directly to daylight.")
	lights.set_elapsed(Daylight.CYCLE_SECONDS - 0.001)
	var before_wrap := lights.sun.rotation
	lights.set_elapsed(Daylight.CYCLE_SECONDS)
	_expect(lights.sun.rotation.distance_to(before_wrap) < 0.001
		and lights.sky_material.sky_top_color.is_equal_approx(Daylight.DAY_TOP)
		and is_zero_approx(lights.night_amount),
		"A complete day must wrap smoothly back to the exact starting appearance.")
	stage.free()
	studio.free()


func _test_automatic_headlights() -> void:
	var car := Cube.new()
	var other := Cube.new()
	get_root().add_child(car)
	get_root().add_child(other)
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	car.apply_state(state)
	var bounds := car.local_bounds()
	var lenses := car.get_node("Chassis/HeadlightsAndIndicators") as MeshInstance3D
	var surface: int = car.get("_headlight_surface")
	var exported := lenses.mesh.surface_get_material(surface) as StandardMaterial3D
	var original_emission := exported.emission_energy_multiplier
	car.apply_state(state, true, 0.0, true, false, 1.0)
	var lit := lenses.get_active_material(surface) as StandardMaterial3D
	_expect(car.headlights.size() == 2 and is_equal_approx(car.headlight_level, 1.0)
		and lit != exported and lit.emission_energy_multiplier >= 2.0,
		"Night must brighten only the imported bulbs, using a per-car material.")
	for light in car.headlights:
		var forward := -light.basis.z
		_expect(light.visible and light.light_energy > 1.0
			and not light.shadow_enabled and light.get_parent() == car.chassis
			and forward.x > 0.95 and forward.y < 0.0,
			"Both headlights must follow chassis pitch and light the road ahead without shadows.")
	_expect(not car.brake_lights[0].visible and car.headlights[0].visible,
		"Essential night lighting must remain when decorative effects are disabled.")
	_expect(car.local_bounds().is_equal_approx(bounds)
		and not other.headlights[0].visible
		and is_equal_approx(exported.emission_energy_multiplier, original_emission),
		"Headlights must not alter car geometry, another car, or shared exported materials.")
	car.apply_state(state)
	_expect(not car.headlights[0].visible and not car.headlights[1].visible
		and is_equal_approx(lit.emission_energy_multiplier, Cube.RUNNING_EMISSION),
		"Daylight and replay must turn off the beams while retaining faint running lamps.")
	car.free()
	other.free()


func _test_parking_and_night() -> void:
	var world := Landscape.new()
	get_root().add_child(world)
	var garage := world.get_node("CopperCreekServiceGarage") as Node3D
	var outline := garage.get_node("ParkingOutline") as MeshInstance3D
	var glow := outline.material_override as ShaderMaterial
	var bounds := outline.global_transform * outline.mesh.get_aabb()
	var ground := Art.world_point(Vector2(Course.FINISH_X,
		_course.ground_height(Course.FINISH_X)))
	_expect(is_equal_approx(bounds.position.x, Course.FINISH_X * Art.WORLD_SCALE)
		and is_equal_approx(bounds.end.x,
			(Course.FINISH_X + Course.FINISH_WIDTH) * Art.WORLD_SCALE)
		and bounds.position.z < -Cube.HALF_WIDTH and bounds.end.z > Cube.HALF_WIDTH
		and bounds.position.y > ground.y and bounds.position.y < ground.y + 0.07,
		"The glowing bay must outline the real finish interval around the driving lane.")
	_expect(glow.shader == Landscape.PARKING_SHADER
		and outline.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"The parking cue must use a shadow-free, Compatibility-safe feathered outline.")
	var state := State.new()
	world.present(state, 1.0, false, true, false)
	_expect(world.parking_label.text == "NEED 5 PLUGS"
		and glow.get_shader_parameter("tint") == Landscape.PARKING_WAIT,
		"The incomplete delivery must identify missing cargo in words as well as color.")
	var pulse: float = glow.get_shader_parameter("pulse")
	world.present(state, 3.0, false, true, false)
	_expect(not is_equal_approx(pulse, glow.get_shader_parameter("pulse")),
		"The optional parking pulse must follow the supplied presentation clock.")
	state.collected.fill(true)
	state.collected[0] = false
	world.present(state, 0.0, true, false, false)
	_expect(world.parking_label.text == "NEED 1 PLUG"
		and is_equal_approx(glow.get_shader_parameter("pulse"), 1.0)
		and is_zero_approx(glow.get_shader_parameter("halo_strength"))
		and outline.visible,
		"Accessibility settings must remove animation and halo, never the parking instruction.")
	state.collected[0] = true
	world.present(state, 0.0, true, true, false)
	_expect(world.parking_label.text == "PARK HERE"
		and world.garage_label.text == "BRAKE TO PARK"
		and glow.get_shader_parameter("tint") == Landscape.PARKING_READY,
		"All five plugs must make the bay ready without pretending the car has finished.")
	state.position.x = Course.FINISH_X
	state.velocity.x = State.PARK_SPEED
	world.present(state, 0.0, true, true, false)
	_expect(world.parking_label.text == "SLOW DOWN" and not state.finished,
		"The approach cue must use the actual parking speed threshold without changing the rules.")
	state.finished = true
	world.present(state, 2.0, false, true, false)
	_expect(world.parking_label.text == "DELIVERED!"
		and world.garage_label.text == "DELIVERY COMPLETE"
		and is_equal_approx(glow.get_shader_parameter("pulse"), 1.0),
		"A successful delivery must leave a stable, explicit celebration on the bay.")
	var midnight := (0.75 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS
	world.present(state, 2.0, false, false, false, 0.0, midnight)
	var workshop := garage.get_node("WorkshopLight") as OmniLight3D
	_expect(workshop.visible and workshop.light_energy > 1.0
		and not workshop.shadow_enabled and world.car.headlights[0].visible,
		"Night must bring up the workshop and car lights even without intense effects.")
	for index in 5:
		var lamp := garage.get_node("DeliveredPlug%d" % (index + 1)) as MeshInstance3D
		_expect((lamp.material_override as StandardMaterial3D).emission_energy_multiplier > 0.0,
			"Collected plugs must light the real delivery bulbs after dark.")
	world.present(State.new(), 0.0, true, false, false)
	_expect(world.parking_label.text == "NEED 5 PLUGS"
		and glow.get_shader_parameter("tint") == Landscape.PARKING_WAIT
		and not workshop.visible and not world.car.headlights[0].visible,
		"Replay must reset the parking cue, completed state and automatic night lights together.")
	var exhibit := Landscape.garage_model(true)
	var exhibit_glow := (exhibit.get_node("ParkingOutline") as MeshInstance3D) \
		.material_override as ShaderMaterial
	_expect(exhibit_glow != glow
		and exhibit_glow.get_shader_parameter("tint") == Landscape.PARKING_READY,
		"The gallery must own a separate, ready parking material rather than inherit a live run.")
	exhibit.free()
	world.free()


func _test_terrain_and_accessibility() -> void:
	var world := Landscape.new()
	get_root().add_child(world)
	var pools := world.get_node("QuarryWater") as Node3D
	var ripples := world.get_node("QuietWaterRipples") as Node3D
	var clouds := world.get_node("SlowDriftingClouds") as Node3D
	_expect(pools.get_child_count() == _course.gap_intervals().size()
		and ripples.get_child_count() == pools.get_child_count() and clouds.get_child_count() > 8,
		"Water, ripples and clouds must extend along the route in locally culled groups.")
	for group in [pools, ripples, clouds]:
		for mesh: MeshInstance3D in group.get_children():
			_expect(mesh.mesh.get_aabb().size.x < 22.0,
				"Ambient batches must stay local, including the summit's 21.5-meter pool and banks.")
	var road := world.get_node("ExactDrivingSurface") as MeshInstance3D
	var faces := road.mesh.get_faces()
	for offset in range(0, faces.size(), 3):
		var center := (faces[offset] + faces[offset + 1] + faces[offset + 2]) / 3.0
		for gap in _course.gap_intervals():
			_expect(not (center.x > gap.x * Art.WORLD_SCALE and center.x < gap.y * Art.WORLD_SCALE),
				"The 3D driving surface must not bridge any of the six physics gaps.")
		for index in 3:
			var vertex := faces[offset + index]
			var height := _course.ground_height(vertex.x / Art.WORLD_SCALE)
			_expect(is_finite(height) and absf(
				vertex.y - (Art.HEIGHT_ORIGIN - height) * Art.WORLD_SCALE
			) < 0.03, "Visible road geometry must agree with the collision profile.")
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	var flag_materials: Array[StandardMaterial3D] = world.get("_flag_materials")
	var original_flag_color := flag_materials[0].albedo_color
	_expect(flag_materials.size() == Course.CHECKPOINT_X.size() - 1
		and flag_materials[0] != flag_materials[1],
		"Each imported checkpoint must own its live field material.")
	for index in world.plugs.size():
		var imported := world.plugs[index].get_node("ImportedPlug") as Node3D
		var bounds := imported.transform * GalleryStage.bounds_of(imported)
		_expect(is_equal_approx(bounds.size.y, Landscape.PLUG_HEIGHT)
			and absf(bounds.get_center().y) < 0.0001
			and world.plugs[index].position.is_equal_approx(
				Art.world_point(_course.plug_position(index))),
			"The imported plug must be enlarged and centered on the existing pickup anchor.")
		_expect(world.plugs[index].get_node("PickupRing") is MeshInstance3D
			and (world.plugs[index].get_node("PickupNumber") as Label3D).text == str(index + 1),
			"Imported pickups must retain their gold ring and distinct readable numbers.")
	var trees := _pine_poses(world)
	_expect(trees.size() > 20 and trees[-1].origin.x > Course.FINISH_X * Art.WORLD_SCALE,
		"The imported forest must extend past the relocated garage, not stop at the old finish.")
	for tree in trees:
		var planted: Vector3 = world.call("_terrain_point", tree.origin.x, tree.origin.z)
		_expect(tree.origin.is_equal_approx(planted),
			"Each generated pine must remain grounded on the exact hillside mesh.")
	var garage := world.get_node("CopperCreekServiceGarage") as Node3D
	var markings := garage.get_node("FinishBayMarkings") as MeshInstance3D
	var parking_bounds := markings.global_transform * markings.mesh.get_aabb()
	_expect(absf(parking_bounds.position.x - Course.FINISH_X * Art.WORLD_SCALE) < 0.04
		and absf(parking_bounds.end.x
			- (Course.FINISH_X + Course.FINISH_WIDTH) * Art.WORLD_SCALE) < 0.04,
		"The replacement garage must mark the real finish interval, not its extra parking stalls.")
	var shop := garage.get_node("ImportedBodyShop") as Node3D
	var apron := shop.to_global(Vector3(0, 0.16, 0))
	var ground := Art.world_point(Vector2(Course.FINISH_X, _course.ground_height(Course.FINISH_X)))
	_expect(apron.y > ground.y and apron.y - ground.y < 0.02,
		"The imported apron must clear z-fighting without floating above the driving surface.")
	var facade := shop.to_global(Vector3(0, 1, 4.0))
	_expect(facade.z < -Cube.HALF_WIDTH - 0.4,
		"The workshop facade must stay behind the car's driving plane.")
	var landscaping := shop.get_node("CarBodyShop/Landscaping") as MeshInstance3D
	var yard_obstacles := landscaping.global_transform * landscaping.mesh.get_aabb()
	_expect(yard_obstacles.end.z < -Cube.HALF_WIDTH - 0.2,
		"The imported fence and boulders must not obstruct the car's driving plane.")
	for corner: Vector3 in [Vector3(-8, 0.16, -4.8), Vector3(8.5, 0.16, -4.8),
			Vector3(-4.5, 0.16, 3.5), Vector3(4.5, 0.16, 3.5)]:
		var paved := shop.to_global(corner)
		var hillside: Vector3 = world.call("_terrain_point", paved.x, paved.z)
		_expect(hillside.y < paved.y and paved.y - hillside.y < 0.05,
			"The actual ridge triangles must sit below the imported open workshop and yard.")
	var site: Rect2 = world.get("_garage_site")
	for tree in trees:
		_expect(not site.has_point(Vector2(tree.origin.x, tree.origin.z)),
			"Background trees must not sprout through the imported workshop or its shelter.")
	for title: String in ["RoadsideTimber", "ShoulderGrass", "ScatteredQuarryStones"]:
		var decoration := world.get_node(title) as MeshInstance3D
		var clear := true
		for vertex in decoration.mesh.get_faces():
			if site.has_point(Vector2(vertex.x, vertex.z)):
				clear = false
				break
		_expect(clear, "Procedural trail scenery must not intrude into the imported yard: " + title)
	state.collected[0] = true
	state.checkpoint = 1
	state.velocity.x = 200
	world.present(state, 2.5, false, true, false, 1.0 / 60.0)
	_expect(not world.plugs[0].visible and world.plugs[1].visible,
		"Only collected 3D spark plugs may disappear.")
	_expect(world.checkpoint_labels[0].text.contains("SAVED"),
		"Saved checkpoints must identify themselves in words, not only flag color.")
	_expect(flag_materials[0].albedo_color.is_equal_approx(Art.TEAL)
		and flag_materials[1].albedo_color.is_equal_approx(original_flag_color),
		"Saving one checkpoint must not recolor the other imported flag.")
	for flag in world.checkpoint_flags:
		for surface in flag.mesh.get_surface_count():
			var exported := flag.mesh.surface_get_material(surface) as StandardMaterial3D
			var active := flag.get_active_material(surface) as StandardMaterial3D
			if exported.resource_name == Landscape.CHECKPOINT_FIELD_MATERIAL:
				_expect(active != exported
					and exported.albedo_color.is_equal_approx(original_flag_color),
					"Checkpoint state must never mutate the shared exported material.")
			else:
				_expect(active == exported,
					"Checkpoint feedback must preserve the authored dark checker pattern.")
		_expect(not is_zero_approx(flag.rotation.y)
			and (flag.get_parent().get_node("PoleAndHardware") as Node3D).rotation.is_zero_approx()
			and (flag.get_parent().get_node("Footing") as Node3D).rotation.is_zero_approx(),
			"Only imported cloth should sway, not the pole or stone footing.")
	var dust := world.get_node("OptionalTireDust") as MultiMeshInstance3D
	_expect(dust.multimesh.visible_instance_count > 0,
		"Moving tires may emit dust when both visual preferences allow it.")
	world.present(state, 0.0, true, true, false)
	_expect(dust.multimesh.visible_instance_count == 0
		and clouds.position == Vector3.ZERO and ripples.position == Vector3.ZERO
		and world.plugs[1].rotation == Vector3.ZERO
		and world.plugs[1].position.is_equal_approx(Art.world_point(_course.plug_position(1)))
		and world.checkpoint_flags[0].rotation.is_zero_approx()
		and world.checkpoint_flags[1].rotation.is_zero_approx(),
		"Reduced motion must clear dust and park imported pickup bob/spin and flag sway.")
	world.present(state, 4.0, false, false, false)
	_expect(dust.multimesh.visible_instance_count == 0,
		"Disabling intense effects must also suppress dust.")
	state.collected.fill(true)
	world.present(state, 0.0, true, false, true)
	_expect(world.garage_label.text == "BRAKE TO PARK",
		"The physical garage must display the actual finish requirement.")
	for index in 5:
		var lamp := garage.get_node("DeliveredPlug%d" % (index + 1)) as MeshInstance3D
		_expect((lamp.material_override as StandardMaterial3D).albedo_color == Art.CREAM,
			"The imported shop must retain all five live delivery indicators.")
	var replay := State.new()
	world.present(replay, 0.0, true, false, false)
	_expect(world.garage_label.text == "BRING ALL FIVE PLUGS"
		and flag_materials[0].albedo_color.is_equal_approx(original_flag_color)
		and flag_materials[1].albedo_color.is_equal_approx(original_flag_color),
		"Replay must reset the imported flag colors and shop instruction.")
	for index in 5:
		var lamp := garage.get_node("DeliveredPlug%d" % (index + 1)) as MeshInstance3D
		_expect(world.plugs[index].visible
			and (lamp.material_override as StandardMaterial3D).albedo_color == Color("3f5a50"),
			"Replay must restore every imported pickup and clear its delivery lamp.")
	world.free()


## Every plinth has to have something standing on it, framed from somewhere
## worth looking. An exhibit whose id the stage does not recognise would open an
## empty case, and one with no framing entry would open on an angle nobody chose.
##
## Headless has no renderer, so the stage is never mounted: `build_exhibit` is
## deliberately tree-free, and `bounds_of` measures by walking transforms rather
## than asking for a global one.
func _test_gallery_exhibits() -> void:
	var manifest := Game.manifest()
	_expect(manifest.has_gallery(),
		"Cube Trials must declare both its exhibits and the stage that draws them.")
	_expect(manifest.gallery_exhibits == Options.GALLERY_EXHIBITS,
		"The manifest must exhibit the list the game owns, not a second copy.")
	var stage := GalleryStage.new()
	var ids: Array[String] = []
	for exhibit: Dictionary in Options.GALLERY_EXHIBITS:
		var id := str(exhibit["id"])
		_expect(not ids.has(id), "Gallery exhibit ids must be unique: " + id)
		ids.append(id)
		if id in [Options.EXHIBIT_SONATA, Options.EXHIBIT_CRV]:
			var requirement := Course.COPPER_COMPLETE if id == Options.EXHIBIT_SONATA \
				else Course.SUNSET_COMPLETE
			_expect(str(exhibit.get("requires_achievement", "")) == requirement,
				"Gallery cars must use the same completion gates as playable cars.")
		_expect(GalleryStage.FRAMING.has(id),
			"The gallery stage must know where to open '%s' from." % id)
		var model: Node3D = stage.call("build_exhibit", id)
		_expect(model != null, "The gallery stage must build '%s'." % id)
		if model == null:
			continue
		var bounds := GalleryStage.bounds_of(model)
		_expect(bounds.size.length() > 0.1 and bounds.get_center().is_finite(),
			"Exhibit '%s' must have something to look at." % id)
		_expect(model.find_children("*", "MeshInstance3D", true, false).size() > 0,
			"Exhibit '%s' must be built from real geometry." % id)
		model.free()
	_expect(ids.has(Options.EXHIBIT_SONATA) and ids.has(Options.EXHIBIT_CRV),
		"Both saved reference cars must appear in the game's Gallery catalogue.")
	_expect(stage.call("build_exhibit", "not_an_exhibit") == null,
		"The gallery stage must not invent a model for an id it does not know.")
	_test_gallery_provenance(stage)
	_test_gallery_reference_cars(stage)
	stage.free()


func _test_gallery_reference_cars(stage: GalleryStage) -> void:
	for sample: Dictionary in [
		{"id": Options.EXHIBIT_SONATA, "asset": GalleryStage.SONATA_MODEL,
			"assembly": ^"HyundaiSonata"},
		{"id": Options.EXHIBIT_CRV, "asset": GalleryStage.CRV_MODEL,
			"assembly": ^"HondaCRV"},
	]:
		var asset: PackedScene = sample["asset"]
		var model := stage.build_exhibit(sample["id"])
		_expect(model != null, "A reference-car exhibit must instantiate its saved model.")
		if model == null:
			continue
		var source := asset.instantiate() as Node3D
		_expect(model.scene_file_path == asset.resource_path and model.has_node(sample["assembly"]),
			"Each reference car must use its own GLB, not a reskinned Cube.")
		_expect(model.transform.is_equal_approx(source.transform)
			and GalleryStage.bounds_of(model).is_equal_approx(GalleryStage.bounds_of(source)),
			"The Gallery must preserve the reference car's authored scale and orientation.")
		_expect(model.find_children("*", "MeshInstance3D", true, false).size() == 16,
			"A reference-car exhibit must retain the complete 16-mesh export.")
		_compare_imported_meshes(model, source)
		source.free()
		model.free()


## The point of the room: what stands on the plinth is the model the match
## builds, settled by the same solver and finished the same way — not a tidier
## one made for a display case.
func _test_gallery_provenance(stage: Node) -> void:
	var car: Node3D = stage.call("build_exhibit", Options.EXHIBIT_CUBE)
	_expect(car is Cube and car.position.is_zero_approx(),
		"The car exhibit must be the imported assembly, brought back to the origin.")
	get_root().add_child(car)
	var settled := State.new()
	settled.advance(GalleryStage.SETTLE_SECONDS, 0.0, 0.0, 0.0)
	var reference := Cube.new()
	get_root().add_child(reference)
	reference.apply_state(settled)
	_expect(car.local_bounds().size.is_equal_approx(reference.local_bounds().size)
		and is_zero_approx(car.brake_level),
		"The exhibited car must be parked at the trial's own ride height.")
	var suspension: Node3D = stage.call("build_exhibit", Options.EXHIBIT_SUSPENSION)
	var shown := suspension.get_node("Strut") as Coilover
	_expect(shown != null and shown.mesh == reference.springs[0].mesh
		and absf(shown.length - reference.springs[0].length) < 0.003
		and GalleryStage.bounds_of(suspension).is_equal_approx(shown.custom_aabb),
		"The coilover exhibit must share the live car's mechanical model, preload and deformed bounds.")
	suspension.free()
	reference.free()
	car.free()

	var plug: Node3D = stage.call("build_exhibit", Options.EXHIBIT_PLUG)
	var world := Landscape.new()
	get_root().add_child(world)
	_compare_prop_import(plug, world.plugs[0], Landscape.PLUG_MODEL, ^"ImportedPlug")
	_expect(GalleryStage.bounds_of(plug).is_equal_approx(
		GalleryStage.bounds_of(world.plugs[0])),
		"The gallery must show the imported pickup at the same scale and anchor as the course.")
	_expect(plug.find_children("*", "Label3D", true, false).size() == 1,
		"The exhibited plug must keep the number that names it.")
	plug.free()

	var pine: Node3D = stage.call("build_exhibit", Options.EXHIBIT_PINE)
	var planted := _pine_poses(world, pine)
	_expect(pine.scene_file_path == Landscape.PINE_MODEL.resource_path
		and (pine.get_node("PineTree") as Node3D).basis.is_equal_approx(planted[3].basis)
		and is_equal_approx(GalleryStage.bounds_of(pine).size.y,
			4.19 * GalleryStage.EXHIBIT_PINE_SCALE),
		"The gallery must show a real mid-sized course pine, not an unscaled source tree.")
	pine.free()
	var checkpoint: Node3D = stage.call("build_exhibit", Options.EXHIBIT_CHECKPOINT)
	_compare_prop_import(checkpoint, world.get_node("Checkpoint1"),
		Landscape.CHECKPOINT_MODEL, ^".")
	_expect(GalleryStage.bounds_of(checkpoint).is_equal_approx(
		GalleryStage.bounds_of(world.get_node("Checkpoint1"))),
		"The displayed checkpoint must retain the course's footing, pole, cloth and label.")
	checkpoint.free()

	# The garage is the one exhibit shown in a state the trail only reaches at
	# the finish, so its wording has to be the finish wording.
	var garage: Node3D = stage.call("build_exhibit", Options.EXHIBIT_GARAGE)
	_compare_prop_import(garage, world.get_node("CopperCreekServiceGarage"),
		Landscape.GARAGE_MODEL, ^"ImportedBodyShop")
	var wording := PackedStringArray()
	for label in garage.find_children("*", "Label3D", true, false):
		wording.append((label as Label3D).text)
	_expect(wording.has("BRAKE TO PARK") and garage.find_children(
		"DeliveredPlug*", "MeshInstance3D", true, false).size() == 5,
		"The garage must be exhibited delivered: five lamps and the finish rule.")
	garage.free()
	world.free()


func _pine_poses(world: Node3D, exhibit: Node3D = null) -> Array[Transform3D]:
	var poses: Array[Transform3D] = world.get("pine_poses")
	var instances := 0
	var source := Landscape.PINE_MODEL.instantiate() as Node3D
	var original_foliage := source.get_node("PineTree/Foliage") as MeshInstance3D
	var original_trunk := source.get_node("PineTree/Trunk") as MeshInstance3D
	for batch in world.get_node("RoadsidePines").get_children():
		var foliage := batch.get_node("Foliage") as MultiMeshInstance3D
		var trunk := batch.get_node("Trunk") as MultiMeshInstance3D
		_expect(foliage.multimesh.mesh == original_foliage.mesh
			and trunk.multimesh.mesh == original_trunk.mesh
			and foliage.material_override == null and trunk.material_override == null,
			"Pine batches must draw the original exported geometry and materials.")
		_expect(foliage.multimesh.instance_count == trunk.multimesh.instance_count
			and foliage.multimesh.instance_count > 0
			and foliage.multimesh.instance_count <= Landscape.PINE_BATCH_SIZE,
			"Each spatial pine batch must pair trunks and foliage without a course-wide bound.")
		instances += foliage.multimesh.instance_count
	_expect(instances == poses.size(),
		"Every logical pine must have exactly one paired rendering instance.")
	if exhibit != null:
		_expect((exhibit.get_node("PineTree/Foliage") as MeshInstance3D).mesh
			== original_foliage.mesh
			and (exhibit.get_node("PineTree/Trunk") as MeshInstance3D).mesh
				== original_trunk.mesh,
			"The pine on the plinth must be the same geometry the instanced forest draws.")
	source.free()
	return poses


func _compare_prop_import(
	exhibit: Node3D, runtime: Node3D, asset: PackedScene, imported_path: NodePath
) -> void:
	var displayed := exhibit.get_node_or_null(imported_path) as Node3D
	var driven := runtime.get_node_or_null(imported_path) as Node3D
	_expect(displayed != null and driven != null,
		"Both course and gallery must retain the imported assembly: " + asset.resource_path)
	if displayed == null or driven == null:
		return
	_expect(displayed.scene_file_path == asset.resource_path
		and driven.scene_file_path == asset.resource_path,
		"Course and gallery must instance the actual generated GLB, not a procedural stand-in.")
	var source := asset.instantiate() as Node3D
	_compare_imported_meshes(displayed, source)
	_compare_imported_meshes(driven, source)
	source.free()


func _compare_imported_meshes(displayed: Node3D, source: Node3D) -> void:
	for part: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var path := source.get_path_to(part)
		var shown := displayed.get_node_or_null(path) as MeshInstance3D
		_expect(shown != null, "An imported model lost its mesh group: " + str(path))
		if shown == null:
			continue
		_expect(shown.mesh == part.mesh and shown.material_override == null,
			"Every imported model must use its exported geometry and materials.")


## The shop sells looks, not advantages, and it repaints the imported car
## rather than a stand-in. Both claims are checked against the model itself.
func _test_store_finishes() -> void:
	var manifest := Game.manifest()
	_expect(manifest.has_store()
		and manifest.store_items == Options.STORE_ITEMS
		and manifest.store_slots == Options.STORE_SLOTS,
		"Cube Trials must offer the shop it declares.")

	# A finish is matched to an exported material by name, so a rename in
	# Blender has to fail here rather than silently stop repainting the car.
	var reference := Cube.new()
	get_root().add_child(reference)
	var body := reference.get_node("Chassis/BrownBodywork") as MeshInstance3D
	var rim := reference.get_node("FrontAxle/FrontRightWheel/AlloyRims") as MeshInstance3D
	for named: Array in [
		[body, Finish.BODY_COAT], [body, Finish.BODY_EDGE],
		[rim, Finish.RIM_FACE], [rim, Finish.RIM_LIP],
	]:
		var owner_mesh: MeshInstance3D = named[0]
		var surface_name: String = named[1]
		var found := false
		for surface in owner_mesh.mesh.get_surface_count():
			var material := owner_mesh.mesh.surface_get_material(surface)
			found = found or (material != null and material.resource_name == surface_name)
		_expect(found, "The export must still batch a '%s' surface to paint." % surface_name)

	# Factory cards quote `cube_finish.gd` for their swatch instead of
	# repeating a hex code, so what it quotes has to be what Blender wrote.
	for quoted: Array in [
		[body, Finish.BODY_COAT, Finish.FACTORY_COAT],
		[rim, Finish.RIM_FACE, Finish.FACTORY_ALLOY],
	]:
		var owner_mesh: MeshInstance3D = quoted[0]
		var surface_name: String = quoted[1]
		var declared: Color = quoted[2]
		for surface in owner_mesh.mesh.get_surface_count():
			var material := owner_mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or material.resource_name != surface_name:
				continue
			_expect(material.albedo_color.to_html(false) == declared.to_html(false),
				"The factory swatch for '%s' says %s but the export is %s."
				% [surface_name, declared.to_html(false),
				material.albedo_color.to_html(false)])

	# Factory finishes use the exported paint/alloys; lamp overrides are independent.
	reference.set_finish(Options.PAINT_FACTORY, Options.RIM_FACTORY)
	_expect(_finish_overrides(reference).is_empty(),
		"The factory look must leave the exported materials untouched.")

	var references := {Profiles.CUBE: reference}
	var stances := {Profiles.CUBE: reference.local_bounds()}
	for vehicle_id: String in [Profiles.SONATA, Profiles.CRV]:
		var car := Cube.new(vehicle_id)
		get_root().add_child(car)
		references[vehicle_id] = car
		stances[vehicle_id] = car.local_bounds()
		var panel := car.chassis.get_node(car.vehicle.body_part) as MeshInstance3D
		var found := false
		for surface in panel.mesh.get_surface_count():
			var material := panel.mesh.surface_get_material(surface) as StandardMaterial3D
			if material.resource_name == Finish.MODERN_BODY_COAT:
				found = true
				_expect(material.albedo_color.to_html(false)
					== Finish.FACTORY_COATS[vehicle_id].to_html(false),
					vehicle_id + ": the factory card must quote this car's exported paint.")
		_expect(found, vehicle_id + ": the export must retain its named body-paint material.")
	var every_id := PackedStringArray()
	for item: Dictionary in Options.STORE_ITEMS:
		var id := str(item["id"])
		every_id.append(id)
		var is_wheel := str(item["kind"]) == Options.RIM_KIND
		var vehicle_id := Profiles.CUBE if is_wheel \
			else str(Options.PAINT_KINDS.find_key(str(item["kind"])))
		var car: Cube = references[vehicle_id]
		car.set_finish("" if is_wheel else id, id if is_wheel else "")
		var painted := _finish_overrides(car)
		# One bodywork batch, but four wheels: a wheel finish is bought once
		# and worn on every corner.
		var surfaces := 8 if is_wheel else (2 if vehicle_id == Profiles.CUBE else 1)
		if Finish.repaints(id):
			_expect(painted.size() == surfaces and painted.has(Finish.swatch(id)),
				"'%s' must restate its %d authored paint surfaces on the correct car."
				% [id, surfaces])
		else:
			_expect(painted.is_empty(),
				"Free look '%s' must not override an exported material." % id)
		_expect(car.local_bounds().size.is_equal_approx((stances[vehicle_id] as AABB).size),
			"'%s' must not change the shape of the car." % id)

	# Every colour sold has to exist, and every colour that exists has to be
	# sold — an unreachable paint is dead weight in the export.
	for id: String in Finish.PAINTS.keys() + Finish.RIMS.keys():
		_expect(every_id.has(id), "cube_finish.gd mixes '%s', which nothing sells." % id)
	reference.set_finish()
	_expect(_finish_overrides(reference).is_empty(),
		"Stripping a car back to factory must clear every paint and alloy override.")
	var reversed := ArrayMesh.new()
	for surface in range(body.mesh.get_surface_count() - 1, -1, -1):
		reversed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			body.mesh.surface_get_arrays(surface))
		reversed.surface_set_material(reversed.get_surface_count() - 1,
			body.mesh.surface_get_material(surface))
	var reordered := MeshInstance3D.new()
	reordered.mesh = reversed
	Finish.dress_body(reordered, "cube_paint_signal")
	for surface in reversed.get_surface_count():
		var label := reversed.surface_get_material(surface).resource_name
		var expected := Finish.swatch("cube_paint_signal")
		if label == Finish.BODY_EDGE:
			expected = expected.darkened(Finish.EDGE_DARKEN)
		_expect((reordered.get_active_material(surface) as StandardMaterial3D)
			.albedo_color.is_equal_approx(expected),
			"Cached finishes must follow material identity even when damage exports reorder surfaces.")
	reordered.free()
	for car: Cube in references.values():
		car.free()

	# The wheel a rim card shows is the imported alloy, wearing that finish.
	var wheel := Cube.wheel_display(Options.RIM_BLACK)
	var alloys := wheel.get_node("AlloyRims") as MeshInstance3D
	_expect(alloys != null and _surface_colors(alloys).has(
		Finish.swatch(Options.RIM_BLACK)),
		"A rim card must show the imported alloy in the finish it sells.")
	wheel.free()


func _finish_overrides(car: Cube) -> Array[Color]:
	var colors := _surface_colors(car.chassis.get_node(car.vehicle.body_part) as MeshInstance3D)
	for wheel in car.wheels:
		colors.append_array(_surface_colors(wheel.get_node("AlloyRims") as MeshInstance3D))
	return colors


func _surface_colors(instance: MeshInstance3D) -> Array[Color]:
	var colors: Array[Color] = []
	for surface in instance.mesh.get_surface_count():
		var material := instance.get_surface_override_material(surface)
		if material is StandardMaterial3D:
			colors.append((material as StandardMaterial3D).albedo_color)
	return colors


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
