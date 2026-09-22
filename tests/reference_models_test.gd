extends SceneTree

## Saved Blender prop exports must remain portable, grounded and meter-scaled.

const MODELS := [
	{
		"file": "pine_tree", "root": "PineTree",
		"groups": ["Foliage", "Trunk"], "triangles": 8000, "surfaces": 5,
		"minimum": Vector3(2.5, 6.02, 2.5), "maximum": Vector3(3.4, 6.04, 3.4),
		"two_sided": ["Foliage shadow", "Foliage midtone", "Foliage highlight"],
	},
	{
		"file": "spark_plug", "root": "SparkPlug",
		"groups": ["Ceramic", "InsulatorBands", "Metalwork"], "triangles": 6000, "surfaces": 7,
		"minimum": Vector3(0.0175, 0.0954, 0.0175),
		"maximum": Vector3(0.0185, 0.0956, 0.019), "two_sided": [],
	},
	{
		"file": "checkpoint_flag", "root": "CheckpointFlag",
		"groups": ["FlagCloth", "Footing", "PoleAndHardware"], "triangles": 4000, "surfaces": 8,
		"minimum": Vector3(2.5, 3.59, 1.6), "maximum": Vector3(2.8, 3.61, 2.0),
		"two_sided": ["Flag field", "Flag check", "Grass"],
	},
	{
		"file": "car_body_shop", "root": "CarBodyShop",
		"groups": ["Cladding", "Forecourt", "Landscaping", "Metalwork", "RedPanels",
			"SignsAndMarkings", "Windows", "Workshop"], "triangles": 24000, "surfaces": 16,
		"minimum": Vector3(18.19, 6.4, 13.89), "maximum": Vector3(18.8, 6.8, 14.2),
		"two_sided": [],
	},
]

var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for model in MODELS:
		_test_model(model)
	if _failures.is_empty():
		print("Cube Trials reference model tests passed.")
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_model(model: Dictionary) -> void:
	var label: String = model["file"]
	var path := "res://games/cube_trials/assets/models/%s.glb" % label
	var packed := load(path) as PackedScene
	_expect(packed != null, label + ": the saved GLB must import as a PackedScene.")
	if packed == null:
		return
	var imported := packed.instantiate() as Node3D
	_expect(imported != null, label + ": the imported root must be Node3D.")
	if imported == null:
		return
	get_root().add_child(imported)
	var assembly := imported.get_node_or_null(NodePath(model["root"])) as Node3D
	_expect(assembly != null, label + ": the named assembly must survive export.")
	if assembly == null:
		imported.free()
		return
	_expect(assembly.position.is_zero_approx() and assembly.scale.is_equal_approx(Vector3.ONE),
		label + ": the assembly must retain an unscaled origin.")
	_expect(assembly.get_child_count() == model["groups"].size(),
		label + ": unexpected or missing material-group nodes.")
	for group in model["groups"]:
		_expect(assembly.get_node_or_null(NodePath(group)) is MeshInstance3D,
			label + ": missing mesh group " + group)
	var triangles := 0
	var surfaces := 0
	var mesh_count := 0
	var bounds := AABB()
	for node in imported.find_children("*", "", true, false):
		_expect(not (node is Camera3D or node is Light3D or node is CollisionObject3D
			or node is AnimationPlayer), label + ": authoring-only nodes leaked into the export.")
		if not node is MeshInstance3D:
			continue
		var mesh: Mesh = node.mesh
		var local: AABB = (imported.global_transform.affine_inverse() * node.global_transform) \
			* mesh.get_aabb()
		bounds = local if mesh_count == 0 else bounds.merge(local)
		mesh_count += 1
		surfaces += mesh.get_surface_count()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			_expect(not vertices.is_empty() and normals.size() == vertices.size(),
				label + ": every mesh needs vertices and authored normals.")
			for vertex in vertices:
				_expect(vertex.is_finite(), label + ": a vertex is not finite.")
			for normal in normals:
				_expect(normal.is_finite() and normal.length_squared() > 0.90
					and normal.length_squared() < 1.10, label + ": invalid exported normal.")
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			_expect(material != null, label + ": materials must use the portable standard shader.")
			if material == null:
				continue
			for texture in BaseMaterial3D.TEXTURE_MAX:
				_expect(material.get_texture(texture) == null,
					label + ": reference pixels must never become exported textures.")
			if material.resource_name.trim_prefix("Cube ") in model["two_sided"]:
				_expect(material.cull_mode == BaseMaterial3D.CULL_DISABLED,
					label + ": foliage, grass and flag cloth must render from both sides.")
			if label == "spark_plug" and material.resource_name == "Cube Dark steel":
				for index in vertices.size():
					var vertex := vertices[index]
					var radial := Vector2(vertex.x, vertex.z)
					if vertex.y > 0.006 and vertex.y < 0.029 and radial.length() > 0.006:
						var facing := Vector2(normals[index].x, normals[index].z)
						_expect(facing.dot(radial) > 0.0,
							"The plug thread must face outward, not disappear behind back-face culling.")
	_expect(mesh_count == model["groups"].size() and triangles > 0
		and triangles <= model["triangles"] and surfaces == model["surfaces"],
		label + ": the mesh, triangle or material-surface budget changed.")
	_expect(absf(bounds.position.y) < 0.0001, label + ": the base must be grounded at Y = 0.")
	for axis in 3:
		_expect(bounds.size[axis] >= model["minimum"][axis]
			and bounds.size[axis] <= model["maximum"][axis],
			"%s: incorrect meter-scale extent on axis %d: %s" % [label, axis, bounds.size])
	print("%s: %d triangles, %d surfaces, size %s" % [label, triangles, surfaces, bounds.size])
	imported.free()


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
