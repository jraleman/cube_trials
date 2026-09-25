extends Control

## The Trail Builder's picture of a trail: sky, blocks, plugs, flags, the car
## on its start pad and the garage at the end. It is drawn from the same data
## the drive is built from, so what a player sees is what they will drive.
##
## Tap a block to pick it. Drag, the mouse wheel or the arrow buttons scroll,
## and Left / Right move the pick when the picture has keyboard focus.

signal block_selected(index: int)
## The visible stretch of trail moved, so scroll buttons can dim at the ends.
signal scrolled

const Trail = preload("res://games/cube_trials/trail_layout.gd")
const PLUG = preload("res://games/cube_trials/assets/icons/plug.svg")

const INK := Color("253336")
const CREAM := Color("ffedc7")
const COPPER := Color("dda368")
const BROWN := Color("805234")
const GOLD := Color("ffd17b")
const PENNANT := Color("f07c3e")
const GLASS := Color("bcd8e0")
## In Trail.Scenery order: mountain, beach, snow.
const PALETTES: Array[Dictionary] = [
	{
		"sky_top": Color("8fc4e8"), "sky_bottom": Color("e8f1e4"),
		"far": Color("a8bfb4"), "near": Color("87a57f"), "leaf": Color("3f8a52"),
		"earth": Color("7a6a4f"), "earth_alt": Color("6c5d44"),
		"cap": Color("6f9a4f"), "road": Color("d8c496"), "water": Color("3f8fa6"),
	},
	{
		"sky_top": Color("7fd3ee"), "sky_bottom": Color("fff1d0"),
		"far": Color("9fd6cf"), "near": Color("ecd8a6"), "leaf": Color("4caf50"),
		"earth": Color("d9b77a"), "earth_alt": Color("cfa96a"),
		"cap": Color("e8cf98"), "road": Color("f4e1b5"), "water": Color("3bb5c4"),
	},
	{
		"sky_top": Color("b6cde0"), "sky_bottom": Color("eef4f8"),
		"far": Color("cbd9e5"), "near": Color("a9bdcc"), "leaf": Color("e8f4ff"),
		"earth": Color("8198a8"), "earth_alt": Color("74899a"),
		"cap": Color("dfe9f0"), "road": Color("f7fbfe"), "water": Color("6f9fc0"),
	},
]
## How far a press may wander, in UI units, and still count as a tap.
const DRAG_SLOP := 12.0
const POP_SECONDS := 0.28
## World units kept clear above the highest road for flags, plugs and the
## garage roof, and below the lowest for the ground.
const HEADROOM := 250.0
const FOOTROOM := 150.0
const WATER_Y := 790.0
const CAP_DEPTH := 26.0
const PLUG_LIFT := 72.0

var trail: Trail
var reduced_motion := false
## The HUD's UI scale, so slop, strokes and the smallest block follow it.
var unit := 1.0
## World x at the left edge.
var scroll := Trail.PAD_LEFT + 300.0
var _scroll_goal := scroll
var _center_y := Trail.BASE_Y
var _blocks: Array[Dictionary] = []
var _route: Dictionary = {}
var _pressing := false
var _dragging := false
var _press_at := Vector2.ZERO
var _press_scroll := 0.0
var _pointer_focus := false
var _pop_index := -1
var _pop_left := 0.0
var _pulse := 0.0


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_on_resized)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(_on_focus_exited)


## Redraws after an edit. [param follow] scrolls the pick into view, and
## [param popped] is a block just added, which rises into place.
func refresh(follow := true, popped := -1) -> void:
	if trail == null:
		return
	_blocks = trail.blocks()
	_route = trail.to_route()
	_pop_index = popped
	_pop_left = POP_SECONDS if popped >= 0 and not reduced_motion else 0.0
	if follow:
		_follow_cursor()
	_scroll_goal = _clamp_scroll(_scroll_goal)
	if reduced_motion:
		_settle()
	queue_redraw()
	scrolled.emit()


## Jumps straight to where the scroll and height are heading.
func settle() -> void:
	_settle()
	queue_redraw()


func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	if value:
		_pop_left = 0.0
		_pulse = 0.0
		_settle()
	queue_redraw()


## Screen pixels per world unit: about nine blocks across a wide screen and
## four and a half on a tall one, never so small a finger cannot pick one, and
## a thousand units of height always fit.
func world_scale() -> float:
	var across := clampf(size.x / maxf(size.y, 1.0) * 5.0, 4.5, 9.0)
	var block := clampf(size.x / across, 56.0 * unit, 150.0 * unit)
	return maxf(minf(block / Trail.PIECE_WIDTH, size.y / 1000.0), 0.01)


func to_screen(point: Vector2) -> Vector2:
	var s := world_scale()
	return Vector2((point.x - scroll) * s, (point.y - _center_y) * s + size.y * 0.5)


func world_x(screen_x: float) -> float:
	return screen_x / world_scale() + scroll


## The block under world [param x]: -1 on the start pad, the last block past
## the end of the trail.
func block_at(x: float) -> int:
	if trail == null or x < Trail.TRAIL_START:
		return -1
	return mini(floori((x - Trail.TRAIL_START) / Trail.PIECE_WIDTH), trail.pieces.size() - 1)


## Screen centre of a block, for tests and for the pick highlight.
func block_center(index: int) -> Vector2:
	var x := Trail.TRAIL_START + (index + 0.5) * Trail.PIECE_WIDTH
	if index < 0:
		x = Trail.TRAIL_START - Trail.PIECE_WIDTH * 0.5
	var y := _ground_y(x)
	return to_screen(Vector2(x, Trail.BASE_Y if is_inf(y) else y))


func can_scroll(direction: int) -> bool:
	var limits := _scroll_range()
	return _scroll_goal < limits.y - 0.5 if direction > 0 else _scroll_goal > limits.x + 0.5


## Scrolls by [param blocks] block widths; negative goes back toward the start.
func scroll_by(blocks: float) -> void:
	_scroll_goal = _clamp_scroll(_scroll_goal + blocks * Trail.PIECE_WIDTH)
	if reduced_motion:
		_settle()
	queue_redraw()
	scrolled.emit()


## About half a screen, for the arrow buttons.
func page_blocks() -> float:
	return maxf(1.0, floorf(size.x / world_scale() / Trail.PIECE_WIDTH * 0.5))


func _process(delta: float) -> void:
	if trail == null or not is_visible_in_tree():
		return
	var changed := false
	if scroll != _scroll_goal:
		scroll = lerpf(scroll, _scroll_goal, 1.0 - exp(-delta * 12.0))
		if absf(scroll - _scroll_goal) < 0.5:
			scroll = _scroll_goal
		changed = true
	var goal := _center_goal()
	if _center_y != goal:
		_center_y = lerpf(_center_y, goal, 1.0 - exp(-delta * 6.0))
		if absf(_center_y - goal) < 0.5:
			_center_y = goal
		changed = true
	if _pop_left > 0.0:
		_pop_left = maxf(0.0, _pop_left - delta)
		changed = true
	if not reduced_motion:
		_pulse = fmod(_pulse + delta, 2.0)
		changed = true
	if changed:
		queue_redraw()


func _settle() -> void:
	scroll = _scroll_goal
	_center_y = _center_goal()


func _scroll_range() -> Vector2:
	var view := size.x / world_scale()
	var low := Trail.PAD_LEFT + 300.0
	var finish := trail.finish_x() if trail != null else Trail.TRAIL_START + Trail.GARAGE_DISTANCE
	return Vector2(low, maxf(low, finish + Trail.FINISH_WIDTH + 260.0 - view))


func _clamp_scroll(value: float) -> float:
	var limits := _scroll_range()
	return clampf(value, limits.x, limits.y)


## Keeps the picked block and the "+" after it on screen.
func _follow_cursor() -> void:
	var view := size.x / world_scale()
	var edge := Trail.TRAIL_START + (trail.cursor + 1) * Trail.PIECE_WIDTH
	var margin := minf(Trail.PIECE_WIDTH * 1.5, view * 0.3)
	if edge - Trail.PIECE_WIDTH - margin < _scroll_goal:
		_scroll_goal = edge - Trail.PIECE_WIDTH - margin
	elif edge + margin > _scroll_goal + view:
		_scroll_goal = edge + margin - view
	_scroll_goal = _clamp_scroll(_scroll_goal)


## Frames the height of the road on screen, favouring the sky above it.
func _center_goal() -> float:
	if trail == null or size.y <= 0.0:
		return _center_y
	var s := world_scale()
	var left := scroll
	var right := scroll + size.x / s
	var low := INF
	var high := -INF
	if left < Trail.TRAIL_START:
		low = Trail.BASE_Y
		high = Trail.BASE_Y
	for block in _blocks:
		var x: float = block["x"]
		if x + Trail.PIECE_WIDTH < left or x > right:
			continue
		var heights: Array[float] = [block["y"], block["end_y"]]
		for point: Vector2 in block["top"]:
			heights.append(point.y)
		for y in heights:
			low = minf(low, y)
			high = maxf(high, y)
	if right > trail.trail_end():
		low = minf(low, _final_y())
		high = maxf(high, _final_y())
	if is_inf(low):
		return _center_y
	var span := size.y / s
	var top := low - HEADROOM
	var bottom := high + FOOTROOM
	return (top + bottom) * 0.5 if bottom - top <= span else top + span * 0.5


func _final_y() -> float:
	return Trail.BASE_Y if _blocks.is_empty() else float(_blocks[-1]["end_y"])


func _ground_y(x: float) -> float:
	for road: Array in _route.get("roads", []):
		for index in range(road.size() - 1):
			var a: Vector2 = road[index]
			var b: Vector2 = road[index + 1]
			if x >= a.x and x <= b.x:
				return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return INF


func _on_resized() -> void:
	if trail == null:
		return
	_follow_cursor()
	_settle()
	queue_redraw()
	scrolled.emit()


func _on_focus_exited() -> void:
	_pointer_focus = false
	queue_redraw()


# --- Input ------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if trail == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_pressing = true
					_dragging = false
					_press_at = button.position
					_press_scroll = _scroll_goal
					_pointer_focus = true
				elif _pressing:
					_pressing = false
					if not _dragging:
						block_selected.emit(block_at(world_x(button.position.x)))
					_dragging = false
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				if button.pressed:
					scroll_by(-1.0)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				if button.pressed:
					scroll_by(1.0)
				accept_event()
	elif event is InputEventMouseMotion:
		if not _pressing:
			return
		var motion := event as InputEventMouseMotion
		if not _dragging and motion.position.distance_to(_press_at) > DRAG_SLOP * unit:
			_dragging = true
		if _dragging:
			_scroll_goal = _clamp_scroll(
				_press_scroll - (motion.position.x - _press_at.x) / world_scale())
			scroll = _scroll_goal
			queue_redraw()
			scrolled.emit()
		accept_event()
	elif event.is_action_pressed("ui_left", true) and trail.cursor > -1:
		_pointer_focus = false
		block_selected.emit(trail.cursor - 1)
		accept_event()
	elif event.is_action_pressed("ui_right", true) and trail.cursor < trail.pieces.size() - 1:
		_pointer_focus = false
		block_selected.emit(trail.cursor + 1)
		accept_event()


# --- Drawing ----------------------------------------------------------------------

func _draw() -> void:
	if trail == null:
		return
	var colors := palette(trail.scenery)
	var s := world_scale()
	var left := scroll - Trail.PIECE_WIDTH
	var right := scroll + size.x / s + Trail.PIECE_WIDTH
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]),
		PackedColorArray([colors["sky_top"], colors["sky_top"], colors["sky_bottom"], colors["sky_bottom"]]))
	_draw_backdrop(colors, s)
	var water := to_screen(Vector2(0.0, WATER_Y)).y
	if water < size.y:
		draw_rect(Rect2(0.0, water, size.x, size.y - water), colors["water"])
		draw_line(Vector2(0.0, water), Vector2(size.x, water), colors["water"].lightened(0.35),
			maxf(2.0, 8.0 * s))
	_draw_ground([Vector2(Trail.PAD_LEFT, Trail.BASE_Y), Vector2(Trail.TRAIL_START, Trail.BASE_Y)],
		colors["earth"].lightened(0.06), colors)
	for index in _blocks.size():
		var block := _blocks[index]
		var x: float = block["x"]
		if x > right or x + Trail.PIECE_WIDTH < left:
			continue
		var rise := 0.0
		if index == _pop_index and _pop_left > 0.0:
			var t := 1.0 - _pop_left / POP_SECONDS
			rise = (1.0 - ease(t, 0.4)) * 160.0 * s
		draw_set_transform(Vector2(0.0, rise))
		_draw_ground(block["top"], colors["earth"] if index % 2 == 0 else colors["earth_alt"], colors)
		draw_set_transform(Vector2.ZERO)
	_draw_ground([Vector2(trail.trail_end(), _final_y()),
		Vector2(trail.finish_x() + Trail.RUNOUT, _final_y())],
		colors["earth"].lightened(0.06), colors)
	_draw_takeoffs(s)
	_draw_garage(s)
	var checkpoints: Array = _route.get("checkpoint_x", [])
	for index in range(1, checkpoints.size()):
		_draw_flag(float(checkpoints[index]), s)
	for x: float in _route.get("plug_x", []):
		_draw_plug(x, s)
	_draw_car(s)
	_draw_pick(s)
	_draw_marker(s)
	if has_focus() and not _pointer_focus:
		draw_style_box(get_theme_stylebox("focus", "Button"), Rect2(Vector2.ZERO, size))


## Two layers of hills slide slower than the trail, for depth.
func _draw_backdrop(colors: Dictionary, s: float) -> void:
	var sharp := trail.scenery != Trail.Scenery.BEACH
	for layer in 2:
		var parallax := 0.25 if layer == 0 else 0.5
		var base := size.y * (0.52 if layer == 0 else 0.66)
		var height := size.y * (0.22 if layer == 0 else 0.12)
		var points := PackedVector2Array([Vector2(0.0, size.y)])
		var steps := 32
		for step in steps + 1:
			var x := size.x * step / steps
			var u := (x / s + scroll * parallax) * (1.0 + layer * 0.6)
			var profile := 0.55 * sin(u * 0.0021) + 0.3 * sin(u * 0.0053 + 1.7) \
				+ 0.15 * sin(u * 0.013 + 0.4)
			if sharp and layer == 0:
				profile = 1.0 - 2.0 * absf(sin(u * 0.0017 + 0.6)) + 0.25 * sin(u * 0.009)
			points.append(Vector2(x, base - height * (profile * 0.5 + 0.5)))
		points.append(size)
		draw_colored_polygon(points, colors["far" if layer == 0 else "near"])


## One stretch of road: earth down to the bottom edge, a grass, sand or snow
## cap, then the pale road line itself.
func _draw_ground(top: Array, earth: Color, colors: Dictionary) -> void:
	if top.size() < 2:
		return
	var s := world_scale()
	var surface := PackedVector2Array()
	var deepest := 0.0
	for point: Vector2 in top:
		var screen := to_screen(point)
		surface.append(screen)
		deepest = maxf(deepest, screen.y)
	var bottom := maxf(size.y, deepest) + 4.0
	var body := surface.duplicate()
	body.append(Vector2(surface[-1].x, bottom))
	body.append(Vector2(surface[0].x, bottom))
	draw_colored_polygon(body, earth)
	var cap := surface.duplicate()
	for index in range(surface.size() - 1, -1, -1):
		cap.append(surface[index] + Vector2(0.0, CAP_DEPTH * s))
	draw_colored_polygon(cap, colors["cap"])
	draw_polyline(surface, colors["road"], maxf(2.0, 9.0 * s), true)


## Gold stripes before every edge, like the takeoff markings on the real road.
func _draw_takeoffs(s: float) -> void:
	var roads: Array = _route.get("roads", [])
	for index in range(roads.size() - 1):
		var edge: float = (roads[index] as Array)[-1].x
		for stripe in 3:
			var x := edge - 110.0 + stripe * 40.0
			var a := to_screen(Vector2(x, _ground_y(x)))
			var b := to_screen(Vector2(x + 20.0, _ground_y(x + 20.0)))
			draw_line(a, b, GOLD, maxf(3.0, 12.0 * s))


func _draw_garage(s: float) -> void:
	var finish := trail.finish_x()
	var y := _final_y()
	var wall := Rect2(to_screen(Vector2(finish - 30.0, y - 200.0)),
		Vector2(Trail.FINISH_WIDTH + 60.0, 200.0) * s)
	draw_rect(wall, CREAM)
	draw_colored_polygon(PackedVector2Array([
		to_screen(Vector2(finish - 70.0, y - 196.0)),
		to_screen(Vector2(finish + Trail.FINISH_WIDTH * 0.5, y - 300.0)),
		to_screen(Vector2(finish + Trail.FINISH_WIDTH + 70.0, y - 196.0)),
	]), BROWN)
	var door := Rect2(to_screen(Vector2(finish, y - 150.0)), Vector2(Trail.FINISH_WIDTH, 150.0) * s)
	draw_rect(door, INK)
	draw_rect(door, COPPER, false, maxf(2.0, 8.0 * s))
	var tiles := 8
	var tile := Trail.FINISH_WIDTH / tiles
	for index in tiles:
		for row in 2:
			if (index + row) % 2 == 0:
				draw_rect(Rect2(to_screen(Vector2(finish + index * tile, y - 20.0 + row * 10.0)),
					Vector2(tile, 10.0) * s), CREAM)


func _draw_flag(x: float, s: float) -> void:
	var ground := _ground_y(x)
	if is_inf(ground):
		return
	var foot := to_screen(Vector2(x, ground))
	var top := to_screen(Vector2(x, ground - 160.0))
	draw_line(foot, top, INK, maxf(2.0, 8.0 * s))
	draw_colored_polygon(PackedVector2Array([
		top, to_screen(Vector2(x + 80.0, ground - 132.0)), to_screen(Vector2(x, ground - 104.0)),
	]), PENNANT)


func _draw_plug(x: float, s: float) -> void:
	var ground := _ground_y(x)
	if is_inf(ground):
		return
	var center := to_screen(Vector2(x, ground - PLUG_LIFT))
	var radius := 30.0 * s
	draw_circle(center, radius, GOLD)
	draw_circle(center, radius, INK, false, maxf(1.5, 4.0 * s), true)
	draw_texture_rect(PLUG, Rect2(center - Vector2.ONE * radius * 0.72, Vector2.ONE * radius * 1.44),
		false, INK)


## The brown Cube waiting on its start pad, facing the trail.
func _draw_car(s: float) -> void:
	var x := Trail.START_X
	var y := Trail.BASE_Y
	var body := PackedVector2Array([
		to_screen(Vector2(x - 78.0, y - 24.0)), to_screen(Vector2(x + 76.0, y - 24.0)),
		to_screen(Vector2(x + 78.0, y - 70.0)), to_screen(Vector2(x + 58.0, y - 82.0)),
		to_screen(Vector2(x + 44.0, y - 122.0)), to_screen(Vector2(x - 70.0, y - 122.0)),
		to_screen(Vector2(x - 80.0, y - 110.0)),
	])
	draw_colored_polygon(body, BROWN)
	draw_colored_polygon(PackedVector2Array([
		to_screen(Vector2(x - 8.0, y - 112.0)), to_screen(Vector2(x + 38.0, y - 112.0)),
		to_screen(Vector2(x + 50.0, y - 82.0)), to_screen(Vector2(x - 8.0, y - 82.0)),
	]), GLASS)
	draw_rect(Rect2(to_screen(Vector2(x - 66.0, y - 112.0)), Vector2(50.0, 30.0) * s), GLASS)
	for side in [-1.0, 1.0]:
		var wheel := to_screen(Vector2(x + side * 53.0, y - 14.0))
		draw_circle(wheel, 15.0 * s, INK)
		draw_circle(wheel, 6.0 * s, COPPER)


## A soft glow over the picked block, or over the end of the start pad.
func _draw_pick(s: float) -> void:
	var line := maxf(3.0, 10.0 * s)
	if trail.cursor < 0 or trail.cursor >= _blocks.size():
		var a := to_screen(Vector2(Trail.TRAIL_START - Trail.PIECE_WIDTH, Trail.BASE_Y))
		var b := to_screen(Vector2(Trail.TRAIL_START, Trail.BASE_Y))
		draw_rect(Rect2(a, Vector2(b.x - a.x, size.y - a.y)), Color(1.0, 1.0, 1.0, 0.18))
		draw_line(a, b, GOLD, line)
		return
	var block := _blocks[trail.cursor]
	var top: Array = block["top"]
	if top.is_empty():
		var x: float = block["x"]
		var rect := Rect2(to_screen(Vector2(x, float(block["y"]) - 20.0)),
			Vector2(Trail.PIECE_WIDTH, 260.0) * s)
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.18))
		draw_rect(rect, GOLD, false, line * 0.6)
		return
	var surface := PackedVector2Array()
	for point: Vector2 in top:
		surface.append(to_screen(point))
	var glow := surface.duplicate()
	glow.append(Vector2(surface[-1].x, maxf(size.y, surface[-1].y) + 4.0))
	glow.append(Vector2(surface[0].x, maxf(size.y, surface[0].y) + 4.0))
	draw_colored_polygon(glow, Color(1.0, 1.0, 1.0, 0.2))
	draw_polyline(surface, GOLD, line, true)


## A pulsing "+" where the next piece will go.
func _draw_marker(s: float) -> void:
	var x := Trail.TRAIL_START + (trail.cursor + 1) * Trail.PIECE_WIDTH
	var y := Trail.BASE_Y if trail.cursor < 0 or _blocks.is_empty() \
		else float(_blocks[mini(trail.cursor, _blocks.size() - 1)]["end_y"])
	var grow := 1.0 + 0.08 * sin(_pulse * PI)
	var center := to_screen(Vector2(x, y - 150.0))
	var radius := maxf(34.0 * s, 14.0 * unit) * grow
	var foot := to_screen(Vector2(x, y))
	var dash := maxf(6.0, 16.0 * s)
	var from := center.y + radius
	while from < foot.y - 2.0:
		draw_line(Vector2(foot.x, from), Vector2(foot.x, minf(from + dash, foot.y)), GOLD,
			maxf(2.0, 5.0 * s))
		from += dash * 2.0
	draw_circle(center, radius, GOLD)
	draw_circle(center, radius, INK, false, maxf(1.5, 4.0 * s), true)
	var arm := radius * 0.55
	draw_line(center - Vector2(arm, 0.0), center + Vector2(arm, 0.0), INK, radius * 0.24)
	draw_line(center - Vector2(0.0, arm), center + Vector2(0.0, arm), INK, radius * 0.24)


# --- Button pictures ------------------------------------------------------------

static func palette(scenery: int) -> Dictionary:
	return PALETTES[clampi(scenery, 0, PALETTES.size() - 1)]


## A piece's picture for its button, in the chosen scenery's colours.
static func draw_piece_icon(item: CanvasItem, rect: Rect2, kind: int, scenery: int) -> void:
	var colors := palette(scenery)
	var surfaces: Array = []
	match kind:
		Trail.Piece.UP:
			surfaces = [[Vector2(0.06, 0.76), Vector2(0.94, 0.36)]]
		Trail.Piece.DOWN:
			surfaces = [[Vector2(0.06, 0.36), Vector2(0.94, 0.76)]]
		Trail.Piece.HILL:
			surfaces = [[Vector2(0.06, 0.68), Vector2(0.5, 0.34), Vector2(0.94, 0.68)]]
		Trail.Piece.DIP:
			surfaces = [[Vector2(0.06, 0.46), Vector2(0.5, 0.78), Vector2(0.94, 0.46)]]
		Trail.Piece.GAP:
			surfaces = [[Vector2(0.06, 0.58), Vector2(0.3, 0.58)], [Vector2(0.7, 0.58), Vector2(0.94, 0.58)]]
		_:
			surfaces = [[Vector2(0.06, 0.58), Vector2(0.94, 0.58)]]
	if kind == Trail.Piece.GAP:
		item.draw_rect(Rect2(_at(rect, Vector2(0.3, 0.8)), rect.size * Vector2(0.4, 0.14)),
			colors["water"])
		var arc := PackedVector2Array()
		for step in 9:
			var t := step / 8.0
			arc.append(_at(rect, Vector2(lerpf(0.26, 0.74, t), 0.46 - sin(t * PI) * 0.24)))
		for step in range(0, arc.size() - 1, 2):
			item.draw_line(arc[step], arc[step + 1], CREAM, rect.size.y * 0.05)
	for surface: Array in surfaces:
		var line := PackedVector2Array()
		for point: Vector2 in surface:
			line.append(_at(rect, point))
		var body := line.duplicate()
		body.append(_at(rect, Vector2(surface[-1].x, 0.94)))
		body.append(_at(rect, Vector2(surface[0].x, 0.94)))
		item.draw_colored_polygon(body, colors["earth"])
		item.draw_polyline(line, colors["cap"], rect.size.y * 0.13)
		item.draw_polyline(line, colors["road"], rect.size.y * 0.045)
	if kind == Trail.Piece.FLAG:
		item.draw_line(_at(rect, Vector2(0.5, 0.56)), _at(rect, Vector2(0.5, 0.1)), CREAM,
			rect.size.x * 0.05)
		item.draw_colored_polygon(PackedVector2Array([
			_at(rect, Vector2(0.52, 0.1)), _at(rect, Vector2(0.86, 0.2)), _at(rect, Vector2(0.52, 0.3)),
		]), PENNANT)


## The scenery buttons: a pine, a palm on the sand, a snowflake.
static func draw_scenery_icon(item: CanvasItem, rect: Rect2, scenery: int) -> void:
	var colors := palette(scenery)
	match scenery:
		Trail.Scenery.BEACH:
			item.draw_circle(_at(rect, Vector2(0.76, 0.26)), rect.size.x * 0.12, GOLD)
			item.draw_colored_polygon(PackedVector2Array([
				_at(rect, Vector2(0.04, 0.94)), _at(rect, Vector2(0.24, 0.8)),
				_at(rect, Vector2(0.7, 0.8)), _at(rect, Vector2(0.96, 0.94)),
			]), colors["cap"])
			item.draw_polyline(PackedVector2Array([
				_at(rect, Vector2(0.5, 0.86)), _at(rect, Vector2(0.47, 0.64)),
				_at(rect, Vector2(0.42, 0.45)), _at(rect, Vector2(0.36, 0.3)),
			]), Color("9b6b3e"), rect.size.x * 0.08)
			for leaf: Array in [
				[Vector2(0.2, 0.2), Vector2(0.06, 0.36)], [Vector2(0.52, 0.18), Vector2(0.66, 0.36)],
				[Vector2(0.24, 0.1), Vector2(0.12, 0.12)], [Vector2(0.46, 0.08), Vector2(0.58, 0.12)],
			]:
				item.draw_polyline(PackedVector2Array([
					_at(rect, Vector2(0.36, 0.3)), _at(rect, leaf[0]), _at(rect, leaf[1]),
				]), colors["leaf"], rect.size.x * 0.09)
		Trail.Scenery.SNOW:
			var center := _at(rect, Vector2(0.5, 0.5))
			var arm := rect.size.x * 0.4
			for spoke in 6:
				var direction := Vector2.UP.rotated(spoke * TAU / 6.0)
				var tip := center + direction * arm
				item.draw_line(center, tip, colors["leaf"], rect.size.x * 0.07)
				var joint := center + direction * arm * 0.62
				for side in [-1.0, 1.0]:
					item.draw_line(joint, joint + direction.rotated(side * 0.8) * arm * 0.3,
						colors["leaf"], rect.size.x * 0.06)
		_:
			item.draw_colored_polygon(PackedVector2Array([
				_at(rect, Vector2(0.5, 0.06)), _at(rect, Vector2(0.76, 0.44)), _at(rect, Vector2(0.24, 0.44)),
			]), colors["leaf"])
			item.draw_colored_polygon(PackedVector2Array([
				_at(rect, Vector2(0.5, 0.26)), _at(rect, Vector2(0.86, 0.76)), _at(rect, Vector2(0.14, 0.76)),
			]), colors["leaf"])
			item.draw_rect(Rect2(_at(rect, Vector2(0.43, 0.76)), rect.size * Vector2(0.14, 0.18)), BROWN)


## An arrow head for the scroll buttons; [param direction] is -1 or 1.
static func draw_chevron(item: CanvasItem, rect: Rect2, direction: int) -> void:
	var center := rect.get_center()
	var half := Vector2(rect.size.x * 0.16 * direction, rect.size.y * 0.3)
	item.draw_polyline(PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, 0.0), center + Vector2(-half.x, half.y),
	]), Color.WHITE, rect.size.x * 0.13, true)


static func _at(rect: Rect2, point: Vector2) -> Vector2:
	return rect.position + point * rect.size
