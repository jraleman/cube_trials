extends Control

## The picture on a store card: the actual car in the paint that card sells, or
## the actual wheel in its finish.
##
## The store asks for this by path (`GameManifest.store_preview_scene_path`) and
## hands it the item, so the framework never learns what a Nissan Cube looks
## like. What it draws is the imported model dressed through
## `world/cube_finish.gd` — the same call the round makes — so the swatch on the
## shelf cannot promise a colour the trail then fails to deliver.
##
## The portrait is deliberately still, for the same reason the gallery's is not:
## a gallery is somewhere to look around a model, and a shelf is somewhere to
## compare thirteen of them at a glance. A card that turned would be animation
## nobody asked for, it would make the shelf expensive, and it would leave
## reduced motion something to switch off on a screen that should not need it.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")

## Long enough on the springs for the car to stop bouncing and sit at the ride
## height a parked Cube actually holds, which is what a paint card should show.
const SETTLE_SECONDS := 1.5
## Front three-quarter. The Cube faces +X, so the lens stands off the nose and
## the near flank, where a body colour has both a large panel and a rounded
## corner to read across. Only the direction matters: how far back to stand is
## solved from the model, not dialled in.
const CAR_LENS := Vector3(3.15, 1.05, 2.5)
const CAR_FIELD_OF_VIEW := 34.0
## The wheel is a disc, so it is shot nearly face-on with just enough angle
## left for the tire wall to separate from the spokes.
const WHEEL_LENS := Vector3(0.28, 0.12, 0.92)
const WHEEL_FIELD_OF_VIEW := 42.0
## Breathing room around the subject, so nothing touches the edge of the card.
const MARGIN := 1.06

var _viewport: SubViewport
var _stage: Node3D
var _subject: Node3D
var _camera: Camera3D
var _lens := CAR_LENS
var _field_of_view := CAR_FIELD_OF_VIEW
var _bounds := AABB()
var _inert := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inert = DisplayServer.get_name() == "headless"
	if _inert:
		return
	_build_case()
	resized.connect(_reframe)


## Draws [param item] — a `Store.describe()` result. Its `kind` chooses the
## subject and its `id` chooses the finish; nothing else here is read, so an
## item that changes price or gets a longer description never redraws.
func configure(item: Dictionary) -> void:
	if _inert or _stage == null:
		return
	if _subject != null:
		_stage.remove_child(_subject)
		_subject.queue_free()
		_subject = null
	var id := str(item.get("id", ""))
	if str(item.get("kind", "")) == Options.RIM_KIND:
		_show_wheel(id)
	else:
		_show_car(id)
	_request_draw()


## Part of the store card's preview contract. Nothing here moves, so this only
## asks for a redraw when a parked card comes back.
func set_preview_running(_running: bool) -> void:
	_request_draw()


func _show_car(paint: String) -> void:
	var car := Cube.new()
	car.paint_id = paint
	_stage.add_child(car)
	var settled := State.new()
	settled.advance(SETTLE_SECONDS, 0.0, 0.0, 0.0)
	car.apply_state(settled)
	# `apply_state` places the car where the trial put it; the plinth is the
	# origin, and the pose below the root is already correct.
	car.position = Vector3.ZERO
	_subject = car
	_aim(CAR_LENS, CAR_FIELD_OF_VIEW)


func _show_wheel(rim: String) -> void:
	var wheel := Cube.wheel_display(rim)
	wheel.name = "AlloyWheel"
	_stage.add_child(wheel)
	_subject = wheel
	_aim(WHEEL_LENS, WHEEL_FIELD_OF_VIEW)


func _aim(lens: Vector3, field_of_view: float) -> void:
	_lens = lens.normalized()
	_field_of_view = field_of_view
	_bounds = _measure(_subject)
	_reframe()


## Stands the lens back until every corner of the subject lands inside the
## card, at whatever size the shelf gave us. Solved rather than dialled in
## because the store sizes its cards from the window: one hand-picked distance
## would frame the car on one monitor and crop it on the next.
func _reframe() -> void:
	if _camera == null or _subject == null or size.x < 1.0 or size.y < 1.0:
		return
	if _bounds.size.is_zero_approx():
		return
	var forward := -_lens
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward)
	var half_height := tan(deg_to_rad(_field_of_view) * 0.5)
	var half_width := half_height * (size.x / size.y)
	var focus := _bounds.get_center()
	var distance := 0.0
	for corner in 8:
		var offset := _bounds.get_endpoint(corner) - focus
		var depth := offset.dot(forward)
		distance = maxf(distance, absf(offset.dot(right)) / half_width - depth)
		distance = maxf(distance, absf(offset.dot(up)) / half_height - depth)
	_camera.fov = _field_of_view
	# `look_at` needs a node already in the tree; a transform does not.
	_camera.transform = Transform3D(
		Basis.IDENTITY, focus + _lens * distance * MARGIN
	).looking_at(focus)
	_request_draw()


## The subject's real extent, measured off the meshes rather than declared, so
## that re-exporting the model reframes the card instead of quietly cropping
## it. Lights are skipped: the brake lamps reach much further than the car.
func _measure(subject: Node3D) -> AABB:
	var to_stage := _stage.global_transform.affine_inverse()
	var merged := AABB()
	var measured := false
	for node in subject.find_children("*", "GeometryInstance3D", true, false):
		var instance := node as GeometryInstance3D
		var box := (to_stage * instance.global_transform) * instance.get_aabb()
		merged = box if not measured else merged.merge(box)
		measured = true
	return merged


func _build_case() -> void:
	var container := SubViewportContainer.new()
	container.name = "Case"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.name = "Portrait"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(_viewport)

	_stage = Node3D.new()
	_stage.name = "Forecourt"
	_viewport.add_child(_stage)
	# Copper Creek's own late-afternoon daylight, so a colour is judged under
	# the light it will be driven in. The sky is dropped for a clear background
	# — a card is a cut-out on a shelf, not a second horizon behind the menu —
	# and the shadow map with it, since nothing here is standing on ground.
	Art.light_stage(_stage)
	var daylight := _stage.get_node("CopperDaylight") as WorldEnvironment
	daylight.environment.background_mode = Environment.BG_CLEAR_COLOR
	(_stage.get_node("LateAfternoonSun") as DirectionalLight3D).shadow_enabled = false

	_camera = Camera3D.new()
	_camera.name = "Lens"
	_camera.near = 0.05
	_camera.far = 40.0
	_camera.current = true
	_stage.add_child(_camera)


func _request_draw() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
