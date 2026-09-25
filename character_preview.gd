extends "res://games/cube_trials/store_preview.gd"

## The shared character selector displays the same rig and finishes as gameplay.

## A store card frames the corners of the car's bounding box, which in a
## three-quarter view leaves the box's far corners as empty air. The setup
## screen stands the car on a plinth as the hero of the screen, so it closes in
## on the silhouette instead, still clear of every edge for all three bodies.
const STAGE_CLOSE_UP := 0.86
## Lower than the store card's lens, near the eye height the plinth is drawn
## from, so the tires read as standing on its top face rather than above it.
const STAGE_LENS := Vector3(3.15, 0.65, 2.5)

var _shown := ""


func configure(character: Dictionary) -> void:
	vehicle_id = str(character["id"])
	player_color = character.get("player_color", Color.TRANSPARENT) \
		if bool(character.get("multiplayer", false)) else Color.TRANSPARENT
	wheel_finish = Store.equipped_id(Options.GAME_ID, Options.RIM_SLOT)
	var paint := Store.equipped_id(Options.GAME_ID, Options.PAINT_SLOTS[vehicle_id])
	var signature := "%s/%s/%s/%s" % [vehicle_id, paint, wheel_finish, player_color.to_html()]
	if signature == _shown:
		return
	_shown = signature
	super({"id": paint, "kind": Options.PAINT_KINDS[vehicle_id]})


func _aim(lens: Vector3, field_of_view: float) -> void:
	super(STAGE_LENS if lens == CAR_LENS else lens, field_of_view)


func _reframe() -> void:
	super()
	if _camera == null or _bounds.size.is_zero_approx():
		return
	var focus := _bounds.get_center()
	_camera.position = focus + (_camera.position - focus) * STAGE_CLOSE_UP
