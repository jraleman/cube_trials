extends SceneTree

## Real Compatibility 3D rendering, visible bodywork and physically sized mobile controls.
## This suite deliberately requires a graphics window rather than --headless.

const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const View = preload("res://games/cube_trials/course_view.gd")
const GalleryStage = preload("res://games/cube_trials/gallery_stage.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")

var _failures := PackedStringArray()
var _game: Node
var _capture_dir := ""
var _peak_draws := 0
var _peak_triangles := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("cube_trials_view_test requires a graphics window, not --headless.")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cube-capture-dir="):
			_capture_dir = argument.trim_prefix("--cube-capture-dir=")
	if not _capture_dir.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
		if error != OK:
			printerr("Could not create Cube Trials capture directory: ", error_string(error))
			quit(1)
			return
	var settings := get_root().get_node("Settings")
	var original_values := (settings.get("_values") as Dictionary).duplicate(true)
	var save_timer := settings.get("_save_timer") as Timer
	var timer_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	settings.call("set_value", "ui/scale", 1.0)
	settings.call("set_value", Options.AIR_CONTROL_KEY, 1.0)
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	settings.call("set_value", Options.DAY_NIGHT_KEY, true)
	GameCatalog.restrict_to(Options.GAME_ID)
	get_root().theme = GameCatalog.theme().restyle(ThemeDB.get_project_theme())
	_game = (load("res://games/cube_trials/gameplay.tscn") as PackedScene).instantiate()
	get_root().add_child(_game)
	_game.set_process(false)
	_test_3d_scene()
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, true)
	Input.action_press(Options.THROTTLE)
	_game.call("_update_round", 0.1, 0.0)
	Input.action_release(Options.THROTTLE)
	_expect((_game.get("_engine") as AudioStreamPlayer).playing,
		"A driving car must actually start the engine loop when enabled.")
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	_expect(not (_game.get("_engine") as AudioStreamPlayer).playing,
		"The engine toggle must stop a real playing voice.")
	_game.call("_on_play_again_pressed")
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(2560, 720)]:
		(_game.get_node("%PauseButton") as Control).visible = dimensions.y > dimensions.x
		get_root().size = dimensions
		await _render_frames()
		_test_bounds()
		_test_brown_cube()
		_test_draw_budget()
		await _capture("trail-%dx%d" % [dimensions.x, dimensions.y])
	get_root().size = Vector2i(390, 844)
	settings.call("set_value", "ui/scale", 1.5)
	await _render_frames()
	_test_bounds()
	await _capture("portrait-large-ui")
	settings.call("set_value", "ui/scale", 1.0)
	get_root().size = Vector2i(1280, 720)
	(_game.get_node("%PauseButton") as Control).hide()
	await _render_frames()
	await _test_rendered_brakes()
	await _test_motion_blur()
	_game.call("_on_play_again_pressed")
	await _render_frames()
	var state: State = _game.get("_state")
	_drive_to(Course.CHECKPOINT_X[1] + 60.0)
	await _render_frames()
	_test_brown_cube()
	_test_draw_budget()
	await _capture("imported-checkpoint")
	_drive_to(2860.0)
	await _render_frames()
	_expect(state.position.x >= 2860.0 and state.contacts == 0,
		"The rendered quarry shot must be an actual airborne drive.")
	var view: Control = _game.get("_view")
	var landing: Vector2 = view.call("project_point",
		Art.world_point(Vector2(3100.0, Course.ground_height(3100.0))))
	_expect(Rect2(Vector2.ZERO, view.size).has_point(landing),
		"The camera must show the far-side landing during the quarry jump.")
	_test_brown_cube()
	_test_draw_budget()
	await _capture("quarry-jump")
	_drive_to(Course.FINISH_X - 80.0)
	await _render_frames()
	_test_brown_cube()
	_test_draw_budget()
	await _capture("imported-garage-approach")
	await _test_parking_and_night()
	_drive_to(6000.0)
	await _render_frames()
	_expect(state.finished, "The rendered run must reach the real garage finish.")
	_test_draw_budget()
	await _capture("results")
	_game.call("_on_see_score_pressed")
	for frame in 45:
		await process_frame
	_expect((_game.get_node("%ShareCardPreview") as TextureRect).texture != null,
		"The custom Cube illustration must render in the shared scorecard.")
	await _capture("scorecard")
	Driver.release_controls()
	_game.free()
	state = null
	await _test_imported_gallery()
	get_root().size = Vector2i(1280, 720)
	var menu := (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	await _render_frames()
	_expect((menu.get_node("%Title") as Label).text == "Cube Trials",
		"The standalone title must come from the game's manifest.")
	await _capture("title")
	menu.free()
	settings.set("_values", original_values)
	save_timer.stop()
	save_timer.process_mode = timer_mode
	GameCatalog.clear_restriction()
	await process_frame
	await create_timer(0.15).timeout
	print("Cube Trials 3D budget: %d draw calls / %d triangles." % [
		_peak_draws, _peak_triangles,
	])
	if _failures.is_empty():
		print("Cube Trials graphics and responsive layout tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _drive_to(x: float) -> void:
	var state: State = _game.get("_state")
	for frame in 60 * 90:
		if state.position.x >= x or state.finished:
			break
		Driver.hold_controls(state)
		_game.call("_update_round", 1.0 / 60.0, 0.0)
	Driver.release_controls()


func _test_bounds() -> void:
	var view: Control = _game.get("_view")
	var controls: Control = _game.get("_controls")
	var visible := get_root().get_visible_rect()
	var physical_scale := float(get_root().size.x) / visible.size.x
	var view_rect := view.get_global_rect()
	_expect(view_rect.size.y * physical_scale >= 180.0,
		"The trail needs at least 180 physical pixels of usable height.")
	_expect(visible.encloses(view_rect) and visible.encloses(controls.get_global_rect()),
		"The course and every pedal must remain inside the viewport.")
	_expect(view_rect.end.y < controls.get_global_rect().position.y,
		"Driving controls cannot cover the car or road.")
	var buttons: Dictionary = controls.get("buttons")
	for action in Options.DRIVE_ACTIONS:
		var button: Button = buttons[action]
		var rect := button.get_global_rect()
		_expect(rect.size.y * physical_scale >= 44.0,
			"%s needs a 44-pixel physical touch target." % action)
		_expect(button.get_theme_font_size("font_size") * physical_scale >= 12.0,
			"%s must retain legible text on a phone." % action)
		_expect(visible.encloses(rect), "%s must not extend off-screen." % action)
	var pause_button := _game.get_node("%PauseButton") as Control
	if pause_button.visible:
		_expect(visible.encloses(pause_button.get_global_rect()),
			"The mobile pause affordance must fit beside the HUD.")
		_expect(pause_button.size.y * physical_scale >= 44.0,
			"The mobile pause button needs a real 44-pixel touch target too.")
	var car_bounds: Rect2 = view.call("car_screen_bounds")
	_expect(car_bounds.size.x * physical_scale >= 48.0,
		"The Cube must remain at least 48 physical pixels wide on a phone.")


func _test_brown_cube() -> void:
	var view: Control = _game.get("_view")
	var world: Node3D = view.get("world")
	var car: Node3D = world.get("car")
	var point: Vector2 = view.call("project_point", car.call("paint_sample"))
	_expect(Rect2(Vector2.ZERO, view.size).has_point(point),
		"The camera must keep the driver's brown bodywork visible.")
	var image := get_root().get_texture().get_image()
	var ratio := Vector2(image.get_size()) / get_root().get_visible_rect().size
	var pixel := (view.global_position + point) * ratio
	var color := image.get_pixel(clampi(roundi(pixel.x), 0, image.get_width() - 1),
		clampi(roundi(pixel.y), 0, image.get_height() - 1))
	_expect(color.r > color.g * 1.25 and color.g > color.b * 1.25,
		"The car must actually render brown, not just name brown in the manifest.")


func _test_3d_scene() -> void:
	var view: Control = _game.get("_view")
	var viewport: SubViewport = view.get("world_viewport")
	var world: Node3D = view.get("world")
	var camera: Camera3D = view.get("world_camera")
	_expect(viewport.own_world_3d and not viewport.disable_3d
		and camera.get_viewport() == viewport,
		"Gameplay must render real 3D in an isolated viewport, not a painted substitute.")
	_expect(world.get_node("ExactDrivingSurface") is MeshInstance3D
		and world.get_node("LayeredQuarryRock") is MeshInstance3D
		and world.get_node(
			"CopperCreekServiceGarage/ImportedBodyShop/CarBodyShop/Cladding"
		) is MeshInstance3D,
		"The course, quarry and garage must have actual 3D geometry.")
	var car: Node3D = world.get("car")
	var body := car.get_node("Chassis/BrownBodywork") as MeshInstance3D
	_expect((body.transform * body.mesh.get_aabb()).size.z > 2.0
		and car.get_node("Chassis/WraparoundGlazing") is MeshInstance3D
		and car.get_node("FrontAxle/FrontRightWheel/Tires") is MeshInstance3D
		and car.get_node("FrontAxle/FrontLeftWheel/Tires") is MeshInstance3D
		and car.get_node("RearAxle/RearRightWheel/Tires") is MeshInstance3D
		and car.get_node("RearAxle/RearLeftWheel/Tires") is MeshInstance3D,
		"The imported Nissan Cube must retain its volumetric body, glazing and four wheels.")
	# The headless renderer cannot read MultiMesh transforms back; verify the real GPU storage here.
	var poses: Array[Transform3D] = world.get("pine_poses")
	var first := 0
	for batch in world.get_node("RoadsidePines").get_children():
		var foliage := batch.get_node("Foliage") as MultiMeshInstance3D
		var trunk := batch.get_node("Trunk") as MultiMeshInstance3D
		for index in foliage.multimesh.instance_count:
			_expect(foliage.multimesh.get_instance_transform(index).is_equal_approx(
				poses[first + index])
				and trunk.multimesh.get_instance_transform(index).is_equal_approx(
					poses[first + index]),
				"The rendered trunks and foliage must use the actual grounded planting transforms.")
		first += foliage.multimesh.instance_count
	_expect(first == poses.size(), "The real renderer must contain every planted pine.")


func _test_imported_gallery() -> void:
	var stage := GalleryStage.new()
	get_root().add_child(stage)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(2560, 720)]:
		get_root().size = dimensions
		await _render_frames()
		stage.size = get_root().get_visible_rect().size
		for id: String in [Options.EXHIBIT_PLUG, Options.EXHIBIT_CHECKPOINT,
				Options.EXHIBIT_PINE, Options.EXHIBIT_GARAGE]:
			stage.configure({"id": id})
			for pose: Vector2 in [Vector2.ZERO, Vector2(PI * 0.5, 0.0),
					Vector2(PI, 0.7), Vector2(0, -0.9)]:
				stage.set_view(pose.x, pose.y, 1.0)
				await _render_frames()
				var model: Node3D = stage.get("_exhibit")
				var camera: Camera3D = stage.get("_camera")
				var viewport: SubViewport = stage.get("_viewport")
				var picture := Rect2(Vector2.ZERO, Vector2(viewport.size))
				var contained := true
				for part: MeshInstance3D in model.find_children(
					"*", "MeshInstance3D", true, false
				):
					for corner in 8:
						var point := part.to_global(part.mesh.get_aabb().get_endpoint(corner))
						contained = contained and not camera.is_position_behind(point) \
							and picture.has_point(camera.unproject_position(point))
				_expect(contained, "%s must fit its gallery case at %s, pose %s."
					% [id, dimensions, pose])
				if pose.is_zero_approx():
					await _capture("gallery-%s-%dx%d" % [id, dimensions.x, dimensions.y])
	stage.free()


func _test_draw_budget() -> void:
	var view: Control = _game.get("_view")
	var viewport: SubViewport = view.get("world_viewport")
	var draws := viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
	)
	var triangles := viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME
	)
	_peak_draws = maxi(_peak_draws, draws)
	_peak_triangles = maxi(_peak_triangles, triangles)
	print("Render budget at x=%.1f, size=%s: %d draws / %d triangles"
		% [(_game.get("_state") as State).position.x, get_root().size, draws, triangles])
	_expect(draws > 10 and draws <= 200 and triangles > 1000 and triangles < 120000,
		"The actual 3D view must stay within its Compatibility budget (%d draws / %d triangles)."
		% [draws, triangles])


func _test_rendered_brakes() -> void:
	var view := _game.get("_view") as View
	var car: Cube = view.world.car
	var state: State = _game.get("_state")
	var saved_transform := view.world_camera.transform
	var saved_size := view.world_camera.size
	view.world_camera.position = car.position + Vector3(-5.5, 2.3, 5.5)
	view.world_camera.look_at(car.position)
	view.world_camera.size = 4.7
	car.apply_state(state, false)
	await _render_frames()
	var off := view.world_viewport.get_texture().get_image()
	# Essential emission must remain visible even with both decorative effects disabled.
	car.apply_state(state, true, 0.0, true, false)
	await _render_frames()
	var on := view.world_viewport.get_texture().get_image()
	var brighter_red := 0
	for y in range(0, on.get_height(), 2):
		for x in range(0, on.get_width(), 2):
			var dark := off.get_pixel(x, y)
			var bright := on.get_pixel(x, y)
			if bright.r > dark.r + 0.08 and bright.r > bright.g * 1.5 \
				and bright.r > bright.b * 1.5:
				brighter_red += 1
	_expect(brighter_red > 12,
		"Braking must visibly brighten the rendered red lenses, not only a material property.")
	car.apply_state(state, true, 0.0, false, true)
	await _render_frames()
	_test_draw_budget()
	await _capture("brakes-on")
	car.apply_state(state, false)
	view.world_camera.transform = saved_transform
	view.world_camera.size = saved_size
	view.present(0.0)


func _test_motion_blur() -> void:
	var view := _game.get("_view") as View
	var state: State = _game.get("_state")
	var image_node := view.get_node("WorldImage") as TextureRect
	_game.call("_set_reduced_motion_enabled", false)
	_game.call("_set_intense_effects_enabled", true)
	state.started = true
	state.velocity = Vector2(520, 0)
	for frame in 40:
		view.present(1.0 / 60.0)
	var blur_pixels: Vector2 = view.get("_blur_pixels")
	_expect(image_node.material is ShaderMaterial and blur_pixels.length() > 2.1
		and blur_pixels.length() <= View.MAX_BLUR_PIXELS + 0.001,
		"High-speed scenery blur must remain subtle and capped at 2.25 render pixels.")
	await _render_frames()
	_test_brown_cube()
	var blurred := get_root().get_texture().get_image()
	await _capture("motion-blur")
	var blur_material := image_node.material
	image_node.material = null
	await _render_frames()
	_test_brown_cube()
	var sharp := get_root().get_texture().get_image()
	await _capture("motion-blur-sharp")
	var ratio := Vector2(sharp.get_size()) / get_root().get_visible_rect().size
	var rectangle := view.get_global_rect()
	var world_pixels := Rect2(rectangle.position * ratio, rectangle.size * ratio)
	var car_bounds := view.car_screen_bounds()
	var car_pixels := Rect2((view.global_position + car_bounds.position) * ratio,
		car_bounds.size * ratio)
	var changed_world := 0
	var changed_hud := 0
	var changed_car := 0
	for y in range(0, sharp.get_height(), 2):
		for x in range(0, sharp.get_width(), 2):
			var difference := _color_difference(sharp.get_pixel(x, y), blurred.get_pixel(x, y))
			if car_pixels.has_point(Vector2(x, y)) and difference >= 0.012:
				changed_car += 1
			if difference < 0.015:
				continue
			if world_pixels.has_point(Vector2(x, y)):
				changed_world += 1
			else:
				changed_hud += 1
	_expect(changed_world > 80 and changed_hud == 0,
		"The shader must blur actual scenery pixels while leaving the entire HUD untouched.")
	_expect(changed_car == 0,
		"The protected car region must retain crisp paint and wheel detail.")
	image_node.material = blur_material
	_game.call("_set_reduced_motion_enabled", true)
	_expect(image_node.material == null,
		"Reduced motion must immediately bypass the blur shader.")
	_game.call("_set_reduced_motion_enabled", false)
	for frame in 10:
		view.present(1.0 / 60.0)
	_game.call("_set_intense_effects_enabled", false)
	_expect(image_node.material == null,
		"Disabling intense effects must independently remove motion blur.")
	_game.call("_set_intense_effects_enabled", true)
	for frame in 10:
		view.present(1.0 / 60.0)
	paused = true
	_expect(image_node.material == null, "Pausing must not leave a frozen blurred world.")
	paused = false
	state.velocity = Vector2(-520, 0)
	for frame in 10:
		view.present(1.0 / 60.0)
	blur_pixels = view.get("_blur_pixels")
	_expect(blur_pixels.x < 0.0, "Reversing must reverse the projected blur direction.")
	state.velocity = Vector2(View.BLUR_START_SPEED, 0)
	view.present(1.0 / 60.0)
	_expect(image_node.material == null, "Slow driving and parking must remain sharp.")
	state.velocity = Vector2(520, 0)
	view.present(1.0 / 60.0)
	state.crash_wait = 0.5
	view.present(1.0 / 60.0)
	_expect(image_node.material == null, "Recovery must remove motion blur immediately.")
	state.crash_wait = 0.0
	view.present(1.0 / 60.0)
	_expect(image_node.material == null, "The first post-recovery frame must not smear a teleport.")
	for frame in 10:
		view.present(1.0 / 60.0)
	state.finished = true
	view.present(1.0 / 60.0)
	_expect(image_node.material == null, "Results must never retain speed blur.")
	_game.call("_set_reduced_motion_enabled", true)


func _test_parking_and_night() -> void:
	var view := _game.get("_view") as View
	var reduced := view.reduced_motion
	var effects := view.intense_effects
	var cycling := view.day_night_enabled
	var garage := view.world.get_node("CopperCreekServiceGarage") as Node3D
	var outline := garage.get_node("ParkingOutline") as MeshInstance3D
	view.set_reduced_motion(true)
	view.set_intense_effects(true)
	_expect(await _outline_pixels(view, outline) > 20,
		"The parking outline must visibly mark the road, not just exist as a material.")
	_test_parking_hint(view)
	var day := view.world_viewport.get_texture().get_image()
	await _capture("parking-daylight")
	view.set_reduced_motion(false)
	view.set_day_night_enabled(true)
	view.daylight_time = (0.5 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS
	view.present(0.0)
	await _render_frames()
	await _capture("parking-sunset")
	view.daylight_time = (0.75 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS
	view.set_intense_effects(false)
	await _render_frames()
	var night := view.world_viewport.get_texture().get_image()
	_expect(_average_luminance(night) < _average_luminance(day) * 0.9
		and _average_luminance(night) > 0.08,
		"The real night image must be distinct from daylight without blacking out the course.")
	_expect(await _outline_pixels(view, outline) > 20,
		"Night parking must remain visibly outlined with intense effects disabled.")
	var paint := view.world_camera.unproject_position(view.world.car.paint_sample())
	var paint_color := night.get_pixel(
		clampi(roundi(paint.x), 0, night.get_width() - 1),
		clampi(roundi(paint.y), 0, night.get_height() - 1))
	_expect(paint_color.get_luminance() > 0.055,
		"The driver's actual bodywork must remain readable at night.")
	for light in view.world.car.headlights:
		light.visible = false
	await _render_frames()
	var without_headlights := view.world_viewport.get_texture().get_image()
	_expect(_brighter_pixels(night, without_headlights) > 20,
		"Automatic headlights must illuminate actual road pixels, not only light their bulbs.")
	view.present(0.0)
	var workshop := garage.get_node("WorkshopLight") as OmniLight3D
	workshop.visible = false
	await _render_frames()
	var without_workshop := view.world_viewport.get_texture().get_image()
	_expect(_brighter_pixels(night, without_workshop) > 20,
		"The warm workshop light must visibly illuminate the garage at night.")
	view.present(0.0)
	await _render_frames()
	_test_draw_budget()
	await _capture("parking-night-low-effects")
	view.set_intense_effects(true)
	await _render_frames()
	await _capture("parking-night")
	view.set_intense_effects(false)
	get_root().size = Vector2i(390, 844)
	await _render_frames()
	_test_bounds()
	_test_draw_budget()
	_expect(await _outline_pixels(view, outline) > 20,
		"The night parking target must remain visibly identifiable on a portrait phone.")
	_test_parking_hint(view)
	await _capture("parking-night-portrait")
	get_root().size = Vector2i(1280, 720)
	view.set_day_night_enabled(cycling)
	view.set_reduced_motion(reduced)
	view.set_intense_effects(effects)
	await _render_frames()


func _test_parking_hint(view: View) -> void:
	var physical_scale := float(get_root().size.x) / get_root().get_visible_rect().size.x
	var bounds: Rect2 = view.get("_parking_hint_bounds")
	var font_size: int = view.get("_parking_hint_font_size")
	var target := view.project_point(view.world.parking_target())
	_expect(bounds.has_area() and Rect2(Vector2.ZERO, view.size).encloses(bounds)
		and font_size * physical_scale >= 13.0
		and bounds.size.y * physical_scale >= 24.0 and bounds.end.y < target.y,
		"The parking callout must stay legible, on-screen and above its pointer to the real bay.")


func _outline_pixels(view: View, outline: MeshInstance3D) -> int:
	outline.visible = false
	await _render_frames()
	var off := view.world_viewport.get_texture().get_image()
	outline.visible = true
	await _render_frames()
	var on := view.world_viewport.get_texture().get_image()
	var changed := 0
	for y in range(0, on.get_height(), 2):
		for x in range(0, on.get_width(), 2):
			if _color_difference(on.get_pixel(x, y), off.get_pixel(x, y)) > 0.1:
				changed += 1
	return changed


func _brighter_pixels(on: Image, off: Image) -> int:
	var changed := 0
	for y in range(0, on.get_height(), 2):
		for x in range(0, on.get_width(), 2):
			if on.get_pixel(x, y).get_luminance() > off.get_pixel(x, y).get_luminance() + 0.025:
				changed += 1
	return changed


func _average_luminance(image: Image) -> float:
	var total := 0.0
	var samples := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			total += image.get_pixel(x, y).get_luminance()
			samples += 1
	return total / samples


func _color_difference(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _render_frames() -> void:
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw


func _capture(label: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var error := image.save_png(_capture_dir.path_join(label + ".png"))
	_expect(error == OK, "Could not save %s: %s." % [label, error_string(error)])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
