extends Node3D

## Copper Creek is real extruded terrain, with scenery kept out of the driving plane.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Daylight = preload("res://games/cube_trials/world/daylight.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const PINE_MODEL = preload("res://games/cube_trials/assets/models/pine_tree.glb")
const PLUG_MODEL = preload("res://games/cube_trials/assets/models/spark_plug.glb")
const CHECKPOINT_MODEL = preload("res://games/cube_trials/assets/models/checkpoint_flag.glb")
const GARAGE_MODEL = preload("res://games/cube_trials/assets/models/car_body_shop.glb")
const PARKING_SHADER = preload("res://games/cube_trials/assets/shaders/parking_outline.gdshader")
const PARKING_WAIT := Color("ffd17b")
const PARKING_READY := Color("67f0c2")
const PARKING_DEPTH := 4.2
const ROAD_HALF_WIDTH := 3.2
const TIRE_CLEARANCE := State.WHEEL_RADIUS * Art.WORLD_SCALE - 0.15
const HILL_X_ORIGIN := -30.0
const HILL_STEP := 5.0
const HILL_ROWS: Array[float] = [-3.3, -8.0, -16.0, -25.0, -34.0, -44.0]
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
var daylight: Daylight
var pine_poses: Array[Transform3D] = []
var plugs: Array[Node3D] = []
var checkpoint_flags: Array[MeshInstance3D] = []
var checkpoint_labels: Array[Label3D] = []
var garage_label: Label3D
var parking_label: Label3D
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
var _dust: MultiMeshInstance3D
var _last_plugs := -1
var _last_checkpoint := -1
var _last_finished := false


func _ready() -> void:
	daylight = Art.light_stage(self)
	_build_garage()
	_build_terrain()
	_build_hills()
	_build_scenery()
	_build_water_and_clouds()
	_build_pickups()
	_build_checkpoints()
	_build_dust()
	car = Cube.new()
	add_child(car)


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
		plugs[index].position = Art.world_point(Course.plug_position(index))
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
	_ripples.position.y = 0.0 if reduced else sin(time * 1.5) * 0.02
	_update_dust(state, time, not reduced and intense)


## The screen-space hint points at the near edge of the actual stopping zone.
func parking_target() -> Vector3:
	return _parking_outline.to_global(Vector3(0, 0, PARKING_DEPTH * 0.5))


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
	elif state.position.x >= Course.FINISH_X \
		and state.position.x <= Course.FINISH_X + Course.FINISH_WIDTH \
		and absf(state.velocity.x) >= State.PARK_SPEED:
		parking_label.text = "SLOW DOWN"
	parking_label.modulate = color
	_parking_material.set_shader_parameter("tint", color)
	var animate := not reduced and intense and not state.is_over()
	_parking_material.set_shader_parameter("pulse",
		0.9 + sin(time * 1.8) * 0.1 if animate else 1.0)
	_parking_material.set_shader_parameter("halo_strength", 1.0 if intense else 0.0)
	_workshop_light.visible = daylight.night_amount > 0.01
	_workshop_light.light_energy = daylight.night_amount * 1.6


func _build_terrain() -> void:
	var road := Builder.new()
	var earth := Builder.new()
	var depths: Array[float] = [-3.2, -2.55, -2.2, 2.2, 2.55, 3.2]
	var colors: Array[Color] = [
		Color("70805b"), Color("d8c496"), Color("b5a27b"),
		Color("d8c496"), Color("70805b"),
	]
	var layers: Array[float] = [0.0, 0.40, 1.10, 2.7, 4.0, 6.5, 18.0]
	var rock: Array[Color] = [
		Color("99815a"), Color("bd9769"), Color("9c7654"),
		Color("c29e70"), Color("a58460"), Color("806f55"),
	]
	for section: Array in Course.ROADS:
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
					a + Vector3(0, 0.018, z - 0.18), Color("978866"))
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
			var near_top := p + Vector3(0, 0, ROAD_HALF_WIDTH)
			var far_top := p - Vector3(0, 0, ROAD_HALF_WIDTH)
			if endpoint == 0:
				earth.quad(near_top, far_top, far_top - Vector3.UP * 18,
					near_top - Vector3.UP * 18, Color("aa835e"))
			else:
				earth.quad(far_top, near_top, near_top - Vector3.UP * 18,
					far_top - Vector3.UP * 18, Color("aa835e"))
	_mesh("ExactDrivingSurface", road, Art.material(0.98))
	_mesh("LayeredQuarryRock", earth, Art.material(0.98))
	var markers := Builder.new()
	for gap in Course.gap_intervals():
		for offset: float in [130.0, 90.0, 50.0]:
			var x := gap.x - offset
			var a := Art.world_point(Vector2(x, Course.ground_height(x))) + Vector3.UP * 0.025
			var b := Art.world_point(Vector2(x + 7.0, Course.ground_height(x + 7.0))) \
				+ Vector3.UP * 0.025
			markers.quad(a + Vector3(0, 0, 2.5), b + Vector3(0, 0, 2.5),
				b - Vector3(0, 0, 2.5), a - Vector3(0, 0, 2.5), Color("e6c77d"))
	_mesh("JumpApproachMarkers", markers, signage_material())


func _build_hills() -> void:
	var hills := Builder.new()
	var rows := HILL_ROWS
	var columns := ceili((Course.END_X * Art.WORLD_SCALE + 30.0 - HILL_X_ORIGIN) / HILL_STEP)
	for row in range(rows.size() - 1):
		for column in columns:
			var x := HILL_X_ORIGIN + column * HILL_STEP
			var a := _hill_point(x, rows[row])
			var b := _hill_point(x + HILL_STEP, rows[row])
			var c := _hill_point(x + HILL_STEP, rows[row + 1])
			var d := _hill_point(x, rows[row + 1])
			var color := Color("657b55").lerp(
				Color("a6b6b2"), float(row) / (rows.size() - 2)
			)
			color = color.lightened(float((column + row) % 3) * 0.025)
			hills.triangle(a, b, c, color)
			hills.triangle(a, c, d, color.darkened(0.025))
	_mesh("DistantThreeDimensionalRidges", hills, Art.material(1.0))


func _hill_point(x: float, z: float) -> Vector3:
	var floor_y := Course.ground_height(x / Art.WORLD_SCALE)
	var base := (Art.HEIGHT_ORIGIN - floor_y) * Art.WORLD_SCALE if is_finite(floor_y) else 0.0
	var distance := absf(z) - 3.3
	var ridge := sin(x * 0.13 + z * 0.037) * 0.48 \
		+ cos(x * 0.065 - z * 0.10) * 0.38 + sin(x * 0.28 + z * 0.12) * 0.14
	var height := base + (0.7 + ridge) * minf(distance * 0.16, 7.0)
	for gap in Course.gap_intervals():
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
	var count := ceili((Course.END_X * Art.WORLD_SCALE + 16.0) / 2.05)
	for index in count:
		var x := -8.0 + index * 2.05
		var floor_y := Course.ground_height(x / Art.WORLD_SCALE)
		if not is_finite(floor_y):
			continue
		var ground := Art.world_point(Vector2(x / Art.WORLD_SCALE, floor_y))
		for side: float in [-1.0, 1.0]:
			var z := side * (2.75 + float(index % 3) * 0.09)
			var position := ground + Vector3(0, 0, z)
			if _garage_site.grow(0.35).has_point(Vector2(position.x, position.z)):
				continue
			stones.ellipsoid(position + Vector3(0, 0.07, 0),
				Vector3(0.18 + index % 3 * 0.05, 0.13, 0.16), Color("94876c"), 8)
			for blade in 3:
				var offset := Vector3(blade * 0.055, 0, 0)
				foliage.triangle(position + offset, position + offset + Vector3(0.08, 0, 0),
					position + offset + Vector3(0.04, 0.23 + blade * 0.06, -0.04),
					Color("8b985b") if index % 2 == 0 else Color("667b4b"))
		if index % 3 == 0 and not _garage_site.grow(0.8).has_point(Vector2(x, -2.92)):
			fence_parts(wood, ground + Vector3(0, 0, -2.92))
		if index % 4 == 0:
			var tree_z := -7.5 - index % 3 * 3.0
			if _garage_site.grow(1.5).has_point(Vector2(x + 1.0, tree_z)):
				tree_z = _garage_site.position.y - 1.5
			var tree_at := _terrain_point(x + 1.0, tree_z)
			var tree_scale := PINE_SCALE * (0.8 + float(index % 5) * 0.13)
			pine_poses.append(Transform3D(Basis.from_scale(Vector3.ONE * tree_scale), tree_at))
		if index % 7 == 0 and not _garage_site.grow(1.0).has_point(Vector2(x - 0.3, -4.0)):
			var rock_at := _terrain_point(x - 0.3, -4.0)
			stones.ellipsoid(rock_at + Vector3(0, 0.35, 0),
				Vector3(1.0, 0.7, 0.85), Color("9e9279"), 8)
	for sign: Dictionary in Course.SIGNS:
		var x: float = sign["x"]
		var base := Art.world_point(Vector2(x, Course.ground_height(x)), -3.0)
		sign_parts(wood, details, base)
		for label in sign_labels(sign["title"], sign["detail"], base):
			add_child(label)
	_mesh("RoadsideTimber", wood, timber_material())
	_mesh("ShoulderGrass", foliage, foliage_material())
	_mesh("ScatteredQuarryStones", stones, Art.material(1.0))
	_mesh("TrailSignBoards", details, signage_material())
	_build_pines()


## Small spatial batches share the exported meshes without drawing the whole forest at once.
func _build_pines() -> void:
	var forest := Node3D.new()
	forest.name = "RoadsidePines"
	add_child(forest)
	var source := PINE_MODEL.instantiate() as Node3D
	var assembly := source.get_node("PineTree") as Node3D
	for start in range(0, pine_poses.size(), PINE_BATCH_SIZE):
		var batch := Node3D.new()
		batch.name = "PineBatch%d" % start
		forest.add_child(batch)
		for part: MeshInstance3D in assembly.get_children():
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = part.mesh
			multimesh.instance_count = mini(PINE_BATCH_SIZE, pine_poses.size() - start)
			for index in multimesh.instance_count:
				multimesh.set_instance_transform(index,
					pine_poses[start + index] * assembly.transform * part.transform)
			var instance := MultiMeshInstance3D.new()
			instance.name = part.name
			instance.multimesh = multimesh
			batch.add_child(instance)
	source.free()


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
	var level := Art.world_point(Vector2(0, Course.FALL_Y - 80.0)).y
	var gaps := Course.gap_intervals()
	# Local bounds let each camera cull distant pools and clouds on the longer trail.
	for gap_index in gaps.size():
		var gap := gaps[gap_index]
		var water := Builder.new()
		var ripples := Builder.new()
		var left := (gap.x - 200.0) * Art.WORLD_SCALE
		var right := (gap.y + 200.0) * Art.WORLD_SCALE
		water.quad(Vector3(left, level, 8), Vector3(right, level, 8),
			Vector3(right, level, -24), Vector3(left, level, -24), Color("467d7a"))
		for index in 8:
			var center := Vector3(lerpf(left, right, 0.2 + (index % 3) * 0.3),
				level + 0.025, -index * 2.9)
			var radius := 0.5 + (index % 4) * 0.32
			ripples.torus(center, radius, radius + 0.017, Color("94b7a6"))
		_mesh("Pool%d" % gap_index, water, water_finish, pools)
		_mesh("Ripples%d" % gap_index, ripples, ripple_finish, _ripples)
	for index in ceili((Course.END_X * Art.WORLD_SCALE + 30.0) / 23.0):
		var clouds := Builder.new()
		var at := Vector3(-8 + index * 23, 9 + (index % 3) * 1.2, -41 - (index % 2) * 6)
		for lobe in 4:
			clouds.ellipsoid(at + Vector3(lobe * 1.7, sin(lobe * 1.9) * 0.3, 0),
				Vector3(4.3, 1.25 + (lobe % 2) * 0.4, 2.4), Color("e1e4d2"), 12)
		_mesh("Cloud%d" % index, clouds, cloud_finish, _clouds)


func _build_pickups() -> void:
	for index in Course.PLUG_X.size():
		var root := numbered_plug(index)
		root.position = Art.world_point(Course.plug_position(index))
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
	for index in range(1, Course.CHECKPOINT_X.size()):
		var x := Course.CHECKPOINT_X[index]
		var base := Art.world_point(Vector2(x, Course.ground_height(x)), -2.8)
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
	var x := (Course.FINISH_X + GARAGE_COURSE_OFFSET) * Art.WORLD_SCALE
	var y := Art.world_point(Vector2(Course.FINISH_X, Course.ground_height(Course.FINISH_X))).y
	var model := garage_model()
	model.position = Vector3(x, y, -4.9)
	add_child(model)
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
static func garage_model(delivered := false) -> Node3D:
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
	var width := Course.FINISH_WIDTH * Art.WORLD_SCALE
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
	_dust = MultiMeshInstance3D.new()
	_dust.name = "OptionalTireDust"
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = 14
	multimesh.visible_instance_count = 0
	_dust.multimesh = multimesh
	var material := Art.material(1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust.material_override = material
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)


func _update_dust(state: State, time: float, enabled: bool) -> void:
	var active := enabled and state.contacts > 0 and absf(state.velocity.x) > 80 \
		and state.crash_wait == 0.0 and not state.is_over()
	_dust.multimesh.visible_instance_count = 14 if active else 0
	if not active:
		return
	var origin := Art.world_point(state.wheel_centers[0])
	for index in 14:
		var age := fposmod(time * 1.6 + index / 14.0, 1.0)
		var at := origin + Vector3(-age * state.velocity.x * 0.003,
			-TIRE_CLEARANCE + age * 0.45, -Cube.WHEEL_Z if index % 2 == 0 else Cube.WHEEL_Z)
		var scale_factor := 0.12 + age * 0.55
		_dust.multimesh.set_instance_transform(index,
			Transform3D(Basis.from_scale(Vector3.ONE * scale_factor), at))
		_dust.multimesh.set_instance_color(index, Color(0.75, 0.65, 0.47, (1.0 - age) * 0.28))


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
