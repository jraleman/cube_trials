extends Control

## A real 3D studio portrait of the very same model driven on Copper Creek.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Cube = preload("res://games/cube_trials/world/cube_model.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")

var model: Cube
var world_viewport: SubViewport
var _camera: Camera3D
var _image: TextureRect
var _paint_id := ""
var _rim_id := ""
var _damage_stage := 0
var _vehicle_id := Profiles.CUBE
var _player_color := Color.TRANSPARENT
var _stage: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_viewport = SubViewport.new()
	world_viewport.name = "CubePortraitViewport"
	world_viewport.own_world_3d = true
	world_viewport.gui_disable_input = true
	world_viewport.msaa_3d = Viewport.MSAA_4X
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.size = Vector2i(512, 512)
	add_child(world_viewport)
	_stage = Node3D.new()
	world_viewport.add_child(_stage)
	Art.light_stage(_stage)
	_install_model()
	var floor_parts := Builder.new()
	var center := Vector3(model.position.x, -0.16, 0)
	floor_parts.cylinder(center, 4.0, 0.32, Color("637664"), Vector3.ZERO, 64)
	floor_parts.torus(center + Vector3.UP * 0.14, 3.82, 3.90, Art.COPPER)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "StudioPlinth"
	floor_mesh.mesh = floor_parts.finish()
	floor_mesh.material_override = Art.material(0.85)
	_stage.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.current = true
	_stage.add_child(_camera)
	var focus := model.position + Vector3(0, -0.25, 0)
	_camera.position = focus + Vector3(6.3, 3.3, 8)
	_camera.look_at(focus)
	_image = TextureRect.new()
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.texture = world_viewport.get_texture()
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_frame_camera)
	_frame_camera()


## Score art is a parked model, so captures never depend on a decorative animation phase.
##
## The car on the card is the one that just did the run, in the paint it did it
## in, with its accumulated damage — a pristine bronze Cube after a battered,
## resprayed run would be advertising a different car than the player drove.
func configure(data: Dictionary) -> void:
	_paint_id = str(data.get("paint_id", ""))
	_rim_id = str(data.get("rim_id", ""))
	_damage_stage = int(data.get("damage_stage", 0))
	_vehicle_id = str(data.get("vehicle_id", Profiles.CUBE))
	_player_color = data.get("player_color", Color.TRANSPARENT)
	if is_node_ready():
		if model.vehicle.id != _vehicle_id:
			_stage.remove_child(model)
			model.queue_free()
			_install_model()
		model.set_finish(_paint_id, _rim_id)
		model.set_player_color(_player_color)
		model.set_damage_stage(_damage_stage)
		_frame_camera()


func _install_model() -> void:
	model = Cube.new(_vehicle_id)
	model.paint_id = _paint_id
	model.rim_id = _rim_id
	model.player_color = _player_color
	_stage.add_child(model)
	var state := State.new(_vehicle_id)
	state.advance(0.5, 0.0, 0.0, 0.0)
	model.apply_state(state)
	model.set_damage_stage(_damage_stage)


func _frame_camera() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var aspect := size.x / size.y
	var focus := model.position + Vector3(0, -0.25, 0)
	_camera.position = focus + Vector3(6.3, 3.3, 8)
	_camera.look_at(focus)
	_camera.size = maxf(5.4, 6.5 / aspect)
	var pixels := size * 1.25
	if pixels.x > 1200:
		pixels *= 1200.0 / pixels.x
	if pixels.y > 1200:
		pixels *= 1200.0 / pixels.y
	world_viewport.size = Vector2i(maxi(1, roundi(pixels.x)), maxi(1, roundi(pixels.y)))
