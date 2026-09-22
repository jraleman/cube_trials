extends SceneTree

## Rebinding, multitouch, live assists and a real finish through GameShell.
## Use an isolated user profile: the genuine finish intentionally awards achievements.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const GAME := "res://games/cube_trials/gameplay.tscn"

var _failures := PackedStringArray()
var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings := get_root().get_node("Settings")
	var original_values := (settings.get("_values") as Dictionary).duplicate(true)
	var save_timer := settings.get("_save_timer") as Timer
	var timer_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	var original_id := GameCatalog.current_id()
	GameCatalog.select(Options.GAME_ID)
	var manifest := GameCatalog.current()
	_expect(manifest != null and not manifest.uses_shell_round_rules
		and not manifest.supports_multiplayer and not manifest.supports_cpu_opponent,
		"Cube Trials must declare its own ending and solo-only controls.")
	_expect(ResourceLoader.exists(manifest.intro_scene_path)
		and ResourceLoader.exists(manifest.tutorial_poster_path)
		and ResourceLoader.exists(manifest.share_art_scene_path),
		"The intro, picker poster and game-owned share illustration must all exist.")
	var pause_on_start := false
	for event in InputMap.action_get_events(&"pause"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START:
			pause_on_start = true
	_expect(pause_on_start, "The documented Start button must match the shared pause binding.")
	_expect(ProjectSettings.get_setting("dcs/build/single_game_id.cube_trials") == Options.GAME_ID
		and ProjectSettings.get_setting("application/config/custom_user_dir_name.cube_trials")
			== "DeskCanSaw Games/Cube Trials",
		"A tagged standalone build must have its own stable save directory.")
	_game = (load(GAME) as PackedScene).instantiate()
	get_root().add_child(_game)
	_game.set_process(false)
	await process_frame
	await process_frame
	_expect(not bool(_game.get("_uses_shell_round_rules")) and not bool(_game.get("_lives_mode"))
		and (_game.get_node("%RoundTimer") as Timer).is_stopped(),
		"The shared countdown and lives pool must not run during the trial.")
	await _test_rebinding(settings)
	_test_multitouch_and_pause()
	_test_brake_inputs()
	_test_day_night_settings(settings)
	_test_live_accessibility(settings)
	_test_real_finish()
	_game.call("_on_play_again_pressed")
	var replay: State = _game.get("_state")
	_expect(not replay.finished and replay.plug_count() == 0 and replay.checkpoint == 0
		and replay.elapsed == 0.0 and replay.recoveries == 0,
		"Replay must reset time, pickups, checkpoint and penalties together.")
	var controls: Node = _game.get("_controls")
	_expect(not (controls.get("buttons")[Options.THROTTLE] as Button).disabled,
		"Replay must re-enable controls disabled by the finish.")
	Driver.release_controls()
	_game.free()
	for voice: AudioStreamPlayer in get_root().get_node("AudioManager").get("_sfx_pool"):
		voice.stop()
	settings.set("_values", original_values)
	save_timer.stop()
	save_timer.process_mode = timer_mode
	GameCatalog.select(original_id)
	await process_frame
	await create_timer(0.15).timeout
	if _failures.is_empty():
		print("Cube Trials scene tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_rebinding(settings: Node) -> void:
	var key := "controls/cube_trials_throttle"
	var original_key: int = settings.call("binding_keycode", key)
	settings.call("set_binding_key", key, KEY_T, Options.GAME_ID)
	var controls: Node = _game.get("_controls")
	var throttle: Button = controls.get("buttons")[Options.THROTTLE]
	_expect(throttle.text.ends_with("\nT"), "The pedal hint must reflect live rebinding.")
	var event := InputEventKey.new()
	event.keycode = KEY_T
	event.physical_keycode = KEY_T
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var state: State = _game.get("_state")
	var start := state.position.x
	for frame in 45:
		_game.call("_update_round", 1.0 / 60.0, 0.0)
	_expect(state.position.x > start + 80.0 and state.started,
		"The newly rebound physical key must accelerate the actual car.")
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	settings.call("set_binding_key", key, original_key, Options.GAME_ID)
	await process_frame
	_expect(not Input.is_action_pressed(Options.THROTTLE),
		"Releasing the physical key must release the registered throttle action.")


func _test_multitouch_and_pause() -> void:
	var controls: Node = _game.get("_controls")
	var buttons: Dictionary = controls.get("buttons")
	var throttle: Button = buttons[Options.THROTTLE]
	var nose: Button = buttons[Options.NOSE_UP]
	_touch(0, throttle.get_global_rect().get_center(), true)
	_touch(1, nose.get_global_rect().get_center(), true)
	_expect(float(controls.call("strength", Options.THROTTLE)) == 1.0
		and float(controls.call("strength", Options.NOSE_UP)) == 1.0,
		"Two fingers must hold throttle and tilt at the same time.")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(-30, -30)
	get_root().push_input(drag, true)
	_expect(float(controls.call("strength", Options.THROTTLE)) == 0.0
		and float(controls.call("strength", Options.NOSE_UP)) == 1.0,
		"Dragging off one pedal releases only that finger's control.")
	_touch(0, Vector2(-30, -30), false)
	var state: State = _game.get("_state")
	var before := state.position
	var clock := state.adjusted_time()
	paused = true
	_game.call("_update_round", 2.0, 0.0)
	_expect(state.position == before and state.adjusted_time() == clock,
		"Pause must freeze both vehicle physics and the race clock.")
	_expect(float(controls.call("strength", Options.NOSE_UP)) == 0.0,
		"Pause must discard all touch ownership, even without a release event.")
	paused = false
	_touch(1, nose.get_global_rect().get_center(), false)
	var recover_button: Button = buttons[Options.RECOVER]
	var old_recoveries := state.recoveries
	_touch(2, recover_button.get_global_rect().get_center(), true)
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.position = recover_button.get_global_rect().get_center()
	emulated.pressed = true
	get_root().push_input(emulated, true)
	emulated.pressed = false
	get_root().push_input(emulated, true)
	_touch(2, recover_button.get_global_rect().get_center(), false)
	_expect(state.recoveries == old_recoveries + 1,
		"Mouse emulation must not charge a touch recovery twice.")


func _test_day_night_settings(settings: Node) -> void:
	_game.call("_on_play_again_pressed")
	_game.call("_set_reduced_motion_enabled", false)
	settings.call("set_value", Options.DAY_NIGHT_KEY, true)
	var view: Node = _game.get("_view")
	var state: State = _game.get("_state")
	var world: Node = view.get("world")
	view.call("present", 2.0)
	_expect(is_zero_approx(float(view.get("daylight_time"))),
		"The day/night cycle must wait for the first driving input, like the trial clock.")
	Input.action_press(Options.THROTTLE)
	_game.call("_update_round", 0.1, 0.0)
	Input.action_release(Options.THROTTLE)
	_expect(float(view.get("daylight_time")) > 0.0,
		"Real driving must start the optional day/night presentation clock.")
	var before: float = view.get("daylight_time")
	paused = true
	_game.call("_update_round", 2.0, 0.0)
	view.call("present", 2.0)
	_expect(is_equal_approx(float(view.get("daylight_time")), before),
		"Neither the round loop nor a direct paused redraw may advance the sun.")
	settings.call("set_value", Options.DAY_NIGHT_KEY, false)
	var lights: Daylight = world.get("daylight")
	_expect(not bool(view.get("day_night_enabled"))
		and is_zero_approx(float(view.get("daylight_time")))
		and lights.sky_material.sky_top_color.is_equal_approx(Daylight.DAY_TOP),
		"The live setting must restore fixed afternoon light even while paused.")
	paused = false
	settings.call("set_value", Options.DAY_NIGHT_KEY, true)
	_game.call("_set_intense_effects_enabled", false)
	var midnight := (0.75 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS
	view.call("present", midnight)
	_expect(is_equal_approx(float(view.get("daylight_time")), midnight)
		and is_equal_approx(lights.night_amount, 1.0),
		"Disabling intense effects must not disable the optional, gentle lighting cycle.")
	_game.call("_recover")
	_expect(is_equal_approx(float(view.get("daylight_time")), midnight),
		"A recovery penalty must not skip the sun forward by five seconds.")
	_game.call("_set_reduced_motion_enabled", true)
	view.call("present", 5.0)
	_expect(is_zero_approx(float(view.get("daylight_time")))
		and is_zero_approx(lights.night_amount),
		"Reduced motion must immediately park the sky in daylight and keep it there.")
	_game.call("_set_reduced_motion_enabled", false)
	view.call("present", Daylight.CYCLE_SECONDS * 2.0 + 3.0)
	_expect(is_equal_approx(float(view.get("daylight_time")), 3.0),
		"The presentation clock must wrap rather than grow indefinitely during a long run.")
	state.finished = true
	view.call("present", 5.0)
	_expect(is_equal_approx(float(view.get("daylight_time")), 3.0),
		"Results must freeze the lighting along with the trial clock.")
	_game.call("_on_play_again_pressed")
	_expect(is_zero_approx(float(view.get("daylight_time")))
		and is_zero_approx(lights.night_amount),
		"Replay must restart in afternoon light, not inherit the last run's night.")


func _test_live_accessibility(settings: Node) -> void:
	settings.call("set_value", Options.AIR_CONTROL_KEY, 1.4)
	var state: State = _game.get("_state")
	_expect(is_equal_approx(state.air_control, 1.4), "Air control must update the live chassis.")
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	_expect(not (_game.get("_engine") as AudioStreamPlayer).playing,
		"The live engine toggle must immediately silence the loop.")
	_game.call("_set_reduced_motion_enabled", true)
	_game.call("_set_intense_effects_enabled", false)
	var view: Node = _game.get("_view")
	var start := state.position
	Input.action_press(Options.THROTTLE)
	_game.call("_update_round", 0.2, 0.0)
	Input.action_release(Options.THROTTLE)
	_expect(bool(_game.get("_reduced_motion_enabled")) and bool(view.get("reduced_motion"))
		and float(view.get("ambient_time")) == 0.0 and state.position != start,
		"Reduced motion parks scenery and dust, not driving or suspension.")
	_expect(not bool(_game.get("_intense_effects_enabled"))
		and not bool(view.get("intense_effects")),
		"Both the shell and trail must receive the intense-effects setting.")
	settings.call("set_value", Options.AIR_CONTROL_KEY, 1.0)


func _test_brake_inputs() -> void:
	var view: Node = _game.get("_view")
	var world: Node = view.get("world")
	var car: Node = world.get("car")
	_game.call("_set_reduced_motion_enabled", false)
	_game.call("_set_intense_effects_enabled", true)
	Input.action_press(Options.BRAKE)
	for frame in 15:
		_game.call("_update_round", 1.0 / 60.0, 0.0)
	_expect(float(car.get("brake_level")) > 0.99,
		"The registered keyboard/gamepad brake action must animate the actual rear lamps.")
	Input.action_release(Options.BRAKE)
	for frame in 40:
		_game.call("_update_round", 1.0 / 60.0, 0.0)
	_expect(float(car.get("brake_level")) < 0.001,
		"Releasing real brake input must let the lamps finish fading.")
	var controls: Node = _game.get("_controls")
	var button: Button = controls.get("buttons")[Options.BRAKE]
	_touch(3, button.get_global_rect().get_center(), true)
	_game.call("_update_round", 0.2, 0.0)
	_expect(float(car.get("brake_level")) > 0.98,
		"The mobile brake pedal must use the same live rear-light animation.")
	_touch(3, button.get_global_rect().get_center(), false)
	_game.call("_set_reduced_motion_enabled", true)
	Input.action_press(Options.BRAKE)
	_game.call("_update_round", 1.0 / 60.0, 0.0)
	_expect(is_equal_approx(float(car.get("brake_level")), 1.0),
		"Reduced motion must retain immediate, input-driven brake feedback.")
	Input.action_release(Options.BRAKE)
	_game.call("_on_play_again_pressed")
	_expect(not bool(view.get("braking")) and is_zero_approx(float(car.get("brake_level"))),
		"Replay must clear brake state and emission rather than carry it into the next run.")


func _test_real_finish() -> void:
	_game.call("_on_play_again_pressed")
	var state: State = _game.get("_state")
	for frame in 60 * 90:
		Driver.hold_controls(state)
		_game.call("_update_round", 1.0 / 60.0, 0.0)
		if state.finished:
			break
	Driver.release_controls()
	_expect(state.finished and not bool(_game.get("_round_active")),
		"A real input-driven finish must end the shared round exactly once.")
	_expect(state.recoveries == 0 and state.medal() == "GOLD",
		"The scene's input driver must produce a genuinely clean gold run.")
	_expect((_game.get_node("%RoundOver") as Control).visible
		and (_game.get_node("%ResultLabel") as Label).text.contains("HOME IN ONE PIECE"),
		"The finish must reach the shared results rather than a parallel game UI.")
	_expect((_game.get_node("%PlayerOneStatsScore") as Label).text == str(state.score())
		and (_game.get_node("%PlayerOneStatsMisses") as Label).text == str(state.recoveries),
		"Shared stats must report the actual score and recovery count.")
	var payload: Dictionary = _game.call("_share_payload")
	_expect(payload["game_id"] == Options.GAME_ID and payload["hits_value"] == 5
		and payload["misses_value"] == state.recoveries
		and str(payload["score"]) == str(state.score()),
		"Sharing must carry this trial's results and identity.")
	var achievements := get_root().get_node("AchievementManager")
	for id in ["cube_trials_home", "cube_trials_clean", "cube_trials_gold"]:
		_expect(bool(achievements.call("is_unlocked", id)),
			"The clean gold run must award its declared achievement: %s." % id)
	var before := state.adjusted_time()
	_game.call("_update_round", 3.0, 0.0)
	_expect(state.adjusted_time() == before, "Results cannot keep spending race time.")


func _touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	get_root().push_input(event, true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
