"""Five authored chassis looks, built from the saved car's optimized geometry.

Called by export_nissan_cube.py in its background Blender process. The pristine
source and wheels are never deformed. Scrapes are projected mesh ribbons, not
renderer-specific decals, and therefore also work in Godot Compatibility.
"""

import json
import math
import struct
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


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


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def deform(point, stage):
    # One continuous field moves panel seams, glass, trim and lamp sockets together.
    x, y, z = point
    roof = (0.0, 0.008, 0.055, 0.22, 0.36)[stage]
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
    return Vector((x, y, z))


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def tree(obj):
    return BVHTree.FromPolygons(
        [vertex.co for vertex in obj.data.vertices],
        [list(face.vertices) for face in obj.data.polygons], all_triangles=True,
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


def variant(source, stage, parent, collection):
    result = source.copy()
    result.data = source.data.copy()
    result.name = STAGES[stage] + source.name
    result.data.name = result.name
    collection.objects.link(result)
    result.parent = parent
    result.matrix_parent_inverse = Matrix.Identity(4)
    result.matrix_basis = Matrix.Identity(4)
    mesh = bmesh.new()
    mesh.from_mesh(result.data)
    if source.name in {"BrownBodywork", "WraparoundGlazing"}:
        long_edges = [edge for edge in mesh.edges if edge.calc_length() > 0.45]
        bmesh.ops.subdivide_edges(mesh, edges=long_edges, cuts=1, use_grid_fill=True)
    for vertex in mesh.verts:
        vertex.co = deform(vertex.co, stage)
    bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
    mesh.normal_update()
    mesh.to_mesh(result.data)
    mesh.free()
    result.data.update()
    return result


def projected(point, face, side, source_tree, target_tree, stage, offset):
    u, v = point
    if face == "side":
        origin, direction = Vector((u, side * 3.0, v)), Vector((0, -side, 0))
    else:
        origin, direction = Vector((3.0, u, v)), Vector((-1, 0, 0))
    hit, _, _, _ = source_tree.ray_cast(origin, direction)
    if hit is None:
        raise ValueError(f"Damage mark misses its source panel: {face}, {side}, {point}.")
    moved = deform(hit, stage)
    origin = moved - direction * 3.0
    hit, normal, _, _ = target_tree.ray_cast(origin, direction)
    if hit is None:
        raise ValueError(f"Damage mark misses its deformed panel: {stage}, {point}.")
    if normal.dot(direction) > 0.0:
        normal = -normal
    return hit + normal * offset, normal


def ribbon(vertices, faces, indices, path, width, material_index,
           face, side, source_tree, target_tree, stage, offset=0.0025):
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
                                          source_tree, target_tree, stage, offset)
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


def add_marks(target, source, stage, materials, collection, glass=False):
    source_tree, target_tree = tree(source), tree(target)
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
                ribbon(vertices, faces, indices, path, 0.009, 0, "side", side,
                       source_tree, target_tree, stage)
        for path in [
            [(-0.20, 1.30), (-0.40, 1.38), (-0.55, 1.48)],
            [(-0.20, 1.30), (0.02, 1.41), (0.27, 1.49)],
            [(-0.20, 1.30), (-0.05, 1.22), (0.21, 1.15)],
        ]:
            ribbon(vertices, faces, indices, path, 0.009, 0, "front", 1,
                   source_tree, target_tree, stage)
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
                ribbon(vertices, faces, indices, path, width, 0, "side", side,
                       source_tree, target_tree, stage)
                ribbon(vertices, faces, indices, path, width * 0.28, 1, "side", side,
                       source_tree, target_tree, stage, 0.0038)
        for height in (0.38, 0.43):
            ribbon(vertices, faces, indices, [(-0.55, height), (0.0, height + 0.02),
                                             (0.48, height - 0.02)],
                   0.025 + stage * 0.008, 1, "front", 1, source_tree, target_tree, stage)
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


def validate(path):
    binary = path.read_bytes()
    magic, version, size = struct.unpack_from("<4sII", binary)
    length, kind = struct.unpack_from("<II", binary, 12)
    if (magic, version, size, kind) != (b"glTF", 2, len(binary), 0x4E4F534A):
        raise ValueError("Invalid damage GLB.")
    doc = json.loads(binary[20:20 + length])
    nodes = {node["name"]: node for node in doc["nodes"]}
    expected = {"NissanCubeDamage"}
    children = set(PARTS) | set(SOCKETS) | {"BodyPaintSample"}
    for stage in STAGES[1:]:
        expected.add(stage)
        expected.update(stage + name for name in children)
        actual = {doc["nodes"][index]["name"] for index in nodes[stage]["children"]}
        if actual != {stage + name for name in children}:
            raise ValueError(f"{stage} lost its complete chassis/socket hierarchy.")
    if set(nodes) != expected or len(doc["nodes"]) != len(expected):
        raise ValueError("The damage library must contain only four unique chassis variants.")
    if len(doc["scenes"]) != 1 or any(doc.get(key) for key in (
            "images", "cameras", "animations", "skins", "extensionsUsed")):
        raise ValueError("Damage must remain texture-free, static and portable.")


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


def save_authoring(chassis, stages, wheels, source_hash):
    scene = bpy.data.scenes.new("Nissan Cube - Five Damage Stages")
    scene["source_sha256"] = source_hash
    scene["regenerate"] = "export_nissan_cube.py from the pristine nissan_cube.blend"
    scene.world = bpy.data.scenes["Nissan Cube Z12 - Studio"].world
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
    result = bpy.ops.wm.save_as_mainfile(filepath=str(AUTHORING), compress=True, copy=True)
    if result != {"FINISHED"}:
        raise RuntimeError(f"Could not save the damage authoring scene: {result}")


def export_damage(chassis, wheels, source_hash):
    scene = bpy.data.scenes.new("NissanCubeDamageAsset")
    collection = bpy.data.collections.new("Damage export only")
    scene.collection.children.link(collection)
    bpy.context.window.scene = scene
    root = bpy.data.objects.new("NissanCubeDamage", None)
    collection.objects.link(root)
    sources = {obj.name: obj for obj in chassis.children}
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
        parts = {part: variant(sources[part], index, group, collection) for part in PARTS}
        add_marks(parts["BrownBodywork"], sources["BrownBodywork"], index,
                  [undercoat, steel], collection)
        add_marks(parts["WraparoundGlazing"], sources["WraparoundGlazing"], index,
                  [cracks], collection, glass=True)
        points = dict(SOCKETS, BodyPaintSample=sources["BodyPaintSample"].location.copy())
        for label, point in points.items():
            marker = bpy.data.objects.new(name + label, None)
            collection.objects.link(marker)
            marker.parent = group
            marker.location = deform(point, index)
        count = sum(triangles(part) for part in parts.values()) + wheel_triangles
        surfaces = sum(len(part.data.materials) for part in parts.values()) + wheel_surfaces
        if count > MAX_CAR_TRIANGLES or surfaces > MAX_CAR_SURFACES:
            raise ValueError(f"{name} exceeds the live car budget: {count} triangles, {surfaces} surfaces.")
        report[name] = {"car_triangles": count, "car_surfaces": surfaces}
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root] + list(root.children_recursive):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    temporary = OUTPUT.with_suffix(".tmp.glb")
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
        validate(temporary)
        temporary.replace(OUTPUT)
    finally:
        temporary.unlink(missing_ok=True)
    save_authoring(chassis, stages, wheels, source_hash)
    print("GODOT_CUBE_DAMAGE_EXPORTED", json.dumps({
        "path": str(OUTPUT), "bytes": OUTPUT.stat().st_size, "stages": report,
        "authoring": str(AUTHORING), "source_sha256": source_hash,
    }))
