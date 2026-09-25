extends Node3D

## A stalled car waits in the finish garage behind a roll-up door and iron bars.
## Delivering the level's plugs rolls the door up, sinks the bars and wakes it.
## [method pose] depends only on the reveal clock, so skipping, pausing and a
## mid-scene Reduced motion change all land on the same frames.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
## Garage-root coordinates of the imported shop's open bay.
const FLOOR_Y := 0.084
const LINTEL_Y := 2.85
const DOOR_HEIGHT := LINTEL_Y - FLOOR_Y
const DOOR_X := 0.75
const DOOR_Z := 0.47
const DOOR_WIDTH := 4.8
const SLAT_COUNT := 14
const SLAT_PITCH := 0.21
const SIGN_Y := FLOOR_Y + 1.6
const BARS_Z := 0.36
const BAR_COUNT := 15
const BAR_SPAN := Vector2(-1.4, 2.9)
const BAR_HEIGHT := 2.7
const BAR_TIP := 0.12
const RAIL_HEIGHTS: Array[float] = [0.3, 1.45, 2.6]
const CAR_X := 0.7
## Between the lift's arm pads, so the tires never sink into them.
const REAR_AXLE_Z := -3.81
## The reveal camera frames the whole opening, its header and the shop's sign.
const FOCUS := AABB(Vector3(-1.8, 0.0, 0.2), Vector3(6.2, 4.8, 0.9))
const DURATION := 7.4
const REDUCED_DURATION := 4.0
## Door, bars, wake-up and the end, in both timings, so a change keeps its place.
const KEYS: Array[float] = [0.0, 0.6, 3.0, 4.0, DURATION]
const REDUCED_KEYS: Array[float] = [0.0, 0.8, 1.6, 2.4, REDUCED_DURATION]
const CUES := {"door": 0.6, "bars": 3.0, "horn": 4.0}
const REDUCED_CUES := {"door": 0.8, "bars": 1.6, "horn": 2.4}
const DOOR_SECONDS := 2.0
const BARS_SECONDS := 1.0
## Takeoff, airtime and height of each happy hop.
const HOPS: Array[Vector3] = [
	Vector3(4.4, 0.52, 0.5), Vector3(5.3, 0.44, 0.34), Vector3(6.05, 0.36, 0.2),
]
const CROUCH_SECONDS := 0.16
const SETTLE_SECONDS := 0.2
const SQUASH := 0.08
## Spawn time, sideways offset, sideways drift and size of each floating heart.
const HEARTS: Array[Vector4] = [
	Vector4(4.45, -0.35, -0.35, 0.34), Vector4(4.55, 0.25, 0.3, 0.3),
	Vector4(4.7, 0.0, 0.05, 0.38), Vector4(5.3, 0.45, 0.4, 0.3),
	Vector4(5.4, -0.5, -0.3, 0.32), Vector4(5.55, 0.1, 0.1, 0.36),
	Vector4(5.7, -0.2, -0.2, 0.3), Vector4(5.8, 0.3, 0.25, 0.34),
]
const HEART_LIFE := 1.5
## Still hearts for Reduced motion or without intense effects: x, y, z and size.
const RESTING_HEARTS: Array[Vector4] = [
	Vector4(-0.62, 2.08, 0.28, 0.3), Vector4(0.0, 2.34, 0.3, 0.36),
	Vector4(0.62, 2.08, 0.28, 0.3),
]
const DOOR_COLOR := Color("b8b4a4")
const CREASE_COLOR := Color("858173")
const RAIL_COLOR := Color("4c4d48")
const IRON := Color("30383b")
const HEART_PINK := Color("ff6f91")

var car: Cube
var vehicle_id := ""
var door_open := 0.0
var bars_sunk := 0.0
var eyes := 0.0
var hop_height := 0.0
var bay_light := 0.0
var hearts_shown := 0
var sign_label: Label3D
var _state: State
var _rest_y := 0.0
var _center_z := 0.0
var _heart_start := Vector3.ZERO
var _curtain: Node3D
var _shut: MeshInstance3D
var _slats: MultiMeshInstance3D
var _rail: MeshInstance3D
var _plate: MeshInstance3D
var _sign: Node3D
var _bars: MeshInstance3D
var _slot: MeshInstance3D
var _hearts: MultiMeshInstance3D
var _posed := Vector3(-1.0, -1.0, -1.0)


func _init() -> void:
	name = "GarageReveal"
	_build_door()
	_build_bars()
	_build_hearts()
	visible = false


## "" empties the bay and leaves the garage open, exactly as it was before.
func set_captive(id: String, paint := "", rim := "") -> void:
	if id != vehicle_id:
		if car != null:
			remove_child(car)
			car.queue_free()
			car = null
		vehicle_id = id
		if not id.is_empty():
			_park(id)
		_posed = Vector3(-1.0, -1.0, -1.0)
	visible = not id.is_empty()
	if car != null:
		car.set_finish(paint, rim)
	pose(0.0)


static func duration(reduced: bool) -> float:
	return REDUCED_DURATION if reduced else DURATION


static func cue_times(reduced: bool) -> Dictionary:
	return REDUCED_CUES if reduced else CUES


## Maps a moment in one timing onto the matching moment in the other.
static func remap_time(time: float, from_reduced: bool, to_reduced: bool) -> float:
	if from_reduced == to_reduced:
		return time
	var source := REDUCED_KEYS if from_reduced else KEYS
	var target := REDUCED_KEYS if to_reduced else KEYS
	for index in range(1, source.size()):
		if time <= source[index]:
			return lerpf(target[index - 1], target[index],
				inverse_lerp(source[index - 1], source[index], maxf(time, 0.0)))
	return target[-1]


func pose(time: float, reduced := false, intense := true) -> void:
	var key := Vector3(time, float(reduced), float(intense))
	if key == _posed:
		return
	_posed = key
	var cues := cue_times(reduced)
	var wake: float = time - float(cues["horn"])
	if reduced:
		door_open = 1.0 if time >= float(cues["door"]) else 0.0
		bars_sunk = 1.0 if time >= float(cues["bars"]) else 0.0
	else:
		door_open = _ease_in_out(clampf((time - float(cues["door"])) / DOOR_SECONDS, 0.0, 1.0))
		var drop := clampf((time - float(cues["bars"])) / BARS_SECONDS, 0.0, 1.0)
		bars_sunk = drop * drop
	bay_light = 1.4 * door_open
	_pose_door()
	_bars.visible = door_open > 0.0 and bars_sunk < 1.0
	_bars.position.y = -bars_sunk * (BAR_HEIGHT + BAR_TIP + 0.02)
	_slot.visible = door_open > 0.0
	eyes = _eyes(wake, reduced, intense)
	hop_height = 0.0
	if car != null:
		_pose_car(time, wake, reduced, intense)
	_pose_hearts(time, wake, reduced or not intense)


func _pose_door() -> void:
	var lift := door_open * DOOR_HEIGHT
	var moving := door_open > 0.0
	_shut.visible = not moving
	_slats.visible = moving
	_rail.visible = moving
	_plate.visible = moving
	_curtain.position.y = lift
	_curtain.visible = lift < DOOR_HEIGHT - 0.001
	_slats.multimesh.visible_instance_count = mini(SLAT_COUNT,
		ceili((DOOR_HEIGHT - lift) / SLAT_PITCH - 0.001))
	_sign.visible = SIGN_Y - 0.34 + lift < LINTEL_Y


## Two quick blinks, then the headlights stay on: the car is awake.
static func _eyes(wake: float, reduced: bool, intense: bool) -> float:
	if wake < 0.0:
		return 0.0
	if reduced:
		return 1.0
	if not intense:
		return clampf(wake / 0.4, 0.0, 1.0)
	if wake < 0.4:
		return 1.0 if fmod(wake, 0.2) < 0.1 else 0.0
	return smoothstep(0.4, 0.7, wake)


func _pose_car(time: float, wake: float, reduced: bool, intense: bool) -> void:
	# Hidden behind a closed door, the car costs neither draws nor shadows.
	car.visible = door_open > 0.0
	if not car.visible:
		return
	_state.hazards_on = wake >= 0.0
	_state.hazard_time = fposmod(maxf(wake, 0.0), State.HAZARD_PERIOD)
	car.apply_state(_state, false, 0.0, reduced, intense, eyes)
	var dip := 0.0
	var pitch := 0.0
	var roll := 0.0
	var wag := 0.0
	if not reduced:
		for index in HOPS.size():
			var hop := HOPS[index]
			var strength := hop.z / HOPS[0].z
			var air := (time - hop.x) / hop.y
			if air > 0.0 and air < 1.0:
				hop_height += 4.0 * hop.z * air * (1.0 - air)
				pitch += 0.12 * strength * sin(TAU * air) * (1.0 - 0.5 * air)
				roll += 0.035 * strength * sin(PI * air) * (1.0 if index % 2 == 0 else -1.0)
			var crouch := (time - hop.x + CROUCH_SECONDS) / CROUCH_SECONDS
			if crouch > 0.0 and crouch < 1.0:
				dip += SQUASH * strength * sin(PI * crouch)
			var settle := (time - hop.x - hop.y) / SETTLE_SECONDS
			if settle > 0.0 and settle < 1.0:
				dip += SQUASH * strength * sin(PI * settle)
		var happy := clampf((time - 4.2) / 2.8, 0.0, 1.0)
		wag = 0.06 * sin(TAU * (time - 4.2) / 0.9) * sin(PI * happy)
	car.position = Vector3(CAR_X, _rest_y + hop_height, _center_z)
	car.basis = Basis.from_euler(Vector3(roll, -PI * 0.5 + wag, pitch))
	car.chassis.position.y -= dip


func _pose_hearts(time: float, wake: float, resting: bool) -> void:
	var batch := _hearts.multimesh
	var count := 0
	if resting and wake >= 0.0:
		for heart in RESTING_HEARTS:
			batch.set_instance_transform(count, Transform3D(
				Basis.from_scale(Vector3.ONE * heart.w),
				Vector3(CAR_X + heart.x, FLOOR_Y + heart.y, heart.z)))
			count += 1
	elif not resting:
		for index in HEARTS.size():
			var heart := HEARTS[index]
			var along := (time - heart.x) / HEART_LIFE
			if along <= 0.0 or along >= 1.0:
				continue
			var grow := clampf(along / 0.15, 0.0, 1.0) - 1.0
			var size := heart.w * (1.0 + 2.70158 * pow(grow, 3.0) + 1.70158 * grow * grow) \
				* smoothstep(0.0, 0.25, 1.0 - along)
			var sway := sin(TAU * 1.4 * along * HEART_LIFE + index) * 0.06
			batch.set_instance_transform(count, Transform3D(
				Basis.from_scale(Vector3.ONE * maxf(size, 0.001)),
				_heart_start + Vector3(heart.y + heart.z * along + sway,
					1.1 * along + 0.3 * along * along, 2.3 * along)))
			count += 1
	batch.visible_instance_count = count
	_hearts.visible = count > 0
	hearts_shown = count


func _park(id: String) -> void:
	car = Cube.new(id)
	car.name = "CaptiveCar"
	add_child(car)
	car.build()
	_state = State.new(id)
	_state.advance(1.5, 0.0, 0.0, 0.0)
	car.apply_state(_state)
	_rest_y = FLOOR_Y - car.axles[0].position.y + car.vehicle.wheel_radius * Art.WORLD_SCALE
	_center_z = REAR_AXLE_Z - car.axles[0].position.x
	car.position = Vector3.ZERO
	car.basis = Basis.IDENTITY
	var bounds := car.local_bounds()
	_heart_start = Vector3(CAR_X, _rest_y + bounds.end.y * 0.85 + 0.2,
		_center_z + bounds.end.x - 0.55)
	sign_label.text = "%s\nWAITING FOR SPARK PLUGS" % car.vehicle.title.to_upper()


func _build_door() -> void:
	_curtain = Node3D.new()
	_curtain.name = "RollUpDoor"
	add_child(_curtain)
	var finish := Art.material(0.6, 0.25)
	# Drivers pass a shut door all level, so it is a single mesh. The building
	# already shades everything it could, so it casts no shadow either.
	var shut := Builder.new()
	for index in SLAT_COUNT:
		_add_slat(shut, _slat_position(index))
	_add_rail(shut)
	_add_plate(shut)
	_shut = _mesh("ClosedDoor", shut, finish, _curtain)
	_shut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var slat := Builder.new()
	_add_slat(slat, Vector3.ZERO)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = slat.finish()
	batch.instance_count = SLAT_COUNT
	for index in SLAT_COUNT:
		batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, _slat_position(index)))
	_slats = MultiMeshInstance3D.new()
	_slats.name = "DoorSlats"
	_slats.multimesh = batch
	_slats.material_override = finish
	_curtain.add_child(_slats)
	var rail := Builder.new()
	_add_rail(rail)
	_rail = _mesh("DoorRail", rail, finish, _curtain)
	_sign = Node3D.new()
	_sign.name = "DoorSign"
	_curtain.add_child(_sign)
	var plate := Builder.new()
	_add_plate(plate)
	_plate = _mesh("SignPlate", plate, finish, _sign)
	sign_label = Label3D.new()
	sign_label.name = "SignLabel"
	sign_label.font_size = 40
	sign_label.pixel_size = 0.0048
	sign_label.modulate = Art.CREAM
	sign_label.outline_size = 0
	sign_label.position = Vector3(DOOR_X, SIGN_Y, DOOR_Z + 0.04)
	_sign.add_child(sign_label)


static func _slat_position(index: int) -> Vector3:
	return Vector3(DOOR_X, FLOOR_Y + (index + 0.5) * SLAT_PITCH, DOOR_Z)


static func _add_slat(parts: Builder, at: Vector3) -> void:
	parts.box(at, Vector3(DOOR_WIDTH, SLAT_PITCH, 0.035), DOOR_COLOR)
	parts.box(at + Vector3(0, -SLAT_PITCH * 0.5 + 0.018, 0.01), Vector3(DOOR_WIDTH, 0.03, 0.03),
		CREASE_COLOR)


## The bottom rail and its handle.
static func _add_rail(parts: Builder) -> void:
	parts.box(Vector3(DOOR_X, FLOOR_Y + 0.04, DOOR_Z + 0.012), Vector3(DOOR_WIDTH, 0.08, 0.06),
		RAIL_COLOR)
	parts.box(Vector3(DOOR_X, FLOOR_Y + 0.46, DOOR_Z + 0.035), Vector3(0.46, 0.07, 0.05),
		RAIL_COLOR)


static func _add_plate(parts: Builder) -> void:
	parts.box(Vector3(DOOR_X, SIGN_Y, DOOR_Z + 0.028), Vector3(2.95, 0.66, 0.02), Art.INK)


func _build_bars() -> void:
	var slot := Builder.new()
	slot.box(Vector3(DOOR_X, FLOOR_Y + 0.002, BARS_Z),
		Vector3(BAR_SPAN.y - BAR_SPAN.x + 0.24, 0.004, 0.12), Color("1b2224"))
	_slot = _mesh("BarSlot", slot, Art.material(0.9), self)
	var iron := Builder.new()
	for index in BAR_COUNT:
		var x := lerpf(BAR_SPAN.x, BAR_SPAN.y, float(index) / (BAR_COUNT - 1))
		iron.cylinder(Vector3(x, FLOOR_Y + BAR_HEIGHT * 0.5, BARS_Z), 0.035, BAR_HEIGHT, IRON,
			Vector3.ZERO, 8)
		iron.cylinder(Vector3(x, FLOOR_Y + BAR_HEIGHT + BAR_TIP * 0.5, BARS_Z), 0.055, BAR_TIP,
			IRON, Vector3.ZERO, 8, 0.0)
	for height in RAIL_HEIGHTS:
		iron.box(Vector3(DOOR_X, FLOOR_Y + height, BARS_Z),
			Vector3(BAR_SPAN.y - BAR_SPAN.x + 0.16, 0.07, 0.05), IRON)
	_bars = _mesh("IronBars", iron, Art.material(0.45, 0.55), self)


func _build_hearts() -> void:
	var fill := PackedVector2Array()
	for step in 36:
		var angle := TAU * step / 36.0
		fill.append(Vector2(16.0 * pow(sin(angle), 3.0), 13.0 * cos(angle)
			- 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle) + 2.5) / 32.0)
	var outline := PackedVector2Array()
	for point in fill:
		outline.append(point * 1.2)
	var heart := Builder.new()
	heart.extrude(outline, 0.03, Art.INK)
	heart.extrude(fill, 0.05, HEART_PINK)
	var finish := StandardMaterial3D.new()
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	finish.vertex_color_use_as_albedo = true
	finish.vertex_color_is_srgb = true
	finish.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	finish.billboard_keep_scale = true
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = heart.finish()
	batch.instance_count = HEARTS.size()
	batch.visible_instance_count = 0
	_hearts = MultiMeshInstance3D.new()
	_hearts.name = "HappyHearts"
	_hearts.multimesh = batch
	_hearts.material_override = finish
	_hearts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hearts.extra_cull_margin = 2.0
	_hearts.visible = false
	add_child(_hearts)


func _mesh(title: String, parts: Builder, finish: Material, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = parts.finish()
	instance.material_override = finish
	parent.add_child(instance)
	return instance


static func _ease_in_out(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
