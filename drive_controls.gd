extends GridContainer

## Independent touch contacts allow throttle and tilt together, without global actions.

signal recovery_requested
signal camera_requested
signal jump_requested

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const ACTIONS: Array[StringName] = [
	Options.NOSE_UP, Options.NOSE_DOWN, Options.REVERSE,
	Options.THROTTLE, Options.JUMP, Options.BRAKE, Options.RECOVER,
]
const TITLES := ["NOSE UP", "NOSE DOWN", "REVERSE", "THROTTLE", "JUMP", "BRAKE", "RECOVER +5s"]
const ICONS: Array[Texture2D] = [
	preload("res://games/cube_trials/assets/icons/tilt_up.svg"),
	preload("res://games/cube_trials/assets/icons/tilt_down.svg"),
	preload("res://games/cube_trials/assets/icons/reverse.svg"),
	preload("res://games/cube_trials/assets/icons/throttle.svg"),
	preload("res://games/cube_trials/assets/icons/jump.svg"),
	preload("res://games/cube_trials/assets/icons/brake.svg"),
	preload("res://assets/images/icon_replay.svg"),
]

var buttons: Dictionary[StringName, Button] = {}
var _touches: Dictionary[int, StringName] = {}
var _mouse_action: StringName = &""
var _enabled := true
var _key_labels := {}
var _compact := false
var _camera_button: Button


func _ready() -> void:
	columns = ACTIONS.size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 10)
	for index in ACTIONS.size():
		var action := ACTIONS[index]
		var button := Button.new()
		button.name = str(action)
		button.icon = ICONS[index]
		button.expand_icon = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(100, 76)
		button.accessibility_name = TITLES[index]
		button.button_down.connect(_mouse_down.bind(action))
		button.button_up.connect(_mouse_up)
		if action == Options.RECOVER:
			button.pressed.connect(_request_recovery)
		add_child(button)
		buttons[action] = button


## Rebinding changes the on-screen hints at once; this view reads no autoload.
func set_key_labels(labels: Dictionary) -> void:
	_key_labels = labels.duplicate()
	_refresh_labels()


## Share touch ownership and emulation filtering with the pedals, even in the HUD.
func attach_camera_button(button: Button) -> void:
	_camera_button = button
	button.pressed.connect(_request_camera)
	button.disabled = not _enabled


func _refresh_labels() -> void:
	for index in ACTIONS.size():
		var action := ACTIONS[index]
		var key: String = _key_labels.get(action, "")
		buttons[action].text = "" if _compact else key
		buttons[action].tooltip_text = "%s (%s)" % [TITLES[index], key]
		buttons[action].accessibility_name = buttons[action].tooltip_text


## Preserve touch target size on high-DPI portrait windows.
func fit_width(width: float, readability: float) -> void:
	columns = ACTIONS.size() if width >= 536.0 * readability else 4
	if width < 302.0 * readability:
		columns = 3
	_compact = width < 1000.0 * readability
	add_theme_constant_override("h_separation", roundi(10 * readability))
	add_theme_constant_override("v_separation", roundi(8 * readability))
	for button in buttons.values():
		button.custom_minimum_size = Vector2(68, 70) * readability
		button.add_theme_font_size_override("font_size", roundi(20 * readability))
		button.add_theme_constant_override("icon_max_width", roundi(30 * readability))
	_refresh_labels()
	size.x = width
	size.y = get_combined_minimum_size().y


## Each finger belongs to one control; keyboard and gamepad state stay separate.
func strength(action: StringName) -> float:
	return 1.0 if _enabled and (
		_mouse_action == action or _touches.values().has(action)
	) else 0.0


## A paused or finished run cannot retain throttle from an absent finger.
func clear_input() -> void:
	_touches.clear()
	_mouse_action = &""
	_sync_buttons()


## Results remain modal even if a pointer was held when the car parked.
func set_enabled(value: bool) -> void:
	_enabled = value
	clear_input()
	for button in buttons.values():
		button.disabled = not value
	if _camera_button != null:
		_camera_button.disabled = not value


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_input()


func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	if (event is InputEventMouseButton or event is InputEventMouseMotion) \
		and event.device == InputEvent.DEVICE_ID_EMULATION \
		and (get_global_rect().has_point(event.position) \
			or (_camera_button != null and _camera_button.get_global_rect().has_point(event.position))):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed:
		_mouse_up()
	if event is InputEventScreenTouch:
		if event.pressed:
			var action := _action_at(event.position)
			if action == &"":
				return
			_touches[event.index] = action
			if action == Options.RECOVER:
				recovery_requested.emit()
			elif action == Options.CAMERA:
				camera_requested.emit()
			elif action == Options.JUMP:
				jump_requested.emit()
		elif _touches.has(event.index):
			_touches.erase(event.index)
		else:
			return
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = _action_at(event.position)
	else:
		return
	_sync_buttons()
	get_viewport().set_input_as_handled()


func _action_at(point: Vector2) -> StringName:
	for action in ACTIONS:
		if buttons[action].get_global_rect().has_point(point):
			return action
	if _camera_button != null and _camera_button.get_global_rect().has_point(point):
		return Options.CAMERA
	return &""


func _mouse_down(action: StringName) -> void:
	if _enabled:
		_mouse_action = action
		if action == Options.JUMP:
			jump_requested.emit()


func _mouse_up() -> void:
	_mouse_action = &""
	_sync_buttons()


func _request_recovery() -> void:
	if _enabled:
		recovery_requested.emit()


func _request_camera() -> void:
	if _enabled:
		camera_requested.emit()


func _sync_buttons() -> void:
	for action in buttons:
		buttons[action].set_pressed_no_signal(strength(action) > 0.0)
	if _camera_button != null:
		_camera_button.set_pressed_no_signal(strength(Options.CAMERA) > 0.0)
