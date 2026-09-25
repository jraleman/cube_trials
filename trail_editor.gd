extends Control

## The Trail Builder, made for players who may not read yet: every control is
## a picture, every edit shows on the trail at once and is saved straight
## away, and the big green button drives it. Words live only in tooltips and
## screen-reader names.

signal play_requested
signal pause_requested

const Trail = preload("res://games/cube_trials/trail_layout.gd")
const TrailCanvas = preload("res://games/cube_trials/trail_canvas.gd")
const PLAY = preload("res://games/cube_trials/assets/icons/play.svg")
const UNDO = preload("res://games/cube_trials/assets/icons/undo.svg")
const TRASH = preload("res://games/cube_trials/assets/icons/trash.svg")
const NEW_TRAIL = preload("res://games/cube_trials/assets/icons/new_trail.svg")
const CONFIRM = preload("res://games/cube_trials/assets/icons/confirm.svg")
const PAUSE = preload("res://games/cube_trials/assets/icons/pause.svg")
const PIECE_TIPS: Array[String] = [
	"Flat road", "Ramp up", "Ramp down", "Hill", "Dip", "Gap: jump it!", "Checkpoint flag",
]
const SCENERY_TIPS: Array[String] = ["Mountains", "Beach", "Snow"]
const BACKDROP := Color("0e1c1b")
const PLATE := Color("142725")
const EDGE := Color("b89166", 0.55)
const PICKED := Color("ffd17b")
const GO := Color("3f9b5f")
const WARN := Color("c8553d")
## The New button waits this long for its second, confirming tap.
const CONFIRM_SECONDS := 3.0
## Button and spacing sizes in UI units, the HUD's 68-unit touch target.
const BUTTON := 68.0
const SPACING := 8.0
const PIECE_HEIGHT := 88.0
const PIECE_WIDTH_MAX := 128.0
const PLAY_WIDTH := 2.1
const PLAY_WIDTH_NARROW := 1.6


## A button's picture, drawn over it so it can dim when the button has
## nothing to do and follow the chosen scenery's colours.
class Glyph extends Control:
	var texture: Texture2D
	var painter := Callable()
	## Width over height of the picture's box.
	var aspect := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var box := Vector2(minf(size.x, size.y * aspect), 0.0)
		box.y = box.x / aspect
		var rect := Rect2((size - box) * 0.5, box)
		if texture != null:
			draw_texture_rect(texture, rect, false)
		elif painter.is_valid():
			painter.call(self, rect)


var trail: Trail
## Where every edit is saved. Tests point it somewhere disposable.
var save_path := Trail.SAVE_PATH
var canvas: TrailCanvas
var play_button: Button
var pause_button: Button
var undo_button: Button
var remove_button: Button
var new_button: Button
var scroll_back_button: Button
var scroll_on_button: Button
var piece_buttons: Array[Button] = []
var scenery_buttons: Array[Button] = []
var _layout: VBoxContainer
var _top: HBoxContainer
var _scenery_row: HBoxContainer
var _tools: HBoxContainer
var _tools_row: HBoxContainer
var _stage: Control
var _palette: HFlowContainer
var _confirm_left := 0.0
var _unit := 1.0
var _content := Rect2()
var _reduced_motion := false


func _ready() -> void:
	assert(trail != null, "Give the Trail Builder its trail before adding it to the tree.")
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout = VBoxContainer.new()
	_layout.name = "Layout"
	add_child(_layout)
	_top = HBoxContainer.new()
	_top.name = "TopRow"
	_layout.add_child(_top)
	pause_button = _button("PauseButton", "Pause", pause_requested.emit, PAUSE)
	_top.add_child(pause_button)
	_scenery_row = HBoxContainer.new()
	_scenery_row.name = "Scenery"
	_top.add_child(_scenery_row)
	var scenery_group := ButtonGroup.new()
	for scenery in SCENERY_TIPS.size():
		var button := _button("Scenery%d" % scenery, SCENERY_TIPS[scenery],
			_on_scenery_pressed.bind(scenery), null,
			func(item: CanvasItem, rect: Rect2) -> void:
				TrailCanvas.draw_scenery_icon(item, rect, scenery))
		button.toggle_mode = true
		button.button_group = scenery_group
		_scenery_row.add_child(button)
		scenery_buttons.append(button)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(spacer)
	_tools = HBoxContainer.new()
	_tools.name = "Tools"
	_top.add_child(_tools)
	undo_button = _button("UndoButton", "Undo", _on_undo_pressed, UNDO)
	remove_button = _button("RemoveButton", "Remove the picked block", _on_remove_pressed, TRASH)
	new_button = _button("NewButton", "Start a new trail", _on_new_pressed, NEW_TRAIL)
	for button in [undo_button, remove_button, new_button]:
		_tools.add_child(button)
	play_button = _button("PlayButton", "Drive this trail", play_requested.emit, PLAY)
	play_button.set_meta("fill", GO)
	_top.add_child(play_button)
	_tools_row = HBoxContainer.new()
	_tools_row.name = "ToolsRow"
	_tools_row.alignment = BoxContainer.ALIGNMENT_END
	_layout.add_child(_tools_row)
	_tools_row.hide()
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_stage)
	canvas = TrailCanvas.new()
	canvas.name = "TrailCanvas"
	canvas.trail = trail
	canvas.reduced_motion = _reduced_motion
	canvas.tooltip_text = "Your trail. Tap a block to pick it; new pieces go after it."
	_stage.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.block_selected.connect(_on_block_selected)
	canvas.scrolled.connect(_refresh_scroll_buttons)
	scroll_back_button = _button("ScrollBackButton", "Scroll back", _on_scroll_pressed.bind(-1), null,
		func(item: CanvasItem, rect: Rect2) -> void: TrailCanvas.draw_chevron(item, rect, -1))
	scroll_on_button = _button("ScrollOnButton", "Scroll on", _on_scroll_pressed.bind(1), null,
		func(item: CanvasItem, rect: Rect2) -> void: TrailCanvas.draw_chevron(item, rect, 1))
	for button in [scroll_back_button, scroll_on_button]:
		button.set_meta("fill", Color(PLATE, 0.78))
		_stage.add_child(button)
	_stage.resized.connect(_place_scroll_buttons)
	_palette = HFlowContainer.new()
	_palette.name = "Pieces"
	_palette.alignment = FlowContainer.ALIGNMENT_CENTER
	_layout.add_child(_palette)
	for kind in Trail.PIECE_NAMES.size():
		var button := _button("Piece%s" % Trail.PIECE_NAMES[kind].capitalize(), PIECE_TIPS[kind],
			_on_piece_pressed.bind(kind), null,
			func(item: CanvasItem, rect: Rect2) -> void:
				TrailCanvas.draw_piece_icon(item, rect, kind, trail.scenery))
		(button.get_node("Glyph") as Glyph).aspect = 1.3
		_palette.add_child(button)
		piece_buttons.append(button)
	fit(Rect2(Vector2.ZERO, size) if _content.size == Vector2.ZERO else _content, _unit)
	_refresh()
	canvas.refresh(true)


func _process(delta: float) -> void:
	if _confirm_left > 0.0 and not get_tree().paused:
		_confirm_left = maxf(0.0, _confirm_left - delta)
		if _confirm_left == 0.0:
			_cancel_confirm()


## Every edit key is a picture button too; these are the keyboard's shortcuts.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not is_visible_in_tree():
		return
	if key.keycode == KEY_Z and key.is_command_or_control_pressed():
		get_viewport().set_input_as_handled()
		_on_undo_pressed()
	elif key.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		get_viewport().set_input_as_handled()
		_on_remove_pressed()


## Shows the builder with the trail as last saved or edited.
func open() -> void:
	show()
	_cancel_confirm()
	canvas.refresh(true)
	canvas.settle()
	_refresh()
	focus_default()


func close() -> void:
	_cancel_confirm()
	hide()


func focus_default() -> void:
	if is_visible_in_tree():
		play_button.grab_focus()


func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value
	if canvas != null:
		canvas.set_reduced_motion(value)


## Lays the builder out over [param content], the playfield inside the screen
## edges, at the HUD's UI scale [param unit].
func fit(content: Rect2, unit: float) -> void:
	_content = content
	_unit = unit
	if _layout == null:
		return
	_layout.position = content.position
	_layout.size = content.size
	var gap := roundi(SPACING * unit)
	for box: BoxContainer in [_layout, _top, _scenery_row, _tools, _tools_row]:
		box.add_theme_constant_override("separation", gap)
	_palette.add_theme_constant_override("h_separation", gap)
	_palette.add_theme_constant_override("v_separation", gap)
	var side := BUTTON * unit
	# One row needs room for nine buttons, the wide Play button and a little air.
	var narrow := content.size.x < side * (8.0 + PLAY_WIDTH) + gap * 8.0
	var tools_parent := _tools_row if narrow else _top
	if _tools.get_parent() != tools_parent:
		_tools.get_parent().remove_child(_tools)
		tools_parent.add_child(_tools)
		if not narrow:
			_top.move_child(_tools, play_button.get_index())
	_tools_row.visible = narrow
	for button: Button in [pause_button, undo_button, remove_button, new_button]:
		button.custom_minimum_size = Vector2.ONE * side
		_fit_glyph(button, 12.0 * unit)
	for button in scenery_buttons:
		button.custom_minimum_size = Vector2.ONE * side
		_fit_glyph(button, 9.0 * unit)
	play_button.custom_minimum_size = Vector2(side * (PLAY_WIDTH_NARROW if narrow else PLAY_WIDTH), side)
	_fit_glyph(play_button, 13.0 * unit)
	var per_row := 7
	var width := (content.size.x - (per_row - 1) * gap) / per_row
	if width < side:
		per_row = 4
		width = (content.size.x - (per_row - 1) * gap) / per_row
	width = floorf(clampf(width, side, PIECE_WIDTH_MAX * unit))
	for button in piece_buttons:
		button.custom_minimum_size = Vector2(width, maxf(side, PIECE_HEIGHT * unit))
		_fit_glyph(button, 8.0 * unit)
	for button in [scroll_back_button, scroll_on_button]:
		button.size = Vector2(BUTTON, 96.0) * unit
		_fit_glyph(button, 8.0 * unit)
	for button in _all_buttons():
		_style_button(button)
	canvas.unit = unit
	_place_scroll_buttons()
	_refresh()


func _button(node_name: String, tip: String, action: Callable, texture: Texture2D = null,
	painter := Callable()) -> Button:
	var button := Button.new()
	button.name = node_name
	button.tooltip_text = tip
	button.accessibility_name = tip
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	var glyph := Glyph.new()
	glyph.name = "Glyph"
	glyph.texture = texture
	glyph.painter = painter
	button.add_child(glyph)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return button


func _fit_glyph(button: Button, inset: float) -> void:
	var glyph := button.get_node("Glyph") as Glyph
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = inset
	glyph.offset_top = inset
	glyph.offset_right = -inset
	glyph.offset_bottom = -inset


## Solid plates like the driving HUD's buttons. A picked scenery wears a gold rim.
func _style_button(button: Button) -> void:
	var fill: Color = button.get_meta("fill", PLATE)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.lightened(0.12) if state.begins_with("hover") else fill
		if state == "pressed" and not button.toggle_mode:
			style.bg_color = fill.darkened(0.2)
		style.border_color = EDGE
		style.set_border_width_all(maxi(1, roundi(2.0 * _unit)))
		if button.toggle_mode and state.ends_with("pressed"):
			style.border_color = PICKED
			style.set_border_width_all(maxi(2, roundi(5.0 * _unit)))
		if state == "disabled":
			style.bg_color = fill.darkened(0.3)
			style.border_color = Color(EDGE, 0.25)
		style.set_corner_radius_all(roundi(12.0 * _unit))
		style.set_content_margin_all(0.0)
		button.add_theme_stylebox_override(state, style)


func _all_buttons() -> Array[Button]:
	var buttons: Array[Button] = [
		pause_button, undo_button, remove_button, new_button, play_button,
		scroll_back_button, scroll_on_button,
	]
	buttons.append_array(scenery_buttons)
	buttons.append_array(piece_buttons)
	return buttons


func _place_scroll_buttons() -> void:
	if scroll_back_button == null:
		return
	var margin := 8.0 * _unit
	var y := maxf(0.0, _stage.size.y - scroll_back_button.size.y - margin)
	scroll_back_button.position = Vector2(margin, y)
	scroll_on_button.position = Vector2(_stage.size.x - scroll_on_button.size.x - margin, y)


## Dims whatever cannot be used right now, so a greyed piece says "not here"
## without words: a ramp past the sky, a drop below the lowest road, a gap
## without flat road before it or level road to land on, or a full trail.
func _refresh() -> void:
	if _layout == null:
		return
	for kind in piece_buttons.size():
		piece_buttons[kind].disabled = not trail.can_add(kind)
	undo_button.disabled = not trail.can_undo()
	remove_button.disabled = not trail.can_remove()
	new_button.disabled = trail.pieces.is_empty()
	# Quiet presses skip the button group, so an undone scenery must let go itself.
	for scenery in scenery_buttons.size():
		scenery_buttons[scenery].set_pressed_no_signal(scenery == trail.scenery)
	for button in _all_buttons():
		var glyph := button.get_node("Glyph") as Glyph
		glyph.modulate.a = 0.35 if button.disabled else 1.0
		glyph.queue_redraw()
	canvas.accessibility_name = "Your trail: %d blocks. Picked: %s." % [
		trail.pieces.size(),
		"start" if trail.cursor < 0 else "%d, %s" % [trail.cursor + 1, PIECE_TIPS[trail.pieces[trail.cursor]]],
	]
	_refresh_scroll_buttons()


func _refresh_scroll_buttons() -> void:
	if scroll_back_button == null:
		return
	for pair: Array in [[scroll_back_button, -1], [scroll_on_button, 1]]:
		var button: Button = pair[0]
		button.disabled = not canvas.can_scroll(pair[1])
		(button.get_node("Glyph") as Control).modulate.a = 0.35 if button.disabled else 1.0


func _changed(popped := -1, follow := true) -> void:
	_cancel_confirm()
	trail.save(save_path)
	canvas.refresh(follow, popped)
	_refresh()


func _on_piece_pressed(kind: int) -> void:
	if trail.add(kind):
		_changed(trail.cursor)


func _on_remove_pressed() -> void:
	if trail.remove():
		_changed()


func _on_undo_pressed() -> void:
	if trail.undo():
		_changed()


## Clearing takes two taps: the first turns the button into a tick, which
## clears on a second tap within a few seconds. Undo still brings it back.
func _on_new_pressed() -> void:
	if _confirm_left <= 0.0:
		_confirm_left = CONFIRM_SECONDS
		_set_new_look(true)
		return
	if trail.clear():
		_changed()
	_cancel_confirm()


func _on_scenery_pressed(scenery: int) -> void:
	if trail.set_scenery(scenery):
		_changed(-1, false)


func _on_block_selected(index: int) -> void:
	_cancel_confirm()
	trail.select(index)
	canvas.refresh(true)
	_refresh()


func _on_scroll_pressed(direction: int) -> void:
	canvas.scroll_by(direction * canvas.page_blocks())


func _cancel_confirm() -> void:
	_confirm_left = 0.0
	if new_button != null:
		_set_new_look(false)


func _set_new_look(confirming: bool) -> void:
	var glyph := new_button.get_node("Glyph") as Glyph
	glyph.texture = CONFIRM if confirming else NEW_TRAIL
	glyph.queue_redraw()
	new_button.set_meta("fill", WARN if confirming else PLATE)
	new_button.tooltip_text = "Tap again to clear the trail" if confirming else "Start a new trail"
	new_button.accessibility_name = new_button.tooltip_text
	_style_button(new_button)
