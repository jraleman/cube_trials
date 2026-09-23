extends RefCounted

## Fixed-step sprung chassis and run rules, independent of nodes and autoloads.

const Course = preload("res://games/cube_trials/course.gd")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
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
const GOLD_SECONDS := 65.0
const SILVER_SECONDS := 95.0
const FINISH_BONUS := 3000
const POINTS_PER_SECOND := 30.0
const PARK_SPEED := 120.0
const DAMAGE_NAMES := ["Pristine", "Scuffed", "Dented", "Crumpled", "Battered"]
const MAX_DAMAGE_STAGE := 4
const HARD_LANDING_SPEED := 850.0
const DAMAGE_AIR_TIME := 0.12
const DAMAGE_SETTLE_TIME := 0.20
const JUMP_SPEED := 680.0
const JUMP_BUFFER_SECONDS := 0.12
const JUMP_COYOTE_SECONDS := 0.08
const JUMP_RECHARGE_SECONDS := 0.18
const AIR_TORQUE := 72000.0
const AIR_SPIN_LIMIT := 8.0
const FLIP_POINTS := 500
const FLIP_LANDING_SECONDS := 0.12
const MIN_SCORING_AIR_TIME := 0.20
const AIR_POINTS_PER_SECOND := 80.0
const SPEED_POINTS_PER_SECOND := 120.0
const ANGLE_POINTS_PER_SECOND := 100.0
const SCORING_SPEED := 650.0
const HAZARD_MULTIPLIER := 1.15
const HAZARD_PERIOD := 0.8

var position := Vector2.ZERO
var vehicle: Profiles
var course: Course
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
var landed_flips := 0
var flip_points := 0
var pending_flips := 0
var landed_jumps := 0
var jump_points := 0
var hazard_points := 0
var hazards_on := false
var hazard_time := 0.0
var hazard_bonus := false
var _air_time := 0.0
var _trick_air_time := 0.0
var _air_points := 0.0
var _scoring_flight := false
var _flip_rotation := 0.0
var _flip_landing_time := 0.0
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


func _init(vehicle_id := Profiles.CUBE, level_id := Course.COPPER) -> void:
	vehicle = Profiles.new(vehicle_id)
	course = Course.new(level_id)
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
		if hazards_on:
			hazard_time = fposmod(hazard_time + STEP, HAZARD_PERIOD)
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


## Switching on in flight qualifies this attempt once; leaving them on never chains bonuses.
func toggle_hazards() -> void:
	if is_over() or crash_wait > 0.0:
		return
	hazards_on = not hazards_on
	hazard_time = 0.0
	if hazards_on and is_airborne() and _trick_air_time > 0.0:
		hazard_bonus = true
	_events.append({
		"kind": "hazards",
		"text": "Hazards on. Land to bank a %.2fx jump bonus." % HAZARD_MULTIPLIER
			if hazards_on and hazard_bonus else "Hazards on. Switch on in mid-air for a jump bonus."
			if hazards_on else "Hazards off.",
	})


## Manual and automatic recoveries share one cost; a crash cannot be charged twice.
func recover() -> void:
	if is_over() or crash_wait > 0.0:
		return
	started = true
	recoveries += 1
	_respawn()
	_events.append({
		"kind": "recover",
		"text": "Recovered. +5 seconds; plugs and banked points kept. Unlanded tricks lost.",
	})


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


func pending_flip_points() -> int:
	return pending_flips * FLIP_POINTS


func pending_jump_points() -> int:
	return roundi(_air_points) if _scoring_flight else 0


func jump_multiplier() -> float:
	return HAZARD_MULTIPLIER if hazard_bonus else 1.0


func pending_trick_points() -> int:
	return roundi((pending_flip_points() + pending_jump_points()) * jump_multiplier())


## Only landed tricks count; an unfinished run keeps cargo and banked trick points.
func score() -> int:
	var result := plug_count() * 1000 + flip_points + jump_points + hazard_points
	if finished:
		result += maxi(0, FINISH_BONUS - ceili(adjusted_time() * POINTS_PER_SECOND))
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
		var arm := vehicle.axles[index].rotated(angle)
		var anchor := position + arm
		var hit := course.wheel_contact(anchor, down, MAX_LENGTH, vehicle.wheel_radius)
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
		wheel_angles[index] += speed / vehicle.wheel_radius * STEP
		if length < Tuning.MIN_LENGTH:
			position += normal * (Tuning.MIN_LENGTH - length) * 0.5
			var inward := velocity.dot(normal)
			if inward < 0.0:
				velocity -= normal * inward * 0.55
	var wheel_contact := contacts > 0
	if _try_jump():
		force = Vector2(-velocity.x * 0.18, Tuning.GRAVITY)
		torque = -angular_velocity * INERTIA * 1.2
	if contacts == 0:
		# Small corrections and brief suspension hops keep their original precision.
		var trick_control := _air_time >= 0.12
		var strength := smoothstep(0.75, 1.0, absf(tilt)) if trick_control else 0.0
		var slowing_trick := absf(_flip_rotation) > PI * 0.5 or pending_flips > 0
		var damping := 6.0 if slowing_trick and absf(tilt) < 0.05 else 1.2
		torque = -angular_velocity * INERTIA * damping
		torque += tilt * air_control * lerpf(32000.0, AIR_TORQUE, strength)
	else:
		torque += tilt * air_control * (32000.0 if contacts < 2 else 14000.0)
	velocity += force * STEP
	velocity.x = clampf(velocity.x, -400.0, 650.0)
	velocity.y = clampf(velocity.y, -1100.0, 1200.0)
	var spin_limit := AIR_SPIN_LIMIT if contacts == 0 else 5.0
	angular_velocity = clampf(angular_velocity + torque / INERTIA * STEP, -spin_limit, spin_limit)
	position += velocity * STEP
	var rotation_step := angular_velocity * STEP
	angle = wrapf(angle + rotation_step, -PI, PI)
	if contacts == 0 and started:
		_air_time += STEP
		longest_air = maxf(longest_air, _air_time)
	else:
		_air_time = 0.0
	if position.x < 0.0:
		position.x = 0.0
		velocity.x = maxf(0.0, velocity.x)
	if position.y > course.fall_y or position.x > course.end_x:
		_crash("Off the trail.")
		return
	for corner in vehicle.roof:
		var point := position + corner.rotated(angle)
		if point.y > course.ground_height(point.x) - 2.0:
			_crash("Roof hit the trail.")
			return
	for corner in vehicle.body_contacts:
		var arm: Vector2 = corner.rotated(angle)
		var point := position + arm
		var penetration := point.y - course.ground_height(point.x)
		if penetration <= 0.0:
			continue
		body_contact = true
		var normal := course.ground_normal(point.x)
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
	_update_tricks(rotation_step, body_contact)


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
	_events.append({"kind": "jump", "text": "Jump! Hold tilt to flip, release to slow the spin."})
	return true


func _update_tricks(rotation_step: float, body_contact: bool) -> void:
	if contacts == 0 and not body_contact and started:
		_flip_landing_time = 0.0
		_trick_air_time += STEP
		_scoring_flight = _scoring_flight or _trick_air_time + 0.0000001 >= MIN_SCORING_AIR_TIME
		var speed_factor := clampf(absf(velocity.x) / SCORING_SPEED, 0.0, 1.0)
		var angle_factor := absf(angle) / PI
		_air_points += STEP * (AIR_POINTS_PER_SECOND
			+ SPEED_POINTS_PER_SECOND * speed_factor + ANGLE_POINTS_PER_SECOND * angle_factor)
		# Signed, unwrapped travel rejects angle wrapping and back-and-forth rocking.
		_flip_rotation += rotation_step
		if absf(_flip_rotation) >= TAU:
			var direction := signf(_flip_rotation)
			_flip_rotation -= direction * TAU
			pending_flips += 1
			_events.append({
				"kind": "flip",
				"text": "%s! Land on both wheels to bank %d points." % [
					"Frontflip" if direction > 0.0 else "Backflip", pending_trick_points(),
				],
			})
		return
	_trick_air_time = 0.0
	_flip_rotation = 0.0
	if pending_trick_points() == 0:
		_clear_trick_attempt()
		return
	if contacts < 2 or body_contact or absf(angle) >= 0.9 or absf(angular_velocity) > 1.5:
		_flip_landing_time = 0.0
		return
	_flip_landing_time += STEP
	if _flip_landing_time + 0.0000001 < FLIP_LANDING_SECONDS:
		return
	var points := pending_trick_points()
	var flips := pending_flip_points()
	var air := pending_jump_points()
	landed_jumps += 1
	landed_flips += pending_flips
	flip_points += flips
	jump_points += air
	hazard_points += points - flips - air
	var trick := "%d flip%s" % [pending_flips, "" if pending_flips == 1 else "s"] \
		if pending_flips > 0 else "Jump"
	_events.append({
		"kind": "trick",
		"text": "%s landed! +%d%s" % [trick, points,
			" / hazards %.2fx" % HAZARD_MULTIPLIER if hazard_bonus else ""],
	})
	_clear_trick_attempt()


func _clear_trick_attempt() -> void:
	pending_flips = 0
	_flip_rotation = 0.0
	_flip_landing_time = 0.0
	_trick_air_time = 0.0
	_air_points = 0.0
	_scoring_flight = false
	hazard_bonus = false


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
		if not collected[index] and position.distance_to(course.plug_position(index)) < 87.0:
			collected[index] = true
			_events.append({
				"kind": "plug", "text": "Spark plug %d collected. %d / 5 aboard." % [
					index + 1, plug_count(),
				],
			})
	for index in range(checkpoint + 1, course.checkpoint_x.size()):
		if position.distance_to(course.spawn_position(index)) > 110.0 or contacts == 0:
			continue
		var ready := true
		for plug in collected.size():
			if course.plug_x[plug] < course.checkpoint_x[index] and not collected[plug]:
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
	var at_garage := position.x >= course.finish_x \
		and position.x <= course.finish_x + course.finish_width
	if not at_garage:
		_gate_notified = false
		return
	if plug_count() == collected.size() and contacts > 0 and pending_trick_points() == 0 \
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
	_clear_trick_attempt()
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
	position = course.spawn_position(checkpoint)
	position.y += Tuning.RIDE_HEIGHT - vehicle.ride_height
	velocity = Vector2.ZERO
	angle = 0.0
	angular_velocity = 0.0
	contacts = 0
	crash_wait = 0.0
	_air_time = 0.0
	_clear_trick_attempt()
	_damage_air_time = 0.0
	_damage_ground_time = 0.0
	_landing_ready = true
	_landing_armed = false
	_jump_buffer = 0.0
	_jump_grace = 0.0
	_jump_recharge = 0.0
	_gate_notified = false
	for index in 2:
		wheel_centers[index] = position + vehicle.axles[index] + Vector2.DOWN * Tuning.STATIC_LENGTH
		wheel_angles[index] = 0.0
