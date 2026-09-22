extends RefCounted

## Bakes game-owned details into a few lit surfaces instead of hundreds of draw calls.

var _surface := SurfaceTool.new()
var _vertex_count := 0


func _init() -> void:
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)


## Normals describe the exterior; Godot's front-facing index order is clockwise.
func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	_vertex(a, normal, color)
	_vertex(c, normal, color)
	_vertex(b, normal, color)


## Course surfaces keep their exact sloped collision profile.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	triangle(a, b, c, color)
	triangle(a, c, d, color)


## Native primitive normals also work for rotated timbers and small fittings.
func box(at: Vector3, dimensions: Vector3, color: Color, rotation := Vector3.ZERO) -> void:
	var primitive := BoxMesh.new()
	primitive.size = dimensions
	_append(primitive, Transform3D(Basis.from_euler(rotation), at), color)


## Real rounded edges catch sunlight even on the Compatibility renderer.
func rounded_box(
	at: Vector3, dimensions: Vector3, radius: float, color: Color,
	rotation := Vector3.ZERO
) -> void:
	var half := dimensions * 0.5
	var cut := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.9)
	var core := half - Vector3.ONE * cut
	var transform := Transform3D(Basis.from_euler(rotation), at)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var us: Array[float] = [-half[u], -core[u], core[u], half[u]]
		var vs: Array[float] = [-half[v], -core[v], core[v], half[v]]
		for sign_value: float in [-1.0, 1.0]:
			for row in 3:
				for column in 3:
					var points: Array[Vector3] = []
					var normals: Array[Vector3] = []
					for corner in [Vector2i(0, 0), Vector2i(1, 0),
						Vector2i(1, 1), Vector2i(0, 1)]:
						var raw := Vector3.ZERO
						raw[axis] = half[axis] * sign_value
						raw[u] = us[column + corner.x]
						raw[v] = vs[row + corner.y]
						var inner := raw.clamp(-core, core)
						var normal := (raw - inner).normalized()
						points.append(transform * (inner + normal * cut))
						normals.append(transform.basis * normal)
					for indices in [Vector3i(0, 1, 2), Vector3i(0, 2, 3)]:
						var a: int = indices.x
						var b: int = indices.y
						var c: int = indices.z
						var outward := (points[b] - points[a]).cross(points[c] - points[a])
						if outward.dot(normals[a] + normals[b] + normals[c]) < 0.0:
							var swap := b
							b = c
							c = swap
						for index in [a, c, b]:
							_vertex(points[index], normals[index], color)


## An actual hollow fender profile leaves room for the sprung tires.
func extrude(profile: PackedVector2Array, depth: float, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(profile)
	for offset in range(0, indices.size(), 3):
		var points: Array[Vector3] = []
		for corner in 3:
			var p := profile[indices[offset + corner]]
			points.append(Vector3(p.x, p.y, depth * 0.5))
		if (points[1] - points[0]).cross(points[2] - points[0]).z < 0.0:
			var swap := points[1]
			points[1] = points[2]
			points[2] = swap
		triangle(points[0], points[1], points[2], color)
		var back := Vector3(0, 0, -depth)
		triangle(points[2] + back, points[1] + back, points[0] + back, color)
	var clockwise := Geometry2D.is_polygon_clockwise(profile)
	for index in profile.size():
		var a := profile[index]
		var b := profile[(index + 1) % profile.size()]
		if clockwise:
			var swap := a
			a = b
			b = swap
		quad(Vector3(a.x, a.y, depth * 0.5), Vector3(a.x, a.y, -depth * 0.5),
			Vector3(b.x, b.y, -depth * 0.5), Vector3(b.x, b.y, depth * 0.5), color)


## A beam's length and orientation come from its endpoints, not guessed Euler angles.
func beam(a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var primitive := BoxMesh.new()
	primitive.size = Vector3(thickness, a.distance_to(b), thickness)
	var basis := Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	_append(primitive, Transform3D(basis, (a + b) * 0.5), color)


## Circular parts remain geometry, including trim, wheel hubs and roadside posts.
func cylinder(
	at: Vector3, radius: float, height: float, color: Color,
	rotation := Vector3.ZERO, segments := 20, top_ratio := 1.0
) -> void:
	var primitive := CylinderMesh.new()
	primitive.top_radius = radius * top_ratio
	primitive.bottom_radius = radius
	primitive.height = height
	primitive.radial_segments = segments
	primitive.rings = 1
	_append(primitive, Transform3D(Basis.from_euler(rotation), at), color)


## Smooth tire shoulders and badge rings do not depend on screen-space effects.
func torus(
	at: Vector3, inner: float, outer: float, color: Color, rotation := Vector3.ZERO
) -> void:
	var primitive := TorusMesh.new()
	primitive.inner_radius = inner
	primitive.outer_radius = outer
	primitive.rings = 32
	primitive.ring_segments = 10
	_append(primitive, Transform3D(Basis.from_euler(rotation), at), color)


## Scenery and the driver's helmet share small, fully three-dimensional rounded forms.
func ellipsoid(at: Vector3, dimensions: Vector3, color: Color, segments := 12) -> void:
	var primitive := SphereMesh.new()
	primitive.radius = 0.5
	primitive.height = 1.0
	primitive.radial_segments = segments
	primitive.rings = maxi(4, segments / 2)
	_append(primitive, Transform3D(Basis.from_scale(dimensions), at), color)


## A continuous, round-wire spring; changing pitch never changes the wire diameter.
func helix(
	radius: float, height: float, wire_radius: float, turns: int, color: Color
) -> void:
	var steps := turns * 16
	var sides := 8
	for step in steps:
		for side in sides:
			for corner in [
				Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1),
				Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1),
			]:
				var frame := _helix_frame(radius, height, turns, float(step + corner.x) / steps)
				var phase := TAU * float(side + corner.y) / sides
				var normal := frame.basis * Vector3(cos(phase), sin(phase), 0)
				_vertex(frame.origin + normal * wire_radius, normal, color)
	for end in 2:
		var frame := _helix_frame(radius, height, turns, float(end))
		var normal := frame.basis.z * (-1.0 if end == 0 else 1.0)
		for side in sides:
			_vertex(frame.origin, normal, color)
			for corner: int in ([0, 1] if end == 0 else [1, 0]):
				var phase := TAU * float(side + corner) / sides
				var offset := frame.basis * Vector3(cos(phase), sin(phase), 0) * wire_radius
				_vertex(frame.origin + offset, normal, color)


func _helix_frame(radius: float, height: float, turns: int, along: float) -> Transform3D:
	var angle := TAU * turns * along
	var radial := Vector3(cos(angle), 0, sin(angle))
	var tangent := Vector3(-radius * sin(angle), height / (TAU * turns), radius * cos(angle)).normalized()
	return Transform3D(Basis(radial, tangent.cross(radial), tangent),
		radial * radius + Vector3.UP * (along - 0.5) * height)


## One surface per finish makes static terrain inexpensive to draw.
func finish(indexed := true) -> ArrayMesh:
	assert(_vertex_count > 0, "A Cube Trials mesh must contain geometry.")
	if indexed:
		_surface.index()
	return _surface.commit()


func _append(primitive: Mesh, transform: Transform3D, color: Color) -> void:
	var arrays := primitive.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := transform.basis.inverse().transposed()
	for index in indices:
		_vertex(transform * vertices[index], (normal_basis * normals[index]).normalized(), color)


func _vertex(point: Vector3, normal: Vector3, color: Color) -> void:
	_surface.set_color(color)
	_surface.set_normal(normal)
	_surface.add_vertex(point)
	_vertex_count += 1
