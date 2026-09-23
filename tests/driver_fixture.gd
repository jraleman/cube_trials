extends RefCounted

## A feedback driver uses only the same throttle, brake, tilt and jump as a human.

const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")


## Carry momentum over short-wheel-travel crests and the quarry, then actually park.
static func controls(state: State) -> Vector3:
	if state.course.id != Course.COPPER:
		return _ridge_controls(state)
	var x := state.position.x
	var target_speed := 380.0
	if x > 1080.0 and x < 1820.0:
		target_speed = 340.0
	elif x > 2100.0 and x < 3140.0:
		target_speed = 620.0
	elif x > 5000.0 and x < 6100.0:
		target_speed = 560.0
	elif x > 6300.0 and x < 7200.0:
		target_speed = 320.0
	elif x > 7230.0 and x < 8810.0:
		target_speed = 560.0
	elif x > 8890.0 and x < 9650.0:
		target_speed = 320.0
	elif (x > 11400.0 and x < 12560.0) or (x > 12900.0 and x < 14200.0):
		target_speed = 560.0
	elif x > Course.FINISH_X - 120.0:
		target_speed = 65.0
	var brake := 1.0 if state.velocity.x > target_speed + 25.0 else 0.0
	var target_angle := 0.0
	var rear := state.course.ground_height(x - 60.0)
	var front := state.course.ground_height(x + 60.0)
	if is_finite(rear) and is_finite(front):
		target_angle = atan2(front - rear, 120.0)
	if x > 2700.0 and x < 2810.0:
		target_angle = -0.48
	elif x >= 2810.0 and x < 3050.0:
		target_angle = 0.12
	var tilt := clampf(
		wrapf(target_angle - state.angle, -PI, PI) * 4.0
		- state.angular_velocity * 1.8, -1.0, 1.0
	)
	return Vector3(0.0 if brake > 0.0 else 1.0, brake, tilt)


static func jump_pressed(state: State) -> bool:
	# Collect the washboard plug before hopping; the taller arc would sail over it.
	if state.course.id == Course.COPPER and state.contacts > 0 and (
		(state.collected[1] and state.position.x >= 1510.0 and state.position.x < 1680.0)
		or (state.position.x >= 6920.0 and state.position.x < 7000.0)
		or (state.position.x >= 8830.0 and state.position.x < 8960.0)
		or (state.position.x >= 9340.0 and state.position.x < 9440.0)
	):
		return true
	var first_gap := 1 if state.course.id == Course.COPPER else 0
	for index in range(first_gap, state.course.roads.size() - 1):
		var edge: float = state.course.roads[index][-1].x
		if state.position.x >= edge - 85.0 and state.position.x < edge + 20.0:
			return true
	return false


static func _ridge_controls(state: State) -> Vector3:
	var x := state.position.x
	var target_speed := 380.0
	for gap in state.course.gap_intervals():
		if x > gap.x - 650.0 and x < gap.y + 200.0:
			target_speed = 560.0
	if x > state.course.finish_x - 180.0:
		target_speed = 65.0
	var brake := 1.0 if state.velocity.x > target_speed + 25.0 else 0.0
	var rear := state.course.ground_height(x - 60.0)
	var front := state.course.ground_height(x + 60.0)
	var target_angle := atan2(front - rear, 120.0) if is_finite(rear) and is_finite(front) else 0.0
	var tilt := clampf(wrapf(target_angle - state.angle, -PI, PI) * 4.0
		- state.angular_velocity * 1.8, -1.0, 1.0)
	return Vector3(0.0 if brake > 0.0 else 1.0, brake, tilt)


## Scene checks drive the registered actions, rather than assigning a winning pose.
static func hold_controls(state: State) -> void:
	var axes := controls(state)
	Input.action_press(Options.THROTTLE, maxf(0.0, axes.x))
	Input.action_press(Options.REVERSE, maxf(0.0, -axes.x))
	Input.action_press(Options.BRAKE, axes.y)
	Input.action_press(Options.NOSE_UP, maxf(0.0, -axes.z))
	Input.action_press(Options.NOSE_DOWN, maxf(0.0, axes.z))
	if jump_pressed(state):
		Input.action_press(Options.JUMP)
	else:
		Input.action_release(Options.JUMP)


## Never leave synthesized input held for a later test or scene.
static func release_controls() -> void:
	for action in Options.DRIVE_ACTIONS:
		Input.action_release(action)
