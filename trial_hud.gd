extends Control

## Small, readable counters live over the sky, not in a separate header.

const State = preload("res://games/cube_trials/trial_state.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const LIFE = preload("res://games/cube_trials/assets/icons/life.svg")
const POINTS = preload("res://games/cube_trials/assets/icons/points.svg")
const PLUG = preload("res://games/cube_trials/assets/icons/plug.svg")
const TIMER = preload("res://games/cube_trials/assets/icons/timer.svg")
const PAUSE = preload("res://games/cube_trials/assets/icons/pause.svg")
const CAMERA = preload("res://games/cube_trials/assets/icons/camera.svg")

var lives_label: Label
var points_label: Label
var plugs_label: Label
var time_label: Label
var feedback_label: Label
var bar: GridContainer
var camera_button: Button
var driver_label: Label
var _feedback: CenterContainer
var _actions: HBoxContainer
var _action_buttons: Array[Button] = []
var _icons: Array[TextureRect] = []
var _rows: Array[HBoxContainer] = []
var _action_styles: Array[StyleBox] = []
var _style: StyleBoxFlat
var _compact := false
var _readability := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color("142725")
	_style.border_color = Color("b89166", 0.55)
	_style.set_border_width_all(1)
	bar = GridContainer.new()
	bar.columns = 6
	bar.name = "Counters"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	lives_label = _metric("Lives", LIFE, Color("ff8b82"))
	points_label = _metric("Points", POINTS, Color("ffd17b"))
	plugs_label = _metric("Plugs", PLUG, Art.CREAM)
	var driver_panel := PanelContainer.new()
	driver_panel.name = "Driver"
	driver_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	driver_panel.add_theme_stylebox_override("panel", _style)
	bar.add_child(driver_panel)
	driver_label = Label.new()
	driver_label.name = "DriverIdentity"
	driver_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	driver_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	driver_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	driver_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	driver_panel.add_child(driver_label)
	time_label = _metric("Time", TIMER, Art.CREAM)
	_actions = HBoxContainer.new()
	_actions.name = "ViewActions"
	bar.add_child(_actions)
	camera_button = Button.new()
	camera_button.name = "CameraButton"
	camera_button.focus_mode = Control.FOCUS_NONE
	_actions.add_child(camera_button)
	_style_action(camera_button, CAMERA)
	_feedback = CenterContainer.new()
	_feedback.name = "Feedback"
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feedback)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style)
	_feedback.add_child(panel)
	feedback_label = Label.new()
	feedback_label.add_theme_color_override("font_color", Art.CREAM)
	panel.add_child(feedback_label)
	_feedback.hide()
	bar.minimum_size_changed.connect(_layout_bar)
	_feedback.minimum_size_changed.connect(_layout_feedback)


func attach_pause(button: Button) -> void:
	button.reparent(_actions, false)
	_style_action(button, PAUSE)
	button.tooltip_text = "Pause (Escape / Start)"
	button.accessibility_name = "Pause"
	button.show()


func set_camera_hint(mode: String, key: String) -> void:
	camera_button.tooltip_text = "Camera: %s. Change view (%s / R3)" % [mode, key]
	camera_button.accessibility_name = camera_button.tooltip_text


func _style_action(button: Button, texture: Texture2D) -> void:
	_action_buttons.append(button)
	button.text = ""
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := button.get_theme_stylebox(style_name).duplicate() as StyleBox
		if style is StyleBoxFlat and style_name != "focus":
			style.bg_color = _style.bg_color.lightened(0.10 if style_name == "hover" else 0.0)
		button.add_theme_stylebox_override(style_name, style)
		_action_styles.append(style)


func fit_width(width: float, readability: float) -> void:
	_readability = readability
	_compact = width < 1000.0 * readability
	bar.columns = 3 if width < 650.0 * readability else 6
	_style.content_margin_left = 10 * readability
	_style.content_margin_right = 10 * readability
	_style.content_margin_top = 6 * readability
	_style.content_margin_bottom = 6 * readability
	_style.set_corner_radius_all(roundi(12 * readability))
	bar.add_theme_constant_override("h_separation", roundi(8 * readability))
	bar.add_theme_constant_override("v_separation", roundi(8 * readability))
	_actions.add_theme_constant_override("separation", roundi(8 * readability))
	bar.custom_minimum_size.y = 68 * readability
	for row in _rows:
		row.add_theme_constant_override("separation", roundi(6 * readability))
	for icon in _icons:
		icon.custom_minimum_size = Vector2.ONE * 28 * readability
	for label in [lives_label, points_label, plugs_label, time_label]:
		label.add_theme_font_size_override("font_size", roundi(27 * readability))
	feedback_label.add_theme_font_size_override("font_size", roundi(22 * readability))
	driver_label.add_theme_font_size_override("font_size", roundi(22 * readability))
	for button in _action_buttons:
		button.custom_minimum_size = Vector2.ONE * 68 * readability
		button.add_theme_constant_override("icon_max_width", roundi(28 * readability))
	for style in _action_styles:
		style.content_margin_left = 10 * readability
		style.content_margin_right = 10 * readability
		style.content_margin_top = 8 * readability
		style.content_margin_bottom = 8 * readability
	bar.size = Vector2(width, bar.get_combined_minimum_size().y)
	_layout_bar()


func _layout_bar() -> void:
	bar.size.y = bar.get_combined_minimum_size().y
	size = bar.size
	_layout_feedback()


func _layout_feedback() -> void:
	_feedback.position = Vector2(0, bar.size.y + 10 * _readability)
	_feedback.size = Vector2(bar.size.x, _feedback.get_combined_minimum_size().y)


func sync(state: State, feedback: String) -> void:
	lives_label.text = str(state.lives_left)
	points_label.text = str(state.score())
	plugs_label.text = "%d/5" % state.plug_count()
	var time := State.time_text(state.adjusted_time())
	time_label.text = time.get_slice(".", 0) if _compact else time
	_describe(lives_label, "%d of %d lives. Crashes cost one life." % [
		state.lives_left, State.STARTING_LIVES,
	])
	_describe(points_label, (
		"%d points: %d from %d landed flips, %d from airtime, speed and angle, "
		+ "%d hazard bonus. %d pending at %.2fx; land on both wheels to bank."
	) % [
		state.score(), state.flip_points, state.landed_flips, state.jump_points,
		state.hazard_points, state.pending_trick_points(), state.jump_multiplier(),
	])
	_describe(plugs_label, "%d of 5 spark plugs collected" % state.plug_count())
	_describe(time_label, "Time including recovery penalties: %s" % time)
	feedback_label.text = feedback
	if state.pending_trick_points() > 0:
		var trick := "%d FLIP%s" % [state.pending_flips, "" if state.pending_flips == 1 else "S"] \
			if state.pending_flips > 0 else "JUMP"
		feedback_label.text = "%s / LAND +%d" % [trick, state.pending_trick_points()]
		if state.hazard_bonus:
			feedback_label.text += "\nHAZARDS x%.2f" % state.jump_multiplier()
	elif state.hazard_bonus:
		feedback_label.text = "HAZARDS x%.2f / LAND TO BANK" % state.jump_multiplier()
	feedback_label.accessibility_name = feedback_label.text
	_feedback.visible = not feedback_label.text.is_empty()


func set_driver(name_text: String, color: Color) -> void:
	driver_label.text = name_text
	driver_label.accessibility_name = name_text
	(driver_label.get_parent() as Control).tooltip_text = name_text
	driver_label.add_theme_color_override("font_color", color)


func _metric(title: String, texture: Texture2D, color: Color) -> Label:
	var panel := PanelContainer.new()
	panel.name = title
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _style)
	bar.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	_rows.append(row)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture
	icon.self_modulate = color
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	_icons.append(icon)
	var label := Label.new()
	label.name = "Value"
	label.add_theme_color_override("font_color", Art.CREAM)
	row.add_child(label)
	return label


func _describe(label: Label, text: String) -> void:
	label.accessibility_name = text
	(label.get_parent().get_parent() as Control).tooltip_text = text
