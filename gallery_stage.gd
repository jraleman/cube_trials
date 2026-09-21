extends Control

## A turntable for the models Copper Creek is made of.
##
## The gallery screen asks for this by path (`GameManifest.gallery_stage_scene_path`)
## and drives it with `configure()`, `set_view()` and `set_auto_spin()`, so the
## framework never learns what a Nissan Cube is. Everything on the plinth is the
## same assembly the match builds — the imported car through `cube_model.gd`,
## the scenery through `copper_creek.gd` — settled and lit the same way. A
## trials course is driven past at speed from one fixed side, so a gallery that
## showed a nicer version of the car would be an advert rather than a museum.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Landscape = preload("res://games/cube_trials/world/copper_creek.gd")
const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")

## Long enough on the springs for the car to stop bouncing and sit at its real
## ride height, which is the only pose worth exhibiting it in.
const SETTLE_SECONDS := 1.5
## The pine is planted at 0.80x to 1.32x along the trail; this is the middle one.
const EXHIBIT_PINE_SCALE := 1.06

const FIELD_OF_VIEW := 40.0
## Breathing room around the exhibit, so an aerial or a gate post never touches
## the edge of the case.
const FRAMING_MARGIN := 1.10
## Kept clear of the poles: an orbit camera looking straight down cannot tell
## which way is up, and the whole view rolls.
const PITCH_LIMIT := 1.3439

## Where each exhibit is worth opening on. The car faces +X, so a front
## three-quarter needs most of a quarter turn. Boards, doors and flags all face
## +Z, the way the side-view camera reads them, so they open nearly square on
## with just enough yaw to show they have a back.
const FRAMING := {
	Options.EXHIBIT_CUBE: {"yaw": 0.9599, "pitch": 0.2094},
	Options.EXHIBIT_WHEEL: {"yaw": 0.6109, "pitch": 0.1745},
	Options.EXHIBIT_SUSPENSION: {"yaw": 0.0, "pitch": 0.1222},
	Options.EXHIBIT_PLUG: {"yaw": 0.0, "pitch": 0.2618},
	Options.EXHIBIT_CHECKPOINT: {"yaw": 0.3491, "pitch": 0.1222},
	Options.EXHIBIT_SIGN: {"yaw": 0.2618, "pitch": 0.0873},
	Options.EXHIBIT_PINE: {"yaw": 0.0, "pitch": 0.1745},
	Options.EXHIBIT_FENCE: {"yaw": 0.5236, "pitch": 0.1745},
	Options.EXHIBIT_GARAGE: {"yaw": 0.4363, "pitch": 0.2618},
}

var _viewport: SubViewport
var _camera: Camera3D
var _plinth: Node3D
var _exhibit: Node3D
## Built exhibits, kept by id and hidden rather than rebuilt. Instancing the
## car's 44,000-triangle export on every click of a nine-item list would be the
## one expensive thing this screen does, and it can be open over a live round.
var _built := {}
var _focus := Vector3.ZERO
var _base_distance := 6.0
var _base_yaw := 0.0
var _base_pitch := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _zoom := 1.0
var _inert := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inert = DisplayServer.get_name() == "headless"
	if _inert:
		return
	_build_case()
	# A resize changes the aspect, and the aspect is half of the framing maths.
	resized.connect(_on_resized)


## Puts [param exhibit] — a `GameManifest.gallery_exhibits` entry — on the
## plinth. Only the id matters; every model brings its own paint.
func configure(exhibit: Dictionary) -> void:
	var id := str(exhibit.get("id", ""))
	var framing: Dictionary = FRAMING.get(id, {})
	_base_yaw = float(framing.get("yaw", 0.0))
	_base_pitch = float(framing.get("pitch", 0.1745))
	if _inert or _plinth == null:
		return
	if _exhibit != null:
		_exhibit.visible = false
	_exhibit = _resident(id)
	if _exhibit == null:
		_request_draw()
		return
	_exhibit.visible = true
	_frame(bounds_of(_exhibit))
	_apply_camera()


## Orbit offsets from the exhibit's default framing, in radians, plus a
## magnification where 1.0 is that default and 2.0 is twice as close.
func set_view(yaw: float, pitch: float, zoom: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_zoom = maxf(zoom, 0.01)
	_apply_camera()


## Nothing here spins on its own — the screen owns the turntable and feeds it
## through [method set_view] — so this only makes sure a parked model is drawn
## with whatever view it stopped on.
func set_auto_spin(_enabled: bool) -> void:
	_request_draw()


# --------------------------------------------------------------------------
# The exhibits
# --------------------------------------------------------------------------


## Builds a fresh copy of the model behind [param id], at the origin, or null
## for an id this game does not exhibit.
##
## Public because it is the honest test surface: a headless run can build every
## exhibit and measure it without a renderer. Nothing here reads the scene tree,
## so it works on a loose node as well as a mounted one.
func build_exhibit(id: String) -> Node3D:
	match id:
		Options.EXHIBIT_CUBE:
			return _cube()
		Options.EXHIBIT_WHEEL:
			return _wheel()
		Options.EXHIBIT_SUSPENSION:
			return _suspension()
		Options.EXHIBIT_PLUG:
			return _plug()
		Options.EXHIBIT_CHECKPOINT:
			return _checkpoint()
		Options.EXHIBIT_SIGN:
			return _sign()
		Options.EXHIBIT_PINE:
			return _pine()
		Options.EXHIBIT_FENCE:
			return _fence()
		Options.EXHIBIT_GARAGE:
			return _garage()
	return null


## The car parked on its own springs. `apply_state` puts the assembly on the
## trail and poses everything under it relatively, so moving the root back to
## the origin keeps the settled pose and brings it onto the plinth.
func _cube() -> Node3D:
	var car := Cube.new()
	car.name = "BrownNissanCube"
	var state := State.new()
	state.advance(SETTLE_SECONDS, 0.0, 0.0, 0.0)
	car.apply_state(state)
	car.position = Vector3.ZERO
	return car


func _wheel() -> Node3D:
	var root := Node3D.new()
	root.name = "AlloyWheel"
	root.add_child(Cube.wheel_display())
	return root


## Shown at the length the parked car's own weight settles it to, which is most
## of its travel already used up — a trials car sits low on purpose.
func _suspension() -> Node3D:
	var root := Node3D.new()
	root.name = "CoiloverStrut"
	var strut := MeshInstance3D.new()
	strut.name = "Strut"
	strut.mesh = Cube.suspension_mesh()
	strut.material_override = Cube.suspension_material()
	strut.scale = Vector3(1.0, Tuning.STATIC_LENGTH * Art.WORLD_SCALE, 1.0)
	root.add_child(strut)
	return root


func _plug() -> Node3D:
	var root := Node3D.new()
	root.name = "SparkPlug"
	var model := MeshInstance3D.new()
	model.name = "Plug"
	model.mesh = Landscape.plug_mesh()
	model.material_override = Landscape.plug_material()
	root.add_child(model)
	root.add_child(Landscape.plug_label(0))
	return root


func _checkpoint() -> Node3D:
	var root := Node3D.new()
	root.name = "CheckpointFlag"
	var posts := Builder.new()
	Landscape.checkpoint_mast_parts(posts, Vector3.ZERO)
	root.add_child(_surface("Mast", posts, Landscape.signage_material()))
	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	flag.mesh = Landscape.checkpoint_flag_mesh()
	flag.material_override = Landscape.checkpoint_flag_material()
	flag.position = Landscape.CHECKPOINT_FLAG_OFFSET
	root.add_child(flag)
	root.add_child(Landscape.trail_label(
		"CHECKPOINT 1", Landscape.CHECKPOINT_LABEL_OFFSET, 42, 0.006, Art.CREAM
	))
	return root


## The trailhead board, wording and all, read straight out of the course.
func _sign() -> Node3D:
	var root := Node3D.new()
	root.name = "TrailSign"
	var wood := Builder.new()
	var boards := Builder.new()
	Landscape.sign_parts(wood, boards, Vector3.ZERO)
	root.add_child(_surface("Posts", wood, Landscape.timber_material()))
	root.add_child(_surface("Board", boards, Landscape.signage_material()))
	var board: Dictionary = Course.SIGNS[0]
	for label in Landscape.sign_labels(board["title"], board["detail"], Vector3.ZERO):
		root.add_child(label)
	return root


func _pine() -> Node3D:
	var root := Node3D.new()
	root.name = "RoadsidePine"
	var trunk := Builder.new()
	var needles := Builder.new()
	Landscape.tree_parts(trunk, needles, Vector3.ZERO, EXHIBIT_PINE_SCALE)
	root.add_child(_surface("Trunk", trunk, Landscape.timber_material()))
	root.add_child(_surface("Tiers", needles, Landscape.foliage_material()))
	return root


func _fence() -> Node3D:
	var root := Node3D.new()
	root.name = "TrailFence"
	var wood := Builder.new()
	Landscape.fence_parts(wood, Vector3.ZERO)
	root.add_child(_surface("Bay", wood, Landscape.timber_material()))
	return root


## The garage in its finished state: every bulb lit and the sign already asking
## for the brake, because this exhibit only opens once a run has got here.
func _garage() -> Node3D:
	var root := Node3D.new()
	root.name = "TrailService"
	var parts := Builder.new()
	var metal := Builder.new()
	Landscape.garage_parts(parts, metal, Vector3.ZERO)
	root.add_child(_surface("Shed", parts, Landscape.signage_material()))
	root.add_child(_surface("Fittings", metal, Landscape.fitting_material()))
	for label in Landscape.garage_labels("BRAKE TO PARK", Vector3.ZERO):
		root.add_child(label)
	for index in 5:
		var lamp := Landscape.garage_lamp(index, Vector3.ZERO)
		(lamp.material_override as StandardMaterial3D).albedo_color = Art.CREAM
		root.add_child(lamp)
	return root


func _surface(title: String, parts: Builder, finish: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = parts.finish()
	instance.material_override = finish
	return instance


func _resident(id: String) -> Node3D:
	if _built.has(id):
		return _built[id]
	var model := build_exhibit(id)
	if model == null:
		return null
	model.visible = false
	_built[id] = model
	_plinth.add_child(model)
	return model


# --------------------------------------------------------------------------
# The case
# --------------------------------------------------------------------------


## Rendering is request-driven rather than continuous: the viewport draws one
## frame whenever the view actually changes. A gallery left open on a still
## model then costs nothing, which matters because this screen can be opened
## from the pause menu with a whole Copper Creek still resident behind it.
func _request_draw() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_case() -> void:
	var container := SubViewportContainer.new()
	container.name = "Case"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.name = "Turntable"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(_viewport)

	_plinth = Node3D.new()
	_plinth.name = "Plinth"
	_viewport.add_child(_plinth)
	# Copper Creek's own late-afternoon daylight, so a model is lit here exactly
	# as it is out on the trail.
	Art.light_stage(_plinth)
	var daylight := _plinth.get_node("CopperDaylight") as WorldEnvironment
	# The sky goes, so the menu behind the case shows through rather than a
	# second horizon. Ambient is a flat colour anyway, so nothing is lost.
	daylight.environment.background_mode = Environment.BG_CLEAR_COLOR
	# Nothing on a plinth casts onto anything else, so the shadow map is cost
	# without a picture.
	(_plinth.get_node("LateAfternoonSun") as DirectionalLight3D).shadow_enabled = false

	_camera = Camera3D.new()
	_camera.name = "Lens"
	_camera.fov = FIELD_OF_VIEW
	_camera.near = 0.01
	_camera.far = 400.0
	_viewport.add_child(_camera)


# --------------------------------------------------------------------------
# Framing
# --------------------------------------------------------------------------


## The extent of everything [param root] actually draws, in its own space.
##
## Walked by hand instead of through `global_transform`, which needs the node to
## be inside a tree — a headless test measures exhibits that are not. Lights are
## skipped for the same reason the car's brake glow is not part of its outline.
static func bounds_of(root: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(root, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var bounds: AABB = boxes[0]
	for index in range(1, boxes.size()):
		bounds = bounds.merge(boxes[index])
	return bounds


static func _collect_bounds(node: Node3D, at: Transform3D, boxes: Array[AABB]) -> void:
	if node is GeometryInstance3D:
		boxes.append(at * (node as GeometryInstance3D).get_aabb())
	for child in node.get_children():
		var spatial := child as Node3D
		if spatial != null:
			_collect_bounds(spatial, at * spatial.transform, boxes)


## Fits the exhibit to whichever of the two field-of-view angles is tighter, so
## a nine-unit garage frames itself on a phone held upright and a tall
## checkpoint mast frames itself on an ultrawide — and a new exhibit needs no
## hand-measured camera distance at all.
##
## The model is treated as the cylinder it sweeps out as it turns, not as its
## bounding box: a box would fit at one yaw and clip at the next. Horizontally
## the camera sits where that cylinder is exactly tangent to the frustum;
## vertically it also backs off by the cylinder's radius, because the near side
## of a turning model is that much closer than its middle.
func _frame(bounds: AABB) -> void:
	_focus = bounds.get_center()
	var radius := maxf(
		Vector2(bounds.size.x, bounds.size.z).length() * 0.5, 0.005
	)
	var half_height := maxf(bounds.size.y * 0.5, 0.005)
	var vertical := deg_to_rad(FIELD_OF_VIEW)
	var horizontal := 2.0 * atan(tan(vertical * 0.5) * _aspect())
	_base_distance = (
		maxf(
			radius / sin(horizontal * 0.5),
			half_height / tan(vertical * 0.5) + radius
		)
		* FRAMING_MARGIN
	)


func _aspect() -> float:
	var box := size
	if box.x <= 0.0 or box.y <= 0.0:
		return 16.0 / 9.0
	return box.x / box.y


func _apply_camera() -> void:
	if _camera == null:
		return
	var pitch := clampf(_base_pitch + _pitch, -PITCH_LIMIT, PITCH_LIMIT)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)).rotated(
		Vector3.UP, _base_yaw + _yaw
	)
	_camera.position = _focus + offset * (_base_distance / _zoom)
	_camera.look_at(_focus, Vector3.UP)
	_request_draw()


func _on_resized() -> void:
	if _exhibit != null:
		_frame(bounds_of(_exhibit))
	_apply_camera()
