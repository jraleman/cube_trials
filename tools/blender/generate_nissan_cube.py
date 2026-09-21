"""Original Z12 geometry, authored against the multi-view dimensional reference.

Run in Blender with --python <this file> -- --build-cube. The reference image is
not read, traced, sampled, packed, or used as a texture by this script.
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


HERE = Path(__file__).resolve().parent
SCENE_NAME = "Nissan Cube Z12 - Studio"
SCENE = None
ROOT = None
GROUPS = {}
MATERIALS = {}
WHEELS = []
AXLES = (-1.23, 1.30)
WHEEL_Z = 0.323
STATIONS = [
    (-2.020, 0.694, 0.307, 0.969),
    (-2.015, 0.746, 0.271, 0.982),
    (-2.000, 0.776, 0.244, 0.996),
    (-1.970, 0.811, 0.226, 1.005),
    (-1.920, 0.837, 0.218, 1.015),
    (-1.840, 0.848, 0.219, 1.028),
    (-1.650, 0.849, 0.222, 1.048),
    (-1.230, 0.848, 0.225, 1.070),
    (-1.070, 0.845, 0.225, 1.073),
    (-0.700, 0.844, 0.225, 1.059),
    (0.000, 0.845, 0.225, 1.058),
    (0.700, 0.846, 0.225, 1.060),
    (1.300, 0.850, 0.227, 1.065),
    (1.720, 0.849, 0.230, 1.065),
    (1.870, 0.839, 0.233, 1.061),
    (1.960, 0.810, 0.244, 1.049),
    (2.005, 0.759, 0.269, 1.023),
    (2.020, 0.701, 0.313, 0.984),
]


def material(name, color, metallic=0.0, roughness=0.4, coat=0.0,
             transmission=0.0, emission=0.0):
    mat = bpy.data.materials.new("Z12 | " + name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Coat Weight"].default_value = coat
    shader.inputs["Coat Roughness"].default_value = 0.17
    shader.inputs["Transmission Weight"].default_value = transmission
    shader.inputs["IOR"].default_value = 1.46
    if emission:
        shader.inputs["Emission Color"].default_value = (*color, 1.0)
        shader.inputs["Emission Strength"].default_value = emission
    MATERIALS[name] = mat
    return mat


def put(obj, group, parent=True):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    GROUPS[group].objects.link(obj)
    if parent and ROOT is not None:
        obj.parent = ROOT
    return obj


def mesh(name, vertices, faces, mat=None, group="Bodywork", smooth=True):
    data = bpy.data.meshes.new("Z12 | " + name)
    data.from_pydata(vertices, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new("Z12 | " + name, data)
    put(obj, group)
    if mat:
        data.materials.append(MATERIALS[mat])
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    return obj


def apply_modifier(obj, modifier):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def bevel(obj, amount, segments=3, apply=False, normals=True):
    mod = obj.modifiers.new("Soft manufactured edges", "BEVEL")
    mod.width = amount
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.harden_normals = True
    if apply:
        apply_modifier(obj, mod)
    if normals:
        weighted = obj.modifiers.new("Area weighted normals", "WEIGHTED_NORMAL")
        weighted.keep_sharp = True
        weighted.weight = 40
    return obj


def box(name, location, dimensions, mat, radius=0.0, group="Details"):
    x, y, z = [dimension * 0.5 for dimension in dimensions]
    vertices = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
                (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
    faces = [(3, 2, 1, 0), (0, 1, 5, 4), (1, 2, 6, 5),
             (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]
    obj = mesh(name, vertices, faces, mat, group)
    obj.location = location
    if radius:
        bevel(obj, radius, 5)
    return obj


def curve(name, points, radius, mat, group="Details", cyclic=False):
    data = bpy.data.curves.new("Z12 | " + name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 2
    data.bevel_depth = radius
    data.bevel_resolution = 3
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for item, point in zip(spline.points, points):
        item.co = (*point, 1.0)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new("Z12 | " + name, data)
    put(obj, group)
    data.materials.append(MATERIALS[mat])
    return obj


def lathe(name, profile, center, axis, mat, group="Details", segments=64,
          closed=False, caps=False, smooth=True):
    center = Vector(center)
    rotation = Vector(axis).normalized().to_track_quat("Z", "Y")
    vertices = []
    for distance, radius in profile:
        for index in range(segments):
            angle = math.tau * index / segments
            local = Vector((radius * math.cos(angle), radius * math.sin(angle), distance))
            vertices.append(tuple(center + rotation @ local))
    faces = []
    count = len(profile)
    for row in range(count if closed else count - 1):
        next_row = (row + 1) % count
        for index in range(segments):
            nxt = (index + 1) % segments
            faces.append((row * segments + index, row * segments + nxt,
                          next_row * segments + nxt, next_row * segments + index))
    if caps:
        faces.extend([tuple(reversed(range(segments))),
                      tuple((count - 1) * segments + index for index in range(segments))])
    return mesh(name, vertices, faces, mat, group, smooth)


def cylinder(name, center, radius, depth, axis, mat, group="Details", segments=48):
    return lathe(name, [(-depth / 2, radius), (depth / 2, radius)], center,
                 axis, mat, group, segments, caps=True)


def torus(name, center, radius, minor, axis, mat, group="Details", segments=64):
    profile = [(minor * math.sin(math.tau * index / 12),
                radius + minor * math.cos(math.tau * index / 12)) for index in range(12)]
    return lathe(name, profile, center, axis, mat, group, segments, closed=True)


def rounded_polygon(points, radius=0.06, steps=7, edge_step=0.065):
    rounded = []
    for index, point in enumerate(points):
        point = Vector(point)
        before = Vector(points[index - 1])
        after = Vector(points[(index + 1) % len(points)])
        incoming, outgoing = before - point, after - point
        distance = min(radius, incoming.length * 0.40, outgoing.length * 0.40)
        start = point + incoming.normalized() * distance
        end = point + outgoing.normalized() * distance
        for step in range(steps + 1):
            t = step / steps
            rounded.append(tuple((1 - t) ** 2 * start + 2 * t * (1 - t) * point + t * t * end))
    result = []
    for index, point in enumerate(rounded):
        start, end = Vector(point), Vector(rounded[(index + 1) % len(rounded)])
        divisions = max(1, math.ceil((end - start).length / edge_step))
        result.extend(tuple(start.lerp(end, step / divisions)) for step in range(divisions))
    return result


def rectangle(cx, cy, width, height, radius=0.04):
    return rounded_polygon([(cx - width / 2, cy - height / 2),
                            (cx + width / 2, cy - height / 2),
                            (cx + width / 2, cy + height / 2),
                            (cx - width / 2, cy + height / 2)], radius)


def surface(name, outline, mapper, mat, group="Details", reverse=False, thickness=0):
    center = sum((Vector(point) for point in outline), Vector((0, 0))) / len(outline)
    vertices = [mapper(*center)]
    rings = (0.20, 0.40, 0.60, 0.80, 1.0)
    for scale in rings:
        vertices.extend(mapper(*(center.lerp(Vector(point), scale))) for point in outline)
    count = len(outline)
    faces = [(0, 1 + index, 1 + (index + 1) % count) for index in range(count)]
    for row in range(len(rings) - 1):
        for index in range(count):
            nxt = (index + 1) % count
            faces.append((1 + row * count + index, 1 + row * count + nxt,
                          1 + (row + 1) * count + nxt, 1 + (row + 1) * count + index))
    if reverse:
        faces = [tuple(reversed(face)) for face in faces]
    obj = mesh(name, vertices, faces, mat, group)
    if thickness:
        solid = obj.modifiers.new("Physical pane thickness", "SOLIDIFY")
        solid.thickness = thickness
        solid.offset = -1
    return obj


def rounded_grid(name, width, bottom, top, radius, mapper, mat, group="Glazing"):
    vertices, faces = [], []
    columns, rows = 128, 20
    for column in range(columns + 1):
        u = width * column / columns
        distance = min(u, width - u)
        inset = radius * (1 - math.sqrt(distance / radius)) ** 2 if distance < radius else 0
        for row in range(rows + 1):
            z = bottom + inset + (top - bottom - 2 * inset) * row / rows
            vertices.append(mapper(u, z))
    for column in range(columns):
        for row in range(rows):
            index = column * (rows + 1) + row
            faces.append((index, index + 1, index + rows + 2, index + rows + 1))
    obj = mesh(name, vertices, faces, mat, group)
    solid = obj.modifiers.new("Physical pane thickness", "SOLIDIFY")
    solid.thickness = 0.004
    solid.offset = -1
    return obj


def prism(name, outline, mapper, offset, group="Bodywork"):
    offset = Vector(offset)
    front = [Vector(mapper(*point)) for point in outline]
    vertices = [tuple(point - offset) for point in front] + [
        tuple(point + offset) for point in front]
    count = len(outline)
    faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    faces.extend((index, (index + 1) % count, (index + 1) % count + count, index + count)
                 for index in range(count))
    return mesh(name, vertices, faces, group=group, smooth=False)


def difference(obj, cutter):
    mod = obj.modifiers.new("Authored opening", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    apply_modifier(obj, mod)
    data = cutter.data
    bpy.data.objects.remove(cutter, do_unlink=True)
    if data.users == 0:
        bpy.data.meshes.remove(data)


def interpolate(y, column):
    if y <= STATIONS[0][0]:
        return STATIONS[0][column]
    for first, second in zip(STATIONS, STATIONS[1:]):
        if y <= second[0]:
            t = (y - first[0]) / (second[0] - first[0])
            return first[column] * (1 - t) + second[column] * t
    return STATIONS[-1][column]


def body_width(y, z):
    width, bottom, top = (interpolate(y, index) for index in (1, 2, 3))
    if z < bottom or z > top:
        return 0.0
    crown = 0.008 * math.sin(math.pi * (z - bottom) / (top - bottom))
    radius = 0.065
    if z > top - radius:
        return width - radius + math.sqrt(max(0, radius ** 2 - (z - top + radius) ** 2)) + crown
    if z < bottom + radius:
        return width - radius + math.sqrt(max(0, radius ** 2 - (z - bottom - radius) ** 2)) + crown
    return width + crown


def cabin_width(z):
    return 0.846 - 0.064 * max(0, min(1, (z - 1.005) / 0.670))


def side_point(side, y, z, offset=0.003):
    width = body_width(y, z) if z < 1.023 else cabin_width(z)
    return (side * (width + offset), y, z)


def front_y(x, z):
    low, high = -2.02, -1.65
    for _ in range(22):
        middle = (low + high) / 2
        if body_width(middle, z) >= abs(x):
            high = middle
        else:
            low = middle
    _, width, bottom, top = STATIONS[0]
    r = max(abs(x) / width, abs(z - (top + bottom) / 2) / ((top - bottom) / 2))
    crown = 0.025 * max(0, 1 - r * r)
    return high - crown - 0.010


def rear_y(x, z):
    low, high = 1.72, 2.02
    for _ in range(22):
        middle = (low + high) / 2
        if body_width(middle, z) >= abs(x):
            low = middle
        else:
            high = middle
    _, width, bottom, top = STATIONS[-1]
    r = max(abs(x) / width, abs(z - (top + bottom) / 2) / ((top - bottom) / 2))
    crown = 0.022 * max(0, 1 - r * r)
    return low + crown + 0.010


def windshield(x, z, offset=0.008):
    y = -1.19 + (z - 1.005) * (0.51 / 0.621)
    return (x, y - offset - 0.009 * max(0, 1 - (x / 0.77) ** 2), z)


def rear_glass_y(z):
    return 1.946 - (z - 1.005) * (0.046 / 0.60)


def create_scene():
    global SCENE, ROOT
    if bpy.data.scenes.get(SCENE_NAME):
        raise RuntimeError("The authored Cube scene already exists; refusing to replace it.")
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    SCENE = bpy.data.scenes.new(SCENE_NAME)
    bpy.context.window.scene = SCENE
    SCENE.unit_settings.system = "METRIC"
    SCENE.unit_settings.length_unit = "METERS"
    SCENE["reference"] = "Dimensional study of tools\\reference\\car.png; no image data embedded."
    SCENE["vehicle"] = "Nissan Cube Z12, 2009 generation; original unbranded geometry."
    SCENE["axes"] = "Z up, nose toward -Y. Model dimensions are in meters."
    vehicle = bpy.data.collections.new("Nissan Cube | Editable model")
    SCENE.collection.children.link(vehicle)
    for index, name in enumerate(("Bodywork", "Glazing", "Wheels", "Details", "Interior")):
        collection = bpy.data.collections.new(f"{index + 1:02d} | {name}")
        vehicle.children.link(collection)
        GROUPS[name] = collection
    GROUPS["Studio"] = bpy.data.collections.new("Studio | Cameras and softboxes")
    SCENE.collection.children.link(GROUPS["Studio"])
    ROOT = bpy.data.objects.new("Nissan Cube Z12 | Assembly", None)
    vehicle.objects.link(ROOT)
    ROOT.empty_display_type = "PLAIN_AXES"
    ROOT.empty_display_size = 0.35
    ROOT["wheelbase_m"] = 2.53
    ROOT["body_width_m"] = 1.70
    ROOT["body_height_m"] = 1.675
    ROOT["note"] = "Separate wheel pivots; original mesh geometry, no reference textures."
    material("Bronze metallic", (0.230, 0.137, 0.068), 0.68, 0.25, 0.33)
    material("Bronze edge", (0.190, 0.103, 0.045), 0.68, 0.32, 0.28)
    material("Panel gaps", (0.020, 0.012, 0.007), 0.10, 0.51)
    material("Rubber seals", (0.008, 0.011, 0.012), 0.02, 0.39)
    material("Tire rubber", (0.014, 0.016, 0.019), 0.02, 0.64)
    material("Tread recess", (0.005, 0.007, 0.009), 0.00, 0.82)
    material("Silver alloy", (0.57, 0.61, 0.64), 0.87, 0.23, 0.16)
    material("Polished chrome", (0.71, 0.75, 0.79), 0.96, 0.12, 0.20)
    material("Brake steel", (0.17, 0.19, 0.20), 0.84, 0.39)
    material("Dark hardware", (0.025, 0.033, 0.038), 0.63, 0.34)
    material("Grille", (0.030, 0.034, 0.035), 0.40, 0.32)
    material("Cabin glass", (0.74, 0.83, 0.80), 0.0, 0.075, 0.14, 1.0)
    material("Privacy glass", (0.37, 0.47, 0.43), 0.0, 0.095, 0.18, 0.95)
    material("Lamp glass", (0.90, 0.96, 0.98), 0.0, 0.045, 0.15, 1.0)
    MATERIALS["Cabin glass"].diffuse_color = (0.045, 0.081, 0.089, 1.0)
    MATERIALS["Privacy glass"].diffuse_color = (0.020, 0.035, 0.040, 1.0)
    material("Lamp reflector", (0.70, 0.75, 0.78), 0.94, 0.17)
    material("Bulb", (0.82, 0.86, 0.78), 0.14, 0.18, emission=0.20)
    material("Amber lens", (0.90, 0.23, 0.008), 0.12, 0.23, 0.46, 0.15)
    material("Red lens", (0.25, 0.0015, 0.003), 0.0, 0.22, 0.22, 0.12)
    material("Red lens dark", (0.07, 0.001, 0.002), 0.15, 0.27, 0.28)
    material("Reverse lens", (0.63, 0.69, 0.68), 0.36, 0.22, 0.38)
    material("Interior charcoal", (0.025, 0.031, 0.032), 0.0, 0.82)
    material("Interior upholstery", (0.058, 0.065, 0.063), 0.0, 0.95)
    material("Mirror", (0.42, 0.52, 0.56), 0.97, 0.07)
    material("Plate", (0.30, 0.25, 0.18), 0.28, 0.49)
    material("Studio floor", (0.205, 0.225, 0.24), 0.08, 0.52)
    print("Created a separate metric scene and 26 original surface materials.")


def build_body():
    # Every station needs identical topology even where its width changes.
    rings = []
    for y, width, bottom, top in STATIONS:
        ring = []
        radius = 0.065
        for cx, cz, start in ((width - radius, top - radius, 0),
                               (-width + radius, top - radius, 90),
                               (-width + radius, bottom + radius, 180),
                               (width - radius, bottom + radius, 270)):
            for index in range(9):
                angle = math.radians(start + 90 * index / 8)
                ring.append((cx + radius * math.cos(angle), y, cz + radius * math.sin(angle)))
        sampled = []
        for index, point in enumerate(ring):
            start, end = Vector(point), Vector(ring[(index + 1) % len(ring)])
            divisions = 6 if index % 9 == 8 else 1
            for step in range(divisions):
                x, station_y, z = start.lerp(end, step / divisions)
                crown = 0.008 * math.sin(math.pi * (z - bottom) / (top - bottom))
                sampled.append((x + math.copysign(crown, x), station_y, z))
        rings.append(sampled)
    count = len(rings[0])
    vertices = [point for ring in rings for point in ring]
    faces = []
    for row in range(len(rings) - 1):
        faces.extend((row * count + index, row * count + (index + 1) % count,
                      (row + 1) * count + (index + 1) % count, (row + 1) * count + index)
                     for index in range(count))
    for row, sign, crown in ((0, -1, 0.025), (len(rings) - 1, 1, 0.022)):
        y, _, bottom, top = STATIONS[row]
        mid_z = (bottom + top) / 2
        outside = [row * count + index for index in range(count)]
        for scale in (0.8, 0.6, 0.4, 0.2):
            inside = list(range(len(vertices), len(vertices) + count))
            vertices.extend((x * scale, y + sign * crown * (1 - scale * scale),
                             mid_z + (z - mid_z) * scale) for x, _, z in rings[row])
            faces.extend((outside[i], outside[(i + 1) % count],
                          inside[(i + 1) % count], inside[i]) for i in range(count))
            outside = inside
        center = len(vertices)
        vertices.append((0, y + sign * crown, mid_z))
        faces.extend((outside[i], outside[(i + 1) % count], center) for i in range(count))
    lower = mesh("Sculpted lower body with wheel openings", vertices, faces, "Bronze metallic")
    for side in (-1, 1):
        for axle in AXLES:
            cutter = cylinder("Wheel opening tool", (side * 0.86, axle, WHEEL_Z),
                              0.365, 0.64, (1, 0, 0), None, "Bodywork", 96)
            difference(lower, cutter)
    interior = box("Interior cavity tool", (0, 0.395, 0.85), (1.435, 2.84, 1.02),
                   None, 0.07, "Bodywork")
    for modifier in list(interior.modifiers):
        apply_modifier(interior, modifier)
    difference(lower, interior)
    bevel(lower, 0.005, 3, normals=False)

    outline = rounded_polygon([(-1.19, 1.005), (-0.70, 1.626), (-0.57, 1.675),
                               (1.75, 1.675), (1.90, 1.605), (1.946, 1.005)], 0.075)
    count = len(outline)
    vertices = [(side * cabin_width(z), y, z) for side in (-1, 1) for y, z in outline]
    faces = [tuple(reversed(range(count))), tuple(range(count, 2 * count))]
    faces.extend((index, (index + 1) % count, (index + 1) % count + count, index + count)
                 for index in range(count))
    cabin = mesh("Hollow cabin and roof", vertices, faces, "Bronze metallic")
    bevel(cabin, 0.052, 6, apply=True, normals=False)
    inner_outline = rounded_polygon([(-1.115, 0.970), (-0.661, 1.582), (-0.545, 1.629),
                                     (1.718, 1.629), (1.851, 1.571), (1.901, 0.970)], 0.06)
    n = len(inner_outline)
    inner_vertices = [(side * (cabin_width(z) - 0.034), y, z)
                      for side in (-1, 1) for y, z in inner_outline]
    inner_faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    inner_faces.extend((index, (index + 1) % n, (index + 1) % n + n, index + n)
                       for index in range(n))
    difference(cabin, mesh("Cabin cavity tool", inner_vertices, inner_faces, smooth=False))
    GROUPS["Bodywork"]["shell_name"] = cabin.name

    for side in (-1, 1):
        for axle_index, axle in enumerate(AXLES):
            vertices, faces = [], []
            radii = (0.365, 0.374, 0.391, 0.426, 0.467)
            bulges = (0.005, 0.016, 0.020, 0.010, -0.001)
            for radius, bulge in zip(radii, bulges):
                for index in range(65):
                    angle = math.radians(-10 + 200 * index / 64)
                    y, z = axle + radius * math.cos(angle), WHEEL_Z + radius * math.sin(angle)
                    vertices.append((side * (body_width(y, z) + bulge), y, z))
            for row in range(4):
                faces.extend((row * 65 + i, row * 65 + i + 1,
                              (row + 1) * 65 + i + 1, (row + 1) * 65 + i) for i in range(64))
            mesh(f"{side:+d} {axle_index} rolled steel wheel-arch flare", vertices, faces,
                 "Bronze metallic")
            vertices, faces = [], []
            for x in (0.58, 0.83):
                for index in range(65):
                    angle = math.pi * index / 64
                    vertices.append((side * x, axle + 0.362 * math.cos(angle),
                                     WHEEL_Z + 0.362 * math.sin(angle)))
            faces.extend((i, i + 1, 65 + i + 1, 65 + i) for i in range(64))
            mesh(f"{side:+d} {axle_index} dark wheel-well liner", vertices, faces,
                 "Rubber seals", "Details")

    hood = rounded_polygon([(-0.695, -1.951), (0.695, -1.951),
                            (0.756, -1.114), (-0.756, -1.114)], 0.07)
    hood_map = lambda x, y: (x, y, interpolate(y, 3) + 0.0015 + 0.004 * (1 - (x / 0.78) ** 2))
    surface("Crowned short hood", hood, hood_map, "Bronze metallic", "Bodywork", thickness=0.003)
    curve("Hood shut line", [hood_map(*p) for p in hood], 0.0017, "Panel gaps", cyclic=True)
    box("Underfloor", (0, 0.03, 0.245), (1.38, 3.48, 0.09), "Dark hardware", 0.05)
    for side in (-1, 1):
        box(f"{side:+d} sculpted rocker sill", (side * 0.817, 0.035, 0.265),
            (0.062, 1.86, 0.075), "Bronze metallic", 0.024, "Bodywork")
    print("Built hollow body, sculpted flares, four real wheel apertures, hood and chassis.")


def build_glazing():
    cabin = bpy.data.objects[GROUPS["Bodywork"]["shell_name"]]
    front = rounded_polygon([(-1.074, 1.075), (-0.656, 1.567), (-0.556, 1.606),
                             (0.196, 1.605), (0.207, 1.063), (-0.966, 1.052)], 0.105)
    passenger = rounded_polygon([(0.369, 1.054), (1.183, 1.054),
                                 (1.178, 1.602), (0.367, 1.602)], 0.10)
    quarter = rounded_polygon([(1.270, 1.071), (1.789, 1.078),
                               (1.765, 1.588), (1.270, 1.598)], 0.115)
    for side in (-1, 1):
        profiles = [("Front door", front, "Cabin glass"),
                    ("Rear door", passenger, "Privacy glass")]
        if side == 1:
            profiles.append(("Quarter", quarter, "Privacy glass"))
        for name, outline, mat in profiles:
            cutter = prism("Side glazing aperture", outline,
                           lambda y, z: (side * 0.81, y, z), (0.19, 0, 0))
            difference(cabin, cutter)
            mapper = lambda y, z, s=side: (s * (cabin_width(z) + 0.002), y, z)
            surface(f"{side:+d} {name} curved glass", outline, mapper, mat,
                    "Glazing", reverse=side < 0, thickness=0.004)
            curve(f"{side:+d} {name} window rubber", [mapper(*p) for p in outline],
                  0.011, "Rubber seals", "Glazing", True)
        mapper = lambda y, z, s=side: (s * (cabin_width(z) + 0.006), y, z)
        strip = rectangle(1.230, 1.327, 0.083, 0.552, 0.008)
        surface(f"{side:+d} black rear divider", strip, mapper, "Rubber seals", "Glazing",
                reverse=side < 0)
        curve(f"{side:+d} rear opening vent divider",
              [mapper(1.013, z) for z in (1.07, 1.57)], 0.007, "Rubber seals", "Glazing")

    wind_outline = rounded_polygon([(-0.758, 1.087), (0.758, 1.087),
                                    (0.714, 1.592), (-0.714, 1.592)], 0.065)
    difference(cabin, prism("Windshield aperture", wind_outline, windshield, (0, 0.10, -0.04)))
    surface("Panoramic curved windshield", wind_outline, windshield, "Cabin glass",
            "Glazing", thickness=0.005)
    curve("Windshield bonded surround", [windshield(*p) for p in wind_outline],
          0.014, "Rubber seals", "Glazing", True)

    rear_cut = rectangle(-0.076, 1.337, 1.682, 0.495, 0.10)
    difference(cabin, prism("Asymmetric backlight aperture", rear_cut,
                           lambda x, z: (x, rear_glass_y(z), z), (0, 0.14, 0)))
    side_cut = rectangle(1.634, 1.337, 0.760, 0.495, 0.10)
    difference(cabin, prism("Wraparound quarter aperture", side_cut,
                           lambda y, z: (-0.81, y, z), (0.19, 0, 0)))

    path_length = 2.125
    outline = rounded_polygon([(0, 1.100), (path_length, 1.100),
                               (path_length, 1.574), (0, 1.574)], 0.09, 10, 0.012)

    def wrap(s, z):
        width = cabin_width(z) + 0.004
        back = rear_glass_y(z) + 0.006
        if s < 0.53:
            return (-width, 1.287 + (back - 0.108 - 1.287) * s / 0.53, z)
        if s < 0.700:
            angle = (s - 0.53) / 0.170 * math.pi / 2
            return (-width + 0.108 - 0.108 * math.cos(angle),
                    back - 0.108 + 0.108 * math.sin(angle), z)
        t = (s - 0.700) / (path_length - 0.700)
        return ((-width + 0.108) * (1 - t) + 0.705 * t, back, z)

    rounded_grid("Continuous asymmetric rear and right quarter glass", path_length,
                 1.100, 1.574, 0.09, wrap, "Privacy glass")
    curve("Continuous wraparound backlight seal", [wrap(*p) for p in outline],
          0.013, "Rubber seals", "Glazing", True)
    for index in range(7):
        z = 1.16 + index * 0.051
        curve(f"Rear demister filament {index + 1}",
              [(x, rear_glass_y(z) + 0.011, z) for x in (-0.65, 0.0, 0.65)],
              0.00075, "Bronze edge", "Glazing")
    bevel(cabin, 0.003, 2, normals=True)
    print("Cut cabin glazing apertures and fitted independent panes, seals and wraparound rear glass.")


def build_wheels():
    tire_profile = [(-0.096, 0.200), (-0.108, 0.235), (-0.108, 0.270),
                    (-0.099, 0.298), (-0.081, 0.315), (-0.068, 0.321),
                    (-0.053, 0.323), (-0.049, 0.316), (-0.043, 0.316), (-0.039, 0.323),
                    (-0.019, 0.324), (-0.015, 0.316), (-0.009, 0.316), (-0.005, 0.324),
                    (0.014, 0.324), (0.018, 0.316), (0.024, 0.316), (0.028, 0.323),
                    (0.046, 0.323), (0.050, 0.316), (0.056, 0.316), (0.060, 0.322),
                    (0.081, 0.315), (0.099, 0.298), (0.108, 0.270), (0.108, 0.235),
                    (0.096, 0.200)]
    for side in (-1, 1):
        for axle_index, y in enumerate(AXLES):
            label = ("R" if side < 0 else "L") + ("F" if axle_index == 0 else "R")
            center = (side * 0.744, y, WHEEL_Z)
            before = set(GROUPS["Wheels"].objects)
            axis = (side, 0, 0)
            lathe(label + " radial tire with tread channels", tire_profile, center, axis,
                  "Tire rubber", "Wheels", 96, closed=True)
            for radius in (0.218, 0.292):
                torus(label + " molded sidewall ring", (side * 0.851, y, WHEEL_Z),
                      radius, 0.0013, axis, "Tire rubber", "Wheels", 96)
            vertices, faces = [], []
            for row, axial in enumerate((-0.070, -0.031, 0.007, 0.043, 0.073)):
                for index in range(72):
                    angle = math.tau * (index + 0.30 * (row % 2)) / 72
                    base = len(vertices)
                    for da, dx in ((-0.004, -0.009), (0.004, -0.009),
                                   (0.027, 0.009), (0.019, 0.009)):
                        radial = 0.324 if abs(axial) < 0.065 else 0.319
                        vertices.append((center[0] + side * (axial + dx),
                                         y + radial * math.cos(angle + da),
                                         WHEEL_Z + radial * math.sin(angle + da)))
                    faces.append(tuple(range(base, base + 4)))
            mesh(label + " fine diagonal tread sipes", vertices, faces, "Tread recess", "Wheels")
            lathe(label + " cast alloy barrel",
                  [(-0.075, 0.187), (-0.075, 0.198), (0.093, 0.201),
                   (0.105, 0.192), (0.088, 0.181), (-0.061, 0.178)],
                  center, axis, "Silver alloy", "Wheels", 80, closed=True)
            torus(label + " polished rim lip", (side * 0.850, y, WHEEL_Z),
                  0.195, 0.007, axis, "Polished chrome", "Wheels", 80)
            cylinder(label + " brake rotor", (side * 0.807, y, WHEEL_Z),
                     0.159, 0.016, axis, "Brake steel", "Wheels", 72)
            for radius in (0.116, 0.137, 0.151):
                torus(label + " rotor machining", (side * 0.818, y, WHEEL_Z),
                      radius, 0.0008, axis, "Dark hardware", "Wheels")
            box(label + " brake caliper", (side * 0.821, y + 0.121, WHEEL_Z + 0.032),
                (0.045, 0.059, 0.099), "Dark hardware", 0.012, "Wheels")
            for index in range(5):
                angle = math.tau * index / 5 + 0.15
                shape = [(0.048, -0.022), (0.097, -0.025), (0.182, -0.038),
                         (0.192, -0.021), (0.187, 0.035), (0.095, 0.025), (0.048, 0.022)]
                vertices = []
                for back in (0.0, -0.025):
                    for radius, tangent in shape:
                        x = 0.868 - 0.018 * (radius / 0.19) + back
                        vertices.append((side * x,
                                         y + radius * math.cos(angle) - tangent * math.sin(angle),
                                         WHEEL_Z + radius * math.sin(angle) + tangent * math.cos(angle)))
                n = len(shape)
                faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
                faces.extend((j, (j + 1) % n, (j + 1) % n + n, j + n) for j in range(n))
                spoke = mesh(f"{label} sculpted spoke {index + 1}", vertices, faces,
                             "Silver alloy", "Wheels")
                bevel(spoke, 0.006, 3)
            cylinder(label + " hub", (side * 0.861, y, WHEEL_Z),
                     0.061, 0.022, axis, "Silver alloy", "Wheels")
            for index in range(5):
                angle = math.tau * index / 5 + 0.15
                location = (side * 0.875, y + 0.040 * math.cos(angle),
                            WHEEL_Z + 0.040 * math.sin(angle))
                cylinder(label + " lug pocket", location, 0.013, 0.004, axis,
                         "Dark hardware", "Wheels", 24)
                location = (side * 0.879, location[1], location[2])
                cylinder(label + " hex wheel bolt", location, 0.0085, 0.008, axis,
                         "Polished chrome", "Wheels", 6)
            cylinder(label + " unbranded center cap", (side * 0.879, y, WHEEL_Z),
                     0.024, 0.009, axis, "Polished chrome", "Wheels")
            torus(label + " center cap seam", (side * 0.884, y, WHEEL_Z),
                  0.024, 0.0013, axis, "Dark hardware", "Wheels")
            cylinder(label + " tire valve", (side * 0.859, y + 0.111, WHEEL_Z - 0.131),
                     0.005, 0.020, axis, "Rubber seals", "Wheels", 16)
            pivot = bpy.data.objects.new("Z12 | " + label + " wheel pivot", None)
            put(pivot, "Wheels")
            pivot.location = center
            pivot.empty_display_size = 0.13
            pivot["rotation_axis"] = "Local X"
            bpy.context.view_layer.update()
            for obj in set(GROUPS["Wheels"].objects) - before - {pivot}:
                transform = obj.matrix_world.copy()
                obj.parent = pivot
                obj.matrix_world = transform
            WHEELS.append(pivot)
    print("Built four individually pivoted wheels with five spokes, brakes, bolts and tread.")


def face_patch(name, cx, z, width, height, radius, mat, rear=False, offset=0.0):
    outline = rectangle(cx, z, width, height, radius)
    sign = 1 if rear else -1
    mapper = lambda x, h: (x, (rear_y(x, h) if rear else front_y(x, h)) + sign * offset, h)
    return surface(name, outline, mapper, mat, reverse=rear, thickness=0.003)


def build_front():
    lower = bpy.data.objects["Z12 | Sculpted lower body with wheel openings"]
    for modifier in list(lower.modifiers):
        apply_modifier(lower, modifier)
    face_patch("Upper grille perimeter", 0, 0.842, 0.914, 0.209, 0.041, "Rubber seals")
    face_patch("Graphite upper grille", 0, 0.842, 0.882, 0.184, 0.033, "Grille", offset=0.005)
    for side in (-1, 1):
        for x in (0.159, 0.242, 0.321, 0.382):
            for z in (0.790, 0.839, 0.888):
                face_patch("Rounded grille ventilation slot", side * x, z,
                           0.049, 0.020, 0.009, "Rubber seals", offset=0.011)
        cx = side * 0.644
        outline = rectangle(cx, 0.831, 0.404, 0.245, 0.084)
        difference(lower, prism("Recessed headlight pocket", outline,
                                lambda x, z: (x, -2.010, z), (0, 0.20, 0)))
        curve(f"{side:+d} headlamp black surround",
              [(x, front_y(x, z) - 0.003, z) for x, z in outline],
              0.009, "Rubber seals", cyclic=True)
        face_patch(f"{side:+d} headlamp silver housing", cx, 0.831, 0.374, 0.211, 0.075,
                   "Lamp reflector", offset=-0.073)
        face_patch(f"{side:+d} headlamp inner shadow", cx, 0.832, 0.343, 0.179, 0.065,
                   "Dark hardware", offset=-0.065)
        for index, (x, radius) in enumerate(((side * 0.685, 0.078), (side * 0.535, 0.043))):
            y = front_y(x, 0.834) + 0.017
            profile = [(0.010, radius), (-0.008, radius * 0.87),
                       (-0.032, radius * 0.52), (-0.036, radius * 0.15)]
            lathe(f"{side:+d} reflector bowl {index}", profile, (x, y, 0.837),
                  (0, -1, 0), "Lamp reflector", segments=40, smooth=False)
            torus(f"{side:+d} headlamp reflector rim {index}", (x, y - 0.011, 0.837),
                  radius, 0.003, (0, -1, 0), "Polished chrome")
            cylinder(f"{side:+d} headlamp bulb {index}", (x, y - 0.018, 0.837),
                     radius * 0.29, 0.023, (0, -1, 0), "Bulb", segments=32)
        face_patch(f"{side:+d} amber corner signal", side * 0.811, 0.832,
                   0.037, 0.155, 0.015, "Amber lens", offset=0.003)
        lens = rectangle(cx, 0.831, 0.371, 0.208, 0.075)
        surface(f"{side:+d} clear headlamp lens", lens,
                lambda x, z: (x, front_y(x, z) - 0.016, z),
                "Lamp glass", "Glazing", thickness=0.003)
        for index in range(5):
            x = side * (0.492 + index * 0.020)
            curve(f"{side:+d} headlamp fluting {index}",
                  [(x, front_y(x, z) - 0.017, z) for z in (0.794, 0.830, 0.866)],
                  0.0009, "Lamp glass", "Glazing")

    badge_y = front_y(0, 0.842) - 0.018
    torus("Plain grille medallion rim", (0, badge_y, 0.842), 0.049, 0.0045,
          (0, -1, 0), "Polished chrome")
    cylinder("Unbranded satin grille medallion", (0, badge_y + 0.002, 0.842),
             0.041, 0.008, (0, -1, 0), "Silver alloy")
    face_patch("Slim bumper intake surround", 0, 0.628, 0.920, 0.080, 0.032,
               "Bronze edge", offset=0.007)
    face_patch("Slim bumper intake", 0, 0.628, 0.875, 0.052, 0.023,
               "Rubber seals", offset=0.011)
    for x in (-0.29, -0.145, 0, 0.145, 0.29):
        box("Upper intake fin", (x, front_y(x, 0.628) - 0.016, 0.628),
            (0.006, 0.014, 0.041), "Grille", 0.002)
    face_patch("Lower intake sculpted bezel", 0, 0.407, 1.061, 0.231, 0.064,
               "Bronze edge", offset=0.006)
    face_patch("Lower radiator opening", 0, 0.409, 0.973, 0.188, 0.032,
               "Rubber seals", offset=0.014)
    for index in range(20):
        x = -0.443 + 0.0466 * index
        box("Radiator vertical fin", (x, front_y(x, 0.410) - 0.020, 0.410),
            (0.006, 0.014, 0.163), "Grille", 0.002)
    for z in (0.349, 0.391, 0.436, 0.473):
        curve("Radiator horizontal louvre",
              [(x, front_y(x, z) - 0.024, z) for x in (-0.46, 0.0, 0.46)],
              0.004, "Dark hardware")
    curve("Bronze lower bumper crossbar",
          [(x, front_y(x, 0.399) - 0.039, 0.399) for x in (-0.49, -0.25, 0, 0.25, 0.49)],
          0.009, "Bronze metallic")
    for side in (-1, 1):
        x, z = side * 0.621, 0.426
        y = front_y(x, z)
        torus(f"{side:+d} fog lamp painted bezel", (x, y - 0.016, z), 0.083, 0.016,
              (0, -1, 0), "Bronze edge")
        cylinder(f"{side:+d} fog lamp recess", (x, y - 0.021, z), 0.073, 0.024,
                 (0, -1, 0), "Rubber seals")
        torus(f"{side:+d} fog lamp inner rim", (x, y - 0.038, z), 0.055, 0.004,
              (0, -1, 0), "Polished chrome")
        cylinder(f"{side:+d} fog lamp smoked lens", (x, y - 0.040, z), 0.052, 0.008,
                 (0, -1, 0), "Privacy glass")
    curve("Front bumper lower return",
          [(x, front_y(x, 0.302) - 0.003, 0.302) for x in (-0.59, -0.3, 0, 0.3, 0.59)],
          0.003, "Bronze edge")
    print("Built detailed front optics, ventilation slots, radiator and recessed fog lights.")


def build_details():
    front_door = [(-1.094, 1.064), (-1.026, 0.822), (-0.867, 0.535), (-0.848, 0.335),
                  (-0.792, 0.292), (0.246, 0.292), (0.274, 0.333), (0.274, 1.630),
                  (-0.565, 1.637), (-0.685, 1.586)]
    rear_door = [(0.287, 0.293), (0.897, 0.293), (0.938, 0.360), (1.000, 0.536),
                 (1.153, 0.713), (1.234, 0.758), (1.237, 1.630), (0.287, 1.630)]
    for side in (-1, 1):
        for name, outline in (("Front door", front_door), ("Rear door", rear_door)):
            rounded = rounded_polygon(outline, 0.035, edge_step=0.025)
            curve(f"{side:+d} {name} panel seam",
                  [side_point(side, y, z, 0.0035) for y, z in rounded],
                  0.0026, "Panel gaps", cyclic=True)
        for index, y in enumerate((0.035, 1.018)):
            outline = rectangle(y, 0.953, 0.205, 0.062, 0.029)
            surface(f"{side:+d} handle pocket {index}", outline,
                    lambda u, v, s=side: side_point(s, u, v, 0.005), "Bronze edge",
                    reverse=side < 0)
            width = body_width(y, 0.952)
            for dy in (-0.077, 0.077):
                box(f"{side:+d} door handle support", (side * (width + 0.021), y + dy, 0.951),
                    (0.041, 0.033, 0.025), "Bronze metallic", 0.01)
            box(f"{side:+d} pull door handle {index}", (side * (width + 0.039), y, 0.959),
                (0.038, 0.222, 0.029), "Bronze metallic", 0.013)
            if index == 0:
                cylinder(f"{side:+d} door lock", (side * (width + 0.060), y + 0.078, 0.959),
                         0.0065, 0.003, (side, 0, 0), "Polished chrome", segments=24)
        marker = rectangle(-1.337, 0.983, 0.067, 0.024, 0.011)
        surface(f"{side:+d} fender repeater", marker,
                lambda y, z, s=side: side_point(s, y, z, 0.008), "Reverse lens",
                reverse=side < 0)
        surface(f"{side:+d} repeater amber center", rectangle(-1.337, 0.983, 0.024, 0.010, 0.004),
                lambda y, z, s=side: side_point(s, y, z, 0.010), "Amber lens",
                reverse=side < 0)
        curve(f"{side:+d} mirror stem",
              [(side * 0.828, -0.943, 1.106), (side * 0.904, -0.990, 1.136)],
              0.025, "Rubber seals")
        box(f"{side:+d} body-color mirror shell", (side * 0.935, -1.003, 1.151),
            (0.183, 0.201, 0.145), "Bronze metallic", 0.055, "Bodywork")
        outline = rectangle(side * 0.935, 1.152, 0.162, 0.115, 0.033)
        surface(f"{side:+d} mirror gasket", outline, lambda x, z: (x, -0.899, z),
                "Rubber seals", reverse=True)
        outline = rectangle(side * 0.935, 1.152, 0.143, 0.092, 0.025)
        surface(f"{side:+d} mirror reflective face", outline, lambda x, z: (x, -0.895, z),
                "Mirror", "Glazing", reverse=True)
        curve(f"{side:+d} roof gutter",
              [(side * 0.731, y, 1.679) for y in (-0.53, 0.1, 0.8, 1.63)],
              0.004, "Bronze edge")
    fuel = rectangle(1.622, 0.904, 0.232, 0.221, 0.041)
    curve("Fuel filler flap seam", [side_point(1, y, z, 0.003) for y, z in fuel],
          0.0021, "Panel gaps", cyclic=True)
    for index, x in enumerate((-0.462, -0.154, 0.154, 0.462)):
        points = [(x, -0.16, 1.676), (x, -0.09, 1.684), (x, 1.38, 1.684), (x, 1.45, 1.676)]
        curve(f"Roof pressing rib {index + 1}", points, 0.0065, "Bronze metallic", "Bodywork")
    box("Antenna mounting foot", (-0.53, 1.660, 1.697), (0.064, 0.108, 0.028),
        "Rubber seals", 0.014)
    curve("Flexible roof aerial", [(-0.53, 1.671, 1.703), (-0.53, 1.795, 1.936)],
          0.0043, "Rubber seals")

    curve("Black windshield cowl", [windshield(x, 1.086, 0.017) for x in (-0.69, 0, 0.69)],
          0.013, "Rubber seals")
    for index, x in enumerate((-0.40, 0.22)):
        arm = [(x + 0.13, 1.103), (x + 0.01, 1.133), (x - 0.15, 1.142)]
        curve(f"Front wiper arm {index + 1}", [windshield(u, z, 0.031) for u, z in arm],
              0.004, "Dark hardware")
        blade = [(x - 0.20, 1.140), (x, 1.146), (x + 0.21, 1.140)]
        curve(f"Front wiper blade {index + 1}", [windshield(u, z, 0.039) for u, z in blade],
              0.006, "Rubber seals")
    print("Added four door seams and handles, mirrors, filler flap, roof pressings and wipers.")


def build_rear():
    face_patch("Rear light band gasket", 0, 0.677, 1.582, 0.157, 0.070, "Rubber seals", True)
    face_patch("Continuous low rear light band", 0, 0.677, 1.534, 0.126, 0.055,
               "Red lens", True, 0.008)
    face_patch("Rear light band center insert", 0, 0.677, 0.525, 0.109, 0.010,
               "Red lens dark", True, 0.013)
    for side in (-1, 1):
        face_patch(f"{side:+d} rear reversing cluster", side * 0.391, 0.677,
                   0.256, 0.109, 0.036, "Reverse lens", True, 0.017)
        face_patch(f"{side:+d} rear indicator lens", side * 0.451, 0.677,
                   0.078, 0.097, 0.013, "Lamp reflector", True, 0.021)
        x = side * 0.663
        y = rear_y(x, 0.677) + 0.024
        torus(f"{side:+d} stop-light concentric lens", (x, y, 0.677), 0.043, 0.0035,
              (0, 1, 0), "Red lens dark")
        for index in range(6):
            x = side * (0.294 + index * 0.035)
            curve(f"{side:+d} reversing lens prism {index}",
                  [(x, rear_y(x, z) + 0.023, z) for z in (0.640, 0.677, 0.714)],
                  0.0015, "Lamp glass")
    face_patch("Rear license recess", 0, 0.398, 0.540, 0.233, 0.039, "Bronze edge", True, 0.006)
    face_patch("Rear license inner border", 0, 0.398, 0.497, 0.204, 0.019,
               "Rubber seals", True, 0.009)
    face_patch("Blank rear registration plate", 0, 0.398, 0.474, 0.183, 0.014,
               "Plate", True, 0.013)
    for x in (-0.194, 0.194):
        cylinder("Rear plate fastener", (x, rear_y(x, 0.462) + 0.018, 0.462),
                 0.004, 0.004, (0, 1, 0), "Dark hardware", segments=16)
    x, z = -0.493, 0.976
    face_patch("Tailgate handle recess", x, z, 0.219, 0.068, 0.031, "Bronze edge", True, 0.005)
    box("Side-hinged tailgate pull", (x, rear_y(x, z) + 0.032, z),
        (0.222, 0.042, 0.031), "Bronze metallic", 0.014)
    badge_y = rear_y(0, 0.967)
    torus("Plain tailgate medallion", (0, badge_y + 0.020, 0.967),
          0.046, 0.004, (0, 1, 0), "Polished chrome")
    cylinder("Unbranded rear medallion face", (0, badge_y + 0.020, 0.967),
             0.037, 0.008, (0, 1, 0), "Silver alloy")
    hatch = [(-0.785, 1.058), (-0.787, 0.884), (-0.736, 0.772),
             (0.736, 0.772), (0.784, 0.863), (0.751, 1.611),
             (0.668, 1.650), (-0.699, 1.650)]
    curve("Side-hinged hatch shut line",
          [(x, rear_y(x, z) + 0.003 if z < 1.023 else rear_glass_y(z) + 0.005, z)
           for x, z in hatch], 0.0024, "Panel gaps")
    for z in (1.13, 1.43):
        box("Exposed tailgate hinge", (0.783, rear_glass_y(z) + 0.007, z),
            (0.029, 0.036, 0.087), "Bronze edge", 0.009)
    box("High stop-light gasket", (0, 1.891, 1.631), (0.295, 0.026, 0.051),
        "Rubber seals", 0.016)
    box("High-mounted stop lamp", (0, 1.907, 1.632), (0.265, 0.012, 0.033),
        "Red lens", 0.011)
    curve("Rear wiper arm", [(-0.355, rear_glass_y(1.138) + 0.024, 1.138),
                            (-0.167, rear_glass_y(1.158) + 0.025, 1.158)],
          0.006, "Dark hardware")
    curve("Rear wiper blade", [(x, rear_glass_y(1.146) + 0.036, 1.146)
                              for x in (-0.365, -0.130, 0.105)],
          0.007, "Rubber seals")
    for x in (-0.635, 0.635):
        cylinder("Rear parking sensor", (x, rear_y(x, 0.437) + 0.004, 0.437),
                 0.012, 0.003, (0, 1, 0), "Bronze edge", segments=32)
    cylinder("Exhaust silencer", (0.48, 1.675, 0.235), 0.074, 0.38,
             (0, 1, 0), "Dark hardware")
    lathe("Hollow polished exhaust tip", [(-0.11, 0.037), (0.055, 0.041),
                                        (0.064, 0.036), (-0.11, 0.030)],
          (0.48, 2.00, 0.224), (0, 1, 0), "Polished chrome", closed=True)
    cylinder("Exhaust interior", (0.48, 1.991, 0.224), 0.030, 0.005,
             (0, 1, 0), "Rubber seals")
    print("Built low rear light bar, asymmetric hatch details, rear wiper and hollow exhaust.")


def build_interior():
    box("Cabin floor", (0, 0.35, 0.423), (1.40, 2.51, 0.06),
        "Interior charcoal", 0.035, "Interior")
    box("Rounded dashboard", (0, -0.821, 0.997), (1.397, 0.330, 0.190),
        "Interior charcoal", 0.069, "Interior")
    for side in (-1, 1):
        x = side * 0.351
        box(f"{side:+d} front seat cushion", (x, -0.035, 0.635),
            (0.448, 0.474, 0.134), "Interior upholstery", 0.061, "Interior")
        back = box(f"{side:+d} front seat backrest", (x, 0.152, 0.927),
                   (0.443, 0.159, 0.543), "Interior upholstery", 0.067, "Interior")
        back.rotation_euler.x = math.radians(8)
        box(f"{side:+d} front headrest", (x, 0.200, 1.273),
            (0.263, 0.136, 0.218), "Interior upholstery", 0.055, "Interior")
        for dx in (-0.07, 0.07):
            cylinder("Headrest support", (x + dx, 0.20, 1.160), 0.008, 0.087,
                     (0, 0, 1), "Dark hardware", "Interior", 16)
        box(f"{side:+d} inner door card", (side * 0.738, 0.05, 0.830),
            (0.039, 1.99, 0.324), "Interior charcoal", 0.018, "Interior")
    box("Rear bench seat", (0, 1.052, 0.681), (1.262, 0.429, 0.151),
        "Interior upholstery", 0.059, "Interior")
    box("Rear bench backrest", (0, 1.298, 0.948), (1.269, 0.158, 0.519),
        "Interior upholstery", 0.061, "Interior")
    for x in (-0.405, 0.405):
        box("Rear headrest", (x, 1.296, 1.268), (0.260, 0.126, 0.195),
            "Interior upholstery", 0.046, "Interior")
    steering_center = Vector((0.377, -0.555, 1.067))
    steering_axis = Vector((0, -0.79, 0.61)).normalized()
    torus("Steering wheel", steering_center, 0.134, 0.016, steering_axis,
          "Interior charcoal", "Interior")
    cylinder("Steering wheel hub", steering_center, 0.043, 0.040, steering_axis,
             "Interior charcoal", "Interior")
    rotation = steering_axis.to_track_quat("Z", "Y")
    for angle in (0, 2.3, 3.98):
        end = steering_center + rotation @ Vector((0.119 * math.cos(angle),
                                                  0.119 * math.sin(angle), 0))
        curve("Steering wheel spoke", [tuple(steering_center), tuple(end)], 0.009,
              "Dark hardware", "Interior")
    box("Interior rear-view mirror", (0, -0.735, 1.454), (0.248, 0.040, 0.083),
        "Interior charcoal", 0.023, "Interior")
    print("Built a shaded cabin interior with seats, headrests, dashboard and steering wheel.")


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def build_studio():
    floor = box("Studio ground", (0, 0, -0.049), (200, 200, 0.090),
                "Studio floor", 0, "Studio")
    floor.parent = None
    for name, location, power, size, color, shape, size_y in (
        ("Key softbox", (1.3, -4.5, 6.0), 720, 4.1, (1.0, 0.91, 0.79), "RECTANGLE", 3.1),
        ("Side strip", (4.4, 0.8, 3.0), 620, 4.2, (0.83, 0.91, 1.0), "RECTANGLE", 1.7),
        ("Roof rim", (-2.5, 3.0, 5.0), 960, 3.5, (1.0, 0.92, 0.79), "RECTANGLE", 2.2),
        ("Front fill", (-3.5, -4.0, 2.5), 370, 3.0, (0.83, 0.91, 1.0), "DISK", 3.0),
        ("Rear fill", (1.0, 4.8, 2.8), 390, 2.8, (1.0, 0.98, 0.94), "RECTANGLE", 2.0),
    ):
        data = bpy.data.lights.new("Z12 | " + name, "AREA")
        data.energy, data.shape, data.size, data.color = power, shape, size, color
        if shape == "RECTANGLE":
            data.size_y = size_y
        obj = bpy.data.objects.new("Z12 | " + name, data)
        put(obj, "Studio", parent=False)
        obj.location = location
        aim(obj, (0, 0, 0.75))
    for frame, name, position, scale in (
        (1, "Front three-quarter", (5.7, -8.3, 3.05), 5.65),
        (2, "Rear wraparound three-quarter", (-5.9, 8.2, 3.10), 5.65),
        (3, "Left elevation", (8.0, 0.0, 1.0), 4.8),
        (4, "Front elevation", (0.0, -8.0, 1.0), 2.8),
        (5, "Rear elevation", (0.0, 8.0, 1.0), 2.8),
    ):
        data = bpy.data.cameras.new("Z12 | " + name)
        data.type = "PERSP" if frame < 3 else "ORTHO"
        data.ortho_scale = scale
        data.lens = 65
        data.clip_end = 300
        obj = bpy.data.objects.new("Z12 | Camera | " + name, data)
        put(obj, "Studio", parent=False)
        obj.location = position
        aim(obj, (0, 0, 0.86))
        marker = SCENE.timeline_markers.new(name, frame=frame)
        marker.camera = obj
        if frame == 1:
            SCENE.camera = obj
    world = bpy.data.worlds.new("Z12 | Neutral studio")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.12, 0.14, 0.16, 1.0)
    background.inputs["Strength"].default_value = 0.25
    SCENE.world = world
    SCENE.render.engine = "CYCLES"
    SCENE.cycles.samples = 64
    SCENE.cycles.use_denoising = True
    SCENE.cycles.preview_samples = 16
    SCENE.cycles.use_preview_denoising = True
    SCENE.cycles.max_bounces = 8
    SCENE.cycles.transmission_bounces = 6
    SCENE.render.resolution_x = 1600
    SCENE.render.resolution_y = 1100
    SCENE.render.resolution_percentage = 100
    SCENE.render.image_settings.file_format = "PNG"
    SCENE.render.image_settings.color_mode = "RGBA"
    SCENE.render.film_transparent = False
    SCENE.view_settings.view_transform = "AgX"
    SCENE.render.filepath = str(HERE / "nissan_cube_preview.png")
    SCENE.frame_start, SCENE.frame_end = 1, 5
    SCENE.frame_set(1)
    if bpy.context.window:
        layout = bpy.data.workspaces.get("Layout")
        if layout:
            bpy.context.window.workspace = layout
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type == "VIEW_3D":
                    area.spaces.active.region_3d.view_perspective = "CAMERA"
                    area.spaces.active.region_3d.view_camera_zoom = 26
                    area.spaces.active.shading.type = "SOLID"
                    area.spaces.active.shading.color_type = "MATERIAL"
                    area.spaces.active.shading.light = "STUDIO"
                    area.spaces.active.shading.show_cavity = True
                    area.spaces.active.overlay.show_overlays = False
    print("Created five inspection cameras and a softbox studio.")


def save_project():
    if SCENE is None or len(WHEELS) != 4:
        raise RuntimeError("The model is incomplete; refusing to save a success-shaped asset.")
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    ROOT.select_set(True)
    bpy.context.view_layer.objects.active = ROOT
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / "nissan_cube.blend"), compress=True)
    print("Saved " + str(HERE / "nissan_cube.blend"))


def build_all():
    create_scene()
    build_body()
    build_glazing()
    build_wheels()
    build_front()
    build_details()
    build_rear()
    build_interior()
    build_studio()
    save_project()


if __name__ == "__main__" and "--build-cube" in sys.argv:
    build_all()
