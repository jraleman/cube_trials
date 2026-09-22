extends GameShell

## One original physics trial, inside the reusable navigation and results shell.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const CourseView = preload("res://games/cube_trials/course_view.gd")
const DriveControls = preload("res://games/cube_trials/drive_controls.gd")
const TrialHUD = preload("res://games/cube_trials/trial_hud.gd")
const CubeAudio = preload("res://games/cube_trials/cube_audio.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")

var _state := State.new()
var _view: CourseView
var _controls: DriveControls
var _trial_hud: TrialHUD
var _bottom_stack: VBoxContainer
var _audio_caption: Control
var _engine: AudioStreamPlayer
var _cues: Dictionary[String, AudioStreamWAV] = {}
var _engine_enabled := true
var _day_night_enabled := true
var _air_control := 1.0
var _feedback_text := ""
var _feedback_left := 0.0
var _paint_id := ""
var _rim_id := ""
var _ui_factor := 1.0
var _layout_pending := false
var _camera_key := ""
var _jump_pending := false


func _ready() -> void:
	AudioManager.stop_music(0.2)
	super()


## GameCatalog discovers the folder; no framework branch knows this id.
func game_id() -> String:
	return Options.GAME_ID


func _prepare_session() -> void:
	GameSession.configure_single_player()
	super()


func _load_round_settings() -> void:
	super()
	_air_control = Settings.tunable(Options.AIR_CONTROL_KEY)
	_engine_enabled = Settings.tunable_bool(Options.ENGINE_AUDIO_KEY)
	_day_night_enabled = Settings.tunable_bool(Options.DAY_NIGHT_KEY)
	_paint_id = Store.equipped_id(Options.GAME_ID, Options.PAINT_SLOT)
	_rim_id = Store.equipped_id(Options.GAME_ID, Options.RIM_SLOT)


## The garage can be visited from the pause menu, so a car that was resprayed
## mid-run comes back wearing the new coat rather than waiting for a restart.
func _apply_finish() -> void:
	if _view == null:
		return
	_paint_id = Store.equipped_id(Options.GAME_ID, Options.PAINT_SLOT)
	_rim_id = Store.equipped_id(Options.GAME_ID, Options.RIM_SLOT)
	_view.set_finish(_paint_id, _rim_id)


func _build_playfield() -> void:
	_view = CourseView.new()
	_view.name = "CopperCreek"
	_playfield.add_child(_view)
	_view.set_reduced_motion(_reduced_motion_enabled)
	_view.set_intense_effects(_intense_effects_enabled)
	_view.set_day_night_enabled(_day_night_enabled)
	var overlay := _hud.get_node("Overlay") as Control
	_bottom_stack = VBoxContainer.new()
	_bottom_stack.name = "DrivingBar"
	_bottom_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_bottom_stack)
	_audio_caption = _hud.get_node("Overlay/Margins/Layout/AudioCaption") as Control
	_audio_caption.reparent(_bottom_stack, false)
	_audio_caption.custom_minimum_size = Vector2.ZERO
	_audio_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_caption.add_theme_stylebox_override("panel",
		_audio_caption.get_theme_stylebox("panel").duplicate())
	_audio_caption.visibility_changed.connect(_queue_layout)
	_bottom_stack.resized.connect(_queue_layout)
	_bottom_stack.minimum_size_changed.connect(_queue_layout)
	_controls = DriveControls.new()
	_controls.name = "DriveControls"
	_bottom_stack.add_child(_controls)
	_controls.recovery_requested.connect(_recover)
	_controls.jump_requested.connect(_queue_jump)
	_trial_hud = TrialHUD.new()
	_trial_hud.name = "TrialHUD"
	overlay.add_child(_trial_hud)
	_trial_hud.attach_pause(_pause_button)
	_controls.attach_camera_button(_trial_hud.camera_button)
	_controls.camera_requested.connect(_cycle_camera)
	(_hud.get_node("Overlay/Margins") as Control).hide()
	_engine = AudioStreamPlayer.new()
	_engine.name = "CubeEngine"
	_engine.bus = "SFX"
	_engine.volume_db = -17.0
	if DisplayServer.get_name() != "headless":
		_engine.stream = CubeAudio.engine()
		_cues = CubeAudio.cues()
	add_child(_engine)
	get_viewport().size_changed.connect(_resize_layout)
	_configure_mode_ui()
	_resize_layout()


func _reset_round_state() -> void:
	_state = State.new()
	_jump_pending = false
	_state.air_control = _air_control
	_feedback_left = 0.0
	_feedback_text = ""
	_controls.set_enabled(true)
	var device := _controller_device()
	if _strength(Options.JUMP) > 0.0 \
		or (device >= 0 and Input.is_joy_button_pressed(device, JOY_BUTTON_A)):
		_state.clear_jump_input()
	_apply_finish()
	_view.set_day_night_enabled(_day_night_enabled)
	_view.configure(_state)
	_engine.stop()
	_sync_hud()


func _activate_round() -> void:
	_announcement.hide()
	get_viewport().gui_release_focus()
	_feedback("5 lives. Jump, collect, park.")


func _update_round(delta: float, _time_left: float) -> void:
	if not _round_active or get_tree().paused or Router.is_transitioning():
		return
	var drive := _strength(Options.THROTTLE) - _strength(Options.REVERSE)
	var tilt := _strength(Options.NOSE_DOWN) - _strength(Options.NOSE_UP)
	var brake := _strength(Options.BRAKE)
	var jump := _jump_pending or _strength(Options.JUMP) > 0.0
	_jump_pending = false
	var device := _controller_device()
	if device >= 0:
		var stick := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(stick) > 0.18:
			tilt = clampf(tilt + stick, -1.0, 1.0)
		drive = clampf(drive
			+ maxf(0.0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT))
			- maxf(0.0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)), -1.0, 1.0)
		jump = jump or Input.is_joy_button_pressed(device, JOY_BUTTON_A)
		if Input.is_joy_button_pressed(device, JOY_BUTTON_B):
			brake = 1.0
	_state.advance(delta, drive, brake, tilt, jump)
	_view.braking = brake > 0.0
	_feedback_left = maxf(0.0, _feedback_left - delta)
	for event in _state.take_events():
		var kind: String = event["kind"]
		_feedback(event["text"], kind)
		if kind == "crash" or kind == "damage":
			_view.world.car.play_impact()
		elif kind == "jump":
			_view.world.car.play_jump()
		if kind == "crash":
			_jump_pending = false
			_controls.clear_input()
			if _state.lives_left == 0:
				_controls.set_enabled(false)
	_scores[PLAYER_ONE] = _state.score()
	_sync_hud()
	_view.present(delta)
	_update_engine(drive)
	if _state.is_over():
		_end_round()


func _strength(action: StringName) -> float:
	return maxf(Input.get_action_strength(action), _controls.strength(action))


func _controller_device() -> int:
	return GameSession.controller_device_for_player(PLAYER_ONE)


func _handle_gameplay_input(event: InputEvent) -> void:
	if get_tree().paused or event.is_echo():
		return
	if event.is_action_pressed(Options.CAMERA):
		get_viewport().set_input_as_handled()
		_cycle_camera()
	elif event.is_action_pressed(Options.RECOVER):
		get_viewport().set_input_as_handled()
		_recover()
	elif event.is_action_pressed(Options.JUMP):
		get_viewport().set_input_as_handled()
		_queue_jump()
	elif event is InputEventJoypadButton and event.pressed \
		and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B] \
		and event.device == _controller_device():
		get_viewport().set_input_as_handled()
		if event.button_index == JOY_BUTTON_A:
			_queue_jump()
	elif event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_RIGHT_STICK \
		and event.device == _controller_device():
		get_viewport().set_input_as_handled()
		_cycle_camera()
	elif event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_Y \
		and event.device == _controller_device():
		get_viewport().set_input_as_handled()
		_recover()
	else:
		for action in Options.DRIVE_ACTIONS:
			if event.is_action(action):
				get_viewport().set_input_as_handled()
				return


func _queue_jump() -> void:
	if _round_active and not get_tree().paused and not Router.is_transitioning() \
		and _state.crash_wait == 0.0 and not _state.is_over():
		_jump_pending = true


func _recover() -> void:
	if not _round_active or get_tree().paused or Router.is_transitioning():
		return
	_state.recover()
	_state.clear_jump_input()
	_jump_pending = false
	_controls.clear_input()
	_view.braking = false
	_view.present(0.0)
	_sync_hud()


func _cycle_camera() -> void:
	if not _round_active or get_tree().paused or Router.is_transitioning() or _state.lives_left == 0:
		return
	_view.cycle_camera()
	get_viewport().gui_release_focus()
	_feedback("%s view" % _view.camera_name(), "camera")


## Clear local touch ownership before the shell pauses the scene tree.
func open_pause_menu() -> void:
	_state.clear_jump_input()
	_jump_pending = false
	if _controls != null:
		_controls.clear_input()
	super()


func _on_pause_closed() -> void:
	super()
	_apply_finish()
	if _round_active:
		get_viewport().gui_release_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_state.clear_jump_input()
		_jump_pending = false
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _round_active:
		open_pause_menu()


func _finish_round() -> void:
	_jump_pending = false
	_state.clear_jump_input()
	if _controls != null:
		_controls.set_enabled(false)
	if _engine != null:
		_engine.stop()
	if _view != null:
		_view.braking = false
		_view.world.car.reset_motion()
		_view.present(0.0)


func _configure_mode_ui() -> void:
	super()
	_time_progress.hide()
	_round_instructions.text = "Five lives. Find a cleaner line."
	_share_card_hint.text = "Save your Copper Creek run and challenge a friend."
	var labels := {}
	for binding in Options.CONTROL_BINDINGS:
		labels[binding["action"]] = Settings.control_key_label(binding["action"])
	_camera_key = labels[Options.CAMERA]
	if _controls != null:
		_controls.set_key_labels(labels)
	_sync_hud()


func _sync_hud() -> void:
	if _trial_hud != null:
		_trial_hud.sync(_state, _feedback_text if _feedback_left > 0.0 else "")
		_trial_hud.set_camera_hint(_view.camera_name(), _camera_key)


func _feedback(text: String, cue := "") -> void:
	_feedback_text = text
	match cue:
		"plug":
			_feedback_text = "+1000"
		"checkpoint":
			_feedback_text = "Checkpoint saved"
		"recover":
			_feedback_text = "Recovered / +5s"
		"crash":
			_feedback_text = "-1 life / +5s" if _state.lives_left > 0 else "No lives left"
		"damage":
			_feedback_text = "Hard landing"
		"jump":
			_feedback_text = "Jump!"
		"notice":
			_feedback_text = "Collect missing plugs" if _state.plug_count() < 5 else "Brake to park"
		"finish":
			_feedback_text = "Delivered!"
		"out":
			_feedback_text = "Out of lives"
	_feedback_left = 1.2 if cue in ["camera", "jump"] else 2.5
	_sync_hud()
	AudioManager.request_caption(text)
	if _cues.has(cue) and DisplayServer.get_name() != "headless":
		AudioManager.play_sfx(_cues[cue], -7.0)


func _update_engine(drive: float) -> void:
	var should_play := DisplayServer.get_name() != "headless" and _engine_enabled \
		and _state.started and not _state.is_over() and _state.crash_wait == 0.0
	if not should_play:
		_engine.stop()
		return
	_engine.pitch_scale = 0.85 + absf(_state.velocity.x) / 450.0 + absf(drive) * 0.25
	if not _engine.playing:
		_engine.play()


func _round_length_seconds() -> float:
	return _state.adjusted_time()


func _round_mode_summary() -> String:
	return "Solo / Copper Creek / %d lives" % State.STARTING_LIVES


func _describe_round_outcome(_one: int, _two: int) -> Dictionary:
	if _state.failed:
		return {
			"result": "OUT OF LIVES",
			"subtitle": "%d of 5 plugs collected. Your points are kept; try a cleaner line." \
				% _state.plug_count(),
			"color": Color("ff8b82"),
		}
	if not _state.finished:
		return {
			"result": "TRIAL STOPPED",
			"subtitle": "The garage is still waiting. No completion medal was earned.",
			"color": Art.CREAM,
		}
	return {
		"result": "%s / HOME IN ONE PIECE" % _state.medal(),
		"subtitle": "%s including %d recovery penalties. All five spark plugs delivered." % [
			State.time_text(_state.adjusted_time()), _state.recoveries,
		],
		"color": Art.COPPER,
	}


func _award_round_achievements(_one: int, _two: int) -> void:
	if not _state.finished:
		return
	_unlock_round_achievement("cube_trials_home")
	if _state.recoveries == 0:
		_unlock_round_achievement("cube_trials_clean")
	if _state.medal() == "GOLD":
		_unlock_round_achievement("cube_trials_gold")


func _best_combo_summary() -> String:
	return "%d / 5 plugs / %d recoveries / longest jump %.2fs" % [
		_state.plug_count(), _state.recoveries, _state.longest_air,
	]


func _round_totals() -> Dictionary:
	return {"hits": _state.plug_count(), "attempts": 5}


func _player_stats(player: int) -> Dictionary:
	return {
		"score": _scores[player],
		"hits": _state.plug_count() if player == PLAYER_ONE else 0,
		"misses": _state.recoveries if player == PLAYER_ONE else 0,
		"accuracy": _state.plug_count() * 20 if player == PLAYER_ONE else 0,
		"streak": 0,
	}


func _share_payload() -> Dictionary:
	var data := super()
	data["score_caption"] = "TRIAL POINTS"
	data["hits_caption"] = "SPARK PLUGS"
	data["accuracy_caption"] = "DELIVERED"
	data["combo_caption"] = "RECOVERIES"
	data["combo"] = str(_state.recoveries)
	data["combo_value"] = _state.recoveries
	data["misses_value"] = _state.recoveries
	data["challenge"] = "A VERY UNREASONABLE COMMUTE"
	data["paint_id"] = _paint_id
	data["rim_id"] = _rim_id
	data["damage_stage"] = _state.damage_stage
	data["lives_left"] = _state.lives_left
	data["failed"] = _state.failed
	data["rematch_title"] = "FIVE PLUGS. ONE LITTLE CUBE."
	data["rematch_copy"] = "%s / %s / Can you find a cleaner line?" % [
		"OUT OF LIVES" if _state.failed else _state.medal(),
		State.time_text(_state.adjusted_time()),
	]
	return data


func _set_reduced_motion_enabled(value: bool) -> void:
	super(value)
	if _view != null:
		_view.set_reduced_motion(value)


func _set_intense_effects_enabled(value: bool) -> void:
	super(value)
	if _view != null:
		_view.set_intense_effects(value)


func _spawn_round_confetti(color: Color) -> void:
	if _state.finished and _intense_effects_enabled:
		super(color)


func _on_game_setting_changed(key: String, _value: Variant) -> void:
	if key == Options.AIR_CONTROL_KEY:
		_air_control = Settings.tunable(Options.AIR_CONTROL_KEY)
		_state.air_control = _air_control
	elif key == Options.ENGINE_AUDIO_KEY:
		_engine_enabled = Settings.tunable_bool(Options.ENGINE_AUDIO_KEY)
		if not _engine_enabled and _engine != null:
			_engine.stop()
	elif key == Options.DAY_NIGHT_KEY:
		_day_night_enabled = Settings.tunable_bool(Options.DAY_NIGHT_KEY)
		if _view != null:
			_view.set_day_night_enabled(_day_night_enabled)
	elif key == "ui/scale":
		_resize_layout()


func _resize_layout() -> void:
	if _controls == null:
		return
	var dimensions := get_viewport_rect().size
	_ui_factor = maxf(1.0, dimensions.x / maxf(get_window().size.x, 1.0) / 1.5)
	var width := _playfield_bounds().size.x
	_bottom_stack.size.x = width
	_bottom_stack.add_theme_constant_override("separation", roundi(8 * _ui_factor))
	var caption_label := _audio_caption.get_node("CaptionLabel") as Label
	caption_label.add_theme_font_size_override("font_size", roundi(22 * _ui_factor))
	var caption_style := _audio_caption.get_theme_stylebox("panel") as StyleBoxFlat
	caption_style.content_margin_left = 20 * _ui_factor
	caption_style.content_margin_right = 20 * _ui_factor
	caption_style.content_margin_top = 8 * _ui_factor
	caption_style.content_margin_bottom = 8 * _ui_factor
	_controls.fit_width(width, _ui_factor)
	_queue_layout()


func _queue_layout() -> void:
	if not _layout_pending and is_inside_tree():
		_layout_pending = true
		_layout_course.call_deferred()


func _playfield_bounds() -> Rect2:
	var dimensions := get_viewport_rect().size
	var inset := Vector2.ONE * 12 * _ui_factor
	return Rect2(inset, (dimensions - inset * 2.0).max(Vector2.ONE))


func _layout_course() -> void:
	_layout_pending = false
	if _view == null or _controls == null or not is_inside_tree():
		return
	var bounds := _playfield_bounds()
	var controls_height := _bottom_stack.get_combined_minimum_size().y
	_bottom_stack.position = Vector2(bounds.position.x, bounds.end.y - controls_height)
	_bottom_stack.size = Vector2(bounds.size.x, controls_height)
	_view.position = bounds.position
	_view.size = Vector2(bounds.size.x, maxf(1, bounds.size.y - controls_height - 12 * _ui_factor))
	_trial_hud.position = bounds.position + Vector2.ONE * 12 * _ui_factor
	_trial_hud.fit_width(bounds.size.x - 24 * _ui_factor, _ui_factor)
	_sync_hud()
	_view.present(0.0)
