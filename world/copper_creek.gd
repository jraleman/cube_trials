extends Node3D

## Copper Creek is real extruded terrain, with scenery kept out of the driving plane.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Course = preload("res://games/cube_trials/course.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const ROAD_HALF_WIDTH := 3.2
const TIRE_CLEARANCE := State.WHEEL_RADIUS * Art.WORLD_SCALE - 0.15
const HILL_ROWS: Array[float] = [-3.3, -8.0, -16.0, -25.0, -34.0, -44.0]

var car: Cube
var plugs: Array[Node3D] = []
var checkpoint_flags: Array[MeshInstance3D] = []
var checkpoint_labels: Array[Label3D] = []
var garage_label: Label3D
var _flag_materials: Array[StandardMaterial3D] = []
var _garage_lamps: Array[MeshInstance3D] = []
var _clouds: MeshInstance3D
var _ripples: MeshInstance3D
var _dust: MultiMeshInstance3D
var _last_plugs := -1
var _last_checkpoint := -1


func _ready() -> void:
	Art.light_stage(self)
	_build_terrain()
	_build_hills()
	_build_scenery()
	_build_water_and_clouds()
	_build_pickups()
	_build_checkpoints()
	_build_garage()
	_build_dust()
	car = Cube.new()
	add_child(car)


## Rendering reads the model; it never steps physics or changes checkpoint ownership.
func present(state: State, time: float, reduced: bool, intense: bool, braking: bool) -> void:
	car.apply_state(state, braking)
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
			_flag_materials[index].albedo_color = Art.TEAL if saved else Art.CREAM
			checkpoint_labels[index].text = "CHECKPOINT %d%s" % [
				index + 1, " / SAVED" if saved else "",
			]
	if _last_plugs != state.plug_count():
		_last_plugs = state.plug_count()
		garage_label.text = "BRAKE TO PARK" if _last_plugs == 5 else "BRING ALL FIVE PLUGS"
		for index in 5:
			var material := _garage_lamps[index].material_override as StandardMaterial3D
			material.albedo_color = Art.CREAM if state.collected[index] else Color("3f5a50")
	_clouds.position.x = 0.0 if reduced else sin(time * 0.07) * 1.5
	_ripples.position.y = 0.0 if reduced else sin(time * 1.5) * 0.02
	_update_dust(state, time, not reduced and intense)


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
			for z: float in [-1.07, 1.07]:
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


func _build_hills() -> void:
	var hills := Builder.new()
	var rows := HILL_ROWS
	for row in range(rows.size() - 1):
		for column in 42:
			var x := -30.0 + column * 5.0
			var a := _hill_point(x, rows[row])
			var b := _hill_point(x + 5, rows[row])
			var c := _hill_point(x + 5, rows[row + 1])
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
	var quarry := exp(-pow((x - 71.5) / 9.0, 4)) * maxf(0, 1.0 - distance / 28.0)
	return Vector3(x, height - quarry * 14.0, z)


func _terrain_point(x: float, z: float) -> Vector3:
	var left := floorf((x + 30.0) / 5.0) * 5.0 - 30.0
	for row in range(HILL_ROWS.size() - 1):
		if z > HILL_ROWS[row] or z < HILL_ROWS[row + 1]:
			continue
		var a := _hill_point(left, HILL_ROWS[row])
		var b := _hill_point(left + 5, HILL_ROWS[row])
		var c := _hill_point(left + 5, HILL_ROWS[row + 1])
		var d := _hill_point(left, HILL_ROWS[row + 1])
		var u := (x - left) / 5.0
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
	for index in 78:
		var x := -8.0 + index * 2.05
		var floor_y := Course.ground_height(x / Art.WORLD_SCALE)
		if not is_finite(floor_y):
			continue
		var ground := Art.world_point(Vector2(x / Art.WORLD_SCALE, floor_y))
		for side: float in [-1.0, 1.0]:
			var z := side * (2.75 + float(index % 3) * 0.09)
			var position := ground + Vector3(0, 0, z)
			stones.ellipsoid(position + Vector3(0, 0.07, 0),
				Vector3(0.18 + index % 3 * 0.05, 0.13, 0.16), Color("94876c"), 8)
			for blade in 3:
				var offset := Vector3(blade * 0.055, 0, 0)
				foliage.triangle(position + offset, position + offset + Vector3(0.08, 0, 0),
					position + offset + Vector3(0.04, 0.23 + blade * 0.06, -0.04),
					Color("8b985b") if index % 2 == 0 else Color("667b4b"))
		if index % 3 == 0:
			var post := ground + Vector3(0, 0, -2.92)
			wood.box(post + Vector3(0, 0.63, 0), Vector3(0.13, 1.30, 0.13),
				Color("74644a"), Vector3(0, 0, -0.025))
			wood.box(post + Vector3(0, 0.82, 0), Vector3(1.55, 0.10, 0.10),
				Color("b29c70"))
		if index % 4 == 0:
			var tree_at := _terrain_point(x + 1.0, -7.5 - index % 3 * 3.0)
			_tree(wood, foliage, tree_at, 0.8 + float(index % 5) * 0.13)
		if index % 7 == 0:
			var rock_at := _terrain_point(x - 0.3, -4.0)
			stones.ellipsoid(rock_at + Vector3(0, 0.35, 0),
				Vector3(1.0, 0.7, 0.85), Color("9e9279"), 8)
	for sign: Dictionary in Course.SIGNS:
		var x: float = sign["x"]
		var base := Art.world_point(Vector2(x, Course.ground_height(x)), -3.0)
		for offset: float in [-1.08, 1.08]:
			wood.box(base + Vector3(offset, 1.55, 0), Vector3(0.12, 3.10, 0.12),
				Color("756147"))
		details.rounded_box(base + Vector3(0, 3.0, 0),
			Vector3(3.15, 0.92, 0.15), 0.065, Color("2f5146"))
		details.box(base + Vector3(0, 3.0, 0.083),
			Vector3(2.98, 0.76, 0.02), Color("d0c196"))
		details.box(base + Vector3(0, 3.0, 0.101),
			Vector3(2.92, 0.70, 0.015), Color("345a4b"))
		_label(sign["title"], base + Vector3(0, 3.16, 0.13), 48, 0.006, Art.CREAM, false)
		_label(sign["detail"], base + Vector3(0, 2.84, 0.13), 32, 0.0042, Art.CREAM, false)
	_mesh("RoadsideTimber", wood, Art.material(0.96))
	var grass_material := Art.material(0.95)
	grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh("PinesAndShoulderGrass", foliage, grass_material)
	_mesh("ScatteredQuarryStones", stones, Art.material(1.0))
	_mesh("TrailSignBoards", details, Art.material(0.8))


func _tree(wood: Builder, leaves: Builder, at: Vector3, scale_factor: float) -> void:
	wood.cylinder(at + Vector3.UP * 1.75 * scale_factor, 0.11 * scale_factor,
		3.5 * scale_factor, Color("786345"), Vector3.ZERO, 8, 0.62)
	for tier in 4:
		var height := 1.6 * scale_factor
		var center := at + Vector3.UP * (1.5 + tier * 0.63) * scale_factor
		leaves.cylinder(center, (1.22 - tier * 0.22) * scale_factor, height,
			Color("456c53").lightened(tier * 0.026), Vector3(0, tier * 0.43, 0), 9, 0.0)


func _build_water_and_clouds() -> void:
	var water := Builder.new()
	var level := Art.world_point(Vector2(0, 970)).y
	water.quad(Vector3(64, level, 8), Vector3(79, level, 8),
		Vector3(79, level, -24), Vector3(64, level, -24), Color("467d7a"))
	_mesh("QuarryWater", water, Art.material(0.21, 0.25))
	var ripples := Builder.new()
	for index in 8:
		var center := Vector3(66.0 + (index % 3) * 3.7, level + 0.025, -index * 2.9)
		var radius := 0.5 + (index % 4) * 0.32
		ripples.torus(center, radius, radius + 0.017, Color("94b7a6"))
	_ripples = _mesh("QuietWaterRipples", ripples, Art.material(0.5))
	var clouds := Builder.new()
	for index in 8:
		var at := Vector3(-8 + index * 23, 9 + (index % 3) * 1.2, -41 - (index % 2) * 6)
		for lobe in 4:
			clouds.ellipsoid(at + Vector3(lobe * 1.7, sin(lobe * 1.9) * 0.3, 0),
				Vector3(4.3, 1.25 + (lobe % 2) * 0.4, 2.4), Color("e1e4d2"), 12)
	_clouds = _mesh("SlowDriftingClouds", clouds, Art.material(1.0))


func _build_pickups() -> void:
	var parts := Builder.new()
	parts.cylinder(Vector3(0, 0.05, 0), 0.13, 0.48, Art.CREAM, Vector3.ZERO, 16)
	for rib in 5:
		parts.torus(Vector3(0, -0.10 + rib * 0.075, 0), 0.12, 0.16, Art.CREAM)
	parts.cylinder(Vector3(0, -0.24, 0), 0.19, 0.12, Color("b5b5a0"),
		Vector3.ZERO, 6)
	parts.cylinder(Vector3(0, -0.36, 0), 0.085, 0.14, Color("878f84"))
	parts.cylinder(Vector3(0, 0.37, 0), 0.065, 0.16, Color("cacdb9"))
	parts.torus(Vector3.ZERO, 0.55, 0.575, Color("e6c77d"), Vector3(PI / 2, 0, 0))
	var mesh := parts.finish()
	var finish := Art.material(0.4, 0.18)
	for index in Course.PLUG_X.size():
		var root := Node3D.new()
		root.name = "SparkPlug%d" % (index + 1)
		root.position = Art.world_point(Course.plug_position(index))
		add_child(root)
		var model := MeshInstance3D.new()
		model.mesh = mesh
		model.material_override = finish
		root.add_child(model)
		var number := Label3D.new()
		number.text = str(index + 1)
		number.font_size = 54
		number.pixel_size = 0.007
		number.position.y = 0.82
		number.modulate = Art.CREAM
		number.outline_modulate = Art.INK
		number.outline_size = 10
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(number)
		plugs.append(root)


func _build_checkpoints() -> void:
	var posts := Builder.new()
	for index in range(1, Course.CHECKPOINT_X.size()):
		var x := Course.CHECKPOINT_X[index]
		var base := Art.world_point(Vector2(x, Course.ground_height(x)), -2.8)
		posts.cylinder(base + Vector3.UP * 1.85, 0.065, 3.70, Color("665b43"))
		posts.ellipsoid(base + Vector3.UP * 3.72, Vector3.ONE * 0.15, Art.COPPER)
		var fabric := Builder.new()
		fabric.quad(Vector3.ZERO, Vector3(0, -0.70, 0),
			Vector3(1.15, -0.58, 0), Vector3(1.26, 0.10, 0), Color.WHITE)
		var finish := Art.material(0.9)
		finish.albedo_color = Art.CREAM
		finish.cull_mode = BaseMaterial3D.CULL_DISABLED
		var flag := _mesh("Checkpoint%dFlag" % index, fabric, finish)
		flag.position = base + Vector3(0, 3.5, 0)
		_flag_materials.append(finish)
		checkpoint_flags.append(flag)
		var label := _label("CHECKPOINT %d" % index,
			base + Vector3(0.5, 4.08, 0), 42, 0.006, Art.CREAM)
		checkpoint_labels.append(label)
	_mesh("CheckpointMasts", posts, Art.material(0.8))


func _build_garage() -> void:
	var parts := Builder.new()
	var metal := Builder.new()
	var x := (Course.FINISH_X + 100.0) * Art.WORLD_SCALE
	var y := Art.world_point(Vector2(Course.FINISH_X, Course.ground_height(Course.FINISH_X))).y
	var at := Vector3(x, y, -4.9)
	parts.rounded_box(at + Vector3(0, 1.9, -0.4), Vector3(9.0, 3.8, 3.8),
		0.05, Color("517060"))
	for stripe in 23:
		parts.box(at + Vector3(-4.25 + stripe * 0.38, 1.9, 1.52),
			Vector3(0.035, 3.60, 0.04), Color("78907a"))
	parts.rounded_box(at + Vector3(0, 4.10, -0.2), Vector3(9.60, 0.20, 4.4),
		0.06, Color("9b6044"))
	parts.box(at + Vector3(0.7, 1.58, 1.56), Vector3(4.4, 3.0, 0.10), Color("263e38"))
	for slat in 14:
		parts.box(at + Vector3(0.7, 0.2 + slat * 0.21, 1.63),
			Vector3(4.23, 0.17, 0.05), Color("72816c"))
	parts.box(at + Vector3(-3.15, 1.60, 1.58), Vector3(1.0, 2.7, 0.10),
		Color("c2b890"))
	parts.box(at + Vector3(-3.15, 2.16, 1.64), Vector3(0.72, 1.0, 0.04),
		Color("4a6263"))
	metal.cylinder(at + Vector3(-2.86, 1.33, 1.72), 0.055, 0.12,
		Art.CREAM, Vector3(PI / 2, 0, 0))
	parts.rounded_box(at + Vector3(0, 4.57, 0.7), Vector3(6.8, 0.76, 0.15),
		0.065, Art.INK)
	_label("COPPER CREEK / TRAIL SERVICE", at + Vector3(0, 4.58, 0.80),
		44, 0.0058, Art.CREAM, false)
	garage_label = _label("BRING ALL FIVE PLUGS", at + Vector3(0.7, 3.48, 1.73),
		40, 0.0055, Art.CREAM, false)
	for index in 5:
		var light := MeshInstance3D.new()
		light.name = "DeliveredPlug%d" % (index + 1)
		var bulb := SphereMesh.new()
		bulb.radius = 0.10
		bulb.height = 0.20
		light.mesh = bulb
		light.material_override = Art.material(0.35)
		light.position = at + Vector3(-0.4 + index * 0.55, 3.10, 1.8)
		add_child(light)
		_garage_lamps.append(light)
	for side: float in [-1.0, 1.0]:
		var post := Vector3(x + side * 4.30, y, -2.85)
		parts.cylinder(post + Vector3.UP * 0.5, 0.11, 1.0, Art.COPPER, Vector3.ZERO, 10)
		parts.box(Vector3(x + side * 3.4, y + 0.027, 0),
			Vector3(0.075, 0.035, 4.8), Art.CREAM)
	for mark in 12:
		parts.box(Vector3(x - 3.3 + mark * 0.6, y + 0.03, 2.43),
			Vector3(0.58, 0.05, 0.24), Art.CREAM if mark % 2 == 0 else Art.INK)
	for barrel in 3:
		var spot := at + Vector3(5.2 + (barrel % 2) * 0.65, 0.50, 0.6 - barrel * 0.25)
		parts.cylinder(spot, 0.30, 0.95, Color("a16c48"), Vector3.ZERO, 16)
		metal.torus(spot + Vector3.UP * 0.25, 0.295, 0.31, Color("636956"))
		metal.torus(spot - Vector3.UP * 0.25, 0.295, 0.31, Color("636956"))
	_mesh("CopperCreekServiceGarage", parts, Art.material(0.8))
	_mesh("GarageFittings", metal, Art.material(0.55, 0.35))


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
		and state.crash_wait == 0.0 and not state.finished
	_dust.multimesh.visible_instance_count = 14 if active else 0
	if not active:
		return
	var origin := Art.world_point(state.wheel_centers[0])
	for index in 14:
		var age := fposmod(time * 1.6 + index / 14.0, 1.0)
		var at := origin + Vector3(-age * state.velocity.x * 0.003,
			-TIRE_CLEARANCE + age * 0.45, -0.9 if index % 2 == 0 else 0.9)
		var scale_factor := 0.12 + age * 0.55
		_dust.multimesh.set_instance_transform(index,
			Transform3D(Basis.from_scale(Vector3.ONE * scale_factor), at))
		_dust.multimesh.set_instance_color(index, Color(0.75, 0.65, 0.47, (1.0 - age) * 0.28))


func _mesh(title: String, parts: Builder, finish: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = parts.finish()
	instance.material_override = finish
	add_child(instance)
	return instance


func _label(
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
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	label.position = at
	add_child(label)
	return label
