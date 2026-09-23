"""Five authored chassis looks, built from the saved car's optimized geometry.

Called by the car exporters in their background Blender processes. The pristine
source and wheels are never deformed. Scrapes are projected mesh ribbons, not
renderer-specific decals, and therefore also work in Godot Compatibility.
"""

import json
import math
import struct
from dataclasses import dataclass
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform


STAGES = ("Pristine", "Scuffed", "Dented", "Crumpled", "Battered")
PARTS = (
    "BrownBodywork", "CabinAndDriver", "ChromeHandlesGrilleAndBadges",
    "HeadlightsAndIndicators", "LampGlazing", "RearBrakeLights",
    "RubberTrimAndUnderbody", "WraparoundGlazing",
)
SOCKETS = {
    "LeftBrakeSocket": (-2.045, 0.65, 0.677),
    "RightBrakeSocket": (-2.045, -0.65, 0.677),
    "LeftHeadlightSocket": (2.005, 0.644, 0.837),
    "RightHeadlightSocket": (2.005, -0.644, 0.837),
}
MAX_CAR_TRIANGLES = 48000
MAX_CAR_SURFACES = 48
OUTPUT = Path(__file__).resolve().parents[2] / "assets" / "models" / "nissan_cube_damage.glb"
AUTHORING = Path(__file__).with_name("nissan_cube_damage.blend")


@dataclass(frozen=True)
class DamageSpec:
    key: str = "nissan_cube"
    title: str = "Nissan Cube"
    root_node: str = "NissanCube"
    source_scene: str = "Nissan Cube Z12 - Studio"
    parts: tuple = PARTS
    body: str = "BrownBodywork"
    glass: str = "WraparoundGlazing"
    scale: tuple = (1.0, 1.0, 1.0)
    roof_crush_scale: float = 1.0
    side_window: tuple = (-0.72, 1.32, 1.0, 1.0)
    front_window: tuple = (-0.20, 1.30, 1.0, 1.0)
    body_marks: tuple = (0.0, 0.70, 1.0, 1.0)
    front_scrapes: bool = True


def mapped_path(path, anchor, transform):
    x, z, width, height = transform
    return [(x + (u - anchor[0]) * width, z + (v - anchor[1]) * height) for u, v in path]


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def deform(point, stage, scale=(1.0, 1.0, 1.0), roof_crush_scale=1.0):
    # One continuous field moves panel seams, glass, trim and lamp sockets together.
    x, y, z = (point[axis] / scale[axis] for axis in range(3))
    roof = (0.0, 0.008, 0.055, 0.22, 0.36)[stage] * roof_crush_scale
    nose = (0.0, 0.025, 0.13, 0.24, 0.38)[stage]
    dent = (0.0, 0.018, 0.11, 0.19, 0.28)[stage]
    sag = (0.0, 0.025, 0.075, 0.13, 0.20)[stage]
    roof_weight = smooth(0.98, 1.64, z) * math.exp(-((x + 0.50) / 1.70) ** 4)
    front = smooth(1.32, 2.12, x)
    rear = smooth(1.58, 2.15, -x)
    hood = math.exp(-((x - 1.30) / 0.70) ** 4) * smooth(0.72, 1.02, z)
    door = math.exp(-((x + 0.22) / 0.75) ** 4 - ((z - 0.77) / 0.32) ** 2)
    side = 1.0 if y > 0.0 else -1.0
    side_weight = smooth(0.35, 0.72, abs(y))
    x += -nose * front + nose * 0.60 * rear + roof * 0.10 * roof_weight
    y -= side * dent * door * side_weight * (1.0 if side < 0 else 0.72)
    y += roof * 0.14 * roof_weight
    z -= roof * roof_weight * (1.0 + 0.16 * math.sin(x * 4.0 + y * 2.0))
    z += nose * hood * (0.48 * math.sin((x - 0.50) * 5.5) - 0.22)
    z -= sag * (front + rear * 0.70) * (1.0 - smooth(0.70, 1.18, z))
    return Vector((x * scale[0], y * scale[1], z * scale[2]))


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def tree(obj):
    return mesh_tree(obj.data)


def mesh_tree(mesh):
    return BVHTree.FromPolygons(
        [vertex.co for vertex in mesh.vertices],
        [list(face.vertices) for face in mesh.polygons], all_triangles=True,
    )


def material(name, color, metallic, roughness):
    result = bpy.data.materials.new("Cube " + name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    result.diffuse_color = (*color, 1.0)
    result.use_backface_culling = True
    return result


def prepare_geometry(source, spec):
    result = source.data.copy()
    mesh = bmesh.new()
    mesh.from_mesh(result)
    if source.name in {spec.body, spec.glass}:
        long_edges = [edge for edge in mesh.edges if edge.calc_length() > 0.45]
        bmesh.ops.subdivide_edges(mesh, edges=long_edges, cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
    mesh.normal_update()
    mesh.to_mesh(result)
    mesh.free()
    result.update()
    return result


def variant(source, geometry, stage, parent, collection, spec):
    result = source.copy()
    result.data = geometry.copy()
    result.name = STAGES[stage] + source.name
    result.data.name = result.name
    collection.objects.link(result)
    result.parent = parent
    result.matrix_parent_inverse = Matrix.Identity(4)
    result.matrix_basis = Matrix.Identity(4)
    mesh = bmesh.new()
    mesh.from_mesh(result.data)
    for vertex in mesh.verts:
        vertex.co = deform(vertex.co, stage, spec.scale, spec.roof_crush_scale)
    mesh.normal_update()
    mesh.to_mesh(result.data)
    mesh.free()
    result.data.update()
    if [tuple(face.vertices) for face in geometry.polygons] != [
            tuple(face.vertices) for face in result.data.polygons]:
        raise ValueError("Deformation must preserve the prepared surface correspondence.")
    return result


def projected(point, face, side, source_tree, surface_map, stage, offset):
    u, v = point
    if face == "side":
        origin, direction = Vector((u, side * 3.0, v)), Vector((0, -side, 0))
    else:
        origin, direction = Vector((3.0, u, v)), Vector((-1, 0, 0))
    hit, _, index, _ = source_tree.ray_cast(origin, direction)
    if hit is None:
        raise ValueError(f"Damage mark misses its source panel: {face}, {side}, {point}.")
    # Transfer the hit onto the exact rendered triangle. Recasting in the
    # original direction can miss a sloped windshield once it has folded.
    source, target = surface_map
    original = [source.vertices[v].co for v in source.polygons[index].vertices]
    moved = [target.vertices[v].co for v in target.polygons[index].vertices]
    hit = barycentric_transform(hit, *original, *moved)
    normal = (moved[1] - moved[0]).cross(moved[2] - moved[0]).normalized()
    if normal.length_squared < 0.99:
        raise ValueError(f"Damage stage {stage} collapsed a marked surface.")
    if normal.dot(direction) > 0.0:
        normal = -normal
    return hit + normal * offset, normal


def ribbon(vertices, faces, indices, path, width, material_index,
           face, side, source_tree, surface_map, stage, offset=0.0025):
    for start, end in zip(path, path[1:]):
        a, b = Vector(start), Vector(end)
        tangent = (b - a).normalized()
        across = Vector((-tangent.y, tangent.x))
        previous = None
        for step in range(7):
            t = step / 6.0
            center = a.lerp(b, t)
            half = width * (0.18 + 0.32 * math.sin(math.pi * t))
            pair = []
            normals = []
            for sign in (-1, 1):
                point, normal = projected(center + across * half * sign, face, side,
                                          source_tree, surface_map, stage, offset)
                pair.append(len(vertices))
                vertices.append(point)
                normals.append(normal)
            if previous is not None:
                quad = [previous[0], pair[0], pair[1], previous[1]]
                normal = (vertices[quad[1]] - vertices[quad[0]]).cross(
                    vertices[quad[2]] - vertices[quad[0]])
                if normal.dot(normals[0]) < 0:
                    quad.reverse()
                faces.append(quad)
                indices.append(material_index)
            previous = pair


def add_marks(target, source, stage, materials, collection, spec, glass=False):
    source_tree, surface_map = mesh_tree(source), (source, target.data)
    vertices, faces, indices = [], [], []
    if glass:
        if stage < 3:
            return
        branches = [
            [(-0.72, 1.32), (-0.88, 1.39), (-1.02, 1.48)],
            [(-0.72, 1.32), (-0.53, 1.38), (-0.46, 1.50)],
            [(-0.72, 1.32), (-0.62, 1.23), (-0.44, 1.16)],
            [(-0.72, 1.32), (-0.89, 1.25), (-1.02, 1.18)],
            [(-0.72, 1.32), (-0.74, 1.45), (-0.78, 1.54)],
        ]
        for side in (-1, 1):
            for path in branches[:3 if stage == 3 else 5]:
                path = mapped_path(path, (-0.72, 1.32), spec.side_window)
                ribbon(vertices, faces, indices, path, 0.009, 0, "side", side,
                       source_tree, surface_map, stage)
        for path in [
            [(-0.20, 1.30), (-0.40, 1.38), (-0.55, 1.48)],
            [(-0.20, 1.30), (0.02, 1.41), (0.27, 1.49)],
            [(-0.20, 1.30), (-0.05, 1.22), (0.21, 1.15)],
        ]:
            path = mapped_path(path, (-0.20, 1.30), spec.front_window)
            ribbon(vertices, faces, indices, path, 0.009, 0, "front", 1,
                   source_tree, surface_map, stage)
    else:
        strokes = [
            ([(-0.75, 0.74), (-0.33, 0.79), (0.26, 0.83)], 0.065),
            ([(-0.66, 0.66), (-0.15, 0.71), (0.35, 0.77)], 0.032),
            ([(-0.37, 0.88), (-0.05, 0.91), (0.22, 0.94)], 0.025),
            ([(-0.78, 0.52), (-0.29, 0.62), (0.42, 0.66)], 0.062),
            ([(-0.50, 0.94), (-0.22, 0.98), (0.11, 1.00)], 0.038),
            ([(-0.82, 0.62), (-0.48, 0.71), (0.19, 0.74)], 0.050),
            ([(-0.55, 0.42), (-0.15, 0.52), (0.53, 0.56)], 0.080),
            ([(-0.70, 0.97), (-0.43, 0.91), (0.23, 0.84)], 0.055),
            ([(-0.30, 0.66), (0.11, 0.88), (0.49, 0.95)], 0.065),
        ]
        for side in (-1, 1):
            for path, width in strokes[:(3, 5, 7, 9)[stage - 1]]:
                path = mapped_path(path, (0.0, 0.70), spec.body_marks)
                ribbon(vertices, faces, indices, path, width, 0, "side", side,
                       source_tree, surface_map, stage)
                ribbon(vertices, faces, indices, path, width * 0.28, 1, "side", side,
                       source_tree, surface_map, stage, 0.0038)
        for height in (0.38, 0.43) if spec.front_scrapes else ():
            ribbon(vertices, faces, indices, [(-0.55, height), (0.0, height + 0.02),
                                             (0.48, height - 0.02)],
                   0.025 + stage * 0.008, 1, "front", 1, source_tree, surface_map, stage)
    data = bpy.data.meshes.new(target.name + "Marks")
    data.from_pydata(vertices, [], faces)
    for mat in materials:
        data.materials.append(mat)
    for polygon, index in zip(data.polygons, indices):
        polygon.material_index = index
    marks = bpy.data.objects.new(data.name, data)
    collection.objects.link(marks)
    bpy.ops.object.select_all(action="DESELECT")
    marks.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    mesh = bmesh.new()
    mesh.from_mesh(target.data)
    bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
    mesh.to_mesh(target.data)
    mesh.free()
    target.data.update()


def validate(path, spec, wheel_triangles, wheel_surfaces):
    binary = path.read_bytes()
    magic, version, size = struct.unpack_from("<4sII", binary)
    length, kind = struct.unpack_from("<II", binary, 12)
    if (magic, version, size, kind) != (b"glTF", 2, len(binary), 0x4E4F534A):
        raise ValueError("Invalid damage GLB.")
    doc = json.loads(binary[20:20 + length])
    nodes = {node["name"]: node for node in doc["nodes"]}
    expected = {spec.root_node + "Damage"}
    children = set(spec.parts) | set(SOCKETS) | {"BodyPaintSample"}
    report = {}
    for stage in STAGES[1:]:
        expected.add(stage)
        expected.update(stage + name for name in children)
        actual = {doc["nodes"][index]["name"] for index in nodes[stage]["children"]}
        if actual != {stage + name for name in children}:
            raise ValueError(f"{stage} lost its complete chassis/socket hierarchy.")
        count, surfaces = wheel_triangles, wheel_surfaces
        for part in spec.parts:
            mesh = doc["meshes"][nodes[stage + part]["mesh"]]
            for primitive in mesh["primitives"]:
                if primitive.get("mode", 4) != 4:
                    raise ValueError("Damage meshes must contain triangles only.")
                count += doc["accessors"][primitive["indices"]]["count"] // 3
                surfaces += 1
        if count > MAX_CAR_TRIANGLES or surfaces > MAX_CAR_SURFACES:
            raise ValueError(f"Written {stage} exceeds the complete-car runtime budget.")
        report[stage] = {"car_triangles": count, "car_surfaces": surfaces}
    if set(nodes) != expected or len(doc["nodes"]) != len(expected):
        raise ValueError("The damage library must contain only four unique chassis variants.")
    if len(doc["scenes"]) != 1 or any(doc.get(key) for key in (
            "images", "cameras", "animations", "skins", "extensionsUsed")):
        raise ValueError("Damage must remain texture-free, static and portable.")
    return report


def preview_copy(source, parent, collection, prefix):
    obj = source.copy()
    obj.name = prefix + source.name
    collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = source.matrix_local.copy()
    for child in source.children:
        preview_copy(child, obj, collection, prefix)
    return obj


def save_authoring(chassis, stages, wheels, source_hash, spec):
    scene = bpy.data.scenes.new(spec.title + " - Five Damage Stages")
    scene["source_sha256"] = source_hash
    exporter = "export_nissan_cube.py" if spec.key == "nissan_cube" else "export_reference_cars.py"
    scene["regenerate"] = f"{exporter} from the pristine {spec.key}.blend"
    scene.world = bpy.data.scenes[spec.source_scene].world
    for index, source in enumerate([chassis] + stages):
        collection = bpy.data.collections.new(f"{index} - {STAGES[index]}")
        scene.collection.children.link(collection)
        root = bpy.data.objects.new(STAGES[index] + "Preview", None)
        collection.objects.link(root)
        root.location.x = index * 6.0
        preview_copy(source, root, collection, "Preview")
        for wheel in wheels:
            preview_copy(wheel, root, collection, STAGES[index])
        camera_data = bpy.data.cameras.new(STAGES[index] + "Camera")
        camera_data.type = "ORTHO"
        camera_data.ortho_scale = 5.5
        camera = bpy.data.objects.new(camera_data.name, camera_data)
        collection.objects.link(camera)
        focus = Vector((index * 6.0, 0, 0.85))
        camera.location = focus + Vector((4.2, -6.8, 2.8))
        camera.rotation_euler = (focus - camera.location).to_track_quat("-Z", "Y").to_euler()
        marker = scene.timeline_markers.new(STAGES[index], frame=index + 1)
        marker.camera = camera
        if index == 0:
            scene.camera = camera
        for offset, energy, size in [((0, -4, 6), 1000, 5), ((1, 3, 4), 850, 4)]:
            light_data = bpy.data.lights.new(STAGES[index] + "Softbox", "AREA")
            light_data.energy, light_data.shape, light_data.size = energy, "DISK", size
            light = bpy.data.objects.new(light_data.name, light_data)
            collection.objects.link(light)
            light.location = focus + Vector(offset)
            light.rotation_euler = (focus - light.location).to_track_quat("-Z", "Y").to_euler()
    scene.frame_start, scene.frame_end = 1, 5
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    scene.render.resolution_percentage = 100
    bpy.context.window.scene = scene
    bpy.context.view_layer.update()
    for other in list(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_recursive=True)
    authoring = AUTHORING.with_name(spec.key + "_damage.blend")
    result = bpy.ops.wm.save_as_mainfile(filepath=str(authoring), compress=True, copy=True)
    if result != {"FINISHED"}:
        raise RuntimeError(f"Could not save the damage authoring scene: {result}")


def export_damage(chassis, wheels, source_hash, spec=DamageSpec()):
    scene = bpy.data.scenes.new(spec.root_node + "DamageAsset")
    collection = bpy.data.collections.new("Damage export only")
    scene.collection.children.link(collection)
    bpy.context.window.scene = scene
    root = bpy.data.objects.new(spec.root_node + "Damage", None)
    collection.objects.link(root)
    sources = {obj.name: obj for obj in chassis.children}
    geometry = {part: prepare_geometry(sources[part], spec) for part in spec.parts}
    undercoat = material("Exposed primer", (0.050, 0.055, 0.053), 0.15, 0.87)
    steel = material("Scraped steel", (0.42, 0.45, 0.44), 0.72, 0.55)
    cracks = material("Glass fractures", (0.48, 0.62, 0.65), 0.05, 0.72)
    wheel_triangles = sum(triangles(part) for wheel in wheels for part in wheel.children)
    wheel_surfaces = sum(len(part.data.materials) for wheel in wheels for part in wheel.children)
    stages, report = [], {}
    for index, name in enumerate(STAGES[1:], 1):
        group = bpy.data.objects.new(name, None)
        collection.objects.link(group)
        group.parent = root
        stages.append(group)
        parts = {part: variant(sources[part], geometry[part], index, group, collection, spec)
                 for part in spec.parts}
        add_marks(parts[spec.body], geometry[spec.body], index,
                  [undercoat, steel], collection, spec)
        add_marks(parts[spec.glass], geometry[spec.glass], index,
                  [cracks], collection, spec, glass=True)
        points = dict(SOCKETS, BodyPaintSample=sources["BodyPaintSample"].location.copy())
        for label in SOCKETS:
            if label in sources:
                points[label] = sources[label].location.copy()
        for label, point in points.items():
            marker = bpy.data.objects.new(name + label, None)
            collection.objects.link(marker)
            marker.parent = group
            marker.location = deform(point, index, spec.scale, spec.roof_crush_scale)
        count = sum(triangles(part) for part in parts.values()) + wheel_triangles
        surfaces = sum(len(part.data.materials) for part in parts.values()) + wheel_surfaces
        if count > MAX_CAR_TRIANGLES or surfaces > MAX_CAR_SURFACES:
            raise ValueError(f"{name} exceeds the live car budget: {count} triangles, {surfaces} surfaces.")
        report[name] = {"car_triangles": count, "car_surfaces": surfaces}
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root] + list(root.children_recursive):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    output = OUTPUT.with_name(spec.key + "_damage.glb")
    temporary = output.with_suffix(".tmp.glb")
    try:
        result = bpy.ops.export_scene.gltf(
            filepath=str(temporary), export_format="GLB", use_selection=True,
            use_active_scene=True, export_apply=True, export_yup=True, export_texcoords=False,
            export_normals=True, export_tangents=False, export_materials="EXPORT",
            export_extras=False, export_cameras=False, export_lights=False,
            export_animations=False, export_skins=False, export_morph=False,
            export_draco_mesh_compression_enable=False,
        )
        if result != {"FINISHED"} or not temporary.is_file():
            raise RuntimeError(f"Damage export failed: {result}")
        actual = validate(temporary, spec, wheel_triangles, wheel_surfaces)
        if actual != report:
            raise ValueError(f"The written damage geometry differs from its source: {actual}.")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    save_authoring(chassis, stages, wheels, source_hash, spec)
    print("GODOT_CAR_DAMAGE_EXPORTED", json.dumps({
        "path": str(output), "bytes": output.stat().st_size, "stages": report,
        "authoring": str(AUTHORING.with_name(spec.key + "_damage.blend")),
        "source_sha256": source_hash,
    }))
