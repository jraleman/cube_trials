"""Export the saved authoring model, not its generator, as a portable Godot GLB.

Run Blender with --background nissan_cube.blend --python this_file.py.
The source .blend is never saved or modified on disk.
"""

import hashlib
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


OUTPUT = Path(__file__).resolve().parents[2] / "assets" / "models" / "nissan_cube.glb"
MAX_TRIANGLES = 45000
MAX_SURFACES = 48
REDUCTION = {
    "BrownBodywork": 0.38,
    "RubberTrimAndUnderbody": 0.30,
    "ChromeHandlesGrilleAndBadges": 0.28,
    "CabinAndDriver": 0.33,
    "HeadlightsAndIndicators": 0.38,
    "RearBrakeLights": 0.40,
}
MICRO_DETAILS = (
    "fine diagonal tread sipes",
    "molded sidewall ring",
    "rotor machining",
    "center cap seam",
    "tire valve",
    "Rear demister filament",
    "headlamp fluting",
    "door lock",
    "Rear plate fastener",
    "reversing lens prism",
)
WHEEL_NAMES = {
    "LF": "FrontLeftWheel",
    "RF": "FrontRightWheel",
    "LR": "RearLeftWheel",
    "RR": "RearRightWheel",
}
MATERIAL_GROUPS = {
    "Bronze metallic": "BrownBodywork",
    "Bronze edge": "BrownBodywork",
    "Panel gaps": "RubberTrimAndUnderbody",
    "Rubber seals": "RubberTrimAndUnderbody",
    "Dark hardware": "RubberTrimAndUnderbody",
    "Grille": "RubberTrimAndUnderbody",
    "Plate": "RubberTrimAndUnderbody",
    "Silver alloy": "ChromeHandlesGrilleAndBadges",
    "Polished chrome": "ChromeHandlesGrilleAndBadges",
    "Brake steel": "ChromeHandlesGrilleAndBadges",
    "Mirror": "ChromeHandlesGrilleAndBadges",
    "Interior charcoal": "CabinAndDriver",
    "Interior upholstery": "CabinAndDriver",
    "Cabin glass": "WraparoundGlazing",
    "Privacy glass": "WraparoundGlazing",
    "Lamp glass": "LampGlazing",
    "Lamp reflector": "HeadlightsAndIndicators",
    "Bulb": "HeadlightsAndIndicators",
    "Amber lens": "HeadlightsAndIndicators",
    "Reverse lens": "HeadlightsAndIndicators",
    "Red lens dark": "HeadlightsAndIndicators",
    "Red lens": "RearBrakeLights",
}


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply(obj, modifier):
    activate(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def polyline(points, tolerance):
    if len(points) <= 2:
        return points
    direction = points[-1] - points[0]
    length_squared = direction.length_squared
    greatest, split = 0.0, 0
    for index in range(1, len(points) - 1):
        t = (points[index] - points[0]).dot(direction) / length_squared if length_squared else 0
        nearest = points[0] + direction * max(0, min(1, t))
        distance = (points[index] - nearest).length
        if distance > greatest:
            greatest, split = distance, index
    if greatest <= tolerance:
        return [points[0], points[-1]]
    return polyline(points[:split + 1], tolerance)[:-1] + polyline(points[split:], tolerance)


def simplify_curve(obj):
    obj.data.bevel_resolution = 0
    for spline in list(obj.data.splines):
        if spline.type != "POLY":
            raise ValueError(f"Unsupported curve type in {obj.name}: {spline.type}")
        points = [Vector(point.co[:3]) for point in spline.points]
        if spline.use_cyclic_u:
            split = len(points) // 2
            points = (polyline(points[:split + 1], 0.0008)[:-1]
                      + polyline(points[split:] + [points[0]], 0.0008)[:-1])
        else:
            points = polyline(points, 0.0008)
        replacement = obj.data.splines.new("POLY")
        replacement.points.add(len(points) - 1)
        replacement.use_cyclic_u = spline.use_cyclic_u
        for point, coordinate in zip(replacement.points, points):
            point.co = (*coordinate, 1.0)
        obj.data.splines.remove(spline)


def portable_material(source, cache):
    if source.name in cache:
        return cache[source.name]
    label = source.name.removeprefix("Z12 | ")
    shader = source.node_tree.nodes.get("Principled BSDF") if source.use_nodes else None
    if shader is None:
        raise ValueError(f"{source.name} needs a Principled BSDF for portable export.")
    for name in ("Base Color", "Metallic", "Roughness", "Alpha"):
        if shader.inputs[name].is_linked:
            raise ValueError(f"{source.name}/{name} is textured; bake it before this export.")
    material = bpy.data.materials.new("Cube " + label)
    material.use_nodes = True
    target = material.node_tree.nodes.get("Principled BSDF")
    color = tuple(shader.inputs["Base Color"].default_value)
    alpha = 1.0
    metallic = shader.inputs["Metallic"].default_value
    roughness = shader.inputs["Roughness"].default_value
    if label in {"Cabin glass", "Privacy glass", "Lamp glass"}:
        colors = {
            "Cabin glass": ((0.045, 0.081, 0.089, 1.0), 0.48),
            "Privacy glass": ((0.020, 0.035, 0.040, 1.0), 0.64),
            "Lamp glass": ((0.65, 0.73, 0.76, 1.0), 0.16),
        }
        color, alpha = colors[label]
        metallic = 0.08
        roughness = max(0.14, roughness)
    target.inputs["Base Color"].default_value = color
    target.inputs["Alpha"].default_value = alpha
    target.inputs["Metallic"].default_value = metallic
    target.inputs["Roughness"].default_value = roughness
    target.inputs["Transmission Weight"].default_value = 0.0
    target.inputs["Coat Weight"].default_value = 0.0
    target.inputs["IOR"].default_value = 1.5
    target.inputs["Emission Color"].default_value = shader.inputs["Emission Color"].default_value
    target.inputs["Emission Strength"].default_value = shader.inputs["Emission Strength"].default_value
    material.diffuse_color = (*color[:3], alpha)
    material.use_backface_culling = label not in {"Cabin glass", "Privacy glass", "Lamp glass"}
    cache[source.name] = material
    return material


def validate_export(path):
    binary = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", binary)
    json_length, chunk_type = struct.unpack_from("<II", binary, 12)
    if (magic, version, length, chunk_type) != (b"glTF", 2, len(binary), 0x4E4F534A):
        raise ValueError("The exporter did not produce a valid glTF 2.0 binary.")
    document = json.loads(binary[20:20 + json_length])
    names = [node.get("name") for node in document["nodes"]]
    if len(document["scenes"]) != 1 or len(names) != 23 or len(set(names)) != len(names):
        raise ValueError("The GLB must contain one assembly without duplicate or studio nodes.")
    for key, name in WHEEL_NAMES.items():
        pivot = next(node for node in document["nodes"] if node.get("name") == name)
        children = {names[index] for index in pivot["children"]}
        if children != {key + "Tires", key + "AlloyRims"}:
            raise ValueError(f"The exported {name} lost its tire/rim hierarchy.")
    if any(document.get(key) for key in ("images", "cameras", "animations", "extensionsUsed")):
        raise ValueError("The portable car must not require images, studio nodes or extensions.")


def main():
    source_path = Path(bpy.data.filepath)
    if not source_path.is_file():
        raise ValueError("Open the saved nissan_cube.blend before exporting.")
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    scene = bpy.data.scenes.get("Nissan Cube Z12 - Studio")
    root = bpy.data.objects.get("Nissan Cube Z12 | Assembly")
    if scene is None or root is None or root.name not in scene.objects:
        raise ValueError("The saved file does not contain the expected Nissan Cube assembly.")
    bpy.context.window.scene = scene
    source_objects = list(root.children_recursive)
    pivots = {obj.name.split(" | ")[-1].split()[0]: obj
              for obj in source_objects if obj.type == "EMPTY" and obj.name.endswith("wheel pivot")}
    if set(pivots) != set(WHEEL_NAMES):
        raise ValueError(f"Expected four authored wheel pivots, got {sorted(pivots)}.")
    inverse_root = root.matrix_world.inverted()
    centers = {key: (inverse_root @ pivot.matrix_world).translation
               for key, pivot in pivots.items()}
    center_y = sum(point.y for point in centers.values()) / 4
    alignment = Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Translation((0, -center_y, 0))
    converted_centers = {key: alignment @ center for key, center in centers.items()}
    export_collection = bpy.data.collections.new("Godot export only")
    scene.collection.children.link(export_collection)
    meshes = defaultdict(list)
    material_cache = {}
    excluded, before_triangles = 0, 0

    for source in source_objects:
        if source.type not in {"MESH", "CURVE"}:
            continue
        if any(detail in source.name for detail in MICRO_DETAILS):
            excluded += 1
            continue
        elements = source.data.polygons if source.type == "MESH" else source.data.splines
        indices = {element.material_index for element in elements}
        used_materials = {source.data.materials[index] for index in indices}
        if len(used_materials) != 1 or None in used_materials:
            raise ValueError(f"{source.name} needs one explicitly assigned source material.")
        source_material = used_materials.pop()
        label = source_material.name.removeprefix("Z12 | ")
        owner = next((key for key, pivot in pivots.items() if source.parent == pivot), None)
        if owner:
            group = "Tires" if label in {"Tire rubber", "Tread recess"} else "AlloyRims"
        else:
            if label not in MATERIAL_GROUPS:
                raise ValueError(f"No runtime material group for {label} on {source.name}.")
            group = MATERIAL_GROUPS[label]
        if source.type == "CURVE":
            simplify_curve(source)
        for modifier in source.modifiers:
            if modifier.type == "BEVEL":
                modifier.segments = min(modifier.segments, 2)
            if modifier.type == "SOLIDIFY" and group in {"WraparoundGlazing", "LampGlazing"}:
                modifier.show_viewport = False
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = source.evaluated_get(depsgraph)
        data = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        data.calc_loop_triangles()
        before_triangles += len(data.loop_triangles)
        data.materials.clear()
        data.materials.append(portable_material(source_material, material_cache))
        for polygon in data.polygons:
            polygon.material_index = 0
        obj = bpy.data.objects.new("Export " + source.name, data)
        export_collection.objects.link(obj)
        obj.matrix_world = alignment @ inverse_root @ source.matrix_world
        dissolve = obj.modifiers.new("Remove redundant planar topology", "DECIMATE")
        dissolve.decimate_type = "DISSOLVE"
        dissolve.angle_limit = math.radians(0.8)
        dissolve.delimit = {"NORMAL"}
        apply(obj, dissolve)
        obj.data.calc_loop_triangles()
        count = len(obj.data.loop_triangles)
        if count > 140 and group not in {"WraparoundGlazing", "LampGlazing"}:
            reduction = obj.modifiers.new("Runtime silhouette reduction", "DECIMATE")
            reduction.decimate_type = "COLLAPSE"
            reduction.ratio = 0.31 if owner else REDUCTION[group]
            reduction.use_collapse_triangulate = True
            apply(obj, reduction)
        meshes[(owner, group)].append(obj)

    exported_root = bpy.data.objects.new("NissanCube", None)
    export_collection.objects.link(exported_root)
    chassis = bpy.data.objects.new("Chassis", None)
    export_collection.objects.link(chassis)
    chassis.parent = exported_root
    exported_pivots = {}
    for key, name in WHEEL_NAMES.items():
        pivot = bpy.data.objects.new(name, None)
        export_collection.objects.link(pivot)
        pivot.parent = exported_root
        pivot.location = converted_centers[key]
        exported_pivots[key] = pivot
    report = {}
    exported_meshes = []
    for (owner, group), parts in meshes.items():
        activate(parts[0])
        for part in parts:
            part.select_set(True)
        if len(parts) > 1:
            bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = owner + group if owner else group
        obj.data.name = (WHEEL_NAMES[owner] + " " if owner else "") + group
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        obj.parent = exported_pivots[owner] if owner else chassis
        if owner:
            obj.data.transform(Matrix.Translation(-converted_centers[owner]))
        triangulate = obj.modifiers.new("Stable game triangulation", "TRIANGULATE")
        apply(obj, triangulate)
        obj.data.calc_loop_triangles()
        triangles = len(obj.data.loop_triangles)
        report[obj.data.name] = {"triangles": triangles, "surfaces": len(obj.data.materials)}
        exported_meshes.append(obj)

    paint = next(obj for obj in exported_meshes if obj.name == "BrownBodywork")
    bpy.context.view_layer.update()
    hit, point, normal, _ = paint.ray_cast(Vector((0, -5, 0.72)), Vector((0, 1, 0)))
    if not hit:
        raise ValueError("Could not locate exposed side paint for the render contract.")
    marker = bpy.data.objects.new("BodyPaintSample", None)
    export_collection.objects.link(marker)
    marker.parent = chassis
    marker.location = point + normal * 0.003
    total_triangles = sum(item["triangles"] for item in report.values())
    total_surfaces = sum(item["surfaces"] for item in report.values())
    print("EXPORT_GEOMETRY", json.dumps(report, indent=2))
    if total_triangles > MAX_TRIANGLES or total_surfaces > MAX_SURFACES:
        raise ValueError(f"Runtime car exceeds its budget: {total_triangles} triangles, "
                         f"{total_surfaces} surfaces.")
    export_scene = bpy.data.scenes.new("NissanCubeAsset")
    export_scene.collection.children.link(export_collection)
    bpy.context.window.scene = export_scene
    activate(exported_root)
    for obj in exported_root.children_recursive:
        obj.select_set(True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(__file__).with_suffix(".tmp.glb")
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
            raise RuntimeError(f"glTF export did not complete: {result}")
        validate_export(temporary)
        temporary.replace(OUTPUT)
    finally:
        temporary.unlink(missing_ok=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_hash:
        raise RuntimeError("The authoring file changed during export.")
    print("GODOT_CUBE_EXPORTED", json.dumps({
        "path": str(OUTPUT), "bytes": OUTPUT.stat().st_size,
        "triangles": total_triangles, "surfaces": total_surfaces,
        "geometry_before_reduction": before_triangles, "micro_details_removed": excluded,
        "source_sha256": source_hash, "forward": "+X", "up": "+Y",
    }))


if __name__ == "__main__":
    main()
