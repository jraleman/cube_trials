extends GameShell

## One original physics trial, inside the reusable navigation and results shell.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const CourseView = preload("res://games/cube_trials/course_view.gd")
const DriveControls = preload("res://games/cube_trials/drive_controls.gd")
const CubeAudio = preload("res://games/cube_trials/cube_audio.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")

var _state := State.new()
var _view: CourseView
var _controls: DriveControls
var _engine: AudioStreamPlayer
var _cues: Dictionary[String, AudioStreamWAV] = {}
var _engine_enabled := true
var _air_control := 1.0
var _feedback_text := ""
var _feedback_left := 0.0
var _key_hint := ""
var _paint_id := ""
var _rim_id := ""
var _ui_factor := 1.0
var _layout_pending := false


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
	_controls = DriveControls.new()
	_controls.name = "DriveControls"
	_hud.get_node("Overlay").add_child(_controls)
	_controls.recovery_requested.connect(_recover)
	_engine = AudioStreamPlayer.new()
	_engine.name = "CubeEngine"
	_engine.bus = "SFX"
	_engine.volume_db = -17.0
	if DisplayServer.get_name() != "headless":
		_engine.stream = CubeAudio.engine()
		_cues = CubeAudio.cues()
	add_child(_engine)
	get_viewport().size_changed.connect(_resize_layout)
	(_player_one_card.get_parent() as Control).resized.connect(_queue_layout)
	_callout.item_rect_changed.connect(_queue_layout)
	_hint.item_rect_changed.connect(_queue_layout)
	(_hint.get_parent() as Control).item_rect_changed.connect(_queue_layout)
	var caption := _hud.get_node("Overlay/Margins/Layout/AudioCaption") as Control
	caption.item_rect_changed.connect(_queue_layout)
	caption.visibility_changed.connect(_queue_layout)
	_configure_mode_ui()
	_resize_layout()


func _reset_round_state() -> void:
	_state = State.new()
	_state.air_control = _air_control
	_feedback_left = 0.0
	_feedback_text = ""
	_controls.set_enabled(true)
	_apply_finish()
	_view.configure(_state)
	_engine.stop()
	_sync_hud()


func _activate_round() -> void:
	_announcement.hide()
	get_viewport().gui_release_focus()
	_feedback("Collect five spark plugs, then brake in the garage. The clock starts when you drive.")


func _update_round(delta: float, _time_left: float) -> void:
	if not _round_active or get_tree().paused or Router.is_transitioning():
		return
	var drive := _strength(Options.THROTTLE) - _strength(Options.REVERSE)
	var tilt := _strength(Options.NOSE_DOWN) - _strength(Options.NOSE_UP)
	var brake := _strength(Options.BRAKE)
	var device := GameSession.controller_device_for_player(PLAYER_ONE)
	if device >= 0:
		var stick := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(stick) > 0.18:
			tilt = clampf(tilt + stick, -1.0, 1.0)
		drive = clampf(drive
			+ maxf(0.0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT))
			- maxf(0.0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)), -1.0, 1.0)
		if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
			brake = 1.0
	_state.advance(delta, drive, brake, tilt)
	_view.braking = brake > 0.0
	_feedback_left = maxf(0.0, _feedback_left - delta)
	for event in _state.take_events():
		var kind: String = event["kind"]
		_feedback(event["text"], kind)
		if kind == "crash":
			_controls.clear_input()
			_add_screen_shake(5.0)
	_scores[PLAYER_ONE] = _state.score()
	_sync_hud()
	_view.present(delta)
	_update_engine(drive)
	if _state.finished:
		_end_round()


func _strength(action: StringName) -> float:
	return maxf(Input.get_action_strength(action), _controls.strength(action))


func _handle_gameplay_input(event: InputEvent) -> void:
	if get_tree().paused or event.is_echo():
		return
	if event.is_action_pressed(Options.RECOVER):
		get_viewport().set_input_as_handled()
		_recover()
	elif event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_Y \
		and event.device == GameSession.controller_device_for_player(PLAYER_ONE):
		get_viewport().set_input_as_handled()
		_recover()
	else:
		for action in Options.DRIVE_ACTIONS:
			if event.is_action(action):
				get_viewport().set_input_as_handled()
				return


func _recover() -> void:
	if not _round_active or get_tree().paused or Router.is_transitioning():
		return
	_state.recover()
	_controls.clear_input()
	_view.braking = false
	_view.present(0.0)


## Clear local touch ownership before the shell pauses the scene tree.
func open_pause_menu() -> void:
	if _controls != null:
		_controls.clear_input()
	super()


func _on_pause_closed() -> void:
	super()
	_apply_finish()
	if _round_active:
		get_viewport().gui_release_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _round_active:
		open_pause_menu()


func _finish_round() -> void:
	if _controls != null:
		_controls.set_enabled(false)
	if _engine != null:
		_engine.stop()
	if _view != null:
		_view.braking = false
		_view.present(0.0)


func _configure_mode_ui() -> void:
	super()
	_player_one_caption.text = (
		"P1 / SPARK PLUGS" if Settings.player_labels_enabled() else "SPARK PLUGS"
	)
	_time_caption.text = "TIME + RECOVERY PENALTIES"
	_time_progress.hide()
	_round_instructions.text = "Try a cleaner line. Recoveries add 5 seconds each."
	_share_card_hint.text = "Save your Copper Creek run and challenge a friend."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_hint.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var labels := {}
	for binding in Options.CONTROL_BINDINGS:
		labels[binding["action"]] = Settings.control_key_label(binding["action"])
	_key_hint = "%s / %s drive   |   %s / %s tilt   |   %s brake   |   %s recover" % [
		labels[Options.THROTTLE], labels[Options.REVERSE],
		labels[Options.NOSE_UP], labels[Options.NOSE_DOWN],
		labels[Options.BRAKE], labels[Options.RECOVER],
	]
	if GameSession.gamepad_connected():
		_key_hint += "\nPad: RT / LT drive, left stick tilt, A brake, Y recover, Start pause."
	if _controls != null:
		_controls.set_key_labels(labels)
	_sync_hud()


func _sync_hud() -> void:
	_update_scores()
	_update_streaks()
	_time_label.text = State.time_text(_state.adjusted_time())
	_callout.text = "%s  /  CHECKPOINT %d OF 2  /  %s" % [
		Course.TITLE, _state.checkpoint,
		"BRING ALL 5 PLUGS HOME" if _state.plug_count() < 5 else "BRAKE IN THE GARAGE",
	]
	_hint.text = _feedback_text if _feedback_left > 0.0 else _key_hint


func _update_scores() -> void:
	_player_one_score.text = "%d / 5" % _state.plug_count()


func _update_streaks() -> void:
	_player_one_streak.text = "%d RECOVERIES  /  +%ds" % [
		_state.recoveries, roundi(_state.recoveries * State.RECOVERY_PENALTY),
	]


func _feedback(text: String, cue := "") -> void:
	_feedback_text = text
	_feedback_left = 3.5
	_hint.text = text
	AudioManager.request_caption(text)
	if _cues.has(cue) and DisplayServer.get_name() != "headless":
		AudioManager.play_sfx(_cues[cue], -7.0)


func _update_engine(drive: float) -> void:
	var should_play := DisplayServer.get_name() != "headless" and _engine_enabled \
		and _state.started and not _state.finished and _state.crash_wait == 0.0
	if not should_play:
		_engine.stop()
		return
	_engine.pitch_scale = 0.85 + absf(_state.velocity.x) / 450.0 + absf(drive) * 0.25
	if not _engine.playing:
		_engine.play()


func _round_length_seconds() -> float:
	return _state.adjusted_time()


func _round_mode_summary() -> String:
	return "Solo / Copper Creek / Time trial"


func _describe_round_outcome(_one: int, _two: int) -> Dictionary:
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
	data["rematch_title"] = "FIVE PLUGS. ONE LITTLE CUBE."
	data["rematch_copy"] = "%s / %s / Can you find a cleaner line?" % [
		_state.medal(), State.time_text(_state.adjusted_time()),
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
	if _intense_effects_enabled:
		super(color)


func _on_game_setting_changed(key: String, _value: Variant) -> void:
	if key == Options.AIR_CONTROL_KEY:
		_air_control = Settings.tunable(Options.AIR_CONTROL_KEY)
		_state.air_control = _air_control
	elif key == Options.ENGINE_AUDIO_KEY:
		_engine_enabled = Settings.tunable_bool(Options.ENGINE_AUDIO_KEY)
		if not _engine_enabled and _engine != null:
			_engine.stop()
	elif key == "ui/scale":
		_resize_layout()


func _resize_layout() -> void:
	if _controls == null:
		return
	var dimensions := get_viewport_rect().size
	_ui_factor = maxf(1.0, dimensions.x / maxf(get_window().size.x, 1.0) / 1.5)
	var portrait := dimensions.y > dimensions.x
	var pause_parent := _time_label.get_parent() if portrait else _player_one_card.get_parent()
	if _pause_button.get_parent() != pause_parent:
		_pause_button.reparent(pause_parent, false)
	_pause_button.custom_minimum_size = Vector2(112, 66) * _ui_factor
	var fonts := {
		_player_one_caption: 18, _player_one_score: 44, _player_one_streak: 17,
		_time_label: 44, _time_caption: 15, _mode_title: 23,
		_callout: 17, _hint: 20, _pause_button: 20,
	}
	for label: Control in fonts:
		label.add_theme_font_size_override("font_size", roundi(fonts[label] * _ui_factor))
	for label in [_player_one_caption, _player_one_streak, _time_caption, _callout, _mode_title]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_player_one_card.custom_minimum_size.x = minf(360 * _ui_factor, dimensions.x * 0.37)
	_controls.fit_width(dimensions.x - SIDE_CLEARANCE * 2, _ui_factor)
	_queue_layout()


func _queue_layout() -> void:
	if not _layout_pending and is_inside_tree():
		_layout_pending = true
		_layout_course.call_deferred()


func _playfield_bounds() -> Rect2:
	var dimensions := get_viewport_rect().size
	var top := maxf(TOP_CLEARANCE, _callout.get_global_rect().end.y + 14 * _ui_factor)
	var bottom := (_hint.get_parent() as Control).get_global_rect().position.y \
		- 12 * _ui_factor
	var caption := _hud.get_node("Overlay/Margins/Layout/AudioCaption") as Control
	if caption.visible:
		bottom = minf(bottom, caption.get_global_rect().position.y - 12 * _ui_factor)
	return Rect2(Vector2(SIDE_CLEARANCE, top),
		Vector2(maxf(1, dimensions.x - SIDE_CLEARANCE * 2), maxf(1, bottom - top)))


func _layout_course() -> void:
	_layout_pending = false
	if _view == null or _controls == null or not is_inside_tree():
		return
	var bounds := _playfield_bounds()
	var controls_height := _controls.get_combined_minimum_size().y
	_controls.position = Vector2(bounds.position.x, bounds.end.y - controls_height)
	_controls.size = Vector2(bounds.size.x, controls_height)
	_view.position = bounds.position
	_view.size = Vector2(bounds.size.x, maxf(1, bounds.size.y - controls_height - 12 * _ui_factor))
	_view.present(0.0)
