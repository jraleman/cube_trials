extends SceneTree

## Regenerates the game's original promotional PNGs from its actual 3D meshes.
## Run with a graphics window; this development tool is excluded from exports.

const View = preload("res://games/cube_trials/course_view.gd")
const Portrait = preload("res://games/cube_trials/share_art.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const ASSETS := "res://games/cube_trials/assets/"

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Cube Trials artwork capture requires a graphics window.")
		quit(1)
		return
	get_root().size = Vector2i(1200, 675)
	var portrait := Portrait.new()
	portrait.size = Vector2(512, 512)
	get_root().add_child(portrait)
	await _settle()
	var icon := portrait.world_viewport.get_texture().get_image()
	icon.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	_save(icon, ASSETS + "game-icon.png")
	portrait.free()
	var state := State.new()
	state.advance(0.5, 0, 0, 0)
	for frame in 150:
		state.advance(1.0 / 60.0, 0.8, 0.0, 0.0)
		if state.position.x >= 600.0:
			break
	var view := View.new()
	view.size = Vector2(1200, 675)
	get_root().add_child(view)
	view.set_reduced_motion(true)
	view.configure(state)
	await _settle()
	view.world_viewport.size = Vector2i(1200, 675)
	var focus := Art.world_point(state.position + Vector2(120, -12))
	view.world_camera.position = focus + Vector3(6, 5, 14)
	view.world_camera.look_at(focus)
	view.world_camera.size = 8.0
	await _settle()
	_save(view.world_viewport.get_texture().get_image(), ASSETS + "tutorial_poster.png")
	view.free()
	await process_frame
	if not _failed:
		print("Cube Trials 3D icon and poster regenerated from the real model and course.")
	quit(1 if _failed else 0)


func _settle() -> void:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(image: Image, path: String) -> void:
	var error := image.save_png(path)
	if error != OK:
		printerr("Could not write %s: %s." % [path, error_string(error)])
		_failed = true
