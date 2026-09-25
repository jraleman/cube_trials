extends SceneTree

## The Trail Builder: its drivability rules on hand-picked and fuzzed trails,
## saving, the picture-only editor, the unlock gate and real drives through
## GameShell. Use a fresh, isolated user profile: this suite unlocks every car
## and writes the builder's own save.

const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Trail = preload("res://games/cube_trials/trail_layout.gd")
const TrailEditor = preload("res://games/cube_trials/trail_editor.gd")
const TrailCanvas = preload("res://games/cube_trials/trail_canvas.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const View = preload("res://games/cube_trials/course_view.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const TrialHUD = preload("res://games/cube_trials/trial_hud.gd")
const GAME := "res://games/cube_trials/gameplay.tscn"
const CAPTURE_ART := "res://games/cube_trials/tools/capture_art.gd"
const SCRATCH := "user://cube_trials_builder_test.cfg"
## One letter per Trail.Piece, so a case reads like the trail it builds:
## flat, up, down, hill, dip, gap and flag.
const LETTERS := "FUDHV_P"
const SEED := 20260925
## How often fuzzed edits pick each piece: gaps and flat road come up most, so
## long jumps, landings and run-ups get tried in every combination.
const WEIGHTS: Array[int] = [3, 1, 1, 1, 1, 3, 1]
## The rules restated here rather than read from Trail, so a change to either
## has to be made on purpose.
const LEVEL_ROAD: Array[int] = [Trail.Piece.FLAT, Trail.Piece.FLAG]
const FAST_ROAD: Array[int] = [Trail.Piece.FLAT, Trail.Piece.DOWN, Trail.Piece.FLAG]

var _failures := PackedStringArray()
var _first_seen := {}
var _session: Node
var _achievements: Node
var _store: Node
var _settings: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	get_root().size = Vector2i(1280, 720)
	GameCatalog.select(Options.GAME_ID)
	_session = get_root().get_node("GameSession")
	_achievements = get_root().get_node("AchievementManager")
	_store = get_root().get_node("Store")
	_settings = get_root().get_node("Settings")
	if FileAccess.file_exists(Trail.SAVE_PATH) or FileAccess.file_exists(SCRATCH) \
		or bool(_achievements.call("is_unlocked", Course.COPPER_COMPLETE)):
		printerr("cube_trials_builder_test needs a fresh, isolated user profile: "
			+ "it would overwrite this profile's trail and unlocks.")
		quit(1)
		return
	var original_values := (_settings.get("_values") as Dictionary).duplicate(true)
	var save_timer := _settings.get("_save_timer") as Timer
	var timer_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	_settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	_settings.call("set_value", "ui/scale", 1.0)
	_settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	_settings.call("set_value", Options.AIR_CONTROL_KEY, 1.0)
	_test_catalog()
	_test_editing()
	_test_rules()
	_test_fuzzed_trails()
	_test_persistence()
	_test_courses()
	await _test_route_views()
	_test_deliveries()
	await _test_gate()
	await _test_editor()
	await _test_scene_flow()
	await _test_hot_seat()
	Driver.release_controls()
	for path in [SCRATCH, Trail.SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_settings.set("_values", original_values)
	save_timer.stop()
	save_timer.process_mode = timer_mode
	await process_frame
	await create_timer(0.15).timeout
	if _failures.is_empty():
		print("Cube Trials Trail Builder tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


# --- The model ------------------------------------------------------------------

func _test_catalog() -> void:
	_expect(Trail.Piece.size() == Trail.PIECE_NAMES.size() and LETTERS.length() == Trail.PIECE_NAMES.size()
		and TrailEditor.PIECE_TIPS.size() == Trail.PIECE_NAMES.size()
		and WEIGHTS.size() == Trail.PIECE_NAMES.size(),
		"Every piece needs a saved name, a tooltip and a letter in these tests.")
	_expect(Trail.Scenery.size() == Course.Scenery.size()
		and Trail.SCENERY_NAMES.size() == Trail.Scenery.size()
		and Trail.HILL_COLORS.size() == Trail.Scenery.size()
		and TrailCanvas.PALETTES.size() == Trail.Scenery.size()
		and TrailEditor.SCENERY_TIPS.size() == Trail.Scenery.size(),
		"Every scenery needs a saved name, hill colour, builder palette and tooltip.")
	for key: String in Trail.Scenery:
		_expect(Course.Scenery.has(key) and Course.Scenery[key] == Trail.Scenery[key],
			"The builder's sceneries must use the levels' scenery ids.")
	for level in Course.LEVELS:
		var course := Course.new(str(level["id"]))
		_expect(Trail.HILL_COLORS[course.scenery].is_equal_approx(course.hill_color),
			"A built trail's hills must match the level with the same scenery.")
	_expect(Trail.START_X == Course.START_X and Trail.FINISH_WIDTH == Course.FINISH_WIDTH,
		"A built trail must start and park like every level.")

	var levels := Course.setup_levels()
	var builder: Dictionary = levels[-1]
	_expect(levels.size() == Course.LEVELS.size() + 1 and builder["id"] == Course.CUSTOM
		and builder["title"] == "Trail Builder" and not str(builder["description"]).is_empty(),
		"The setup screen must offer the Trail Builder after the three levels.")
	var manifest := GameCatalog.get_manifest(Options.GAME_ID)
	var offered := PackedStringArray()
	for option: Dictionary in manifest.levels:
		offered.append(str(option["id"]))
	var expected := PackedStringArray()
	for option in levels:
		expected.append(str(option["id"]))
	_expect(offered == expected and expected[0] == Course.COPPER,
		"The game must list its levels in order, then the Trail Builder.")
	# The last car to unlock is the one the latest level frees.
	var last_car := ""
	var latest := -1
	for character in Profiles.CHARACTERS:
		var requirement := str(character.get("requires_achievement", ""))
		for index in Course.LEVELS.size():
			if Course.LEVELS[index]["completion_achievement"] == requirement and index > latest:
				latest = index
				last_car = requirement
	_expect(not last_car.is_empty() and builder.get("requires_achievement", "") == last_car
		and not str(builder.get("locked_description", "")).is_empty()
		and Profiles.freed_by(last_car) == Profiles.CHARACTERS[-1]["id"],
		"The Trail Builder must open with the last car, and say so while it is locked.")
	var still := load(str(builder["icon"])) as Texture2D
	var reference := load(str(Course.LEVELS[0]["icon"])) as Texture2D
	_expect(still != null and reference != null and still.get_size() == reference.get_size(),
		"The Trail Builder needs its own still, the same size as the levels' stills.")
	for icon in ["play", "undo", "trash", "new_trail", "confirm", "build", "pause"]:
		_expect(load("res://games/cube_trials/assets/icons/%s.svg" % icon) is Texture2D,
			"The builder's %s picture must load." % icon)
	var files := GameSaves.save_files(manifest)
	_expect(files.size() == 1 and files[0]["path"] == Trail.SAVE_PATH
		and files[0]["title"] == "My Trail" and GameSaves.path_problem(Trail.SAVE_PATH).is_empty(),
		"The Saves screen must know the built trail as this game's own file.")

	var sample: Array[int] = Trail.SAMPLE
	_expect(_rule_break(sample).is_empty() and Trail.effective(sample) == sample,
		"The first trail must follow every rule it teaches.")
	for kind in Trail.PIECE_NAMES.size():
		_expect(kind in sample, "The first trail must show every piece: %s." % Trail.PIECE_NAMES[kind])
	var fresh := Trail.new()
	_expect(fresh.pieces == sample and fresh.scenery == Trail.Scenery.MOUNTAIN
		and fresh.cursor == sample.size() - 1 and not fresh.can_undo(),
		"A new trail must be the sample, picked at its end, with nothing to undo.")


func _test_editing() -> void:
	var trail := Trail.new(_pieces("FHU"))
	_expect(trail.cursor == 2, "A trail must start with its last block picked.")
	trail.select(-1)
	_expect(trail.add(Trail.Piece.FLAG) and _code(trail.pieces) == "PFHU" and trail.cursor == 0,
		"A piece added with the start picked must go first and become the pick.")
	trail.select(99)
	_expect(trail.cursor == 3, "Picking past the end must pick the last block.")
	trail.select(-9)
	_expect(trail.cursor == -1 and not trail.can_remove() and not trail.remove(),
		"The start pad can never be removed.")
	trail.select(1)
	_expect(trail.remove() and _code(trail.pieces) == "PHU" and trail.cursor == 0,
		"Remove must delete the picked block and pick the one before it.")
	_expect(trail.undo() and _code(trail.pieces) == "PFHU" and trail.cursor == 1,
		"Undo must bring back the block and the pick.")
	_expect(not trail.set_scenery(Trail.Scenery.MOUNTAIN) and not trail.set_scenery(7)
		and not trail.set_scenery(-1) and trail.scenery == Trail.Scenery.MOUNTAIN,
		"Picking the current or an unknown scenery must change nothing.")
	_expect(trail.set_scenery(Trail.Scenery.BEACH) and trail.scenery == Trail.Scenery.BEACH
		and trail.undo() and trail.scenery == Trail.Scenery.MOUNTAIN,
		"A scenery change must be one undoable step.")
	_expect(trail.undo() and _code(trail.pieces) == "FHU" and not trail.can_undo(),
		"Refused edits must not leave empty steps to undo.")
	trail.set_scenery(Trail.Scenery.SNOW)
	trail.select(2)
	_expect(trail.clear() and trail.pieces.is_empty() and trail.cursor == -1
		and trail.scenery == Trail.Scenery.SNOW and not trail.clear(),
		"A new trail must empty the blocks but keep the scenery.")
	_expect(trail.undo() and _code(trail.pieces) == "FHU" and trail.cursor == 2,
		"Undo must bring a cleared trail back.")

	var long := Trail.new([])
	for step in Trail.HISTORY_LIMIT + 10:
		long.add(Trail.Piece.FLAT)
	var undone := 0
	while long.undo():
		undone += 1
	_expect(undone == Trail.HISTORY_LIMIT and long.pieces.size() == 10,
		"Undo must keep the latest %d steps." % Trail.HISTORY_LIMIT)
	var full := Trail.new(_pieces("F".repeat(Trail.MAX_PIECES + 16)))
	_expect(full.pieces.size() == Trail.MAX_PIECES and not full.can_add(Trail.Piece.FLAT)
		and not full.add(Trail.Piece.FLAT) and full.pieces.size() == Trail.MAX_PIECES,
		"A trail must stop at %d blocks." % Trail.MAX_PIECES)
	full.select(10)
	_expect(not full.can_add(Trail.Piece.FLAT), "A full trail must refuse pieces anywhere.")
	var mixed := Trail.new([0, 99, -1, "gap", 5.0, 6, null, Vector2.ONE])
	_expect(_code(mixed.pieces) == "F_P", "A trail must keep only real pieces.")
	for kind in [-1, Trail.PIECE_NAMES.size()]:
		_expect(not mixed.can_add(kind) and not mixed.add(kind), "An unknown piece must never be added.")
	_expect(Trail.new([], Trail.Scenery.SNOW).scenery == Trail.Scenery.SNOW,
		"A new trail must keep the scenery it was given.")


func _test_rules() -> void:
	# The trail, the piece added at its end, and whether it fits.
	for case: Array in [
		["", "_", true], ["", "U", true], ["F", "_", true], ["P", "_", false], ["U", "_", false],
		["H", "_", false], ["F_", "_", true], ["_", "_", false], ["F__", "_", false],
		["F_", "F", true], ["F_", "P", true], ["F_", "U", false], ["F_", "D", false],
		["F_", "H", false], ["F_", "V", false], ["F_F", "U", false], ["F_F", "_", false],
		["F_FF", "U", true], ["F_FF", "_", true], ["UUUUUUUUU", "U", false],
		["UUUUUUUUU", "D", true], ["DDD", "D", false], ["DDD", "U", true], ["V", "D", false],
		["V", "H", true], ["VF", "D", true], ["HF_", "_", false], ["DF_", "_", true],
		["FF_FF_", "_", true], ["F__F", "U", false], ["F__FF", "_", true],
	]:
		var trail := Trail.new(_pieces(case[0]))
		var kind := LETTERS.find(case[1])
		var allowed: bool = case[2]
		var name := "'%s' after '%s'" % [case[1], case[0]]
		_expect(Trail.effective(trail.pieces) == trail.pieces and _rule_break(trail.pieces).is_empty(),
			"Rule cases must start from trails that follow the rules: " + name)
		_expect(trail.can_add(kind) == allowed and trail.add(kind) == allowed,
			"%s must be %s." % [name, "allowed" if allowed else "refused"])
		_expect(_rule_break(_pieces(case[0] + case[1])).is_empty() == allowed,
			"These tests' own rules must agree on " + name)
	# The trail, the block picked, the piece added after it, and whether it fits.
	for case: Array in [
		["FF_FF", 1, "U", false], ["FF_FF", 1, "F", true], ["D", -1, "V", false],
		["D", -1, "H", true], ["F_FF", 2, "_", false], ["F_FF", 2, "F", true],
		["F_FF", 1, "U", false], ["FF__", 0, "U", false], ["FF__", 0, "F", true],
	]:
		var trail := Trail.new(_pieces(case[0]))
		trail.select(case[1])
		var allowed: bool = case[3]
		_expect(trail.add(LETTERS.find(case[2])) == allowed
			and trail.cursor == (int(case[1]) + 1 if allowed else int(case[1])),
			"Adding '%s' after block %d of '%s' must be %s." % [
				case[2], case[1], case[0], "allowed" if allowed else "refused"])
	# Pieces that no longer fit build as flat road.
	for case: Array in [
		["UUUUUUUUUU", "UUUUUUUUUF"], ["DDDD", "DDDF"], ["P_", "PF"], ["F_U", "F_F"],
		["F___", "F__F"], ["VD", "VF"], ["_F_", "_FF"], ["U_", "UF"], ["F_UF_", "F_FF_"],
		["__", "_F"], ["P__", "PF_"],
	]:
		_expect(_code(Trail.effective(_pieces(case[0]))) == case[1], "'%s' must build as '%s'." % case)

	var trail := Trail.new(_pieces("UF_FF"))
	trail.select(1)
	trail.remove()
	var blocks := trail.blocks()
	_expect(_code(trail.pieces) == "U_FF" and _code(Trail.effective(trail.pieces)) == "UFFF"
		and blocks[1]["kind"] == Trail.Piece.FLAT and blocks[1]["placed"] == Trail.Piece.GAP
		and Course.new(Course.CUSTOM, trail.to_route()).roads.size() == 1,
		"A gap an edit leaves without flat road before it must build as road, not a hole.")
	trail.select(0)
	_expect(trail.can_add(Trail.Piece.FLAT), "Putting the flat road back must be allowed.")
	_expect(trail.undo() and Course.new(Course.CUSTOM, trail.to_route()).roads.size() == 2,
		"Undo must bring the jump back.")
	# The trail, and how many extra blocks of landing its garage road needs.
	for case: Array in [["", 0], ["FF", 0], ["FF_", 2], ["FF_F", 1], ["FF_FF", 0], ["FF_P", 1], ["P_", 0]]:
		var ending := Trail.new(_pieces(case[0]))
		_expect(is_equal_approx(ending.garage_distance(),
				Trail.GARAGE_DISTANCE + int(case[1]) * Trail.PIECE_WIDTH)
			and is_equal_approx(ending.finish_x(), ending.trail_end() + ending.garage_distance()),
			"After '%s' the garage road must leave %d more blocks to land on." % case)


func _test_fuzzed_trails() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for index in 400:
		var trail := Trail.new() if rng.randf() < 0.5 else Trail.new([])
		trail.set_scenery(rng.randi_range(0, Trail.Scenery.size() - 1))
		for step in rng.randi_range(4, 60):
			var roll := rng.randf()
			if roll < 0.7:
				trail.select(rng.randi_range(-1, trail.pieces.size() - 1))
				var kind := _random_piece(rng)
				var before := trail.pieces.duplicate()
				var flattened := _flattened(before)
				var allowed := trail.can_add(kind)
				_expect_trail(trail.add(kind) == allowed, "add() must do exactly what can_add() says.",
					_code(before))
				if allowed:
					_expect_trail(_flattened(trail.pieces) <= flattened,
						"An allowed piece must never flatten another.", _code(trail.pieces))
				else:
					_expect_trail(trail.pieces == before, "A refused piece must leave the trail as it was.",
						_code(before))
			elif roll < 0.85:
				trail.select(rng.randi_range(-1, trail.pieces.size() - 1))
				trail.remove()
			elif roll < 0.93:
				trail.undo()
			elif roll < 0.98:
				trail.set_scenery(rng.randi_range(0, Trail.Scenery.size() - 1))
			else:
				trail.clear()
		_check_trail(trail)
	# Raw piece lists, as a hand-edited save could hold, break every rule at once.
	for index in 200:
		var raw := []
		for piece in rng.randi_range(0, Trail.MAX_PIECES + 6):
			raw.append(rng.randi_range(0, Trail.PIECE_NAMES.size() - 1) if rng.randf() < 0.5
				else _random_piece(rng))
		var trail := Trail.new(raw)
		trail.set_scenery(rng.randi_range(0, Trail.Scenery.size() - 1))
		_check_trail(trail)


## Everything a trail promises however it was made: the rules, its blocks as
## drawn and its route as driven.
func _check_trail(trail: Trail) -> void:
	var placed := trail.pieces
	var code := _code(placed)
	var built := Trail.effective(placed)
	_expect_trail(built.size() == placed.size() and _rule_break(built).is_empty(),
		"Every trail must build as one that follows the rules.", code)
	_expect_trail(Trail.effective(built) == built, "A built trail must build as itself.", code)
	if _rule_break(placed).is_empty():
		_expect_trail(built == placed, "A trail that follows the rules must build exactly as placed.", code)
	for index in placed.size():
		if built[index] == placed[index]:
			continue
		var kept := built.slice(0, index)
		kept.append(placed[index])
		_expect_trail(built[index] == Trail.Piece.FLAT and not _rule_break(kept).is_empty(),
			"Only a piece that no longer fits may be built flat.", code)

	var blocks := trail.blocks()
	_expect_trail(blocks.size() == placed.size(), "Every placed piece must be one block.", code)
	var level := 0
	for index in blocks.size():
		var block := blocks[index]
		var kind: int = block["kind"]
		var x := Trail.TRAIL_START + index * Trail.PIECE_WIDTH
		var y := Trail.height(level)
		level += int(kind == Trail.Piece.UP) - int(kind == Trail.Piece.DOWN)
		var top: Array = block["top"]
		_expect_trail(kind == built[index] and block["placed"] == placed[index]
			and is_equal_approx(block["x"], x) and is_equal_approx(block["y"], y)
			and is_equal_approx(block["end_y"], Trail.height(level))
			and top.is_empty() == (kind == Trail.Piece.GAP),
			"Each block must be drawn where it is driven.", code)
		if not top.is_empty():
			_expect_trail(top[0].is_equal_approx(Vector2(x, y))
				and top[-1].is_equal_approx(Vector2(x + Trail.PIECE_WIDTH, Trail.height(level))),
				"A block's road must join its neighbours'.", code)

	var route := trail.to_route()
	var course := Course.new(Course.CUSTOM, route)
	_expect_trail(course.is_custom() and course.number == 0 and course.title == Trail.TITLE
		and course.label() == Trail.TITLE and course.short_label() == Trail.TITLE
		and course.completion_achievement().is_empty() and int(course.scenery) == int(trail.scenery)
		and course.hill_color == Trail.HILL_COLORS[trail.scenery],
		"A built trail must be its own course in its chosen scenery, with no reward.", code)
	_expect_trail(is_equal_approx(course.finish_x, trail.finish_x())
		and is_equal_approx(course.finish_x, trail.trail_end() + trail.garage_distance())
		and course.finish_x + course.finish_width < course.end_x,
		"The garage must follow the last block with room to park.", code)
	var runs := 0
	for index in built.size():
		runs += int(built[index] == Trail.Piece.GAP and (index == 0 or built[index - 1] != Trail.Piece.GAP))
	_expect_trail(course.roads.size() == runs + 1, "Every run of gaps must split the road.", code)
	var steepest := Trail.STEP_HEIGHT / Trail.PIECE_WIDTH
	for road: Array in course.roads:
		for index in road.size() - 1:
			var a: Vector2 = road[index]
			var b: Vector2 = road[index + 1]
			_expect_trail(a.is_finite() and b.is_finite() and b.x > a.x
				and absf(b.y - a.y) <= (b.x - a.x) * steepest + 0.01,
				"The road must run forward and never be steeper than a ramp.", code)
		for point: Vector2 in road:
			_expect_trail(point.y >= Trail.height(Trail.HIGHEST) - Trail.BUMP_HEIGHT - 0.01
				and point.y <= Trail.height(Trail.LOWEST) + Trail.BUMP_HEIGHT + 0.01
				and Art.world_point(point).y > Landscape.BEACH_SEA_Y,
				"The road must stay between the ceiling and the sea.", code)
	var gaps := course.gap_intervals()
	for index in gaps.size():
		var gap := gaps[index]
		var takeoff: Array = course.roads[index]
		var landing: Array = course.roads[index + 1]
		var width := gap.y - gap.x
		_expect_trail((is_equal_approx(width, Trail.PIECE_WIDTH) or is_equal_approx(width, Trail.PIECE_WIDTH * 2.0))
			and is_inf(course.ground_height((gap.x + gap.y) * 0.5)),
			"A gap must be one or two blocks of open air.", code)
		_expect_trail(is_equal_approx(takeoff[-1].y, takeoff[-2].y)
			and takeoff[-1].x - takeoff[-2].x >= Trail.PIECE_WIDTH - 0.01
			and is_equal_approx(landing[0].y, takeoff[-1].y) and is_equal_approx(landing[1].y, landing[0].y)
			and landing[1].x - landing[0].x >= Trail.LANDING_CLEARANCE - 0.01,
			"A gap needs flat road before it and level road to land on.", code)
	if not gaps.is_empty():
		_expect_trail(course.finish_x - gaps[-1].y >= Trail.GARAGE_DISTANCE + Trail.LANDING_CLEARANCE - 0.01,
			"The last landing must still leave the whole garage road.", code)
	_expect_trail(course.plug_x.size() == Trail.PLUG_COUNT, "Every trail must carry five plugs.", code)
	for index in course.plug_x.size():
		var x := course.plug_x[index]
		_expect_trail((index == 0 or x > course.plug_x[index - 1]) and x >= Trail.TRAIL_START
			and x <= course.finish_x - Trail.PLUG_BEFORE_GARAGE + 0.01 and course.plug_position(index).is_finite(),
			"Plugs must be in order, on the road and before the garage.", code)
		for gap in gaps:
			_expect_trail(x <= gap.x - Trail.TAKEOFF_CLEARANCE + 0.01
				or x >= gap.y + Trail.LANDING_CLEARANCE - 0.01,
				"Plugs must keep clear of takeoffs and landings.", code)
	var flags: Array[float] = [Trail.START_X]
	for block in blocks:
		if block["kind"] == Trail.Piece.FLAG:
			flags.append(block["x"] + Trail.PIECE_WIDTH * 0.5)
	_expect_trail(course.checkpoint_x == flags, "Every flag must be a checkpoint after the start.", code)
	for index in course.checkpoint_x.size():
		var spawn := course.spawn_position(index)
		for offset: float in [-75.0, 75.0]:
			_expect_trail(spawn.is_finite()
				and is_equal_approx(course.ground_height(spawn.x + offset), course.ground_height(spawn.x)),
				"Every checkpoint needs a flat pull-off.", code)
	var parked := course.ground_height(course.finish_x)
	_expect_trail(is_finite(parked)
		and is_equal_approx(course.ground_height(course.finish_x + course.finish_width), parked)
		and is_equal_approx(course.ground_height(course.finish_x - Trail.GARAGE_DISTANCE + 1.0), parked)
		and is_equal_approx(course.ground_height(course.end_x - 1.0), parked),
		"The garage road must be level from the last block to the end.", code)
	_expect_trail(course.signs.size() == 2 and is_equal_approx(course.signs[1]["x"], course.finish_x - 200.0),
		"A built trail must sign its start and its garage.", code)
	var run := State.new(Profiles.CUBE, Course.CUSTOM, route)
	_expect_trail(run.course.layout_key == course.layout_key and is_equal_approx(run.position.x, Trail.START_X),
		"A drive must start on the trail's own start pad.", code)

	var legal := _rule_break(placed).is_empty()
	var cursor := trail.cursor
	for pick in [-1, floori(placed.size() / 2.0) - 1, placed.size() - 1]:
		trail.select(pick)
		for kind in Trail.PIECE_NAMES.size():
			var trial := placed.duplicate()
			trial.insert(trail.cursor + 1, kind)
			var fits := placed.size() < Trail.MAX_PIECES and _flattened(trial) <= _flattened(placed)
			_expect_trail(trail.can_add(kind) == fits,
				"can_add() must allow exactly the pieces that flatten nothing new.", code)
			if legal and placed.size() < Trail.MAX_PIECES:
				_expect_trail(trail.can_add(kind) == _rule_break(trial).is_empty(),
					"On a trail that follows the rules, exactly the pieces that keep them must fit.", code)
	trail.select(cursor)


func _test_persistence() -> void:
	var trail := Trail.new(_pieces("FUP_FH"))
	trail.set_scenery(Trail.Scenery.SNOW)
	_expect(trail.save(SCRATCH) == OK, "A trail must save.")
	var config := ConfigFile.new()
	_expect(config.load(SCRATCH) == OK and config.get_value(Trail.SECTION, "format") == Trail.FORMAT
		and config.get_value(Trail.SECTION, "scenery") == "snow"
		and Array(config.get_value(Trail.SECTION, "pieces")) == ["flat", "up", "flag", "gap", "flat", "hill"],
		"A saved trail must keep every block as placed, by name.")
	var loaded := Trail.new([])
	loaded.add(Trail.Piece.FLAT)
	_expect(loaded.load_file(SCRATCH) and loaded.pieces == trail.pieces
		and loaded.scenery == Trail.Scenery.SNOW and loaded.cursor == trail.pieces.size() - 1
		and not loaded.can_undo(),
		"Loading must bring back the same blocks and scenery, with nothing to undo.")
	config = ConfigFile.new()
	config.set_value(Trail.SECTION, "scenery", "moon")
	config.set_value(Trail.SECTION, "pieces", ["flat", "rocket", "gap", 7, "FLAG", "flag"])
	config.save(SCRATCH)
	_expect(loaded.load_file(SCRATCH) and _code(loaded.pieces) == "F_P"
		and loaded.scenery == Trail.Scenery.MOUNTAIN,
		"Unknown pieces and sceneries in a save must be skipped, not guessed.")
	var many := PackedStringArray()
	for index in Trail.MAX_PIECES + 16:
		many.append("flat")
	config.set_value(Trail.SECTION, "pieces", many)
	config.save(SCRATCH)
	_expect(loaded.load_file(SCRATCH) and loaded.pieces.size() == Trail.MAX_PIECES,
		"A save can never hold more than a full trail.")
	config.set_value(Trail.SECTION, "pieces", 5)
	config.save(SCRATCH)
	_expect(loaded.load_file(SCRATCH) and loaded.pieces.is_empty(),
		"A save whose blocks are not a list must load as an empty trail.")
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("[trail\npieces = [\"flat\"")
	file.close()
	var kept := Trail.new(_pieces("FF"))
	_expect(not kept.load_file(SCRATCH) and _code(kept.pieces) == "FF"
		and not kept.load_file("user://cube_trials_no_such_trail.cfg") and _code(kept.pieces) == "FF",
		"A missing or unreadable save must keep the trail in hand.")

	_expect(Course.new(Course.CUSTOM).layout_key
		== Course.new(Course.CUSTOM, Trail.new().to_route()).layout_key,
		"Before anything is built, the Trail Builder must drive the sample trail.")
	trail.save(Trail.SAVE_PATH)
	var saved := Course.new(Course.CUSTOM)
	_expect(saved.layout_key == Course.new(Course.CUSTOM, trail.to_route()).layout_key
		and saved.scenery == Course.Scenery.SNOW,
		"A Trail Builder course without a route must drive the saved trail.")
	var manifest := GameCatalog.get_manifest(Options.GAME_ID)
	var summary := GameSaves.summary(manifest)
	_expect(bool(summary["has_save"]) and _lists_trail(summary["files"]),
		"The Saves screen must count a built trail as progress.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Trail.SAVE_PATH))
	_expect(not _lists_trail(GameSaves.summary(manifest)["files"]),
		"A deleted trail must leave the Saves screen.")


func _lists_trail(files: Array) -> bool:
	for entry: Dictionary in files:
		if entry["path"] == Trail.SAVE_PATH:
			return true
	return false


func _test_courses() -> void:
	var trail := Trail.new()
	var key := Course.new(Course.CUSTOM, trail.to_route()).layout_key
	_expect(key.begins_with(Course.CUSTOM + ":")
		and key == Course.new(Course.CUSTOM, Trail.new().to_route()).layout_key,
		"The same trail must always ask for the same scenery.")
	trail.add(Trail.Piece.FLAT)
	var longer := Course.new(Course.CUSTOM, trail.to_route()).layout_key
	trail.undo()
	trail.set_scenery(Trail.Scenery.BEACH)
	var beach := Course.new(Course.CUSTOM, trail.to_route()).layout_key
	trail.undo()
	_expect(longer != key and beach != key and longer != beach
		and Course.new(Course.CUSTOM, trail.to_route()).layout_key == key,
		"A new block or scenery must rebuild the scenery, and undo must match the original again.")
	_expect(Course.new(Course.CUSTOM, Trail.new(_pieces("P_")).to_route()).layout_key
		== Course.new(Course.CUSTOM, Trail.new(_pieces("PF")).to_route()).layout_key,
		"A piece built flat must drive, and look, exactly like flat road.")
	for level in Course.LEVELS:
		var course := Course.new(str(level["id"]))
		_expect(course.layout_key == course.id and not course.is_custom()
			and course.completion_achievement() == level["completion_achievement"]
			and course.label() == "Level %d - %s" % [course.number, course.title]
			and course.short_label() == "L%d / %s" % [course.number, course.title],
			"The handcrafted levels must keep their ids, rewards and labels.")


func _test_route_views() -> void:
	var view := View.new()
	view.size = Vector2(1280, 620)
	get_root().add_child(view)
	view.set_reduced_motion(true)
	for case: Array in [
		["", Trail.Scenery.MOUNTAIN], [_code(Trail.SAMPLE), Trail.Scenery.MOUNTAIN],
		["F__FFPF_FF", Trail.Scenery.BEACH], ["UUHF_FFPDV", Trail.Scenery.SNOW],
		["UUUUUUUUUFFDDDDDDDDDDDDF", Trail.Scenery.BEACH], ["FFHF", Trail.Scenery.SNOW],
	]:
		var trail := Trail.new(_pieces(case[0]))
		trail.set_scenery(case[1])
		var name := "Trail '%s' in the %s" % [case[0], Trail.SCENERY_NAMES[trail.scenery]]
		var run := State.new(Profiles.CRV, Course.CUSTOM, trail.to_route())
		view.configure(run)
		var world := view.world
		var course := run.course
		_expect(world.course.layout_key == course.layout_key
			and world.checkpoint_flags.size() == course.checkpoint_x.size() - 1
			and world.get_node("QuarryWater").get_child_count() == course.gap_intervals().size()
			and world.has_node("JumpApproachMarkers") == (course.gap_intervals().size() > 0)
			and not world.has_captive(),
			name + ": a built trail needs its own flags, a pool and takeoff marks at every gap and an empty garage.")
		_expect(world.has_node("CoastalOcean") == (trail.scenery == Trail.Scenery.BEACH)
			and world.has_node("OptionalSnowfall") == (trail.scenery == Trail.Scenery.SNOW),
			name + ": a built trail must dress in its chosen scenery.")
		for index in Trail.PLUG_COUNT:
			_expect(world.plugs[index].position.is_equal_approx(Art.world_point(course.plug_position(index))),
				name + ": the plugs drawn must be where they are collected.")
		var road := world.get_node("ExactDrivingSurface") as MeshInstance3D
		var vertices: PackedVector3Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point in vertices:
			var height := course.ground_height(point.x / Art.WORLD_SCALE)
			_expect(is_finite(height) and absf(point.y - Art.world_point(Vector2(0, height)).y) < 0.03,
				name + ": the road drawn must be the road driven.")
		view.configure(State.new(Profiles.CUBE, Course.CUSTOM, trail.to_route()))
		_expect(view.world == world, name + ": driving the same trail again must reuse its scenery.")
		await process_frame
	view.free()
	await process_frame


## Real drives from the start and from every flag, as after a crash there: a
## careful driver at 30 FPS and a kid holding full throttle at 60, in every car.
func _test_deliveries() -> void:
	var art: Array[int] = []
	art.assign((load(CAPTURE_ART) as GDScript).get_script_constant_map()["BUILDER_ART_TRAIL"])
	var codes: Array[String] = [
		_code(Trail.SAMPLE), _code(art), "", "FF_", "F__FFPF_FF", "FF_FFDF__FF",
		"UUUUUUUUUFPF_FF", "DDDHVHVFF_F", "FF_PPF_FF", _code(_long_trail()),
	]
	for code in codes:
		var trail := Trail.new(_pieces(code))
		_expect(_rule_break(trail.pieces).is_empty() and Trail.effective(trail.pieces) == trail.pieces,
			"Delivery trails must follow the rules: '%s'." % code)
		var route := trail.to_route()
		for checkpoint in (route["checkpoint_x"] as Array).size():
			for character in Profiles.CHARACTERS:
				for kid in [false, true]:
					var problem := _deliver(str(character["id"]), route, checkpoint, kid)
					_expect(problem.is_empty(),
						"Trail '%s' from checkpoint %d must deliver: %s." % [code, checkpoint, problem])


## Drives [param route] from [param checkpoint] with the plugs before it
## aboard. Returns why the delivery failed, or "".
func _deliver(vehicle_id: String, route: Dictionary, checkpoint: int, kid: bool) -> String:
	var run := State.new(vehicle_id, Course.CUSTOM, route)
	if checkpoint > 0:
		for plug in run.collected.size():
			run.collected[plug] = run.course.plug_x[plug] < run.course.checkpoint_x[checkpoint]
		run.checkpoint = checkpoint
		run._respawn()
	var fps := 60 if kid else 30
	for frame in fps * 150:
		var axes := Driver.controls(run)
		if kid and run.position.x < run.course.finish_x - 180.0:
			axes = Vector3(1.0, 0.0, axes.z)
		run.advance(1.0 / fps, axes.x, axes.y, axes.z, Driver.jump_pressed(run))
		if run.recoveries > 0 or run.is_over():
			break
	if run.finished and run.plug_count() == Trail.PLUG_COUNT and run.recoveries == 0:
		return ""
	return "%s in the %s stopped at x=%.0f with %d plugs and %d recoveries" % [
		"a kid at full throttle" if kid else "the driver", Profiles.new(vehicle_id).title,
		run.position.x, run.plug_count(), run.recoveries,
	]


## The longest trail there is, built one allowed piece at a time.
func _long_trail() -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var trail := Trail.new([])
	var guard := 0
	while trail.pieces.size() < Trail.MAX_PIECES and guard < 4000:
		guard += 1
		trail.add(_random_piece(rng))
	return trail.pieces


# --- The unlock -------------------------------------------------------------------

func _test_gate() -> void:
	_session.call("configure_single_player")
	_session.call("set_level", Course.CUSTOM)
	_expect((_session.call("selected_level") as Dictionary)["id"] == Course.COPPER,
		"A locked Trail Builder must not be picked, even from code.")
	await _check_picker(false)
	_achievements.call("unlock", Course.COPPER_COMPLETE)
	await _check_picker(false)
	_achievements.call("unlock", Course.SUNSET_COMPLETE)
	await _check_picker(true)
	_session.call("set_level", Course.CUSTOM)
	_expect((_session.call("selected_level") as Dictionary)["id"] == Course.CUSTOM,
		"Once every car is free, the Trail Builder must be a level to pick.")


func _check_picker(open: bool) -> void:
	var cars := true
	for character in Profiles.CHARACTERS:
		cars = cars and bool(_session.call("setup_option_is_unlocked", character))
	_expect(cars == open and bool(_session.call("setup_option_is_unlocked", Course.BUILDER)) == open,
		"The Trail Builder must open exactly when the last car does.")
	var menu := (load("res://scenes/menus/mode_select.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	menu.call("_on_single_player_pressed")
	var picker := menu.get("_level_choice") as OptionButton
	var index := Course.setup_levels().size() - 1
	_expect(picker != null and picker.item_count == index + 1 and picker.get_item_icon(index) != null,
		"The level picker must show the Trail Builder with its picture.")
	if picker != null and picker.item_count > index:
		_expect(picker.is_item_disabled(index) != open
			and picker.get_item_text(index) == "Trail Builder" + ("" if open else " (Locked)")
			and picker.get_popup().get_item_tooltip(index)
				== str(Course.BUILDER["description" if open else "locked_description"]),
			"A locked Trail Builder must say how to open it, and an open one what it is.")
	menu.free()
	await process_frame


# --- The editor -------------------------------------------------------------------

func _test_editor() -> void:
	var trail := Trail.new(_pieces(_code(Trail.SAMPLE) + "F".repeat(12)))
	var editor := TrailEditor.new()
	editor.trail = trail
	editor.save_path = SCRATCH
	editor.set_reduced_motion(true)
	var requests := {"play": 0, "pause": 0}
	editor.play_requested.connect(func() -> void: requests["play"] += 1)
	editor.pause_requested.connect(func() -> void: requests["pause"] += 1)
	get_root().add_child(editor)
	var screen := get_root().get_visible_rect().size
	editor.size = screen
	editor.fit(Rect2(Vector2.ONE * 12.0, screen - Vector2.ONE * 24.0), 1.0)
	editor.open()
	await _frames(3)
	var canvas := editor.canvas
	_expect(editor.find_children("*", "Label", true, false).is_empty()
		and editor.find_children("*", "RichTextLabel", true, false).is_empty()
		and editor.find_children("*", "LineEdit", true, false).is_empty(),
		"The Trail Builder must not need reading: no words anywhere.")
	var buttons: Array[Button] = editor.call("_all_buttons")
	_expect(buttons.size() == 7 + Trail.Scenery.size() + Trail.PIECE_NAMES.size(),
		"The builder needs its seven tools, three sceneries and seven pieces.")
	for button in buttons:
		_expect(button.text.is_empty() and button.icon == null and button.has_node("Glyph")
			and not button.tooltip_text.is_empty() and not button.accessibility_name.is_empty(),
			"%s must be a picture with a tooltip and a screen-reader name." % button.name)
	_expect(not canvas.tooltip_text.is_empty()
		and canvas.accessibility_name.contains("%d blocks" % trail.pieces.size()),
		"The trail picture must describe itself to a screen reader.")
	_expect(get_root().gui_get_focus_owner() == editor.play_button,
		"Opening the builder must put keyboard focus on Play.")
	for kind in Trail.PIECE_NAMES.size():
		_expect(not editor.piece_buttons[kind].disabled, "Every piece must fit after flat road.")
	_expect(editor.undo_button.disabled and not editor.remove_button.disabled
		and not editor.new_button.disabled and editor.scenery_buttons[0].button_pressed,
		"A fresh builder has nothing to undo, a block to remove and its scenery picked.")

	await _scroll_to_end(editor, -1)
	_expect(is_equal_approx(canvas.scroll, Trail.PAD_LEFT + 300.0) and editor.scroll_back_button.disabled
		and not editor.scroll_on_button.disabled,
		"Scrolling back must stop at the start pad, and then only scroll on.")
	_tap(_on_screen(canvas, canvas.block_center(1)))
	await _frames(1)
	_expect(trail.cursor == 1 and canvas.accessibility_name.contains("Picked: 2, Ramp up"),
		"Tapping a block must pick it.")
	for kind in Trail.PIECE_NAMES.size():
		_expect(editor.piece_buttons[kind].disabled == (kind == Trail.Piece.GAP),
			"After a ramp, only the gap must be greyed out.")
	_tap(_on_screen(canvas, canvas.block_center(-1)))
	await _frames(1)
	_expect(trail.cursor == -1 and canvas.accessibility_name.contains("Picked: start")
		and editor.remove_button.disabled,
		"Tapping the start pad must pick the start, which cannot be removed.")
	_tap(_on_screen(canvas, canvas.block_center(1)))
	await _frames(1)

	var count := trail.pieces.size()
	_tap_button(editor.piece_buttons[Trail.Piece.FLAT])
	await _frames(1)
	_expect(trail.pieces.size() == count + 1 and trail.cursor == 2 and trail.pieces[2] == Trail.Piece.FLAT
		and not editor.undo_button.disabled and _saved_as(trail),
		"Tapping a piece must add it after the pick, pick it and save the trail.")
	_tap_button(editor.remove_button)
	await _frames(1)
	_expect(trail.pieces.size() == count and trail.cursor == 1 and _saved_as(trail),
		"The bin must remove the picked block and save.")
	_tap_button(editor.undo_button)
	await _frames(1)
	_expect(trail.pieces.size() == count + 1 and trail.cursor == 2 and _saved_as(trail),
		"Undo must bring the block back and save.")
	for keycode in [KEY_DELETE, KEY_BACKSPACE]:
		_key(keycode)
		_expect(trail.pieces.size() == count and trail.cursor == 1,
			"%s must remove the picked block." % OS.get_keycode_string(keycode))
		_key(KEY_Z, true)
		_expect(trail.pieces.size() == count + 1 and trail.cursor == 2 and _saved_as(trail),
			"Ctrl+Z must undo.")

	var before := canvas.scroll
	var middle := _on_screen(canvas, canvas.size * 0.5)
	_drag(middle, middle - Vector2(300.0, 0.0))
	await _frames(1)
	_expect(canvas.scroll > before + 100.0 and trail.cursor == 2,
		"Dragging the picture must scroll the trail without picking a block.")
	before = canvas.scroll
	_wheel(middle, MOUSE_BUTTON_WHEEL_DOWN)
	_expect(is_equal_approx(canvas.scroll, before + Trail.PIECE_WIDTH),
		"The mouse wheel must scroll one block.")
	await _scroll_to_end(editor, 1)
	_expect(editor.scroll_on_button.disabled and not editor.scroll_back_button.disabled
		and canvas.world_x(canvas.size.x) > trail.finish_x() + Trail.FINISH_WIDTH,
		"Scrolling on must stop once the garage is in view.")
	await _scroll_to_end(editor, -1)

	_tap_button(editor.scenery_buttons[Trail.Scenery.BEACH])
	await _frames(1)
	_expect(trail.scenery == Trail.Scenery.BEACH and _picked_scenery(editor) == [Trail.Scenery.BEACH]
		and _saved_as(trail),
		"Tapping a scenery must pick it, alone, and save.")
	_tap_button(editor.undo_button)
	await _frames(1)
	_expect(trail.scenery == Trail.Scenery.MOUNTAIN and _picked_scenery(editor) == [Trail.Scenery.MOUNTAIN],
		"Undoing a scenery must pick the old one, alone.")

	var glyph := editor.new_button.get_node("Glyph")
	count = trail.pieces.size()
	_tap_button(editor.new_button)
	_expect(trail.pieces.size() == count and glyph.get("texture") == TrailEditor.CONFIRM
		and editor.new_button.tooltip_text == "Tap again to clear the trail",
		"The first tap on New must only ask again, with a tick.")
	_tap_button(editor.new_button)
	await _frames(1)
	_expect(trail.pieces.is_empty() and glyph.get("texture") == TrailEditor.NEW_TRAIL
		and editor.new_button.disabled and editor.remove_button.disabled and _saved_as(trail),
		"The second tap on New must clear the trail and save it.")
	_tap_button(editor.undo_button)
	await _frames(1)
	_expect(trail.pieces.size() == count, "Undo must bring a cleared trail back.")
	_tap_button(editor.new_button)
	editor.call("_process", TrailEditor.CONFIRM_SECONDS + 0.1)
	_expect(glyph.get("texture") == TrailEditor.NEW_TRAIL, "An unanswered New must give up after a moment.")
	_tap_button(editor.new_button)
	_tap_button(editor.piece_buttons[Trail.Piece.FLAT])
	_tap_button(editor.new_button)
	_expect(trail.pieces.size() == count + 1 and glyph.get("texture") == TrailEditor.CONFIRM,
		"Any edit must cancel a waiting New.")
	_tap(_on_screen(canvas, canvas.block_center(0)))
	await _frames(1)
	_expect(glyph.get("texture") == TrailEditor.NEW_TRAIL and trail.cursor == 0,
		"Picking a block must cancel a waiting New too.")

	_tap_button(editor.play_button)
	_tap_button(editor.pause_button)
	_expect(requests["play"] == 1 and requests["pause"] == 1, "Play and Pause must each ask once.")
	editor.set_reduced_motion(false)
	_expect(not canvas.reduced_motion, "The picture must animate unless motion is reduced.")
	editor.set_reduced_motion(true)
	editor.close()
	_expect(not editor.visible, "Closing the builder must hide it.")
	editor.open()
	await _frames(1)
	_expect(editor.visible and get_root().gui_get_focus_owner() == editor.play_button,
		"Reopening the builder must focus Play again.")
	editor.free()
	await process_frame


func _scroll_to_end(editor: TrailEditor, direction: int) -> void:
	var button := editor.scroll_on_button if direction > 0 else editor.scroll_back_button
	for press in 40:
		if button.disabled:
			break
		_tap_button(button)
		await process_frame
	_expect(button.disabled, "The %s arrow must reach the end of the trail." % (
		"on" if direction > 0 else "back"))


func _picked_scenery(editor: TrailEditor) -> Array[int]:
	var picked: Array[int] = []
	for scenery in editor.scenery_buttons.size():
		if editor.scenery_buttons[scenery].button_pressed:
			picked.append(scenery)
	return picked


func _saved_as(trail: Trail) -> bool:
	var saved := Trail.new([])
	return saved.load_file(SCRATCH) and saved.pieces == trail.pieces and saved.scenery == trail.scenery


# --- The game -------------------------------------------------------------------

func _test_scene_flow() -> void:
	_session.call("set_character_for_player", 0, Profiles.CRV)
	var game := _new_game()
	await _frames(3)
	var editor: TrailEditor = game.get("_editor")
	var view := game.get("_view") as View
	var hud := game.get("_trial_hud") as TrialHUD
	var build := game.get("_build_button") as Button
	var round_over := game.get_node("%RoundOver") as Control
	var note := str((game.get_script() as GDScript).get_script_constant_map()["TRAIL_NOTE"])
	_expect(editor != null and bool(game.call("is_building")) and editor.is_visible_in_tree()
		and not bool(game.get("_round_active")) and not view.visible and not hud.visible
		and view.world_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"The Trail Builder must open first, with the drive behind it stopped and not drawn.")
	_expect(editor.trail == game.get("_trail") and editor.trail.pieces == Trail.SAMPLE
		and editor.save_path == Trail.SAVE_PATH,
		"A first visit must build the sample trail and save to the builder's own file.")
	_expect(get_root().gui_get_focus_owner() == editor.play_button,
		"The builder must open with keyboard focus on Play.")

	var unlocked: int = _achievements.call("unlocked_count")
	var progression := (_achievements.get("_progression") as Dictionary).duplicate(true)
	var sparks: int = _store.call("points", Options.GAME_ID)
	var world_id := view.world.get_instance_id()
	editor.play_button.pressed.emit()
	await _frames(2)
	var state: State = game.get("_state")
	_expect(not bool(game.call("is_building")) and bool(game.get("_round_active")) and view.visible
		and hud.visible and build.is_visible_in_tree() and state.course.is_custom()
		and state.vehicle.id == Profiles.CRV
		and state.course.layout_key == Course.new(Course.CUSTOM, editor.trail.to_route()).layout_key
		and view.world.get_instance_id() == world_id
		and view.world_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Play must drive the trail as built, in the chosen car, in the scenery already made for it.")
	_drive_turn(game)
	# The results focus Play Again a frame later; no player taps Build before that.
	await _frames(1)
	_expect(state.finished and not bool(game.call("is_revealing")) and round_over.visible,
		"A built trail's garage holds no car, so a delivery goes straight to the results.")
	_expect(int(_achievements.call("unlocked_count")) == unlocked
		and (_achievements.get("_progression") as Dictionary) == progression
		and int(_store.call("points", Options.GAME_ID)) == sparks
		and (game.get("_round_achievements") as Array).is_empty(),
		"A built trail must award no achievements, progress or Sparks, however well it is driven.")
	var highlight := (game.get("_round_highlight") as Label).text
	_expect(note in (game.get("_round_progression_notes") as PackedStringArray)
		and highlight.contains(note) and not highlight.contains("earned"),
		"The results must say a built trail is just for fun.")
	var stats: Dictionary = game.call("_player_stats", 0)
	var payload: Dictionary = game.call("_share_payload")
	_expect(stats["details"][0]["value"] == Trail.TITLE and payload["level_id"] == Course.CUSTOM
		and payload["level_number"] == 0 and payload["level_title"] == Trail.TITLE,
		"The results and share card must name the player's own trail.")
	var build_again := game.get("_results_build_button") as Button
	var again := game.get("_play_again_button") as Button
	_expect(build_again.is_visible_in_tree() and build_again.get_parent() == again.get_parent()
		and build_again.get_index() == again.get_index() + 1 and build_again.icon != null,
		"The results must offer Build right after Play Again.")

	build_again.pressed.emit()
	await _frames(2)
	_expect(bool(game.call("is_building")) and not round_over.visible and not view.visible,
		"Build on the results must return to the builder.")
	_expect(get_root().gui_get_focus_owner() == editor.play_button,
		"Back in the builder, Play must hold the keyboard focus, not the hidden Play Again.")
	editor.piece_buttons[Trail.Piece.FLAG].pressed.emit()
	var saved := Trail.new([])
	_expect(saved.load_file(Trail.SAVE_PATH) and saved.pieces == editor.trail.pieces
		and editor.trail.pieces.size() == Trail.SAMPLE.size() + 1,
		"Every edit must be saved straight away.")
	world_id = view.world.get_instance_id()
	editor.play_button.pressed.emit()
	await _frames(2)
	state = game.get("_state")
	_expect(view.world.get_instance_id() != world_id
		and view.world.course.layout_key == state.course.layout_key
		and view.world.checkpoint_flags.size() == 2 and state.course.checkpoint_x.size() == 3,
		"Driving an edited trail must build its new scenery, with the new flag.")

	Input.action_press(Options.THROTTLE)
	game.call("_update_round", 0.5, 0.0)
	Input.action_release(Options.THROTTLE)
	build.pressed.emit()
	await _frames(2)
	_expect(bool(game.call("is_building")) and not bool(game.get("_round_active")) and not round_over.visible
		and int(_achievements.call("unlocked_count")) == unlocked,
		"The HUD's build button must stop the drive, without results, and reopen the builder.")
	world_id = view.world.get_instance_id()
	editor.play_button.pressed.emit()
	await _frames(2)
	state = game.get("_state")
	_expect(view.world.get_instance_id() == world_id and state.elapsed == 0.0 and state.plug_count() == 0,
		"Driving an unchanged trail again must reuse its scenery and start afresh.")

	build.pressed.emit()
	await _frames(1)
	editor.pause_button.pressed.emit()
	await _frames(1)
	var menu: Node = game.get("_pause_menu")
	_expect(is_instance_valid(menu) and paused, "The builder's pause button must pause the game.")
	editor.play_button.pressed.emit()
	_expect(bool(game.call("is_building")), "Play must wait while the game is paused.")
	if is_instance_valid(menu):
		menu.call("resume")
	await _frames(2)
	_expect(not paused and bool(game.call("is_building"))
		and get_root().gui_get_focus_owner() == editor.play_button,
		"Closing the pause menu must return to the builder with Play focused.")
	game.call("_set_reduced_motion_enabled", false)
	_expect(not editor.canvas.reduced_motion, "The builder must follow the Reduced motion setting.")
	game.call("_set_reduced_motion_enabled", true)
	_expect(editor.canvas.reduced_motion, "The builder must follow the Reduced motion setting.")

	editor.play_button.pressed.emit()
	await _frames(1)
	game.call("_end_round")
	await _frames(1)
	var stopped := (game.get("_round_subtitle") as Label).text
	_expect(round_over.visible and stopped.contains(Trail.TITLE) and not stopped.contains("medal"),
		"Stopping a built trail must not mention a medal it could never earn.")
	var stopped_run: State = game.get("_state")
	again.pressed.emit()
	await _frames(1)
	state = game.get("_state")
	_expect(not bool(game.call("is_building")) and bool(game.get("_round_active")) and not round_over.visible
		and state != stopped_run and state.plug_count() == 0
		and state.course.layout_key == stopped_run.course.layout_key
		and view.visible and build.is_visible_in_tree(),
		"Play Again must drive the same built trail again, from its start.")
	build.pressed.emit()
	await _frames(1)
	editor.play_button.pressed.emit()
	await _frames(1)
	state = game.get("_state")
	state.failed = true
	state.lives_left = 0
	game.call("_update_round", 0.0, 0.0)
	var subtitle := (game.get("_round_subtitle") as Label).text
	_expect(round_over.visible and subtitle.contains(Trail.TITLE) and not subtitle.contains("points"),
		"Running out of lives on a built trail must not mention points it never pays.")
	await _test_layouts(game)
	game.free()
	await process_frame


## The builder and the HUD's build button on a desktop, two phones and a
## large UI scale: 44-pixel targets, all on screen, none on top of another.
func _test_layouts(game: Node) -> void:
	var editor: TrailEditor = game.get("_editor")
	var build := game.get("_build_button") as Button
	for layout: Array in [
		[Vector2i(1280, 720), 1.0], [Vector2i(390, 844), 1.0], [Vector2i(320, 844), 1.0],
		[Vector2i(390, 844), 1.5],
	]:
		var dimensions: Vector2i = layout[0]
		get_root().size = dimensions
		_settings.call("set_value", "ui/scale", layout[1])
		build.pressed.emit()
		await _frames(4)
		var name := "%dx%d at %d%%" % [dimensions.x, dimensions.y, roundi(float(layout[1]) * 100.0)]
		_check_builder_layout(editor, name)
		editor.play_button.pressed.emit()
		await _frames(4)
		_check_hud_layout(game, name)
	build.pressed.emit()
	get_root().size = Vector2i(1280, 720)
	_settings.call("set_value", "ui/scale", 1.0)
	await _frames(2)


func _check_builder_layout(editor: TrailEditor, name: String) -> void:
	var screen := get_root().get_visible_rect().grow(0.5)
	var physical := float(get_root().size.x) / get_root().get_visible_rect().size.x
	var canvas := editor.canvas
	var picture := canvas.get_global_rect()
	_expect(bool(editor.is_visible_in_tree()) and screen.encloses(picture)
		and canvas.world_scale() * Trail.PIECE_WIDTH * physical >= 44.0,
		"%s: the trail must be on screen, every block big enough to tap." % name)
	var placed: Array[Rect2] = []
	for button: Button in editor.call("_all_buttons"):
		var rect := button.get_global_rect()
		_expect(button.is_visible_in_tree() and screen.encloses(rect)
			and rect.size.x * physical >= 44.0 and rect.size.y * physical >= 44.0,
			"%s: %s must be on screen with a 44-pixel physical target (%s)." % [
				name, button.name, rect.size * physical])
		for other in placed:
			_expect(not rect.grow(-1.0).intersects(other.grow(-1.0)),
				"%s: the builder's buttons must not overlap." % name)
		if button != editor.scroll_back_button and button != editor.scroll_on_button:
			_expect(not rect.grow(-1.0).intersects(picture.grow(-1.0)),
				"%s: only the scroll arrows may sit on the trail picture." % name)
		placed.append(rect)


func _check_hud_layout(game: Node, name: String) -> void:
	var hud := game.get("_trial_hud") as TrialHUD
	var view := game.get("_view") as Control
	var build := game.get("_build_button") as Button
	var physical := float(get_root().size.x) / get_root().get_visible_rect().size.x
	var rect := build.get_global_rect()
	var camera := hud.camera_button.get_global_rect()
	_expect(build.is_visible_in_tree() and view.get_global_rect().grow(0.5).encloses(rect)
		and rect.size.x * physical >= 44.0 and rect.size.y * physical >= 44.0
		and rect.end.x <= camera.position.x + 0.5 and absf(rect.get_center().y - camera.get_center().y) < 1.0,
		"%s: the HUD's build button needs a 44-pixel target beside the camera, inside the view." % name)
	for counter: Control in [hud.lives_label, hud.points_label, hud.plugs_label, hud.time_label]:
		_expect(not rect.grow(-1.0).intersects(counter.get_global_rect().grow(-1.0)),
			"%s: the build button must not cover the HUD's counters." % name)


func _test_hot_seat() -> void:
	for player in 2:
		_session.call("set_character_for_player", player, Profiles.CHARACTERS[player]["id"])
	var game := _new_game(2)
	await _frames(2)
	var editor: TrailEditor = game.get("_editor")
	var note := str((game.get_script() as GDScript).get_script_constant_map()["TRAIL_NOTE"])
	_expect(bool(game.call("is_building")), "A hot-seat match on a built trail must open in the builder.")
	var sparks: int = _store.call("points", Options.GAME_ID)
	var unlocked: int = _achievements.call("unlocked_count")
	editor.play_button.pressed.emit()
	await _frames(1)
	_expect(not bool(game.call("is_building")) and bool(game.get("_round_active"))
		and not (game.get("_build_button") as Button).visible,
		"One driver must not rebuild the trail in the middle of a match.")
	var first: State = game.get("_state")
	first.collected.fill(true)
	first.finished = true
	game.call("_update_round", 0.0, 0.0)
	game.call("_process", 0.0)
	(game.get("_handoff_button") as Button).pressed.emit()
	game.call("_update_round", 0.0, 0.0)
	var second: State = game.get("_state")
	_expect(second != first and second.course.is_custom() and second.plug_count() == 0
		and second.course.layout_key == first.course.layout_key,
		"The second driver must drive the same built trail from its start.")
	second.failed = true
	second.lives_left = 0
	game.call("_update_round", 0.0, 0.0)
	_expect((game.get_node("%RoundOver") as Control).visible
		and note in (game.get("_round_progression_notes") as PackedStringArray)
		and not str(game.call("_best_combo_summary")).contains("payout")
		and int(_store.call("points", Options.GAME_ID)) == sparks
		and int(_achievements.call("unlocked_count")) == unlocked,
		"A hot-seat match on a built trail must pay and award nothing, and say so.")
	_expect((game.get("_results_build_button") as Button).is_visible_in_tree(),
		"Once the match is over, the results must offer Build.")
	game.free()
	await process_frame
	_session.call("configure_single_player")


func _new_game(players := 1) -> Node:
	_session.call("set_level", Course.CUSTOM)
	if players == 1:
		_session.call("configure_single_player")
	else:
		_session.call("configure_multiplayer", 0, 1, players)
	var game := (load(GAME) as PackedScene).instantiate()
	get_root().add_child(game)
	game.set_process(false)
	return game


func _drive_turn(game: Node) -> void:
	var run: State = game.get("_state")
	for frame in 30 * 120:
		Driver.hold_controls(run)
		game.call("_update_round", 1.0 / 30.0, 0.0)
		if run.is_over():
			break
	Driver.release_controls()
	_expect(run.finished, "The sample trail must finish through gameplay (x=%.1f, plugs=%d)." % [
		run.position.x, run.plug_count(),
	])


# --- Helpers --------------------------------------------------------------------

## Why a built trail could not be driven flat out, or "" when it can. The
## design's rules, written out again independently of Trail.effective().
func _rule_break(built: Array[int]) -> String:
	var level := 0
	# The latest gap block. The start pad counts as a full landing.
	var gap_end := -Trail.RUNUP_BLOCKS - 1
	for index in built.size():
		var kind := built[index]
		var before := built[index - 1] if index > 0 else Trail.Piece.FLAT
		level += int(kind == Trail.Piece.UP) - int(kind == Trail.Piece.DOWN)
		if level < Trail.LOWEST or level > Trail.HIGHEST:
			return "the road leaves the floor or the ceiling"
		if kind == Trail.Piece.DOWN and before == Trail.Piece.DIP:
			return "a ramp down straight out of a dip"
		if kind == Trail.Piece.GAP:
			if before != Trail.Piece.GAP:
				if before != Trail.Piece.FLAT:
					return "a gap without flat road before it"
				if index - gap_end - 1 < Trail.RUNUP_BLOCKS:
					return "a gap before the last landing is over"
			else:
				var first := index - 1
				if first > 0 and built[first - 1] == Trail.Piece.GAP:
					return "three gaps in a row"
				# Two blocks of full-speed road before a long jump; the pad is one.
				if first < 1 or (first > 1 and built[first - 2] not in FAST_ROAD):
					return "a long jump without a run-up"
			gap_end = index
		elif kind not in LEVEL_ROAD and index - gap_end <= Trail.RUNUP_BLOCKS:
			return "a slope or bump where a jump lands"
	return ""


func _flattened(values: Array[int]) -> int:
	var built := Trail.effective(values)
	var count := 0
	for index in values.size():
		count += int(built[index] != values[index])
	return count


func _random_piece(rng: RandomNumberGenerator) -> int:
	var total := 0
	for weight in WEIGHTS:
		total += weight
	var roll := rng.randi_range(1, total)
	for kind in WEIGHTS.size():
		if roll <= WEIGHTS[kind]:
			return kind
		roll -= WEIGHTS[kind]
	return Trail.Piece.FLAT


func _pieces(code: String) -> Array[int]:
	var result: Array[int] = []
	for letter in code:
		result.append(LETTERS.find(letter))
	return result


func _code(values: Array[int]) -> String:
	var text := ""
	for kind in values:
		text += LETTERS[kind]
	return text


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _on_screen(control: Control, local: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas() * local


func _tap_button(button: Button) -> void:
	_tap(button.get_global_transform_with_canvas() * (button.size * 0.5))


func _tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = point
		event.global_position = point
		get_root().push_input(event, true)


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	get_root().push_input(press, true)
	var last := from
	for step in range(1, 5):
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = from.lerp(to, step / 4.0)
		motion.global_position = motion.position
		motion.relative = motion.position - last
		last = motion.position
		get_root().push_input(motion, true)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.button_mask = 0
	release.position = to
	release.global_position = to
	get_root().push_input(release, true)


func _wheel(point: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		get_root().push_input(event, true)


func _key(keycode: Key, control := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.ctrl_pressed = control
		event.pressed = pressed
		get_root().push_input(event)


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)


## Records the first trail that breaks each promise, so a fuzz failure can be
## replayed by hand.
func _expect_trail(condition: bool, message: String, code: String) -> void:
	if condition or _first_seen.has(message):
		return
	_first_seen[message] = code
	_failures.append("%s First seen on '%s'." % [message, code])
