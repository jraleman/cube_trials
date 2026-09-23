extends SceneTree

## Real gated setup, coloured previews, handoffs and results. Use a fresh isolated profile.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")
const Identity = preload("res://scripts/player_identity.gd")
var _failures := PackedStringArray()
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("cube_trials_multiplayer_view_test requires a graphics window.")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cube-capture-dir="):
			_capture_dir = argument.trim_prefix("--cube-capture-dir=")
	if not _capture_dir.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
		if error != OK:
			printerr(error_string(error))
			quit(1)
			return
	var settings := get_root().get_node("Settings")
	var original := (settings.get("_values") as Dictionary).duplicate(true)
	var timer := settings.get("_save_timer") as Timer
	timer.process_mode = Node.PROCESS_MODE_DISABLED
	settings.call("set_value", "accessibility/reduced_motion", true)
	settings.call("set_value", "ui/scale", 1.0)
	settings.call("set_value", "game/show_instructions", true)
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	GameCatalog.restrict_to(Options.GAME_ID)
	var achievements := get_root().get_node("AchievementManager")
	get_root().theme = GameCatalog.theme().restyle(ThemeDB.get_project_theme())
	get_root().size = Vector2i(1280, 720)
	var router := get_root().get_node("Router")
	router.call("goto", "res://scenes/menus/mode_select.tscn", false)
	await router.transition_finished
	await _render()
	var menu := current_scene
	(menu.get_node("%SinglePlayerButton") as Button).pressed.emit()
	var cards: Array = menu.get("_player_setup_cards")
	var level_choice := menu.get("_level_choice") as OptionButton
	_expect(level_choice.is_item_disabled(1) and level_choice.is_item_disabled(2)
		and (cards[0]["picker"] as OptionButton).is_item_disabled(1)
		and (cards[0]["picker"] as OptionButton).is_item_disabled(2),
		"A fresh profile must show the two earned levels and cars as locked.")
	get_root().size = Vector2i(390, 844)
	await _render()
	_expect(level_choice.get_global_rect().size.y
		* get_root().size.x / get_root().get_visible_rect().size.x >= 44.0,
		"The level picker must remain a physically usable phone-sized target.")
	await _capture("locked-levels-phone")
	achievements.call("unlock", Course.COPPER_COMPLETE)
	_expect(not level_choice.is_item_disabled(1) and level_choice.is_item_disabled(2)
		and not (cards[0]["picker"] as OptionButton).is_item_disabled(1)
		and (cards[0]["picker"] as OptionButton).is_item_disabled(2),
		"Clearing Level 1 must refresh the menu without also opening Level 3 or the CR-V.")
	level_choice.item_selected.emit(1)
	(cards[0]["picker"] as OptionButton).item_selected.emit(1)
	await _render()
	_expect((cards[0]["picker"] as OptionButton).get_global_rect().size.y
		* get_root().size.x / get_root().get_visible_rect().size.x >= 44.0,
		"The solo car picker must remain a physically usable phone-sized target.")
	_expect(((cards[0]["preview"] as Node).get("_subject") as Cube).vehicle.id == Profiles.SONATA,
		"Solo selection must display the actual Sonata.")
	await _capture("solo-car-selection-phone")
	achievements.call("unlock", Course.SUNSET_COMPLETE)
	level_choice.item_selected.emit(2)
	get_root().size = Vector2i(1280, 720)
	(menu.get_node("%PreviousButton") as Button).pressed.emit()
	(menu.get_node("%MultiplayerButton") as Button).pressed.emit()
	var count := menu.get("_player_count_choice") as OptionButton
	count.select(count.get_item_index(3))
	count.item_selected.emit(count.selected)
	for player in 3:
		(cards[player]["picker"] as OptionButton).item_selected.emit(player)
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(800, 900)]:
		get_root().size = dimensions
		await _render()
		_expect(count.get_selected_id() == 3,
			"The displayed player count must match the three-car roster.")
		for player in 3:
			var preview := cards[player]["preview"] as Control
			var car := preview.get("_subject") as Cube
			_expect(car != null and car.vehicle.id == Profiles.CHARACTERS[player]["id"]
				and _body_color(car).is_equal_approx(Identity.color(player)),
				"Each setup card must show its selected car in the correct seat colour.")
			_expect((cards[player]["panel"] as Control).size.x <= get_root().get_visible_rect().size.x,
				"Character cards must fit their available width.")
		_expect((menu.get_node("%ConfirmButton") as Button).is_visible_in_tree(),
			"The setup action must remain reachable with three car cards.")
		await _capture("three-car-selection-%dx%d" % [dimensions.x, dimensions.y])
	get_root().size = Vector2i(1280, 720)
	(menu.get_node("%ConfirmButton") as Button).pressed.emit()
	await router.transition_finished
	await _render()
	_expect(get_root().get_node("GameSession").call("player_count") == 3,
		"The real confirmation button must commit three players.")
	var briefing := current_scene
	_expect((briefing.get("_extra_control_cards") as Array).size() == 1,
		"The routed instructions must include the third driver.")
	await _capture("three-player-instructions")
	(briefing.get_node("%StartButton") as Button).pressed.emit()
	await router.transition_finished
	await process_frame
	var game := current_scene
	game.set_process(false)
	for player in 3:
		await _render()
		var state: State = game.get("_state")
		var view: Node = game.get("_view")
		_expect(state.course.id == Course.ALPINE and state.vehicle.id == Profiles.CHARACTERS[player]["id"]
			and _body_color(view.get("world").car).is_equal_approx(Identity.color(player)),
			"The live turn must match its chosen vehicle and player colour.")
		_expect((game.get("_trial_hud").driver_label as Label).text.contains("P%d" % (player + 1)),
			"The active driver must be identified by number, not just paint.")
		await _capture("hot-seat-driver-%d" % (player + 1))
		state.collected.fill(true)
		state.elapsed = 60.0 - player * 10.0
		state.finished = true
		game.call("_update_round", 0.0, 0.0)
		await _render()
		if player < 2:
			_check_panel(game.get("_handoff_panel"), "Handoff")
			await _capture("handoff-to-player-%d" % (player + 2))
			game.call("_process", 0.0)
			(game.get("_handoff_button") as Button).pressed.emit()
			game.call("_update_round", 0.0, 0.0)
	_check_panel(game.get("_round_panel"), "Three-player results")
	await _capture("three-player-results")
	(game.get_node("%SeeScoreButton") as Button).pressed.emit()
	for frame in 30:
		await process_frame
		if game.get("_share_card_round") == game.get("_round_id"):
			break
	await _render()
	_check_panel(game.get("_score_panel"), "Three-player detailed scores")
	var ui: Array = game.get("_player_ui")
	_expect((ui[2]["stats_card"] as Control).is_visible_in_tree(),
		"Detailed results must not drop Player 3.")
	await _capture("three-player-scorecard")
	var image := (game.get_node("%ShareCardPreview") as TextureRect).texture
	_expect(image != null and image.get_size() == Vector2(1200, 630),
		"The three-player share card must render at the established QR-safe resolution.")
	if image != null and not _capture_dir.is_empty():
		_expect(image.get_image().save_png(_capture_dir.path_join("three-player-share.png")) == OK,
			"The rendered share image must be writable.")
	(game.get_node("%BackToResultsButton") as Button).pressed.emit()
	(game.find_child("ChooseLevelButton", true, false) as Button).pressed.emit()
	await router.transition_finished
	await _render()
	_expect(current_scene.get("_level_choice") != null
		and (current_scene.get("_level_choice") as OptionButton).selected == 2,
		"The results action must return to level/car setup while retaining the previous selection.")
	settings.set("_values", original)
	timer.stop()
	timer.process_mode = Node.PROCESS_MODE_INHERIT
	var setup := current_scene
	current_scene = null
	setup.queue_free()
	GameCatalog.clear_restriction()
	await process_frame
	await create_timer(0.15).timeout
	_finish.call_deferred()


func _body_color(car: Cube) -> Color:
	var body := car.chassis.get_node(car.vehicle.body_part) as MeshInstance3D
	for surface in body.mesh.get_surface_count():
		var material := body.mesh.surface_get_material(surface)
		if material.resource_name in [Finish.BODY_COAT, Finish.MODERN_BODY_COAT]:
			return (body.get_active_material(surface) as StandardMaterial3D).albedo_color
	assert(false, "Missing body-paint surface.")
	return Color.TRANSPARENT


func _check_panel(panel: Control, title: String) -> void:
	var viewport := get_root().get_visible_rect()
	_expect(viewport.encloses(panel.get_global_rect()),
		"%s must fit the viewport: %s in %s." % [title, panel.get_global_rect(), viewport])


func _render() -> void:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw


func _capture(name: String) -> void:
	if not _capture_dir.is_empty():
		var image := get_root().get_texture().get_image()
		_expect(image.save_png(_capture_dir.path_join(name + ".png")) == OK, "Capture failed: " + name)


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Cube Trials multiplayer presentation tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)
