"""Export a saved Sonata/CR-V, preserving its authoring file and wheel pivots.

Run Blender with --background <car>.blend --python this_file.py.
Append -- --render-previews to render both three-quarter studio cameras first.
"""

import hashlib
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from export_kit import activate, apply, portable_material, triangles_of, validate_export  # noqa: E402
from export_nissan_cube import WHEEL_NAMES, simplify_curve  # noqa: E402
from generate_reference_cars import SPECS  # noqa: E402
from cube_damage import DamageSpec, export_damage, tree  # noqa: E402


GROUPS = {
    "Body paint": "BodyPaint",
    "Panel seams": "RubberTrimAndUnderbody",
    "Rubber": "RubberTrimAndUnderbody",
    "Grille": "RubberTrimAndUnderbody",
    "Alloy": "Metalwork",
    "Chrome": "Metalwork",
    "Brake steel": "Metalwork",
    "Mirror": "Metalwork",
    "Cabin": "CabinAndSeats",
    "Upholstery": "CabinAndSeats",
    "Cabin glass": "Glazing",
    "Privacy glass": "Glazing",
    "Lamp glass": "LampGlazing",
    "Headlight": "HeadlightsAndIndicators",
    "Smoked optics": "HeadlightsAndIndicators",
    "Amber": "HeadlightsAndIndicators",
    "Reverse": "HeadlightsAndIndicators",
    "Red lens": "RearBrakeLights",
    "Red lens dark": "RearBrakeLights",
}
GLASS = {
    "Cabin glass": ((0.045, 0.078, 0.093), 0.40),
    "Privacy glass": ((0.021, 0.035, 0.049), 0.58),
    "Lamp glass": ((0.65, 0.73, 0.78), 0.12),
}
MAX_TRIANGLES = 45000
MAX_SURFACES = 48
SOCKET_NAMES = (
    "BodyPaintSample", "LeftBrakeSocket", "RightBrakeSocket",
    "LeftHeadlightSocket", "RightHeadlightSocket",
)
REDUCTION = {
    "BodyPaint": 0.31,
    "RubberTrimAndUnderbody": 0.31,
    "CabinAndSeats": 0.45,
    "Tires": 0.52,
    "AlloyRims": 0.50,
    "Metalwork": 0.50,
}


def validate_car(path, spec, mesh_names, centers):
    expected = [spec.root_node, "Chassis", *WHEEL_NAMES.values(), *mesh_names, *SOCKET_NAMES]
    document = validate_export(path, expected)
    nodes = {node["name"]: node for node in document["nodes"]}
    names = [node["name"] for node in document["nodes"]]
    if {names[index] for index in nodes[spec.root_node]["children"]} != {"Chassis", *WHEEL_NAMES.values()}:
        raise ValueError("The car must have one chassis and four independent wheel pivots.")
    for code, name in WHEEL_NAMES.items():
        pivot = nodes[name]
        if {names[index] for index in pivot["children"]} != {code + "Tires", code + "AlloyRims"}:
            raise ValueError(f"The exported {name} lost its tire/rim hierarchy.")
        expected_position = Vector((centers[code].x, centers[code].z, -centers[code].y))
        if (Vector(pivot.get("translation", (0, 0, 0))) - expected_position).length > 0.0001:
            raise ValueError(f"Incorrect meter-scaled wheel center: {name}.")
    triangles = 0
    surfaces = 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise ValueError("Runtime cars must contain triangles only.")
            triangles += document["accessors"][primitive["indices"]]["count"] // 3
            surfaces += 1
    if not 10000 <= triangles <= MAX_TRIANGLES or surfaces > MAX_SURFACES:
        raise ValueError(f"Invalid GLB budget: {triangles} triangles / {surfaces} surfaces.")
    return triangles, surfaces


def add_runtime_sockets(chassis, collection, spec):
    parts = {obj.name: obj for obj in chassis.children}
    hit, _, _, _ = tree(parts["BodyPaint"]).ray_cast(
        Vector((0.10, -3.0, spec.cabin_base - 0.18)), Vector((0, 1, 0)))
    if hit is None:
        raise ValueError(f"{spec.title}: the paint sample misses the body.")
    points = {"BodyPaintSample": hit}
    for group, material_names, suffix, front in (
        ("HeadlightsAndIndicators", {"Cube Headlight"}, "HeadlightSocket", True),
        ("RearBrakeLights", {"Cube Red lens", "Cube Red lens dark"}, "BrakeSocket", False),
    ):
        mesh = parts[group].data
        indices = {index for polygon in mesh.polygons
                   if mesh.materials[polygon.material_index].name in material_names
                   for index in polygon.vertices}
        for name, sign in (("Left", 1), ("Right", -1)):
            vertices = [mesh.vertices[index].co for index in indices
                        if mesh.vertices[index].co.y * sign > 0.0]
            if not vertices:
                raise ValueError(f"{spec.title}: no {name} {suffix} geometry.")
            low = Vector(tuple(min(v[axis] for v in vertices) for axis in range(3)))
            high = Vector(tuple(max(v[axis] for v in vertices) for axis in range(3)))
            center = (low + high) * 0.5
            center.x = high.x + 0.01 if front else low.x - 0.01
            points[name + suffix] = center
    for name, point in points.items():
        marker = bpy.data.objects.new(name, None)
        collection.objects.link(marker)
        marker.parent = chassis
        marker.location = point


def damage_spec(spec):
    return DamageSpec(
        key=spec.key, title=spec.title, root_node=spec.root_node,
        source_scene=spec.scene_name, parts=tuple(sorted(set(GROUPS.values()))),
        body="BodyPaint", glass="Glazing",
        scale=((spec.stations[-1][0] - spec.stations[0][0]) / 4.24,
               max(row[1] for row in spec.stations) / 0.85, spec.cabin_height / 1.675),
        # Lower windshields need less roof travel to retain a real cockpit opening.
        roof_crush_scale=0.45 if spec.suv else 0.40,
        side_window=(-0.80, 1.40, 0.55, 0.62) if spec.suv else (-0.65, 1.22, 0.50, 0.48),
        front_window=(-0.12, 1.33, 0.65, 0.75) if spec.suv else (-0.12, 1.19, 0.65, 0.60),
        body_marks=(0.0, 0.80, 1.0, 0.70) if spec.suv else (0.0, 0.70, 1.0, 1.0),
        front_scrapes=False,
    )


def export_car(spec):
    source_path = Path(bpy.data.filepath)
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    scene = bpy.data.scenes.get(spec.scene_name)
    root = bpy.data.objects.get(spec.root_name)
    if scene is None or root is None or root.name not in scene.objects:
        raise ValueError(f"Missing authored {spec.title} scene or assembly.")
    bpy.context.window.scene = scene
    bpy.context.view_layer.update()
    sources = list(root.children_recursive)
    pivots = {obj["wheel_code"]: obj for obj in sources
              if obj.type == "EMPTY" and "wheel_code" in obj}
    if set(pivots) != set(WHEEL_NAMES):
        raise ValueError(f"Expected four authored wheel pivots, got {sorted(pivots)}.")
    inverse_root = root.matrix_world.inverted()
    centers = {code: (inverse_root @ pivot.matrix_world).translation
               for code, pivot in pivots.items()}
    center_y = sum(point.y for point in centers.values()) / 4
    alignment = Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Translation((0, -center_y, 0))
    centers = {code: alignment @ point for code, point in centers.items()}
    collection = bpy.data.collections.new("Godot car export only")
    scene.collection.children.link(collection)
    meshes = defaultdict(list)
    cache = {}
    before = 0
    for source in sources:
        if source.type not in {"MESH", "CURVE"}:
            continue
        if source.type == "CURVE":
            simplify_curve(source)
        elements = source.data.polygons if source.type == "MESH" else source.data.splines
        indices = {element.material_index for element in elements}
        materials = {source.data.materials[index] for index in indices}
        if len(materials) != 1 or None in materials:
            raise ValueError(f"{source.name} needs one explicitly assigned material.")
        material = materials.pop()
        label = material.name.removeprefix(spec.prefix + " | ")
        owner = next((code for code, pivot in pivots.items() if source.parent == pivot), None)
        if owner:
            group = "Tires" if label == "Tire rubber" else "AlloyRims"
        else:
            if label not in GROUPS:
                raise ValueError(f"No export group for {label!r} on {source.name}.")
            group = GROUPS[label]
        for modifier in source.modifiers:
            if modifier.type == "BEVEL":
                modifier.segments = min(modifier.segments, 2)
            if modifier.type == "SOLIDIFY" and label in GLASS:
                modifier.show_viewport = False
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        data = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph), depsgraph=depsgraph)
        if not data.polygons:
            raise ValueError(f"Empty evaluated geometry: {source.name}.")
        before += triangles_of(data)
        target = portable_material(material, cache, spec.prefix,
                                   {name: value[1] for name, value in GLASS.items()},
                                   double_sided=("Rubber",))
        if label in GLASS:
            color, alpha = GLASS[label]
            shader = target.node_tree.nodes["Principled BSDF"]
            shader.inputs["Base Color"].default_value = (*color, 1)
            shader.inputs["Metallic"].default_value = 0.08
            shader.inputs["Roughness"].default_value = 0.17
            target.diffuse_color = (*color, alpha)
        data.materials.clear()
        data.materials.append(target)
        for polygon in data.polygons:
            polygon.material_index = 0
        obj = bpy.data.objects.new("Export " + source.name, data)
        collection.objects.link(obj)
        obj.matrix_world = alignment @ inverse_root @ source.matrix_world
        if len(obj.data.polygons) > 3:
            dissolve = obj.modifiers.new("Remove redundant planar topology", "DECIMATE")
            dissolve.decimate_type = "DISSOLVE"
            dissolve.angle_limit = math.radians(0.6)
            dissolve.delimit = {"NORMAL"}
            apply(obj, dissolve)
        if triangles_of(obj.data) > 96 and group not in {"Glazing", "LampGlazing"}:
            collapse = obj.modifiers.new("Runtime silhouette reduction", "DECIMATE")
            collapse.decimate_type = "COLLAPSE"
            collapse.ratio = REDUCTION.get(group, 0.55)
            collapse.use_collapse_triangulate = True
            apply(obj, collapse)
        meshes[(owner, group)].append(obj)

    exported_root = bpy.data.objects.new(spec.root_node, None)
    collection.objects.link(exported_root)
    chassis = bpy.data.objects.new("Chassis", None)
    collection.objects.link(chassis)
    chassis.parent = exported_root
    exported_pivots = {}
    for code, name in WHEEL_NAMES.items():
        pivot = bpy.data.objects.new(name, None)
        collection.objects.link(pivot)
        pivot.parent = exported_root
        pivot.location = centers[code]
        exported_pivots[code] = pivot
    report = {}
    for (owner, group), parts in meshes.items():
        activate(parts[0])
        for part in parts:
            part.select_set(True)
        if len(parts) > 1:
            bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = (owner or "") + group
        obj.data.name = obj.name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        obj.parent = exported_pivots[owner] if owner else chassis
        if owner:
            obj.data.transform(Matrix.Translation(-centers[owner]))
        triangulate = obj.modifiers.new("Stable runtime triangulation", "TRIANGULATE")
        apply(obj, triangulate)
        report[obj.name] = {"triangles": triangles_of(obj.data), "surfaces": len(obj.data.materials)}
    total = sum(item["triangles"] for item in report.values())
    surfaces = sum(item["surfaces"] for item in report.values())
    print("EXPORT_GEOMETRY", json.dumps(report, indent=2), flush=True)
    if total > MAX_TRIANGLES or surfaces > MAX_SURFACES:
        raise ValueError(f"{spec.title} exceeds its budget: {total} triangles / {surfaces} surfaces.")
    add_runtime_sockets(chassis, collection, spec)
    export_scene = bpy.data.scenes.new(spec.root_node + "Asset")
    export_scene.collection.children.link(collection)
    bpy.context.window.scene = export_scene
    activate(exported_root)
    for obj in exported_root.children_recursive:
        obj.select_set(True)
    output = HERE.parents[1] / "assets" / "models" / f"{spec.key}.glb"
    temporary = output.with_suffix(".tmp.glb")
    try:
        result = bpy.ops.export_scene.gltf(
            filepath=str(temporary), export_format="GLB", use_selection=True,
            use_active_scene=True, export_apply=True, export_yup=True,
            export_texcoords=False, export_normals=True, export_tangents=False,
            export_materials="EXPORT", export_extras=False, export_cameras=False,
            export_lights=False, export_animations=False, export_skins=False,
            export_morph=False, export_draco_mesh_compression_enable=False,
        )
        if result != {"FINISHED"} or not temporary.is_file():
            raise RuntimeError(f"glTF export did not complete: {result}")
        actual_triangles, actual_surfaces = validate_car(temporary, spec, report, centers)
        if (actual_triangles, actual_surfaces) != (total, surfaces):
            raise ValueError("The written GLB differs from the measured export geometry.")
        if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_hash:
            raise RuntimeError("The authoring file changed during export.")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    print("GODOT_CAR_EXPORTED", json.dumps({
        "path": str(output), "bytes": output.stat().st_size, "triangles": total,
        "surfaces": surfaces, "geometry_before_reduction": before,
        "source_sha256": source_hash, "forward": "+X", "up": "+Y",
    }), flush=True)
    export_damage(chassis, list(exported_pivots.values()), source_hash, damage_spec(spec))
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_hash:
        raise RuntimeError("The pristine authoring file changed during damage export.")


def main():
    path = Path(bpy.data.filepath)
    if not path.is_file() or path.stem not in SPECS:
        raise ValueError("Open hyundai_sonata.blend or honda_crv.blend before exporting.")
    spec = SPECS[path.stem]
    if "--render-previews" in sys.argv:
        scene = bpy.data.scenes.get(spec.scene_name)
        if scene is None:
            raise ValueError(f"Missing saved studio: {spec.scene_name}")
        bpy.context.window.scene = scene
        for frame, suffix in ((1, "preview"), (2, "rear")):
            scene.frame_set(frame)
            scene.render.filepath = str(HERE / f"{spec.key}_{suffix}.png")
            bpy.ops.render.render(write_still=True)
    export_car(spec)


if __name__ == "__main__":
    main()
