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

var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_imported_asset()
	_test_vehicle()
	_test_stock_stance()
	_test_brake_animation()
	_test_terrain_and_accessibility()
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
	var exhibited: ArrayMesh = (plug.get_node("Plug") as MeshInstance3D).mesh
	var world := Landscape.new()
	get_root().add_child(world)
	var driven: ArrayMesh = (world.plugs[0].get_child(0) as MeshInstance3D).mesh
	_expect(exhibited.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		== driven.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
		"The exhibited spark plug must be the very mesh the trail hands out.")
	_expect(plug.find_children("*", "Label3D", true, false).size() == 1,
		"The exhibited plug must keep the number that names it.")
	world.free()
	plug.free()

	# The garage is the one exhibit shown in a state the trail only reaches at
	# the finish, so its wording has to be the finish wording.
	var garage: Node3D = stage.call("build_exhibit", Options.EXHIBIT_GARAGE)
	var wording := PackedStringArray()
	for label in garage.find_children("*", "Label3D", true, false):
		wording.append((label as Label3D).text)
	_expect(wording.has("BRAKE TO PARK") and garage.find_children(
		"DeliveredPlug*", "MeshInstance3D", true, false).size() == 5,
		"The garage must be exhibited delivered: five lamps and the finish rule.")
	garage.free()


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
