"""Shared GLB export for the reference-based Cube Trials props.

`export_reference_props.py` calls `export_asset` on the saved `.blend` opened
in background Blender. The authoring file is hashed before and after the run
and is never saved, so exporting cannot mutate the editable source.

The exported file is deliberately portable: flat Principled colors, no images,
no cameras, no lights, no animations and no glTF extensions, which is what the
Godot Compatibility renderer wants.
"""

import hashlib
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

import bpy


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply(obj, modifier):
    activate(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def triangles_of(data):
    data.calc_loop_triangles()
    return len(data.loop_triangles)


def portable_material(source, cache, prefix, transparent, double_sided=()):
    """Copy an authoring material to a flat, texture-free runtime material."""
    if source.name in cache:
        return cache[source.name]
    label = source.name.removeprefix(prefix + " | ")
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
    alpha = float(shader.inputs["Alpha"].default_value)
    if label in transparent:
        alpha = transparent[label]
    target.inputs["Base Color"].default_value = color
    target.inputs["Alpha"].default_value = alpha
    target.inputs["Metallic"].default_value = shader.inputs["Metallic"].default_value
    target.inputs["Roughness"].default_value = shader.inputs["Roughness"].default_value
    target.inputs["Transmission Weight"].default_value = 0.0
    target.inputs["Coat Weight"].default_value = 0.0
    target.inputs["IOR"].default_value = 1.5
    target.inputs["Emission Color"].default_value = shader.inputs["Emission Color"].default_value
    target.inputs["Emission Strength"].default_value = shader.inputs["Emission Strength"].default_value
    material.diffuse_color = (*color[:3], alpha)
    material.use_backface_culling = (alpha >= 1.0 and label not in transparent
                                     and label not in double_sided)
    if alpha < 1.0:
        material.surface_render_method = "BLENDED"
    cache[source.name] = material
    return material


def validate_export(path, expected_nodes):
    binary = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", binary)
    json_length, chunk_type = struct.unpack_from("<II", binary, 12)
    if (magic, version, length, chunk_type) != (b"glTF", 2, len(binary), 0x4E4F534A):
        raise ValueError("The exporter did not produce a valid glTF 2.0 binary.")
    document = json.loads(binary[20:20 + json_length])
    names = [node.get("name") for node in document["nodes"]]
    if len(document["scenes"]) != 1:
        raise ValueError("The GLB must contain exactly one scene.")
    if len(names) != len(set(names)):
        raise ValueError(f"The GLB has duplicate node names: {sorted(names)}")
    if set(names) != set(expected_nodes):
        missing = sorted(set(expected_nodes) - set(names))
        extra = sorted(set(names) - set(expected_nodes))
        raise ValueError(f"Unexpected export hierarchy; missing {missing}, extra {extra}.")
    for key in ("images", "cameras", "animations", "extensionsUsed"):
        if document.get(key):
            raise ValueError(f"The portable prop must not require {key}.")
    return document


def export_asset(*, scene_name, root_name, prefix, output, root_node, groups,
                 max_triangles, max_surfaces=24, reduction=None, keep_dense=(),
                 transparent=None, double_sided=(), dissolve_angle=0.8,
                 collapse_floor=160):
    """Bake one authored prop scene into `output` as a portable GLB.

    `groups` maps an authoring material label to the runtime mesh it joins into,
    which is what keeps a hundred authored parts down to a handful of surfaces.
    """
    output = Path(output)
    reduction = reduction or {}
    transparent = transparent or {}
    source_path = Path(bpy.data.filepath)
    if not source_path.is_file():
        raise ValueError("Open the saved authoring .blend before exporting.")
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    scene = bpy.data.scenes.get(scene_name)
    root = bpy.data.objects.get(root_name)
    if scene is None or root is None or root.name not in scene.objects:
        raise ValueError(f"{source_path.name} does not contain the expected {root_name}.")
    bpy.context.window.scene = scene
    inverse_root = root.matrix_world.inverted()
    export_collection = bpy.data.collections.new("Godot export only")
    scene.collection.children.link(export_collection)
    meshes = defaultdict(list)
    material_cache = {}
    before_triangles = 0

    for source in root.children_recursive:
        if source.type not in {"MESH", "CURVE"}:
            continue
        elements = source.data.polygons if source.type == "MESH" else source.data.splines
        if not len(elements):
            continue
        indices = {element.material_index for element in elements}
        used = {source.data.materials[index] for index in indices}
        if len(used) != 1 or None in used:
            raise ValueError(f"{source.name} needs one explicitly assigned source material.")
        source_material = used.pop()
        label = source_material.name.removeprefix(prefix + " | ")
        if label not in groups:
            raise ValueError(f"No runtime mesh group for material {label!r} on {source.name}.")
        group = groups[label]
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = source.evaluated_get(depsgraph)
        data = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        if not data.polygons:
            bpy.data.meshes.remove(data)
            continue
        before_triangles += triangles_of(data)
        data.materials.clear()
        data.materials.append(
            portable_material(source_material, material_cache, prefix, transparent,
                              double_sided))
        for polygon in data.polygons:
            polygon.material_index = 0
        obj = bpy.data.objects.new("Export " + source.name, data)
        export_collection.objects.link(obj)
        obj.matrix_world = inverse_root @ source.matrix_world
        dissolve = obj.modifiers.new("Remove redundant planar topology", "DECIMATE")
        dissolve.decimate_type = "DISSOLVE"
        dissolve.angle_limit = math.radians(dissolve_angle)
        dissolve.delimit = {"NORMAL"}
        apply(obj, dissolve)
        if triangles_of(obj.data) > collapse_floor and group not in keep_dense:
            collapse = obj.modifiers.new("Runtime silhouette reduction", "DECIMATE")
            collapse.decimate_type = "COLLAPSE"
            collapse.ratio = reduction.get(group, 0.5)
            collapse.use_collapse_triangulate = True
            apply(obj, collapse)
        meshes[group].append(obj)

    if not meshes:
        raise ValueError("Nothing was collected for export.")
    exported_root = bpy.data.objects.new(root_node, None)
    export_collection.objects.link(exported_root)
    report = {}
    for group, parts in sorted(meshes.items()):
        activate(parts[0])
        for part in parts:
            part.select_set(True)
        if len(parts) > 1:
            bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = group
        obj.data.name = group
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        obj.parent = exported_root
        triangulate = obj.modifiers.new("Stable game triangulation", "TRIANGULATE")
        apply(obj, triangulate)
        report[group] = {"triangles": triangles_of(obj.data),
                         "surfaces": len(obj.data.materials)}

    total_triangles = sum(item["triangles"] for item in report.values())
    total_surfaces = sum(item["surfaces"] for item in report.values())
    print("EXPORT_GEOMETRY", json.dumps(report, indent=2))
    if total_triangles > max_triangles or total_surfaces > max_surfaces:
        raise ValueError(f"{root_node} exceeds its budget: {total_triangles} triangles "
                         f"(max {max_triangles}), {total_surfaces} surfaces "
                         f"(max {max_surfaces}).")
    export_scene = bpy.data.scenes.new(root_node + "Asset")
    export_scene.collection.children.link(export_collection)
    bpy.context.window.scene = export_scene
    activate(exported_root)
    for obj in exported_root.children_recursive:
        obj.select_set(True)
    output.parent.mkdir(parents=True, exist_ok=True)
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
        validate_export(temporary, [root_node, *report])
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_hash:
        raise RuntimeError("The authoring file changed during export.")
    summary = {
        "path": str(output), "bytes": output.stat().st_size,
        "triangles": total_triangles, "surfaces": total_surfaces,
        "geometry_before_reduction": before_triangles,
        "source_sha256": source_hash, "up": "+Y",
    }
    print("GODOT_PROP_EXPORTED", json.dumps(summary))
    return summary
