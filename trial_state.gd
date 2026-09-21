extends RefCounted

## Fixed-step sprung chassis and run rules, independent of nodes and autoloads.

const Course = preload("res://games/cube_trials/course.gd")
const STEP := 1.0 / 120.0
const WHEEL_RADIUS := 23.0
const REST_LENGTH := 44.0
const MAX_LENGTH := 61.0
const AXLES: Array[Vector2] = [Vector2(-53, 14), Vector2(53, 14)]
const ROOF: Array[Vector2] = [Vector2(-64, -57), Vector2(0, -62), Vector2(58, -55)]
const INERTIA := 3000.0
const RECOVERY_PENALTY := 5.0
const GOLD_SECONDS := 45.0
const SILVER_SECONDS := 70.0
const PARK_SPEED := 120.0

var position := Vector2.ZERO
var velocity := Vector2.ZERO
var angle := 0.0
var angular_velocity := 0.0
var wheel_centers: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var wheel_angles: Array[float] = [0.0, 0.0]
var contacts := 0
var collected: Array[bool] = [false, false, false, false, false]
var checkpoint := 0
var recoveries := 0
var elapsed := 0.0
var started := false
var finished := false
var crash_wait := 0.0
var air_control := 1.0
var longest_air := 0.0
var _air_time := 0.0
var _accumulator := 0.0
var _events: Array[Dictionary] = []
var _gate_notified := false
var _blocked_checkpoint := -1


func _init() -> void:
	_respawn()


## Identical controls produce the same suspension at 30, 60 or 144 render FPS.
func advance(delta: float, drive: float, brake: float, tilt: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		push_error("Cube Trials requires a finite, nonnegative frame duration.")
		return
	if finished:
		return
	drive = clampf(drive, -1.0, 1.0)
	brake = clampf(brake, 0.0, 1.0)
	tilt = clampf(tilt, -1.0, 1.0)
	if absf(drive) > 0.01 or absf(tilt) > 0.01:
		started = true
	_accumulator += delta
	while _accumulator + 0.0000001 >= STEP and not finished:
		_accumulator -= STEP
		if started:
			elapsed += STEP
		if crash_wait > 0.0:
			crash_wait = maxf(0.0, crash_wait - STEP)
			if crash_wait == 0.0:
				_respawn()
			continue
		_simulate(drive, brake, tilt)
		if crash_wait == 0.0:
			_update_course()


## Manual and automatic recoveries share one cost; a crash cannot be charged twice.
func recover() -> void:
	if finished or crash_wait > 0.0:
		return
	started = true
	recoveries += 1
	_respawn()
	_events.append({"kind": "recover", "text": "Recovered. +5 seconds; collected plugs kept."})


## Event consumption keeps audiovisual feedback out of the deterministic simulation.
func take_events() -> Array[Dictionary]:
	var result := _events
	_events = []
	return result


## Counts unique pickups, including those retained through a recovery.
func plug_count() -> int:
	return collected.count(true)


## The clock never counts menus or pauses; each recovery adds an explicit penalty.
func adjusted_time() -> float:
	return elapsed + recoveries * RECOVERY_PENALTY


## Points reward completion first, then a quicker run; no completion bonus on abandonment.
func score() -> int:
	var result := plug_count() * 1000
	if finished:
		result += maxi(0, 3000 - ceili(adjusted_time() * 40.0))
	return result


## Assists do not disable medals or achievements.
func medal() -> String:
	if not finished:
		return "UNFINISHED"
	if adjusted_time() <= GOLD_SECONDS:
		return "GOLD"
	return "SILVER" if adjusted_time() <= SILVER_SECONDS else "BRONZE"


## Shared formatting keeps the live timer and results honest to hundredths.
static func time_text(seconds: float) -> String:
	var hundredths := maxi(0, floori(seconds * 100.0 + 0.00001))
	return "%02d:%02d.%02d" % [
		hundredths / 6000, (hundredths / 100) % 60, hundredths % 100,
	]


func _simulate(drive: float, brake: float, tilt: float) -> void:
	var down := Vector2.DOWN.rotated(angle)
	var force := Vector2(-velocity.x * 0.18, 980.0)
	var torque := -angular_velocity * INERTIA * 1.2
	contacts = 0
	for index in 2:
		var arm := AXLES[index].rotated(angle)
		var anchor := position + arm
		var hit := Course.wheel_contact(anchor, down, MAX_LENGTH, WHEEL_RADIUS)
		wheel_centers[index] = anchor + down * MAX_LENGTH
		if hit.is_empty():
			wheel_angles[index] += drive * 12.0 * STEP
			continue
		var length: float = hit["length"]
		wheel_centers[index] = hit["point"]
		if length > REST_LENGTH:
			continue
		contacts += 1
		var normal: Vector2 = hit["normal"]
		var tangent := Vector2(-normal.y, normal.x)
		var point_velocity := velocity + Vector2(-arm.y, arm.x) * angular_velocity
		var compression := REST_LENGTH - length
		var support := clampf(compression * 88.0 - point_velocity.dot(normal) * 9.0,
			0.0, 5200.0)
		var spring := normal * support
		var speed := point_velocity.dot(tangent)
		var traction := tangent * clampf(
			drive * 390.0 - speed * (0.55 + brake * 20.0),
			-support * 1.8, support * 1.8
		)
		force += spring + traction
		torque += arm.cross(spring) + arm.cross(traction) * 0.35
		wheel_angles[index] += speed / WHEEL_RADIUS * STEP
		if length < 4.0:
			position += normal * (4.0 - length) * 0.5
			var inward := velocity.dot(normal)
			if inward < 0.0:
				velocity -= normal * inward * 0.55
	torque += tilt * air_control * (32000.0 if contacts < 2 else 14000.0)
	velocity += force * STEP
	velocity.x = clampf(velocity.x, -400.0, 650.0)
	velocity.y = clampf(velocity.y, -1100.0, 1200.0)
	angular_velocity = clampf(angular_velocity + torque / INERTIA * STEP, -5.0, 5.0)
	position += velocity * STEP
	angle = wrapf(angle + angular_velocity * STEP, -PI, PI)
	if contacts == 0 and started:
		_air_time += STEP
		longest_air = maxf(longest_air, _air_time)
	else:
		_air_time = 0.0
	if position.x < 0.0:
		position.x = 0.0
		velocity.x = maxf(0.0, velocity.x)
	if position.y > Course.FALL_Y or position.x > Course.END_X:
		_crash("Off the trail.")
		return
	for corner in ROOF:
		var point := position + corner.rotated(angle)
		if point.y > Course.ground_height(point.x) - 2.0:
			_crash("Roof hit the trail.")
			return
	for corner in [Vector2(-73, 15), Vector2(76, 15)]:
		var arm: Vector2 = corner.rotated(angle)
		var point := position + arm
		var penetration := point.y - Course.ground_height(point.x)
		if penetration <= 0.0:
			continue
		var normal := Course.ground_normal(point.x)
		position += normal * penetration / maxf(-normal.y, 0.1)
		var point_velocity := velocity + Vector2(-arm.y, arm.x) * angular_velocity
		var inward := point_velocity.dot(normal)
		if inward < 0.0:
			var leverage := arm.cross(normal)
			var impulse := -inward / (1.0 + leverage * leverage / INERTIA)
			velocity += normal * impulse
			angular_velocity += leverage * impulse / INERTIA


func _update_course() -> void:
	for index in collected.size():
		if not collected[index] and position.distance_to(Course.plug_position(index)) < 87.0:
			collected[index] = true
			_events.append({
				"kind": "plug", "text": "Spark plug %d collected. %d / 5 aboard." % [
					index + 1, plug_count(),
				],
			})
	for index in range(checkpoint + 1, Course.CHECKPOINT_X.size()):
		if position.distance_to(Course.spawn_position(index)) > 110.0 or contacts == 0:
			continue
		var ready := true
		for plug in collected.size():
			if Course.PLUG_X[plug] < Course.CHECKPOINT_X[index] and not collected[plug]:
				ready = false
		if ready:
			checkpoint = index
			_events.append({"kind": "checkpoint", "text": "Checkpoint %d saved." % index})
		elif _blocked_checkpoint != index:
			_blocked_checkpoint = index
			_events.append({
				"kind": "notice",
				"text": "Checkpoint needs the earlier plugs. Reverse or recover to find them.",
			})
	var at_garage := position.x >= Course.FINISH_X \
		and position.x <= Course.FINISH_X + Course.FINISH_WIDTH
	if not at_garage:
		_gate_notified = false
		return
	if plug_count() == collected.size() and contacts > 0 \
		and absf(velocity.x) < PARK_SPEED and absf(angle) < 0.6:
		finished = true
		_events.append({"kind": "finish", "text": "Home in one piece. Course complete!"})
	elif not _gate_notified:
		_gate_notified = true
		_events.append({
			"kind": "notice",
			"text": "Brake inside the garage to finish." if plug_count() == 5
				else "The garage needs all five spark plugs. Reverse or recover for the rest.",
		})


func _crash(reason: String) -> void:
	started = true
	recoveries += 1
	crash_wait = 0.85
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	_events.append({
		"kind": "crash", "text": "%s Recovering at checkpoint %d. +5 seconds." % [
			reason, checkpoint,
		],
	})


func _respawn() -> void:
	position = Course.spawn_position(checkpoint)
	velocity = Vector2.ZERO
	angle = 0.0
	angular_velocity = 0.0
	contacts = 0
	crash_wait = 0.0
	_air_time = 0.0
	_gate_notified = false
	for index in 2:
		wheel_centers[index] = position + AXLES[index] + Vector2.DOWN * REST_LENGTH
		wheel_angles[index] = 0.0
