extends SceneTree

## Lamp isolation and accessibility; a graphics run also measures actual driving-view pixels.

const State = preload("res://games/cube_trials/trial_state.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Course = preload("res://games/cube_trials/course.gd")
const View = preload("res://games/cube_trials/course_view.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")

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
			printerr("Could not create light capture directory: ", error_string(error))
			quit(1)
			return
	for vehicle_id: String in Profiles.DEFINITIONS:
		await _test_materials(vehicle_id)
	if DisplayServer.get_name() != "headless":
		await _test_rendered_lamps()
	if _failures.is_empty():
		print("Cube Trials lamp and hazard visibility tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_materials(vehicle_id: String) -> void:
	var car := Cube.new(vehicle_id)
	var other := Cube.new(vehicle_id)
	get_root().add_child(car)
	get_root().add_child(other)
	var state := State.new(vehicle_id)
	state.advance(0.5, 0.0, 0.0, 0.0)
	var glows := car.get_node("Chassis/LampGlows") as MultiMeshInstance3D
	_expect(glows.multimesh.instance_count == 6
		and glows.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"Small head, brake and indicator glows must share one shadow-free draw batch.")
	for stage in State.DAMAGE_NAMES.size():
		state.damage_stage = stage
		state.hazards_on = false
		car.apply_state(state, false)
		var front := car.chassis.get_node("HeadlightsAndIndicators") as MeshInstance3D
		var head := int(car.get("_headlight_surface"))
		var indicator := int(car.get("_hazard_surface"))
		var original := front.mesh.surface_get_material(indicator) as StandardMaterial3D
		var original_color := original.albedo_color
		var original_energy := original.emission_energy_multiplier
		var bulb := front.get_active_material(head) as StandardMaterial3D
		var amber := front.get_active_material(indicator) as StandardMaterial3D
		_expect(is_equal_approx(bulb.emission_energy_multiplier, Cube.RUNNING_EMISSION)
			and amber.emission_energy_multiplier == 0.0,
			"%s stage %d: daytime running bulbs must not turn into stuck hazard lights." % [vehicle_id, stage])
		var bounds := car.local_bounds()
		car.apply_state(state, true, 0.0, false, true, 1.0)
		_expect(bulb.emission_energy_multiplier == Cube.HEADLIGHT_EMISSION
			and car.headlights[0].light_energy == 4.0 and car.headlights[0].spot_range == 16.0,
			"%s stage %d: headlights must illuminate both the optics and a longer road beam." % [vehicle_id, stage])
		if vehicle_id != Profiles.CUBE:
			var projector := front.get_active_material(int(car.get("_projector_surface"))) as StandardMaterial3D
			_expect(projector.emission_energy_multiplier == Cube.HEADLIGHT_EMISSION
				and projector.albedo_color == Cube.Art.CREAM,
				"The Sonata and CR-V must light the actual projectors, not only their thin LED trim.")
		for surface in (car.chassis.get_node("RearBrakeLights") as MeshInstance3D).mesh.get_surface_count():
			var rear := (car.chassis.get_node("RearBrakeLights") as MeshInstance3D) \
				.get_active_material(surface) as StandardMaterial3D
			_expect(rear.emission_energy_multiplier == Cube.BRAKE_EMISSION,
				"Every rear lamp surface must retain strong red braking through damage swaps.")
		state.hazards_on = true
		state.hazard_time = 0.1
		car.apply_state(state, false)
		_expect(car.hazard_level == 1.0 and amber.emission_energy_multiplier == Cube.HAZARD_EMISSION
			and car.brake_lights[0].visible and glows.visible,
			"%s stage %d: both front and rear hazards must illuminate on the same phase." % [vehicle_id, stage])
		state.hazard_time = 0.6
		car.apply_state(state, false)
		_expect(car.hazard_level == 0.0 and amber.emission_energy_multiplier == 0.0
			and not car.brake_lights[0].visible,
			"Hazards must have a genuine off phase, not a continuously lit material.")
		car.apply_state(state, true)
		_expect(car.brake_level == 1.0 and car.brake_lights[0].visible,
			"An off-phase hazard must not black out a driver's red brake signal.")
		for reduced: bool in [false, true]:
			car.apply_state(state, false, 0.0, reduced, not reduced, 1.0)
			if reduced:
				_expect(car.hazard_level == 1.0 and not glows.visible
					and not car.brake_lights[0].visible and car.headlights[0].visible,
					"Reduced motion must replace flashing with steady lamps and preserve essential beams.")
		car.apply_state(state, false, 0.0, false, false)
		_expect(car.hazard_level == 1.0 and not glows.visible,
			"Disabling intense effects must also remove flashing and decorative halos.")
		_expect(car.local_bounds().is_equal_approx(bounds)
			and original.albedo_color == original_color
			and original.emission_energy_multiplier == original_energy,
			"Lamp changes must not enlarge physical car bounds or mutate imported material resources.")
		var other_front := other.chassis.get_node("HeadlightsAndIndicators") as MeshInstance3D
		var other_amber := other_front.get_active_material(int(other.get("_hazard_surface"))) as StandardMaterial3D
		_expect(other_amber != amber and other_amber.emission_energy_multiplier == 0.0
			and other.hazard_level == 0.0 and not other.headlights[0].visible,
			"One car's hazards, headlights and damage must never affect another car or preview.")
	state.hazards_on = false
	car.apply_state(state)
	_expect(car.hazard_level == 0.0 and not car.headlights[0].visible and car.brake_level == 0.0,
		"Replay must clear hazard and brake presentation while restoring daylight.")
	if DisplayServer.get_name() != "headless":
		await _render()
	car.free()
	other.free()


func _test_rendered_lamps() -> void:
	var view := View.new()
	get_root().add_child(view)
	for level_id: String in Course.ROUTES:
		for vehicle_id: String in Profiles.DEFINITIONS:
			var state := State.new(vehicle_id, level_id)
			state.advance(0.5, 0.0, 0.0, 0.0)
			view.configure(state)
			for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
				await _resize(view, dimensions)
				for mode in [View.CameraMode.SIDE, View.CameraMode.CHASE]:
					view.set_camera_mode(mode)
					var tag := "%s-%s-%s-%d" % [level_id, vehicle_id, view.camera_name(), dimensions.x]
					_present(view, false, 0.0, false, false)
					await _render()
					var off := view.world_viewport.get_texture().get_image()
					_present(view, false, 0.0, true, false)
					await _render()
					var braking := view.world_viewport.get_texture().get_image()
					var red := _colored_gain(braking, off, _car_rect(view), false)
					var minimum := 4 if dimensions.x < 600 else 12
					_expect(red >= minimum,
						"%s: brakes must brighten at least %d red car pixels (%d)." % [tag, minimum, red])
					_present(view, true, 0.1, false, false)
					await _render()
					var on := view.world_viewport.get_texture().get_image()
					if level_id == Course.COPPER and mode == View.CameraMode.SIDE:
						await _capture(view, tag + "-hazards")
					_present(view, true, 0.6, false, false)
					await _render()
					var dark := view.world_viewport.get_texture().get_image()
					var changed := _colored_gain(on, dark, _car_rect(view), mode == View.CameraMode.SIDE)
					_expect(changed >= minimum,
						"%s: the hazard blink must visibly change at least %d signal pixels (%d)." % [tag, minimum, changed])
					_present(view, true, 0.1, true, true)
					await _render()
					var viewport := view.world_viewport
					var draws := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
						Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
					var triangles := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
						Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
					_expect(draws <= 200 and triangles < 120000,
						"%s: active lights must retain the 200-draw/120k-triangle budget (%d / %d)." % [tag, draws, triangles])
					if level_id == Course.COPPER and dimensions.x == 1280:
						await _capture(view, tag + "-night")
					if mode == View.CameraMode.SIDE:
						await _compare_old_headlights(view, tag)
					print("%s lamps: %d brake / %d hazard pixels; %d draws." % [tag, red, changed, draws])
			if level_id == Course.COPPER:
				await _test_damaged_signals(view, state)
	await _render()
	view.free()
	await process_frame


func _present(view: View, hazards: bool, phase: float, braking: bool, night: bool) -> void:
	view.state.hazards_on = hazards
	view.state.hazard_time = phase
	view.braking = braking
	view.daylight_time = (0.75 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS if night else 0.0
	view.present(0.0)


func _compare_old_headlights(view: View, tag: String) -> void:
	_present(view, false, 0.0, false, true)
	await _render()
	var improved := view.world_viewport.get_texture().get_image()
	var car := view.world.car
	(car.get("_headlight_material") as StandardMaterial3D).emission_energy_multiplier = 2.0
	var projector := car.get("_projector_material") as StandardMaterial3D
	if projector != null:
		projector.emission_energy_multiplier = 0.0
		projector.albedo_color = car.get("_projector_color")
	for light in car.headlights:
		light.light_energy = 2.0
		light.spot_range = 12.0
		light.spot_angle = 33.0
	(car.get_node("Chassis/LampGlows") as MultiMeshInstance3D).hide()
	await _render()
	var legacy := view.world_viewport.get_texture().get_image()
	var brighter := 0
	for y in range(0, improved.get_height(), 2):
		for x in range(0, improved.get_width(), 2):
			if improved.get_pixel(x, y).get_luminance() > legacy.get_pixel(x, y).get_luminance() + 0.06:
				brighter += 1
	_expect(brighter >= 20,
		"%s: stronger headlights must improve actual optics/road pixels over the old settings (%d)." % [tag, brighter])
	for light in car.headlights:
		light.spot_range = 16.0
		light.spot_angle = 36.0
	view.present(0.0)


func _test_damaged_signals(view: View, state: State) -> void:
	await _resize(view, Vector2i(1280, 720))
	for stage in State.DAMAGE_NAMES.size():
		state.damage_stage = stage
		for mode in [View.CameraMode.SIDE, View.CameraMode.CHASE]:
			view.set_camera_mode(mode)
			_present(view, true, 0.1, false, false)
			await _render()
			var on := view.world_viewport.get_texture().get_image()
			_present(view, true, 0.6, false, false)
			await _render()
			var off := view.world_viewport.get_texture().get_image()
			_expect(_colored_gain(on, off, _car_rect(view), mode == View.CameraMode.SIDE) >= 12,
				"%s damage %d / %s: the visible signal must follow the damaged car." % [
					state.vehicle.id, stage, view.camera_name(),
				])
	state.damage_stage = 0
	view.present(0.0)


func _car_rect(view: View) -> Rect2i:
	var scale := Vector2(view.world_viewport.size) / view.size
	var bounds := view.car_screen_bounds()
	return Rect2i(Rect2(bounds.position * scale, bounds.size * scale).grow(8.0)) \
		.intersection(Rect2i(Vector2i.ZERO, view.world_viewport.size))


func _colored_gain(on: Image, off: Image, bounds: Rect2i, amber: bool) -> int:
	var changed := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var bright := on.get_pixel(x, y)
			var dark := off.get_pixel(x, y)
			var signal_color := bright.r > 0.65 and bright.g > 0.3 \
				and bright.b < minf(bright.r, bright.g) * 0.8 if amber \
				else bright.r > bright.g * 1.5 and bright.r > bright.b * 1.5
			if signal_color and bright.r > dark.r + 0.08:
				changed += 1
	return changed


func _render() -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw


func _resize(view: View, dimensions: Vector2i) -> void:
	get_root().size = dimensions
	await process_frame
	view.size = get_root().get_visible_rect().size
	view.call("_resize_world")


func _capture(view: View, title: String) -> void:
	if not _capture_dir.is_empty():
		var error := view.world_viewport.get_texture().get_image().save_png(
			_capture_dir.path_join(title + ".png"))
		_expect(error == OK, "Could not save light capture: " + title)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
