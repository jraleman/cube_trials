extends SceneTree

## Forward-facing views require actual rendered cockpit, framing and visibility checks.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const View = preload("res://games/cube_trials/course_view.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const MODES := [View.CameraMode.SIDE, View.CameraMode.CHASE, View.CameraMode.COCKPIT]

var _failures := PackedStringArray()
var _capture_dir := ""
var _game: Node
var _view: View
var _peak_draws := 0
var _peak_triangles := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("cube_trials_camera_test requires a graphics window, not --headless.")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cube-capture-dir="):
			_capture_dir = argument.trim_prefix("--cube-capture-dir=")
	if not _capture_dir.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
		if error != OK:
			printerr("Could not create camera capture directory: ", error_string(error))
			quit(1)
			return
	var settings := get_root().get_node("Settings")
	var original_values := (settings.get("_values") as Dictionary).duplicate(true)
	var save_timer := settings.get("_save_timer") as Timer
	var timer_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	settings.call("set_value", "ui/scale", 1.0)
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	settings.call("set_value", Options.AIR_CONTROL_KEY, 1.0)
	GameCatalog.restrict_to(Options.GAME_ID)
	get_root().theme = GameCatalog.theme().restyle(ThemeDB.get_project_theme())
	_game = (load("res://games/cube_trials/gameplay.tscn") as PackedScene).instantiate()
	get_root().add_child(_game)
	_game.set_process(false)
	_view = _game.get("_view") as View
	var state: State = _game.get("_state")
	state.advance(0.5, 0, 0, 0)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(2560, 720)]:
		get_root().size = dimensions
		for mode in MODES:
			_view.set_camera_mode(mode)
			_view.present(0.0)
			_game.call("_sync_hud")
			await _render()
			_check_view()
			await _capture("camera-start-%s-%dx%d" % [_view.camera_name(), dimensions.x, dimensions.y])
		await _test_cockpit_damage()
	get_root().size = Vector2i(1280, 720)
	await _test_cockpit_jumping()
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	_view.set_reduced_motion(false)
	_view.set_day_night_enabled(false)
	var next_sample := 450.0
	for frame in 60 * 60:
		Driver.hold_controls(state)
		_game.call("_update_round", 1.0 / 60.0, 0.0)
		if state.position.x >= next_sample and not state.is_over():
			Driver.release_controls()
			for mode in [View.CameraMode.CHASE, View.CameraMode.COCKPIT]:
				_view.set_camera_mode(mode)
				for settle in 12:
					_view.present(1.0 / 60.0)
				await _render()
				_check_view()
			next_sample += 150.0
		for index in Course.gap_intervals().size():
			var gap := Course.gap_intervals()[index]
			var middle := (gap.x + gap.y) * 0.5
			if state.position.x >= middle and state.position.x < middle + 15.0:
				_view.set_camera_mode(View.CameraMode.CHASE)
				await _render()
				_check_view()
				var landing := Art.world_point(
					Vector2(gap.y + 140.0, Course.ground_height(gap.y + 140.0)))
				_expect(not _view.world_camera.is_position_behind(landing)
					and Rect2(Vector2.ZERO, _view.size).has_point(_view.project_point(landing)),
					"The chase view must show the landing during every actual gap crossing.")
				await _capture("camera-gap-%d-Chase" % index)
		if state.position.x >= Course.FINISH_X - 80.0:
			Driver.release_controls()
			break
	Driver.release_controls()
	_expect(state.position.x >= Course.FINISH_X - 80.0
		and state.recoveries == 0 and state.lives_left == 5,
		"The real route must remain drivable while switching cameras repeatedly.")
	await _test_parking_and_night()
	_game.free()
	settings.set("_values", original_values)
	save_timer.stop()
	save_timer.process_mode = timer_mode
	GameCatalog.clear_restriction()
	await process_frame
	await create_timer(0.15).timeout
	print("Camera rendering budget: %d draws / %d triangles." % [_peak_draws, _peak_triangles])
	if _failures.is_empty():
		print("Cube Trials camera rendering tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_cockpit_damage() -> void:
	var state: State = _game.get("_state")
	_view.set_camera_mode(View.CameraMode.COCKPIT)
	for stage in State.DAMAGE_NAMES.size():
		state.damage_stage = stage
		_view.present(0.0)
		await _render()
		_check_view()
		_expect(_cockpit_forward_clear(),
			"The %s cockpit eye must see through the windshield, not opaque roof or dashboard geometry."
			% State.DAMAGE_NAMES[stage])
		await _capture("camera-cockpit-damage-%d-%dx%d" % [
			stage, get_root().size.x, get_root().size.y,
		])
	state.damage_stage = 0
	_view.present(0.0)


func _test_cockpit_jumping() -> void:
	_view.set_camera_mode(View.CameraMode.COCKPIT)
	_view.set_reduced_motion(false)
	for stage in State.DAMAGE_NAMES.size():
		_game.call("_on_play_again_pressed")
		var state: State = _game.get("_state")
		state.damage_stage = stage
		Input.action_press(Options.JUMP)
		for frame in 90:
			_game.call("_update_round", 1.0 / 60.0, 0.0)
			Input.action_release(Options.JUMP)
			if frame in [0, 6, 54, 62, 70, 80]:
				await _render()
				_check_view()
				_expect(_cockpit_forward_clear(),
					"The %s cockpit must remain clear during takeoff and landing (frame %d)."
					% [State.DAMAGE_NAMES[stage], frame])
				if stage in [0, State.MAX_DAMAGE_STAGE] and frame in [0, 62, 70]:
					await _capture("camera-jump-stage-%d-frame-%d" % [stage, frame])
		_expect(state.contacts == 2 and state.recoveries == 0 and state.damage_stage == stage,
			"Every damage stage must retain a clean, controllable jump and landing in Cockpit view.")


func _cockpit_forward_clear() -> bool:
	var eye := _view.world_camera.global_position
	var ahead := eye - _view.world_camera.global_basis.z * 4.0
	for part in ["BrownBodywork", "CabinAndDriver", "RubberTrimAndUnderbody"]:
		var mesh := _view.world.car.chassis.get_node(part) as MeshInstance3D
		var start := mesh.to_local(eye)
		var finish := mesh.to_local(ahead)
		var vertices := mesh.mesh.get_faces()
		for index in range(0, vertices.size(), 3):
			if Geometry3D.segment_intersects_triangle(start, finish,
				vertices[index], vertices[index + 1], vertices[index + 2]) != null:
				return false
	return true


func _test_parking_and_night() -> void:
	_view.set_reduced_motion(false)
	_view.set_day_night_enabled(true)
	_view.daylight_time = (0.75 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
		get_root().size = dimensions
		for mode in [View.CameraMode.CHASE, View.CameraMode.COCKPIT]:
			_view.set_camera_mode(mode)
			_view.present(0.0)
			await _render()
			_check_view()
			_expect((_view.get("_parking_hint_bounds") as Rect2).has_area()
				and _view.world.car.headlights[0].visible,
				"Forward-facing parking must retain the visible callout and automatic headlights at night.")
			var image := _view.world_viewport.get_texture().get_image()
			var luminance := 0.0
			var samples := 0
			for y in range(image.get_height() / 3, image.get_height() * 2 / 3, 4):
				for x in range(image.get_width() / 3, image.get_width() * 2 / 3, 4):
					luminance += image.get_pixel(x, y).get_luminance()
					samples += 1
			_expect(luminance / samples > 0.035,
				"The night road must stay readable through the cockpit and chase views.")
			await _capture("camera-night-%s-%dx%d" % [_view.camera_name(), dimensions.x, dimensions.y])
	_view.set_camera_mode(View.CameraMode.SIDE)
	await _render()
	_expect(not _view.world.daylight.environment.fog_enabled
		and _view.world_camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"Returning from night cockpit must restore the original side projection without leftover haze.")


func _check_view() -> void:
	var viewport := _view.world_viewport
	var draws := viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var triangles := viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	_peak_draws = maxi(_peak_draws, draws)
	_peak_triangles = maxi(_peak_triangles, triangles)
	_expect(draws > 10 and draws <= 200 and triangles > 1000 and triangles < 120000,
		"%s at x=%.0f (%s) exceeds the render budget: %d draws / %d triangles."
		% [_view.camera_name(), _view.state.position.x, get_root().size, draws, triangles])
	_expect(_view.world_camera.transform.is_finite(), "Camera transforms must remain finite.")
	if _view.camera_mode != View.CameraMode.COCKPIT:
		var bounds := _view.car_screen_bounds()
		var scale := float(get_root().size.x) / get_root().get_visible_rect().size.x
		_expect(Rect2(Vector2.ZERO, _view.size).encloses(bounds) and bounds.size.x * scale >= 48.0,
			"%s must frame the full car at %s, x=%.0f."
			% [_view.camera_name(), get_root().size, _view.state.position.x])
	else:
		_expect(_view.world.car.chassis.visible
			and (_view.world.car.chassis.get_node("CabinAndDriver") as Node3D).visible
			and _view.world.car.global_position.distance_to(_view.world_camera.global_position) < 2.0,
			"First person must use the real cabin at the driver's seat, not hide the car or use a hood camera.")
	_expect((_view.get_node("WorldImage") as TextureRect).material == null,
		"Perspective driving and fresh camera cuts must not retain the side-view blur shader.")


func _render() -> void:
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw


func _capture(title: String) -> void:
	if not _capture_dir.is_empty():
		var error := get_root().get_texture().get_image().save_png(_capture_dir.path_join(title + ".png"))
		_expect(error == OK, "Could not save camera capture: %s." % title)


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
