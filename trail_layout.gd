extends RefCounted

## A player's own trail: a row of simple blocks. The builder edits it, a small
## file keeps it, and `to_route()` turns it into the same route data the
## handcrafted levels use, so driving, scenery and scoring need no special case.
##
## Pieces are kept exactly as placed. Anything a later edit made impossible,
## such as a climb past the ceiling or a gap without level road around it, is
## simply built flat, so every saved trail stays drivable at full throttle.

enum Piece { FLAT, UP, DOWN, HILL, DIP, GAP, FLAG }
## In the same order as Course.Scenery.
enum Scenery { MOUNTAIN, BEACH, SNOW }

const PIECE_NAMES: Array[String] = ["flat", "up", "down", "hill", "dip", "gap", "flag"]
const SCENERY_NAMES: Array[String] = ["mountain", "beach", "snow"]
const HILL_COLORS: Array[Color] = [Color("657b55"), Color("ead3a1"), Color("e5eff5")]
const SAVE_PATH := "user://cube_trials_trail.cfg"
const SECTION := "trail"
const FORMAT := 1
const TITLE := "My Trail"
## Course.START_X and Course.FINISH_WIDTH. Course preloads this file, so this
## file cannot preload Course back.
const START_X := 180.0
const FINISH_WIDTH := 240.0
const PIECE_WIDTH := 240.0
## The level start pad every trail begins on, where the car waits.
const PAD_LEFT := -600.0
const TRAIL_START := 600.0
const BASE_Y := 300.0
const STEP_HEIGHT := 100.0
## Low enough that any row of hills and dips can be driven flat out.
const BUMP_HEIGHT := 40.0
## Steps below and above the start. The lowest road stays above the beach sea.
const LOWEST := -3
const HIGHEST := 9
const MAX_PIECES := 64
## Two gaps in a row make a long jump; a third would be too far to clear.
const MAX_GAP_RUN := 2
## A jump carries the car up to two blocks past a gap, so this many blocks
## after every gap stay level for it to land on. Only then can another gap
## start.
const RUNUP_BLOCKS := 2
## Level road. A gap needs RUNUP_BLOCKS of these after it: a slope there would
## move the landing further on, past the level road. Right before a gap only
## FLAT will do, as a car that crashes at the gap starts again at the flag,
## standing still.
const LEVEL_PIECES: Array[int] = [Piece.FLAT, Piece.FLAG]
## Road that keeps full speed. A double gap needs RUNUP_BLOCKS of these in a
## row before it.
const FAST_PIECES: Array[int] = [Piece.FLAT, Piece.DOWN, Piece.FLAG]
const HISTORY_LIMIT := 50
## Flat road from the last block to the garage, then past its back wall.
const GARAGE_DISTANCE := 480.0
const RUNOUT := 850.0
const END_MARGIN := 600.0
const PLUG_COUNT := 5
const PLUG_BEFORE_GARAGE := 150.0
## Plugs keep clear of jump takeoffs and of the whole landing after a gap,
## which a car at full speed flies right over. The garage road after the last
## landing always leaves room for them.
const TAKEOFF_CLEARANCE := 150.0
const LANDING_CLEARANCE := RUNUP_BLOCKS * PIECE_WIDTH
## A first trail that shows every piece and can be driven straight away.
const SAMPLE: Array[int] = [
	Piece.FLAT, Piece.UP, Piece.FLAT, Piece.HILL, Piece.FLAT, Piece.GAP,
	Piece.FLAT, Piece.FLAG, Piece.DOWN, Piece.DIP, Piece.FLAT, Piece.FLAT,
]

var pieces: Array[int] = []
var scenery := Scenery.MOUNTAIN
## The selected block. New pieces go straight after it; -1 is the start pad.
var cursor := -1
var _history: Array[Dictionary] = []


func _init(start: Array = SAMPLE, start_scenery := Scenery.MOUNTAIN) -> void:
	pieces = _sanitized(start)
	scenery = clampi(start_scenery, Scenery.MOUNTAIN, Scenery.SNOW) as Scenery
	cursor = pieces.size() - 1


static func height(level: int) -> float:
	return BASE_Y - level * STEP_HEIGHT


## Replaces the trail with the saved one. Returns false, keeping this trail,
## when there is no readable save.
func load_file(path := SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var config := ConfigFile.new()
	if config.load(path) != OK:
		push_warning("Cube Trials could not read the saved trail at %s." % path)
		return false
	var names: Variant = config.get_value(SECTION, "pieces", PackedStringArray())
	var loaded: Array[int] = []
	if names is PackedStringArray or names is Array:
		for entry: Variant in names:
			var kind := PIECE_NAMES.find(str(entry))
			if kind >= 0 and loaded.size() < MAX_PIECES:
				loaded.append(kind)
	pieces = loaded
	scenery = maxi(SCENERY_NAMES.find(str(config.get_value(SECTION, "scenery", ""))), 0) as Scenery
	cursor = pieces.size() - 1
	_history.clear()
	return true


func save(path := SAVE_PATH) -> Error:
	var names := PackedStringArray()
	for kind in pieces:
		names.append(PIECE_NAMES[kind])
	var config := ConfigFile.new()
	config.set_value(SECTION, "format", FORMAT)
	config.set_value(SECTION, "scenery", SCENERY_NAMES[scenery])
	config.set_value(SECTION, "pieces", names)
	var error := config.save(path)
	if error != OK:
		push_warning("Cube Trials could not save the trail: %s." % error_string(error))
	return error


# --- Editing ------------------------------------------------------------------

## Whether [param kind] fits after the selected block without flattening
## anything: the road stays between the floor and the ceiling, every gap has
## flat road before it and level road after it, and no slope goes down
## straight out of a dip.
func can_add(kind: int) -> bool:
	if kind < 0 or kind >= PIECE_NAMES.size() or pieces.size() >= MAX_PIECES:
		return false
	var trial := pieces.duplicate()
	trial.insert(cursor + 1, kind)
	return _flattened(trial) <= _flattened(pieces)


func add(kind: int) -> bool:
	if not can_add(kind):
		return false
	_remember()
	pieces.insert(cursor + 1, kind)
	cursor += 1
	return true


func can_remove() -> bool:
	return cursor >= 0 and cursor < pieces.size()


## Removes the selected block and selects the one before it, like backspace.
func remove() -> bool:
	if not can_remove():
		return false
	_remember()
	pieces.remove_at(cursor)
	cursor -= 1
	return true


func select(index: int) -> void:
	cursor = clampi(index, -1, pieces.size() - 1)


func set_scenery(value: int) -> bool:
	if value == scenery or value < Scenery.MOUNTAIN or value > Scenery.SNOW:
		return false
	_remember()
	scenery = value as Scenery
	return true


## An empty trail with the same scenery. Undo brings the blocks back.
func clear() -> bool:
	if pieces.is_empty():
		return false
	_remember()
	pieces.clear()
	cursor = -1
	return true


func can_undo() -> bool:
	return not _history.is_empty()


func undo() -> bool:
	if _history.is_empty():
		return false
	var snapshot: Dictionary = _history.pop_back()
	pieces.assign(snapshot["pieces"])
	scenery = snapshot["scenery"]
	cursor = snapshot["cursor"]
	return true


func _remember() -> void:
	_history.append({"pieces": pieces.duplicate(), "scenery": scenery, "cursor": cursor})
	if _history.size() > HISTORY_LIMIT:
		_history.pop_front()


# --- Geometry -------------------------------------------------------------------

## What each piece builds as: its own kind, or FLAT when it no longer fits.
static func effective(values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	var level := 0
	var gaps := 0
	# Road blocks since the last gap, and how many of the latest keep full
	# speed. The start pad is a full landing but, as the car starts there
	# from rest, only one block of run-up.
	var road := RUNUP_BLOCKS
	var fast := 1
	var previous := Piece.FLAT
	for kind in values:
		if not _fits(kind, previous, level, gaps, road, fast):
			kind = Piece.FLAT
		level += int(kind == Piece.UP) - int(kind == Piece.DOWN)
		if kind == Piece.GAP:
			gaps += 1
			road = 0
		else:
			if gaps > 0:
				fast = 0
			gaps = 0
			road += 1
			fast = fast + 1 if kind in FAST_PIECES else 0
		previous = kind
		result.append(kind)
	return result


static func _fits(kind: int, previous: int, level: int, gaps: int, road: int, fast: int) -> bool:
	if kind != Piece.GAP and kind not in LEVEL_PIECES and road < RUNUP_BLOCKS:
		return false
	match kind:
		Piece.UP:
			return level < HIGHEST
		Piece.DOWN:
			# A dip climbs back up to a sharp crest, and the long car would sit on it.
			return level > LOWEST and previous != Piece.DIP
		Piece.GAP:
			if gaps == 0:
				return road >= RUNUP_BLOCKS and previous == Piece.FLAT
			return gaps < MAX_GAP_RUN and fast >= RUNUP_BLOCKS
	return true


static func _flattened(values: Array[int]) -> int:
	var built := effective(values)
	var count := 0
	for index in values.size():
		count += int(built[index] != values[index])
	return count


## Every block as drawn and driven: its built kind, left edge, start and end
## heights and road surface ("top" is empty over a gap).
func blocks() -> Array[Dictionary]:
	return _layout()["blocks"]


func trail_end() -> float:
	return TRAIL_START + pieces.size() * PIECE_WIDTH


func finish_x() -> float:
	return trail_end() + garage_distance()


## The flat road before the garage, plus any landing a gap at the very end
## still needs.
func garage_distance() -> float:
	var road := RUNUP_BLOCKS
	for kind in effective(pieces):
		road = 0 if kind == Piece.GAP else road + 1
	return GARAGE_DISTANCE + maxi(0, RUNUP_BLOCKS - road) * PIECE_WIDTH


## Route data in the shape of Course.ROUTES, ready for `Course.new(CUSTOM, route)`.
func to_route() -> Dictionary:
	var layout := _layout()
	var finish := finish_x()
	var checkpoints: Array[float] = [START_X]
	checkpoints.append_array(layout["flags"])
	return {
		"title": TITLE,
		"finish_x": finish,
		"end_x": finish + END_MARGIN,
		"scenery": int(scenery),
		"hill_color": HILL_COLORS[scenery],
		"plug_x": _plug_spots(layout["roads"], finish),
		"checkpoint_x": checkpoints,
		"roads": layout["roads"],
		"signs": [
			{"x": 360.0, "title": "MY TRAIL", "detail": "BUILT BY YOU"},
			{"x": finish - 200.0, "title": "GARAGE", "detail": "BRAKE TO FINISH"},
		],
	}


func _layout() -> Dictionary:
	var built := effective(pieces)
	var result_blocks: Array[Dictionary] = []
	var roads: Array = []
	var flags: Array[float] = []
	var road: Array = [Vector2(PAD_LEFT, BASE_Y), Vector2(TRAIL_START, BASE_Y)]
	var in_gap := false
	var level := 0
	var x := TRAIL_START
	for index in built.size():
		var kind := built[index]
		var y := height(level)
		level += int(kind == Piece.UP) - int(kind == Piece.DOWN)
		var end_y := height(level)
		var top: Array[Vector2] = []
		match kind:
			Piece.GAP:
				pass
			Piece.HILL:
				top = [Vector2(x, y), Vector2(x + PIECE_WIDTH * 0.5, y - BUMP_HEIGHT),
					Vector2(x + PIECE_WIDTH, y)]
			Piece.DIP:
				top = [Vector2(x, y), Vector2(x + PIECE_WIDTH * 0.5, y + BUMP_HEIGHT),
					Vector2(x + PIECE_WIDTH, y)]
			_:
				top = [Vector2(x, y), Vector2(x + PIECE_WIDTH, end_y)]
		if kind == Piece.GAP:
			if not in_gap:
				roads.append(road)
				in_gap = true
		else:
			if in_gap:
				road = [top[0]]
				in_gap = false
			for point in top.slice(1):
				_extend(road, point)
			if kind == Piece.FLAG:
				flags.append(x + PIECE_WIDTH * 0.5)
		result_blocks.append({
			"kind": kind, "placed": pieces[index], "x": x, "y": y, "end_y": end_y, "top": top,
		})
		x += PIECE_WIDTH
	var y := height(level)
	if in_gap:
		road = [Vector2(x, y)]
	_extend(road, Vector2(finish_x() + RUNOUT, y))
	roads.append(road)
	return {"blocks": result_blocks, "roads": roads, "flags": flags, "level": level}


## Straight runs stay one segment, like the handcrafted roads.
static func _extend(road: Array, point: Vector2) -> void:
	if road.size() >= 2:
		var a: Vector2 = road[-2]
		var b: Vector2 = road[-1]
		if is_zero_approx((b - a).cross(point - b)) and (b - a).dot(point - b) > 0.0:
			road[-1] = point
			return
	road.append(point)


## Five plugs spread evenly along the road, away from jumps and never over a
## gap, so the player never has to design where cargo goes.
static func _plug_spots(roads: Array, finish: float) -> Array[float]:
	var spans: Array[Vector2] = []
	var total := 0.0
	for index in roads.size():
		var road: Array = roads[index]
		var start: float = road[0].x + (LANDING_CLEARANCE if index > 0 else 0.0)
		var end: float = road[-1].x - (TAKEOFF_CLEARANCE if index < roads.size() - 1 else 0.0)
		start = maxf(start, TRAIL_START)
		end = minf(end, finish - PLUG_BEFORE_GARAGE)
		if end > start:
			spans.append(Vector2(start, end))
			total += end - start
	return _spread(spans, total)


static func _spread(spans: Array[Vector2], total: float) -> Array[float]:
	var spots: Array[float] = []
	if spans.is_empty():
		return spots
	for plug in PLUG_COUNT:
		var distance := total * (plug + 0.5) / PLUG_COUNT
		var spot := spans[-1].y
		for span in spans:
			if distance <= span.y - span.x:
				spot = span.x + distance
				break
			distance -= span.y - span.x
		spots.append(spot)
	return spots


static func _sanitized(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		if (value is int or value is float) and int(value) >= 0 and int(value) < PIECE_NAMES.size() \
			and result.size() < MAX_PIECES:
			result.append(int(value))
	return result
