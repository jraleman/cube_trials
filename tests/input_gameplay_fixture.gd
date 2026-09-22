extends "res://games/cube_trials/gameplay.gd"

## Exercise actual joypad events without requiring a connected hardware controller.

var test_controller := -1


func _controller_device() -> int:
	return test_controller if test_controller >= 0 else super()
