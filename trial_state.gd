extends RefCounted

## Fixed-step sprung chassis and run rules, independent of nodes and autoloads.

const Course = preload("res://games/cube_trials/course.gd")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const STEP := 1.0 / 120.0
const WHEEL_RADIUS := Tuning.WHEEL_RADIUS
const REST_LENGTH := Tuning.REST_LENGTH
const MAX_LENGTH := Tuning.MAX_LENGTH
const AXLES: Array[Vector2] = Tuning.AXLES
const ROOF: Array[Vector2] = Tuning.ROOF
const INERTIA := 3000.0
const RECOVERY_PENALTY := 5.0
const STARTING_LIVES := 5
const CRASH_DELAY := 0.85
const GOLD_SECONDS := 45.0
const SILVER_SECONDS := 70.0
const PARK_SPEED := 120.0
const DAMAGE_NAMES := ["Pristine", "Scuffed", "Dented", "Crumpled", "Battered"]
const MAX_DAMAGE_STAGE := 4
const HARD_LANDING_SPEED := 700.0
const DAMAGE_AIR_TIME := 0.12
const DAMAGE_SETTLE_TIME := 0.20
const JUMP_SPEED := 500.0
const JUMP_BUFFER_SECONDS := 0.12
const JUMP_COYOTE_SECONDS := 0.08
const JUMP_RECHARGE_SECONDS := 0.18

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
var lives_left := STARTING_LIVES
var damage_stage := 0
var elapsed := 0.0
var started := false
var finished := false
var failed := false
var crash_wait := 0.0
var air_control := 1.0
var longest_air := 0.0
var _air_time := 0.0
var _accumulator := 0.0
var _events: Array[Dictionary] = []
var _gate_notified := false
var _blocked_checkpoint := -1
var _damage_air_time := 0.0
var _damage_ground_time := 0.0
var _landing_ready := true
var _landing_armed := false
var _jump_held := false
var _jump_buffer := 0.0
var _jump_grace := 0.0
var _jump_recharge := 0.0


func _init() -> void:
	_respawn()


## Identical controls produce the same suspension at 30, 60 or 144 render FPS.
func advance(delta: float, drive: float, brake: float, tilt: float, jump := false) -> void:
	if not is_finite(delta) or delta < 0.0:
		push_error("Cube Trials requires a finite, nonnegative frame duration.")
		return
	if is_over():
		return
	drive = clampf(drive, -1.0, 1.0)
	brake = clampf(brake, 0.0, 1.0)
	tilt = clampf(tilt, -1.0, 1.0)
	if jump and not _jump_held and crash_wait == 0.0:
		_jump_buffer = JUMP_BUFFER_SECONDS
		started = true
	_jump_held = jump
	if absf(drive) > 0.01 or absf(tilt) > 0.01:
		started = true
	_accumulator += delta
	while _accumulator + 0.0000001 >= STEP and not is_over():
		_accumulator -= STEP
		if started:
			elapsed += STEP
		if crash_wait > 0.0:
			crash_wait = maxf(0.0, crash_wait - STEP)
			if crash_wait == 0.0:
				if lives_left == 0:
					failed = true
					_events.append({"kind": "out", "text": "Out of lives. Try again."})
				else:
					_respawn()
			continue
		_simulate(drive, brake, tilt)
		if crash_wait == 0.0:
			_update_course()


## Menus and recovery discard queued presses and require held jump inputs to release.
func clear_jump_input() -> void:
	_jump_buffer = 0.0
	_jump_held = true


## Manual and automatic recoveries share one cost; a crash cannot be charged twice.
func recover() -> void:
	if is_over() or crash_wait > 0.0:
		return
	started = true
	recoveries += 1
	_respawn()
	_events.append({"kind": "recover", "text": "Recovered. +5 seconds; collected plugs kept."})


func is_over() -> bool:
	return finished or failed


## Contact history distinguishes real flight from a respawn awaiting its first step.
func is_airborne() -> bool:
	return started and contacts == 0 and _air_time > 0.0 \
		and crash_wait == 0.0 and not is_over()


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
	var force := Vector2(-velocity.x * 0.18, Tuning.GRAVITY)
	var torque := -angular_velocity * INERTIA * 1.2
	var impact_speed := 0.0
	var body_contact := false
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
		impact_speed = maxf(impact_speed, -point_velocity.dot(normal))
		var compression := REST_LENGTH - length
		var support := clampf(
			compression * Tuning.SPRING_STIFFNESS
			- point_velocity.dot(normal) * Tuning.SPRING_DAMPING, 0.0, 5200.0
		)
		var spring := normal * support
		var speed := point_velocity.dot(tangent)
		var traction := tangent * clampf(
			drive * 390.0 - speed * (0.55 + brake * 20.0),
			-support * 1.8, support * 1.8
		)
		force += spring + traction
		torque += arm.cross(spring) + arm.cross(traction) * 0.35
		wheel_angles[index] += speed / WHEEL_RADIUS * STEP
		if length < Tuning.MIN_LENGTH:
			position += normal * (Tuning.MIN_LENGTH - length) * 0.5
			var inward := velocity.dot(normal)
			if inward < 0.0:
				velocity -= normal * inward * 0.55
	var wheel_contact := contacts > 0
	if _try_jump():
		force = Vector2(-velocity.x * 0.18, Tuning.GRAVITY)
		torque = -angular_velocity * INERTIA * 1.2
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
	for corner in Tuning.BODY_CONTACTS:
		var arm: Vector2 = corner.rotated(angle)
		var point := position + arm
		var penetration := point.y - Course.ground_height(point.x)
		if penetration <= 0.0:
			continue
		body_contact = true
		var normal := Course.ground_normal(point.x)
		position += normal * penetration / maxf(-normal.y, 0.1)
		var point_velocity := velocity + Vector2(-arm.y, arm.x) * angular_velocity
		var inward := point_velocity.dot(normal)
		impact_speed = maxf(impact_speed, -inward)
		if inward < 0.0:
			var leverage := arm.cross(normal)
			var impulse := -inward / (1.0 + leverage * leverage / INERTIA)
			velocity += normal * impulse
			angular_velocity += leverage * impulse / INERTIA
	_update_landing_damage(wheel_contact or body_contact, impact_speed)


func _try_jump() -> bool:
	_jump_recharge = maxf(0.0, _jump_recharge - STEP)
	_jump_grace = maxf(0.0, _jump_grace - STEP)
	if contacts > 0 and absf(angle) < 0.9 and _jump_recharge == 0.0:
		_jump_grace = JUMP_COYOTE_SECONDS
	var ready := _jump_buffer > 0.0 and _jump_grace > 0.0 \
		and _jump_recharge == 0.0 and absf(angle) < 0.9
	_jump_buffer = maxf(0.0, _jump_buffer - STEP)
	if not ready:
		return false
	velocity.y = minf(velocity.y, -JUMP_SPEED)
	contacts = 0
	_jump_buffer = 0.0
	_jump_grace = 0.0
	_jump_recharge = JUMP_RECHARGE_SECONDS
	_events.append({"kind": "jump", "text": "Jump! Tilt to level the landing."})
	return true


func _update_landing_damage(grounded: bool, impact_speed: float) -> void:
	if not grounded:
		_damage_ground_time = 0.0
		_damage_air_time += STEP
		if _landing_ready and _damage_air_time >= DAMAGE_AIR_TIME:
			_landing_armed = true
			_landing_ready = false
		return
	_damage_air_time = 0.0
	_damage_ground_time += STEP
	if _landing_armed and impact_speed >= HARD_LANDING_SPEED:
		_landing_armed = false
		_add_damage()
		_events.append({
			"kind": "damage", "text": "Hard landing. Bodywork: %s. No life lost."
				% DAMAGE_NAMES[damage_stage].to_lower(),
		})
	# A second wheel strike or suspension bounce belongs to this same landing.
	if _damage_ground_time >= DAMAGE_SETTLE_TIME:
		_landing_ready = true
		_landing_armed = false


func _add_damage() -> void:
	damage_stage = mini(damage_stage + 1, MAX_DAMAGE_STAGE)


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
	if is_over() or crash_wait > 0.0:
		return
	started = true
	lives_left -= 1
	if lives_left > 0:
		recoveries += 1
	_add_damage()
	_jump_buffer = 0.0
	_jump_grace = 0.0
	crash_wait = CRASH_DELAY
	velocity = Vector2.ZERO
	angular_velocity = 0.0
	_events.append({
		"kind": "crash",
		"text": "%s One life lost. %s" % [reason,
			"%d lives left. Recovering at checkpoint %d. +5 seconds." % [lives_left, checkpoint]
			if lives_left > 0 else "No lives left."],
	})


func _respawn() -> void:
	position = Course.spawn_position(checkpoint)
	velocity = Vector2.ZERO
	angle = 0.0
	angular_velocity = 0.0
	contacts = 0
	crash_wait = 0.0
	_air_time = 0.0
	_damage_air_time = 0.0
	_damage_ground_time = 0.0
	_landing_ready = true
	_landing_armed = false
	_jump_buffer = 0.0
	_jump_grace = 0.0
	_jump_recharge = 0.0
	_gate_notified = false
	for index in 2:
		wheel_centers[index] = position + AXLES[index] + Vector2.DOWN * Tuning.STATIC_LENGTH
		wheel_angles[index] = 0.0
