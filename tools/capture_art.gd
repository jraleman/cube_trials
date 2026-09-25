extends SceneTree

## Regenerates the game's original promotional PNGs from its actual 3D meshes.
## Run with a graphics window; this development tool is excluded from exports.
## `-- --only=levels` refreshes just the level thumbnails, and
## `-- --only=builder` just the Trail Builder's.

const View = preload("res://games/cube_trials/course_view.gd")
const Portrait = preload("res://games/cube_trials/share_art.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const Trail = preload("res://games/cube_trials/trail_layout.gd")
const TrailEditor = preload("res://games/cube_trials/trail_editor.gd")
const ASSETS := "res://games/cube_trials/assets/"
## The shared setup screen's level row shows each route's own scenery and
## sky. The car is left out: it is chosen on the next row, not by the level.
const LEVEL_ART_SIZE := Vector2i(384, 240)
const LEVEL_ART_SUPERSAMPLE := 3
const LEVEL_ART_X := 520.0
const LEVEL_ART_FOCUS := Vector2(300, -200)
const LEVEL_ART_LENS := Vector3(-3, 1.2, 12)
const LEVEL_ART_FIELD_OF_VIEW := 56.0
## The Trail Builder's still is the builder itself: the car on its pad, one of
## most kinds of block with the flag picked, and the pieces to choose from.
const BUILDER_ART_TRAIL: Array[int] = [
	Trail.Piece.UP, Trail.Piece.HILL, Trail.Piece.FLAT, Trail.Piece.GAP,
	Trail.Piece.FLAG, Trail.Piece.FLAT, Trail.Piece.DOWN, Trail.Piece.DIP,
]
const BUILDER_ART_PICK := 4
## World x at the still's left edge, just behind the car.
const BUILDER_ART_LEFT := 20.0

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Cube Trials artwork capture requires a graphics window.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if not "--only=levels" in args and not "--only=builder" in args:
		await _capture_icon_and_poster()
	if not "--only=builder" in args:
		await _capture_levels()
	await _capture_builder()
	if not _failed:
		print("Cube Trials 3D artwork regenerated from the real model and course.")
	quit(1 if _failed else 0)


func _capture_icon_and_poster() -> void:
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


## One still per route, from the same spot a little way past the start, so
## the three read as a set: green hills, a turquoise shore, then snow.
func _capture_levels() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSETS + "levels"))
	var render := LEVEL_ART_SIZE * LEVEL_ART_SUPERSAMPLE
	get_root().size = render
	for level: Dictionary in Course.LEVELS:
		var state := State.new(Profiles.CUBE, str(level["id"]))
		state.advance(0.5, 0, 0, 0)
		for frame in 400:
			state.advance(1.0 / 60.0, 0.8, 0.0, 0.0)
			if state.position.x >= LEVEL_ART_X:
				break
		var view := View.new(state.course)
		view.size = Vector2(render)
		get_root().add_child(view)
		view.set_reduced_motion(true)
		view.configure(state)
		await _settle()
		view.world_viewport.size = render
		view.world.car.visible = false
		var focus := Art.world_point(state.position + LEVEL_ART_FOCUS)
		view.world_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		view.world_camera.fov = LEVEL_ART_FIELD_OF_VIEW
		view.world_camera.far = 900.0
		view.world_camera.position = focus + LEVEL_ART_LENS
		view.world_camera.look_at(focus)
		await _settle()
		var image := view.world_viewport.get_texture().get_image()
		image.resize(LEVEL_ART_SIZE.x, LEVEL_ART_SIZE.y, Image.INTERPOLATE_LANCZOS)
		_save(image, ASSETS + "levels/%s.png" % level["id"])
		view.free()
		await process_frame


## The Trail Builder's still, drawn by the builder itself without its top row.
func _capture_builder() -> void:
	var render := LEVEL_ART_SIZE * LEVEL_ART_SUPERSAMPLE
	var viewport := SubViewport.new()
	viewport.size = render
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var trail := Trail.new(BUILDER_ART_TRAIL)
	trail.select(BUILDER_ART_PICK)
	var editor := TrailEditor.new()
	editor.trail = trail
	editor.set_reduced_motion(true)
	editor.size = Vector2(render)
	editor.fit(Rect2(Vector2.ZERO, Vector2(render)), 1.0)
	viewport.add_child(editor)
	editor.get_node("Layout/TopRow").hide()
	editor.scroll_back_button.hide()
	editor.scroll_on_button.hide()
	await _settle()
	editor.canvas.scroll_by((BUILDER_ART_LEFT - editor.canvas.scroll) / Trail.PIECE_WIDTH)
	editor.canvas.settle()
	await _settle()
	var image := viewport.get_texture().get_image()
	image.resize(LEVEL_ART_SIZE.x, LEVEL_ART_SIZE.y, Image.INTERPOLATE_LANCZOS)
	_save(image, ASSETS + "levels/%s.png" % Course.CUSTOM)
	viewport.free()
	await process_frame


func _settle() -> void:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(image: Image, path: String) -> void:
	var error := image.save_png(path)
	if error != OK:
		printerr("Could not write %s: %s." % [path, error_string(error)])
		_failed = true
