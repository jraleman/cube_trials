extends Node3D

## Shared trail scenery extrudes the active route without entering the driving plane.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const TireParticles = preload("res://games/cube_trials/world/tire_particles.gd")
const GarageReveal = preload("res://games/cube_trials/world/garage_reveal.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const PINE_MODEL = preload("res://games/cube_trials/assets/models/pine_tree.glb")
const PLUG_MODEL = preload("res://games/cube_trials/assets/models/spark_plug.glb")
const CHECKPOINT_MODEL = preload("res://games/cube_trials/assets/models/checkpoint_flag.glb")
const GARAGE_MODEL = preload("res://games/cube_trials/assets/models/car_body_shop.glb")
const PARKING_SHADER = preload("res://games/cube_trials/assets/shaders/parking_outline.gdshader")
const SNOW_FOLIAGE = preload("res://games/cube_trials/assets/shaders/snow_foliage.gdshader")
const PARKING_WAIT := Color("ffd17b")
const PARKING_READY := Color("67f0c2")
const PARKING_DEPTH := 4.2
const ROAD_HALF_WIDTH := 3.2
const CLIFF_DEPTH := 42.0
const TIRE_CLEARANCE := State.WHEEL_RADIUS * Art.WORLD_SCALE - 0.15
const HILL_X_ORIGIN := -30.0
const HILL_STEP := 5.0
const HILL_ROWS: Array[float] = [-3.3, -8.0, -16.0, -25.0, -34.0, -44.0]
const BEACH_SEA_Y := -2.5
const SNOWFLAKE_COUNT := 288
## Keep the forest's existing height and center pickups on their collision anchors.
const PINE_SCALE := 4.19 / 6.03
const PINE_BATCH_SIZE := 4
const PLUG_HEIGHT := 1.0
const PLUG_SCALE := PLUG_HEIGHT / 0.0955
const CHECKPOINT_FIELD_MATERIAL := "Cube Flag field"
const CHECKPOINT_LABEL_OFFSET := Vector3(0.5, 4.08, 0)
const GARAGE_SCALE := 0.9
const GARAGE_COURSE_OFFSET := 100.0
## The furnished yard stays behind the car; its apron just clears the road.
const GARAGE_MODEL_OFFSET := Vector3(
	0.7 + 1.525 * GARAGE_SCALE, 0.012 - 0.16 * GARAGE_SCALE, -3.0
)
const GARAGE_FEEDBACK_Z := 4.5 * GARAGE_SCALE + GARAGE_MODEL_OFFSET.z

var car: Cube
var course: Course
var daylight: Daylight
var pine_poses: Array[Transform3D] = []
var palm_poses: Array[Transform3D] = []
var plugs: Array[Node3D] = []
var checkpoint_flags: Array[MeshInstance3D] = []
var checkpoint_labels: Array[Label3D] = []
var garage_label: Label3D
var parking_label: Label3D
## The locked car waiting in this garage, built only once a level has one.
var reveal: GarageReveal
var _garage_root: Node3D
var _flag_materials: Array[StandardMaterial3D] = []
var _flag_rest_colors: Array[Color] = []
var _garage_lamps: Array[MeshInstance3D] = []
var _parking_outline: MeshInstance3D
var _parking_material: ShaderMaterial
var _workshop_light: OmniLight3D
var _garage_site := Rect2()
var _garage_pad := Rect2()
var _garage_floor_y := 0.0
var _clouds: Node3D
var _ripples: Node3D
var _dust: TireParticles
var _snowfall: MultiMeshInstance3D
var _last_plugs := -1
var _last_checkpoint := -1
var _last_finished := false
var _reveal_staged := false


func _init(route: Course = null) -> void:
	course = route if route != null else Course.new()


func _ready() -> void:
	daylight = Art.light_stage(self, course.scenery)
	_build_garage()
	_build_terrain()
	_build_hills()
	_build_scenery()
	_build_water_and_clouds()
	_build_pickups()
	_build_checkpoints()
	_build_dust()
	if course.scenery == Course.Scenery.SNOW:
		_build_snowfall()
	car = Cube.new()
	add_child(car)


## A turn changes the vehicle, not the resident trail or its lighting.
func set_vehicle(vehicle_id: String) -> void:
	if car.vehicle.id != vehicle_id:
		remove_child(car)
		car.queue_free()
		car = Cube.new(vehicle_id)
		car.visible = not _reveal_staged
		add_child(car)
	_last_plugs = -1
	_last_checkpoint = -1
	_last_finished = false


## Rendering reads the model; it never steps physics or changes checkpoint ownership.
func present(
	state: State, time: float, reduced: bool, intense: bool, braking: bool,
	delta := 0.0, daylight_time := 0.0
) -> void:
	daylight.set_elapsed(daylight_time)
	car.apply_state(state, braking, delta, reduced, intense, daylight.night_amount)
	for index in plugs.size():
		plugs[index].visible = not state.collected[index]
		plugs[index].rotation.y = 0.0 if reduced else time * 0.75 + index * 0.35
		plugs[index].position = Art.world_point(course.plug_position(index))
		if not reduced:
			plugs[index].position.y += sin(time * 2.0 + index) * 0.075
	for index in checkpoint_flags.size():
		checkpoint_flags[index].rotation.y = 0.0 if reduced else sin(time * 1.3) * 0.08
	if _last_checkpoint != state.checkpoint:
		_last_checkpoint = state.checkpoint
		for index in checkpoint_flags.size():
			var saved := state.checkpoint >= index + 1
			_flag_materials[index].albedo_color = Art.TEAL if saved else _flag_rest_colors[index]
			checkpoint_labels[index].text = "CHECKPOINT %d%s" % [
				index + 1, " / SAVED" if saved else "",
			]
	_update_garage(state, time, reduced, intense)
	_clouds.position.x = 0.0 if reduced else sin(time * 0.07) * 1.5
	_ripples.position.y = 0.0 if reduced or course.scenery == Course.Scenery.SNOW \
		else sin(time * 1.5) * 0.02
	_dust.present(state, delta, not reduced and intense)
	_update_snowfall(state, time, not reduced and intense)


## The screen-space hint points at the near edge of the actual stopping zone.
func parking_target() -> Vector3:
	return _parking_outline.to_global(Vector3(0, 0, PARKING_DEPTH * 0.5))


## Shuts [param vehicle_id] in behind the door and bars; "" leaves the bay open.
func set_captive(vehicle_id: String, paint := "", rim := "") -> void:
	if reveal == null:
		if vehicle_id.is_empty():
			return
		reveal = GarageReveal.new()
		_garage_root.add_child(reveal)
	reveal.set_captive(vehicle_id, paint, rim)
	_update_workshop_light()


func has_captive() -> bool:
	return reveal != null and not reveal.vehicle_id.is_empty()


func pose_reveal(time: float, reduced: bool, intense: bool) -> void:
	if reveal != null:
		reveal.pose(time, reduced, intense)
	_update_workshop_light()


## The parked car and its outline leave the reveal's shot: nothing blocks the
## bay, and the scene stays within the draw budget with two detailed cars.
func stage_reveal(shown: bool) -> void:
	if shown == _reveal_staged:
		return
	_reveal_staged = shown
	car.visible = not shown
	_parking_outline.visible = not shown


## World-space box the reveal camera keeps in frame.
func reveal_focus() -> AABB:
	return _garage_root.transform * GarageReveal.FOCUS


func _update_workshop_light() -> void:
	var energy := daylight.night_amount * 1.6
	if has_captive():
		energy = maxf(energy, reveal.bay_light)
	_workshop_light.visible = energy > 0.01
	_workshop_light.light_energy = energy


func _update_garage(state: State, time: float, reduced: bool, intense: bool) -> void:
	if _last_plugs != state.plug_count() or _last_finished != state.finished:
		_last_plugs = state.plug_count()
		_last_finished = state.finished
		garage_label.text = "BRAKE TO PARK" if _last_plugs == 5 else "BRING ALL FIVE PLUGS"
		if state.finished:
			garage_label.text = "DELIVERY COMPLETE"
		for index in 5:
			var material := _garage_lamps[index].material_override as StandardMaterial3D
			material.albedo_color = Art.CREAM if state.collected[index] else Color("3f5a50")
			material.emission_energy_multiplier = 1.1 if state.collected[index] else 0.0
	var ready := _last_plugs == state.collected.size()
	var color := PARKING_READY if ready else PARKING_WAIT
	parking_label.text = "PARK HERE"
	if state.finished:
		color = Art.CREAM
		parking_label.text = "DELIVERED!"
	elif not ready:
		var missing := state.collected.size() - _last_plugs
		parking_label.text = "NEED %d PLUG%s" % [missing, "" if missing == 1 else "S"]
	elif state.position.x >= course.finish_x \
		and state.position.x <= course.finish_x + course.finish_width \
		and absf(state.velocity.x) >= State.PARK_SPEED:
		parking_label.text = "SLOW DOWN"
	parking_label.modulate = color
	_parking_material.set_shader_parameter("tint", color)
	var animate := not reduced and intense and not state.is_over()
	_parking_material.set_shader_parameter("pulse",
		0.9 + sin(time * 1.8) * 0.1 if animate else 1.0)
	_parking_material.set_shader_parameter("halo_strength", 1.0 if intense else 0.0)
	_update_workshop_light()


func _build_terrain() -> void:
	var road := Builder.new()
	var earth := Builder.new()
	var depths: Array[float] = [-3.2, -2.55, -2.2, 2.2, 2.55, 3.2]
	var colors: Array[Color] = [
		Color("70805b"), Color("d8c496"), Color("b5a27b"),
		Color("d8c496"), Color("70805b"),
	]
	var layers: Array[float] = [0.0, 0.40, 1.10, 2.7, 4.0, 6.5, CLIFF_DEPTH]
	var rock: Array[Color] = [
		Color("99815a"), Color("bd9769"), Color("9c7654"),
		Color("c29e70"), Color("a58460"), Color("806f55"),
	]
	var tire_color := Color("978866")
	var cap_color := Color("aa835e")
	match course.scenery:
		Course.Scenery.BEACH:
			colors = [
				Color("eedbad"), Color("f4e1b5"), Color("dfc58f"),
				Color("f4e1b5"), Color("eedbad"),
			]
			rock = [
				Color("eedbad"), Color("dfc18d"), Color("d2b079"),
				Color("c4a372"), Color("b69468"), Color("9c8563"),
			]
			tire_color = Color("c4a773")
			cap_color = Color("d2b079")
		Course.Scenery.SNOW:
			colors = [
				Color("f3f8fc"), Color("e4eff5"), Color("d2e0e9"),
				Color("e4eff5"), Color("f3f8fc"),
			]
			rock = [
				Color("f3f8fc"), Color("dce9ef"), Color("a5b9c6"),
				Color("8198a8"), Color("6c8293"), Color("536c7c"),
			]
			tire_color = Color("a8bdcc")
	for section: Array in course.roads:
		for index in range(section.size() - 1):
			var a := Art.world_point(section[index])
			var b := Art.world_point(section[index + 1])
			for strip in range(depths.size() - 1):
				var near_z := depths[strip + 1]
				var far_z := depths[strip]
				road.quad(a + Vector3(0, 0, near_z), b + Vector3(0, 0, near_z),
					b + Vector3(0, 0, far_z), a + Vector3(0, 0, far_z), colors[strip])
			for z: float in [-Cube.WHEEL_Z, Cube.WHEEL_Z]:
				road.quad(a + Vector3(0, 0.018, z + 0.18),
					b + Vector3(0, 0.018, z + 0.18),
					b + Vector3(0, 0.018, z - 0.18),
					a + Vector3(0, 0.018, z - 0.18), tire_color)
			for layer in range(layers.size() - 1):
				var top_a := a - Vector3.UP * layers[layer]
				var top_b := b - Vector3.UP * layers[layer]
				var bottom_a := a - Vector3.UP * layers[layer + 1]
				var bottom_b := b - Vector3.UP * layers[layer + 1]
				var shade := rock[layer].lightened((index % 3) * 0.018)
				earth.quad(top_a + Vector3(0, 0, ROAD_HALF_WIDTH),
					bottom_a + Vector3(0, 0, ROAD_HALF_WIDTH),
					bottom_b + Vector3(0, 0, ROAD_HALF_WIDTH),
					top_b + Vector3(0, 0, ROAD_HALF_WIDTH), shade)
				earth.quad(top_b - Vector3(0, 0, ROAD_HALF_WIDTH),
					bottom_b - Vector3(0, 0, ROAD_HALF_WIDTH),
					bottom_a - Vector3(0, 0, ROAD_HALF_WIDTH),
					top_a - Vector3(0, 0, ROAD_HALF_WIDTH), shade.darkened(0.12))
		for endpoint in [0, section.size() - 1]:
			var p := Art.world_point(section[endpoint])
			for layer in range(layers.size() - 1):
				var near_top := p + Vector3(0, -layers[layer], ROAD_HALF_WIDTH)
				var far_top := p + Vector3(0, -layers[layer], -ROAD_HALF_WIDTH)
				var depth := Vector3.UP * (layers[layer + 1] - layers[layer])
				var shade := rock[layer] if course.scenery == Course.Scenery.SNOW else cap_color
				if endpoint == 0:
					earth.quad(near_top, far_top, far_top - depth, near_top - depth, shade)
				else:
					earth.quad(far_top, near_top, near_top - depth, far_top - depth, shade)
	_mesh("ExactDrivingSurface", road, Art.material(0.98))
	_mesh("LayeredQuarryRock", earth, Art.material(0.98))
	var gaps := course.gap_intervals()
	var markers := Builder.new()
	var marker_color := Color("e6c77d") if course.scenery == Course.Scenery.MOUNTAIN \
		else Color("a86c2d")
	for gap in gaps:
		for offset: float in [130.0, 90.0, 50.0]:
			var x := gap.x - offset
			var a := Art.world_point(Vector2(x, course.ground_height(x))) + Vector3.UP * 0.025
			var b := Art.world_point(Vector2(x + 7.0, course.ground_height(x + 7.0))) \
				+ Vector3.UP * 0.025
			markers.quad(a + Vector3(0, 0, 2.5), b + Vector3(0, 0, 2.5),
				b - Vector3(0, 0, 2.5), a - Vector3(0, 0, 2.5), marker_color)
	# A trail built in the Trail Builder may have no jumps to mark.
	if not gaps.is_empty():
		_mesh("JumpApproachMarkers", markers, signage_material())


func _build_hills() -> void:
	var hills := Builder.new()
	var rows := HILL_ROWS
	var distant_color := Color("a6b6b2")
	if course.scenery == Course.Scenery.BEACH:
		distant_color = Color("c8bb90")
	elif course.scenery == Course.Scenery.SNOW:
		distant_color = Color("bbd2e2")
	var columns := ceili((course.end_x * Art.WORLD_SCALE + 30.0 - HILL_X_ORIGIN) / HILL_STEP)
	for row in range(rows.size() - 1):
		for column in columns:
			var x := HILL_X_ORIGIN + column * HILL_STEP
			var a := _hill_point(x, rows[row])
			var b := _hill_point(x + HILL_STEP, rows[row])
			var c := _hill_point(x + HILL_STEP, rows[row + 1])
			var d := _hill_point(x, rows[row + 1])
			var color := course.hill_color.lerp(
				distant_color, float(row) / (rows.size() - 2)
			)
			color = color.lightened(float((column + row) % 3) * 0.025)
			hills.triangle(a, b, c, color)
			hills.triangle(a, c, d, color.darkened(0.025))
	_mesh("DistantThreeDimensionalRidges", hills, Art.material(1.0))


func _hill_point(x: float, z: float) -> Vector3:
	var floor_y := course.ground_height(x / Art.WORLD_SCALE)
	var base := (Art.HEIGHT_ORIGIN - floor_y) * Art.WORLD_SCALE if is_finite(floor_y) else 0.0
	var distance := absf(z) - 3.3
	var ridge := sin(x * 0.13 + z * 0.037) * 0.48 \
		+ cos(x * 0.065 - z * 0.10) * 0.38 + sin(x * 0.28 + z * 0.12) * 0.14
	var height := base + (0.7 + ridge) * minf(distance * 0.16, 7.0)
	if course.scenery == Course.Scenery.BEACH:
		height = lerpf(base + (0.4 + ridge) * minf(distance * 0.12, 1.7),
			BEACH_SEA_Y - 0.5, smoothstep(5.0, 28.0, distance))
	for gap in course.gap_intervals():
		var center := (gap.x + gap.y) * 0.5 * Art.WORLD_SCALE
		var width := maxf(9.0, (gap.y - gap.x) * 0.5 * Art.WORLD_SCALE + 3.5)
		var ravine := exp(-pow((x - center) / width, 4)) * maxf(0, 1.0 - distance / 28.0)
		height -= ravine * 14.0
	if _garage_pad.has_area():
		var pad_distance := maxf(
			maxf(_garage_pad.position.x - x, x - _garage_pad.end.x),
			maxf(_garage_pad.position.y - z, z - _garage_pad.end.y)
		)
		height = lerpf(height, _garage_floor_y - 0.025,
			1.0 - smoothstep(0.0, HILL_STEP, pad_distance))
	return Vector3(x, height, z)


func _terrain_point(x: float, z: float) -> Vector3:
	var left := floorf((x - HILL_X_ORIGIN) / HILL_STEP) * HILL_STEP + HILL_X_ORIGIN
	for row in range(HILL_ROWS.size() - 1):
		if z > HILL_ROWS[row] or z < HILL_ROWS[row + 1]:
			continue
		var a := _hill_point(left, HILL_ROWS[row])
		var b := _hill_point(left + HILL_STEP, HILL_ROWS[row])
		var c := _hill_point(left + HILL_STEP, HILL_ROWS[row + 1])
		var d := _hill_point(left, HILL_ROWS[row + 1])
		var u := (x - left) / HILL_STEP
		var v := (z - HILL_ROWS[row]) / (HILL_ROWS[row + 1] - HILL_ROWS[row])
		var height := a.y + (b.y - a.y) * u + (c.y - b.y) * v if u >= v \
			else a.y + (c.y - d.y) * u + (d.y - a.y) * v
		return Vector3(x, height, z)
	push_error("Copper Creek scenery must be placed inside its authored terrain.")
	return Vector3.INF


func _build_scenery() -> void:
	var wood := Builder.new()
	var foliage := Builder.new()
	var stones := Builder.new()
	var details := Builder.new()
	var beach := course.scenery == Course.Scenery.BEACH
	var snow := course.scenery == Course.Scenery.SNOW
	var snowbanks: Node3D
	var snow_finish: StandardMaterial3D
	var has_snow_parts := false
	if snow:
		snowbanks = Node3D.new()
		snowbanks.name = "RoadsideSnowbanks"
		add_child(snowbanks)
		snow_finish = foliage_material()
		stones = foliage
	var count := ceili((course.end_x * Art.WORLD_SCALE + 16.0) / 2.05)
	for index in count:
		if snow and index > 0 and index % 16 == 0:
			if has_snow_parts:
				_mesh("SnowbankBatch%d" % (index / 16 - 1), foliage, snow_finish, snowbanks)
			foliage = Builder.new()
			stones = foliage
			has_snow_parts = false
		var x := -8.0 + index * 2.05
		var floor_y := course.ground_height(x / Art.WORLD_SCALE)
		if not is_finite(floor_y):
			continue
		var ground := Art.world_point(Vector2(x / Art.WORLD_SCALE, floor_y))
		for side: float in [-1.0, 1.0]:
			var z := side * (2.75 + float(index % 3) * 0.09)
			var position := ground + Vector3(0, 0, z)
			if _garage_site.grow(0.55 if snow else 0.35).has_point(Vector2(position.x, position.z)):
				continue
			stones.ellipsoid(position + Vector3(0, 0.07, 0),
				Vector3(0.18 + index % 3 * 0.05, 0.13, 0.16),
				Color("f4e5cc") if beach else (Color("8c9ca9") if snow else Color("94876c")), 8)
			if snow:
				foliage.ellipsoid(position + Vector3(0, 0.10, 0),
					Vector3(0.9, 0.28, 0.42), Color("f3f8fc"), 8)
				has_snow_parts = true
			else:
				for blade in 3:
					var offset := Vector3(blade * 0.055, 0, 0)
					var color := Color("b3ae72") if beach else \
						(Color("8b985b") if index % 2 == 0 else Color("667b4b"))
					foliage.triangle(position + offset, position + offset + Vector3(0.08, 0, 0),
						position + offset + Vector3(0.04, 0.23 + blade * 0.06, -0.04), color)
		if not beach and index % 3 == 0 \
			and not _garage_site.grow(0.8).has_point(Vector2(x, -2.92)):
			fence_parts(wood, ground + Vector3(0, 0, -2.92))
			if snow:
				foliage.box(ground + Vector3(0, 0.91, -2.92),
					Vector3(1.55, 0.08, 0.15), Color("f3f8fc"))
				has_snow_parts = true
		if index % 4 == 0:
			var tree_z := -7.5 - index % 3 * 3.0
			var clearance := 4.8 if beach else 1.5
			if _garage_site.grow(clearance).has_point(Vector2(x + 1.0, tree_z)):
				tree_z = _garage_site.position.y - clearance
			var tree_at := _terrain_point(x + 1.0, tree_z)
			if beach:
				if tree_at.y > BEACH_SEA_Y + 0.3:
					var scale_factor := 0.82 + float(index % 5) * 0.09
					palm_poses.append(Transform3D(
						Basis(Vector3.UP, index * 1.73).scaled(Vector3.ONE * scale_factor), tree_at))
			else:
				var tree_scale := PINE_SCALE * (0.8 + float(index % 5) * 0.13)
				pine_poses.append(Transform3D(Basis.from_scale(Vector3.ONE * tree_scale), tree_at))
		if index % 7 == 0 and not _garage_site.grow(1.0).has_point(Vector2(x - 0.3, -4.0)):
			var rock_at := _terrain_point(x - 0.3, -4.0)
			stones.ellipsoid(rock_at + Vector3(0, 0.35, 0),
				Vector3(1.0, 0.7, 0.85),
				Color("cbb88c") if beach else (Color("8c9ca9") if snow else Color("9e9279")), 8)
			if snow:
				foliage.ellipsoid(rock_at + Vector3(0, 0.65, 0),
					Vector3(0.9, 0.20, 0.75), Color("f3f8fc"), 8)
				has_snow_parts = true
	for sign: Dictionary in course.signs:
		var x: float = sign["x"]
		var base := Art.world_point(Vector2(x, course.ground_height(x)), -3.0)
		sign_parts(wood, details, base)
		for label in sign_labels(sign["title"], sign["detail"], base):
			add_child(label)
	_mesh("RoadsideTimber", wood, timber_material())
	if snow:
		if has_snow_parts:
			_mesh("SnowbankBatch%d" % ((count - 1) / 16), foliage, snow_finish, snowbanks)
	else:
		_mesh("ShoulderGrass", foliage, foliage_material())
		_mesh("ScatteredQuarryStones", stones, Art.material(1.0))
	_mesh("TrailSignBoards", details, signage_material())
	if beach:
		_build_palms(palm_poses)
	else:
		_build_pines()


## Small spatial batches share the exported meshes without drawing the whole forest at once.
func _build_pines() -> void:
	var forest := Node3D.new()
	forest.name = "RoadsidePines"
	add_child(forest)
	var source := PINE_MODEL.instantiate() as Node3D
	var assembly := source.get_node("PineTree") as Node3D
	var snow_finish := ShaderMaterial.new()
	snow_finish.shader = SNOW_FOLIAGE
	for start in range(0, pine_poses.size(), PINE_BATCH_SIZE):
		var batch := Node3D.new()
		batch.name = "PineBatch%d" % start
		forest.add_child(batch)
		for part: MeshInstance3D in assembly.get_children():
			var instance := _tree_batch(part.name, part.mesh, pine_poses, start,
				assembly.transform * part.transform)
			if course.scenery == Course.Scenery.SNOW and part.name == "Foliage":
				instance.material_override = snow_finish
			batch.add_child(instance)
	source.free()


func _build_palms(poses: Array[Transform3D]) -> void:
	var grove := Node3D.new()
	grove.name = "CoastalPalms"
	add_child(grove)
	var trunk := Builder.new()
	var leaves := Builder.new()
	for segment in 8:
		var a := Vector3(0.013 * segment * segment, segment * 0.6, -0.03 * segment)
		var next := segment + 1
		var b := Vector3(0.013 * next * next, next * 0.6, -0.03 * next)
		var rotation := Basis(Quaternion(Vector3.UP, (b - a).normalized())).get_euler()
		var radius := 0.19 - segment * 0.009
		trunk.cylinder((a + b) * 0.5, radius, a.distance_to(b) + 0.02,
			Color("aa855a"), rotation, 8, 0.94)
		trunk.cylinder(a, radius + 0.012, 0.045, Color("826344"), rotation, 8)
	var crown := Vector3(0.832, 4.8, -0.24)
	for leaf in 9:
		var angle := leaf * TAU / 9.0
		var direction := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(-direction.z, 0, direction.x)
		var length := 2.6 + (leaf % 3) * 0.3
		for step in 6:
			var a := float(step) / 6.0
			var b := float(step + 1) / 6.0
			var start := crown + direction * a * length \
				+ Vector3.UP * (sin(a * PI) * 0.65 - a * a * 1.1)
			var end := crown + direction * b * length \
				+ Vector3.UP * (sin(b * PI) * 0.65 - b * b * 1.1)
			var width_a := sin(a * PI) * 0.36
			var width_b := sin(b * PI) * 0.36
			var ridge_a := start + Vector3.UP * width_a * 0.3
			var ridge_b := end + Vector3.UP * width_b * 0.3
			if step == 0:
				leaves.triangle(start, ridge_b, end + across * width_b, Color("639c57"))
				leaves.triangle(start, end - across * width_b, ridge_b, Color("397c50"))
			elif step == 5:
				leaves.triangle(ridge_a, end, start + across * width_a, Color("639c57"))
				leaves.triangle(start - across * width_a, end, ridge_a, Color("397c50"))
			else:
				leaves.quad(ridge_a, ridge_b, end + across * width_b,
					start + across * width_a, Color("639c57"))
				leaves.quad(start - across * width_a, end - across * width_b,
					ridge_b, ridge_a, Color("397c50"))
	for index in 3:
		var angle := index * TAU / 3.0
		trunk.ellipsoid(crown + Vector3(cos(angle) * 0.22, -0.18, sin(angle) * 0.22),
			Vector3(0.27, 0.32, 0.27), Color("806044"), 8)
	var trunk_mesh := trunk.finish()
	var leaf_mesh := leaves.finish()
	var bark := timber_material()
	var green := foliage_material()
	for start in range(0, poses.size(), PINE_BATCH_SIZE):
		var batch := Node3D.new()
		batch.name = "PalmBatch%d" % start
		grove.add_child(batch)
		var stems := _tree_batch("Trunks", trunk_mesh, poses, start)
		stems.material_override = bark
		batch.add_child(stems)
		var fronds := _tree_batch("Fronds", leaf_mesh, poses, start)
		fronds.material_override = green
		batch.add_child(fronds)


func _tree_batch(
	title: String, mesh: Mesh, poses: Array[Transform3D], start: int,
	local_transform := Transform3D.IDENTITY
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = mini(PINE_BATCH_SIZE, poses.size() - start)
	for index in multimesh.instance_count:
		multimesh.set_instance_transform(index, poses[start + index] * local_transform)
	var instance := MultiMeshInstance3D.new()
	instance.name = title
	instance.multimesh = multimesh
	return instance


static func pine_model(scale_factor: float) -> Node3D:
	var tree := PINE_MODEL.instantiate() as Node3D
	tree.name = "RoadsidePine"
	(tree.get_node("PineTree") as Node3D).scale = Vector3.ONE * PINE_SCALE * scale_factor
	return tree


## One bay of trail fence: a leaning post and the rail it carries.
static func fence_parts(wood: Builder, post: Vector3) -> void:
	wood.box(post + Vector3(0, 0.63, 0), Vector3(0.13, 1.30, 0.13),
		Color("74644a"), Vector3(0, 0, -0.025))
	wood.box(post + Vector3(0, 0.82, 0), Vector3(1.55, 0.10, 0.10),
		Color("b29c70"))


## A trail sign: two posts under a rounded board, its cream plate and its panel.
static func sign_parts(wood: Builder, details: Builder, base: Vector3) -> void:
	for offset: float in [-1.08, 1.08]:
		wood.box(base + Vector3(offset, 1.55, 0), Vector3(0.12, 3.10, 0.12),
			Color("756147"))
	details.rounded_box(base + Vector3(0, 3.0, 0),
		Vector3(3.15, 0.92, 0.15), 0.065, Color("2f5146"))
	details.box(base + Vector3(0, 3.0, 0.083),
		Vector3(2.98, 0.76, 0.02), Color("d0c196"))
	details.box(base + Vector3(0, 3.0, 0.101),
		Vector3(2.92, 0.70, 0.015), Color("345a4b"))


## The two lines a sign board is drawn around, at the sizes it was drawn for.
static func sign_labels(title: String, detail: String, base: Vector3) -> Array[Label3D]:
	return [
		trail_label(title, base + Vector3(0, 3.16, 0.13), 48, 0.006, Art.CREAM, false),
		trail_label(detail, base + Vector3(0, 2.84, 0.13), 32, 0.0042, Art.CREAM, false),
	]


func _build_water_and_clouds() -> void:
	var pools := Node3D.new()
	pools.name = "QuarryWater"
	add_child(pools)
	_ripples = Node3D.new()
	_ripples.name = "QuietWaterRipples"
	add_child(_ripples)
	_clouds = Node3D.new()
	_clouds.name = "SlowDriftingClouds"
	add_child(_clouds)
	var water_finish := Art.material(0.21, 0.25)
	var ripple_finish := Art.material(0.5)
	var cloud_finish := Art.material(1.0)
	var level := Art.world_point(Vector2(0, course.fall_y - 80.0)).y
	var water_color := Color("467d7a")
	var cloud_color := Color("e1e4d2")
	if course.scenery == Course.Scenery.BEACH:
		level = BEACH_SEA_Y
		water_color = Color("56c7ba")
		cloud_color = Color("f8f8ed")
	elif course.scenery == Course.Scenery.SNOW:
		water_color = Color("a7d4e3")
		cloud_color = Color("e6eff4")
		water_finish.roughness = 0.32
	var gaps := course.gap_intervals()
	# Local bounds let each camera cull distant pools and clouds on the longer trail.
	for gap_index in gaps.size():
		var gap := gaps[gap_index]
		var water := Builder.new()
		var ripples := Builder.new()
		var left := (gap.x - 200.0) * Art.WORLD_SCALE
		var right := (gap.y + 200.0) * Art.WORLD_SCALE
		water.quad(Vector3(left, level, 8), Vector3(right, level, 8),
			Vector3(right, level, -24), Vector3(left, level, -24), water_color)
		if course.scenery == Course.Scenery.SNOW:
			for index in 6:
				var at := Vector3(lerpf(left, right, 0.15 + (index % 3) * 0.3),
					level + 0.025, 5.0 - index * 4.2)
				water.beam(at, at + Vector3(1.6, 0, -1.2), 0.025, Color("e2f1f7"))
				water.beam(at, at + Vector3(-0.8, 0, -1.8), 0.018, Color("e2f1f7"))
		else:
			for index in 8:
				var center := Vector3(lerpf(left, right, 0.2 + (index % 3) * 0.3),
					level + 0.025, -index * 2.9)
				var radius := 0.5 + (index % 4) * 0.32
				ripples.torus(center, radius, radius + 0.017,
					Color("b5ece0") if course.scenery == Course.Scenery.BEACH else Color("94b7a6"))
			_mesh("Ripples%d" % gap_index, ripples, ripple_finish, _ripples)
		_mesh("Pool%d" % gap_index, water, water_finish, pools)
	if course.scenery == Course.Scenery.BEACH:
		_build_ocean()
	for index in ceili((course.end_x * Art.WORLD_SCALE + 30.0) / 23.0):
		var clouds := Builder.new()
		var at := Vector3(-8 + index * 23, 9 + (index % 3) * 1.2, -41 - (index % 2) * 6)
		for lobe in 4:
			clouds.ellipsoid(at + Vector3(lobe * 1.7, sin(lobe * 1.9) * 0.3, 0),
				Vector3(4.3, 1.25 + (lobe % 2) * 0.4, 2.4), cloud_color, 12)
		_mesh("Cloud%d" % index, clouds, cloud_finish, _clouds)


func _build_ocean() -> void:
	var ocean := Node3D.new()
	ocean.name = "CoastalOcean"
	add_child(ocean)
	var depths: Array[float] = [-3.3, -18.0, -34.0, -64.0, -155.0]
	var colors: Array[Color] = [
		Color("56c7ba"), Color("35b4b4"), Color("319daf"), Color("2b88a5"),
	]
	var finish := Art.material(0.28, 0.18)
	var foam_finish := Art.material(0.8)
	var count := ceili((course.end_x * Art.WORLD_SCALE + 60.0) / 20.0)
	for chunk in count:
		var water := Builder.new()
		var foam := Builder.new()
		var left := HILL_X_ORIGIN + chunk * 20.0
		var right := left + 20.0
		for band in colors.size():
			water.quad(Vector3(left, BEACH_SEA_Y, depths[band]),
				Vector3(right, BEACH_SEA_Y, depths[band]),
				Vector3(right, BEACH_SEA_Y, depths[band + 1]),
				Vector3(left, BEACH_SEA_Y, depths[band + 1]), colors[band])
		for step in 4:
			var a := _shore_point(left + step * HILL_STEP)
			var b := _shore_point(left + (step + 1) * HILL_STEP)
			foam.quad(a, b, b + Vector3(0, 0, -0.25), a + Vector3(0, 0, -0.25),
				Color("e3f4df"))
			for wave in 3:
				var z := -24.0 - wave * 14.0 + sin((chunk * 4 + step) * 0.8) * 0.8
				a = Vector3(left + step * HILL_STEP, BEACH_SEA_Y + 0.035, z)
				b = Vector3(a.x + HILL_STEP, a.y, z + sin(step + wave) * 0.3)
				foam.quad(a, b, b + Vector3(0, 0, -0.07), a + Vector3(0, 0, -0.07),
					Color("8cdbd2"))
		_mesh("Ocean%d" % chunk, water, finish, ocean)
		_mesh("Surf%d" % chunk, foam, foam_finish, _ripples)


func _shore_point(x: float) -> Vector3:
	var near := _hill_point(x, HILL_ROWS[0])
	for z in HILL_ROWS:
		var far := _hill_point(x, z)
		if far.y <= BEACH_SEA_Y:
			var along := inverse_lerp(near.y, far.y, BEACH_SEA_Y) if near.y > BEACH_SEA_Y else 0.0
			var shore := near.lerp(far, along)
			return Vector3(x, BEACH_SEA_Y + 0.035, shore.z)
		near = far
	assert(false, "Beach terrain must descend below sea level.")
	return Vector3.INF


func _build_pickups() -> void:
	for index in course.plug_x.size():
		var root := numbered_plug(index)
		root.position = Art.world_point(course.plug_position(index))
		add_child(root)
		plugs.append(root)


## Only the pickup cue and number are added; the plug keeps its exported meshes and paint.
static func numbered_plug(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "SparkPlug%d" % (index + 1)
	var model := PLUG_MODEL.instantiate() as Node3D
	model.name = "ImportedPlug"
	model.scale = Vector3.ONE * PLUG_SCALE
	model.position.y = -PLUG_HEIGHT * 0.5
	root.add_child(model)
	var ring := Builder.new()
	ring.torus(Vector3.ZERO, 0.55, 0.575, Color("e6c77d"), Vector3(PI / 2, 0, 0))
	var cue := MeshInstance3D.new()
	cue.name = "PickupRing"
	cue.mesh = ring.finish()
	var ring_material := Art.material(0.4, 0.18)
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cue.material_override = ring_material
	cue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cue)
	root.add_child(plug_label(index))
	return root


## Each plug carries its own number, so the five are told apart by reading rather
## than by counting backwards along the trail.
static func plug_label(index: int) -> Label3D:
	var number := trail_label(str(index + 1), Vector3(0, 0.82, 0), 54, 0.007, Art.CREAM)
	number.name = "PickupNumber"
	number.outline_size = 10
	return number


func _build_checkpoints() -> void:
	for index in range(1, course.checkpoint_x.size()):
		var x := course.checkpoint_x[index]
		var base := Art.world_point(Vector2(x, course.ground_height(x)), -2.8)
		var model := checkpoint_model(index)
		model.position = base
		var flag := model.get_node("CheckpointFlag/FlagCloth") as MeshInstance3D
		var finish := checkpoint_flag_material(flag)
		if finish == null:
			model.free()
			return
		add_child(model)
		_flag_materials.append(finish)
		_flag_rest_colors.append(finish.albedo_color)
		checkpoint_flags.append(flag)
		checkpoint_labels.append(model.get_node("CheckpointLabel") as Label3D)


static func checkpoint_model(index: int) -> Node3D:
	var model := CHECKPOINT_MODEL.instantiate() as Node3D
	model.name = "Checkpoint%d" % index
	var label := trail_label("CHECKPOINT %d" % index,
		CHECKPOINT_LABEL_OFFSET, 42, 0.006, Art.CREAM)
	label.name = "CheckpointLabel"
	model.add_child(label)
	return model


## Tint only this flag's field: the checker and the shared GLB materials stay intact.
static func checkpoint_flag_material(flag: MeshInstance3D) -> StandardMaterial3D:
	for surface in flag.mesh.get_surface_count():
		var exported := flag.mesh.surface_get_material(surface) as StandardMaterial3D
		if exported != null and exported.resource_name == CHECKPOINT_FIELD_MATERIAL:
			var finish := exported.duplicate() as StandardMaterial3D
			flag.set_surface_override_material(surface, finish)
			return finish
	push_error("checkpoint_flag.glb must contain the portable 'Cube Flag field' material.")
	return null


func _build_garage() -> void:
	var x := (course.finish_x + GARAGE_COURSE_OFFSET) * Art.WORLD_SCALE
	var y := Art.world_point(Vector2(course.finish_x, course.ground_height(course.finish_x))).y
	var model := garage_model(false, course.finish_width)
	model.position = Vector3(x, y, -4.9)
	add_child(model)
	_garage_root = model
	var shop := model.get_node("ImportedBodyShop") as Node3D
	var floor_mesh := shop.get_node("CarBodyShop/Forecourt") as MeshInstance3D
	var bounds := (model.transform * shop.transform) * floor_mesh.mesh.get_aabb()
	_garage_site = Rect2(Vector2(bounds.position.x, bounds.position.z),
		Vector2(bounds.size.x, bounds.size.z))
	_garage_floor_y = y
	# Flatten whole ridge cells, not just their centers, so no hill cuts through the open bay.
	var left := floorf((_garage_site.position.x - HILL_X_ORIGIN) / HILL_STEP) \
		* HILL_STEP + HILL_X_ORIGIN
	var right := ceilf((_garage_site.end.x - HILL_X_ORIGIN) / HILL_STEP) \
		* HILL_STEP + HILL_X_ORIGIN
	var back := HILL_ROWS[0]
	for row in HILL_ROWS:
		back = row
		if row <= _garage_site.position.y:
			break
	_garage_pad = Rect2(Vector2(left, back), Vector2(right - left, HILL_ROWS[0] - back))
	garage_label = model.get_node("GarageStatus") as Label3D
	parking_label = model.get_node("ParkingHint") as Label3D
	_parking_outline = model.get_node("ParkingOutline") as MeshInstance3D
	_parking_material = _parking_outline.material_override as ShaderMaterial
	_workshop_light = model.get_node("WorkshopLight") as OmniLight3D
	for index in 5:
		_garage_lamps.append(model.get_node("DeliveredPlug%d" % (index + 1)) as MeshInstance3D)


## The imported shop carries the live delivery board and the exact physics parking zone.
static func garage_model(delivered := false, parking_width := Course.FINISH_WIDTH) -> Node3D:
	var root := Node3D.new()
	root.name = "CopperCreekServiceGarage"
	var shop := GARAGE_MODEL.instantiate() as Node3D
	shop.name = "ImportedBodyShop"
	shop.scale = Vector3.ONE * GARAGE_SCALE
	shop.position = GARAGE_MODEL_OFFSET
	root.add_child(shop)
	var board := Builder.new()
	board.box(Vector3(0.7, 3.24, GARAGE_FEEDBACK_Z - 0.05),
		Vector3(4.65, 0.50, 0.045), Art.INK)
	var panel := MeshInstance3D.new()
	panel.name = "DeliveryBoard"
	panel.mesh = board.finish()
	panel.material_override = signage_material()
	root.add_child(panel)
	var status := "BRAKE TO PARK" if delivered else "BRING ALL FIVE PLUGS"
	var label := trail_label(status, Vector3(0.7, 3.33, GARAGE_FEEDBACK_Z - 0.01),
		40, 0.0055, Art.CREAM, false)
	label.name = "GarageStatus"
	root.add_child(label)
	for index in 5:
		root.add_child(garage_lamp(index, Vector3.ZERO, delivered))
	var markings := Builder.new()
	var start := -GARAGE_COURSE_OFFSET * Art.WORLD_SCALE
	var width := parking_width * Art.WORLD_SCALE
	for x: float in [start, start + width]:
		markings.box(Vector3(x, 0.030, 5.25), Vector3(0.075, 0.016, 4.2), Art.CREAM)
	for index in 12:
		markings.box(Vector3(start + (index + 0.5) * width / 12, 0.030, 7.33),
			Vector3(width / 12, 0.016, 0.24), Art.CREAM if index % 2 == 0 else Art.INK)
	var paint := MeshInstance3D.new()
	paint.name = "FinishBayMarkings"
	paint.mesh = markings.finish()
	paint.material_override = signage_material()
	root.add_child(paint)
	var outline := MeshInstance3D.new()
	outline.name = "ParkingOutline"
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, PARKING_DEPTH)
	outline.mesh = plane
	outline.position = Vector3(start + width * 0.5, 0.055, 5.25)
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := ShaderMaterial.new()
	glow.shader = PARKING_SHADER
	glow.set_shader_parameter("bay_size", plane.size)
	glow.set_shader_parameter("tint", PARKING_READY if delivered else PARKING_WAIT)
	outline.material_override = glow
	root.add_child(outline)
	var hint := trail_label("PARK HERE" if delivered else "NEED 5 PLUGS",
		Vector3(start + width * 0.5, 0.55, 7.65), 40, 0.008,
		PARKING_READY if delivered else PARKING_WAIT)
	hint.name = "ParkingHint"
	root.add_child(hint)
	var light := OmniLight3D.new()
	light.name = "WorkshopLight"
	light.position = Vector3(0.7, 2.6, GARAGE_FEEDBACK_Z - 0.8)
	light.light_color = Color("ffd49a")
	light.omni_range = 6.5
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.visible = false
	root.add_child(light)
	return root


## One of the five bulbs over the door, lit as each plug is delivered.
static func garage_lamp(index: int, at: Vector3, lit := false) -> MeshInstance3D:
	var light := MeshInstance3D.new()
	light.name = "DeliveredPlug%d" % (index + 1)
	var bulb := SphereMesh.new()
	bulb.radius = 0.10
	bulb.height = 0.20
	bulb.radial_segments = 12
	bulb.rings = 6
	light.mesh = bulb
	var finish := Art.material(0.35)
	finish.albedo_color = Art.CREAM if lit else Color("3f5a50")
	finish.emission_enabled = true
	finish.emission = Art.CREAM
	finish.emission_energy_multiplier = 1.1 if lit else 0.0
	light.material_override = finish
	light.position = at + Vector3(-0.4 + index * 0.55, 3.10, GARAGE_FEEDBACK_Z + 0.08)
	return light


# --------------------------------------------------------------------------
# Shared finishes and signage
# --------------------------------------------------------------------------

## Named rather than repeated, so a model on a gallery plinth cannot be given a
## nicer finish than the same model has out on the trail.


static func timber_material() -> StandardMaterial3D:
	return Art.material(0.96)


## Shoulder grass is an open sheet; the pine keeps its imported foliage materials.
static func foliage_material() -> StandardMaterial3D:
	var finish := Art.material(0.95)
	finish.cull_mode = BaseMaterial3D.CULL_DISABLED
	return finish


static func signage_material() -> StandardMaterial3D:
	return Art.material(0.8)


## Every word Copper Creek says in the world is a Label3D built here, so the
## trail and the gallery cannot word or size their signage differently.
static func trail_label(
	text: String, at: Vector3, font_size: int, pixel_size: float,
	color: Color, billboard := true
) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_modulate = Art.INK
	label.outline_size = 6 if billboard else 0
	label.billboard = (
		BaseMaterial3D.BILLBOARD_ENABLED if billboard
		else BaseMaterial3D.BILLBOARD_DISABLED
	)
	label.position = at
	return label


func _build_dust() -> void:
	_dust = TireParticles.new(course.scenery)
	_dust.name = "OptionalTireDust"
	add_child(_dust)


func _build_snowfall() -> void:
	_snowfall = MultiMeshInstance3D.new()
	_snowfall.name = "OptionalSnowfall"
	var flake := QuadMesh.new()
	flake.size = Vector2(0.22, 0.22)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = flake
	multimesh.instance_count = SNOWFLAKE_COUNT
	multimesh.visible_instance_count = 0
	_snowfall.multimesh = multimesh
	var finish := Art.material()
	finish.albedo_texture = Art.soft_particle_texture()
	finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	finish.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	finish.billboard_keep_scale = true
	_snowfall.material_override = finish
	_snowfall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snowfall)


func _update_snowfall(state: State, time: float, enabled: bool) -> void:
	if _snowfall == null:
		return
	_snowfall.multimesh.visible_instance_count = SNOWFLAKE_COUNT \
		if enabled and not state.is_over() else 0
	if _snowfall.multimesh.visible_instance_count == 0:
		return
	var origin := Art.world_point(state.position)
	for index in SNOWFLAKE_COUNT:
		var layer := index % 3
		var breeze := time * (0.35 + layer * 0.08) + sin(time * 0.65 + index * 1.71) * 0.6
		var width := 32.0 if layer == 0 else 52.0
		var height := 16.0 if layer == 0 else 22.0
		var x := fposmod(index * 7.31 - origin.x + breeze, width)
		var y := fposmod(index * 3.77 - origin.y - time * (0.9 + layer * 0.3), height)
		var at := Vector3(
			origin.x - 16.0 + x, origin.y - 7.0 + y,
			-4.5 - layer * 5.5 - fposmod(index * 3.13, 5.0)
		)
		# A sparse forward layer is visible through narrow windshields, never inside the cabin.
		if layer == 0:
			at = Vector3(origin.x + 4.5 + x, origin.y - 4.0 + y,
				-2.8 + fposmod(index * 3.13, 5.6))
		var scale_factor := (0.9 + (index % 5) * 0.18) * (1.0 - layer * 0.15)
		_snowfall.multimesh.set_instance_transform(index,
			Transform3D(Basis.from_scale(Vector3.ONE * scale_factor), at))
		var color := Color("dfeaf2")
		var edge := minf(minf(x, width - x), minf(y, height - y))
		color.a = (0.9 - layer * 0.15) * smoothstep(0.0, 1.6, edge)
		_snowfall.multimesh.set_instance_color(index, color)


func _mesh(
	title: String, parts: Builder, finish: Material, parent: Node3D = null
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = parts.finish()
	instance.material_override = finish
	if parent == null:
		add_child(instance)
	else:
		parent.add_child(instance)
	return instance
