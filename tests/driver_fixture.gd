extends RefCounted

## A feedback driver uses only the same throttle, brake and tilt as a human.

const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")


## Carry momentum over short-wheel-travel crests and the quarry, then actually park.
static func controls(state: State) -> Vector3:
	var x := state.position.x
	var target_speed := 380.0
	if x > 1080.0 and x < 1820.0:
		target_speed = 340.0
	elif x > 2100.0 and x < 3140.0:
		target_speed = 620.0
	elif x > 5030.0:
		target_speed = 65.0
	var brake := 1.0 if state.velocity.x > target_speed + 25.0 else 0.0
	var target_angle := 0.0
	var rear := Course.ground_height(x - 60.0)
	var front := Course.ground_height(x + 60.0)
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


## Scene checks drive the registered actions, rather than assigning a winning pose.
static func hold_controls(state: State) -> void:
	var axes := controls(state)
	Input.action_press(Options.THROTTLE, maxf(0.0, axes.x))
	Input.action_press(Options.REVERSE, maxf(0.0, -axes.x))
	Input.action_press(Options.BRAKE, axes.y)
	Input.action_press(Options.NOSE_UP, maxf(0.0, -axes.z))
	Input.action_press(Options.NOSE_DOWN, maxf(0.0, axes.z))


## Never leave synthesized input held for a later test or scene.
static func release_controls() -> void:
	for action in Options.DRIVE_ACTIONS:
		Input.action_release(action)
