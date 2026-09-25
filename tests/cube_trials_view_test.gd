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
const TrialHUD = preload("res://games/cube_trials/trial_hud.gd")

var _failures := PackedStringArray()
var _course := Course.new()
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
	for dimensions in [
		Vector2i(1280, 720), Vector2i(390, 844), Vector2i(320, 844), Vector2i(2560, 720),
	]:
		get_root().size = dimensions
		await _render_frames()
		_test_bounds()
		_test_brown_cube()
		_test_draw_budget()
		await _capture("trail-%dx%d" % [dimensions.x, dimensions.y])
		await _test_full_hud()
	get_root().size = Vector2i(390, 844)
	settings.call("set_value", "ui/scale", 1.5)
	await _render_frames()
	_test_bounds()
	await _capture("portrait-large-ui")
	settings.call("set_value", "ui/scale", 1.0)
	await _test_caption_layout(settings)
	get_root().size = Vector2i(1280, 720)
	await _render_frames()
	await _test_rendered_impacts()
	await _test_rendered_coilovers()
	await _test_rendered_tricks()
	await _test_damage_looks()
	for stage in State.DAMAGE_NAMES.size():
		await _test_rendered_brakes(stage)
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
		Art.world_point(Vector2(3100.0, _course.ground_height(3100.0))))
	_expect(Rect2(Vector2.ZERO, view.size).has_point(landing),
		"The camera must show the far-side landing during the quarry jump.")
	_test_brown_cube()
	_test_draw_budget()
	await _check_rendered_coilovers(view as View, "quarry-flight", true)
	await _capture("quarry-jump")
	for index in range(1, _course.gap_intervals().size()):
		var gap := _course.gap_intervals()[index]
		_drive_to((gap.x + gap.y) * 0.5)
		await _render_frames()
		_expect(state.contacts == 0 and state.recoveries == 0,
			"Each new ravine capture must be a clean, input-driven manual jump.")
		var far_side := Vector2(gap.y + 140.0, _course.ground_height(gap.y + 140.0))
		_expect(Rect2(Vector2.ZERO, view.size).has_point(
			view.call("project_point", Art.world_point(far_side))),
			"The side camera must reveal the landing across every wider ravine.")
		_test_brown_cube()
		_test_draw_budget()
		await _capture("ravine-jump-%d" % index)
	_drive_to(Course.FINISH_X - 80.0)
	await _render_frames()
	_test_brown_cube()
	_test_draw_budget()
	await _capture("imported-garage-approach")
	await _test_parking_and_night()
	_drive_to(Course.END_X)
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
	await _test_reference_car_gallery_menu()
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
		if state.position.x >= x or state.is_over():
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
	_expect(view_rect.get_area() >= visible.get_area() * 0.80,
		"The expanded game view must occupy at least 80 percent of the screen at %s (actual %.1f%%)."
		% [get_root().size, view_rect.get_area() / visible.get_area() * 100.0])
	_expect(visible.encloses(view_rect) and visible.encloses(controls.get_global_rect()),
		"The course and every pedal must remain inside the viewport.")
	_expect(view_rect.end.y < controls.get_global_rect().position.y,
		"Driving controls cannot cover the car or road.")
	var buttons: Dictionary = controls.get("buttons")
	for action in buttons:
		var button: Button = buttons[action]
		var rect := button.get_global_rect()
		_expect(rect.size.x * physical_scale >= 44.0 and rect.size.y * physical_scale >= 44.0,
			"%s needs a 44-pixel physical touch target." % action)
		_expect(button.get_theme_font_size("font_size") * physical_scale >= 12.0,
			"%s must retain legible text on a phone." % action)
		_expect(button.icon != null
			and button.get_theme_constant("icon_max_width") * physical_scale >= 18.0
			and not button.accessibility_name.is_empty(),
			"%s needs a legible action icon and a screen-reader description." % action)
		_expect(visible.encloses(rect), "%s must not extend off-screen." % action)
	var pause_button := _game.get_node("%PauseButton") as Control
	_expect(pause_button.is_visible_in_tree()
		and visible.encloses(pause_button.get_global_rect()),
		"The icon pause affordance must remain available and on-screen on every device.")
	_expect(pause_button.size.y * physical_scale >= 44.0,
		"The mobile pause button needs a real 44-pixel touch target too.")
	var image := get_root().get_texture().get_image()
	var center := pause_button.get_global_rect().get_center() * physical_scale
	var pause_ink := 0
	for y in range(roundi(center.y - 10), roundi(center.y + 10)):
		for x in range(roundi(center.x - 10), roundi(center.x + 10)):
			var color := image.get_pixel(clampi(x, 0, image.get_width() - 1),
				clampi(y, 0, image.get_height() - 1))
			if color.r > 0.9 and color.g > 0.9 and color.b > 0.9:
				pause_ink += 1
	_expect(pause_ink >= 16,
		"The pause glyph must actually render inside its padding, not just have an icon resource.")
	var hud := _game.get("_trial_hud") as TrialHUD
	_expect(view_rect.encloses(hud.camera_button.get_global_rect())
		and hud.camera_button.size.x * physical_scale >= 44.0
		and hud.camera_button.size.y * physical_scale >= 44.0
		and hud.camera_button.get_global_rect().end.x < pause_button.get_global_rect().position.x,
		"The camera needs its own 44-pixel target immediately beside Pause, including on small phones.")
	_expect(view_rect.encloses(hud.bar.get_global_rect()),
		"Life, points, plugs, timer and pause must all fit inside the game view.")
	var end := hud.bar.global_position.x
	var row := hud.bar.global_position.y
	for child: Control in hud.bar.get_children():
		if child.global_position.y > row + 0.01:
			end = hud.bar.global_position.x
			row = child.global_position.y
		_expect(child.get_global_rect().position.x >= end - 0.01,
			"HUD counters must not overlap at narrow or large-UI sizes.")
		end = child.get_global_rect().end.x
	for label in [hud.lives_label, hud.points_label, hud.plugs_label, hud.time_label]:
		_expect(label.get_theme_font_size("font_size") * physical_scale >= 16.0
			and view_rect.encloses(label.get_global_rect()),
			"Icon counter values must remain legible, unclipped and inside the game view.")
	if hud.feedback_label.is_visible_in_tree():
		_expect(view_rect.encloses(hud.feedback_label.get_global_rect()),
			"Brief event feedback must fit without spilling across the edge of a phone.")
		_expect(hud.feedback_label.global_position.y - hud.bar.get_global_rect().end.y \
			<= 24.0 * float(_game.get("_ui_factor")),
			"Feedback must stay tucked below the counters after portrait/landscape or UI-scale changes.")
	var car_bounds: Rect2 = view.call("car_screen_bounds")
	_expect(maxf(car_bounds.size.x, car_bounds.size.y) * physical_scale >= 48.0,
		"The Cube's long dimension must remain at least 48 physical pixels, even during a flip.")


func _test_full_hud() -> void:
	var state: State = _game.get("_state")
	state.collected.fill(true)
	state.lives_left = 1
	state.elapsed = 6500.25
	_game.call("_sync_hud")
	await _render_frames()
	_test_bounds()
	var hud := _game.get("_trial_hud") as TrialHUD
	_expect(hud.points_label.text == "5000" and hud.lives_label.text == "1"
		and hud.plugs_label.text == "5/5" and hud.time_label.text.begins_with("108:20"),
		"Real point totals and even long untimed runs must fit the compact HUD.")
	await _capture("hud-full-%dx%d" % [get_root().size.x, get_root().size.y])
	state.collected.fill(false)
	state.lives_left = State.STARTING_LIVES
	state.elapsed = 0.0
	_game.call("_sync_hud")


func _test_caption_layout(settings: Node) -> void:
	settings.call("set_value", Settings.AUDIO_CAPTIONS_KEY, true)
	get_root().get_node("AudioManager").call("request_caption",
		"Roof hit the trail. One life lost. 4 lives left. Recovering at checkpoint 0. +5 seconds.")
	await _render_frames()
	_test_bounds()
	var caption := _game.get("_audio_caption") as Control
	var label := caption.get_node("CaptionLabel") as Label
	var view := _game.get("_view") as Control
	var controls := _game.get("_controls") as Control
	var scale := float(get_root().size.x) / get_root().get_visible_rect().size.x
	_expect(caption.is_visible_in_tree() and label.get_theme_font_size("font_size") * scale >= 14.0
		and view.get_global_rect().end.y < caption.get_global_rect().position.y
		and caption.get_global_rect().end.y < controls.get_global_rect().position.y,
		"Optional audio captions must stay readable on phones without obscuring the road or pedals.")
	await _capture("portrait-audio-captions")
	settings.call("set_value", Settings.AUDIO_CAPTIONS_KEY, false)


func _test_rendered_impacts() -> void:
	var view := _game.get("_view") as View
	var state: State = _game.get("_state")
	_game.call("_set_reduced_motion_enabled", false)
	_game.call("_set_intense_effects_enabled", true)
	state.advance(0.5, 0.0, 0.0, 0.0)
	state.damage_stage = 1
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
		get_root().size = dimensions
		view.world.car.reset_motion()
		view.present(0.0)
		await _render_frames()
		_test_bounds()
		var scale := Vector2(view.world_viewport.size) / view.size
		var bounds := view.car_screen_bounds()
		var crop := Rect2i(Rect2(bounds.position * scale, bounds.size * scale).grow(8.0))
		crop = crop.intersection(Rect2i(Vector2i.ZERO, view.world_viewport.size))
		var before := view.world_viewport.get_texture().get_image().get_region(crop)
		view.world.car.play_impact()
		view.present(0.04)
		await _render_frames()
		var impact := view.world_viewport.get_texture().get_image().get_region(crop)
		var changed := 0
		for y in impact.get_height():
			for x in impact.get_width():
				if _color_difference(before.get_pixel(x, y), impact.get_pixel(x, y)) > 0.08:
					changed += 1
		_expect(changed >= maxi(12, floori(crop.get_area() * 0.015)),
			"An impact must visibly animate the real car at %s, not just update an internal timer."
			% dimensions)
		_test_draw_budget()
		await _capture("impact-%dx%d" % [dimensions.x, dimensions.y])
		view.set_reduced_motion(true)
		var body := view.world.car.chassis.get_node("BrownBodywork") as MeshInstance3D
		_expect(body.material_overlay == null and view.world.car.chassis.position == Vector3.ZERO,
			"Live reduced motion must remove the rendered highlight and decorative recoil.")
		view.set_reduced_motion(false)
	_game.call("_on_play_again_pressed")
	_game.call("_set_reduced_motion_enabled", true)
	get_root().size = Vector2i(1280, 720)
	await _render_frames()


func _test_rendered_coilovers() -> void:
	var view := _game.get("_view") as View
	_game.call("_set_reduced_motion_enabled", false)
	_game.call("_set_intense_effects_enabled", true)
	view.set_day_night_enabled(false)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
		get_root().size = dimensions
		_game.call("_on_play_again_pressed")
		var state: State = _game.get("_state")
		_game.call("_update_round", 0.5, 0.0)
		await _render_frames()
		var resting := view.world.car.springs[1].length
		await _check_rendered_coilovers(view, "parked", false)
		Input.action_press(Options.JUMP)
		var landing_frame := -1
		for frame in 150:
			_game.call("_update_round", 1.0 / 60.0, 0.0)
			Input.action_release(Options.JUMP)
			if frame > 0 and state.contacts > 0 and landing_frame < 0:
				landing_frame = frame
			var pose := ""
			if frame == 3:
				pose = "takeoff"
			elif frame == 25:
				pose = "airborne"
			elif frame == 40:
				pose = "apex"
			elif landing_frame >= 0 and frame == landing_frame + 1:
				pose = "landing"
			elif landing_frame >= 0 and frame == landing_frame + 10:
				pose = "rebound"
			elif frame == 149:
				pose = "settled"
			if pose.is_empty():
				continue
			await _render_frames()
			var airborne := pose in ["takeoff", "airborne", "apex"]
			_expect((state.contacts == 0) == airborne,
				"The coilover capture must sample the intended flight or grounded phase: %s." % pose)
			var visible_pixels := await _check_rendered_coilovers(view, pose, airborne)
			_test_bounds()
			_test_draw_budget()
			if pose == "airborne":
				_expect(state.contacts == 0 and view.world.car.springs[1].length > resting + 0.25,
					"The airborne wheels must drop slightly farther to reveal the extended coilovers.")
				await _test_rendered_wheel_droop(view, state, visible_pixels)
			await _capture("coilovers-%s-%dx%d" % [pose, dimensions.x, dimensions.y])
		_expect(landing_frame > 75 and landing_frame < 90,
			"The taller standing jump must still reach a real two-wheel landing.")
		Input.action_press(Options.THROTTLE)
		_game.call("_update_round", 0.2, 0.0)
		Input.action_release(Options.THROTTLE)
		await _render_frames()
		_expect(state.contacts > 0, "The driving coilover check must stay on the trail.")
		await _check_rendered_coilovers(view, "driving", false)
		Input.action_press(Options.BRAKE)
		_game.call("_update_round", 0.15, 0.0)
		Input.action_release(Options.BRAKE)
		await _render_frames()
		_expect(state.contacts > 0, "The braking coilover check must stay on the trail.")
		await _check_rendered_coilovers(view, "braking", false)
		state.damage_stage = State.MAX_DAMAGE_STAGE
		view.present(0.0)
		await _render_frames()
		await _check_rendered_coilovers(view, "battered", false)
		view.set_reduced_motion(true)
		view.set_intense_effects(false)
		Input.action_press(Options.JUMP)
		_game.call("_update_round", 0.25, 0.0)
		Input.action_release(Options.JUMP)
		await _render_frames()
		await _check_rendered_coilovers(view, "reduced-motion", true)
		_expect(view.world.car.chassis.position == Vector3.ZERO
			and view.world.car.springs[1].length > resting + 0.06,
			"Real suspension extension must remain visible without decorative motion or intense effects.")
		state.recover()
		view.present(0.0)
		await _render_frames()
		await _check_rendered_coilovers(view, "recovered", false)
		_game.call("_on_play_again_pressed")
		await _render_frames()
		await _check_rendered_coilovers(view, "replay", false)
		view.set_reduced_motion(false)
		view.set_intense_effects(true)
	_game.call("_on_play_again_pressed")
	_game.call("_set_reduced_motion_enabled", true)
	view.set_day_night_enabled(true)
	get_root().size = Vector2i(1280, 720)
	await _render_frames()


func _test_rendered_wheel_droop(view: View, state: State, extended_pixels: PackedInt32Array) -> void:
	var car := view.world.car
	for index in 2:
		var physical_center := Art.world_point(state.wheel_centers[index])
		_expect(car.axles[index].global_position.distance_to(physical_center) >= 0.14,
			"The rendered wheel must actually move away from the fender in mid-flight.")
		var center := physical_center - car.position
		car.axles[index].position = center
		var mount := car.chassis.position + car.chassis.basis \
			* Vector3(State.AXLES[index].x, -State.AXLES[index].y, 0) * Art.WORLD_SCALE
		car.call("_pose_suspension", index, mount, center)
	await _render_frames()
	var original_pixels := await _check_rendered_coilovers(view, "without-extra-wheel-drop", true)
	for index in 2:
		var minimum_gain := 2 if get_root().size.x < 600 else 8
		_expect(extended_pixels[index] >= original_pixels[index] + minimum_gain,
			"Wheel droop must reveal more coilover pixels at %s, not just move a hidden mesh "
			% get_root().size + "(axle %d: %d -> %d, need +%d)."
			% [index, original_pixels[index], extended_pixels[index], minimum_gain])
	view.present(0.0)
	await _render_frames()


func _test_rendered_tricks() -> void:
	var view := _game.get("_view") as View
	var hud := _game.get("_trial_hud") as TrialHUD
	_game.call("_set_reduced_motion_enabled", false)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
		get_root().size = dimensions
		_game.call("_on_play_again_pressed")
		_game.call("_update_round", 0.5, 0.0)
		await _render_frames()
		var state: State = _game.get("_state")
		var saw_pending := false
		Input.action_press(Options.JUMP)
		for frame in 120:
			if frame == 10:
				Input.action_press(Options.NOSE_UP)
			elif frame == 24:
				_game.call("_toggle_hazards")
			elif frame == 60:
				Input.action_release(Options.NOSE_UP)
			_game.call("_update_round", 1.0 / 60.0, 0.0)
			Input.action_release(Options.JUMP)
			_expect(Rect2(Vector2.ZERO, view.size).encloses(view.car_screen_bounds()),
				"The complete rendered car must stay in view throughout a real flip.")
			if frame in [30, 50]:
				await _render_frames()
				_test_bounds()
				await _capture("flip-pose-%d-%dx%d" % [frame, dimensions.x, dimensions.y])
			if state.pending_flips > 0 and not saw_pending:
				saw_pending = true
				await _render_frames()
				_test_bounds()
				_expect(hud.points_label.text == "0" and hud.feedback_label.text.contains(
					"LAND +%d" % state.pending_trick_points())
					and hud.feedback_label.text.contains("HAZARDS x1.15"),
					"Rendered trick feedback must explain landing without inflating the score.")
				await _capture("flip-pending-%dx%d" % [dimensions.x, dimensions.y])
		await _render_frames()
		_test_bounds()
		_expect(saw_pending and state.landed_flips == 1 and state.jump_points > 0
			and state.hazard_points > 0
			and hud.points_label.text == str(state.score())
			and hud.feedback_label.text.contains("+%d" % state.score()) and state.lives_left == 5,
			"A landed flip must show its dynamic banked total and readable desktop/phone feedback.")
		await _capture("flip-banked-%dx%d" % [dimensions.x, dimensions.y])
	Driver.release_controls()
	_game.call("_on_play_again_pressed")
	_game.call("_set_reduced_motion_enabled", true)
	get_root().size = Vector2i(1280, 720)
	await _render_frames()


func _check_rendered_coilovers(view: View, pose: String, airborne: bool) -> PackedInt32Array:
	var shown := view.world_viewport.get_texture().get_image()
	var counts := PackedInt32Array()
	var visibility: Array[bool] = []
	for strut in view.world.car.springs:
		visibility.append(strut.visible)
		_expect(strut.visible == airborne,
			"Coilovers must be enabled only during flight, not grounded phases: %s." % pose)
		strut.hide()
	await _render_frames()
	var hidden := view.world_viewport.get_texture().get_image()
	for index in view.world.car.springs.size():
		view.world.car.springs[index].visible = visibility[index]
	var render_scale := Vector2(view.world_viewport.size) / view.size
	for index in [1, 3]:
		var strut := view.world.car.springs[index]
		var rect := Rect2()
		for corner in 8:
			var point := view.project_point(strut.to_global(strut.custom_aabb.get_endpoint(corner)))
			rect = Rect2(point, Vector2.ZERO) if corner == 0 else rect.expand(point)
		var crop := Rect2i(Rect2(rect.position * render_scale, rect.size * render_scale).grow(2.0))
		crop = crop.intersection(Rect2i(Vector2i.ZERO, view.world_viewport.size))
		var visible_pixels := 0
		for y in range(crop.position.y, crop.end.y):
			for x in range(crop.position.x, crop.end.x):
				if _color_difference(shown.get_pixel(x, y), hidden.get_pixel(x, y)) > 0.06:
					visible_pixels += 1
		var minimum := 6 if get_root().size.x < 600 else 24
		counts.append(visible_pixels)
		if airborne:
			_expect(visible_pixels >= minimum,
				"Coilover %d must show inside the wheel well during %s at %s (%d visible pixels, need %d)."
				% [index, pose, get_root().size, visible_pixels, minimum])
		else:
			_expect(visible_pixels == 0,
				"Coilover %d must be concealed during %s at %s (%d exposed pixels)."
				% [index, pose, get_root().size, visible_pixels])
	await _render_frames()
	return counts


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
		for id: String in [Options.EXHIBIT_SONATA, Options.EXHIBIT_CRV,
				Options.EXHIBIT_SUSPENSION, Options.EXHIBIT_PLUG, Options.EXHIBIT_CHECKPOINT,
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
						var point := part.to_global(Cube.mesh_bounds(part).get_endpoint(corner))
						contained = contained and not camera.is_position_behind(point) \
							and picture.has_point(camera.unproject_position(point))
				_expect(contained, "%s must fit its gallery case at %s, pose %s."
					% [id, dimensions, pose])
				if pose.is_zero_approx():
					await _capture("gallery-%s-%dx%d" % [id, dimensions.x, dimensions.y])
	stage.free()


func _test_reference_car_gallery_menu() -> void:
	var achievements := get_root().get_node("AchievementManager")
	achievements.call("unlock", Course.COPPER_COMPLETE)
	achievements.call("unlock", Course.SUNSET_COMPLETE)
	var gallery := (load("res://scenes/menus/gallery.tscn") as PackedScene).instantiate() as Control
	gallery.set("game_context_id", Options.GAME_ID)
	get_root().add_child(gallery)
	var stage := gallery.get("_stage") as GalleryStage
	_expect(stage != null, "The Gallery menu must mount the game's actual 3D stage.")
	if stage == null:
		gallery.free()
		return
	var viewer := gallery.get_node("%Viewer") as Control
	var shown := {}
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
		get_root().size = dimensions
		await _render_frames()
		for sample: Dictionary in [
			{"id": Options.EXHIBIT_SONATA, "title": "Hyundai Sonata",
				"asset": GalleryStage.SONATA_MODEL},
			{"id": Options.EXHIBIT_CRV, "title": "Honda CR-V",
				"asset": GalleryStage.CRV_MODEL},
		]:
			var id: String = sample["id"]
			var button := gallery.find_child("Exhibit_" + id, true, false) as Button
			_expect(button != null and not button.disabled,
				"The Gallery must expose an unlocked button for " + id)
			if button == null or button.disabled:
				continue
			button.pressed.emit()
			await _render_frames()
			var model: Node3D = stage.get("_exhibit")
			var asset: PackedScene = sample["asset"]
			_expect(model != null and model.scene_file_path == asset.resource_path,
				"Selecting " + id + " must display its actual saved car model.")
			if model == null:
				continue
			_expect((gallery.get_node("%ExhibitTitle") as Label).text == sample["title"]
				and not (gallery.get_node("%Placeholder") as Label).visible
				and gallery.get_node_or_null("%Controls") == null
				and not viewer.accessibility_description.is_empty(),
				"A reference car needs its label and direct viewer, not a toolbar or badge.")
			if shown.has(id):
				_expect(model == shown[id], "Revisiting a car must reuse its cached exhibit.")
			shown[id] = model
			for resident: Node3D in (stage.get("_built") as Dictionary).values():
				_expect(resident.visible == (resident == model),
					"Only the selected Gallery exhibit may remain visible.")
			var camera: Camera3D = stage.get("_camera")
			var initial := camera.transform
			var center := viewer.get_global_rect().get_center()
			_gallery_mouse(MOUSE_BUTTON_LEFT, true, center)
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(80, 20)
			motion.position = center + motion.relative
			motion.global_position = motion.position
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			root.push_input(motion, true)
			_gallery_mouse(MOUSE_BUTTON_LEFT, false, motion.position)
			await _render_frames()
			_expect(not camera.transform.is_equal_approx(initial),
				"Dragging the Gallery viewer must orbit " + id)
			_gallery_mouse(MOUSE_BUTTON_WHEEL_UP, true, center)
			_gallery_mouse(MOUSE_BUTTON_WHEEL_UP, false, center)
			await _render_frames()
			_expect(float(stage.get("_zoom")) > 1.0,
				"Scrolling over the Gallery viewer must magnify " + id)
			_gallery_mouse(MOUSE_BUTTON_LEFT, true, center, true)
			_gallery_mouse(MOUSE_BUTTON_LEFT, false, center)
			await _render_frames()
			_expect(camera.transform.is_equal_approx(initial),
				"Double-click must restore the reference car's default framing.")
			await _capture("gallery-menu-%s-%dx%d" % [id, dimensions.x, dimensions.y])
	gallery.free()


func _gallery_mouse(
	button: MouseButton, pressed: bool, at: Vector2, double_click := false
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.global_position = at
	event.double_click = double_click
	root.push_input(event, true)


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


func _test_rendered_brakes(stage: int) -> void:
	var view := _game.get("_view") as View
	var car: Cube = view.world.car
	var state: State = _game.get("_state")
	var saved_damage := state.damage_stage
	state.damage_stage = stage
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
		"Stage %d braking must visibly brighten the rendered red lenses, not only a material property."
		% stage)
	car.apply_state(state, true, 0.0, false, true)
	await _render_frames()
	_test_draw_budget()
	await _capture("brakes-on" if stage == 0 else "damage-%d-brakes-on" % stage)
	car.apply_state(state, false)
	state.damage_stage = saved_damage
	view.world_camera.transform = saved_transform
	view.world_camera.size = saved_size
	view.present(0.0)


func _test_damage_looks() -> void:
	var view := _game.get("_view") as View
	var state: State = _game.get("_state")
	var reduced := view.reduced_motion
	var intense := view.intense_effects
	view.set_reduced_motion(true)
	view.set_intense_effects(false)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
		get_root().size = dimensions
		state.damage_stage = 0
		view.present(0.0)
		await _render_frames()
		var scale := Vector2(view.world_viewport.size) / view.size
		var bounds := view.car_screen_bounds()
		var crop := Rect2i(Rect2(bounds.position * scale, bounds.size * scale).grow(8.0))
		crop = crop.intersection(Rect2i(Vector2i.ZERO, view.world_viewport.size))
		var previous: Image
		var sheet := Image.create(crop.size.x * State.DAMAGE_NAMES.size(), crop.size.y,
			false, Image.FORMAT_RGBA8)
		for stage in State.DAMAGE_NAMES.size():
			state.damage_stage = stage
			view.present(0.0)
			await _render_frames()
			var image := view.world_viewport.get_texture().get_image().get_region(crop)
			image.convert(Image.FORMAT_RGBA8)
			if previous != null:
				var changed := 0
				for y in image.get_height():
					for x in image.get_width():
						if _color_difference(image.get_pixel(x, y),
							previous.get_pixel(x, y)) > 0.12:
							changed += 1
				_expect(changed >= maxi(12, floori(crop.get_area() * 0.006)),
					"Damage stage %d must visibly differ from %d at %s: only %d changed car pixels."
					% [stage, stage - 1, dimensions, changed])
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()),
				Vector2i(stage * crop.size.x, 0))
			previous = image
			_test_draw_budget()
			await _capture("damage-%d-%dx%d" % [stage, dimensions.x, dimensions.y])
		if not _capture_dir.is_empty():
			var path := _capture_dir.path_join("damage-stages-%dx%d.png"
				% [dimensions.x, dimensions.y])
			_expect(sheet.save_png(path) == OK, "Could not save the damage comparison strip.")
	state.damage_stage = 0
	get_root().size = Vector2i(1280, 720)
	view.set_reduced_motion(reduced)
	view.set_intense_effects(intense)
	view.present(0.0)
	await _render_frames()


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
	var hud_pixels: Array[Rect2] = []
	var hud := _game.get("_trial_hud") as TrialHUD
	for child: Control in hud.bar.find_children("*", "Control", true, false):
		if child is PanelContainer or child is Button:
			# Rounded transparent corners reveal scenery; sample the opaque HUD interior.
			var rect := child.get_global_rect().grow(-6.0 * float(_game.get("_ui_factor")))
			hud_pixels.append(Rect2(rect.position * ratio, rect.size * ratio))
	for y in range(0, sharp.get_height(), 2):
		for x in range(0, sharp.get_width(), 2):
			var difference := _color_difference(sharp.get_pixel(x, y), blurred.get_pixel(x, y))
			if car_pixels.has_point(Vector2(x, y)) and difference >= 0.012:
				changed_car += 1
			if difference < 0.015:
				continue
			var in_hud := false
			for rect in hud_pixels:
				in_hud = in_hud or rect.has_point(Vector2(x, y))
			if in_hud or not world_pixels.has_point(Vector2(x, y)):
				changed_hud += 1
			else:
				changed_world += 1
	_expect(changed_world > 80 and changed_hud == 0,
		"The shader must blur scenery while leaving HUD content untouched (%d world / %d HUD pixels)."
		% [changed_world, changed_hud])
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
	await _test_damaged_headlights(view)
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


func _test_damaged_headlights(view: View) -> void:
	var state: State = _game.get("_state")
	var saved_damage := state.damage_stage
	for stage in range(1, State.DAMAGE_NAMES.size()):
		state.damage_stage = stage
		view.present(0.0)
		await _render_frames()
		var on := view.world_viewport.get_texture().get_image()
		await _capture("damage-%d-night" % stage)
		for light in view.world.car.headlights:
			light.visible = false
		await _render_frames()
		var off := view.world_viewport.get_texture().get_image()
		_expect(_brighter_pixels(on, off) > 20,
			"Stage %d headlights must still illuminate the road from their displaced sockets." % stage)
	state.damage_stage = saved_damage
	view.present(0.0)
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
