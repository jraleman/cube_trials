extends SceneTree

## Node-free checks for suspension, fair recovery and a physically drivable course.

const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_suspension_and_controls()
	_test_fixed_step()
	_test_pickups_and_checkpoints()
	_test_crash_and_recovery()
	_test_finish_rules()
	_test_complete_course()
	_test_assisted_recovery_runs()
	if _failures.is_empty():
		print("Cube Trials physics and course tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_suspension_and_controls() -> void:
	var state := State.new()
	for frame in 600:
		state.advance(1.0 / 60.0, 0.0, 0.0, 0.0)
	var clearance := Course.ground_height(state.position.x) - state.position.y
	_expect(state.contacts == 2 and absf(clearance - Tuning.RIDE_HEIGHT) < 0.75
		and clearance < 40.0 and absf(state.velocity.y) < 0.05,
		"The short springs must settle at the stock ride height without sinking or bouncing.")
	for index in 2:
		var wheel_bottom := state.wheel_centers[index].y + State.WHEEL_RADIUS
		_expect(absf(wheel_bottom - Course.ground_height(state.wheel_centers[index].x)) < 0.05,
			"The smaller tires must remain on the collision surface at rest.")
	_expect(state.elapsed == 0.0 and state.recoveries == 0,
		"The clock waits for the driver and idle suspension cannot crash.")
	for frame in 36:
		state.advance(1.0 / 60.0, 1.0, 0.0, 0.0)
	var speed := state.velocity.x
	_expect(speed > 150.0 and state.position.x > Course.START_X + 40.0,
		"Throttle must drive the sprung car, not just animate its wheels.")
	for frame in 40:
		state.advance(1.0 / 60.0, 0.0, 1.0, 0.0)
	_expect(absf(state.velocity.x) < speed * 0.2, "Brake must slow the actual chassis.")
	for frame in 30:
		state.advance(1.0 / 60.0, -1.0, 0.0, 0.0)
	_expect(state.velocity.x < -80.0, "Reverse must let the player retrieve missed plugs.")
	state.position = Vector2(2000, 50)
	state.velocity = Vector2.ZERO
	state.angle = 0.0
	state.angular_velocity = 0.0
	state.advance(0.2, 0.0, 0.0, -1.0)
	_expect(state.angle < -0.02 and state.contacts == 0,
		"Airborne tilt must rotate the chassis without imaginary ground contact.")
	_expect(is_inf(Course.ground_height(2870.0)),
		"The quarry is a real gap rather than an invisible collision bridge.")


func _test_fixed_step() -> void:
	var slow := State.new()
	var fast := State.new()
	for frame in 120:
		slow.advance(1.0 / 30.0, 0.7, 0.0, 0.0)
	for frame in 576:
		fast.advance(1.0 / 144.0, 0.7, 0.0, 0.0)
	_expect(slow.position.distance_to(fast.position) < 0.001
		and absf(slow.angle - fast.angle) < 0.00001
		and absf(slow.elapsed - fast.elapsed) < 0.00001,
		"30 and 144 FPS must integrate the same run and clock.")


func _test_pickups_and_checkpoints() -> void:
	var state := State.new()
	state.position = Course.plug_position(0)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.plug_count() == 1 and state.score() == 1000,
		"A plug can only be collected and scored once.")
	state.position = Course.spawn_position(1)
	state.velocity = Vector2.ZERO
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.checkpoint == 0, "A checkpoint cannot strand an earlier missing plug.")
	state.collected[1] = true
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.checkpoint == 1, "A grounded car with earlier plugs saves the checkpoint.")
	state.recover()
	_expect(state.checkpoint == 1 and state.plug_count() == 2
		and state.position == Course.spawn_position(1),
		"Recovery retains pickups and uses the last safe checkpoint.")
	state.position = Course.spawn_position(2)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.checkpoint == 1, "The far-side checkpoint requires the pre-jump plug.")


func _test_crash_and_recovery() -> void:
	var state := State.new()
	state.position = Vector2(400, 632)
	state.angle = PI
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.crash_wait > 0.0 and state.recoveries == 1,
		"Roof contact must crash rather than allow driving upside down.")
	state.recover()
	_expect(state.recoveries == 1, "Manual recovery during a crash cannot double-charge.")
	state.advance(1.0, 0.0, 0.0, 0.0)
	_expect(state.crash_wait == 0.0 and state.position.x == Course.START_X,
		"A crash must automatically return the Cube to safety.")
	_expect(absf(state.adjusted_time() - state.elapsed - 5.0) < 0.001,
		"Each recovery adds exactly five seconds, not a hidden score deduction.")
	state.position = Vector2(2860, Course.FALL_Y + 5)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.recoveries == 2, "Falling into the quarry must recover, not soft-lock.")


func _test_finish_rules() -> void:
	var state := State.new()
	state.position = Vector2(Course.FINISH_X + 100, 610 - Tuning.RIDE_HEIGHT)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(not state.finished, "The garage cannot complete a run with missing plugs.")
	state.collected.fill(true)
	state.velocity.x = 300.0
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(not state.finished, "Flying through the garage is not parking.")
	state.velocity = Vector2.ZERO
	state.elapsed = 40.0
	state.recoveries = 2
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.finished and state.medal() == "SILVER",
		"Five plugs and a slow upright landing finish; penalties count toward the medal.")
	var completed_position := state.position
	var completed_time := state.adjusted_time()
	state.advance(2.0, 1.0, 0.0, 1.0)
	state.recover()
	_expect(state.position == completed_position and state.adjusted_time() == completed_time,
		"A finished run must freeze its score, physics and clock.")
	_expect(state.score() == 5000 + maxi(0, 3000 - ceili(completed_time * 40.0)),
		"Results must use the advertised five-plug plus adjusted-time bonus.")
	_expect(State.time_text(65.239) == "01:05.23", "Clock formatting must preserve hundredths.")


func _test_complete_course() -> void:
	var state := State.new()
	var trace := PackedStringArray()
	for frame in 60 * 100:
		var controls := Driver.controls(state)
		state.advance(1.0 / 60.0, controls.x, controls.y, controls.z)
		for event in state.take_events():
			trace.append("%0.1fs x=%0.0f %s" % [
				state.elapsed, state.position.x, event["text"],
			])
		if state.finished:
			break
	_expect(state.finished and state.plug_count() == 5 and state.checkpoint == 2,
		"A real input-only drive must cross the quarry, collect all five plugs and park.\n"
		+ "\n".join(trace) + "\nFinal position: %s" % state.position)
	if state.finished:
		print("Copper Creek input-only drive: %s, %d recoveries, %s." % [
			State.time_text(state.adjusted_time()), state.recoveries, state.medal(),
		])


func _test_assisted_recovery_runs() -> void:
	for assist in [0.5, 1.5]:
		var state := State.new()
		state.air_control = assist
		var recovered := false
		var fps := 30 if assist == 0.5 else 144
		for frame in fps * 90:
			if state.checkpoint == 1 and state.position.x > 2320.0 and not recovered:
				state.recover()
				recovered = true
			var controls := Driver.controls(state)
			state.advance(1.0 / fps, controls.x, controls.y, controls.z)
			state.take_events()
			if state.finished:
				break
		_expect(recovered and state.finished and state.plug_count() == 5,
			"An input-only run must finish after recovery at %.0f%% air control / %d FPS; got %s."
			% [assist * 100.0, fps, state.position])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
