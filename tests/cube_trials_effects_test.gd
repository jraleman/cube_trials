extends SceneTree

## Headless lifecycle contracts plus optional real Compatibility pixel and draw-budget checks.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const TireParticles = preload("res://games/cube_trials/world/tire_particles.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const View = preload("res://games/cube_trials/course_view.gd")

var _failures := PackedStringArray()
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cube-capture-dir="):
			_capture_dir = argument.trim_prefix("--cube-capture-dir=")
	if not _capture_dir.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
		if error != OK:
			printerr("Could not create effects capture directory: ", error_string(error))
			quit(1)
			return
	for level: String in Course.ROUTES:
		for vehicle: String in Profiles.DEFINITIONS:
			_test_tires(vehicle, level)
	for vehicle: String in Profiles.DEFINITIONS:
		_test_trails(vehicle)
	await _test_view_lifecycle()
	if DisplayServer.get_name() != "headless":
		await _test_rendered_effects()
		await _render()
	if _failures.is_empty():
		print("Cube Trials snow, dirt and airborne light-trail tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_tires(vehicle: String, level: String) -> void:
	var state := State.new(vehicle, level)
	state.advance(0.5, 0, 0, 0)
	var particles := TireParticles.new(state.course.scenery)
	get_root().add_child(particles)
	var dirt := particles.get_node_or_null("DirtClods") as MultiMeshInstance3D
	_expect((dirt != null) == (level == Course.COPPER),
		"Only Level 1 must add solid dirt clods; sand and snow keep their own soft palettes.")
	_expect(particles.multimesh.instance_count == TireParticles.DUST_COUNT
		and particles.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"Tire puffs must share a fixed-size, shadow-free draw batch.")
	var finish := particles.material_override as StandardMaterial3D
	_expect(finish.albedo_texture is GradientTexture2D and finish.billboard_keep_scale
		and not finish.no_depth_test, "Tire particles must have soft, scaled, depth-tested edges.")
	particles.present(state, 1.0 / 60.0, true)
	_expect(particles.multimesh.visible_instance_count == 0, "Parked tires must not make dust.")
	state.velocity.x = 300.0
	particles.present(state, 0.0, true)
	_expect(particles.multimesh.visible_instance_count == 0,
		"Zero-delta layout and pause updates must not spawn tire effects.")
	particles.present(state, 1.0 / 60.0, true)
	_expect(particles.multimesh.visible_instance_count == 4,
		vehicle + " / " + level + ": each grounded tire must emit at its actual contact.")
	var origins: PackedVector3Array = particles.get("_origins")
	var velocities: PackedVector3Array = particles.get("_velocities")
	var colors: PackedColorArray = particles.get("_colors")
	_expect(origins[0].x < origins[2].x and origins[0].z < 0.0 and origins[1].z > 0.0,
		"Front/rear axles and both sides must have distinct contact emitters.")
	_expect(velocities[0].x < 0.0 and velocities[0].y > 0.0,
		"Driving forward must kick particles upward and back, not into the road.")
	if level == Course.ALPINE:
		_expect(colors[0].b > colors[0].r and colors[0].r > 0.8,
			"Alpine tire particles must be pale powder, not brown dust.")
	if dirt != null:
		_expect(dirt.multimesh.visible_instance_count > 0
			and dirt.multimesh.instance_count == TireParticles.DIRT_COUNT,
			"Level 1 must throw bounded, small solid clods as well as soft dust.")
		for frame in 24:
			particles.present(state, 1.0 / 60.0, true)
		var clod_origins: PackedVector3Array = particles.get("_origins")
		var clod_ages: PackedFloat32Array = particles.get("_ages")
		var left := false
		var right := false
		for index in range(TireParticles.DUST_COUNT, clod_ages.size()):
			if clod_ages[index] >= 0.0:
				left = left or clod_origins[index].z < 0.0
				right = right or clod_origins[index].z > 0.0
		_expect(left and right, "Dirt clods must alternate across both sides, not favor one tire track.")
	var first_origin := origins[0]
	state.position.x += 10.0
	state.contacts = 0
	state.started = true
	state.set("_air_time", 0.1)
	var serial := int(particles.get("_serial"))
	particles.present(state, 0.05, true)
	_expect((particles.get("_origins") as PackedVector3Array)[0] == first_origin
		and int(particles.get("_serial")) == serial and particles.multimesh.visible_instance_count > 0,
		"Takeoff must stop emission while existing puffs stay at their world-space launch points.")
	var ages: PackedFloat32Array = (particles.get("_ages") as PackedFloat32Array).duplicate()
	paused = true
	particles.present(state, 0.2, true)
	paused = false
	_expect(ages == particles.get("_ages"), "Pause must freeze existing tire particles.")
	particles.present(state, TireParticles.DUST_LIFETIME + 0.1, true)
	_expect(particles.multimesh.visible_instance_count == 0,
		"Airborne dust must fade out instead of following the car indefinitely.")
	particles.present(state, 0.0, false)
	state = State.new(vehicle, level)
	state.advance(0.5, 0, 0, 0)
	state.velocity.x = -300.0
	particles.present(state, 1.0 / 60.0, true)
	_expect((particles.get("_velocities") as PackedVector3Array)[0].x > 0.0,
		"Reverse must kick dirt in the opposite direction.")
	particles.present(state, 0.0, false)
	_expect(particles.multimesh.visible_instance_count == 0
		and (dirt == null or dirt.multimesh.visible_instance_count == 0),
		"Disabling effects must immediately remove dust and solid clods, even without a frame step.")
	particles.present(state, 1.0 / 60.0, true)
	state.recover()
	particles.present(state, 0.0, true)
	_expect(particles.multimesh.visible_instance_count == 0, "Recovery must clear the old tire wake.")
	for terminal: String in ["crash_wait", "finished", "failed"]:
		state = State.new(vehicle, level)
		state.advance(0.5, 0, 0, 0)
		state.velocity.x = 300.0
		particles.present(state, 1.0 / 60.0, true)
		state.set(terminal, 0.5 if terminal == "crash_wait" else true)
		particles.present(state, 0.0, true)
		_expect(particles.multimesh.visible_instance_count == 0,
			"Crash and results must remove existing tire effects: " + terminal)
	_test_landing_puffs(particles, vehicle, level)
	particles.free()


func _test_landing_puffs(particles: TireParticles, vehicle: String, level: String) -> void:
	var state := State.new(vehicle, level)
	state.advance(0.5, 0, 0, 0)
	var flew := false
	var landed := false
	for frame in 150:
		state.advance(1.0 / 60.0, 0, 0, 0, frame == 0)
		particles.present(state, 1.0 / 60.0, true)
		if state.is_airborne():
			flew = true
		elif flew and state.contacts > 0:
			landed = true
			_expect(particles.multimesh.visible_instance_count >= 6,
				vehicle + " / " + level + ": a real landing must lift a brief surface-colored puff.")
			break
	_expect(landed, "The landing-puff fixture must complete an input-only jump.")
	for frame in 90:
		state.advance(1.0 / 60.0, 0, 0, 0)
		particles.present(state, 1.0 / 60.0, true)
	_expect(particles.multimesh.visible_instance_count == 0,
		"Settled suspension must not keep retriggering landing puffs.")


func _test_trails(vehicle: String) -> void:
	var car := Cube.new(vehicle)
	var other := Cube.new(vehicle)
	get_root().add_child(car)
	get_root().add_child(other)
	var trails := car.get_node("AirborneHazardTrails") as MultiMeshInstance3D
	_expect(trails.multimesh.instance_count == Cube.TRAIL_SAMPLES * 4 and trails.top_level
		and trails.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"Four lamp trails must use one bounded world-space batch, not extra lights or shadow passes.")
	var finish := trails.multimesh.mesh.material as StandardMaterial3D
	_expect(finish.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and not finish.no_depth_test,
		"Trails must glow in Compatibility while remaining occluded by the car and terrain.")
	for stage in State.DAMAGE_NAMES.size():
		for fps: int in [30, 60, 144]:
			var state := _jumping_state(vehicle)
			state.damage_stage = stage
			car.reset_motion()
			for frame in roundi(fps * 0.3):
				state.advance(1.0 / fps, 1, 0, 0.6)
				car.apply_state(state, false, 1.0 / fps)
			var count := trails.multimesh.visible_instance_count
			_expect(state.is_airborne() and count >= 132 and count <= 148,
				"%s damage %d / %d FPS: flight must leave a frame-rate-independent trail (%d)." % [
					vehicle, stage, fps, count,
				])
			var anchors: PackedVector3Array = car.get("_trail_anchors")
			var points: PackedVector3Array = car.get("_trail_points")
			var ages: PackedFloat32Array = car.get("_trail_ages")
			var newest := (int(car.get("_trail_cursor")) + Cube.TRAIL_SAMPLES - 1) % Cube.TRAIL_SAMPLES
			for lamp in 4:
				_expect(points[newest * 4 + lamp].distance_to(car.chassis.global_transform * anchors[lamp]) < 0.35,
					"Trail heads must follow each actual damaged lamp through chassis rotation.")
			var saved_points := points.duplicate()
			var saved_ages := ages.duplicate()
			car.apply_state(state, false, 0.0)
			paused = true
			car.apply_state(state, false, 0.2)
			paused = false
			_expect(saved_points == car.get("_trail_points") and saved_ages == car.get("_trail_ages"),
				"Layout changes and pause must not advance, duplicate or move light samples.")
			var cursor := int(car.get("_trail_cursor"))
			state.hazard_time = 0.6
			car.apply_state(state, false, 1.0 / fps)
			_expect(cursor == int(car.get("_trail_cursor")) and trails.visible,
				"The dark hazard phase must stop emission while the earlier light fades.")
			state.hazards_on = false
			car.apply_state(state, false, Cube.TRAIL_DURATION + 0.01)
			_expect(not trails.visible and trails.multimesh.visible_instance_count == 0,
				"Switching off hazards must leave no trail after its short fade.")
	_expect((other.get_node("AirborneHazardTrails") as MultiMeshInstance3D).multimesh.visible_instance_count == 0,
		"One car's trails must never affect another car or a studio preview.")
	for disabled in 2:
		var state := _jumping_state(vehicle)
		state.advance(0.2, 1, 0, 0)
		car.apply_state(state, false, 0.2)
		_expect(trails.visible, "The accessibility fixture must first have a visible airborne trail.")
		car.apply_state(state, false, 0.0, disabled == 0, disabled == 0)
		_expect(not trails.visible and car.hazard_level == 1.0,
			"Either accessibility setting must immediately clear trails but preserve steady hazard signals.")
	var state := _jumping_state(vehicle)
	state.advance(0.2, 1, 0, 0)
	car.apply_state(state, false, 0.2)
	state.contacts = 2
	var cursor := int(car.get("_trail_cursor"))
	car.apply_state(state, false, 0.05)
	_expect(cursor == int(car.get("_trail_cursor")), "Grounded hazards must not create light trails.")
	car.apply_state(state, false, Cube.TRAIL_DURATION)
	_expect(not trails.visible, "Landing must let the final trail fade away.")
	for reset_kind: String in ["recover", "teleport", "crash", "finish", "replay"]:
		state = _jumping_state(vehicle)
		state.advance(0.2, 1, 0, 0)
		car.apply_state(state, false, 0.2)
		match reset_kind:
			"recover":
				state.recover()
			"teleport":
				state.position.x += 1000.0
			"crash":
				state.crash_wait = 0.5
			"finish":
				state.finished = true
			"replay":
				state = State.new(vehicle)
		car.apply_state(state)
		_expect(not trails.visible, "Old light history must clear on " + reset_kind + ".")
	car.free()
	other.free()


func _jumping_state(vehicle: String) -> State:
	var state := State.new(vehicle)
	state.advance(0.5, 0, 0, 0)
	state.velocity.x = 400.0
	state.advance(1.0 / 60.0, 1, 0, 0, true)
	state.toggle_hazards()
	_expect(state.is_airborne() and state.hazards_on, "The trail fixture must launch a real jump.")
	return state


func _test_view_lifecycle() -> void:
	var view := View.new()
	view.size = Vector2(1280, 720)
	get_root().add_child(view)
	for level: String in [Course.COPPER, Course.ALPINE]:
		var state := State.new(Profiles.CUBE, level)
		view.configure(state)
		if DisplayServer.get_name() != "headless":
			await _render()
		for frame in 120:
			state.advance(1.0 / 60.0, 1, 0, 0)
			view.present(1.0 / 60.0)
		var dust := view.world.get_node("OptionalTireDust") as TireParticles
		_expect(dust.multimesh.visible_instance_count > 0, "Driving must populate the selected route's tire wake.")
		view.set_reduced_motion(true)
		_expect(dust.multimesh.visible_instance_count == 0,
			"Live Reduced motion must clear the tire wake through the actual course view.")
		view.set_reduced_motion(false)
		view.present(1.0 / 60.0)
		view.set_intense_effects(false)
		_expect(dust.multimesh.visible_instance_count == 0,
			"Live Intense effects must clear every tire particle through the actual course view.")
		if level == Course.ALPINE:
			var snow := view.world.get_node("OptionalSnowfall") as MultiMeshInstance3D
			_expect(snow.multimesh.visible_instance_count == 0, "Either setting must clear existing snowfall.")
			view.set_intense_effects(true)
			_expect(snow.multimesh.visible_instance_count == Landscape.SNOWFLAKE_COUNT,
				"Re-enabling effects must restore the bounded Alpine snowfall.")
			var finish := snow.material_override as StandardMaterial3D
			_expect(finish.billboard_keep_scale and finish.albedo_texture is GradientTexture2D
				and not finish.no_depth_test, "Snow must retain soft, varied sizes and real depth occlusion.")
		view.set_intense_effects(true)
		view.configure(State.new(Profiles.CRV, level))
		_expect(dust.multimesh.visible_instance_count == 0,
			"A hot-seat turn must not inherit the previous car's dirt or powder.")
		view.state.finished = true
		view.present(0.0)
		if level == Course.ALPINE:
			_expect((view.world.get_node("OptionalSnowfall") as MultiMeshInstance3D).multimesh.visible_instance_count == 0,
				"Results must hide moving snowfall.")
	view.configure(State.new())
	_expect(not view.world.has_node("OptionalSnowfall"), "Snowfall must not leak into Level 1.")
	if DisplayServer.get_name() != "headless":
		await _render()
	view.free()
	await process_frame


func _test_rendered_effects() -> void:
	var view := View.new()
	get_root().add_child(view)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
		get_root().size = dimensions
		await process_frame
		view.size = get_root().get_visible_rect().size
		view.call("_resize_world")
		for level: String in [Course.COPPER, Course.ALPINE]:
			var state := State.new(Profiles.CUBE, level)
			view.configure(state)
			for frame in 150:
				state.advance(1.0 / 60.0, 1, 0, 0)
				view.present(1.0 / 60.0)
			for mode in [View.CameraMode.SIDE, View.CameraMode.CHASE, View.CameraMode.COCKPIT]:
				view.set_camera_mode(mode)
				var effect := view.world.get_node("OptionalSnowfall" if level == Course.ALPINE
					else "OptionalTireDust") as MultiMeshInstance3D
				if level == Course.COPPER and mode == View.CameraMode.COCKPIT:
					continue
				var label := "%s-%s-%d" % [level, view.camera_name(), dimensions.x]
				effect.show()
				await _render()
				var on := view.world_viewport.get_texture().get_image()
				_capture(on, label)
				effect.hide()
				await _render()
				var off := view.world_viewport.get_texture().get_image()
				var pixels := _changed_pixels(on, off)
				var minimum := 12 if dimensions.x < 600 else 40
				_expect(pixels >= minimum,
					"%s: the requested effect must change visible pixels (%d, need %d)." % [label, pixels, minimum])
				effect.show()
				await _render()
				_check_budget(view, label)
				print("%s: %d effect pixels." % [label, pixels])
		for vehicle: String in Profiles.DEFINITIONS:
			var state := _jumping_state(vehicle)
			view.configure(state)
			for frame in 18:
				state.advance(1.0 / 60.0, 1, 0, 0.6)
				view.present(1.0 / 60.0)
			for mode in [View.CameraMode.SIDE, View.CameraMode.CHASE]:
				view.set_camera_mode(mode)
				var trails := view.world.car.get_node("AirborneHazardTrails") as MultiMeshInstance3D
				var label := "%s-trails-%s-%d" % [vehicle, view.camera_name(), dimensions.x]
				trails.show()
				await _render()
				var on := view.world_viewport.get_texture().get_image()
				_capture(on, label)
				trails.hide()
				await _render()
				var off := view.world_viewport.get_texture().get_image()
				var scale := Vector2(view.world_viewport.size) / view.size
				var bounds := view.car_screen_bounds()
				var car_rect := Rect2(bounds.position * scale, bounds.size * scale)
				var pixels := _changed_pixels(on, off, car_rect)
				var minimum := 6 if dimensions.x < 600 else 20
				_expect(pixels >= minimum,
					"%s: trails must visibly extend beyond the car, not just brighten its lamps (%d)." % [label, pixels])
				trails.show()
				await _render()
				_check_budget(view, label)
				print("%s: %d trail pixels outside the car." % [label, pixels])
	view.free()
	await process_frame


func _changed_pixels(on: Image, off: Image, excluded := Rect2()) -> int:
	var count := 0
	for y in on.get_height():
		for x in on.get_width():
			if excluded.has_point(Vector2(x, y)):
				continue
			var a := on.get_pixel(x, y)
			var b := off.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.035:
				count += 1
	return count


func _check_budget(view: View, label: String) -> void:
	var viewport := view.world_viewport
	var draws := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
		Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var triangles := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
		Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	_expect(draws <= 200 and triangles < 120000,
		"%s: effects must retain the 200-draw/120k-triangle budget (%d / %d)." % [label, draws, triangles])


func _render() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw


func _capture(image: Image, title: String) -> void:
	if not _capture_dir.is_empty():
		var error := image.save_png(_capture_dir.path_join(title + ".png"))
		_expect(error == OK, "Could not save effects capture: " + title)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
