extends SceneTree

## Node-free checks for suspension, fair recovery and a physically drivable course.

const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")

var _failures := PackedStringArray()
var _course := Course.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_suspension_and_controls()
	_test_fixed_step()
	_test_jump_controls()
	_test_jump_buffer_and_coyote()
	_test_jump_frame_rates()
	_test_extended_course()
	_test_pickups_and_checkpoints()
	_test_crash_and_recovery()
	_test_lives()
	_test_damage_lifecycle()
	_test_landing_damage()
	_test_damage_frame_rates()
	_test_clean_flip()
	_test_flip_scoring()
	_test_flip_attempt_rules()
	_test_flip_finish()
	_test_dynamic_jump_scoring()
	_test_hazard_scoring()
	_test_hazard_frame_rates()
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
	var clearance := _course.ground_height(state.position.x) - state.position.y
	_expect(state.contacts == 2 and absf(clearance - Tuning.RIDE_HEIGHT) < 0.75
		and clearance < 40.0 and absf(state.velocity.y) < 0.05,
		"The short springs must settle at the stock ride height without sinking or bouncing.")
	for index in 2:
		var wheel_bottom := state.wheel_centers[index].y + State.WHEEL_RADIUS
		_expect(absf(wheel_bottom - _course.ground_height(state.wheel_centers[index].x)) < 0.05,
			"The smaller tires must remain on the collision surface at rest.")
	_expect(state.elapsed == 0.0 and state.recoveries == 0,
		"The clock waits for the driver and idle suspension cannot crash.")
	_expect(state.damage_stage == 0, "Settling at spawn must not damage a pristine car.")
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
	_expect(is_inf(_course.ground_height(2870.0)),
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


func _jump_events(state: State) -> int:
	var count := 0
	for event in state.take_events():
		if event["kind"] == "jump":
			count += 1
	return count


func _test_jump_controls() -> void:
	var state := State.new()
	_expect(not state.is_airborne(), "A fresh spawn is not a flight before its first contact step.")
	state.advance(0.5, 0.0, 0.0, 0.0)
	var floor_y := state.position.y
	state.advance(State.STEP, 0.0, 0.0, 0.0, true)
	_expect(state.started and state.elapsed > 0.0 and state.contacts == 0 and state.is_airborne()
		and state.velocity.y < -670.0 and _jump_events(state) == 1,
		"A jump press alone must start the clock and launch the actual chassis.")
	var highest := state.position.y
	var repeated := 0
	for frame in 180:
		state.advance(1.0 / 60.0, 0.0, 0.0, 0.0, true)
		highest = minf(highest, state.position.y)
		repeated += _jump_events(state)
	_expect(floor_y - highest > 225.0 and floor_y - highest < 240.0,
		"The higher standing jump must clear 225-240 units, nearly twice the old 127-unit hop.")
	_expect(repeated == 0 and state.contacts == 2 and not state.is_airborne()
		and state.damage_stage == 0
		and state.lives_left == State.STARTING_LIVES and state.recoveries == 0,
		"Holding jump must land once, without auto-hopping, damage or recovery.")
	state.advance(State.STEP, 0.0, 0.0, 0.0, false)
	state.advance(State.STEP, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(state) == 1, "Releasing and pressing again must permit a new grounded jump.")
	state.advance(0.2, 0.0, 0.0, 0.0, false)
	var upward := state.velocity.y
	state.advance(State.STEP, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(state) == 0 and state.velocity.y > upward,
		"A second midair press cannot add another impulse.")
	var queued := State.new()
	queued.advance(State.STEP * 0.25, 0.0, 0.0, 0.0, true)
	_expect(not queued.is_airborne(), "A queued press is not a flight until the physics step launches.")
	queued.advance(State.STEP * 0.75, 0.0, 0.0, 0.0, false)
	_expect(_jump_events(queued) == 1,
		"A short press between fixed steps must survive release until the next simulation tick.")
	var cleared := State.new()
	cleared.advance(0.0, 0.0, 0.0, 0.0, true)
	cleared.clear_jump_input()
	cleared.advance(0.5, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(cleared) == 0 and cleared.contacts == 2,
		"Pause must discard a queued jump and require a held input to release.")
	cleared.advance(0.0, 0.0, 0.0, 0.0, false)
	cleared.advance(0.0, 0.0, 0.0, 0.0, true)
	cleared.recover()
	_expect(not cleared.is_airborne(),
		"Recovery must not look airborne while the checkpoint awaits its first contact step.")
	cleared.advance(0.5, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(cleared) == 0 and cleared.contacts == 2,
		"Recovery cannot carry a queued or held jump onto the checkpoint.")
	cleared.position.y = Course.FALL_Y + 1.0
	cleared.advance(State.STEP, 0.0, 0.0, 0.0, false)
	_expect(not cleared.is_airborne(), "A crash must stop live flight presentation immediately.")
	cleared.advance(State.CRASH_DELAY + 0.5, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(cleared) == 0 and cleared.contacts == 2,
		"Pressing during a crash must not launch the automatic respawn.")
	cleared.finished = true
	var parked := cleared.position
	cleared.advance(1.0, 0.0, 0.0, 0.0, true)
	_expect(cleared.position == parked and _jump_events(cleared) == 0,
		"Jump input must not revive a finished run.")


func _test_jump_buffer_and_coyote() -> void:
	var buffered := State.new()
	buffered.position.y -= 12.0
	buffered.velocity.y = 150.0
	buffered.advance(0.10, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(buffered) == 1 and buffered.velocity.y < -400.0,
		"A press just before landing must buffer into one grounded jump.")
	var expired := State.new()
	expired.position.y -= 200.0
	expired.advance(2.0, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(expired) == 0 and expired.contacts == 2,
		"An early airborne press must expire, not wait indefinitely or auto-hop on landing.")
	for delay in [State.STEP, State.JUMP_COYOTE_SECONDS + State.STEP * 2.0]:
		var late := State.new()
		late.advance(0.5, 0.0, 0.0, 0.0)
		var gap := _course.gap_intervals()[0]
		late.position.x = (gap.x + gap.y) * 0.5
		late.advance(delay, 0.0, 0.0, 0.0)
		late.advance(State.STEP, 0.0, 0.0, 0.0, true)
		_expect(_jump_events(late) == (1 if delay < State.JUMP_COYOTE_SECONDS else 0),
			"Only the brief coyote window may accept a press after leaving the trail.")
	var inverted := State.new()
	inverted.angle = PI
	inverted.advance(State.STEP, 0.0, 0.0, 0.0, true)
	_expect(_jump_events(inverted) == 0, "An overturned car cannot jump from its roof.")


func _test_jump_frame_rates() -> void:
	var reference: State
	for fps: int in [30, 60, 144]:
		var state := State.new()
		var jumps := 0
		for frame in fps * 5:
			var pressed := frame < fps or (frame >= fps * 2 and frame < fps * 3)
			state.advance(1.0 / fps, 0.0, 0.0, 0.0, pressed)
			jumps += _jump_events(state)
		_expect(jumps == 2 and state.damage_stage == 0 and state.recoveries == 0,
			"Two presses must produce exactly two clean jumps at %d FPS." % fps)
		if reference != null:
			_expect(state.position.distance_to(reference.position) < 0.001
				and state.velocity.distance_to(reference.velocity) < 0.001
				and absf(state.elapsed - reference.elapsed) < 0.00001,
				"Jump impulses and landing integration must be identical at 30, 60 and 144 FPS.")
		reference = state


func _test_extended_course() -> void:
	_expect(Course.FINISH_X - Course.START_X >= (10120.0 - Course.START_X) * 1.5,
		"The mountain extension must add at least 50% to the previous start-to-finish route.")
	var gaps := _course.gap_intervals()
	_expect(gaps.size() == 6 and Course.CHECKPOINT_X.size() == 8,
		"The extended trail must contain six real gaps and seven recoverable checkpoint flags.")
	var highest := INF
	var lowest := -INF
	for road: Array in Course.ROADS:
		for point: Vector2 in road:
			highest = minf(highest, point.y)
			lowest = maxf(lowest, point.y)
	_expect(lowest - highest >= 900.0,
		"The actual driving terrain must span at least 900 vertical units, up from 240.")
	_expect(Course.PLUG_X[-1] > 10120.0 and Course.END_X > Course.FINISH_X + Course.FINISH_WIDTH,
		"The final plug and usable garage must require driving the new mountain extension.")
	for index in gaps.size():
		var gap := gaps[index]
		_expect(is_inf(_course.ground_height((gap.x + gap.y) * 0.5)),
			"Every rendered ravine must also be an open physics gap.")
		if index == 0:
			continue
		_expect(gap.y - gap.x >= 330.0, "The new ravines must be wider than the original quarry.")
		var state := State.new()
		state.position = Vector2(gap.x - 100.0,
			_course.ground_height(gap.x - 100.0) - Tuning.RIDE_HEIGHT)
		state.velocity.x = 500.0
		for frame in 120:
			state.advance(1.0 / 60.0, 1.0, 0.0, 0.0)
			if state.recoveries > 0:
				break
		_expect(state.recoveries > 0,
			"New gap %d must require a deliberate jump, not just holding throttle." % index)
	for index in Course.CHECKPOINT_X.size():
		var spawn := _course.spawn_position(index)
		for offset: float in [-73.0, 0.0, 73.0]:
			_expect(is_equal_approx(_course.ground_height(spawn.x + offset),
				spawn.y + Tuning.RIDE_HEIGHT), "Checkpoint tires must respawn on a level pull-off.")
	for index in Course.PLUG_X.size():
		_expect(_course.plug_position(index).is_finite()
			and Course.PLUG_X[index] < Course.FINISH_X,
			"All five required plugs must remain reachable before the new finish.")


func _test_pickups_and_checkpoints() -> void:
	var state := State.new()
	state.position = _course.plug_position(0)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.plug_count() == 1 and state.score() == 1000,
		"A plug can only be collected and scored once.")
	state.position = _course.spawn_position(1)
	state.velocity = Vector2.ZERO
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.checkpoint == 0, "A checkpoint cannot strand an earlier missing plug.")
	state.collected[1] = true
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.checkpoint == 1, "A grounded car with earlier plugs saves the checkpoint.")
	state.recover()
	_expect(state.checkpoint == 1 and state.plug_count() == 2
		and state.position == _course.spawn_position(1),
		"Recovery retains pickups and uses the last safe checkpoint.")
	state.position = _course.spawn_position(2)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.checkpoint == 1, "The far-side checkpoint requires the pre-jump plug.")
	for checkpoint in range(1, Course.CHECKPOINT_X.size()):
		for missing in Course.PLUG_X.size():
			if Course.PLUG_X[missing] >= Course.CHECKPOINT_X[checkpoint]:
				continue
			var gated := State.new()
			gated.collected.fill(true)
			gated.collected[missing] = false
			gated.position = _course.spawn_position(checkpoint)
			gated.advance(State.STEP, 0.0, 0.0, 0.0)
			_expect(gated.checkpoint == 0,
				"Every checkpoint must reject any earlier missing plug, including on the extension.")
			gated.collected[missing] = true
			gated.advance(State.STEP, 0.0, 0.0, 0.0)
			gated.recover()
			_expect(gated.checkpoint == checkpoint
				and gated.position == _course.spawn_position(checkpoint),
				"Every unlocked checkpoint must recover to its own safe pull-off.")


func _test_crash_and_recovery() -> void:
	var state := State.new()
	state.position = Vector2(400, 632)
	state.angle = PI
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.crash_wait > 0.0 and state.recoveries == 1
		and state.lives_left == State.STARTING_LIVES - 1,
		"Roof contact must crash rather than allow driving upside down.")
	_expect(state.damage_stage == 1, "A roof strike must advance exactly one visual stage.")
	state.recover()
	_expect(state.recoveries == 1 and state.lives_left == State.STARTING_LIVES - 1,
		"Manual recovery during a crash cannot double-charge penalties or lives.")
	state.advance(1.0, 0.0, 0.0, 0.0)
	_expect(state.crash_wait == 0.0 and state.position.x == Course.START_X,
		"A crash must automatically return the Cube to safety.")
	_expect(absf(state.adjusted_time() - state.elapsed - 5.0) < 0.001,
		"Each recovery adds exactly five seconds, not a hidden score deduction.")
	state.position = Vector2(2860, Course.FALL_Y + 5)
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.recoveries == 2, "Falling into the quarry must recover, not soft-lock.")
	_expect(state.damage_stage == 2, "A fall must add one stage after retaining roof damage.")


func _test_lives() -> void:
	var state := State.new()
	_expect(state.lives_left == 5 and not state.is_over(), "Every run must start with five lives.")
	state.collected[0] = true
	for crash in State.STARTING_LIVES:
		state.position = Vector2(2860, Course.FALL_Y + 5)
		state.advance(State.STEP, 0.0, 0.0, 0.0)
		var remaining := State.STARTING_LIVES - crash - 1
		_expect(state.lives_left == remaining and not state.is_over() and state.crash_wait > 0.0,
			"A crash must cost one life and leave time for its impact animation.")
		var penalties := state.recoveries
		state.recover()
		state.advance(State.STEP, 1.0, 1.0, 1.0)
		_expect(state.lives_left == remaining and state.recoveries == penalties,
			"Held input and recovery spam must not spend extra lives during a crash.")
		state.advance(1.0, 0.0, 0.0, 0.0)
		_expect(state.failed == (remaining == 0) and not state.finished
			and state.crash_wait == 0.0,
			"Only the fifth crash must end the run, after the impact delay.")
		if remaining > 0:
			_expect(state.position.x == Course.START_X,
				"Crashes with lives remaining must still recover to the checkpoint.")
	_expect(state.recoveries == 4 and state.score() == 1000 and state.medal() == "UNFINISHED",
		"An exhausted run keeps pickup points, with no finish bonus, medal or phantom recovery.")
	var position := state.position
	var time := state.adjusted_time()
	state.take_events()
	state.advance(5.0, 1.0, 0.0, 1.0)
	state.recover()
	_expect(state.position == position and state.adjusted_time() == time
		and state.lives_left == 0 and state.recoveries == 4 and state.take_events().is_empty(),
		"A failed run must freeze and cannot be revived by input or manual recovery.")
	var manual := State.new()
	for recovery in 8:
		manual.recover()
	_expect(manual.lives_left == 5 and manual.damage_stage == 0
		and manual.recoveries == 8 and is_equal_approx(manual.adjusted_time(), 40.0),
		"Manual recovery must remain a five-second penalty, never a life or damage charge.")


func _test_damage_lifecycle() -> void:
	var state := State.new()
	state.recover()
	_expect(state.damage_stage == 0, "Manual recovery alone must not cause damage.")
	for crash in State.MAX_DAMAGE_STAGE:
		state.position = Vector2(2860, Course.FALL_Y + 5)
		state.advance(State.STEP, 0.0, 0.0, 0.0)
		var expected := mini(crash + 1, State.MAX_DAMAGE_STAGE)
		var penalties := state.recoveries
		state.recover()
		_expect(state.damage_stage == expected and state.recoveries == penalties,
			"One crash must advance one stage, cap at battered, and ignore recovery spam.")
		state.advance(1.0, 0.0, 0.0, 0.0)
		_expect(state.damage_stage == expected and state.crash_wait == 0.0,
			"Automatic recovery and suspension settling must retain, not add or repair, damage.")
	state.recover()
	_expect(state.damage_stage == State.MAX_DAMAGE_STAGE and State.new().damage_stage == 0,
		"Damage belongs to the run and survives manual recovery, not to all new cars.")
	var clean := State.new()
	var battered := State.new()
	battered.damage_stage = State.MAX_DAMAGE_STAGE
	for frame in 240:
		clean.advance(State.STEP, 0.65, 0.0, 0.0)
		battered.advance(State.STEP, 0.65, 0.0, 0.0)
	_expect(clean.position == battered.position and clean.velocity == battered.velocity
		and clean.angle == battered.angle and clean.wheel_centers == battered.wheel_centers
		and clean.score() == battered.score() and clean.adjusted_time() == battered.adjusted_time(),
		"Visual damage must not change physics, suspension, score or the clock.")


func _airborne_damage_state() -> State:
	var state := State.new()
	state.position.y -= 200.0
	state.started = true
	state.advance(State.DAMAGE_AIR_TIME + State.STEP * 2.0, 0.0, 0.0, 0.0)
	return state


func _land(state: State, speed: float, horizontal := 0.0, spin := 0.0, jump := false) -> void:
	state.position = _course.spawn_position(0)
	state.velocity = Vector2(horizontal, speed)
	state.angle = 0.0
	state.angular_velocity = spin
	state.advance(State.STEP, 0.0, 0.0, 0.0, jump)


func _test_landing_damage() -> void:
	var soft := _airborne_damage_state()
	_land(soft, State.HARD_LANDING_SPEED - 1.0)
	_expect(soft.damage_stage == 0, "A landing below the exact threshold must not cause damage.")
	var hard := _airborne_damage_state()
	_land(hard, State.HARD_LANDING_SPEED)
	_expect(hard.damage_stage == 1 and hard.recoveries == 0 and hard.crash_wait == 0.0,
		"A threshold-speed landing must add one cosmetic stage without a recovery penalty.")
	_expect(hard.lives_left == State.STARTING_LIVES,
		"Hard landings must never consume a life.")
	var bounced := _airborne_damage_state()
	_land(bounced, State.HARD_LANDING_SPEED, 0.0, 0.0, true)
	_expect(bounced.damage_stage == 1 and bounced.lives_left == State.STARTING_LIVES
		and bounced.contacts == 0 and bounced.velocity.y < -490.0
		and bounced.velocity.y >= -State.JUMP_SPEED,
		"A buffered jump must neither erase its hard landing nor amplify its launch with impact forces.")
	var events := hard.take_events()
	_expect(events.size() == 1 and events[0]["kind"] == "damage",
		"A hard landing must produce one caption, not one event per wheel or physics step.")
	hard.position.y -= 200.0
	hard.velocity = Vector2.ZERO
	hard.advance(State.DAMAGE_AIR_TIME + State.STEP * 2.0, 0.0, 0.0, 0.0)
	_land(hard, State.HARD_LANDING_SPEED + 100.0)
	_expect(hard.damage_stage == 1,
		"An unsettled bounce must not rearm damage even if the second impact is harder.")
	hard.advance(1.0, 0.0, 0.0, 0.0)
	hard.position.y -= 400.0
	hard.velocity = Vector2.ZERO
	hard.advance(4.0, 0.0, 0.0, 0.0)
	_expect(hard.damage_stage == 2,
		"A new hard landing after stable ground contact must rearm damage.")
	var sliding := _airborne_damage_state()
	_land(sliding, 50.0, 1000.0)
	_expect(sliding.damage_stage == 0,
		"Landing severity must measure speed into the surface, not horizontal speed.")
	var spinning := _airborne_damage_state()
	_land(spinning, State.HARD_LANDING_SPEED - 200.0, 0.0, 5.0)
	_expect(spinning.damage_stage == 1,
		"The incoming wheel contact speed must include chassis rotation.")
	var recovered := _airborne_damage_state()
	recovered.recover()
	_land(recovered, State.HARD_LANDING_SPEED)
	_expect(recovered.damage_stage == 0,
		"Recovery must clear pending landing detection instead of treating spawn as impact.")
	var roof := _airborne_damage_state()
	roof.position = Vector2(400, 632)
	roof.angle = PI
	roof.velocity = Vector2(0, State.HARD_LANDING_SPEED)
	roof.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(roof.damage_stage == 1 and roof.recoveries == 1,
		"A crashing landing must take the crash path once, not also charge landing damage.")
	var battered := _airborne_damage_state()
	battered.damage_stage = State.MAX_DAMAGE_STAGE
	_land(battered, State.HARD_LANDING_SPEED)
	events = battered.take_events()
	_expect(battered.damage_stage == State.MAX_DAMAGE_STAGE and battered.lives_left == 5
		and events.size() == 1 and events[0]["kind"] == "damage",
		"A battered car still needs impact feedback, without extra damage or lost lives.")


func _test_damage_frame_rates() -> void:
	for height in [25.0, 240.0, 400.0]:
		var reference: State
		for fps in [30, 60, 144]:
			var state := State.new()
			state.position.y -= height
			state.started = true
			for frame in fps * 4:
				state.advance(1.0 / fps, 0.0, 0.0, 0.0)
			_expect(state.damage_stage == (1 if height == 400.0 else 0)
				and state.recoveries == 0,
				"A %.0f-unit drop at %d FPS must distinguish ordinary and hard landings."
				% [height, fps])
			if reference != null:
				_expect(reference.damage_stage == state.damage_stage
					and reference.position.distance_to(state.position) < 0.001
					and reference.velocity.distance_to(state.velocity) < 0.001,
					"The same fall must resolve identically at 30, 60 and 144 render FPS.")
			reference = state


func _test_clean_flip() -> void:
	var state := State.new()
	state.position = Vector2(180, -1400)
	var rotation := 0.0
	for step in 360:
		var before := state.angle
		state.advance(State.STEP, 0.0, 0.0, 1.0)
		rotation += angle_difference(before, state.angle)
		if rotation >= TAU:
			break
	_expect(rotation >= TAU and state.contacts == 0 and state.damage_stage == 0,
		"A complete input-driven midair flip must not cause damage by orientation alone.")
	_land(state, 100.0)
	_expect(state.damage_stage == 0 and state.recoveries == 0,
		"An upright gentle touchdown after a flip must remain pristine.")


func _test_flip_scoring() -> void:
	for id in [Profiles.CUBE, Profiles.SONATA, Profiles.CRV]:
		for direction: float in [-1.0, 1.0]:
			var reference: State
			for fps: int in [30, 60, 144]:
				var state := State.new(id)
				state.advance(0.5, 0.0, 0.0, 0.0)
				var flip_events := 0
				var bank_events := 0
				var unbanked := false
				for frame in fps * 3:
					var tilt := direction if frame >= fps / 6 and frame < fps else 0.0
					state.advance(1.0 / fps, 0.0, 0.0, tilt, frame == 0)
					if state.pending_flips > 0:
						unbanked = true
						_expect(state.score() == 0 and state.landed_flips == 0,
							"A completed airborne flip must not pay before a stable landing.")
					for event in state.take_events():
						if event["kind"] == "flip":
							flip_events += 1
							_expect(event["text"].begins_with(
								"Frontflip" if direction > 0.0 else "Backflip"),
								"Trick feedback must identify the actual spin direction.")
						elif event["kind"] == "trick":
							bank_events += 1
				_expect(unbanked and flip_events == 1 and bank_events == 1
					and state.landed_flips == 1 and state.flip_points == 500
					and state.jump_points > 0 and state.score() == 500 + state.jump_points
					and state.landed_jumps == 1 and state.hazard_points == 0
					and state.pending_flips == 0 and state.contacts == 2
					and state.recoveries == 0 and state.damage_stage == 0,
					"%s must bank a 500-point %s plus dynamic aerial points at %d FPS." % [
						id, "backflip" if direction < 0.0 else "frontflip", fps,
					])
				if reference != null:
					_expect(state.position.distance_to(reference.position) < 0.001
						and absf(state.angle - reference.angle) < 0.00001
						and state.score() == reference.score(),
						"Identical jump/tilt/release inputs must produce identical tricks at all frame rates.")
				reference = state
			var banked := reference.score()
			reference.recover()
			reference.advance(1.0, 0.0, 0.0, 0.0)
			_expect(reference.flip_points == 500 and reference.landed_flips == 1
				and reference.score() == banked,
				"Banked tricks survive recovery and cannot be awarded again at the checkpoint.")
	_expect(State.new().flip_points == 0 and State.new().pending_flips == 0,
		"Replay and a new hot-seat run must start without another driver's tricks.")


func _rotate_in_air(state: State, turns: float, direction := 1.0) -> void:
	state.position = Vector2(180, -10000)
	state.velocity = Vector2.ZERO
	state.angle = 0.0
	state.angular_velocity = 0.0
	var rotation := 0.0
	for step in 120 * 5:
		var before := state.angle
		state.advance(State.STEP, 0.0, 0.0, direction)
		rotation += angle_difference(before, state.angle) * direction
		if rotation >= TAU * turns:
			break
	_expect(rotation >= TAU * turns and state.contacts == 0,
		"The trick rules fixture must perform actual full-speed airborne rotation.")


func _test_flip_attempt_rules() -> void:
	var state := State.new()
	_rotate_in_air(state, 2.0)
	_expect(state.pending_flips == 2 and state.pending_flip_points() == 1000 and state.score() == 0,
		"Multiple complete rotations in one flight must accumulate unbanked points.")
	_land(state, 100.0)
	_expect(state.pending_flips == 2 and state.flip_points == 0,
		"A one-tick touchdown cannot bank a trick before the car is stable.")
	state.advance(0.5, 0.0, 0.0, 0.0)
	var banked := state.score()
	_expect(state.landed_flips == 2 and state.flip_points == 1000
		and banked == 1000 + state.jump_points and state.jump_points > 0 and state.pending_flips == 0,
		"A stable two-wheel landing banks every completed flip exactly once.")
	_rotate_in_air(state, 1.0, -1.0)
	state.recover()
	_expect(state.pending_flips == 0 and state.landed_flips == 2 and state.score() == banked,
		"Manual recovery discards only the current unlanded trick, not banked points.")
	_rotate_in_air(state, 1.0)
	state.position = Vector2(400, 632)
	state.angle = PI
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.crash_wait > 0.0 and state.pending_flips == 0 and state.score() == banked,
		"A roof strike after a full flip must lose the attempt without erasing earlier points.")
	state.advance(State.CRASH_DELAY + 0.5, 0.0, 0.0, 0.0)
	_rotate_in_air(state, 1.0)
	state.lives_left = 1
	state.position.y = Course.FALL_Y + 1.0
	state.advance(State.CRASH_DELAY + State.STEP * 2.0, 0.0, 0.0, 0.0)
	_expect(state.failed and state.pending_flips == 0 and state.score() == banked,
		"Falling on the final life loses the pending trick and keeps only banked points.")
	var partial := State.new()
	for attempt in 3:
		_rotate_in_air(partial, 0.55)
		_land(partial, 100.0)
		partial.advance(0.5, 0.0, 0.0, 0.0)
	_expect(partial.jump_points > 0 and partial.flip_points == 0
		and partial.pending_flips == 0 and partial.landed_flips == 0,
		"Partial rotations can earn aerial style but cannot be stitched into a 500-point flip.")
	var rocking := State.new()
	rocking.position = Vector2(180, -10000)
	rocking.angle = PI - 0.05
	var crossed_wrap := false
	var travel := 0.0
	for step in 120 * 6:
		var before := rocking.angle
		rocking.advance(State.STEP, 0.0, 0.0, 1.0 if (step / 24) % 2 == 0 else -1.0)
		travel += absf(angle_difference(before, rocking.angle))
		crossed_wrap = crossed_wrap or absf(before - rocking.angle) > PI
	_expect(crossed_wrap and travel > TAU and rocking.pending_flips == 0 and rocking.score() == 0,
		"Crossing the angle wrap or rocking through 360 cumulative degrees is not a full revolution.")
	var grounded := State.new()
	for step in 120 * 3:
		grounded.advance(State.STEP, 0.0, 0.0, 1.0 if (step / 24) % 2 == 0 else -1.0)
	_expect(grounded.score() == 0 and grounded.pending_flips == 0,
		"Grounded rocking and roof rolls must never award flip points.")


func _test_flip_finish() -> void:
	var state := State.new()
	_rotate_in_air(state, 1.0)
	state.collected.fill(true)
	state.position = Vector2(Course.FINISH_X + 100.0,
		_course.ground_height(Course.FINISH_X + 100.0) - state.vehicle.ride_height)
	state.velocity = Vector2.ZERO
	state.angle = 0.0
	state.angular_velocity = 0.0
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(not state.finished and state.pending_flips == 1,
		"The garage must wait for a pending trick to land safely before freezing the run.")
	state.advance(0.5, 0.0, 0.0, 0.0)
	_expect(state.finished and state.landed_flips == 1 and state.pending_flips == 0
		and state.score() == 5500 + state.jump_points
			+ maxi(0, 3000 - ceili(state.adjusted_time() * 30.0)),
		"A flip landed inside the garage must be included in the final score.")
	var score := state.score()
	state.advance(1.0, 0.0, 0.0, 1.0, true)
	state.recover()
	_expect(state.score() == score and state.landed_flips == 1,
		"Finished trick scores must freeze with the rest of the run.")


func _air_sample(speed := 0.0, pitch := 0.0, seconds := 0.5) -> State:
	var state := State.new()
	state.started = true
	state.position = Vector2(4000, -10000)
	state.velocity.x = speed
	state.angle = pitch
	state.advance(seconds, 0.0, 0.0, 0.0)
	return state


func _test_dynamic_jump_scoring() -> void:
	var level := _air_sample()
	var fast := _air_sample(600.0)
	var tilted := _air_sample(0.0, PI * 0.5)
	var inverted := _air_sample(0.0, PI)
	_expect(level.pending_jump_points() == 40 and level.score() == 0,
		"Half a second of level flight must earn exactly 40 unbanked airtime points.")
	_expect(tilted.pending_jump_points() == 65 and inverted.pending_jump_points() == 90,
		"A 90-degree or inverted half-second flight must add exactly 25 or 50 angle points.")
	_expect(fast.pending_jump_points() > level.pending_jump_points()
		and fast.pending_jump_points() < 100,
		"Real horizontal velocity must increase airborne points without exceeding its 120/second cap.")
	_expect(_air_sample(200.0).pending_jump_points() == _air_sample(-200.0).pending_jump_points()
		and tilted.pending_jump_points() == _air_sample(0.0, -PI * 0.5).pending_jump_points(),
		"Forward/reverse travel and either tilt direction must score symmetrically.")
	_expect(_air_sample(0.0, 0.0, 1.0).pending_jump_points() == 80
		and _air_sample(0.0, 0.0, State.MIN_SCORING_AIR_TIME - State.STEP).pending_jump_points() == 0
		and _air_sample(0.0, 0.0, State.MIN_SCORING_AIR_TIME).pending_jump_points() == 16,
		"Airtime must scale with duration; the exact 0.20-second threshold rejects suspension chatter.")
	var expected := fast.pending_trick_points()
	_land(fast, 100.0)
	_expect(fast.score() == 0 and fast.pending_trick_points() == expected,
		"Motion points, like flips, must wait for a stable landing rather than a single wheel strike.")
	fast.advance(0.5, 0.0, 0.0, 0.0)
	_expect(fast.score() == expected and fast.jump_points == expected and fast.landed_jumps == 1
		and fast.pending_trick_points() == 0,
		"A no-flip jump must bank its dynamic points exactly once.")
	fast.advance(2.0, 0.0, 0.0, 0.0)
	_expect(fast.score() == expected and fast.landed_jumps == 1,
		"Ground contact must not repeatedly bank the same jump.")
	var grounded := State.new()
	for step in 60:
		grounded.advance(State.STEP, 1.0, 0.0, 0.0)
	_expect(grounded.velocity.x > 100.0 and grounded.score() == 0
		and grounded.pending_trick_points() == 0,
		"Fast grounded driving must not generate aerial points.")
	var parked := _air_sample()
	parked.collected.fill(true)
	parked.position = Vector2(Course.FINISH_X + 100.0,
		_course.ground_height(Course.FINISH_X + 100.0) - parked.vehicle.ride_height)
	parked.velocity = Vector2.ZERO
	parked.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(not parked.finished and parked.pending_trick_points() == 40,
		"The garage must wait for an ordinary jump's points, not only for flips.")
	parked.advance(0.5, 0.0, 0.0, 0.0)
	_expect(parked.finished and parked.jump_points == 40
		and parked.score() == 5040 + maxi(0, 3000 - ceili(parked.adjusted_time() * 30.0)),
		"A garage landing must include aerial points and the unchanged delivery/time bonus.")


func _test_hazard_scoring() -> void:
	var scrape := _air_sample(0.0, 0.0, State.MIN_SCORING_AIR_TIME - State.STEP)
	scrape.position = Vector2(200, _course.ground_height(200) - 10.0)
	scrape.velocity = Vector2.ZERO
	scrape.angle = 0.6
	scrape.advance(State.STEP, 0.0, 0.0, 0.0)
	scrape.toggle_hazards()
	_expect(scrape.contacts == 0 and scrape.crash_wait == 0.0 and scrape.hazards_on
		and not scrape.hazard_bonus and scrape.pending_trick_points() == 0,
		"Resting on the underbody is not mid-air, even when neither wheel has contact.")
	scrape.position.y -= 100.0
	scrape.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(scrape.pending_trick_points() == 0,
		"A belly scrape must break the minimum uninterrupted airtime needed to score.")
	var state := State.new()
	state.toggle_hazards()
	state.advance(0.3, 0.0, 0.0, 0.0)
	_expect(state.hazards_on and state.hazard_time > 0.0 and not state.started
		and state.elapsed == 0.0 and not state.hazard_bonus and state.score() == 0,
		"Parked hazards must blink without starting the race clock or earning points.")
	state.advance(0.3, 0.0, 0.0, 0.0, true)
	_expect(state.is_airborne() and not state.hazard_bonus and state.jump_multiplier() == 1.0,
		"Leaving hazards on before takeoff must not pre-arm a bonus.")
	state.toggle_hazards()
	state.toggle_hazards()
	state.collected[0] = true
	var base := state.pending_jump_points()
	var boosted := roundi(base * 1.15)
	_expect(state.hazard_bonus and state.jump_multiplier() == 1.15
		and state.pending_trick_points() == boosted and state.score() == 1000,
		"Switching hazards on mid-air must multiply only the pending jump by exactly 1.15.")
	for attempt in 4:
		state.toggle_hazards()
		state.toggle_hazards()
	_expect(state.pending_trick_points() == boosted,
		"Toggle spam must never stack multipliers or award extra points.")
	state.toggle_hazards()
	_expect(state.hazard_bonus and state.pending_trick_points() == boosted,
		"Switching the lamps off must not erase a mid-air activation already earned in this jump.")
	state.toggle_hazards()
	_land(state, 100.0)
	state.advance(0.5, 0.0, 0.0, 0.0)
	_expect(state.score() == 1000 + boosted and state.jump_points == base
		and state.hazard_points == boosted - base and state.hazards_on
		and not state.hazard_bonus and state.pending_trick_points() == 0,
		"Landing must bank the exact bonus, reset eligibility, and leave the normal hazard toggle on.")
	state.advance(0.0, 0.0, 0.0, 0.0, false)
	state.advance(0.3, 0.0, 0.0, 0.0, true)
	_expect(state.pending_jump_points() > 0 and not state.hazard_bonus,
		"The next jump needs a new in-air off/on activation, not a permanently enabled multiplier.")
	state.toggle_hazards()
	state.toggle_hazards()
	state.recover()
	_expect(not state.hazard_bonus and state.pending_trick_points() == 0
		and state.score() == 1000 + boosted and state.hazards_on,
		"Recovery must discard the current aerial bonus without losing banked points or toggling lamps.")
	state.advance(0.5, 0.0, 0.0, 0.0)
	state.advance(0.3, 0.0, 0.0, 0.0, true)
	state.toggle_hazards()
	state.toggle_hazards()
	state.position.y = Course.FALL_Y + 1.0
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.crash_wait > 0.0 and not state.hazard_bonus and state.pending_trick_points() == 0
		and state.score() == 1000 + boosted,
		"A crash must discard dynamic points and their multiplier before any respawn or result.")
	state.toggle_hazards()
	_expect(state.hazards_on, "Inputs during recovery must not change the hazard toggle.")
	state.advance(State.CRASH_DELAY + 0.5, 0.0, 0.0, 0.0)
	state.finished = true
	var phase := state.hazard_time
	var final_score := state.score()
	state.toggle_hazards()
	state.advance(2.0, 0.0, 0.0, 0.0)
	_expect(state.hazards_on and state.hazard_time == phase and state.score() == final_score,
		"Completed runs must freeze hazards and aerial scoring.")
	var fresh := State.new()
	_expect(not fresh.hazards_on and not fresh.hazard_bonus and fresh.hazard_points == 0
		and fresh.jump_points == 0 and fresh.landed_jumps == 0,
		"A fresh run must not inherit any lamps, multiplier or aerial points.")


func _test_hazard_frame_rates() -> void:
	for id in [Profiles.CUBE, Profiles.SONATA, Profiles.CRV]:
		var reference: State
		for fps: int in [30, 60, 144]:
			var state := State.new(id)
			state.advance(0.5, 0.0, 0.0, 0.0)
			for frame in fps * 3:
				if frame == fps / 2:
					state.toggle_hazards()
				var tilt := 1.0 if frame >= fps / 6 and frame < fps else 0.0
				state.advance(1.0 / fps, 0.0, 0.0, tilt, frame == 0)
			_expect(state.landed_flips == 1 and state.landed_jumps == 1
				and state.score() == roundi((500 + state.jump_points) * 1.15)
				and state.hazard_points > 0 and state.recoveries == 0,
				"%s at %d FPS must apply the hazard bonus to both motion and flip points." % [id, fps])
			if reference != null:
				_expect(state.score() == reference.score() and state.jump_points == reference.jump_points
					and state.hazard_points == reference.hazard_points
					and is_equal_approx(state.hazard_time, reference.hazard_time)
					and state.position.distance_to(reference.position) < 0.001,
					"Scoring, hazard timing and physical landings must be identical at 30/60/144 FPS.")
			reference = state


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
	state.elapsed = State.GOLD_SECONDS - 5.0
	state.recoveries = 2
	state.advance(State.STEP, 0.0, 0.0, 0.0)
	_expect(state.finished and state.medal() == "SILVER",
		"Five plugs and a slow upright landing finish; penalties count toward the medal.")
	var completed_position := state.position
	var completed_time := state.adjusted_time()
	var completed_damage := state.damage_stage
	state.advance(2.0, 1.0, 0.0, 1.0)
	state.recover()
	_expect(state.position == completed_position and state.adjusted_time() == completed_time
		and state.damage_stage == completed_damage,
		"A finished run must freeze its score, physics and clock.")
	_expect(state.score() == 5000 + maxi(0, 3000 - ceili(completed_time * 30.0)),
		"Results must use the advertised five-plug plus adjusted-time bonus.")
	_expect(State.time_text(65.239) == "01:05.23", "Clock formatting must preserve hundredths.")


func _test_complete_course() -> void:
	var state := State.new()
	var trace := PackedStringArray()
	var jumps := 0
	for frame in 60 * 100:
		var controls := Driver.controls(state)
		state.advance(1.0 / 60.0, controls.x, controls.y, controls.z, Driver.jump_pressed(state))
		for event in state.take_events():
			if event["kind"] == "jump":
				jumps += 1
			trace.append("%0.1fs x=%0.0f %s" % [
				state.elapsed, state.position.x, event["text"],
			])
		if state.is_over():
			break
	_expect(state.finished and state.plug_count() == 5
		and state.checkpoint == Course.CHECKPOINT_X.size() - 1
		and jumps >= 5 and state.recoveries == 0,
		"A clean input-only drive must jump all six gaps, collect five plugs and park.\n"
		+ "\n".join(trace) + "\nFinal position: %s" % state.position)
	_expect(state.damage_stage == 0,
		"The ordinary input-only route, including the quarry jump, must not count as hard landings.")
	if state.is_over():
		print("Copper Creek input-only drive: %s, %d recoveries, %s." % [
			State.time_text(state.adjusted_time()), state.recoveries, state.medal(),
		])


func _test_assisted_recovery_runs() -> void:
	for assist in [0.5, 1.0, 1.5]:
		var state := State.new()
		state.air_control = assist
		var recovered := PackedInt32Array()
		var trace := PackedStringArray()
		var fps := 30 if assist == 0.5 else (60 if assist == 1.0 else 144)
		for frame in fps * 90:
			if state.checkpoint > 0 and not recovered.has(state.checkpoint) \
				and state.position.x > Course.CHECKPOINT_X[state.checkpoint] + 120.0:
				recovered.append(state.checkpoint)
				state.recover()
			var controls := Driver.controls(state)
			state.advance(1.0 / fps, controls.x, controls.y, controls.z, Driver.jump_pressed(state))
			for event in state.take_events():
				trace.append("%.2fs x=%.0f %s" % [state.elapsed, state.position.x, event["text"]])
			if state.is_over():
				break
		_expect(recovered.size() == Course.CHECKPOINT_X.size() - 1
			and state.finished and state.plug_count() == 5 and state.recoveries == recovered.size(),
			"An input-only run must finish cleanly after every checkpoint recovery "
			+ "at %.0f%% air control / %d FPS; got %s.\n%s"
			% [assist * 100.0, fps, state.position, "\n".join(trace)])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
