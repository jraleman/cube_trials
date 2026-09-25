extends SceneTree

## Run with a fresh, isolated user profile: these deliveries persist real unlocks.

const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const View = preload("res://games/cube_trials/course_view.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const GarageReveal = preload("res://games/cube_trials/world/garage_reveal.gd")
const GAME := "res://games/cube_trials/gameplay.tscn"

var _failures := PackedStringArray()
var _session: Node
var _achievements: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	get_root().size = Vector2i(1280, 720)
	GameCatalog.select(Options.GAME_ID)
	_session = get_root().get_node("GameSession")
	_achievements = get_root().get_node("AchievementManager")
	var settings := get_root().get_node("Settings")
	settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	settings.call("set_value", Options.ENGINE_AUDIO_KEY, false)
	settings.call("set_value", Options.AIR_CONTROL_KEY, 1.0)
	for level in Course.LEVELS:
		_test_geometry(Course.new(str(level["id"])))
		_test_recovery_and_parking(str(level["id"]))
	_test_new_drives()
	await _test_route_views()
	await _test_garage_reveals()
	await _test_progression()
	Driver.release_controls()
	await process_frame
	await create_timer(0.15).timeout
	if _failures.is_empty():
		print("Cube Trials level and progression tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_geometry(course: Course) -> void:
	_expect(course.scenery == [
		Course.Scenery.MOUNTAIN, Course.Scenery.BEACH, Course.Scenery.SNOW,
	][course.number - 1], course.title + ": each level must select its own scenery theme.")
	_expect(course.plug_x.size() == 5 and course.finish_x + course.finish_width < course.end_x,
		course.title + ": five pickups and a complete parking bay must fit inside the level.")
	_expect(course.gap_intervals().size() == [6, 4, 7][course.number - 1],
		course.title + ": each route must have its own authored crossings.")
	for road: Array in course.roads:
		for index in range(road.size() - 1):
			_expect(road[index].is_finite() and road[index].x < road[index + 1].x,
				course.title + ": terrain segments must be finite and ordered.")
	for gap in course.gap_intervals():
		_expect(is_inf(course.ground_height((gap.x + gap.y) * 0.5)),
			course.title + ": ravines must remain actual gaps in collision.")
	for index in course.plug_x.size():
		_expect(course.plug_position(index).is_finite() and course.plug_x[index] < course.finish_x,
			course.title + ": every plug must be on reachable terrain before the garage.")
	for index in course.checkpoint_x.size():
		var spawn := course.spawn_position(index)
		for offset: float in [-75.0, 0.0, 75.0]:
			_expect(is_equal_approx(course.ground_height(spawn.x + offset),
				course.ground_height(spawn.x)), course.title + ": recovery needs a flat pull-off.")
	_expect(is_equal_approx(course.ground_height(course.finish_x),
		course.ground_height(course.finish_x + course.finish_width)),
		course.title + ": the whole finish interval must be level.")


func _test_recovery_and_parking(level_id: String) -> void:
	for character in Profiles.CHARACTERS:
		var run := State.new(str(character["id"]), level_id)
		for index in range(1, run.course.checkpoint_x.size()):
			run.checkpoint = 0
			run.collected.fill(false)
			run.position = run.course.spawn_position(index)
			run.contacts = 2
			run._update_course()
			_expect(run.checkpoint == 0, level_id + ": a checkpoint must not strand earlier cargo.")
			run.collected.fill(true)
			run._update_course()
			_expect(run.checkpoint == index, level_id + ": collecting earlier plugs must open the checkpoint.")
			run.recover()
			_expect(is_equal_approx(run.position.x, run.course.checkpoint_x[index])
				and is_equal_approx(run.course.ground_height(run.position.x) - run.position.y,
					run.vehicle.ride_height),
				level_id + ": recovery must use this route and this car's ride height.")
		run.position = Vector2(run.course.finish_x + 100.0,
			run.course.ground_height(run.course.finish_x + 100.0) - run.vehicle.ride_height)
		run.contacts = 2
		run.collected[4] = false
		run._update_course()
		_expect(not run.finished, level_id + ": missing a plug must still block delivery.")
		run.collected[4] = true
		run.velocity.x = State.PARK_SPEED + 1.0
		run._update_course()
		_expect(not run.finished, level_id + ": passing through at speed must not finish.")
		run.velocity = Vector2.ZERO
		run._update_course()
		_expect(run.finished, level_id + ": parking with all five plugs must finish this route.")


func _test_new_drives() -> void:
	for level_id: String in [Course.SUNSET, Course.ALPINE]:
		for character in Profiles.CHARACTERS:
			for assist: float in [0.5, 1.0, 1.5]:
				var run := State.new(str(character["id"]), level_id)
				run.air_control = assist
				var fps := 30 if assist == 0.5 else (60 if assist == 1.0 else 144)
				for frame in fps * 110:
					var axes := Driver.controls(run)
					run.advance(1.0 / fps, axes.x, axes.y, axes.z, Driver.jump_pressed(run))
					if run.is_over():
						break
				_expect(run.finished and run.plug_count() == 5 and run.recoveries == 0
					and run.checkpoint == run.course.checkpoint_x.size() - 1,
					"%s / %s / %.0f%% / %d FPS must deliver using inputs alone (x=%.1f, plugs=%d, recoveries=%d, checkpoint=%d)." % [
						level_id, run.vehicle.title, assist * 100.0, fps, run.position.x,
						run.plug_count(), run.recoveries, run.checkpoint,
					])
				print("%s / %s / %.0f%%: %s, %d recoveries." % [
					run.course.title, run.vehicle.title, assist * 100.0,
					State.time_text(run.adjusted_time()), run.recoveries,
				])


func _test_route_views() -> void:
	var view := View.new()
	view.size = Vector2(1280, 620)
	get_root().add_child(view)
	for level in Course.LEVELS:
		var run := State.new(Profiles.CRV, str(level["id"]))
		view.configure(run)
		view.set_reduced_motion(true)
		var world := view.world
		var course := run.course
		_expect(world.course.id == course.id and view.course.id == course.id
			and world.checkpoint_flags.size() == course.checkpoint_x.size() - 1
			and world.get_node("QuarryWater").get_child_count() == course.gap_intervals().size(),
			course.title + ": switching routes must rebuild the correct scenery and flags.")
		for index in 5:
			_expect(world.plugs[index].position.is_equal_approx(Art.world_point(course.plug_position(index))),
				course.title + ": visible pickups must match collision anchors.")
		var road := world.get_node("ExactDrivingSurface") as MeshInstance3D
		var vertices: PackedVector3Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point in vertices:
			var height := course.ground_height(point.x / Art.WORLD_SCALE)
			_expect(is_finite(height)
				and absf(point.y - Art.world_point(Vector2(0, height)).y) < 0.03,
				course.title + ": road rendering must match the selected collision surface.")
		_test_scenery(world)
		var outline := world.get("_parking_outline") as MeshInstance3D
		_expect(is_equal_approx(outline.global_position.x,
			(course.finish_x + course.finish_width * 0.5) * Art.WORLD_SCALE),
			course.title + ": the glowing finish bay must be at this route's garage.")
		for checkpoint in course.checkpoint_x.size():
			run.checkpoint = checkpoint
			run._respawn()
			for mode in [View.CameraMode.SIDE, View.CameraMode.CHASE, View.CameraMode.COCKPIT]:
				view.set_camera_mode(mode)
				view.present(0.0)
				var eye := view.world_camera.position
				var ground := course.ground_height(eye.x / Art.WORLD_SCALE)
				_expect(eye.is_finite() and (not is_finite(ground)
					or eye.y > Art.world_point(Vector2(0, ground)).y),
					course.title + ": every camera must follow this route above the road.")
		view.configure(State.new(Profiles.CRV, course.id))
		_expect(view.world == world,
			course.title + ": replay and hot-seat turns must reuse the same themed scenery.")
		await process_frame
	view.configure(State.new())
	_expect(view.world.course.scenery == Course.Scenery.MOUNTAIN
		and not view.world.has_node("CoastalOcean") and not view.world.has_node("OptionalSnowfall")
		and view.world.daylight.sky_material.sky_top_color.is_equal_approx(Daylight.DAY_TOP),
		"Returning to Level 1 must restore its original landscape and daylight.")
	_test_scenery(view.world)
	view.free()
	await process_frame


## Each earned car waits behind its own level's garage door. The reveal depends
## only on its clock: every cue plays once and in order, skipping or changing
## Reduced motion keeps its place, and the shot holds the bay on any screen.
func _test_garage_reveals() -> void:
	for index in GarageReveal.KEYS.size():
		_expect(is_equal_approx(GarageReveal.remap_time(GarageReveal.KEYS[index], false, true),
				GarageReveal.REDUCED_KEYS[index])
			and is_equal_approx(GarageReveal.remap_time(GarageReveal.REDUCED_KEYS[index], true, false),
				GarageReveal.KEYS[index]),
			"Both reveal timings must share their door, bars and wake-up moments.")
	var view := View.new()
	view.size = Vector2(1280, 620)
	get_root().add_child(view)
	for level in Course.LEVELS:
		var captive := Profiles.freed_by(str(level["completion_achievement"]))
		var run := State.new(Profiles.CUBE, str(level["id"]))
		view.set_reduced_motion(false)
		view.configure(run)
		view.set_captive(captive)
		# Render each route before the next replaces it: the Compatibility renderer
		# leaks the radiance maps of a sky freed before its first frame.
		await process_frame
		var world := view.world
		if captive.is_empty():
			view.start_reveal()
			_expect(not world.has_captive() and not view.is_revealing(),
				run.course.title + ": a level that frees no car must never play a reveal.")
			continue
		var reveal := world.reveal
		var title := Profiles.new(captive).title
		_expect(world.has_captive() and reveal.visible and reveal.door_open == 0.0
			and not reveal.car.visible and reveal.sign_label.text.contains(title.to_upper()),
			title + " must wait unseen behind its level's labeled garage door.")
		_expect(_drawn(reveal) == PackedStringArray(["ClosedDoor", "SignLabel"])
			and (reveal.get_node("RollUpDoor/ClosedDoor") as GeometryInstance3D).cast_shadow
				== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			title + ": drivers pass the shut door all level, so it must cost one shadowless mesh and its sign.")
		_test_reveal_timeline(reveal, title)
		var outline := world.get("_parking_outline") as Node3D
		for reduced: bool in [false, true]:
			view.set_reduced_motion(reduced)
			view.configure(run)
			view.start_reveal()
			_expect(view.is_revealing() and not world.car.visible and not outline.visible,
				title + ": the parked car and its outline must leave the reveal's shot.")
			var heard := PackedStringArray()
			for step in 200:
				for cue in view.advance_reveal(0.05):
					heard.append(cue)
					_expect(absf(view.reveal_time - float(GarageReveal.cue_times(reduced)[cue])) < 0.051,
						title + ": each reveal cue must play at its own moment.")
				if view.reveal_complete():
					break
			_expect(heard == PackedStringArray(["door", "bars", "horn"])
				and view.advance_reveal(1.0).is_empty(),
				title + ": every reveal cue must play exactly once, in order.")
		view.set_reduced_motion(false)
		view.configure(run)
		view.start_reveal()
		view.advance_reveal(3.5)
		view.set_reduced_motion(true)
		_expect(is_equal_approx(view.reveal_time, GarageReveal.remap_time(3.5, false, true))
			and reveal.door_open == 1.0 and reveal.bars_sunk == 1.0
			and view.advance_reveal(0.0).is_empty(),
			title + ": Reduced motion mid-reveal must keep its place without replaying cues.")
		view.skip_reveal()
		_expect(view.reveal_complete() and view.advance_reveal(0.1).is_empty()
			and reveal.door_open == 1.0 and reveal.bars_sunk == 1.0 and reveal.eyes == 1.0,
			title + ": skipping must land on the final pose without replaying the horn.")
		view.finish_reveal()
		_expect(view.is_showing_reveal() and not view.is_revealing() and reveal.car.visible,
			title + ": the freed car must keep its final pose behind the results.")
		view.set_reduced_motion(false)
		view.configure(run)
		_expect(world.car.visible and outline.visible and not view.is_showing_reveal(),
			title + ": the next run must bring back the parked car and its outline.")
		view.start_reveal()
		var hop := GarageReveal.HOPS[0]
		view.advance_reveal(hop.x + hop.y * 0.5)
		for dimensions: Vector2 in [Vector2(1280, 620), Vector2(390, 700), Vector2(2560, 620)]:
			view.size = dimensions
			view.call("_resize_world")
			var shot := _shot(view, world.reveal_focus(), Transform3D.IDENTITY)
			_expect(Rect2(Vector2.ZERO, view.size).encloses(shot)
				and maxf(shot.size.x / view.size.x, shot.size.y / view.size.y) > 0.7
				and Rect2(Vector2.ZERO, view.size).encloses(
					_shot(view, reveal.car.local_bounds(), reveal.car.global_transform)),
				"%s: the reveal must fill a %s view with the bay, its sign and the hopping car."
				% [title, dimensions])
		view.size = Vector2(1280, 620)
		view.call("_resize_world")
	view.free()
	await process_frame


## Samples one timing: the door rises before the bars sink, and the car stays
## asleep until the horn, then hops (except in Reduced motion) under hearts.
func _test_reveal_timeline(reveal: GarageReveal, title: String) -> void:
	var shut := reveal.get_node("RollUpDoor/ClosedDoor") as Node3D
	var slats := reveal.get_node("RollUpDoor/DoorSlats") as Node3D
	for reduced: bool in [false, true]:
		for intense: bool in [true, false]:
			var horn := float(GarageReveal.cue_times(reduced)["horn"])
			var door := 0.0
			var bars := 0.0
			var hopped := false
			var hearts := 0
			for step in 149:
				var time := GarageReveal.duration(reduced) * step / 148.0
				reveal.pose(time, reduced, intense)
				_expect(reveal.door_open >= door and reveal.bars_sunk >= bars
					and (reveal.bars_sunk == 0.0 or reveal.door_open == 1.0)
					and reveal.car.visible == (reveal.door_open > 0.0)
					and (time >= horn or (reveal.eyes == 0.0 and reveal.hop_height == 0.0
						and reveal.hearts_shown == 0)),
					title + ": the door must rise first, then the bars, before the car wakes.")
				_expect(shut.is_visible_in_tree() == (reveal.door_open == 0.0)
					and not (shut.is_visible_in_tree() and slats.is_visible_in_tree()),
					title + ": the shut door must give way to its rolling slats, never draw both.")
				door = reveal.door_open
				bars = reveal.bars_sunk
				hopped = hopped or reveal.hop_height > 0.3
				hearts = maxi(hearts, reveal.hearts_shown)
			_expect(hopped == not reduced,
				title + " must hop for joy, except under Reduced motion.")
			var resting := GarageReveal.RESTING_HEARTS.size()
			_expect((hearts == resting) if reduced or not intense else (hearts > resting),
				title + ": hearts must float up, or rest still without motion or intense effects.")
			reveal.pose(GarageReveal.duration(reduced), reduced, intense)
			_expect(reveal.door_open == 1.0 and reveal.bars_sunk == 1.0 and reveal.eyes == 1.0
				and reveal.hop_height == 0.0 and reveal.car.visible,
				title + ": the reveal must end with the car awake and back on the floor.")


## The on-screen rectangle of a box, or an empty one if part of it is behind the camera.
func _shot(view: View, box: AABB, transform: Transform3D) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for index in 8:
		var point := transform * box.get_endpoint(index)
		if view.world_camera.is_position_behind(point):
			return Rect2(Vector2(-1, -1), Vector2.ZERO)
		minimum = minimum.min(view.project_point(point))
		maximum = maximum.max(view.project_point(point))
	return Rect2(minimum, maximum - minimum)


## Names of the geometry a node would actually submit for drawing.
func _drawn(root_node: Node) -> PackedStringArray:
	var names := PackedStringArray()
	for node in root_node.find_children("*", "GeometryInstance3D", true, false):
		if (node as GeometryInstance3D).is_visible_in_tree():
			names.append(node.name)
	return names


func _test_scenery(world: Landscape) -> void:
	var course := world.course
	var beach := course.scenery == Course.Scenery.BEACH
	var snow := course.scenery == Course.Scenery.SNOW
	var graphics := DisplayServer.get_name() != "headless"
	var road := world.get_node("ExactDrivingSurface") as MeshInstance3D
	var expected: Color = [
		Color("b5a27b"), Color("dfc58f"), Color("d2e0e9"),
	][course.number - 1]
	var colors: PackedColorArray = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var has_surface_color := false
	for color in colors:
		has_surface_color = has_surface_color or color.to_html(false) == expected.to_html(false)
	_expect(has_surface_color, course.title + ": the driving surface must use its biome's palette.")
	if beach or snow:
		var markers := world.get_node("JumpApproachMarkers") as MeshInstance3D
		var paint: PackedColorArray = markers.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var contrast := (expected.srgb_to_linear().get_luminance() + 0.05) \
			/ (paint[0].srgb_to_linear().get_luminance() + 0.05)
		_expect(contrast >= 2.4,
			course.title + ": takeoff markings must remain distinct against light sand and snow.")
	_expect(world.has_node("CoastalOcean") == beach and world.has_node("CoastalPalms") == beach
		and world.has_node("RoadsidePines") == not beach
		and world.has_node("RoadsideSnowbanks") == snow
		and world.has_node("OptionalSnowfall") == snow,
		course.title + ": the route must use biome-specific scenery, not only tinted mountains.")
	_expect(world.find_children("*", "CollisionObject3D", true, false).is_empty(),
		course.title + ": scenery must not introduce competing driving collisions.")
	if beach:
		_expect(world.pine_poses.is_empty(), "The beach must replace mountain pines with palms.")
		var ocean := world.get_node("CoastalOcean")
		var ocean_end := -INF
		for section: MeshInstance3D in ocean.get_children():
			var bounds := section.mesh.get_aabb()
			ocean_end = maxf(ocean_end, bounds.end.x)
			_expect(bounds.size.x <= 20.01 and is_equal_approx(bounds.position.y, Landscape.BEACH_SEA_Y)
				and bounds.end.z < -Landscape.ROAD_HALF_WIDTH,
				"Ocean chunks must remain locally culled, at sea level and behind the driving lane.")
		_expect(ocean_end > course.end_x * Art.WORLD_SCALE,
			"The coast must continue past the finish rather than stop after the first beach.")
		var palms := 0
		for batch in world.get_node("CoastalPalms").get_children():
			var stems := batch.get_node("Trunks") as MultiMeshInstance3D
			var fronds := batch.get_node("Fronds") as MultiMeshInstance3D
			_expect(stems.multimesh.instance_count == fronds.multimesh.instance_count
				and stems.multimesh.instance_count <= Landscape.PINE_BATCH_SIZE,
				"Palms must keep their trunks and fronds in matching small spatial batches.")
			for index in stems.multimesh.instance_count:
				var pose := world.palm_poses[palms]
				var planted: Vector3 = world.call("_terrain_point", pose.origin.x, pose.origin.z)
				_expect(pose.origin.is_equal_approx(planted)
					and pose.origin.y > Landscape.BEACH_SEA_Y,
					"Every palm must stand on the actual dunes, never float in the sea.")
				if graphics:
					_expect(pose.is_equal_approx(stems.multimesh.get_instance_transform(index))
						and pose.is_equal_approx(fronds.multimesh.get_instance_transform(index)),
						"Rendered palm trunks and fronds must match their authored placements.")
				palms += 1
			for mesh: Mesh in [stems.multimesh.mesh, fronds.multimesh.mesh]:
				var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
				for normal in normals:
					_expect(normal.is_finite() and absf(normal.length() - 1.0) < 0.001,
						"Original palm geometry must have finite unit normals.")
		_expect(palms > 20 and palms == world.palm_poses.size(),
			"Palms must dress the whole beach route.")
	else:
		for batch in world.get_node("RoadsidePines").get_children():
			var foliage := batch.get_node("Foliage") as MultiMeshInstance3D
			if snow:
				var finish := foliage.material_override as ShaderMaterial
				_expect(finish != null and finish.shader == Landscape.SNOW_FOLIAGE,
					"Alpine pines must show snow on their upward-facing branches.")
			else:
				_expect(foliage.material_override == null,
					"Copper Creek must retain its original imported green foliage.")
	if snow:
		_expect(world.get_node("QuietWaterRipples").get_child_count() == 0,
			"Frozen alpine pools must not keep liquid-water ripple animations.")
		for batch: MeshInstance3D in world.get_node("RoadsideSnowbanks").get_children():
			_expect(batch.mesh.get_aabb().size.x < 34.0,
				"Snowbanks and frosted stones must be locally culled, not drawn for the entire route.")
	var sky := world.daylight.sky_material.sky_top_color
	var studio := Node3D.new()
	var studio_lights := Art.light_stage(studio)
	world.daylight.set_elapsed((0.75 - Daylight.START_PHASE) * Daylight.CYCLE_SECONDS)
	_expect(is_equal_approx(world.daylight.night_amount, 1.0)
		and studio_lights.sky_material.sky_top_color.is_equal_approx(Daylight.DAY_TOP),
		course.title + ": themed lighting must preserve the cycle and never recolor the studios.")
	world.daylight.set_elapsed(0.0)
	_expect(world.daylight.sky_material.sky_top_color.is_equal_approx(sky)
		and sky.is_equal_approx(Daylight.DAY_TOP) == (course.number == 1),
		course.title + ": reset must restore this level's distinct daylight palette.")
	studio.free()
	var run := State.new(world.car.vehicle.id, course.id)
	run.advance(0.5, 0, 0, 0)
	run.velocity.x = 200.0
	world.present(run, 2.0, false, true, false, 1.0 / 60.0)
	var dust := world.get_node("OptionalTireDust") as MultiMeshInstance3D
	_expect(dust.multimesh.visible_instance_count > 0,
		course.title + ": normal driving must retain its optional tire particles.")
	if snow:
		var flakes := world.get_node("OptionalSnowfall") as MultiMeshInstance3D
		_expect(flakes.multimesh.visible_instance_count == Landscape.SNOWFLAKE_COUNT,
			"The snowy route must display its bounded optional snowfall.")
		# The headless dummy renderer does not retain uploaded instance transforms or colors.
		if graphics:
			var powder := dust.multimesh.get_instance_color(0)
			_expect(powder.b > powder.r and powder.r > 0.8,
				"Snowy tires must throw pale powder instead of brown quarry dust.")
			var before := flakes.multimesh.get_instance_transform(0)
			world.present(run, 3.0, false, true, false)
			var after := flakes.multimesh.get_instance_transform(0)
			world.present(run, 3.0, false, true, false)
			_expect(not before.is_equal_approx(after)
				and after.is_equal_approx(flakes.multimesh.get_instance_transform(0)),
				"Snowfall must animate only from the presentation clock, so pause freezes it.")
			for index in flakes.multimesh.instance_count:
				var at := flakes.multimesh.get_instance_transform(index).origin
				_expect(at.is_finite() and (at.z < -Landscape.ROAD_HALF_WIDTH
					or at.x >= Art.world_point(run.position).x + 4.49),
					"Snowflakes must stay in the backdrop or safely ahead of the car, never inside the cockpit.")
	for reduced in [true, false]:
		world.present(run, 4.0, reduced, reduced, false)
		_expect(dust.multimesh.visible_instance_count == 0,
			course.title + ": either accessibility preference must suppress tire particles.")
		if snow:
			var flakes := world.get_node("OptionalSnowfall") as MultiMeshInstance3D
			_expect(flakes.multimesh.visible_instance_count == 0,
				"Reduced motion or disabled intense effects must remove existing snowflakes immediately.")
	if snow:
		run.finished = true
		world.present(run, 5.0, false, true, false)
		_expect((world.get_node("OptionalSnowfall") as MultiMeshInstance3D)
			.multimesh.visible_instance_count == 0, "Results must not retain moving snowfall.")


func _test_progression() -> void:
	_session.call("configure_single_player")
	_expect(not _achievements.call("is_unlocked", Course.COPPER_COMPLETE),
		"This suite requires a fresh profile to verify first-time unlocks.")
	await _check_setup(0)
	_session.call("set_level", Course.ALPINE)
	_session.call("set_character_for_player", 0, Profiles.CRV)
	_expect((_session.call("selected_level") as Dictionary)["id"] == Course.COPPER
		and (_session.call("character_for_player", 0) as Dictionary)["id"] == Profiles.CUBE,
		"Programmatic selection must not bypass either gate.")
	var abandoned := _new_game(Course.COPPER, Profiles.CUBE)
	var waiting := (abandoned.get("_view") as View).world
	_expect(waiting.has_captive() and waiting.reveal.vehicle_id == Profiles.SONATA,
		"Until Level 1 is complete, its garage must hold the locked Sonata.")
	abandoned.get("_state").collected.fill(true)
	abandoned.free()
	_expect(not _achievements.call("is_unlocked", Course.COPPER_COMPLETE),
		"Collecting cargo and exiting without a delivery must not unlock anything.")
	var failed := _new_game(Course.COPPER, Profiles.CUBE)
	failed.get("_state").failed = true
	failed.get("_state").lives_left = 0
	failed.call("_update_round", 0.0, 0.0)
	_expect(not _achievements.call("is_unlocked", Course.COPPER_COMPLETE),
		"Running out of lives must not open Level 2.")
	_expect(not failed.call("is_revealing") and (failed.get_node("%RoundOver") as Control).visible,
		"A failed run must go straight to the results, leaving the Sonata locked away.")
	failed.free()
	await process_frame

	var first := _new_game(Course.COPPER, Profiles.CUBE)
	_drive_turn(first)
	_expect((first.get("_state") as State).finished
		and _achievements.call("is_unlocked", Course.COPPER_COMPLETE),
		"The first unlock must come from a genuine parked delivery through GameShell.")
	_expect(first.call("is_revealing") and not (first.get_node("%RoundOver") as Control).visible,
		"The first delivery must free the Sonata on screen before the results.")
	first.call("skip_reveal")
	_expect(not first.call("is_revealing") and (first.get_node("%RoundOver") as Control).visible,
		"Skipping the garage reveal must land on the shared results.")
	_expect(str(first.get("_round_progression_notes")).contains("Hyundai Sonata"),
		"Results must announce the level and vehicle reward.")
	var payload: Dictionary = first.call("_share_payload")
	_expect(payload["level_id"] == Course.COPPER and payload["level_number"] == 1,
		"Share data must identify the route actually driven.")
	first.call("_on_play_again_pressed")
	_expect(first.get("_state").course.id == Course.COPPER
		and first.get("_state").vehicle.id == Profiles.CUBE and not first.get("_state").started,
		"Replay must keep the selected level and car, not silently advance the campaign.")
	_expect(not (first.get("_view") as View).world.has_captive(),
		"Once freed, the Sonata must leave Level 1's garage open on replay.")
	first.free()
	await _check_setup(1)
	_check_persistence(1)

	var early_exit := _new_game(Course.SUNSET, Profiles.SONATA, 2)
	var first_turn: State = early_exit.get("_state")
	first_turn.collected.fill(true)
	first_turn.finished = true
	early_exit.call("_update_round", 0.0, 0.0)
	_expect(not _achievements.call("is_unlocked", Course.SUNSET_COMPLETE),
		"Hot-seat progression must wait for the full roster, just like results and payouts.")
	early_exit.free()
	await process_frame
	_expect(not _achievements.call("is_unlocked", Course.SUNSET_COMPLETE),
		"Exiting during a hot-seat handoff must not complete the match.")

	var second := _new_game(Course.SUNSET, Profiles.SONATA, 3)
	_drive_turn(second)
	var world_id: int = second.get("_view").world.get_instance_id()
	_expect(second.get("_handoff").visible and not _achievements.call("is_unlocked", Course.SUNSET_COMPLETE),
		"A real Level 2 delivery must hand off without granting premature rewards.")
	for player in [1, 2]:
		second.call("_process", 0.0)
		(second.get("_handoff_button") as Button).pressed.emit()
		second.call("_update_round", 0.0, 0.0)
		var run: State = second.get("_state")
		_expect(run.course.id == Course.SUNSET and run.checkpoint == 0 and run.plug_count() == 0
			and second.get("_view").world.get_instance_id() == world_id,
			"Every hot-seat driver must start the same selected level with independent progress.")
		run.failed = true
		run.lives_left = 0
		second.call("_update_round", 0.0, 0.0)
	_expect(_achievements.call("is_unlocked", Course.SUNSET_COMPLETE)
		and not _achievements.call("is_unlocked", Course.ALPINE_COMPLETE),
		"One finisher must unlock Level 3 and the CR-V after the last turn, not complete Level 3.")
	var garage := (second.get("_view") as View).world
	_expect(second.call("is_revealing") and garage.reveal.vehicle_id == Profiles.CRV
		and not (second.get_node("%RoundOver") as Control).visible,
		"A hot-seat match must free the CR-V after the final turn, before the results.")
	var notes: PackedStringArray = second.get("_round_progression_notes")
	second.call("_award_round_achievements", 0, 0)
	_expect((second.get("_round_progression_notes") as PackedStringArray) == notes,
		"Repeated result handling must not announce or grant the same unlock twice.")
	# Leaving mid-reveal keeps the unlock that was already saved.
	second.free()
	await _check_setup(2)
	_check_persistence(2)

	var third := _new_game(Course.ALPINE, Profiles.CRV)
	_drive_turn(third)
	_expect(third.get("_state").finished
		and _achievements.call("is_unlocked", Course.ALPINE_COMPLETE),
		"The unlocked CR-V must complete the third level through real gameplay.")
	_expect(not (third.get("_view") as View).world.has_captive() and not third.call("is_revealing")
		and (third.get_node("%RoundOver") as Control).visible,
		"Level 3 frees no car, so its delivery must go straight to the results.")
	payload = third.call("_share_payload")
	_expect(payload["level_title"] == "Alpine Pass" and payload["vehicle_id"] == Profiles.CRV
		and str(payload["mode"]).contains("Level 3"),
		"Results and sharing must not label new routes as Copper Creek.")
	third.free()
	for level in Course.LEVELS:
		_session.call("set_level", level["id"])
		for character in Profiles.CHARACTERS:
			_session.call("set_character_for_player", 0, character["id"])
			_expect((_session.call("selected_level") as Dictionary)["id"] == level["id"]
				and (_session.call("character_for_player", 0) as Dictionary)["id"] == character["id"],
				"Unlocked cars must remain available when replaying earlier levels.")
	_check_persistence(3)


func _new_game(level_id: String, vehicle_id: String, players := 1) -> Node:
	_session.call("set_level", level_id)
	_session.call("set_character_for_player", 0, vehicle_id)
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
	for frame in 30 * 110:
		Driver.hold_controls(run)
		game.call("_update_round", 1.0 / 30.0, 0.0)
		if run.is_over():
			break
	Driver.release_controls()
	_expect(run.finished, "%s / %s must finish through gameplay (x=%.1f, plugs=%d)." % [
		run.course.title, run.vehicle.title, run.position.x, run.plug_count(),
	])


func _check_setup(completed: int) -> void:
	var menu := (load("res://scenes/menus/mode_select.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	menu.call("_on_single_player_pressed")
	var picker := menu.get("_level_choice") as OptionButton
	var cards: Array = menu.get("_player_setup_cards")
	_expect(picker != null and picker.item_count == Course.setup_levels().size()
		and picker.item_count == Course.LEVELS.size() + 1,
		"Setup must list all three levels and the Trail Builder, including their locked entries.")
	for index in 3:
		var locked := index > completed
		_expect(picker.is_item_disabled(index) == locked,
			"Level %d must follow sequential completion gates." % (index + 1))
		var car_picker := cards[0]["picker"] as OptionButton
		_expect(car_picker.is_item_disabled(index) == locked,
			"Each car must share its corresponding level's unlock milestone.")
		if locked:
			_expect(not picker.get_popup().get_item_tooltip(index).is_empty()
				and not car_picker.get_popup().get_item_tooltip(index).is_empty(),
				"Locked choices must explain their requirements.")
	# The Trail Builder opens once every car is free, after Level 2.
	var builder := Course.LEVELS.size()
	var builder_locked := completed < 2
	_expect(picker.is_item_disabled(builder) == builder_locked,
		"The Trail Builder must unlock with the last car, after Level 2.")
	if builder_locked:
		_expect(not picker.get_popup().get_item_tooltip(builder).is_empty(),
			"A locked Trail Builder must explain its requirement.")
	menu.call("_on_multiplayer_pressed")
	for card: Dictionary in cards:
		var car_picker := card["picker"] as OptionButton
		for index in 3:
			if (card["panel"] as Control).visible:
				_expect(car_picker.is_item_disabled(index) == (index > completed),
					"Local multiplayer must enforce the same vehicle gates as solo.")
	menu.free()
	await process_frame


func _check_persistence(completed: int) -> void:
	var config := ConfigFile.new()
	_expect(config.load("user://achievements.cfg") == OK,
		"Level completion must be saved by the existing achievement manager.")
	_achievements.set("_unlocked", {})
	_achievements.call("_load_state")
	for index in Course.LEVELS.size():
		var achievement: String = Course.LEVELS[index]["completion_achievement"]
		_expect(bool(_achievements.call("is_unlocked", achievement)) == (index < completed),
			"Reloading a saved profile must preserve exactly the completed levels.")
		for character in Profiles.CHARACTERS:
			var required := str(character.get("requires_achievement", ""))
			if required == achievement:
				_expect(bool(_session.call("setup_option_is_unlocked", character)) == (index < completed),
					"Vehicle unlocks must survive the same save reload.")


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
