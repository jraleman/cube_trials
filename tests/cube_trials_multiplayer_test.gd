extends SceneTree

## All cars, real input-only deliveries, and independent two/three-player turns.
## Run with an isolated user profile: final turns intentionally pay the garage.

const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Portrait = preload("res://games/cube_trials/share_art.gd")
const Identity = preload("res://scripts/player_identity.gd")
const GAME := "res://games/cube_trials/gameplay.tscn"
var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	get_root().size = Vector2i(1280, 720)
	GameCatalog.select(Options.GAME_ID)
	var achievements := get_root().get_node("AchievementManager")
	achievements.call("unlock", Course.COPPER_COMPLETE)
	achievements.call("unlock", Course.SUNSET_COMPLETE)
	for character in Profiles.CHARACTERS:
		_test_vehicle(str(character["id"]))
	await _test_three_turns()
	await _test_two_player_tie()
	await _test_solo_selection()
	Driver.release_controls()
	get_root().get_node("GameSession").call("configure_single_player")
	await process_frame
	await create_timer(0.15).timeout
	_finish.call_deferred()


func _test_vehicle(id: String) -> void:
	var run := State.new(id)
	run.advance(1.5, 0, 0, 0)
	_expect(run.contacts == 2 and absf(
		run.course.ground_height(run.position.x) - run.position.y - run.vehicle.ride_height
	) < 0.75, id + ": the authored tire size must settle at the correct ride height.")
	var car := Cube.new(id)
	var other := Cube.new(id)
	get_root().add_child(car)
	get_root().add_child(other)
	car.apply_state(run)
	var pristine := _body_material(car, false)
	var original := pristine.albedo_color
	car.set_player_color(Identity.color(2))
	other.set_player_color(Identity.color(0))
	_expect(_body_material(car).albedo_color.is_equal_approx(Identity.color(2))
		and _body_material(other).albedo_color.is_equal_approx(Identity.color(0))
		and pristine.albedo_color == original, id + ": player paint must be instance-isolated.")
	for stage in 5:
		run.damage_stage = stage
		car.apply_state(run, true, 0, true, false, 1.0)
		_expect(car.damage_stage == stage and car.cockpit_position().is_finite(),
			id + ": every damage stage must retain a usable cockpit eye.")
		_expect(_body_material(car).albedo_color.is_equal_approx(Identity.color(2)),
			id + ": damage must preserve player paint.")
		var triangles := 0
		var surfaces := 0
		for part: MeshInstance3D in car.get("_parts"):
			if part.get_script() == Cube.Coilover:
				continue
			surfaces += part.mesh.get_surface_count()
			for surface in part.mesh.get_surface_count():
				var arrays := part.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
		_expect(triangles <= 48000 and surfaces <= 48,
			"%s stage %d exceeds its complete-car mesh budget." % [id, stage])
		var points: Dictionary = car.get("_damage_points")[stage]
		_expect(car.headlights[0].position.is_equal_approx(
			Vector3(points["LeftHeadlightSocket"]) * Cube.MODEL_SCALE + car.body_offset
		), id + ": the headlight must follow its own deformed socket.")
		var lamps := car.chassis.get_node("RearBrakeLights") as MeshInstance3D
		for surface in lamps.mesh.get_surface_count():
			var material := lamps.get_active_material(surface) as StandardMaterial3D
			_expect(material.emission_energy_multiplier > 1.7,
				id + ": every brake-light surface must illuminate.")
	for index in 2:
		var axle := run.vehicle.axles[index]
		var expected := Vector3(axle.x, -axle.y - State.Tuning.STATIC_LENGTH, 0) * Art.WORLD_SCALE
		_expect(car.axles[index].position.distance_to(expected) < 0.025,
			id + ": independent wheel pivots must follow this car's physical wheelbase.")
	car.set_player_color(Color.TRANSPARENT)
	car.set_finish(Options.PAINT_SIGNAL, Options.RIM_GRAPHITE)
	_expect(_body_material(car).albedo_color.is_equal_approx(Finish.swatch(Options.PAINT_SIGNAL)),
		id + ": the shared garage paint must work on this body.")
	car.set_finish("", "")
	_expect(_body_material(car).albedo_color == original,
		id + ": factory restoration must restore its own paint, not the Cube's bronze.")
	car.free()
	other.free()
	for assist: float in [0.5, 1.0, 1.5]:
		run = State.new(id)
		run.air_control = assist
		var fps := 30 if assist == 0.5 else (60 if assist == 1.0 else 144)
		for frame in fps * 100:
			var axes := Driver.controls(run)
			run.advance(1.0 / fps, axes.x, axes.y, axes.z, Driver.jump_pressed(run))
			if run.is_over():
				break
		_expect(run.finished and run.plug_count() == 5 and run.recoveries == 0
			and run.damage_stage == 0 and run.checkpoint == Course.CHECKPOINT_X.size() - 1,
			"%s must drive the mountain extension cleanly at %.0f%% air control / %d FPS (%s, x=%.1f)." % [
				id, assist * 100.0, fps, run.medal(), run.position.x,
			])
		print("%s input-only delivery at %.0f%% / %d FPS: %s, %d recoveries." % [
			id, assist * 100.0, fps, State.time_text(run.adjusted_time()), run.recoveries,
		])


func _body_material(car: Cube, active := true) -> StandardMaterial3D:
	var body := car.chassis.get_node(car.vehicle.body_part) as MeshInstance3D
	for surface in body.mesh.get_surface_count():
		var material := body.mesh.surface_get_material(surface) as StandardMaterial3D
		if material.resource_name in [Finish.BODY_COAT, Finish.MODERN_BODY_COAT]:
			return body.get_active_material(surface) as StandardMaterial3D if active else material
	assert(false, "The car lost its body-paint material.")
	return null


func _new_game(count: int) -> Node:
	var session := get_root().get_node("GameSession")
	if count == 1:
		session.call("configure_single_player")
	else:
		session.call("configure_multiplayer", 0, 1, count)
	var game := (load(GAME) as PackedScene).instantiate()
	get_root().add_child(game)
	game.set_process(false)
	return game


func _test_three_turns() -> void:
	var session := get_root().get_node("GameSession")
	for player in 3:
		session.call("set_character_for_player", player, Profiles.CHARACTERS[player]["id"])
	var store := get_root().get_node("Store")
	var banked: int = store.call("points", Options.GAME_ID)
	var game := _new_game(3)
	await process_frame
	var runs: Array = (game.get("_runs") as Array).duplicate()
	var view: Node = game.get("_view")
	var world_id: int = view.get("world").get_instance_id()
	_expect(runs.size() == 3 and game.get("_active_player") == 0
		and view.get("world").car.vehicle.id == Profiles.CUBE,
		"A three-player match must begin with the first selected car.")
	var first: State = runs[0]
	first.collected.fill(true)
	first.checkpoint = 3
	first.elapsed = 55.0
	first.recoveries = 2
	first.damage_stage = 3
	first.landed_flips = 2
	first.flip_points = 1000
	first.jump_points = 240
	first.hazard_points = 186
	first.landed_jumps = 2
	first.hazards_on = true
	first.finished = true
	Input.action_press(Options.THROTTLE)
	Input.action_press(Options.JUMP)
	Input.action_press(Options.HAZARDS)
	game.call("_update_round", 0.0, 0.0)
	game.call("_process", 3.0)
	var handoff := game.get("_handoff") as Control
	var start := game.get("_handoff_button") as Button
	_expect(handoff.visible and not game.get("_round_active") and start.disabled
		and first.elapsed == 55.0 and store.call("points", Options.GAME_ID) == banked,
		"Handoff must freeze play and rewards while held controls are released.")
	game.call("_start_next_turn")
	_expect(game.get("_active_player") == 0, "Held input cannot confirm a handoff.")
	Driver.release_controls()
	game.call("_process", 0.0)
	Input.action_press("ui_accept")
	start.pressed.emit()
	game.call("_update_round", 2.0, 0.0)
	var second: State = game.get("_state")
	_expect(game.get("_active_player") == 1 and second == runs[1]
		and second.elapsed == 0.0 and not second.started and second.damage_stage == 0
		and second.checkpoint == 0 and second.plug_count() == 0 and second.lives_left == 5
		and second.landed_flips == 0 and second.flip_points == 0 and second.pending_flips == 0
		and second.jump_points == 0 and second.hazard_points == 0
		and not second.hazards_on and not second.hazard_bonus,
		"P2 must start a fresh run without inheriting the confirmation press or P1's progress.")
	Input.action_release("ui_accept")
	game.call("_update_round", 0.0, 0.0)
	_expect(view.get("world").car.vehicle.id == Profiles.SONATA
		and _body_material(view.get("world").car).albedo_color.is_equal_approx(Identity.color(1)),
		"The second turn must use the selected Sonata in red.")
	second.collected[0] = true
	second.elapsed = 30.0
	second.recoveries = 1
	second.failed = true
	second.lives_left = 0
	second.damage_stage = 4
	game.call("_update_round", 0.0, 0.0)
	_expect(handoff.visible and (game.get("_handoff_title") as Label).text.contains("PLAYER 3")
		and store.call("points", Options.GAME_ID) == banked,
		"Running out of lives must hand off to P3, not publish premature results.")
	game.call("_process", 0.0)
	start.pressed.emit()
	game.call("_update_round", 0.0, 0.0)
	var third: State = game.get("_state")
	_expect(third == runs[2] and third.vehicle.id == Profiles.CRV
		and _body_material(view.get("world").car).albedo_color.is_equal_approx(Identity.color(2))
		and view.get("world").get_instance_id() == world_id,
		"P3 must use the green CR-V while reusing the same scenery.")
	third.collected.fill(true)
	third.elapsed = 40.0
	third.damage_stage = 2
	third.landed_flips = 3
	third.flip_points = 1500
	third.jump_points = 400
	third.hazard_points = 285
	third.landed_jumps = 3
	third.finished = true
	game.call("_update_round", 0.0, 0.0)
	_expect((game.get_node("%RoundOver") as Control).visible
		and (game.get_node("%ResultLabel") as Label).text == "PLAYER 3 WINS!",
		"Results must wait for the final driver and use adjusted finishing time.")
	var ui: Array = game.get("_player_ui")
	_expect((ui[2]["result_score"] as Label).text == str(third.score())
		and (ui[2]["stats"]["hits"] as Label).text == "5",
		"The third driver's result and detailed stats must be visible.")
	var expected: int = store.call("default_round_points", Options.GAME_ID,
		{"player_scores": [first.score(), second.score(), third.score()]})
	_expect(store.call("points", Options.GAME_ID) == banked + expected,
		"One shared payout must include the third player's best score.")
	var payload: Dictionary = game.call("_share_payload")
	_expect(payload["combo_value"] == 3 and payload["misses_value"] == 3
		and payload["combo_caption"] == "TOTAL RECOVERIES",
		"Shared summary metrics must include every driver's recoveries, not just the winner's.")
	_expect(payload["score_values"] == [first.score(), second.score(), third.score()]
		and payload["standings"] == [2, 0, 1] and payload["players"].size() == 3
		and payload["vehicle_id"] == Profiles.CRV and payload["player_color"] == Identity.color(2),
		"Sharing must retain every driver and identify the actual winning car.")
	_expect(payload["landed_flips"] == 5 and payload["flip_points"] == 2500
		and payload["players"][0]["landed_flips"] == 2
		and payload["players"][1]["flip_points"] == 0
		and payload["players"][2]["flip_points"] == 1500
		and payload["jump_points"] == 640 and payload["hazard_points"] == 471
		and payload["landed_jumps"] == 5 and payload["players"][0]["hazard_points"] == 186
		and payload["players"][1]["jump_points"] == 0 and payload["players"][2]["hazard_points"] == 285,
		"Hot-seat trick totals must include all drivers without sharing points between turns.")
	var portrait := Portrait.new()
	portrait.size = Vector2(512, 512)
	get_root().add_child(portrait)
	portrait.configure(payload)
	_expect(portrait.model.vehicle.id == Profiles.CRV and portrait.model.damage_stage == 2
		and _body_material(portrait.model).albedo_color.is_equal_approx(Identity.color(2)),
		"The share portrait must depict the winning CR-V, including paint and damage.")
	portrait.free()
	game.call("_on_play_again_pressed")
	var replay: Array = game.get("_runs")
	_expect(game.get("_active_player") == 0 and game.get("_scores") == [0, 0, 0]
		and not handoff.visible and replay[0] != first, "Replay must restart the complete turn order.")
	for player in 3:
		var run: State = replay[player]
		_expect(run.vehicle.id == Profiles.CHARACTERS[player]["id"] and run.elapsed == 0
			and run.plug_count() == 0 and run.lives_left == 5 and run.damage_stage == 0
			and run.landed_flips == 0 and run.flip_points == 0 and run.pending_flips == 0
			and run.jump_points == 0 and run.hazard_points == 0 and run.landed_jumps == 0
			and not run.hazards_on and not run.hazard_bonus,
			"Every replayed turn must retain its car but reset its complete run state.")
	_expect(first.finished and first.elapsed == 55.0 and first.checkpoint == 3
		and second.failed, "Later turns and replay must not mutate completed runs.")
	game.free()


func _test_two_player_tie() -> void:
	var session := get_root().get_node("GameSession")
	session.call("set_character_for_player", 0, Profiles.SONATA)
	session.call("set_character_for_player", 1, Profiles.SONATA)
	var game := _new_game(2)
	await process_frame
	for player in 2:
		var state: State = game.get("_state")
		state.collected.fill(true)
		state.elapsed = 50.001 + player * 0.007
		state.finished = true
		game.call("_update_round", 0.0, 0.0)
		if player == 0:
			game.call("_process", 0.0)
			(game.get("_handoff_button") as Button).pressed.emit()
			game.call("_update_round", 0.0, 0.0)
	_expect((game.get_node("%ResultLabel") as Label).text == "SHARED FIRST PLACE"
		and (game.get("_runs") as Array).size() == 2,
		"Two-player mode must finish after P2 and tie at the displayed hundredth.")
	game.free()


func _test_solo_selection() -> void:
	var session := get_root().get_node("GameSession")
	for id: String in [Profiles.SONATA, Profiles.CRV]:
		session.call("set_character_for_player", 0, id)
		var game := _new_game(1)
		await process_frame
		var state: State = game.get("_state")
		var view: Node = game.get("_view")
		_expect(state.vehicle.id == id and view.get("world").car.vehicle.id == id
			and view.get("world").car.player_color.a == 0.0,
			"Solo must use the chosen car without forcing multiplayer paint.")
		state.failed = true
		game.call("_update_round", 0.0, 0.0)
		_expect(not (game.get("_handoff") as Control).visible
			and (game.get_node("%RoundOver") as Control).visible,
			"Solo ending must still go directly to results.")
		game.free()


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Cube Trials fleet and hot-seat tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)
