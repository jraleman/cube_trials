extends Control

## An isolated Compatibility 3D viewport preserves the shared shell and 2D driving rules.

const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const SPEED_BLUR = preload("res://games/cube_trials/assets/shaders/speed_blur.gdshader")
const CAMERA_OFFSET := Vector3(10, 6, 32)
const MAX_RENDER_WIDTH := 1920
const MAX_BLUR_PIXELS := 2.25
const BLUR_START_SPEED := 140.0
const BLUR_FULL_SPEED := 500.0
const CAMERA_NAMES := ["Side", "Chase", "Cockpit"]
const CHASE_OFFSET := Vector3(-8.5, 4.1, 3.8)
const CAMERA_CLEARANCE := 0.45
const PERSPECTIVE_FAR := 40.0

enum CameraMode { SIDE, CHASE, COCKPIT }

var state: State
var course: Course
var camera_mode := CameraMode.SIDE
var reduced_motion := false
var intense_effects := true
var braking := false
var camera := Vector2.ZERO
var ambient_time := 0.0
var daylight_time := 0.0
var day_night_enabled := true
var world: Landscape
var world_viewport: SubViewport
var world_camera: Camera3D
var _image: TextureRect
var _overlay: Control
var _zoom := 1.0
var _camera_ready := false
var _last_camera_position := Vector2.ZERO
var _chase_position := Vector3.ZERO
var _chase_target := Vector3.ZERO
var _blur_material: ShaderMaterial
var _blur_pixels := Vector2.ZERO
var _blur_strength := 0.0
var _last_recoveries := 0
var _was_recovering := false
var _parking_style: StyleBoxFlat
var _parking_hint_bounds := Rect2()
var _parking_hint_font_size := 20


func _init(route: Course = null) -> void:
	course = route if route != null else Course.new()
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
	world_camera = Camera3D.new()
	world_camera.name = "DrivingCamera"
	world_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	world_camera.near = 0.1
	world_camera.far = 250.0
	world_camera.current = true
	_build_world()
	_image = TextureRect.new()
	_image.name = "WorldImage"
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.texture = world_viewport.get_texture()
	_blur_material = ShaderMaterial.new()
	_blur_material.shader = SPEED_BLUR
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = Control.new()
	_overlay.name = "RouteOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_parking_style = StyleBoxFlat.new()
	_parking_style.bg_color = Color("172a29", 0.96)
	resized.connect(_resize_world)
	_resize_world()


## Dresses the car in the paint and wheels bought from the garage. Only the
## look changes: nothing sold alters mass, grip, ride height or the clock.
func set_finish(paint: String, rim: String, player_color := Color.TRANSPARENT) -> void:
	if world != null and world.car != null:
		world.car.set_finish(paint, rim)
		world.car.set_player_color(player_color)


func _build_world() -> void:
	if world != null:
		world.remove_child(world_camera)
		world_viewport.remove_child(world)
		world.queue_free()
	world = Landscape.new(course)
	world.name = course.id.to_pascal_case() + "World"
	world_viewport.add_child(world)
	world.parking_label.visible = false
	world.add_child(world_camera)


## Replays and hot-seat turns reuse scenery; changing level rebuilds it from the same route.
func configure(run: State) -> void:
	state = run
	if course.id != state.course.id:
		course = state.course
		_build_world()
	world.set_vehicle(state.vehicle.id)
	_camera_ready = false
	_last_camera_position = state.position
	ambient_time = 0.0
	daylight_time = 0.0
	braking = false
	_last_recoveries = state.recoveries
	_was_recovering = state.crash_wait > 0.0
	world.car.reset_motion()
	present(0.0)


func camera_name() -> String:
	return CAMERA_NAMES[camera_mode]


func cycle_camera() -> void:
	set_camera_mode((camera_mode + 1) % CAMERA_NAMES.size())


func set_camera_mode(value: CameraMode) -> void:
	assert(value >= CameraMode.SIDE and value <= CameraMode.COCKPIT, "Unknown driving camera.")
	if camera_mode == value:
		return
	camera_mode = value
	_camera_ready = false
	_clear_motion_blur()
	present(0.0)


## Essential camera tracking remains; reduced motion removes interpolation and decoration.
func present(delta: float) -> void:
	if state == null or world == null:
		return
	var recovering := state.crash_wait > 0.0
	var recovered := not recovering \
		and (state.recoveries != _last_recoveries or _was_recovering)
	_last_recoveries = state.recoveries
	_was_recovering = recovering
	var snap := reduced_motion or recovered or not _camera_ready \
		or state.position.distance_to(_last_camera_position) > 650.0
	var motion_delta := 0.0 if get_tree().paused or state.is_over() else delta
	if not reduced_motion and not state.is_over() and not get_tree().paused:
		ambient_time += delta
		if day_night_enabled and state.started:
			daylight_time = fposmod(daylight_time + delta, Art.Daylight.CYCLE_SECONDS)
	if recovered:
		world.car.reset_motion()
	world.car.steady_cabin = camera_mode == CameraMode.COCKPIT
	world.present(state, ambient_time, reduced_motion, intense_effects, braking,
		0.0 if recovered else motion_delta, daylight_time)
	_update_camera_atmosphere()
	match camera_mode:
		CameraMode.SIDE:
			snap = _present_side_camera(motion_delta, snap)
		CameraMode.CHASE:
			_present_chase_camera(motion_delta, snap)
		CameraMode.COCKPIT:
			_present_cockpit_camera()
	_camera_ready = true
	_last_camera_position = state.position
	_update_motion_blur(motion_delta, snap or recovering)
	_overlay.queue_redraw()


func _present_side_camera(delta: float, snap: bool) -> bool:
	world_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	world_camera.near = 0.1
	world_camera.far = 250.0
	var visible_width := 980.0 if size.y > size.x * 0.95 else 1250.0
	_zoom = maxf(0.1, minf(size.x / visible_width, size.y / 590.0))
	var visible_height := size.y / _zoom
	var target := state.position + Vector2(220, 47.5 - visible_height * 0.25)
	target.x = clampf(target.x, 380.0, course.finish_x + 10.0)
	var landing_height := course.ground_height(state.position.x + 330.0)
	if is_finite(landing_height):
		target.y = maxf(target.y, landing_height - visible_height * 0.34)
	snap = snap or camera.distance_to(target) > 650.0
	if snap:
		camera = target
	else:
		camera = camera.lerp(target, 1.0 - exp(-delta * 7.0))
	var focus := Art.world_point(camera)
	world_camera.position = focus + CAMERA_OFFSET
	world_camera.look_at(focus)
	world_camera.size = maxf(1.0, visible_height * Art.WORLD_SCALE)
	return snap


func _present_chase_camera(delta: float, snap: bool) -> void:
	_set_perspective(76.0, 60.0, 100.0, 0.08)
	var car := Art.world_point(state.position)
	var ahead := 2.5
	if not reduced_motion:
		ahead += clampf(state.velocity.x / 650.0, -0.5, 1.0) * 3.0
	var target := car + Vector3(ahead, 0.7, 0)
	var ground := course.ground_height(target.x / Art.WORLD_SCALE)
	if is_finite(ground):
		target.y = maxf(target.y, (Art.HEIGHT_ORIGIN - ground) * Art.WORLD_SCALE + 0.7)
	var at := car + CHASE_OFFSET
	var anchor := car + Vector3(0, 0.3, 0)
	at = _clear_chase_terrain(at, anchor)
	if snap:
		_chase_position = at
		_chase_target = target
	elif delta > 0.0:
		var response := 1.0 - exp(-delta * 9.0)
		_chase_position = _chase_position.lerp(at, response)
		_chase_target = _chase_target.lerp(target, response)
	# Smoothing must never pull the eye or the line to the car back through a crest.
	_chase_position = _clear_chase_terrain(_chase_position, anchor)
	world_camera.position = _chase_position
	world_camera.look_at(_chase_target, Vector3.UP)
	_frame_chase_car()


func _frame_chase_car() -> void:
	var bounds := world.car.local_bounds()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for index in 8:
		var point := world_camera.to_local(world.car.to_global(bounds.get_endpoint(index)))
		var angles := Vector2(atan2(point.x, -point.z), atan2(point.y, -point.z))
		minimum = minimum.min(angles)
		maximum = maximum.max(angles)
	var tangent := tan(deg_to_rad(world_camera.fov * 0.5)) * 0.92
	var limit := Vector2(atan(tangent * size.x / maxf(size.y, 1.0)), atan(tangent))
	var correction := Vector2(
		clampf(0.0, maximum.x - limit.x, minimum.x + limit.x),
		clampf(0.0, maximum.y - limit.y, minimum.y + limit.y),
	)
	# Crest look-ahead must not aim above a longer or more steeply pitched car.
	var direction := Vector3(tan(correction.x), tan(correction.y), -1)
	world_camera.look_at(world_camera.position + world_camera.basis * direction, Vector3.UP)


func _clear_chase_terrain(at: Vector3, anchor: Vector3) -> Vector3:
	var ground := course.ground_height(at.x / Art.WORLD_SCALE)
	if is_finite(ground):
		at.y = maxf(at.y, (Art.HEIGHT_ORIGIN - ground) * Art.WORLD_SCALE + CAMERA_CLEARANCE)
	var span := at.x - anchor.x
	if absf(span) < 0.001:
		return at
	# The road is piecewise linear: endpoints and crests bound the entire sight line.
	for road: Array in course.roads:
		for point: Vector2 in road:
			var vertex := Art.world_point(point)
			var along := (vertex.x - anchor.x) / span
			if along > 0.0 and along < 1.0:
				at.y = maxf(at.y, anchor.y \
					+ (vertex.y + CAMERA_CLEARANCE - anchor.y) / along)
	return at


func _present_cockpit_camera() -> void:
	_set_perspective(88.0, 50.0, 90.0, 0.03)
	# Follow essential pitch, not the decorative body rock or impact recoil.
	var attitude := Basis(Vector3.BACK, -state.angle)
	world_camera.position = Art.world_point(state.position) \
		+ attitude * world.car.cockpit_position()
	world_camera.look_at(world_camera.position + attitude * Vector3(10, -0.2, 0),
		attitude * Vector3.UP)


func _set_perspective(horizontal_fov: float, minimum: float, maximum: float, near: float) -> void:
	world_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	world_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var aspect := maxf(size.x, 1.0) / maxf(size.y, 1.0)
	world_camera.fov = clampf(rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_fov * 0.5)) \
		/ aspect)), minimum, maximum)
	world_camera.near = near
	world_camera.far = PERSPECTIVE_FAR


func _update_camera_atmosphere() -> void:
	var environment := world.daylight.environment
	environment.fog_enabled = camera_mode != CameraMode.SIDE
	if environment.fog_enabled:
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_light_color = world.daylight.sky_material.sky_horizon_color
		environment.fog_depth_begin = PERSPECTIVE_FAR * 0.6
		environment.fog_depth_end = PERSPECTIVE_FAR - 2.0
		environment.fog_sky_affect = 1.0


## Ambient nodes return to a defined resting pose instead of continuing behind a menu.
func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	if value:
		ambient_time = 0.0
		daylight_time = 0.0
	present(0.0)


## Disabling the cycle restores readable daylight immediately, including in menus.
func set_day_night_enabled(value: bool) -> void:
	day_night_enabled = value
	if not value:
		daylight_time = 0.0
	present(0.0)


## Disabling effects removes existing dust immediately, including while paused.
func set_intense_effects(value: bool) -> void:
	intense_effects = value
	present(0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_clear_motion_blur()


func _update_motion_blur(delta: float, reset: bool) -> void:
	if camera_mode != CameraMode.SIDE or reset or delta <= 0.0 or reduced_motion or not intense_effects \
		or get_tree().paused or not state.started or state.is_over() \
		or absf(state.velocity.x) <= BLUR_START_SPEED:
		_clear_motion_blur()
		return
	var target := smoothstep(BLUR_START_SPEED, BLUR_FULL_SPEED, absf(state.velocity.x))
	_blur_strength = lerpf(_blur_strength, target, 1.0 - exp(-delta * 10.0))
	var focus := Art.world_point(state.position)
	var moving := Art.world_point(state.position + state.velocity)
	var direction := world_camera.unproject_position(moving) \
		- world_camera.unproject_position(focus)
	_blur_pixels = direction.normalized() * MAX_BLUR_PIXELS * _blur_strength
	var car_bounds := car_screen_bounds()
	_blur_material.set_shader_parameter("blur_offset",
		_blur_pixels / Vector2(world_viewport.size))
	_blur_material.set_shader_parameter("focus_uv", car_bounds.get_center() / size)
	_blur_material.set_shader_parameter("focus_radius", car_bounds.size * 0.6 / size)
	_image.material = _blur_material


func _clear_motion_blur() -> void:
	_blur_strength = 0.0
	_blur_pixels = Vector2.ZERO
	if _image != null:
		_image.material = null


## Screen projection is shared by the route feedback and geometric rendering checks.
func project_point(point: Vector3) -> Vector2:
	var projected := world_camera.unproject_position(point)
	return projected * size / Vector2(world_viewport.size)


## A model-space envelope avoids treating a 3D car as the old flat sprite rectangle.
func car_screen_bounds() -> Rect2:
	if camera_mode == CameraMode.COCKPIT:
		return Rect2(Vector2.ZERO, size)
	var bounds := world.car.local_bounds()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for index in 8:
		var point := world.car.to_global(bounds.get_endpoint(index))
		if world_camera.is_position_behind(point):
			continue
		var projected := project_point(point)
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	return Rect2(minimum, maximum - minimum) if minimum.is_finite() else Rect2()


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
	var unit := maxf(1.0, get_viewport().get_visible_rect().size.x \
		/ maxf(get_window().size.x, 1.0) / 1.5)
	var left := 26.0 * unit
	var width := size.x - left * 2.0
	var y := size.y - 20.0 * unit
	_overlay.draw_line(Vector2(left, y), Vector2(left + width, y),
		Color("203834", 0.85), 4 * unit)
	for index in 5:
		var x := left + course.plug_x[index] / course.finish_x * width
		_overlay.draw_circle(Vector2(x, y), 6 * unit,
			Art.CREAM if state.collected[index] else Art.INK)
		if state.collected[index]:
			_overlay.draw_circle(Vector2(x, y), 2 * unit, Art.INK)
	var progress := clampf(state.position.x / course.finish_x, 0.0, 1.0)
	var marker := Vector2(left + progress * width, y - 9 * unit)
	_overlay.draw_colored_polygon(PackedVector2Array([
		marker, marker + Vector2(-7, -10) * unit, marker + Vector2(7, -10) * unit,
	]), Art.CREAM)
	_overlay.draw_rect(Rect2(Vector2.ZERO, size), Color("b89166"), false, 2)
	_draw_parking_hint()


func _draw_parking_hint() -> void:
	_parking_hint_bounds = Rect2()
	if state.position.x < course.finish_x - 700.0 or state.crash_wait > 0.0 or state.failed:
		return
	var parking := world.parking_target()
	if camera_mode != CameraMode.SIDE:
		parking.z = 0.0
	if world_camera.is_position_behind(parking):
		return
	var target := project_point(parking)
	if not Rect2(Vector2.ZERO, size).has_point(target):
		return
	var physical_scale := float(get_window().size.x) \
		/ maxf(get_viewport().get_visible_rect().size.x, 1.0)
	var font := ThemeDB.fallback_font
	_parking_hint_font_size = maxi(20, ceili(13.0 / physical_scale))
	var text := world.parking_label.text
	var padding := Vector2(12, 7) / physical_scale
	var box_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_parking_hint_font_size) + padding * 2.0
	var at := target - Vector2(box_size.x * 0.5, box_size.y + 18.0 / physical_scale)
	var inset := 12.0 / physical_scale
	at.x = clampf(at.x, inset, maxf(inset, size.x - inset - box_size.x))
	at.y = clampf(at.y, inset, maxf(inset, size.y - 36.0 - box_size.y))
	_parking_hint_bounds = Rect2(at, box_size)
	var color := world.parking_label.modulate
	_parking_style.border_color = color
	_parking_style.set_border_width_all(maxi(1, roundi(1.0 / physical_scale)))
	_parking_style.set_corner_radius_all(roundi(6.0 / physical_scale))
	_overlay.draw_line(Vector2(at.x + box_size.x * 0.5, at.y + box_size.y),
		target, color, 2.0 / physical_scale, true)
	_overlay.draw_circle(target, 3.0 / physical_scale, color)
	_overlay.draw_style_box(_parking_style, _parking_hint_bounds)
	_overlay.draw_string(font,
		at + padding + Vector2(0, font.get_ascent(_parking_hint_font_size)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, _parking_hint_font_size, Art.CREAM)
