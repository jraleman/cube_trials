extends SceneTree

## Use a fresh isolated profile. Run without --headless to check real store pixels.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")
const Preview = preload("res://games/cube_trials/store_preview.gd")
const Portrait = preload("res://games/cube_trials/share_art.gd")
const Identity = preload("res://scripts/player_identity.gd")
const FACTORIES := {
	Profiles.CUBE: Options.PAINT_FACTORY,
	Profiles.SONATA: Options.SONATA_PAINT_FACTORY,
	Profiles.CRV: Options.CRV_PAINT_FACTORY,
}
const PURCHASES := {
	Profiles.CUBE: Options.PAINT_CREEK,
	Profiles.SONATA: Options.SONATA_PAINT_LAGOON,
	Profiles.CRV: Options.CRV_PAINT_FOREST,
}
const PAINT_PRICES := [0, 525, 525, 840, 840, 1155, 1470, 2520]
const WHEEL_PRICES := [0, 630, 945, 945, 1260]

var _failures := PackedStringArray()
var _store: Node
var _session: Node
var _achievements: Node
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_store = get_root().get_node("Store")
	_session = get_root().get_node("GameSession")
	_achievements = get_root().get_node("AchievementManager")
	if FileAccess.file_exists("user://store.cfg") \
		or _achievements.call("is_unlocked", Course.COPPER_COMPLETE):
		printerr("cube_trials_store_test requires a fresh isolated user profile.")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cube-capture-dir="):
			_capture_dir = argument.trim_prefix("--cube-capture-dir=")
	if not _capture_dir.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
		if error != OK:
			printerr("Cannot create store capture directory: ", error_string(error))
			quit(1)
			return
	GameCatalog.restrict_to(Options.GAME_ID)
	get_root().theme = GameCatalog.theme().restyle(ThemeDB.get_project_theme())
	get_root().size = Vector2i(1280, 720)
	var settings := get_root().get_node("Settings")
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	_test_catalog()
	if DisplayServer.get_name() != "headless":
		await _test_first_open_previews(settings)
	_test_legacy_and_purchases()
	await _test_application()
	GameCatalog.clear_restriction()
	await process_frame
	await create_timer(0.15).timeout
	if _failures.is_empty():
		print("Cube Trials per-car store tests passed (%s)." % DisplayServer.get_name())
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_catalog() -> void:
	var items: Array[Dictionary] = _store.call("items", Options.GAME_ID)
	var colors := PackedStringArray()
	var counts := {Profiles.CUBE: 0, Profiles.SONATA: 0, Profiles.CRV: 0}
	var wheels := 0
	_expect(items.size() == 29 and _store.call("slots", Options.GAME_ID).size() == 4,
		"The garage must have three independent eight-color catalogs and five shared wheel finishes.")
	for item in items:
		var id := str(item["id"])
		var kind := str(item["kind"])
		var slots: Array[Dictionary] = _store.call("slots_for_item", Options.GAME_ID, id)
		if kind == Options.RIM_KIND:
			_expect(wheels < WHEEL_PRICES.size() and int(item["price"]) == WHEEL_PRICES[wheels],
				id + ": wheel prices must be exactly 21 times their original tiers.")
			wheels += 1
			_expect(slots.size() == 1 and slots[0]["id"] == Options.RIM_SLOT,
				id + ": wheels must retain the single shared slot.")
			continue
		var vehicle_id := str(Options.PAINT_KINDS.find_key(kind))
		_expect(counts.has(vehicle_id), id + ": every body paint must belong to a known car.")
		if not counts.has(vehicle_id):
			continue
		var index: int = counts[vehicle_id]
		_expect(index < PAINT_PRICES.size() and int(item["price"]) == PAINT_PRICES[index],
			id + ": paint prices must be exactly 21 times their original tiers.")
		counts[vehicle_id] = index + 1
		_expect(slots.size() == 1 and slots[0]["id"] == Options.PAINT_SLOTS[vehicle_id],
			id + ": a paint may be equipped only on its own car.")
		var color: Color = item["color"]
		_expect(not colors.has(color.to_html(false)),
			id + ": the three body-paint palettes must use distinct colors.")
		colors.append(color.to_html(false))
		_expect(color.is_equal_approx(Finish.swatch(id, Finish.FACTORY_COATS[vehicle_id])),
			id + ": the catalog swatch must match the actual material.")
	for vehicle_id: String in counts:
		_expect(counts[vehicle_id] == 8
			and _store.call("equipped_id", Options.GAME_ID, Options.PAINT_SLOTS[vehicle_id])
				== FACTORIES[vehicle_id]
			and _store.call("is_owned", Options.GAME_ID, FACTORIES[vehicle_id]),
			vehicle_id + ": each car must start in its own free factory paint.")
	_expect(wheels == 5 and _store.call("points", Options.GAME_ID) == 0,
		"New shelves must not grant money or duplicate the shared wheel catalog.")
	_expect(_store.call("default_round_points", Options.GAME_ID,
		{"single_player": true, "player_one_score": 6500}) == 43
		and _store.call("default_round_points", Options.GAME_ID,
		{"single_player": true, "player_one_score": 7000}) == 46,
		"The 21x prices must not also multiply the existing round and trick payouts.")


func _test_legacy_and_purchases() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("points", Options.GAME_ID, 524)
	legacy.set_value("owned", Options.GAME_ID, PackedStringArray([
		"cube_paint_factory", "cube_paint_signal", "cube_rim_factory", "cube_rim_graphite",
	]))
	legacy.set_value("equipped", Options.GAME_ID, {
		"cube_body_paint": "cube_paint_signal", "cube_wheel_finish": "cube_rim_graphite",
	})
	_expect(legacy.save("user://store.cfg") == OK, "The legacy store fixture must be writable.")
	_store.call("_load_state")
	_expect(_store.call("points", Options.GAME_ID) == 524
		and _store.call("equipped_id", Options.GAME_ID, Options.PAINT_SLOT) == "cube_paint_signal"
		and _store.call("equipped_id", Options.GAME_ID, Options.RIM_SLOT) == "cube_rim_graphite",
		"Legacy balances, Cube paint purchases and shared wheels must survive without a new charge.")
	for vehicle_id: String in [Profiles.SONATA, Profiles.CRV]:
		_expect(_store.call("equipped_id", Options.GAME_ID, Options.PAINT_SLOTS[vehicle_id])
			== FACTORIES[vehicle_id]
			and not _store.call("is_owned", Options.GAME_ID, PURCHASES[vehicle_id]),
			vehicle_id + ": legacy Cube purchases must not unlock the new car's palette.")
	_expect(not _store.call("purchase", Options.GAME_ID, Options.PAINT_SIGNAL)
		and not _store.call("purchase", Options.GAME_ID, Options.PAINT_CREEK)
		and _store.call("points", Options.GAME_ID) == 524,
		"An already-owned paint or a 525-Spark paint bought with 524 Sparks must not spend money.")
	_store.call("add_points", Options.GAME_ID, 1)
	_expect(_store.call("purchase", Options.GAME_ID, Options.PAINT_CREEK)
		and _store.call("points", Options.GAME_ID) == 0,
		"The exact 525-Spark threshold must buy and equip only the Cube paint.")
	_store.call("add_points", Options.GAME_ID, 9000)
	_expect(not _store.call("purchase", Options.GAME_ID, Options.SONATA_PAINT_LAGOON)
		and not _store.call("purchase", Options.GAME_ID, Options.CRV_PAINT_FOREST)
		and _store.call("points", Options.GAME_ID) == 9000,
		"New paint purchases must respect the car unlocks even when the wallet can afford them.")
	_achievements.call("unlock", Course.COPPER_COMPLETE)
	_expect(_store.call("purchase", Options.GAME_ID, Options.SONATA_PAINT_LAGOON)
		and not _store.call("purchase", Options.GAME_ID, Options.CRV_PAINT_FOREST),
		"Level 1 must open the Sonata palette without opening the CR-V palette.")
	_achievements.call("unlock", Course.SUNSET_COMPLETE)
	_expect(_store.call("purchase", Options.GAME_ID, Options.CRV_PAINT_FOREST)
		and _store.call("points", Options.GAME_ID) == 7950,
		"Each new car's first paint must deduct its own 525-Spark purchase.")
	for vehicle_id: String in PURCHASES:
		for target_id: String in PURCHASES:
			if target_id == vehicle_id:
				continue
			_expect(not _store.call("equip", Options.GAME_ID, PURCHASES[vehicle_id],
				Options.PAINT_SLOTS[target_id]), "Cross-car paint equipping must be rejected.")
		_expect(_store.call("equipped_id", Options.GAME_ID, Options.PAINT_SLOTS[vehicle_id])
			== PURCHASES[vehicle_id], vehicle_id + ": buying another car's paint must not change this coat.")
	_expect(not _store.call("equip", Options.GAME_ID, Options.SONATA_PAINT_CORAL,
		Options.SONATA_PAINT_SLOT), "Unowned colors must not be equippable.")
	_expect(_store.call("equip", Options.GAME_ID, Options.SONATA_PAINT_FACTORY)
		and _store.call("equipped_id", Options.GAME_ID, Options.PAINT_SLOT) == Options.PAINT_CREEK
		and _store.call("equipped_id", Options.GAME_ID, Options.CRV_PAINT_SLOT) == Options.CRV_PAINT_FOREST,
		"Restoring one car's factory paint must leave the other two cars alone.")
	_store.call("equip", Options.GAME_ID, Options.SONATA_PAINT_LAGOON)
	_expect(_store.call("purchase", Options.GAME_ID, Options.RIM_BRONZE)
		and _store.call("equipped_id", Options.GAME_ID, Options.RIM_SLOT) == Options.RIM_BRONZE
		and _store.call("points", Options.GAME_ID) == 7005,
		"A wheel finish must still be bought once for the fleet at its exact 945-Spark price.")
	_store.call("equip", Options.GAME_ID, Options.RIM_GRAPHITE)
	var reloaded := (load("res://autoload/store.gd") as Script).new() as Node
	get_root().add_child(reloaded)
	for vehicle_id: String in PURCHASES:
		_expect(reloaded.call("equipped_id", Options.GAME_ID, Options.PAINT_SLOTS[vehicle_id])
			== PURCHASES[vehicle_id]
			and reloaded.call("is_owned", Options.GAME_ID, PURCHASES[vehicle_id]),
			vehicle_id + ": a fresh store instance must reload its independent purchase and selection.")
	_expect(reloaded.call("points", Options.GAME_ID) == 7005
		and reloaded.call("equipped_id", Options.GAME_ID, Options.RIM_SLOT) == Options.RIM_GRAPHITE
		and reloaded.call("is_owned", Options.GAME_ID, "cube_paint_signal"),
		"Saving new purchases must retain the legacy paint, shared wheels and exact balance.")
	reloaded.free()


func _test_application() -> void:
	for vehicle_id: String in PURCHASES:
		_session.call("configure_single_player")
		_session.call("set_level", Course.COPPER)
		_session.call("set_character_for_player", 0, vehicle_id)
		var game := (load("res://games/cube_trials/gameplay.tscn") as PackedScene).instantiate()
		get_root().add_child(game)
		game.set_process(false)
		var car: Cube = game.get("_view").world.car
		_expect(car.vehicle.id == vehicle_id and car.paint_id == PURCHASES[vehicle_id]
			and car.rim_id == Options.RIM_GRAPHITE
			and _body_color(car).is_equal_approx(Finish.swatch(PURCHASES[vehicle_id])),
			vehicle_id + ": a solo run must wear its own saved paint and the shared wheels.")
		var state: State = game.get("_state")
		state.damage_stage = 2
		game.get("_view").present(0.0)
		_store.call("equip", Options.GAME_ID, FACTORIES[vehicle_id])
		game.call("_on_pause_closed")
		_expect(car.paint_id == FACTORIES[vehicle_id] and car.damage_stage == 2
			and _body_color(car).to_html(false) == Finish.FACTORY_COATS[vehicle_id].to_html(false),
			vehicle_id + ": a paused respray must restore its own factory paint without repairing damage.")
		_store.call("equip", Options.GAME_ID, PURCHASES[vehicle_id])
		game.call("_on_pause_closed")
		game.call("_on_play_again_pressed")
		_expect(car.paint_id == PURCHASES[vehicle_id] and car.damage_stage == 0,
			vehicle_id + ": replay must retain the car-specific paint while resetting damage.")
		var payload: Dictionary = game.call("_share_payload")
		var portrait := Portrait.new()
		portrait.configure(payload)
		get_root().add_child(portrait)
		_expect(payload["paint_id"] == PURCHASES[vehicle_id]
			and portrait.model.vehicle.id == vehicle_id
			and _body_color(portrait.model).is_equal_approx(Finish.swatch(PURCHASES[vehicle_id])),
			vehicle_id + ": the score portrait must preserve the solo car and its paint.")
		if DisplayServer.get_name() != "headless":
			await _render()
		portrait.free()
		game.free()
		await process_frame
	_session.call("configure_multiplayer", 0, 1, 3)
	for player in 3:
		_session.call("set_character_for_player", player, Profiles.CHARACTERS[player]["id"])
	var game := (load("res://games/cube_trials/gameplay.tscn") as PackedScene).instantiate()
	get_root().add_child(game)
	game.set_process(false)
	for player in 3:
		game.call("_begin_turn", player)
		var state: State = game.get("_state")
		var car: Cube = game.get("_view").world.car
		_expect(car.paint_id == PURCHASES[state.vehicle.id]
			and _body_color(car).is_equal_approx(Identity.color(player))
			and car.rim_id == Options.RIM_GRAPHITE,
			"Hot seat must retain player-identifying paint and shared wheels after each car switch.")
		state.collected.fill(true)
		state.finished = true
		state.elapsed = 20.0 + player * 10.0
	var payload: Dictionary = game.call("_share_payload")
	_expect(payload["vehicle_id"] == Profiles.CUBE and payload["paint_id"] == Options.PAINT_CREEK
		and payload["player_color"] == Identity.color(0),
		"A hot-seat share image must identify the winning car's paint, not the last driver's palette.")
	if DisplayServer.get_name() != "headless":
		await _render()
	game.free()
	await process_frame


func _test_first_open_previews(settings: Node) -> void:
	var router := get_root().get_node("Router")
	for reduced in [false, true]:
		settings.call("set_value", Settings.REDUCED_MOTION_KEY, reduced)
		router.call("goto", "res://scenes/menus/store.tscn", false)
		await router.transition_finished
		await _render()
		var screen := current_scene
		_expect(screen != null, "The real store route must become the current scene.")
		if screen == null:
			return
		var cards: Array = screen.get("_cards")
		_expect(cards.size() == 29, "The real store must display all three paint shelves and shared wheels.")
		for dimensions in [Vector2i(1280, 720), Vector2i(390, 844)]:
			get_root().size = dimensions
			await _render()
			for card in cards:
				var item: Dictionary = _store.call("describe", Options.GAME_ID, card.item_id())
				_check_preview(card.get("_preview_instance") as Preview, item)
			if not reduced:
				await _capture("store-first-open-%dx%d" % [dimensions.x, dimensions.y])
		get_root().size = Vector2i(1280, 720)
		await _render()
		var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		var sections: VBoxContainer = screen.get("_sections")
		for shelf: Control in sections.get_children():
			scroll.scroll_vertical = roundi(shelf.position.y)
			await _render()
			if not reduced:
				await _capture("store-" + str(shelf.name))
		_expect(_store.call("points", Options.GAME_ID) == 0,
			"Rendering factory and unowned colors must not need a purchase, equip or wallet change.")
		current_scene = null
		screen.queue_free()
		await process_frame
	var early := Preview.new()
	early.size = Vector2(320, 176)
	early.configure(_store.call("describe", Options.GAME_ID, Options.PAINT_FACTORY))
	var item: Dictionary = _store.call("describe", Options.GAME_ID, Options.CRV_PAINT_FACTORY)
	early.configure(item)
	get_root().add_child(early)
	await _render()
	_check_preview(early, item)
	early.hide()
	item = _store.call("describe", Options.GAME_ID, Options.SONATA_PAINT_LAGOON)
	early.configure(item)
	early.size = Vector2(420, 220)
	await _render()
	early.show()
	await _render()
	_check_preview(early, item)
	early.free()
	var character := (load("res://games/cube_trials/character_preview.gd") as Script).new() as Preview
	character.size = Vector2(320, 176)
	character.configure({"id": Profiles.SONATA})
	get_root().add_child(character)
	await _render()
	_check_preview(character, _store.call("describe", Options.GAME_ID, Options.SONATA_PAINT_FACTORY))
	character.free()
	await process_frame


func _check_preview(preview: Preview, item: Dictionary) -> void:
	_expect(preview != null and preview.get("_subject") != null,
		str(item["id"]) + ": previews configured before or after readiness must build a subject.")
	if preview == null or preview.get("_subject") == null:
		return
	var viewport := preview.get("_viewport") as SubViewport
	var image := viewport.get_texture().get_image()
	var opaque := 0
	var samples := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			samples += 1
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	_expect(samples > 0 and float(opaque) / maxi(1, samples) > 0.08,
		str(item["id"]) + ": the routed card must contain visible model pixels before any equip action.")
	_expect(viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS
		and viewport.render_target_update_mode != SubViewport.UPDATE_WHEN_VISIBLE
		and not preview.get("_draw_queued"),
		"Store cards must settle to static one-shot rendering, not redraw continuously.")
	if str(item["kind"]) == Options.RIM_KIND:
		_expect((preview.get("_subject") as Node).name == "AlloyWheel",
			"A wheel finish must still show the actual shared alloy.")
		return
	var car := preview.get("_subject") as Cube
	var vehicle_id := str(Options.PAINT_KINDS.find_key(str(item["kind"])))
	var color: Color = item["color"]
	_expect(car != null and car.vehicle.id == vehicle_id
		and _body_color(car).to_html(false) == color.to_html(false),
		str(item["id"]) + ": the card must show the correct car in the advertised color.")


func _body_color(car: Cube) -> Color:
	var body := car.chassis.get_node(car.vehicle.body_part) as MeshInstance3D
	for surface in body.mesh.get_surface_count():
		var material := body.mesh.surface_get_material(surface)
		if material.resource_name in [Finish.BODY_COAT, Finish.MODERN_BODY_COAT]:
			return (body.get_active_material(surface) as StandardMaterial3D).albedo_color
	_expect(false, car.vehicle.id + ": the body must retain its named paint material.")
	return Color.TRANSPARENT


func _render() -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw


func _capture(title: String) -> void:
	if not _capture_dir.is_empty():
		var error := get_root().get_texture().get_image().save_png(_capture_dir.path_join(title + ".png"))
		_expect(error == OK, "Could not save store capture: " + title)


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
