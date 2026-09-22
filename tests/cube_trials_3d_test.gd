extends SceneTree

## Geometry and animation contracts stay verifiable without a graphics driver.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
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

var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_imported_asset()
	_test_vehicle()
	_test_stock_stance()
	_test_brake_animation()
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
		Course.ground_height(state.position.x))).y
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
	for spring in car.springs:
		_expect(spring.scale.y < 0.25,
			"Parked suspension struts must remain short and tucked into the wheel wells.")
	car.free()


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
		and lenses.get_surface_override_material(surface) == null,
		"Daylight and replay must turn off the beams and restore the exported bulb finish.")
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
		Course.ground_height(Course.FINISH_X)))
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
	var flag_materials: Array[StandardMaterial3D] = world.get("_flag_materials")
	var original_flag_color := flag_materials[0].albedo_color
	_expect(flag_materials.size() == 2 and flag_materials[0] != flag_materials[1],
		"Each imported checkpoint must own its live field material.")
	for index in world.plugs.size():
		var imported := world.plugs[index].get_node("ImportedPlug") as Node3D
		var bounds := imported.transform * GalleryStage.bounds_of(imported)
		_expect(is_equal_approx(bounds.size.y, Landscape.PLUG_HEIGHT)
			and absf(bounds.get_center().y) < 0.0001
			and world.plugs[index].position.is_equal_approx(
				Art.world_point(Course.plug_position(index))),
			"The imported plug must be enlarged and centered on the existing pickup anchor.")
		_expect(world.plugs[index].get_node("PickupRing") is MeshInstance3D
			and (world.plugs[index].get_node("PickupNumber") as Label3D).text == str(index + 1),
			"Imported pickups must retain their gold ring and distinct readable numbers.")
	var trees := _pine_poses(world)
	_expect(trees.size() == 20, "The imported forest must retain the authored planting count.")
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
	var ground := Art.world_point(Vector2(Course.FINISH_X, Course.ground_height(Course.FINISH_X)))
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
	world.present(state, 2.5, false, true, false)
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
		and world.plugs[1].rotation == Vector3.ZERO
		and world.plugs[1].position.is_equal_approx(Art.world_point(Course.plug_position(1)))
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
	for exhibit: Dictionary in Options.GALLERY_EXHIBITS:
		var id := str(exhibit["id"])
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
	_expect(stage.call("build_exhibit", "not_an_exhibit") == null,
		"The gallery stage must not invent a model for an id it does not know.")
	_test_gallery_provenance(stage)
	stage.free()


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
	for part: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var path := source.get_path_to(part)
		var shown := displayed.get_node_or_null(path) as MeshInstance3D
		var live := driven.get_node_or_null(path) as MeshInstance3D
		_expect(shown != null and live != null,
			"An imported prop lost its mesh group: " + str(path))
		if shown == null or live == null:
			continue
		_expect(shown.mesh == part.mesh and live.mesh == part.mesh
			and shown.material_override == null and live.material_override == null,
			"Every prop must use the exported geometry and materials on both surfaces.")
	source.free()


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

	# The two free cards quote `cube_finish.gd` for their swatch instead of
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

	# The free looks are the exported materials themselves, not a copy: a
	# factory car must carry no override at all.
	reference.set_finish(Options.PAINT_FACTORY, Options.RIM_FACTORY)
	_expect(_overrides(reference).is_empty(),
		"The factory look must leave the exported materials untouched.")

	var stance := reference.local_bounds()
	var every_id := PackedStringArray()
	for item: Dictionary in Options.STORE_ITEMS:
		var id := str(item["id"])
		every_id.append(id)
		var paint := id if str(item["kind"]) == Options.PAINT_KIND else ""
		var wheels := id if str(item["kind"]) == Options.RIM_KIND else ""
		reference.set_finish(paint, wheels)
		var painted := _overrides(reference)
		# One bodywork batch, but four wheels: a wheel finish is bought once
		# and worn on every corner.
		var wearers := 4 if str(item["kind"]) == Options.RIM_KIND else 1
		if Finish.repaints(id):
			_expect(painted.size() == 2 * wearers and painted.has(Finish.swatch(id)),
				"'%s' must restate two surfaces on each of its %d wearers."
				% [id, wearers])
		else:
			_expect(painted.is_empty(),
				"Free look '%s' must not override an exported material." % id)
		_expect(reference.local_bounds().size.is_equal_approx(stance.size),
			"'%s' must not change the shape of the car." % id)

	# Every colour sold has to exist, and every colour that exists has to be
	# sold — an unreachable paint is dead weight in the export.
	for id: String in Finish.PAINTS.keys() + Finish.RIMS.keys():
		_expect(every_id.has(id), "cube_finish.gd mixes '%s', which nothing sells." % id)
	reference.set_finish()
	_expect(_overrides(reference).is_empty(),
		"Stripping a car back to factory must clear every override.")
	reference.free()

	# The wheel a rim card shows is the imported alloy, wearing that finish.
	var wheel := Cube.wheel_display(Options.RIM_BLACK)
	var alloys := wheel.get_node("AlloyRims") as MeshInstance3D
	_expect(alloys != null and _surface_colors(alloys).has(
		Finish.swatch(Options.RIM_BLACK)),
		"A rim card must show the imported alloy in the finish it sells.")
	wheel.free()


## Every albedo the car is currently overriding, so a test can ask what a
## finish changed without knowing which surface index it landed on.
func _overrides(car: Cube) -> Array[Color]:
	var colors: Array[Color] = []
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_surface_override_material(surface)
			if material is StandardMaterial3D:
				colors.append((material as StandardMaterial3D).albedo_color)
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
