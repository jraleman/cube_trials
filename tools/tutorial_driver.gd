extends RefCounted

## The same input-only feedback driver used by the physics regressions records
## the real first course. No car poses, pickups or checkpoints are assigned.

signal keycap_requested(text: String)

const State = preload("res://games/cube_trials/trial_state.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Driver = preload("res://games/cube_trials/tests/driver_fixture.gd")
const STEPS: Array[Dictionary] = [
	{"time": 0.0, "title": "Drive the very unreasonable commute",
		"body": "W drives forward, S reverses and Shift brakes. Deliver five plugs, then park in the garage."},
	{"time": 5.0, "title": "Collect the numbered spark plugs",
		"body": "Drive through each plug. The cargo counter tracks your delivery; suspension keeps the tires working."},
	{"time": 9.0, "title": "Jump the gaps and land level",
		"body": "Tap Space to jump; release before jumping again. A and D tilt the car for a balanced landing."},
	{"time": 15.5, "title": "Checkpoint flags remember your progress",
		"body": "Flags save the route after earlier plugs are collected. A crash costs a life; your cargo stays safe."},
	{"time": 22.0, "title": "Choose your camera",
		"body": "C cycles Side, Chase and Cockpit. The same driving controls work in every view."},
	{"time": 28.5, "title": "Recover instead of starting over",
		"body": "R returns to the last flag and adds five seconds. Keep your plugs and continue toward the garage."},
]

var _done: Dictionary[String, bool] = {}
var _jump_was_held := false
var _furthest := 0.0


## This is the common solo driving lesson, not a separate hot-seat simulation.
func configure(variant: String) -> bool:
	_done.clear()
	_jump_was_held = false
	_furthest = 0.0
	return variant == "solo"


## The timings follow measured 30 Hz driving on the shipped Copper Creek route.
func steps() -> Array[Dictionary]:
	return STEPS


## Show the recovery and resumed driving before the fade.
func duration() -> float:
	return 36.0


## Stable daylight and stock assists keep the demonstrated terrain readable.
func settings_overrides() -> Dictionary:
	return {
		Options.AIR_CONTROL_KEY: 1.0,
		Options.DAY_NIGHT_KEY: false,
		Options.ENGINE_AUDIO_KEY: false,
	}


## Record the car and level available on a new profile.
func configure_session(session: Node) -> void:
	session.call("configure_single_player")
	session.call("set_level", Course.COPPER)
	session.call("set_character_for_player", 0, Profiles.CUBE)


## Never inherit a held test action when starting a take.
func start(_scene: Node) -> void:
	Driver.release_controls()


## Steering enters through the registered actions; camera and recovery use real input handlers.
func update(scene: Node, time: float, _delta: float) -> void:
	if not bool(scene.get("_round_active")) or time < 1.0:
		return
	var state := scene.get("_state") as State
	_furthest = maxf(_furthest, state.position.x)
	Driver.hold_controls(state)
	var jump := Input.is_action_pressed(Options.JUMP)
	if jump and not _jump_was_held:
		keycap_requested.emit("Space")
	_jump_was_held = jump
	if _once("drive", true):
		keycap_requested.emit("W")
	if _once("chase", time >= 22.5):
		_press(scene, Options.CAMERA, "C")
	if _once("cockpit", time >= 24.2):
		_press(scene, Options.CAMERA, "C")
	if _once("side", time >= 26.2):
		_press(scene, Options.CAMERA, "C")
	if _once("recover", time >= 29.0):
		_press(scene, Options.RECOVER, "R")


## These milestones require actual progress, jumping and a real checkpoint recovery.
func validate_finished(scene: Node) -> bool:
	Driver.release_controls()
	var state := scene.get("_state") as State
	var complete := _furthest > 6000.0 and state.plug_count() >= 3 \
		and state.checkpoint >= 2 and state.landed_jumps >= 2 \
		and state.recoveries == 1 and not state.failed
	for milestone: String in ["drive", "chase", "cockpit", "side", "recover"]:
		complete = complete and _done.get(milestone, false)
	if not complete:
		push_error("Cube tutorial incomplete: x=%.0f, plugs=%d, flag=%d, jumps=%d, recoveries=%d."
			% [_furthest, state.plug_count(), state.checkpoint,
				state.landed_jumps, state.recoveries])
	return complete


func _once(key: String, ready: bool) -> bool:
	if not ready or _done.has(key):
		return false
	_done[key] = true
	return true


func _press(scene: Node, action: StringName, label: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	scene.call("_handle_gameplay_input", event)
	keycap_requested.emit(label)
