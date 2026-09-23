extends "res://games/cube_trials/store_preview.gd"

## The shared character selector displays the same rig and finishes as gameplay.

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
