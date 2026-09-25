extends GameShell

## Three original physics trials, inside the reusable navigation and results shell.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const CourseView = preload("res://games/cube_trials/course_view.gd")
const DriveControls = preload("res://games/cube_trials/drive_controls.gd")
const TrialHUD = preload("res://games/cube_trials/trial_hud.gd")
const CubeAudio = preload("res://games/cube_trials/cube_audio.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Trail = preload("res://games/cube_trials/trail_layout.gd")
const TrailEditor = preload("res://games/cube_trials/trail_editor.gd")
const BUILD_ICON = preload("res://games/cube_trials/assets/icons/build.svg")
## The key or tap that parked the car must not also skip the scene it starts.
const REVEAL_SKIP_GRACE := 0.8
## The results line on a player's own trail, in place of any reward.
const TRAIL_NOTE := "Your own trail: just for fun, no Sparks or awards."

var _state := State.new()
var _course := Course.new()
var _runs: Array[State] = []
var _active_player := 0
var _wait_for_release := false
var _handoff: Control
var _handoff_panel: PanelContainer
var _handoff_title: Label
var _handoff_copy: Label
var _handoff_button: Button
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
var _capture_inset := 0.0
## The locked car behind this level's garage bars, or "" once it has been freed.
var _captive_id := ""
var _holding_results := false
var _held_effects: Array[Callable] = []
var _reveal_clock := 0.0
var _skip_reveal_button: Button
## The Trail Builder's trail, loaded the first time a round drives it.
var _trail: Trail
## This round's built route, or empty on a handcrafted level.
var _route: Dictionary = {}
var _editor: TrailEditor
var _build_button: Button
var _results_build_button: Button


func _ready() -> void:
	AudioManager.stop_music(0.2)
	super()


## GameCatalog discovers the folder; no framework branch knows this id.
func game_id() -> String:
	return Options.GAME_ID


func _prepare_session() -> void:
	if GameSession.player_two_is_cpu():
		push_warning("Cube Trials has human hot-seat drivers, not a CPU opponent.")
		GameSession.configure_multiplayer(GameSession.PlayerTwoController.HUMAN)
	super()


func _load_round_settings() -> void:
	super()
	_air_control = Settings.tunable(Options.AIR_CONTROL_KEY)
	_engine_enabled = Settings.tunable_bool(Options.ENGINE_AUDIO_KEY)
	_day_night_enabled = Settings.tunable_bool(Options.DAY_NIGHT_KEY)
	var level_id := str(GameSession.selected_level().get("id", Course.COPPER))
	_route = {}
	if level_id == Course.CUSTOM:
		if _trail == null:
			_trail = Trail.new()
			_trail.load_file()
		_route = _trail.to_route()
	_course = Course.new(level_id, _route)


## Garage changes apply immediately; hot-seat body paint still identifies the seat.
func _apply_finish() -> void:
	if _view == null:
		return
	_paint_id = Store.equipped_id(Options.GAME_ID, Options.PAINT_SLOTS[_state.vehicle.id])
	_rim_id = Store.equipped_id(Options.GAME_ID, Options.RIM_SLOT)
	_view.set_finish(_paint_id, _rim_id, _driver_color())
	var captive_paint := "" if _captive_id.is_empty() \
		else Store.equipped_id(Options.GAME_ID, Options.PAINT_SLOTS[_captive_id])
	_view.set_captive(_captive_id, captive_paint, _rim_id)


func _build_playfield() -> void:
	_view = CourseView.new(_course)
	_view.name = "TrialCourse"
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
	_controls.hazards_requested.connect(_toggle_hazards)
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
	_build_handoff()
	var choose_level := Button.new()
	choose_level.name = "ChooseLevelButton"
	choose_level.text = "Levels & cars"
	choose_level.custom_minimum_size = _see_score_button.custom_minimum_size
	choose_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choose_level.tooltip_text = "Choose an unlocked level and cars. Play Again keeps this setup."
	choose_level.pressed.connect(_choose_level)
	_see_score_button.get_parent().add_child(choose_level)
	AudioManager.attach_ui_sounds(choose_level)
	_skip_reveal_button = Button.new()
	_skip_reveal_button.name = "SkipRevealButton"
	_skip_reveal_button.text = "Skip"
	_skip_reveal_button.focus_mode = Control.FOCUS_NONE
	_skip_reveal_button.tooltip_text = "Skip the garage scene and show the results."
	_skip_reveal_button.pressed.connect(skip_reveal)
	_skip_reveal_button.hide()
	overlay.add_child(_skip_reveal_button)
	# A solid plate, like the HUD's own buttons, stays readable over the sunlit shop.
	for style_name in ["normal", "hover", "pressed"]:
		var style := _skip_reveal_button.get_theme_stylebox(style_name).duplicate() as StyleBox
		if style is StyleBoxFlat:
			(style as StyleBoxFlat).bg_color = Color("142725").lightened(
				0.10 if style_name == "hover" else 0.0)
		_skip_reveal_button.add_theme_stylebox_override(style_name, style)
	AudioManager.attach_ui_sounds(_skip_reveal_button)
	if _course.is_custom():
		_build_trail_builder(overlay)
	get_viewport().size_changed.connect(_resize_layout)
	_configure_mode_ui()
	_resize_layout()


## The Trail Builder covers the scene until its Play button starts a drive.
## A build button on the HUD and another on the results bring it back.
func _build_trail_builder(overlay: Control) -> void:
	_editor = TrailEditor.new()
	_editor.name = "TrailBuilder"
	_editor.trail = _trail
	_editor.set_reduced_motion(_reduced_motion_enabled)
	_editor.hide()
	overlay.add_child(_editor)
	_editor.play_requested.connect(_play_trail)
	_editor.pause_requested.connect(open_pause_menu)
	AudioManager.attach_ui_sounds(_editor)
	_build_button = Button.new()
	_build_button.name = "BuildButton"
	_build_button.focus_mode = Control.FOCUS_NONE
	_build_button.pressed.connect(_on_build_pressed)
	_trial_hud.add_action(_build_button, BUILD_ICON)
	_build_button.tooltip_text = "Change your trail"
	_build_button.accessibility_name = _build_button.tooltip_text
	AudioManager.attach_ui_sounds(_build_button)
	_results_build_button = Button.new()
	_results_build_button.name = "BuildTrailButton"
	_results_build_button.text = "Build"
	_results_build_button.icon = BUILD_ICON
	_results_build_button.set("icon_max_width", _play_again_button.get("icon_max_width"))
	_results_build_button.tooltip_text = "Change your trail, then drive it again."
	_results_build_button.pressed.connect(_on_build_pressed)
	var actions := _play_again_button.get_parent()
	actions.add_child(_results_build_button)
	actions.move_child(_results_build_button, _play_again_button.get_index() + 1)
	AudioManager.attach_ui_sounds(_results_build_button)


func _reset_round_state() -> void:
	_stop_reveal()
	_runs.clear()
	for player in _active_player_indices():
		var selected := GameSession.character_for_player(player)
		var run := State.new(str(selected.get("id", Profiles.CUBE)), _course.id, _route)
		run.air_control = _air_control
		_runs.append(run)
	_handoff.hide()
	_captive_id = _locked_car()
	_begin_turn(0)


## The car this level's garage holds until the level is first completed, or "".
## A player's own trail never holds one.
func _locked_car() -> String:
	var achievement := _course.completion_achievement()
	if achievement.is_empty():
		return ""
	var vehicle_id := Profiles.freed_by(achievement)
	return "" if AchievementManager.is_unlocked(achievement) else vehicle_id


func _begin_turn(player: int) -> void:
	_active_player = player
	_state = _runs[player]
	_wait_for_release = player > 0
	_jump_pending = false
	_state.air_control = _air_control
	_feedback_left = 0.0
	_feedback_text = ""
	_controls.set_enabled(not _wait_for_release)
	var device := _controller_device()
	if _strength(Options.JUMP) > 0.0 \
		or (device >= 0 and Input.is_joy_button_pressed(device, JOY_BUTTON_A)):
		_state.clear_jump_input()
	_view.set_day_night_enabled(_day_night_enabled)
	_view.configure(_state)
	if not GameSession.is_single_player():
		_view.set_camera_mode(CourseView.CameraMode.SIDE)
	_apply_finish()
	_engine.stop()
	_sync_hud()


func _activate_round() -> void:
	_announcement.hide()
	get_viewport().gui_release_focus()
	_feedback("%s. Five plugs to deliver." % _course.label(), "start")


func _choose_level() -> void:
	if _round_over.visible and not Router.is_transitioning():
		Router.goto("res://scenes/menus/mode_select.tscn")


## A player's own trail opens in the Trail Builder; every drive starts from Play.
func _begin_first_round() -> void:
	if _editor != null:
		_open_builder()
	else:
		super()


func is_building() -> bool:
	return _editor != null and _editor.visible


## Stops any drive without results, since a trail's test drive records nothing,
## and shows the Trail Builder. The scene behind it stops drawing until Play.
func _open_builder() -> void:
	_round_active = false
	_round_timer.stop()
	_finish_round()
	_stop_reveal()
	_reset_motion_fx()
	_clear_world_fx()
	for control: Control in [_round_over, _handoff, _announcement, _bottom_stack, _trial_hud]:
		control.hide()
	_feedback_left = 0.0
	_view.set_rendering(false)
	_editor.open()
	_queue_layout()


func _play_trail() -> void:
	if not is_building() or get_tree().paused or Router.is_transitioning():
		return
	_editor.close()
	_view.set_rendering(true)
	_bottom_stack.show()
	_trial_hud.show()
	_start_round()
	_queue_layout()


func _on_build_pressed() -> void:
	if _editor == null or is_building() or is_revealing() or get_tree().paused \
		or Router.is_transitioning():
		return
	_open_builder()


func _process(delta: float) -> void:
	if _handoff != null and _handoff.visible and _handoff_button.disabled \
		and not _inputs_held():
		_handoff_button.disabled = false
		_handoff_button.grab_focus()
	if is_revealing() and not get_tree().paused and not Router.is_transitioning():
		advance_reveal(delta)
	super(delta)


func _update_round(delta: float, _time_left: float) -> void:
	if not _round_active or get_tree().paused or Router.is_transitioning():
		return
	if _wait_for_release:
		if _inputs_held():
			return
		_wait_for_release = false
		_controls.set_enabled(true)
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
	_scores[_active_player] = _state.score()
	_sync_hud()
	_view.present(delta)
	_update_engine(drive)
	if _state.is_over():
		_finish_turn()


func _strength(action: StringName) -> float:
	return maxf(Input.get_action_strength(action), _controls.strength(action))


func _controller_device() -> int:
	var device := GameSession.controller_device_for_player(_active_player)
	return device if device >= 0 else GameSession.controller_device_for_player(PLAYER_ONE)


func _inputs_held() -> bool:
	for binding: Dictionary in Options.CONTROL_BINDINGS:
		if Input.is_action_pressed(binding["action"]):
			return true
	if Input.is_action_pressed("ui_accept"):
		return true
	var device := _controller_device()
	if device < 0:
		return false
	for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_RIGHT_STICK]:
		if Input.is_joy_button_pressed(device, button):
			return true
	return absf(Input.get_joy_axis(device, JOY_AXIS_LEFT_X)) > 0.18 \
		or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.05 \
		or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.05


func _handle_gameplay_input(event: InputEvent) -> void:
	if get_tree().paused or event.is_echo() or _wait_for_release:
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
	elif event.is_action_pressed(Options.HAZARDS):
		get_viewport().set_input_as_handled()
		_toggle_hazards()
	elif event is InputEventJoypadButton and event.pressed \
		and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X] \
		and event.device == _controller_device():
		get_viewport().set_input_as_handled()
		if event.button_index == JOY_BUTTON_A:
			_queue_jump()
		elif event.button_index == JOY_BUTTON_X:
			_toggle_hazards()
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


func _toggle_hazards() -> void:
	if not _round_active or _wait_for_release or get_tree().paused or Router.is_transitioning():
		return
	_state.toggle_hazards()
	_sync_hud()
	_view.present(0.0)


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
	if _round_active or is_revealing():
		get_viewport().gui_release_focus()
	elif is_building():
		_editor.focus_default()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_state.clear_jump_input()
		_jump_pending = false
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and (_round_active or is_revealing()):
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


func _finish_turn() -> void:
	_scores[_active_player] = _state.score()
	if _active_player == _runs.size() - 1:
		_end_round()
		return
	_round_active = false
	_finish_round()
	var next := _active_player + 1
	_handoff_title.text = "%s / %s" % [
		_player_name(next).to_upper(), _runs[next].vehicle.title.to_upper(),
	]
	_handoff_title.add_theme_color_override("font_color", _player_color(next))
	_handoff_copy.text = "%s: %s\n\nPass the controls. The next driver starts with five lives, " \
		% [_player_name(_active_player), _run_description(_state)] \
		+ "fresh cargo and their own checkpoints.\nRelease the driving controls, then start your turn."
	_handoff_button.text = "Start %s" % _player_name(next)
	_handoff_button.accessibility_description = _handoff_title.text + ". " + _handoff_copy.text
	_handoff_button.disabled = true
	_handoff.show()
	AudioManager.request_caption(_handoff_title.text + ". Pass the controls.")


func _start_next_turn() -> void:
	if not _handoff.visible or _handoff_button.disabled or _round_active:
		return
	_handoff.hide()
	_begin_turn(_active_player + 1)
	_round_active = true
	_activate_round()


## The first delivery to a garage that still holds a car frees it on screen
## before the results. Replays, Level 3 and runs that never reached the garage
## go straight to the results, exactly as before.
func _end_round() -> void:
	var finished := false
	for run in _runs:
		finished = finished or run.finished
	_holding_results = finished and not _captive_id.is_empty()
	super()
	if not _holding_results:
		return
	if not AchievementManager.is_unlocked(_course.completion_achievement()):
		_release_results()
		return
	_round_over.hide()
	# The shell queues focus for Play Again; a hidden button must not take Enter.
	get_viewport().gui_release_focus.call_deferred()
	_reveal_clock = 0.0
	_view.start_reveal()
	_skip_reveal_button.show()
	_queue_layout()


## Steps the garage reveal. Tests drive it here because their games do not process.
func advance_reveal(delta: float) -> void:
	if not is_revealing():
		return
	_reveal_clock += maxf(delta, 0.0)
	for cue in _view.advance_reveal(delta):
		_play_reveal_cue(cue)
	if _view.reveal_complete():
		_end_reveal()


## Lands on the freed car's final pose and shows the results straight away.
func skip_reveal() -> void:
	if not is_revealing():
		return
	_view.skip_reveal()
	_end_reveal()


func is_revealing() -> bool:
	return _view != null and _view.is_revealing()


func _play_reveal_cue(cue: String) -> void:
	var title := Profiles.new(_captive_id).title
	match cue:
		"door":
			AudioManager.request_caption("The garage door rattles open.")
		"bars":
			AudioManager.request_caption("Iron bars sink into the floor.")
		"horn":
			AudioManager.request_caption("Beep beep! The %s is free." % title)
			_feedback_text = "%s FREED!" % title.to_upper()
			_feedback_left = 1.0
			_sync_hud()
	if _cues.has(cue):
		AudioManager.play_sfx(_cues[cue], -7.0)


func _end_reveal() -> void:
	if not _holding_results:
		return
	_view.finish_reveal()
	_skip_reveal_button.hide()
	_round_over.show()
	_score_panel.hide()
	_round_panel.show()
	_animate_modal_panel(_round_panel)
	_play_again_button.grab_focus()
	_release_results()


## Confetti, fanfare and unlock captions wait for the reveal instead of covering it.
func _after_reveal(effect: Callable) -> void:
	if _holding_results:
		_held_effects.append(effect)
	else:
		effect.call()


func _release_results() -> void:
	_holding_results = false
	var effects := _held_effects.duplicate()
	_held_effects.clear()
	for effect: Callable in effects:
		effect.call()


func _stop_reveal() -> void:
	_holding_results = false
	_held_effects.clear()
	if _skip_reveal_button != null:
		_skip_reveal_button.hide()


func _celebrate_level_unlock(title: String) -> void:
	if _holding_results:
		_held_effects.append(_celebrate_level_unlock.bind(title))
		return
	super(title)


## Pause still opens the menu. Any other press after a short grace skips.
func _unhandled_input(event: InputEvent) -> void:
	if not is_revealing() or event.is_action_pressed("pause"):
		super(event)
		return
	get_viewport().set_input_as_handled()
	if event.is_echo() or _reveal_clock < REVEAL_SKIP_GRACE or get_tree().paused:
		return
	if event.is_action_pressed("skip") or event.is_action_pressed("ui_accept") \
		or event.is_action_pressed(Options.JUMP):
		skip_reveal()


func _build_handoff() -> void:
	_handoff = Control.new()
	_handoff.name = "HotSeatHandoff"
	_hud.add_child(_handoff)
	_handoff.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("10211b", 0.92)
	_handoff.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_handoff.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_handoff_panel = PanelContainer.new()
	center.add_child(_handoff_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("243c32")
	style.set_corner_radius_all(18)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	_handoff_panel.add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	_handoff_panel.add_child(layout)
	_handoff_title = Label.new()
	_handoff_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_handoff_title)
	_handoff_copy = Label.new()
	_handoff_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_handoff_copy)
	_handoff_button = Button.new()
	_handoff_button.pressed.connect(_start_next_turn)
	layout.add_child(_handoff_button)
	_handoff.hide()
	AudioManager.attach_ui_sounds(_handoff)


func _driver_color() -> Color:
	return Color.TRANSPARENT if GameSession.is_single_player() else _player_color(_active_player)


func _configure_mode_ui() -> void:
	super()
	_time_progress.hide()
	_round_instructions.text = "Five lives. Find a cleaner line." if GameSession.is_single_player() \
		else "Fastest adjusted finish wins. Play again restarts every turn."
	var duration_caption := _game_duration_stat.get_parent().get_node("Caption") as Label
	duration_caption.text = "TIME + PENALTIES" if GameSession.is_single_player() else "LEADING DRIVER TIME"
	_share_card_hint.text = "Save your %s run and challenge a friend." % _course.title
	var labels := {}
	for binding in Options.CONTROL_BINDINGS:
		labels[binding["action"]] = Settings.control_key_label(binding["action"])
	_camera_key = labels[Options.CAMERA]
	if _controls != null:
		_controls.set_key_labels(labels)
	for player in _active_player_indices():
		var stats := player_stats_panel(player).get_node("Layout/Stats")
		(stats.get_node("HitsCaption") as Label).text = "Spark plugs"
		(stats.get_node("MissesCaption") as Label).text = "Recoveries (+5s)"
		(stats.get_node("AccuracyCaption") as Label).text = "Collected"
		(stats.get_node("StreakCaption") as Label).text = "Landed flips"
		(stats.get_node("StreakCaption") as Control).show()
		(stats.get_child(7) as Control).show()
	if _build_button != null:
		# One driver must not rebuild the trail in the middle of a hot-seat match.
		_build_button.visible = GameSession.is_single_player()
	_sync_hud()


func _sync_hud() -> void:
	if _controls != null:
		_controls.set_hazards(_state.hazards_on)
	if _trial_hud != null:
		_trial_hud.sync(_state, _feedback_text if _feedback_left > 0.0 else "")
		_trial_hud.set_camera_hint(_view.camera_name(), _camera_key)
		var driver := _state.vehicle.title
		if not GameSession.is_single_player():
			driver = "P%d / %s" % [_active_player + 1, driver]
		driver = "%s\n%s" % [_state.course.short_label(), driver]
		_trial_hud.set_driver(driver, Art.CREAM if GameSession.is_single_player() else _driver_color())


func _feedback(text: String, cue := "") -> void:
	_feedback_text = text
	match cue:
		"start":
			_feedback_text = "Five plugs to deliver"
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
		"flip":
			_feedback_text = ""
		"hazards":
			_feedback_text = "Hazards ON" if _state.hazards_on else "Hazards OFF"
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
	return _representative_run().adjusted_time()


func _round_mode_summary() -> String:
	return "%s / %s / %d lives" % [
		"Solo" if GameSession.is_single_player() else GameSession.mode_title(),
		_course.label(), State.STARTING_LIVES,
	]


func _describe_round_outcome(_one: int, _two: int) -> Dictionary:
	if not GameSession.is_single_player():
		var order := _standings()
		var best: int = order[0]
		var leaders := PackedStringArray()
		for player in order:
			if _runs[player].finished and _same_rank(player, best):
				leaders.append(_player_name(player).to_upper())
		var lines := PackedStringArray()
		for player in order:
			lines.append("%d. %s / %s / %s" % [
				_placing(player), _player_name(player),
				_runs[player].vehicle.title, _run_description(_runs[player]),
			])
		return {
			"result": "NO FINISHERS" if leaders.is_empty()
				else "%s WINS!" % leaders[0] if leaders.size() == 1 else "SHARED FIRST PLACE",
			"subtitle": _course.title + "\n" + "\n".join(lines),
			"color": _player_color(best) if leaders.size() == 1 else Art.CREAM,
		}
	if _state.failed:
		# A player's own trail pays nothing, so there are no points to keep.
		var advice := "Try a cleaner line." if _course.is_custom() \
			else "Your points are kept; try a cleaner line."
		return {
			"result": "OUT OF LIVES",
			"subtitle": "%s / %d of 5 plugs collected. %s" \
				% [_course.title, _state.plug_count(), advice],
			"color": Color("ff8b82"),
		}
	if not _state.finished:
		# A player's own trail has no completion medal to miss.
		var medal := "" if _course.is_custom() else " No completion medal was earned."
		return {
			"result": "TRIAL STOPPED",
			"subtitle": "%s: the garage is still waiting.%s" % [_course.title, medal],
			"color": Art.CREAM,
		}
	return {
		"result": "%s / HOME IN ONE PIECE" % _state.medal(),
		"subtitle": "%s / %s including %d recovery penalties. All five spark plugs delivered." % [
			_course.title, State.time_text(_state.adjusted_time()), _state.recoveries,
		],
		"color": Art.COPPER,
	}


func _award_round_achievements(_one: int, _two: int) -> void:
	if _course.is_custom():
		_round_progression_notes.append(TRAIL_NOTE)
		return
	for run in _runs:
		if not run.finished:
			continue
		var level: Dictionary = Course.LEVELS[run.course.number - 1]
		var achievement := run.course.completion_achievement()
		var completed := AchievementManager.is_unlocked(achievement)
		_unlock_round_achievement(achievement)
		if not completed:
			_round_progression_notes.append(str(level["unlock_text"]))
			_after_reveal(AudioManager.request_caption.bind(str(level["unlock_text"])))
		if run.recoveries == 0:
			_unlock_round_achievement("cube_trials_clean")
		if run.medal() == "GOLD":
			_unlock_round_achievement("cube_trials_gold")


## A player's own trail is practice, so it never counts toward any game's
## unlock rule.
func _record_round(player_one_total: int, player_two_total: int) -> String:
	return "" if _course.is_custom() else super(player_one_total, player_two_total)


## Nor does it pay Sparks: a tiny trail must not become a points farm.
func _round_points_earned(player_one_total: int, player_two_total: int) -> int:
	return 0 if _course.is_custom() else super(player_one_total, player_two_total)


func _best_combo_summary() -> String:
	if not GameSession.is_single_player():
		var finishers := 0
		for run in _runs:
			finishers += int(run.finished)
		return "%d / %d deliveries completed.%s" % [
			finishers, _runs.size(), "" if _course.is_custom() else " One shared garage payout.",
		]
	return "%d / 5 plugs / %d recoveries / %d landed flips / longest jump %.2fs" % [
		_state.plug_count(), _state.recoveries, _state.landed_flips, _state.longest_air,
	]


func _round_totals() -> Dictionary:
	var hits := 0
	for run in _runs:
		hits += run.plug_count()
	return {"hits": hits, "attempts": 5 * _runs.size()}


func _player_stats(player: int) -> Dictionary:
	var run: State = _runs[player] if player < _runs.size() else null
	return {
		"score": _scores[player],
		"hits": run.plug_count() if run != null else 0,
		"misses": run.recoveries if run != null else 0,
		"accuracy": run.plug_count() * 20 if run != null else 0,
		"streak": run.landed_flips if run != null else 0,
		"details": [] if run == null else [
			{"label": "Level", "value": run.course.title if run.course.is_custom()
				else "%d - %s" % [run.course.number, run.course.title]},
			{"label": "Car", "value": run.vehicle.title},
			{"label": "Time + penalties", "value": State.time_text(run.adjusted_time())},
			{"label": "Result", "value": run.medal() if run.finished else "Did not finish"},
			{"label": "Aerial points", "value": "%d (+%d hazards)" % [
				run.flip_points + run.jump_points + run.hazard_points, run.hazard_points,
			]},
		],
	}


func _standings() -> Array[int]:
	var order := _active_player_indices()
	order.sort_custom(func(left: int, right: int) -> bool:
		return left < right if _same_rank(left, right) else _ranks_before(left, right)
	)
	return order


func _ranks_before(left: int, right: int) -> bool:
	var a := _runs[left]
	var b := _runs[right]
	if a.finished != b.finished:
		return a.finished
	if a.finished:
		return _hundredths(a) < _hundredths(b)
	return a.plug_count() > b.plug_count()


func _same_rank(left: int, right: int) -> bool:
	return not _ranks_before(left, right) and not _ranks_before(right, left)


func _placing(player: int) -> int:
	var place := 1
	for other in _active_player_indices():
		place += int(_ranks_before(other, player))
	return place


func _hundredths(run: State) -> int:
	return floori(run.adjusted_time() * 100.0 + 0.00001)


func _representative_run() -> State:
	return _state if _runs.is_empty() else _runs[_standings()[0]]


func _run_description(run: State) -> String:
	return "%s / %s" % [State.time_text(run.adjusted_time()), run.medal()] if run.finished \
		else "Did not finish / %d of 5 plugs" % run.plug_count()


func _share_payload() -> Dictionary:
	var data := super()
	var run := _representative_run()
	var best := _standings()[0]
	var recoveries := 0
	var flips := 0
	var flip_points := 0
	var jump_points := 0
	var hazard_points := 0
	var jumps := 0
	data["level_id"] = run.course.id
	data["level_title"] = run.course.title
	data["level_number"] = run.course.number
	for participant in _runs:
		recoveries += participant.recoveries
		flips += participant.landed_flips
		flip_points += participant.flip_points
		jump_points += participant.jump_points
		hazard_points += participant.hazard_points
		jumps += participant.landed_jumps
	data["landed_flips"] = flips
	data["flip_points"] = flip_points
	data["jump_points"] = jump_points
	data["hazard_points"] = hazard_points
	data["landed_jumps"] = jumps
	data["score_caption"] = "TRIAL POINTS"
	if not GameSession.is_single_player():
		var tags := PackedStringArray()
		for player in _active_player_indices():
			tags.append("P%d" % (player + 1))
		data["score_caption"] += " / " + " / ".join(tags)
	data["hits_caption"] = "SPARK PLUGS" if GameSession.is_single_player() else "TOTAL SPARK PLUGS"
	data["accuracy_caption"] = "DELIVERED"
	data["combo_caption"] = "RECOVERIES" if GameSession.is_single_player() else "TOTAL RECOVERIES"
	data["combo"] = str(recoveries)
	data["combo_value"] = recoveries
	data["misses_value"] = recoveries
	data["challenge"] = "A VERY UNREASONABLE COMMUTE"
	data["paint_id"] = _paint_id if GameSession.is_single_player() \
		else Store.equipped_id(Options.GAME_ID, Options.PAINT_SLOTS[run.vehicle.id])
	data["rim_id"] = _rim_id
	data["vehicle_id"] = run.vehicle.id
	data["player_color"] = Color.TRANSPARENT if GameSession.is_single_player() else _player_color(best)
	data["damage_stage"] = run.damage_stage
	data["lives_left"] = run.lives_left
	data["failed"] = run.failed
	data["players"] = []
	for player in _active_player_indices():
		var participant := _runs[player]
		data["players"].append({
			"player_index": player, "name": _player_name(player),
			"color": _player_color(player), "vehicle_id": participant.vehicle.id,
			"vehicle_title": participant.vehicle.title, "score": _scores[player],
			"place": _placing(player),
			"adjusted_seconds": participant.adjusted_time(), "finished": participant.finished,
			"plugs": participant.plug_count(), "recoveries": participant.recoveries,
			"landed_flips": participant.landed_flips, "flip_points": participant.flip_points,
			"landed_jumps": participant.landed_jumps, "jump_points": participant.jump_points,
			"hazard_points": participant.hazard_points,
		})
	data["standings"] = _standings()
	data["rematch_title"] = "FIVE PLUGS. THREE EVERYDAY CARS."
	data["rematch_copy"] = "%s / %s / Beat the time or trick score!" % [
		"OUT OF LIVES" if run.failed else run.medal(),
		State.time_text(run.adjusted_time()),
	]
	return data


func _set_reduced_motion_enabled(value: bool) -> void:
	super(value)
	if _view != null:
		_view.set_reduced_motion(value)
	if _editor != null:
		_editor.set_reduced_motion(value)


func _set_intense_effects_enabled(value: bool) -> void:
	super(value)
	if _view != null:
		_view.set_intense_effects(value)


func _spawn_round_confetti(color: Color) -> void:
	if _holding_results:
		_held_effects.append(_spawn_round_confetti.bind(color))
		return
	if _representative_run().finished and _intense_effects_enabled:
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
	if _handoff_panel != null:
		_handoff_panel.custom_minimum_size.x = minf(720 * _ui_factor, width - 32 * _ui_factor)
		_handoff_title.add_theme_font_size_override("font_size", roundi(30 * _ui_factor))
		_handoff_copy.add_theme_font_size_override("font_size", roundi(23 * _ui_factor))
		_handoff_button.add_theme_font_size_override("font_size", roundi(24 * _ui_factor))
		_handoff_button.custom_minimum_size.y = 64 * _ui_factor
	_queue_layout()


func _queue_layout() -> void:
	if not _layout_pending and is_inside_tree():
		_layout_pending = true
		_layout_course.call_deferred()


func _playfield_bounds() -> Rect2:
	var dimensions := get_viewport_rect().size
	var inset := Vector2.ONE * 12 * _ui_factor
	return Rect2(inset, (dimensions - inset * 2.0 - Vector2(0, _capture_inset)).max(Vector2.ONE))


func _set_capture_inset(bottom: float) -> void:
	_capture_inset = maxf(bottom, 0.0)
	_queue_layout()


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
	# Bottom right of the scene, clear of the route bar along its lower edge, and
	# as tall as the HUD buttons so it keeps a 44-pixel physical touch target.
	_skip_reveal_button.add_theme_font_size_override("font_size", roundi(24 * _ui_factor))
	_skip_reveal_button.size = Vector2(150, 68) * _ui_factor
	_skip_reveal_button.position = _view.position + _view.size - _skip_reveal_button.size \
		- Vector2(18, 44) * _ui_factor
	if _editor != null:
		_editor.position = Vector2.ZERO
		_editor.size = get_viewport_rect().size
		_editor.fit(bounds, _ui_factor)
	_sync_hud()
	_view.present(0.0)
