extends RefCounted

## Preload-safe controls and assists; the shared settings screen owns persistence.

const GAME_ID := "cube_trials"
const AIR_CONTROL_KEY := "game/cube_trials_air_control"
const ENGINE_AUDIO_KEY := "game/cube_trials_engine_audio"
const THROTTLE := &"cube_trials_throttle"
const REVERSE := &"cube_trials_reverse"
const NOSE_UP := &"cube_trials_nose_up"
const NOSE_DOWN := &"cube_trials_nose_down"
const BRAKE := &"cube_trials_brake"
const RECOVER := &"cube_trials_recover"
const DRIVE_ACTIONS: Array[StringName] = [NOSE_UP, NOSE_DOWN, REVERSE, THROTTLE, BRAKE]

const TUNABLES: Array[Dictionary] = [
	{
		"key": AIR_CONTROL_KEY, "default": 1.0, "min": 0.5, "max": 1.5,
		"step": 0.1, "format": GameManifest.FORMAT_PERCENT,
		"title": "Air control", "heading": "Cube Trials - live",
		"description": "How strongly the tilt controls rotate the car. Takes effect immediately.",
	},
	{
		"key": ENGINE_AUDIO_KEY, "type": GameManifest.OPTION_TOGGLE,
		"default": true, "title": "Engine sound", "heading": "Cube Trials - live",
		"description": "Play the car's continuous engine hum. Event sounds remain enabled.",
	},
]

const CONTROL_BINDINGS: Array[Dictionary] = [
	{
		"key": "controls/cube_trials_throttle", "action": THROTTLE,
		"default": KEY_W, "title": "Accelerate", "player": 0,
		"description": "Drive toward the garage.", "heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_reverse", "action": REVERSE,
		"default": KEY_S, "title": "Reverse", "player": 0,
		"description": "Drive backward to retrieve a missed spark plug.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_nose_up", "action": NOSE_UP,
		"default": KEY_A, "title": "Tilt nose up", "player": 0,
		"description": "Rotate counterclockwise, especially during a jump.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_nose_down", "action": NOSE_DOWN,
		"default": KEY_D, "title": "Tilt nose down", "player": 0,
		"description": "Rotate clockwise to land on both wheels.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_brake", "action": BRAKE,
		"default": KEY_SPACE, "title": "Brake", "player": 0,
		"description": "Slow both wheels. Brake inside the garage to finish.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_recover", "action": RECOVER,
		"default": KEY_R, "title": "Recover (+5 seconds)", "player": 0,
		"description": "Return to the last checkpoint, keeping collected plugs.",
		"heading": "Cube Trials",
	},
]
