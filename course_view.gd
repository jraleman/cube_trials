extends Control

## An isolated Compatibility 3D viewport preserves the shared shell and 2D driving rules.

const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const CAMERA_OFFSET := Vector3(10, 6, 32)
const MAX_RENDER_WIDTH := 1920

var state: State
var reduced_motion := false
var intense_effects := true
var braking := false
var camera := Vector2.ZERO
var ambient_time := 0.0
var world: Landscape
var world_viewport: SubViewport
var world_camera: Camera3D
var _image: TextureRect
var _overlay: Control
var _zoom := 1.0
var _camera_ready := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	world_viewport = SubViewport.new()
	world_viewport.name = "CopperCreekViewport"
	world_viewport.own_world_3d = true
	world_viewport.gui_disable_input = true
	world_viewport.msaa_3d = Viewport.MSAA_4X
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.size = Vector2i(1280, 720)
	add_child(world_viewport)
	world = Landscape.new()
	world.name = "CopperCreekWorld"
	world_viewport.add_child(world)
	world_camera = Camera3D.new()
	world_camera.name = "SideFollowCamera"
	world_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	world_camera.near = 0.1
	world_camera.far = 250.0
	world_camera.current = true
	world.add_child(world_camera)
	_image = TextureRect.new()
	_image.name = "WorldImage"
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.texture = world_viewport.get_texture()
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = Control.new()
	_overlay.name = "RouteOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	resized.connect(_resize_world)
	_resize_world()


## Replays reuse the scenery; only the model, camera and collectible visibility reset.
func configure(run: State) -> void:
	state = run
	_camera_ready = false
	ambient_time = 0.0
	present(0.0)


## Essential camera tracking remains; reduced motion removes interpolation and decoration.
func present(delta: float) -> void:
	if state == null or world == null:
		return
	var visible_width := 980.0 if size.y > size.x * 0.95 else 1250.0
	_zoom = maxf(0.1, minf(size.x / visible_width, size.y / 590.0))
	var visible_height := size.y / _zoom
	var target := state.position + Vector2(220, 47.5 - visible_height * 0.25)
	target.x = clampf(target.x, 380.0, Course.FINISH_X + 10.0)
	var landing_height := Course.ground_height(state.position.x + 330.0)
	if is_finite(landing_height):
		target.y = maxf(target.y, landing_height - visible_height * 0.34)
	if reduced_motion or not _camera_ready or camera.distance_to(target) > 650.0:
		camera = target
	else:
		camera = camera.lerp(target, 1.0 - exp(-delta * 7.0))
	_camera_ready = true
	if not reduced_motion and not state.finished:
		ambient_time += delta
	var focus := Art.world_point(camera)
	world_camera.position = focus + CAMERA_OFFSET
	world_camera.look_at(focus)
	world_camera.size = maxf(1.0, visible_height * Art.WORLD_SCALE)
	world.present(state, ambient_time, reduced_motion, intense_effects, braking)
	_overlay.queue_redraw()


## Ambient nodes return to a defined resting pose instead of continuing behind a menu.
func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	if value:
		ambient_time = 0.0
	present(0.0)


## Disabling effects removes existing dust immediately, including while paused.
func set_intense_effects(value: bool) -> void:
	intense_effects = value
	present(0.0)


## Screen projection is shared by the route feedback and geometric rendering checks.
func project_point(point: Vector3) -> Vector2:
	var projected := world_camera.unproject_position(point)
	return projected * size / Vector2(world_viewport.size)


## A model-space envelope avoids treating a 3D car as the old flat sprite rectangle.
func car_screen_bounds() -> Rect2:
	var bounds := world.car.local_bounds()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for index in 8:
		var point := world.car.to_global(bounds.get_endpoint(index))
		var projected := project_point(point)
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	return Rect2(minimum, maximum - minimum)


func _resize_world() -> void:
	if world_viewport == null:
		return
	var visible_size := get_viewport().get_visible_rect().size
	var physical_scale := float(get_window().size.x) / maxf(visible_size.x, 1.0)
	var render_size := size * physical_scale * 1.15
	if render_size.x > MAX_RENDER_WIDTH:
		render_size *= MAX_RENDER_WIDTH / render_size.x
	if render_size.y > 1600:
		render_size *= 1600.0 / render_size.y
	world_viewport.size = Vector2i(maxi(1, roundi(render_size.x)), maxi(1, roundi(render_size.y)))
	present(0.0)


func _draw_overlay() -> void:
	if state == null:
		return
	var left := 26.0
	var width := size.x - 52.0
	var y := size.y - 25.0
	_overlay.draw_line(Vector2(left, y), Vector2(left + width, y),
		Color("203834", 0.85), 6)
	for index in 5:
		var x := left + Course.PLUG_X[index] / Course.FINISH_X * width
		_overlay.draw_circle(Vector2(x, y), 6, Art.CREAM if state.collected[index] else Art.INK)
		if state.collected[index]:
			_overlay.draw_circle(Vector2(x, y), 2, Art.INK)
	var progress := clampf(state.position.x / Course.FINISH_X, 0.0, 1.0)
	var marker := Vector2(left + progress * width, y - 9)
	_overlay.draw_colored_polygon(PackedVector2Array([
		marker, marker + Vector2(-7, -10), marker + Vector2(7, -10),
	]), Art.CREAM)
	_overlay.draw_rect(Rect2(Vector2.ZERO, size), Color("b89166"), false, 2)
	if state.crash_wait > 0.0:
		var point := project_point(Art.world_point(state.position + Vector2(0, -100)))
		_overlay.draw_string(ThemeDB.fallback_font, point + Vector2(-80, 0),
			"RECOVERING  +5s", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Art.CREAM)
