extends SceneTree

## Rebinding, multitouch, live assists and a real finish through GameShell.
## Use an isolated user profile: the genuine finish intentionally awards achievements.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const Course = preload("res://games/cube_trials/course.gd")
const View = preload("res://games/cube_trials/course_view.gd")
const Portrait = preload("res://games/cube_trials/share_art.gd")
const TrialHUD = preload("res://games/cube_trials/trial_hud.gd")
const GAME := "res://games/cube_trials/gameplay.tscn"

var _failures := PackedStringArray()
var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	get_root().size = Vector2i(1280, 720)
	var settings := get_root().get_node("Settings")
	var original_values := (settings.get("_values") as Dictionary).duplicate(true)
	var save_timer := settings.get("_save_timer") as Timer
	var timer_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	var original_id := GameCatalog.current_id()
	GameCatalog.select(Options.GAME_ID)
	var manifest := GameCatalog.current()
	_expect(manifest != null and not manifest.uses_shell_round_rules
		and manifest.supports_multiplayer and not manifest.supports_cpu_opponent
		and manifest.max_local_players == 3 and manifest.local_multiplayer_turns,
		"Cube Trials must declare its own ending and up to three human hot-seat drivers.")
	get_root().get_node("GameSession").call("configure_single_player")
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
	_game.set_script(load("res://games/cube_trials/tests/input_gameplay_fixture.gd"))
	get_root().add_child(_game)
	_game.set_process(false)
	await process_frame
	await process_frame
	_expect(not bool(_game.get("_uses_shell_round_rules")) and not bool(_game.get("_lives_mode"))
		and (_game.get_node("%RoundTimer") as Timer).is_stopped(),
		"The shared countdown and lives pool must not run during the trial.")
	_test_compact_hud()
	await _test_rebinding(settings)
	await _test_camera_controls(settings)
	_test_multitouch_and_pause()
	await _test_jump_inputs(settings)
	await _test_hazard_inputs(settings)
	await _test_gamepad_jump_and_brake()
	await _test_flip_inputs()
	_test_brake_inputs()
	_test_day_night_settings(settings)
	_test_live_accessibility(settings)
	_test_damage_lifecycle()
	_test_life_loss()
	await _test_real_finish()
	_game.call("_on_play_again_pressed")
	var replay: State = _game.get("_state")
	_expect(not replay.finished and replay.plug_count() == 0 and replay.checkpoint == 0
		and replay.elapsed == 0.0 and replay.recoveries == 0 and replay.damage_stage == 0
		and replay.lives_left == State.STARTING_LIVES and not replay.failed
		and replay.landed_flips == 0 and replay.flip_points == 0 and replay.pending_flips == 0
		and replay.jump_points == 0 and replay.hazard_points == 0
		and not replay.hazards_on and not replay.hazard_bonus,
		"Replay must reset time, pickups, checkpoint, penalties, damage and lives together.")
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


func _test_compact_hud() -> void:
	var hud := _game.get("_trial_hud") as TrialHUD
	_expect(hud.lives_label.text == "5" and hud.points_label.text == "0"
		and hud.plugs_label.text == "0/5",
		"The in-view HUD must show actual lives, points and plug progress separately.")
	_expect(not (_game.get_node("%Callout") as Control).is_visible_in_tree()
		and not (_game.get_node("%Hint") as Control).is_visible_in_tree()
		and (_game.get_node("%PauseButton") as Button).icon != null,
		"Gameplay must replace the persistent header and instruction blocks with an icon HUD.")
	_game.call("_update_round", 2.6, 0.0)
	_expect(not hud.feedback_label.is_visible_in_tree(),
		"Brief feedback must disappear instead of reverting to a permanent wall of instructions.")
	var state: State = _game.get("_state")
	state.collected[0] = true
	_game.call("_update_round", 0.0, 0.0)
	_expect(hud.points_label.text == "1000" and hud.plugs_label.text == "1/5"
		and hud.lives_label.accessibility_name.contains("5 lives"),
		"Icon counters need real score values and meaningful screen-reader descriptions.")
	_game.call("_on_play_again_pressed")


func _test_rebinding(settings: Node) -> void:
	var key := "controls/cube_trials_throttle"
	var original_key: int = settings.call("binding_keycode", key)
	settings.call("set_binding_key", key, KEY_T, Options.GAME_ID)
	var controls: Node = _game.get("_controls")
	var throttle: Button = controls.get("buttons")[Options.THROTTLE]
	controls.call("fit_width", 1400.0, 1.0)
	_expect(throttle.text == "T" and throttle.tooltip_text.contains("(T)") and throttle.icon != null,
		"The wide-screen pedal and its accessible hint must reflect live rebinding.")
	controls.call("fit_width", 540.0, 1.0)
	_expect(throttle.text.is_empty() and throttle.accessibility_name.contains("(T)"),
		"Phone pedals must keep rebound keys accessible without adding visible instruction text.")
	_game.call("_resize_layout")
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


func _test_camera_controls(settings: Node) -> void:
	_game.call("_on_play_again_pressed")
	await process_frame
	var view := _game.get("_view") as View
	var hud := _game.get("_trial_hud") as TrialHUD
	var state: State = _game.get("_state")
	var controls: Node = _game.get("_controls")
	_expect(view.camera_mode == View.CameraMode.SIDE and hud.camera_button.icon != null,
		"New games must start in Side view with a camera icon rather than a permanent mode label.")
	var original: int = settings.call("binding_keycode", "controls/cube_trials_camera")
	settings.call("set_binding_key", "controls/cube_trials_camera", KEY_V, Options.GAME_ID)
	_expect(hud.camera_button.accessibility_name.contains("V / R3"),
		"Rebinding the camera key must immediately update its accessible HUD hint.")
	var key := InputEventKey.new()
	key.keycode = KEY_V
	key.physical_keycode = KEY_V
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	_expect(view.camera_mode == View.CameraMode.CHASE and not state.started and state.elapsed == 0.0,
		"The rebound key must switch the real camera without starting the driving clock.")
	key.echo = true
	Input.parse_input_event(key)
	await process_frame
	_expect(view.camera_mode == View.CameraMode.CHASE, "Holding the camera key must not cycle every repeat.")
	key.echo = false
	key.pressed = false
	Input.parse_input_event(key)
	settings.call("set_binding_key", "controls/cube_trials_camera", original, Options.GAME_ID)
	var throttle: Button = controls.get("buttons")[Options.THROTTLE]
	_touch(5, throttle.get_global_rect().get_center(), true)
	var point := hud.camera_button.get_global_rect().get_center()
	_touch(6, point, true)
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.position = point
	emulated.pressed = true
	get_root().push_input(emulated, true)
	emulated.pressed = false
	get_root().push_input(emulated, true)
	_touch(6, point, false)
	_expect(view.camera_mode == View.CameraMode.COCKPIT
		and float(controls.call("strength", Options.THROTTLE)) == 1.0,
		"A second finger must change view once without double-firing or releasing the held pedal.")
	_touch(5, throttle.get_global_rect().get_center(), false)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.pressed = true
	get_root().push_input(mouse, true)
	var draw_mode := hud.camera_button.get_draw_mode()
	mouse.pressed = false
	get_root().push_input(mouse, true)
	_expect(view.camera_mode == View.CameraMode.SIDE,
		"A real mouse click must cycle Cockpit back to Side (mode %s, draw %s, button %s, viewport %s)."
		% [view.camera_name(), draw_mode, hud.camera_button.get_global_rect(), get_root().get_visible_rect()])
	view.set_camera_mode(View.CameraMode.CHASE)
	paused = true
	_game.call("_cycle_camera")
	_expect(view.camera_mode == View.CameraMode.CHASE, "Pause must gate camera selection along with driving.")
	paused = false
	_game.call("_recover")
	_game.call("_on_play_again_pressed")
	_expect(view.camera_mode == View.CameraMode.CHASE and not hud.camera_button.disabled
		and hud.camera_button.accessibility_name.contains("Chase"),
		"Recovery and replay must preserve the selected view and re-enable its button.")
	var foreign_pad := InputEventJoypadButton.new()
	foreign_pad.device = 999
	foreign_pad.button_index = JOY_BUTTON_RIGHT_STICK
	foreign_pad.pressed = true
	_game.call("_handle_gameplay_input", foreign_pad)
	_expect(view.camera_mode == View.CameraMode.CHASE,
		"A controller not assigned to the driver cannot switch the camera.")
	view.set_camera_mode(View.CameraMode.SIDE)
	_game.call("_on_play_again_pressed")
	await process_frame


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


func _test_jump_inputs(settings: Node) -> void:
	_game.call("_on_play_again_pressed")
	_game.call("_set_reduced_motion_enabled", false)
	await process_frame
	var controls: Node = _game.get("_controls")
	var button: Button = controls.get("buttons")[Options.JUMP]
	var state: State = _game.get("_state")
	var view := _game.get("_view") as View
	for binding in Options.CONTROL_BINDINGS:
		if binding["action"] == Options.JUMP:
			_expect(binding["default"] == KEY_SPACE, "Space must be the new default jump key.")
		elif binding["action"] == Options.BRAKE:
			_expect(binding["default"] == KEY_SHIFT, "Brake must move to Shift, not share Space.")
	var original: int = settings.call("binding_keycode", "controls/cube_trials_jump")
	settings.call("set_binding_key", "controls/cube_trials_jump", KEY_J, Options.GAME_ID)
	_expect(button.icon != null and button.accessibility_name.contains("JUMP (J)"),
		"The new touch control must have an icon and an accessible, live rebound key hint.")
	_key(KEY_J, true)
	await process_frame
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.started and state.contacts == 0 and state.velocity.y < -490.0
		and float(view.world.car.get("_jump_time")) < 0.1 and not view.braking,
		"A rebound physical jump key must launch and animate the car without applying the brake.")
	_key(KEY_J, false)
	await process_frame
	_game.call("_update_round", 0.2, 0.0)
	var falling := state.velocity.y
	_key(KEY_J, true)
	await process_frame
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.velocity.y > falling, "Pressing the keyboard jump again in midair cannot double-jump.")
	_key(KEY_J, false)
	settings.call("set_binding_key", "controls/cube_trials_jump", original, Options.GAME_ID)
	await process_frame
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	var throttle: Button = controls.get("buttons")[Options.THROTTLE]
	var tilt: Button = controls.get("buttons")[Options.NOSE_UP]
	_touch(10, throttle.get_global_rect().get_center(), true)
	_touch(11, tilt.get_global_rect().get_center(), true)
	var point := button.get_global_rect().get_center()
	_touch(12, point, true)
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.position = point
	emulated.pressed = true
	get_root().push_input(emulated, true)
	emulated.pressed = false
	get_root().push_input(emulated, true)
	_touch(12, point, false)
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.velocity.y < -490.0
		and float(controls.call("strength", Options.THROTTLE)) == 1.0
		and float(controls.call("strength", Options.NOSE_UP)) == 1.0,
		"A short third-finger jump must survive release without stealing throttle or tilt.")
	_touch(10, throttle.get_global_rect().get_center(), false)
	_touch(11, tilt.get_global_rect().get_center(), false)
	for frame in 150:
		_game.call("_update_round", 1.0 / 60.0, 0.0)
	_expect(state.contacts == 2 and state.longest_air > 1.3 and state.longest_air < 1.6
		and state.recoveries == 0,
		"Touch/mouse emulation must trigger only one clean hop.")
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.pressed = true
	get_root().push_input(mouse, true)
	mouse.pressed = false
	get_root().push_input(mouse, true)
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.velocity.y < -490.0,
		"A complete mouse click between updates must still queue one jump.")
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	_touch(12, point, true)
	paused = true
	_game.call("_update_round", 1.0, 0.0)
	paused = false
	_game.call("_update_round", 0.2, 0.0)
	_expect(not state.started and state.contacts == 2
		and float(controls.call("strength", Options.JUMP)) == 0.0,
		"Pause must discard a queued touch jump, including its unreleased contact.")
	_touch(12, point, false)
	_game.call("_queue_jump")
	_game.call("_recover")
	_game.call("_update_round", 0.2, 0.0)
	_expect(state.contacts == 2 and absf(state.velocity.y) < 0.1,
		"Manual recovery must discard an unconsumed jump before the checkpoint is presented.")
	_game.call("_on_play_again_pressed")


func _test_hazard_inputs(settings: Node) -> void:
	_game.call("_on_play_again_pressed")
	await process_frame
	var state: State = _game.get("_state")
	var hud := _game.get("_trial_hud") as TrialHUD
	var controls: Node = _game.get("_controls")
	var button: Button = controls.get("buttons")[Options.HAZARDS]
	_key(KEY_F, true)
	await process_frame
	_game.call("_update_round", 0.3, 0.0)
	_expect(state.hazards_on and not state.started and not state.hazard_bonus
		and button.accessibility_name.contains("ON") and button.icon != null,
		"F must toggle visible, accessible hazards on the ground without starting the clock.")
	var repeated := InputEventKey.new()
	repeated.keycode = KEY_F
	repeated.physical_keycode = KEY_F
	repeated.pressed = true
	repeated.echo = true
	_game.call("_handle_gameplay_input", repeated)
	_expect(state.hazards_on, "Keyboard auto-repeat must not keep toggling hazards.")
	_key(KEY_F, false)
	await process_frame
	_game.call("_queue_jump")
	_game.call("_update_round", 0.3, 0.0)
	_expect(state.is_airborne() and not state.hazard_bonus,
		"A jump cannot inherit a bonus from hazards enabled on the ground.")
	_key(KEY_F, true)
	_key(KEY_F, false)
	await process_frame
	_key(KEY_F, true)
	_key(KEY_F, false)
	await process_frame
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.hazards_on and state.hazard_bonus and hud.feedback_label.text.contains("x1.15")
		and hud.feedback_label.text.contains(str(state.pending_trick_points())),
		"An in-air off/on F press must show the actual unbanked 1.15x jump value.")
	var phase := state.hazard_time
	var points := state.pending_trick_points()
	paused = true
	_game.call("_toggle_hazards")
	_game.call("_update_round", 2.0, 0.0)
	_expect(state.hazards_on and state.hazard_time == phase and state.pending_trick_points() == points,
		"Pause must freeze the blink and pending score, and ignore hazard input.")
	paused = false
	for frame in 150:
		_game.call("_update_round", 1.0 / 60.0, 0.0)
	_expect(state.hazard_points > 0 and state.landed_jumps == 1 and not state.hazard_bonus
		and hud.points_label.text == str(state.score()) and state.hazards_on,
		"An ordinary jump must bank its hazard bonus through the real gameplay loop.")
	var payload: Dictionary = _game.call("_share_payload")
	_expect(payload["jump_points"] == state.jump_points and payload["hazard_points"] == state.hazard_points
		and payload["players"][0]["hazard_points"] == state.hazard_points
		and payload["landed_jumps"] == 1,
		"Share totals and driver details must retain exactly the banked dynamic score.")
	var key := "controls/cube_trials_hazards"
	settings.call("set_binding_key", key, KEY_H, Options.GAME_ID)
	_expect(button.tooltip_text.contains("(H /"), "The hazard button must reflect live rebinding.")
	_key(KEY_F, true)
	_key(KEY_F, false)
	await process_frame
	_expect(state.hazards_on, "The old key must stop toggling after rebinding hazards.")
	_key(KEY_H, true)
	_key(KEY_H, false)
	await process_frame
	_expect(not state.hazards_on, "The rebound key must control the same hazard toggle.")
	settings.call("set_binding_key", key, KEY_F, Options.GAME_ID)
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	await process_frame
	_game.call("_queue_jump")
	_game.call("_update_round", 0.3, 0.0)
	var throttle: Button = controls.get("buttons")[Options.THROTTLE]
	_touch(31, throttle.get_global_rect().get_center(), true)
	_touch(32, button.get_global_rect().get_center(), true)
	_touch(32, button.get_global_rect().get_center(), false)
	_expect(state.hazards_on and state.hazard_bonus
		and float(controls.call("strength", Options.THROTTLE)) == 1.0,
		"Touch must toggle and release hazards without stealing a held throttle finger.")
	_touch(31, throttle.get_global_rect().get_center(), false)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = button.get_global_rect().get_center()
	mouse.pressed = true
	get_root().push_input(mouse, true)
	mouse.pressed = false
	get_root().push_input(mouse, true)
	_expect(not state.hazards_on, "A full mouse click between ticks must toggle hazards exactly once.")
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	_expect(not state.hazards_on and not state.hazard_bonus and state.hazard_points == 0
		and button.accessibility_name.contains("OFF"),
		"Replay must reset both the simulated hazard toggle and its visible button.")


func _test_gamepad_jump_and_brake() -> void:
	var device := 15
	while device >= 0 and Input.get_connected_joypads().has(device):
		device -= 1
	_expect(device >= 0, "The gamepad input test needs an unused virtual controller slot.")
	if device < 0:
		return
	_game.set("test_controller", device)
	_game.call("_on_play_again_pressed")
	var state: State = _game.get("_state")
	var view := _game.get("_view") as View
	_pad(device, JOY_BUTTON_B, true)
	await process_frame
	_game.call("_update_round", 0.2, 0.0)
	_expect(view.braking and view.world.car.brake_level > 0.98 and not state.started,
		"The assigned gamepad's B button must brake, not jump or leave gameplay.")
	_pad(device, JOY_BUTTON_B, false)
	await process_frame
	_game.call("_update_round", 0.3, 0.0)
	_pad(device, JOY_BUTTON_A, true)
	await process_frame
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.velocity.y < -490.0 and not view.braking,
		"The assigned gamepad's A button must jump instead of retaining the old brake action.")
	_pad(device, JOY_BUTTON_X, true)
	await process_frame
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.hazards_on and state.hazard_bonus and bool(_game.call("_inputs_held")),
		"The assigned gamepad's X button must toggle hazards and participate in handoff release gating.")
	_pad(device, JOY_BUTTON_X, false)
	await process_frame
	for frame in 180:
		_game.call("_update_round", 1.0 / 60.0, 0.0)
	_expect(state.contacts == 2 and state.recoveries == 0,
		"Holding gamepad A must not auto-hop after landing.")
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	_game.call("_update_round", 0.3, 0.0)
	_expect(state.contacts == 2 and not state.started,
		"Replay must not turn a still-held gamepad button into a fresh jump.")
	_game.call("_recover")
	_game.call("_update_round", 0.3, 0.0)
	_expect(state.contacts == 2,
		"A held gamepad button must stay suppressed across recovery until released.")
	_pad(device, JOY_BUTTON_A, false)
	await process_frame
	var foreign := InputEventJoypadButton.new()
	foreign.device = 999
	foreign.button_index = JOY_BUTTON_A
	foreign.pressed = true
	_game.call("_handle_gameplay_input", foreign)
	_game.call("_update_round", 0.1, 0.0)
	_expect(state.contacts == 2, "An unassigned gamepad must not queue a jump.")
	foreign.button_index = JOY_BUTTON_X
	_game.call("_handle_gameplay_input", foreign)
	_expect(not state.hazards_on, "An unassigned gamepad must not toggle hazards.")
	_game.set("test_controller", -1)
	_game.call("_on_play_again_pressed")


func _test_flip_inputs() -> void:
	for touch: bool in [false, true]:
		Driver.release_controls()
		_game.call("_on_play_again_pressed")
		await process_frame
		_game.call("_update_round", 0.5, 0.0)
		var state: State = _game.get("_state")
		var hud := _game.get("_trial_hud") as TrialHUD
		var controls: Node = _game.get("_controls")
		var action := Options.NOSE_UP if touch else Options.NOSE_DOWN
		var tilt: Button = controls.get("buttons")[action]
		var jump: Button = controls.get("buttons")[Options.JUMP]
		var saw_pending := false
		for frame in 180:
			if frame in [0, 1]:
				if touch:
					_touch(20, jump.get_global_rect().get_center(), frame == 0)
				elif frame == 0:
					Input.action_press(Options.JUMP)
				else:
					Input.action_release(Options.JUMP)
			if frame in [10, 60]:
				if touch:
					_touch(21, tilt.get_global_rect().get_center(), frame == 10)
				elif frame == 10:
					Input.action_press(action)
				else:
					Input.action_release(action)
			_game.call("_update_round", 1.0 / 60.0, 0.0)
			if state.pending_flips > 0 and not saw_pending:
				saw_pending = true
				_expect(hud.points_label.text == "0" and hud.feedback_label.text.contains(
					"LAND +%d" % state.pending_trick_points()),
					"The live HUD must distinguish a pending trick from banked score.")
				var position := state.position
				var clock := state.elapsed
				paused = true
				_game.call("_update_round", 2.0, 0.0)
				paused = false
				_expect(state.position == position and state.elapsed == clock
					and state.pending_flips == 1 and state.score() == 0,
					"Pause must preserve an unlanded trick without moving, banking or losing it.")
		Driver.release_controls()
		var banked := state.score()
		_expect(saw_pending and state.landed_flips == 1 and state.flip_points == 500
			and state.jump_points > 0 and banked == 500 + state.jump_points
			and hud.points_label.text == str(banked) and state.recoveries == 0
			and hud.points_label.accessibility_name.contains("500 from 1 landed flips"),
			"Touch and keyboard tilt must visibly bank the flip plus its dynamic aerial points.")
		var stats: Dictionary = _game.call("_player_stats", 0)
		var payload: Dictionary = _game.call("_share_payload")
		_expect(stats["score"] == banked and stats["streak"] == 1
			and payload["landed_flips"] == 1 and payload["flip_points"] == 500
			and payload["players"][0]["flip_points"] == 500
			and payload["jump_points"] == state.jump_points
			and payload["players"][0]["jump_points"] == state.jump_points,
			"Driver statistics and share data must include the same banked trick points as the HUD.")
		_game.call("_recover")
		_game.call("_update_round", 0.5, 0.0)
		_expect(state.landed_flips == 1 and hud.points_label.text == str(banked),
			"A real recovery must retain the banked trick in the live HUD.")
		_game.call("_on_play_again_pressed")
		var replay: State = _game.get("_state")
		_expect(replay.landed_flips == 0 and replay.pending_flips == 0 and hud.points_label.text == "0",
			"Replay must clear banked points and pending trick feedback together.")


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
	# A profile that already freed the Sonata still exercises its garage reveal.
	if str(_game.get("_captive_id")).is_empty():
		_game.set("_captive_id", "cube_sonata")
		_game.call("_apply_finish")
	var state: State = _game.get("_state")
	var view := _game.get("_view") as View
	var reveal := view.world.reveal
	_expect(reveal.visible and reveal.door_open == 0.0 and not reveal.car.visible
		and reveal.sign_label.text.contains("HYUNDAI SONATA"),
		"Level 1's closed garage door must name the locked Sonata waiting behind it.")
	for frame in 60 * 90:
		Driver.hold_controls(state)
		_game.call("_update_round", 1.0 / 60.0, 0.0)
		if state.is_over():
			break
	Driver.release_controls()
	_expect(state.finished and not bool(_game.get("_round_active")),
		"A real input-driven finish must end the shared round exactly once.")
	_expect(state.recoveries == 0 and state.medal() == "GOLD",
		"The scene's input driver must produce a genuinely clean gold run.")
	await _test_garage_reveal(view)
	_expect((_game.get_node("%RoundOver") as Control).visible
		and (_game.get_node("%ResultLabel") as Label).text.contains("HOME IN ONE PIECE"),
		"The finish must reach the shared results rather than a parallel game UI.")
	_expect((_game.get_node("%PlayerOneStatsScore") as Label).text == str(state.score())
		and (_game.get_node("%PlayerOneStatsMisses") as Label).text == str(state.recoveries),
		"Shared stats must report the actual score and recovery count.")
	var payload: Dictionary = _game.call("_share_payload")
	_expect(payload["game_id"] == Options.GAME_ID and payload["hits_value"] == 5
		and payload["misses_value"] == state.recoveries
		and payload["damage_stage"] == state.damage_stage
		and str(payload["score"]) == str(state.score()),
		"Sharing must carry this trial's results and identity.")
	var achievements := get_root().get_node("AchievementManager")
	for id in ["cube_trials_home", "cube_trials_clean", "cube_trials_gold"]:
		_expect(bool(achievements.call("is_unlocked", id)),
			"The clean gold run must award its declared achievement: %s." % id)
	var before := state.adjusted_time()
	_game.call("_update_round", 3.0, 0.0)
	_expect(state.adjusted_time() == before, "Results cannot keep spending race time.")


## The first delivery frees the waiting car before the shared results. Pause
## still works, a press carried over from driving cannot skip it, and Skip lands
## on the freed car with the held confetti and captions.
func _test_garage_reveal(view: View) -> void:
	var reveal := view.world.reveal
	var round_over := _game.get_node("%RoundOver") as Control
	var skip := _game.get("_skip_reveal_button") as Button
	var outline := view.world.get("_parking_outline") as Node3D
	_expect(bool(_game.call("is_revealing")) and not round_over.visible and skip.visible
		and not view.world.car.visible and not outline.visible,
		"The first delivery must clear the bay and free the Sonata before the results.")
	var achievements := get_root().get_node("AchievementManager")
	_expect(bool(achievements.call("is_unlocked", Course.COPPER_COMPLETE))
		and not (_game.get("_held_effects") as Array).is_empty(),
		"The unlock must be saved at once while confetti and captions wait for the reveal.")
	await process_frame
	await process_frame
	_expect(get_root().gui_get_focus_owner() == null,
		"Hidden results must not keep keyboard focus during the reveal.")
	_push_action(&"ui_accept")
	_expect(bool(_game.call("is_revealing")),
		"A press carried over from driving must not skip the reveal straight away.")
	_push_action(&"pause")
	var menu: Node = _game.get("_pause_menu")
	_expect(is_instance_valid(menu) and paused, "Pause must still open the menu during the reveal.")
	var clock := view.reveal_time
	_game.call("_process", 1.0)
	_push_action(&"skip")
	_expect(view.reveal_time == clock and bool(_game.call("is_revealing")),
		"A paused reveal must hold its frame and ignore Skip.")
	if is_instance_valid(menu):
		menu.call("resume")
	_game.call("_process", 1.0)
	_expect(view.reveal_time > clock and reveal.door_open > 0.0 and reveal.car.visible,
		"Resuming must continue the reveal as the door rolls up on the waiting car.")
	_push_action(&"skip")
	_expect(not bool(_game.call("is_revealing")) and round_over.visible and not skip.visible
		and reveal.door_open == 1.0 and reveal.bars_sunk == 1.0 and reveal.eyes == 1.0,
		"After a short grace, Skip must land on the freed car behind the results.")
	_expect((_game.get("_held_effects") as Array).is_empty()
		and get_root().gui_get_focus_owner() == _game.get("_play_again_button"),
		"The results must release the held celebration and take keyboard focus.")


func _push_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_root().push_input(event)


func _test_damage_lifecycle() -> void:
	_game.call("_on_play_again_pressed")
	var state: State = _game.get("_state")
	var view := _game.get("_view") as View
	var car := view.world.car
	state.position = Vector2(2860, Course.FALL_Y + 5.0)
	_game.call("_update_round", State.STEP, 0.0)
	_expect(state.damage_stage == 1 and car.damage_stage == 1,
		"A real crash event must update the visible gameplay chassis immediately.")
	paused = true
	_game.call("_update_round", 2.0, 0.0)
	view.present(0.0)
	_expect(state.damage_stage == 1 and car.damage_stage == 1 and state.crash_wait > 0.0,
		"Paused redraws must retain damage without advancing crash or landing state.")
	paused = false
	_game.call("_update_round", 1.0, 0.0)
	_game.call("_recover")
	_expect(state.damage_stage == 1 and car.damage_stage == 1 and state.crash_wait == 0.0,
		"Both automatic and manual checkpoint recovery must retain visible damage.")
	view.set_finish("cube_paint_signal", "cube_rim_graphite")
	_expect(car.damage_stage == 1 and car.paint_id == "cube_paint_signal",
		"Respraying the live car must not silently repair its chassis.")
	_game.call("_apply_finish")
	_expect(car.damage_stage == 1, "Returning from the garage must retain the run's damage.")
	var payload: Dictionary = _game.call("_share_payload")
	var portrait := Portrait.new()
	portrait.configure(payload)
	get_root().add_child(portrait)
	_expect(payload["damage_stage"] == 1 and portrait.model.damage_stage == 1,
		"The share portrait must show the run's damage even when configured before ready.")
	portrait.configure({"damage_stage": 3, "paint_id": "cube_paint_signal"})
	_expect(portrait.model.damage_stage == 3 and portrait.model.paint_id == "cube_paint_signal",
		"A reused share portrait must update damage and paint together.")
	portrait.configure({})
	_expect(portrait.model.damage_stage == 0,
		"An unconfigured/default portrait must not inherit another run's damage.")
	portrait.free()
	_game.call("_on_play_again_pressed")
	var replay: State = _game.get("_state")
	_expect(replay.damage_stage == 0 and car.damage_stage == 0 and view.world.car == car,
		"Replay must restore pristine bodywork on the existing car, not rebuild the scenery.")


func _test_life_loss() -> void:
	_game.call("_on_play_again_pressed")
	_game.call("_set_reduced_motion_enabled", false)
	_game.call("_set_intense_effects_enabled", true)
	var state: State = _game.get("_state")
	var hud := _game.get("_trial_hud") as TrialHUD
	var view := _game.get("_view") as View
	var controls: Node = _game.get("_controls")
	state.collected[0] = true
	for crash in State.STARTING_LIVES:
		state.position = Vector2(2860, Course.FALL_Y + 5.0)
		_game.call("_update_round", State.STEP, 0.0)
		_expect(hud.lives_label.text == str(State.STARTING_LIVES - crash - 1)
			and bool(_game.get("_round_active"))
			and float(view.world.car.get("_impact_time")) < 0.1,
			"A live crash must update the heart counter and animate before recovery or results.")
		if state.lives_left == 0:
			_expect((controls.get("buttons")[Options.THROTTLE] as Button).disabled,
				"The final impact must disable touch input immediately.")
			paused = true
			var clock := state.adjusted_time()
			_game.call("_update_round", 2.0, 0.0)
			_expect(not state.failed and state.adjusted_time() == clock,
				"Pausing during the final impact must freeze its countdown and the clock.")
			paused = false
		_game.call("_update_round", 1.0, 0.0)
	_expect(state.failed and not state.finished and not bool(_game.get("_round_active"))
		and (_game.get_node("%ResultLabel") as Label).text == "OUT OF LIVES"
		and (_game.get_node("%RoundOver") as Control).visible,
		"The fifth crash must reach the shared loss results without falsely delivering the plugs.")
	var mode := view.camera_mode
	_game.call("_cycle_camera")
	_expect(hud.camera_button.disabled and view.camera_mode == mode,
		"Results must disable both the camera button and late camera input.")
	_expect((_game.get_node("%PlayerOneStatsScore") as Label).text == "1000"
		and (_game.get("_round_achievements") as Array).is_empty()
		and _game.get_node("%WorldFX").get_child_count() == 0,
		"A loss keeps collected points but awards no completion achievement or victory confetti.")
	var payload: Dictionary = _game.call("_share_payload")
	_expect(payload["failed"] and payload["lives_left"] == 0
		and payload["damage_stage"] == State.MAX_DAMAGE_STAGE and payload["misses_value"] == 4,
		"Loss sharing must retain the true lives, cosmetic damage and actual recovery count.")
	var clock := state.adjusted_time()
	_game.call("_recover")
	_game.call("_queue_jump")
	_game.call("_update_round", 2.0, 0.0)
	_expect(state.adjusted_time() == clock and state.lives_left == 0
		and not bool(_game.get("_jump_pending")),
		"Gameplay callbacks cannot keep spending time or revive a completed loss.")
	_game.call("_on_play_again_pressed")
	state = _game.get("_state")
	_expect(state.lives_left == 5 and not state.failed and state.damage_stage == 0
		and hud.lives_label.text == "5" and hud.points_label.text == "0"
		and not (controls.get("buttons")[Options.THROTTLE] as Button).disabled,
		"Replay after a loss must reset the heart, score, car and enabled controls together.")


func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	get_root().push_input(event, true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
