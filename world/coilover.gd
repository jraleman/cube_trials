extends MeshInstance3D

## One shared mesh, with per-wheel morphs for a helical spring and telescoping damper.

const Art = preload("res://games/cube_trials/cube_art.gd")
const Builder = preload("res://games/cube_trials/world/mesh_builder.gd")
const REFERENCE_LENGTH := 0.55
const COMPRESSED_LENGTH := 0.32
const EXTENDED_LENGTH := 1.10
const SPRING_RADIUS := 0.079
const WIRE_RADIUS := 0.016
const TURNS := 5
const END_CLEARANCE := 0.075
const CASE_LENGTH := 0.20
const EYE_RADIUS := 0.034
const BOUNDS_RADIUS := 0.105
const COIL_COLOR := Color("ffbc58")
const CHROME := Color("d5e2dc")
const SHAFT_COLOR := Color("edf5f0")
const CASE_COLOR := Color("34454c")

static var _shared_mesh: ArrayMesh
static var _shared_finish: StandardMaterial3D

var length := REFERENCE_LENGTH


func _init() -> void:
	if _shared_mesh == null:
		_shared_mesh = _build_mesh()
	if _shared_finish == null:
		_shared_finish = Art.material(0.32, 0.55)
	mesh = _shared_mesh
	material_override = _shared_finish
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	set_length(REFERENCE_LENGTH)


func fit_between(upper: Vector3, lower: Vector3) -> void:
	var span := upper - lower
	assert(span.is_finite() and span.length() > 0.001, "Coilover mounts must be distinct and finite.")
	position = (upper + lower) * 0.5
	basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	set_length(span.length())


func set_length(value: float) -> void:
	assert(is_finite(value) and value > 0.001, "Coilover length must be positive and finite.")
	length = value
	set_blend_shape_value(0, maxf(0.0,
		(REFERENCE_LENGTH - length) / (REFERENCE_LENGTH - COMPRESSED_LENGTH)))
	set_blend_shape_value(1, maxf(0.0,
		(length - REFERENCE_LENGTH) / (EXTENDED_LENGTH - REFERENCE_LENGTH)))
	var bottom := -length * 0.5 - EYE_RADIUS
	var top := maxf(length * 0.5 + EYE_RADIUS, -length * 0.5 + 0.045 + CASE_LENGTH)
	custom_aabb = AABB(Vector3(-BOUNDS_RADIUS, bottom, -BOUNDS_RADIUS),
		Vector3(BOUNDS_RADIUS * 2.0, top - bottom, BOUNDS_RADIUS * 2.0))


static func _build_mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	result.add_blend_shape("Compression")
	result.add_blend_shape("Extension")
	var base := _geometry(REFERENCE_LENGTH).surface_get_arrays(0)
	var shapes: Array[Array] = []
	for span: float in [COMPRESSED_LENGTH, EXTENDED_LENGTH]:
		var geometry := _geometry(span).surface_get_arrays(0)
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = geometry[Mesh.ARRAY_VERTEX]
		shape[Mesh.ARRAY_NORMAL] = geometry[Mesh.ARRAY_NORMAL]
		assert((geometry[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			== (base[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			"Coilover morphs must preserve vertex order and topology.")
		shapes.append(shape)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base, shapes)
	return result


static func _geometry(span: float) -> ArrayMesh:
	var parts := Builder.new()
	var lower := -span * 0.5
	var upper := span * 0.5
	parts.helix(SPRING_RADIUS, span - END_CLEARANCE * 2.0,
		WIRE_RADIUS, TURNS, COIL_COLOR)
	parts.cylinder(Vector3(0, lower + 0.045 + CASE_LENGTH * 0.5, 0),
		0.045, CASE_LENGTH, CASE_COLOR, Vector3.ZERO, 12)
	var rod_bottom := lower + 0.16
	var rod_top := upper - 0.035
	parts.cylinder(Vector3(0, (rod_bottom + rod_top) * 0.5, 0),
		0.019, rod_top - rod_bottom, SHAFT_COLOR, Vector3.ZERO, 12)
	for seat: float in [lower + END_CLEARANCE, upper - END_CLEARANCE]:
		parts.cylinder(Vector3(0, seat, 0), 0.102, 0.020, CHROME, Vector3.ZERO, 14)
	for end: float in [lower, upper]:
		parts.cylinder(Vector3(0, end, 0), EYE_RADIUS, 0.12, CHROME, Vector3(PI / 2, 0, 0), 12)
		parts.cylinder(Vector3(0, end, 0), 0.023, 0.124,
			Color("253135"), Vector3(PI / 2, 0, 0), 12)
		parts.cylinder(Vector3(0, end, 0), 0.010, 0.126, CHROME, Vector3(PI / 2, 0, 0), 8)
	# Stable, unindexed topology keeps the two morph targets aligned with the resting mesh.
	return parts.finish(false)
