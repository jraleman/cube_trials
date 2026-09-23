"""Author the car2/car3 studies without reading or embedding reference pixels.

Run in a fresh Blender process with -- --car hyundai_sonata or --car honda_crv.
Each build saves only the selected car; studio and mesh primitives are shared.
"""

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from generate_nissan_cube import harden_surface_edges, rounded_polygon  # noqa: E402
from prop_kit import Asset, srgb  # noqa: E402


@dataclass(frozen=True)
class CarSpec:
    key: str
    title: str
    prefix: str
    reference: str
    suv: bool
    paint: str
    axles: tuple
    tire_radius: float
    half_track: float
    cabin_base: float
    cabin_height: float
    stations: tuple
    roof: tuple
    windows: tuple

    @property
    def scene_name(self):
        return self.title + " - Studio"

    @property
    def root_name(self):
        return self.title + " | Assembly"

    @property
    def root_node(self):
        return self.title.replace(" ", "").replace("-", "")


SPECS = {
    "hyundai_sonata": CarSpec(
        "hyundai_sonata", "Hyundai Sonata", "Sonata", "car2.png", False, "E7EBF0",
        (-1.52, 1.32), 0.338, 0.795, 1.005, 1.465,
        (
            (-2.445, 0.630, 0.310, 0.823), (-2.430, 0.720, 0.254, 0.846),
            (-2.390, 0.792, 0.218, 0.870), (-2.315, 0.861, 0.193, 0.903),
            (-2.210, 0.906, 0.179, 0.933), (-2.070, 0.922, 0.173, 0.954),
            (-1.860, 0.930, 0.169, 0.980), (-1.520, 0.932, 0.170, 1.009),
            (-1.200, 0.921, 0.170, 1.010), (-0.940, 0.907, 0.169, 1.027),
            (-0.450, 0.910, 0.170, 1.028), (0.200, 0.916, 0.170, 1.040),
            (0.850, 0.927, 0.170, 1.065), (1.320, 0.934, 0.170, 1.075),
            (1.680, 0.926, 0.180, 1.058), (1.950, 0.910, 0.188, 1.030),
            (2.125, 0.896, 0.200, 1.026), (2.310, 0.854, 0.222, 1.010),
            (2.410, 0.774, 0.262, 0.978), (2.445, 0.660, 0.307, 0.942),
        ),
        ((-1.075, 1.023), (-0.79, 1.233), (-0.41, 1.408), (-0.08, 1.463),
         (0.36, 1.465), (0.72, 1.422), (1.11, 1.280), (1.68, 1.050)),
        (
            ("Front door", ((-0.962, 1.073), (-0.368, 1.371), (-0.11, 1.410),
                            (0.175, 1.413), (0.180, 1.077)), "Cabin glass"),
            ("Rear door", ((0.273, 1.083), (0.267, 1.413), (0.615, 1.373),
                           (0.88, 1.278), (1.095, 1.110)), "Privacy glass"),
            ("Quarter", ((1.170, 1.111), (0.999, 1.257),
                         (1.502, 1.110)), "Privacy glass"),
        ),
    ),
    "honda_crv": CarSpec(
        "honda_crv", "Honda CR-V", "CRV", "car3.png", True, "07387F",
        (-1.40, 1.22), 0.355, 0.780, 1.105, 1.645,
        (
            (-2.285, 0.650, 0.407, 0.951), (-2.266, 0.750, 0.345, 0.969),
            (-2.215, 0.825, 0.303, 0.990), (-2.125, 0.882, 0.275, 1.015),
            (-1.985, 0.907, 0.260, 1.041), (-1.700, 0.914, 0.252, 1.077),
            (-1.400, 0.914, 0.250, 1.083), (-1.100, 0.900, 0.250, 1.107),
            (-0.900, 0.896, 0.250, 1.115), (-0.200, 0.900, 0.250, 1.132),
            (0.450, 0.903, 0.250, 1.150), (1.220, 0.917, 0.252, 1.177),
            (1.650, 0.916, 0.260, 1.198), (1.970, 0.906, 0.280, 1.205),
            (2.160, 0.880, 0.315, 1.199), (2.250, 0.803, 0.363, 1.181),
            (2.285, 0.694, 0.418, 1.155),
        ),
        ((-1.075, 1.090), (-0.79, 1.292), (-0.42, 1.548), (-0.10, 1.628),
         (0.55, 1.645), (1.32, 1.642), (1.53, 1.610), (1.74, 1.455),
         (2.105, 1.185)),
        (
            ("Front door", ((-0.969, 1.159), (-0.412, 1.508), (-0.15, 1.581),
                            (0.270, 1.594), (0.269, 1.166)), "Cabin glass"),
            ("Rear door", ((0.355, 1.173), (0.352, 1.594), (1.035, 1.583),
                           (1.174, 1.211)), "Privacy glass"),
            ("Quarter", ((1.255, 1.222), (1.122, 1.582), (1.474, 1.528),
                         (1.866, 1.316), (1.598, 1.242)), "Privacy glass"),
        ),
    ),
}


def outline(points, radius=0.035):
    return rounded_polygon(points, radius, steps=4, edge_step=0.065)


def rectangle(cx, cy, width, height, radius=0.025):
    return outline(((cx - width / 2, cy - height / 2),
                    (cx + width / 2, cy - height / 2),
                    (cx + width / 2, cy + height / 2),
                    (cx - width / 2, cy + height / 2)), radius)


def smooth_value(points, x, column=1):
    if x <= points[0][0]:
        return points[0][column]
    if x >= points[-1][0]:
        return points[-1][column]
    index = next(i for i in range(len(points) - 1) if x <= points[i + 1][0])

    def slope(i):
        a, b = points[i], points[i + 1]
        return (b[column] - a[column]) / (b[0] - a[0])

    def tangent(i):
        if i == 0:
            return slope(0)
        if i == len(points) - 1:
            return slope(i - 1)
        left, right = slope(i - 1), slope(i)
        if left * right <= 0:
            return 0.0
        return 2 * left * right / (left + right)

    a, b = points[index], points[index + 1]
    width = b[0] - a[0]
    t = (x - a[0]) / width
    return ((2 * t ** 3 - 3 * t ** 2 + 1) * a[column]
            + (t ** 3 - 2 * t ** 2 + t) * width * tangent(index)
            + (-2 * t ** 3 + 3 * t ** 2) * b[column]
            + (t ** 3 - t ** 2) * width * tangent(index + 1))


def smooth_loop(points, samples=3):
    points = [Vector(p) for p in points]
    result = []
    for i, b in enumerate(points):
        a, c, d = points[i - 1], points[(i + 1) % len(points)], points[(i + 2) % len(points)]
        for step in range(samples):
            t = step / samples
            result.append(0.5 * ((2 * b) + (-a + c) * t
                                 + (2 * a - 5 * b + 4 * c - d) * t * t
                                 + (-a + 3 * b - 3 * c + d) * t ** 3))
    return result


class ReferenceCar(Asset):
    def __init__(self, spec):
        super().__init__(
            spec.prefix, spec.scene_name, spec.root_name,
            ("Bodywork", "Glazing", "Wheels", "Details", "Interior"),
            notes={
                "reference": f"Dimensional study of tools\\reference\\{spec.reference}.",
                "vehicle": spec.title + "; original unbranded geometry.",
                "axes": "Meters, Z up, nose -Y. Wheel pivots rotate on local X.",
                "rights": "No image pixels, traced surfaces, logos or wordmarks embedded.",
            },
        )
        self.spec = spec
        self.wheels = {}
        self.root["wheelbase_m"] = spec.axles[1] - spec.axles[0]
        self.root["tire_radius_m"] = spec.tire_radius
        self.root["reference_file"] = spec.reference
        self.root["forward_axis"] = "-Y"
        self.build_materials()

    def build_materials(self):
        self.material("Body paint", srgb(self.spec.paint),
                      metallic=0.68 if self.spec.suv else 0.22,
                      roughness=0.28 if self.spec.suv else 0.24, coat=0.24)
        self.material("Panel seams", (0.014, 0.018, 0.023), roughness=0.48)
        self.material("Rubber", (0.007, 0.009, 0.012), roughness=0.62)
        self.material("Tire rubber", (0.012, 0.015, 0.019), roughness=0.72)
        self.material("Grille", (0.025, 0.031, 0.038), metallic=0.40, roughness=0.32)
        self.material("Alloy", (0.48, 0.52, 0.58), metallic=0.86, roughness=0.24)
        self.material("Wheel graphite", (0.028, 0.038, 0.052), metallic=0.86, roughness=0.29)
        self.material("Chrome", (0.67, 0.72, 0.78), metallic=0.96, roughness=0.15)
        self.material("Brake steel", (0.14, 0.16, 0.18), metallic=0.79, roughness=0.42)
        self.material("Mirror", (0.53, 0.62, 0.66), metallic=0.99, roughness=0.065)
        self.material("Cabin", (0.023, 0.029, 0.036), roughness=0.78)
        self.material("Upholstery", (0.055, 0.064, 0.075), roughness=0.90)
        self.material("Headlight", (0.79, 0.85, 0.94), metallic=0.22,
                      roughness=0.19, emission=0.18)
        self.material("Smoked optics", (0.025, 0.043, 0.059), metallic=0.30,
                      roughness=0.20, coat=0.22)
        self.material("Amber", (0.88, 0.205, 0.005), roughness=0.23, coat=0.30)
        self.material("Red lens", (0.26, 0.002, 0.006), roughness=0.26,
                      coat=0.20, emission=0.08)
        self.material("Red lens dark", (0.048, 0.0007, 0.002), roughness=0.29, coat=0.18)
        self.material("Reverse", (0.57, 0.65, 0.72), metallic=0.27, roughness=0.20)
        for name, color, viewport in (
            ("Cabin glass", (0.40, 0.49, 0.51), (0.055, 0.095, 0.11)),
            ("Privacy glass", (0.12, 0.18, 0.21), (0.025, 0.040, 0.055)),
            ("Lamp glass", (0.76, 0.86, 0.92), (0.38, 0.47, 0.54)),
        ):
            mat = self.material(name, color, roughness=0.10, coat=0.02)
            shader = mat.node_tree.nodes["Principled BSDF"]
            shader.inputs["Transmission Weight"].default_value = 1.0
            shader.inputs["Specular IOR Level"].default_value = 0.16 if name == "Lamp glass" else 0.08
            if name == "Lamp glass":
                shader.inputs["IOR"].default_value = 1.33
            mat.diffuse_color = (*viewport, 1.0)
        self.material("Studio floor", (0.16, 0.19, 0.225), roughness=0.59)

    def lines(self, name, paths, radius, mat, group="Details", cyclic=False):
        data = bpy.data.curves.new(f"{self.prefix} | {name}", "CURVE")
        data.dimensions = "3D"
        data.resolution_u = 1
        data.bevel_depth = radius
        data.bevel_resolution = 1
        for points in paths:
            spline = data.splines.new("POLY")
            spline.points.add(len(points) - 1)
            for point, coordinate in zip(spline.points, points):
                point.co = (*coordinate, 1.0)
            spline.use_cyclic_u = cyclic
        data.materials.append(self.materials[mat])
        obj = bpy.data.objects.new(f"{self.prefix} | {name}", data)
        return self.put(obj, group)

    def curve(self, name, points, radius, mat, group="Details", cyclic=False):
        return self.lines(name, [points], radius, mat, group, cyclic)

    def orient(self, obj, normal):
        direction = sum((p.normal * p.area for p in obj.data.polygons), Vector())
        if direction.dot(Vector(normal)) < 0:
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
            bm.to_mesh(obj.data)
            bm.free()
        return obj

    @staticmethod
    def patch_geometry(border, mapper, radial_steps=5):
        center = sum((Vector(p) for p in border), Vector((0, 0))) / len(border)
        vertices = [mapper(*center)]
        count = len(border)
        for row in range(1, radial_steps + 1):
            scale = row / radial_steps
            vertices.extend(mapper(*center.lerp(Vector(p), scale)) for p in border)
        faces = [(0, i + 1, (i + 1) % count + 1) for i in range(count)]
        for row in range(radial_steps - 1):
            faces.extend((1 + row * count + i, 1 + row * count + (i + 1) % count,
                          1 + (row + 1) * count + (i + 1) % count,
                          1 + (row + 1) * count + i) for i in range(count))
        return vertices, faces

    def patch(self, name, border, mapper, mat, group="Details", normal=(0, 0, 1),
              thickness=0.0, radial_steps=5):
        vertices, faces = self.patch_geometry(border, mapper, radial_steps)
        obj = self.mesh(name, vertices, faces, mat, group, smooth=True)
        self.orient(obj, normal)
        if thickness:
            self.solidify(obj, thickness, offset=-1)
        return obj

    def solidify(self, obj, thickness, offset=0.0):
        harden_surface_edges(obj)
        return super().solidify(obj, thickness, offset)

    def ribbon(self, name, points, width, mapper, mat, normal, thickness=0.003):
        path = []
        for a, b in zip(points, points[1:]):
            a, b = Vector(a), Vector(b)
            steps = max(1, math.ceil((b - a).length / 0.035))
            path.extend(a.lerp(b, i / steps) for i in range(steps))
        path.append(Vector(points[-1]))
        vertices = []
        for i, point in enumerate(path):
            tangent = path[min(i + 1, len(path) - 1)] - path[max(0, i - 1)]
            across = Vector((-tangent.y, tangent.x)).normalized() * width / 2
            vertices.extend((mapper(*(point - across)), mapper(*(point + across))))
        faces = [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(len(path) - 1)]
        obj = self.mesh(name, vertices, faces, mat, smooth=True)
        self.orient(obj, normal)
        self.solidify(obj, thickness)
        return obj

    def cutter(self, name, border, mapper, offset):
        offset = Vector(offset)
        # A curved aperture must share the pane tessellation, not use nonplanar ngon caps.
        surface, front_faces = self.patch_geometry(border, mapper)
        points = [Vector(point) for point in surface]
        vertices = [p - offset for p in points] + [p + offset for p in points]
        n = len(points)
        faces = [tuple(reversed(face)) for face in front_faces]
        faces.extend(tuple(index + n for index in face) for face in front_faces)
        count = len(border)
        first = n - count
        for i in range(count):
            a, b = first + i, first + (i + 1) % count
            faces.append((a, b, b + n, a + n))
        return self.mesh(name, vertices, faces)

    def weighted(self, obj):
        mod = obj.modifiers.new("Area weighted manufactured normals", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
        mod.weight = 40

    def interpolate(self, y, column):
        return smooth_value(self.spec.stations, y, column)

    @staticmethod
    def project(tree, origin, direction, offset=0.0):
        point, normal, _, _ = tree.ray_cast(Vector(origin), Vector(direction), 10)
        if point is None:
            raise ValueError(f"No authored skin from {origin} along {direction}.")
        return tuple(point + normal * offset)

    def body_width(self, y, z):
        point, _, _, _ = self.body_surface.ray_cast(Vector((2, y, z)), Vector((-1, 0, 0)), 4)
        return point.x if point is not None else 0.0

    def cabin_width(self, z, y=0.0):
        return self.project(self.cabin_surface, (2, y, z), (-1, 0, 0))[0]

    def cabin_side(self, side, y, z, offset=0.0):
        return self.project(self.cabin_surface, (side * 2, y, z), (-side, 0, 0), offset)

    def side_point(self, side, y, z, offset=0.004):
        hits = []
        for tree in (self.body_surface, self.cabin_surface):
            point, normal, _, _ = tree.ray_cast(
                Vector((side * 2, y, z)), Vector((-side, 0, 0)), 4)
            if point is not None:
                hits.append((side * point.x, point, normal))
        if not hits:
            raise ValueError(f"No side panel at y={y}, z={z}.")
        _, point, normal = max(hits, key=lambda hit: hit[0])
        return tuple(point + normal * offset)

    def cabin_edge(self, value, coordinate, rear=True):
        if coordinate == 0:
            return self.project(self.cabin_surface, (0, value, 3), (0, 0, -1))[2]
        return self.glazing_point(0, value, rear, 0)[1]

    def glazing_point(self, x, z, rear=False, offset=0.005):
        return self.project(self.cabin_surface, (x, 4 if rear else -4, z),
                            (0, -1 if rear else 1, 0), offset)

    def face_point(self, x, z, rear=False, offset=0.012):
        return self.project(self.body_surface, (x, 4 if rear else -4, z),
                            (0, -1 if rear else 1, 0), offset)

    def face_patch(self, name, border, mat, rear=False, offset=0.012, thickness=0):
        mapper = lambda x, z: self.face_point(x, z, rear, offset)
        return self.patch(name, border, mapper, mat, normal=(0, 1 if rear else -1, 0),
                          thickness=thickness, radial_steps=8)

    def split_bumper_cladding(self, name, border, center_y, half_depth):
        tool = self.cutter(name + " region", border,
                           lambda x, z: (x, center_y, z), (0, half_depth, 0))
        panel = self.body.copy()
        panel.data = self.body.data.copy()
        panel.name = panel.data.name = f"{self.prefix} | {name}"
        self.put(panel, "Bodywork")
        intersection = panel.modifiers.new("Integrated bumper cladding", "BOOLEAN")
        intersection.operation = "INTERSECT"
        intersection.solver = "EXACT"
        intersection.object = tool
        self.apply(panel, intersection)
        self.difference(self.body, tool)
        if not panel.data.polygons:
            raise ValueError(f"Empty bumper region: {name}.")
        panel.data.materials.clear()
        panel.data.materials.append(self.materials["Rubber"])
        for polygon in panel.data.polygons:
            polygon.material_index = 0

    def loft(self, name, rings, mat=None, shaped_ends=False):
        count = len(rings[0])
        vertices = [point for ring in rings for point in ring]
        faces = []
        for row in range(len(rings) - 1):
            faces.extend((row * count + i, row * count + (i + 1) % count,
                          (row + 1) * count + (i + 1) % count, (row + 1) * count + i)
                         for i in range(count))
        if shaped_ends:
            for row, sign in ((0, -1), (len(rings) - 1, 1)):
                ring = rings[row]
                middle = (min(p[2] for p in ring) + max(p[2] for p in ring)) / 2
                outside = [row * count + i for i in range(count)]
                for step in range(11, 0, -1):
                    scale = step / 12
                    inside = list(range(len(vertices), len(vertices) + count))
                    for x, y, z in ring:
                        x, z = x * scale, middle + (z - middle) * scale
                        if sign > 0:
                            plate_z = 0.928 if self.spec.suv else 0.565
                            depth = (0.038 * math.exp(-((z - 0.48) / 0.14) ** 2)
                                     - 0.028 * math.exp(-(x / 0.34) ** 4
                                                       - ((z - plate_z) / 0.135) ** 4)
                                     + 0.010 * math.exp(-((z - 0.73) / 0.040) ** 2))
                        else:
                            depth = 0.026 * math.exp(-((z - 0.55) / 0.15) ** 2)
                        vertices.append((x, y + sign * depth * (1 - scale * scale), z))
                    faces.extend((outside[i], outside[(i + 1) % count],
                                  inside[(i + 1) % count], inside[i]) for i in range(count))
                    outside = inside
                faces.append(tuple(outside))
        else:
            faces.extend((tuple(reversed(range(count))),
                          tuple((len(rings) - 1) * count + i for i in range(count))))
        return self.mesh(name, vertices, faces, mat, "Bodywork", smooth=True)

    @staticmethod
    def stations(points, step):
        values = [points[0][0]]
        for a, b in zip(points, points[1:]):
            count = max(1, math.ceil((b[0] - a[0]) / step))
            values.extend(a[0] + (b[0] - a[0]) * i / count for i in range(1, count + 1))
        return values

    def build_body(self):
        rings = []
        for y in self.stations(self.spec.stations, 0.065):
            width, bottom, top = (self.interpolate(y, i) for i in (1, 2, 3))
            half = [(0, top + 0.021), (0.40 * width, top + 0.014),
                    (0.72 * width, top + 0.003), (0.89 * width, top - 0.020),
                    (0.986 * width, top - 0.060), (width, top - 0.113),
                    (0.985 * width, top - 0.235), (0.950 * width, top - 0.365),
                    (0.947 * width, bottom + 0.105), (0.925 * width, bottom + 0.026),
                    (0.80 * width, bottom), (0, bottom)]
            section = half + [(-x, z) for x, z in half[-2:0:-1]]
            ring = []
            for x, z in smooth_loop(section):
                side_weight = max(0, min(1, (abs(x) / width - 0.72) / 0.25))
                flare = sum(0.014 * math.exp(-((math.hypot(y - axle, z - self.spec.tire_radius)
                                               - self.spec.tire_radius - 0.070) / 0.075) ** 2)
                            for axle in self.spec.axles)
                crease_z = (0.55 if self.spec.suv else 0.48) + 0.10 * ((y + 0.90) / 1.90) ** 2
                door_pressing = (0.029 if self.spec.suv else 0.021) * math.exp(
                    -((y + 0.02) / 0.91) ** 6 - ((z - crease_z) / 0.105) ** 2)
                x += (1 if x >= 0 else -1) * (flare - door_pressing) * side_weight
                ring.append((x, y, max(bottom, z)))
            rings.append(ring)
        body = self.loft("Sculpted body shell and bumpers", rings, "Body paint", shaped_ends=True)
        self.body = body
        bpy.context.view_layer.update()
        self.body_surface = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
        arch = self.spec.tire_radius + (0.045 if self.spec.suv else 0.042)
        for side in (-1, 1):
            for axle in self.spec.axles:
                tool = self.cylinder("Wheel aperture tool", (side * 0.86, axle,
                                     self.spec.tire_radius), arch, 0.69, None,
                                     segments=64, rotation=(0, 90, 0))
                self.difference(body, tool)
        tool = self.box("Hollow interior tool",
                        (0, 0.57, 0.925) if self.spec.suv else (0, 0.36, 0.80),
                        (1.51, 3.02, 1.16) if self.spec.suv else (1.55, 2.75, 0.95),
                        None, radius=0.055, segments=3)
        for modifier in list(tool.modifiers):
            self.apply(tool, modifier)
        self.difference(body, tool)
        self.bevel(body, 0.004, segments=2, angle=55, apply=True)
        self.build_cabin()
        self.build_arches(arch)
        self.box("Enclosed underfloor", (0, 0.10, 0.27 if self.spec.suv else 0.19),
                 (1.42, 3.70, 0.10), "Rubber", radius=0.04)

        hood = outline(((-0.62, self.spec.stations[2][0]), (0.62, self.spec.stations[2][0]),
                        (0.768, -1.095), (-0.768, -1.095)), 0.045)
        mapper = lambda x, y: self.project(self.body_surface, (x, y, 3), (0, 0, -1), 0.0008)
        self.curve("Hood shut line", [mapper(*p) for p in hood],
                   0.0012, "Panel seams", cyclic=True)
        print("Built compound-curved body skins and an integrated hood.", flush=True)

    def build_cabin(self):
        rings = []
        first, last = self.spec.roof[0][0], self.spec.roof[-1][0]
        for y in self.stations(self.spec.roof, 0.050):
            roof = smooth_value(self.spec.roof, y)
            base = min(roof - 0.016, self.interpolate(y, 3) - 0.018)
            height = roof - base
            end_factor = min(1, max(0, min(y - first, last - y) / 0.60))
            width = (0.865 if self.spec.suv else 0.873) * (0.958 + 0.042 * end_factor)
            roof_width = (0.742 if self.spec.suv else 0.725) * (0.952 + 0.048 * end_factor)
            drop = min(0.047, height * 0.32)
            half = [(0, roof), (roof_width * 0.37, roof - drop * 0.06),
                    (roof_width * 0.72, roof - drop * 0.26),
                    (roof_width * 0.94, roof - drop * 0.65),
                    (roof_width, roof - drop),
                    (width * 0.99, base + height * 0.15),
                    (width, base), (width * 0.985, base - 0.037),
                    (width * 0.78, base - 0.080), (0, base - 0.080)]
            points = half + [(-x, z) for x, z in half[-2:0:-1]]
            rings.append([(x, y, z) for x, z in smooth_loop(points)])
        self.cabin = self.loft("Hollow roof and pillars", rings, "Body paint")
        bpy.context.view_layer.update()
        self.cabin_surface = BVHTree.FromObject(self.cabin, bpy.context.evaluated_depsgraph_get())
        inner = [[(x * 0.944, 0.36 + (y - 0.36) * 0.980, z - 0.038)
                  for x, y, z in ring] for ring in rings]
        self.difference(self.cabin, self.loft("Cabin cavity tool", inner))

    def build_arches(self, arch):
        for side in (-1, 1):
            for index, axle in enumerate(self.spec.axles):
                for label, radii, bulges, mat in (
                    ("Rolled fender", (arch, arch + 0.007, arch + 0.020),
                     (0.002, 0.004, 0.0005), "Body paint"),
                    *((("Arch cladding", (arch - 0.001, arch + 0.017, arch + 0.040),
                        (0.004, 0.008, 0.004), "Rubber"),) if self.spec.suv else ()),
                ):
                    vertices, faces = [], []
                    start = -8 if self.spec.suv else -17
                    for radius, bulge in zip(radii, bulges):
                        for i in range(49):
                            angle = math.radians(start + (180 - 2 * start) * i / 48)
                            y = axle + radius * math.cos(angle)
                            z = self.spec.tire_radius + radius * math.sin(angle)
                            vertices.append((side * (self.body_width(y, z) + bulge), y, z))
                    for row in range(len(radii) - 1):
                        faces.extend((row * 49 + i, row * 49 + i + 1,
                                      (row + 1) * 49 + i + 1, (row + 1) * 49 + i)
                                     for i in range(48))
                    obj = self.mesh(f"{side:+d} {index} {label}", vertices, faces, mat,
                                    "Bodywork", smooth=True)
                    self.orient(obj, (side, 0, 0))
                    self.solidify(obj, 0.003, offset=-1)
                vertices = []
                for x in (0.57, 0.87):
                    for i in range(49):
                        angle = math.pi * i / 48
                        vertices.append((side * x, axle + arch * math.cos(angle),
                                         self.spec.tire_radius + arch * math.sin(angle)))
                faces = [(i, i + 1, 50 + i, 49 + i) for i in range(48)]
                obj = self.mesh(f"{side:+d} {index} dark wheel well", vertices, faces,
                                "Rubber", smooth=True)
                self.solidify(obj, 0.006)

    def build_glazing(self):
        for side in (-1, 1):
            mapper = lambda y, z, s=side: self.cabin_side(s, y, z, 0.001)
            for name, points, mat in self.spec.windows:
                border = outline(points, 0.060 if name != "Quarter" else 0.025)
                tool = self.cutter("Side window aperture", border, mapper, (0.19, 0, 0))
                self.difference(self.cabin, tool)
                self.patch(f"{side:+d} {name} glass", border, mapper, mat, "Glazing",
                           normal=(side, 0, 0), thickness=0.004)
                self.curve(f"{side:+d} {name} bonded seal", [mapper(*p) for p in border],
                           0.0055, "Rubber", "Glazing", cyclic=True)
            center_y = 0.314 if self.spec.suv else 0.225
            low, high = ((1.169, 1.595) if self.spec.suv else (1.076, 1.415))
            border = rectangle(center_y, (low + high) / 2, 0.096, high - low, 0.007)
            self.patch(f"{side:+d} satin B pillar", border, mapper, "Rubber", "Glazing",
                       normal=(side, 0, 0), thickness=0.008)
            surround = (
                ((-0.972, 1.152), (-0.417, 1.519), (-0.15, 1.591), (0.30, 1.604),
                 (1.048, 1.595), (1.482, 1.539), (1.886, 1.316), (1.60, 1.234))
                if self.spec.suv else
                ((-0.968, 1.065), (-0.372, 1.381), (-0.11, 1.421), (0.20, 1.423),
                 (0.62, 1.388), (0.90, 1.292), (1.529, 1.104))
            )
            self.curve(f"{side:+d} continuous glasshouse chrome",
                       [(x + side * 0.004, y, z) for x, y, z in
                        (mapper(*p) for p in outline(surround, 0.055))],
                       0.0022, "Chrome", "Glazing", cyclic=True)

        for rear, bottom, top in (
            (False, 1.17 if self.spec.suv else 1.075, self.spec.cabin_height - 0.095),
            (True, 1.225 if self.spec.suv else 1.105, self.spec.cabin_height - 0.090),
        ):
            border = outline(((-0.795, bottom), (0.795, bottom),
                              (0.678, top), (-0.678, top)), 0.050)
            mapper = lambda x, z, r=rear: self.glazing_point(x, z, r)
            tool = self.cutter("Backlight aperture" if rear else "Windshield aperture",
                               border, mapper, (0, 0.15, 0))
            self.difference(self.cabin, tool)
            name = "Rear backlight" if rear else "Curved windshield"
            self.patch(name, border, mapper, "Privacy glass" if rear else "Cabin glass",
                       "Glazing", normal=(0, 1 if rear else -1, 0), thickness=0.005)
            self.curve(name + " perimeter seal", [mapper(*p) for p in border],
                       0.0075, "Rubber", "Glazing", cyclic=True)
            if rear:
                paths = []
                for i in range(7):
                    z = bottom + 0.030 + (top - bottom - 0.065) * i / 6
                    paths.append([self.glazing_point(x, z, True, 0.009)
                                  for x in (-0.62, 0, 0.62)])
                self.lines("Rear demister", paths, 0.0008, "Brake steel", "Glazing")
            else:
                for i, x in enumerate((-0.36, 0.34)):
                    points = [self.glazing_point(x - 0.18, bottom + 0.017, False, 0.02),
                              self.glazing_point(x + 0.24, bottom + 0.027, False, 0.02)]
                    self.curve(f"Windshield wiper {i + 1}", points, 0.008, "Rubber")
        if self.spec.suv:
            border = rectangle(0, 0.28, 1.03, 0.79, 0.07)
            mapper = lambda x, y: self.project(self.cabin_surface, (x, y, 3), (0, 0, -1), 0.003)
            self.difference(self.cabin, self.cutter("Sunroof opening", border, mapper, (0, 0, 0.15)))
            self.patch("Inset sunroof", border, mapper, "Privacy glass", "Glazing",
                       thickness=0.005)
            self.curve("Sunroof seal", [mapper(*p) for p in border], 0.007,
                       "Rubber", "Glazing", cyclic=True)
        self.bevel(self.cabin, 0.0025, segments=2)
        print("Fitted separate glass in actual window apertures.", flush=True)

    def build_wheels(self):
        radius = self.spec.tire_radius
        rim = 0.218 if self.spec.suv else 0.223
        profile = [
            (-0.092, rim), (-0.109, radius * 0.76), (-0.110, radius * 0.85),
            (-0.099, radius * 0.93), (-0.076, radius * 0.990),
            (-0.059, radius), (-0.054, radius - 0.007), (-0.047, radius - 0.007),
            (-0.042, radius), (-0.014, radius), (-0.009, radius - 0.007),
            (-0.002, radius - 0.007), (0.003, radius), (0.038, radius),
            (0.043, radius - 0.007), (0.050, radius - 0.007), (0.055, radius),
            (0.076, radius * 0.990), (0.099, radius * 0.93),
            (0.110, radius * 0.85), (0.109, radius * 0.76), (0.092, rim),
        ]
        for side in (-1, 1):
            for axle_index, y in enumerate(self.spec.axles):
                code = ("L" if side > 0 else "R") + ("F" if axle_index == 0 else "R")
                center = (side * self.spec.half_track, y, radius)
                before = set(self.model.all_objects)
                rotation = (0, side * 90, 0)
                self.lathe(code + " grooved tire", profile, "Tire rubber", "Wheels",
                           segments=64, location=center, rotation=rotation, caps=False, closed=True)
                outer = self.spec.half_track + 0.108
                for r in (rim + 0.009, radius * 0.87):
                    self.torus(code + " sidewall bead", (side * outer, y, radius), r, 0.0017,
                               "Tire rubber", "Wheels", segments=64, sides=6, rotation=rotation)
                self.lathe(code + " alloy barrel",
                           [(-0.080, rim - 0.013), (-0.080, rim),
                            (0.095, rim), (0.107, rim - 0.005),
                            (0.085, rim - 0.017), (-0.066, rim - 0.023)],
                           "Wheel graphite", "Wheels", segments=64, location=center,
                           rotation=rotation, caps=False, closed=True)
                self.torus(code + " machined rim lip", (side * outer, y, radius),
                           rim - 0.005, 0.0035, "Chrome", "Wheels",
                           segments=64, sides=8, rotation=rotation)
                self.cylinder(code + " brake rotor", (side * (outer - 0.037), y, radius),
                              rim * 0.78, 0.018, "Brake steel", "Wheels",
                              segments=48, rotation=rotation)
                fixed_caliper = self.box(
                    code + " fixed brake caliper", (side * (outer - 0.027), y + 0.135, radius),
                    (0.040, 0.060, 0.125), "Rubber", "Wheels", radius=0.014, segments=2)
                for spoke in range(5):
                    for branch in (-1, 1):
                        angle = math.tau * spoke / 5 + 0.08 + branch * (0.16 if self.spec.suv else 0.15)
                        shape = ((0.044, -0.014), (0.093, -0.016), (rim - 0.020, -0.013),
                                 (rim - 0.010, 0.007), (rim - 0.015, 0.017), (0.078, 0.020))
                        vertices = []
                        for depth in (0.0, -0.025):
                            for r, t in shape:
                                vertices.append((side * (outer + 0.004 - 0.022 * r / rim + depth),
                                                 y + r * math.cos(angle) - t * math.sin(angle),
                                                 radius + r * math.sin(angle) + t * math.cos(angle)))
                        n = len(shape)
                        faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
                        faces.extend((i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n))
                        obj = self.mesh(f"{code} split spoke {spoke + 1} {branch:+d}",
                                        vertices, faces, "Wheel graphite", "Wheels", smooth=True)
                        self.bevel(obj, 0.0035, segments=2)
                        self.weighted(obj)
                        front = []
                        for r, t in shape:
                            t *= 0.61 if self.spec.suv else 0.49
                            front.append((side * (outer + 0.006 - 0.022 * r / rim),
                                          y + r * math.cos(angle) - t * math.sin(angle),
                                          radius + r * math.sin(angle) + t * math.cos(angle)))
                        face = self.mesh(f"{code} machined spoke face {spoke + 1} {branch:+d}",
                                         front, [tuple(range(n))], "Alloy", "Wheels")
                        self.orient(face, (side, 0, 0))
                self.cylinder(code + " hub", (side * (outer + 0.007), y, radius),
                              0.060, 0.024, "Alloy", "Wheels", segments=40, rotation=rotation)
                for i in range(5):
                    angle = math.tau * i / 5 + 0.08
                    position = (side * (outer + 0.022), y + 0.039 * math.cos(angle),
                                radius + 0.039 * math.sin(angle))
                    self.cylinder(code + " lug recess", position, 0.010, 0.006,
                                  "Rubber", "Wheels", segments=16, rotation=rotation)
                    self.cylinder(code + " hex lug bolt",
                                  (position[0] + side * 0.005, *position[1:]),
                                  0.0065, 0.008, "Chrome", "Wheels", segments=6, rotation=rotation)
                self.cylinder(code + " plain center cap", (side * (outer + 0.023), y, radius),
                              0.023, 0.011, "Chrome", "Wheels", segments=32, rotation=rotation)
                pivot = self.empty(code + " wheel pivot", center)
                self.put(pivot, "Wheels")
                pivot["wheel_code"] = code
                pivot["rotation_axis"] = "Local X"
                bpy.context.view_layer.update()
                for obj in set(self.model.all_objects) - before - {pivot, fixed_caliper}:
                    transform = obj.matrix_world.copy()
                    obj.parent = pivot
                    obj.matrix_world = transform
                self.wheels[code] = pivot
        print("Built four independently pivoted split-spoke wheels.", flush=True)

    def build_sides(self):
        suv = self.spec.suv
        front_path = ((-0.975, 1.151), (-0.935, 0.48), (-0.81, 0.32),
                      (0.314, 0.32), (0.314, 1.169)) if suv else (
                          (-0.973, 1.053), (-0.94, 0.39), (-0.78, 0.232),
                          (0.225, 0.232), (0.225, 1.080))
        rear_path = ((0.314, 0.32), (0.78, 0.32), (0.90, 0.57),
                     (1.08, 0.81), (1.315, 0.95), (1.245, 1.20), (0.314, 1.169)) if suv else (
                         (0.225, 0.232), (0.72, 0.232), (0.90, 0.54),
                         (1.17, 0.76), (1.37, 0.91), (1.18, 1.100), (0.225, 1.080))
        for side in (-1, 1):
            for name, points in (("Front", front_path), ("Rear", rear_path)):
                border = outline(points, 0.035) if name == "Front" else points
                self.curve(f"{side:+d} {name} door shut line",
                           [self.side_point(side, y, z, 0.0015) for y, z in border],
                           0.0012, "Panel seams", cyclic=name == "Front")
            for index, y in enumerate((-0.01, 1.06) if suv else (-0.09, 1.00)):
                z = (1.036 if suv else 0.958) + 0.010 * index
                x = side * (self.body_width(y, z) + 0.010)
                self.box(f"{side:+d} {index} handle recess", (x, y, z),
                         (0.015, 0.23, 0.037), "Panel seams", radius=0.016, segments=3)
                self.box(f"{side:+d} {index} door handle", (x + side * 0.019, y, z + 0.006),
                         (0.027, 0.196, 0.035), "Body paint", radius=0.014, segments=3)
                self.box(f"{side:+d} {index} handle bright edge",
                         (x + side * 0.034, y, z + 0.016), (0.004, 0.159, 0.006),
                         "Chrome", radius=0.002)
            z = 0.298 if suv else 0.223
            self.box(f"{side:+d} rocker sill", (side * 0.88, -0.02, z),
                     (0.064, 1.77, 0.105 if suv else 0.054),
                     "Rubber" if suv else "Body paint", radius=0.018, segments=3)
            mirror_y, mirror_z = (-0.91, 1.222) if suv else (-0.88, 1.114)
            self.curve(f"{side:+d} mirror support",
                       [(side * 0.86, mirror_y + 0.045, mirror_z - 0.045),
                        (side * 0.973, mirror_y, mirror_z - 0.012)],
                       0.030, "Rubber")
            self.sphere(f"{side:+d} mirror housing", (side * 1.0, mirror_y, mirror_z),
                        1, "Body paint", segments=24, rings=12, smooth=True,
                        scale=(0.098, 0.137, 0.064))
            self.sphere(f"{side:+d} mirror lower trim",
                        (side * 1.0, mirror_y + 0.002, mirror_z - 0.035),
                        1, "Rubber", segments=24, rings=10, smooth=True,
                        scale=(0.094, 0.129, 0.032))
            border = rectangle(side * 1.0, mirror_z + 0.002, 0.146, 0.066, 0.024)
            self.patch(f"{side:+d} mirror glass", border,
                       lambda x, z, y=mirror_y: (x, y + 0.108, z),
                       "Mirror", normal=(0, 1, 0), thickness=0.003)
            self.box(f"{side:+d} mirror indicator",
                     (side * 1.006, mirror_y - 0.123, mirror_z - 0.015),
                     (0.087, 0.009, 0.008), "Reverse", radius=0.003)
        fuel_y, fuel_z = (1.64, 1.055) if suv else (1.78, 0.92)
        fuel = rectangle(fuel_y, fuel_z, 0.23, 0.185, 0.04)
        self.curve("Fuel flap", [self.side_point(-1, y, z, 0.005) for y, z in fuel],
                   0.0017, "Panel seams", cyclic=True)
        if suv:
            for side in (-1, 1):
                points = [(side * 0.715, y, self.cabin_edge(y, 0) + height)
                          for y, height in ((-0.10, 0.004), (0.04, 0.031),
                                            (0.53, 0.035), (1.14, 0.033), (1.42, 0.003))]
                self.curve(f"{side:+d} satin roof rail", points, 0.013, "Alloy")
                for y in (-0.03, 1.36):
                    self.box(f"{side:+d} rail foot", (side * 0.715, y, self.cabin_edge(y, 0) - 0.013),
                             (0.062, 0.12, 0.038), "Rubber", radius=0.013, segments=3)
            self.box("Roof spoiler", (0, 1.57, 1.592), (1.49, 0.192, 0.031),
                     "Body paint", radius=0.013, segments=4, rotation=(-24, 0, 0), smooth=True)
        y = 1.34 if suv else 0.79
        z = self.cabin_edge(y, 0)
        fin = self.prism("Shark fin antenna", ((-0.044, 0), (0.044, 0), (0.027, 0.15),
                                              (-0.027, 0.15)), 0.072, "Body paint",
                        location=(0, y, z - 0.015), taper=0.13, smooth=True)
        self.bevel(fin, 0.006, segments=2)

    def grille(self, points, rows, upper_width, lower_width, bottom, top):
        border = outline(points, 0.025)
        self.difference(self.body, self.cutter(
            "Grille aperture", border, lambda x, z: self.face_point(x, z, offset=0), (0, 0.055, 0)))
        self.face_patch("Recessed grille shadow", border, "Rubber", offset=-0.022, thickness=0.003)
        self.curve("Grille chrome perimeter",
                   [self.face_point(x, z, offset=0.005) for x, z in border],
                   0.0045, "Chrome", cyclic=True)
        paths = []
        if not self.spec.suv:
            for row in range(rows + 1):
                z = bottom + (top - bottom) * row / rows
                half = lower_width + (upper_width - lower_width) * (z - bottom) / (top - bottom)
                path = [self.face_point(x, z - 0.006 * (1 - abs(x) / half), offset=-0.011)
                        for x in (-half + 0.02, -half * 0.66, 0, half * 0.66, half - 0.02)]
                paths.append(path)
                if row < rows:
                    for column in range(-5, 6):
                        x = column * 0.112 + (row % 2) * 0.041
                        if abs(x) < half - 0.050:
                            paths.append([self.face_point(x, z, offset=-0.011),
                                          self.face_point(x + 0.026, z + (top - bottom) / rows,
                                                          offset=-0.011)])
            self.lines("Stacked sculpted grille louvres", paths, 0.005, "Grille")
            return
        for row in range(rows):
            z = bottom + (top - bottom) * (row + 0.5) / rows
            half = lower_width + (upper_width - lower_width) * (z - bottom) / (top - bottom)
            for column in range(-10, 11):
                x = (column + 0.5 * (row % 2)) * 0.086
                if abs(x) + 0.042 > half - 0.018:
                    continue
                paths.append([self.face_point(x + dx, z + dz, offset=-0.009)
                              for dx, dz in ((-0.039, 0), (-0.022, -0.024), (0.022, -0.024),
                                             (0.039, 0), (0.022, 0.024), (-0.022, 0.024))])
        self.lines("Geometric grille lattice", paths, 0.0030, "Grille", cyclic=True)

    def headlamp(self, side, points, projectors, suv=False):
        border = outline([(side * x, z) for x, z in points], 0.014)
        self.difference(self.body, self.cutter(
            "Headlamp pocket", border, lambda x, z: self.face_point(x, z, offset=0), (0, 0.085, 0)))
        self.face_patch(f"{side:+d} swept headlamp housing", border, "Rubber", offset=-0.004,
                        thickness=0.004)
        self.curve(f"{side:+d} headlamp chrome surround",
                   [self.face_point(x, z, offset=0.005) for x, z in border],
                   0.0035, "Chrome", cyclic=True)
        for i, (x, z, radius) in enumerate(projectors):
            location = Vector(self.face_point(side * x, z, offset=0.005))
            normal = (Vector(self.face_point(side * x, z, offset=0.015)) - location).normalized()
            rotation = tuple(math.degrees(value) for value in normal.to_track_quat("Z", "Y").to_euler())
            self.cylinder(f"{side:+d} projector reflector {i + 1}", location, radius, 0.009,
                          "Chrome", segments=32, rotation=rotation)
            self.cylinder(f"{side:+d} projector lens {i + 1}",
                          location + normal * 0.006, radius * 0.71,
                          0.005, "Smoked optics", segments=32, rotation=rotation)
            self.torus(f"{side:+d} projector lens rim {i + 1}", location + normal * 0.008,
                       radius * 0.75, 0.002, "Chrome", segments=32, sides=6, rotation=rotation)
        self.patch(f"{side:+d} clear headlamp cover", border,
                   lambda x, z: self.face_point(x, z, offset=0.021),
                   "Lamp glass", "Glazing", normal=(0, -1, 0), thickness=0.002)
        led = ([(0.47, 0.866), (0.66, 0.846), (0.823, 0.944)] if suv
               else [(0.45, 0.790), (0.61, 0.769), (0.80, 0.858)])
        self.curve(f"{side:+d} headlamp LED blade",
                   [self.face_point(side * x, z, offset=0.024) for x, z in led],
                   0.0035, "Headlight")
        x, z = (0.827, 0.927) if suv else (0.817, 0.852)
        amber = rectangle(side * x, z, 0.018, 0.065 if suv else 0.042, 0.006)
        self.face_patch(f"{side:+d} amber corner marker", amber, "Amber", offset=0.024)

    def build_front(self):
        if self.spec.suv:
            self.grille(((-0.61, 0.945), (0.61, 0.945), (0.50, 0.750), (-0.50, 0.750)),
                        3, 0.61, 0.50, 0.758, 0.935)
            for index, z in enumerate((0.918, 0.874)):
                points = [(x, z + 0.021 * abs(x) / 0.59)
                          for x in (-0.59, -0.36, 0, 0.36, 0.59)]
                self.ribbon(f"Chrome grille wing {index + 1}", points,
                            0.028 if index == 0 else 0.016,
                            lambda x, z: self.face_point(x, z, offset=0.008),
                            "Chrome", (0, -1, 0))
            for side in (-1, 1):
                self.headlamp(side, ((0.435, 0.933), (0.827, 0.998),
                                    (0.856, 0.872), (0.622, 0.833), (0.44, 0.858)),
                              ((0.572, 0.895, 0.034), (0.727, 0.927, 0.038)), suv=True)
                border = outline(((side * 0.51, 0.653), (side * 0.825, 0.679),
                                  (side * 0.81, 0.510), (side * 0.615, 0.508)), 0.018)
                self.difference(self.body, self.cutter(
                    "Fog lamp pocket", border,
                    lambda x, z: self.face_point(x, z, offset=0), (0, 0.045, 0)))
                self.face_patch(f"{side:+d} fog lamp bezel", border, "Rubber",
                                offset=-0.009, thickness=0.003)
                self.face_patch(f"{side:+d} fog lamp", rectangle(side * 0.702, 0.584, 0.15, 0.047),
                                "Smoked optics", offset=0.001)
                self.face_patch(f"{side:+d} fog reflector",
                                rectangle(side * 0.702, 0.584, 0.087, 0.026, 0.009),
                                "Reverse", offset=0.007)
            cladding = outline(((-2.0, -0.25), (2.0, -0.25), (2.0, 0.481),
                                (0.60, 0.506), (0, 0.568), (-0.60, 0.506),
                                (-2.0, 0.481)), 0.025)
            self.split_bumper_cladding("Front bumper cladding", cladding, -2.70, 0.95)
            skid = outline(((-0.61, 0.355), (-0.48, 0.490), (0.48, 0.490),
                            (0.61, 0.355)), 0.025)
            self.face_patch("Front satin skid plate", skid, "Alloy", offset=0.014)
            self.face_patch("Lower cooling inlet", rectangle(0, 0.442, 0.84, 0.065, 0.019),
                            "Rubber", offset=0.021)
        else:
            self.grille(((-0.675, 0.786), (0.675, 0.786), (0.775, 0.666),
                         (0.448, 0.364), (-0.448, 0.364), (-0.775, 0.666)),
                        6, 0.70, 0.448, 0.377, 0.775)
            for side in (-1, 1):
                self.headlamp(side, ((0.425, 0.800), (0.83, 0.899),
                                    (0.85, 0.789), (0.61, 0.752)),
                              ((0.57, 0.795, 0.026), (0.68, 0.818, 0.026),
                               (0.773, 0.848, 0.024)))
                border = outline(((side * 0.590, 0.385), (side * 0.644, 0.502),
                                  (side * 0.845, 0.550), (side * 0.831, 0.360)), 0.014)
                self.difference(self.body, self.cutter(
                    "Air curtain opening", border,
                    lambda x, z: self.face_point(x, z, offset=0), (0, 0.040, 0)))
                self.face_patch(f"{side:+d} lower bumper air curtain", border,
                                "Rubber", offset=-0.006, thickness=0.003)
                for index in range(4):
                    x = side * (0.68 + index * 0.040)
                    points = [self.face_point(x, z, offset=0.002) for z in (0.388, 0.477)]
                    self.curve(f"{side:+d} intake fin {index + 1}", points, 0.0045, "Grille")
            splitter = [self.face_point(x, 0.313 + 0.020 * abs(x), offset=0.021)
                        for x in (-0.83, -0.64, -0.35, 0, 0.35, 0.64, 0.83)]
            self.curve("Front lower chrome blade", splitter, 0.010, "Chrome")
            self.face_patch("Lower central intake", rectangle(0, 0.305, 1.04, 0.042, 0.012),
                            "Rubber", offset=0.032)
        print("Built reference-specific front lights, grilles and bumper details.", flush=True)

    def build_rear(self):
        suv = self.spec.suv
        if suv:
            hatch = outline(((-0.76, 0.49), (0.76, 0.49), (0.82, 1.154),
                             (0.66, 1.170), (-0.66, 1.170), (-0.82, 1.154)), 0.06)
            self.curve("Tailgate shut line", [self.face_point(x, z, True, 0.021) for x, z in hatch],
                       0.002, "Panel seams", cyclic=True)
            self.curve("Tailgate chrome garnish",
                       [self.face_point(x, 1.145 - 0.014 * abs(x), True, 0.029)
                        for x in (-0.70, -0.40, 0, 0.40, 0.70)], 0.011, "Chrome")
            for side in (-1, 1):
                border = outline(((0.0, 1.215), (0.10, 1.215), (0.10, 1.550),
                                  (0.065, 1.577), (0.015, 1.564)), 0.010)

                def mapper(u, z, s=side, offset=0.005):
                    inner = 0.807 - 0.355 * (z - 1.225)
                    outer = self.cabin_width(z) * 0.992
                    return self.glazing_point(s * (inner + u * 10 * (outer - inner)),
                                              z, True, offset)

                self.patch(f"{side:+d} D-pillar lamp opaque housing", border,
                           lambda u, z: mapper(u, z, offset=0.001), "Rubber",
                           normal=(0, -1, 0))
                # This rear projection already wraps onto the side without crossing the backlight.
                self.patch(f"{side:+d} tall D-pillar tail lamp", border, mapper, "Red lens",
                           normal=(0, 1, 0), thickness=0.005)
                self.face_patch(f"{side:+d} rear lamp base",
                                rectangle(side * 0.772, 1.106, 0.136, 0.142, 0.018),
                                "Red lens", rear=True, offset=0.012)
                self.face_patch(f"{side:+d} clear reversing segment",
                                rectangle(side * 0.772, 1.112, 0.117, 0.066, 0.012),
                                "Reverse", rear=True, offset=0.017)
                bridge = [
                    self.face_point(side * x, 1.166, True, 0.011) for x in (0.735, 0.817)
                ]
                bridge.extend((
                    mapper(0.10, 1.224),
                    mapper(0.0, 1.224),
                ))
                lamp = self.mesh(f"{side:+d} tail lamp corner bridge", bridge, [(0, 1, 2, 3)],
                                 "Red lens", smooth=True)
                self.orient(lamp, (0, 1, 0))
                self.solidify(lamp, 0.004)
            cladding = rectangle(0, 0.10, 4.0, 0.79, 0.04)
            self.split_bumper_cladding("Rear bumper cladding", cladding, 2.75, 1.0)
            self.face_patch("Rear satin skid plate",
                            outline(((-0.63, 0.371), (-0.53, 0.457), (0.53, 0.457),
                                     (0.63, 0.371)), 0.024),
                            "Alloy", rear=True, offset=0.021)
            location = self.face_point(-0.67, 0.343, True, 0.036)
            self.cylinder("Single exhaust outlet", location, 0.048, 0.13,
                          "Chrome", segments=40, rotation=(90, 0, 0))
            self.cylinder("Exhaust bore", (location[0], location[1] + 0.068, location[2]),
                          0.037, 0.006, "Rubber", segments=40, rotation=(90, 0, 0))
            wiper = [self.glazing_point(x, 1.295 + 0.006 * x, True, 0.025)
                     for x in (-0.36, -0.16, 0.12)]
            self.curve("Rear window wiper", wiper, 0.010, "Rubber")
            self.box("High mount brake light", (0, 1.658, 1.561), (0.55, 0.010, 0.016),
                     "Red lens", radius=0.005, segments=3)
        else:
            trunk = outline(((-0.75, 0.668), (0.75, 0.668), (0.80, 0.923),
                             (0.70, 0.987), (-0.70, 0.987), (-0.80, 0.923)), 0.055)
            self.curve("Trunk shut line", [self.face_point(x, z, True, 0.021) for x, z in trunk],
                       0.0017, "Panel seams", cyclic=True)
            self.curve("Trunk trailing lip",
                       [self.face_point(x, 0.981, True, 0.018)
                        for x in (-0.74, -0.50, 0, 0.50, 0.74)], 0.012, "Body paint", "Bodywork")
            bar = rectangle(0, 0.818, 1.59, 0.035, 0.012)
            self.face_patch("Full width rear light shadow", bar, "Rubber", rear=True, offset=0.027)
            self.face_patch("Continuous red tail light bar", rectangle(0, 0.820, 1.56, 0.018, 0.007),
                            "Red lens", rear=True, offset=0.033)
            for side in (-1, 1):
                border = outline(((side * 0.585, 0.950), (side * 0.842, 0.942),
                                  (side * 0.828, 0.816), (side * 0.727, 0.817)), 0.012)
                self.face_patch(f"{side:+d} angular tail lamp backing", border, "Red lens dark",
                                rear=True, offset=0.013)
                paths = [[self.face_point(side * x, z, True, 0.022)
                          for x, z in ((0.60, 0.941), (0.831, 0.931), (0.816, 0.832),
                                       (0.745, 0.820))]]
                self.lines(f"{side:+d} rear LED hook", paths, 0.010, "Red lens")
                side_border = outline(((1.968, 1.002), (2.354, 0.956),
                                       (2.298, 0.858), (2.13, 0.917)), 0.012)
                self.patch(f"{side:+d} wraparound rear lamp", side_border,
                           lambda y, z, s=side: (s * (self.body_width(y, z) + 0.015), y, z),
                           "Red lens", normal=(side, 0, 0), thickness=0.006)
            diffuser = outline(((-0.78, 0.394), (-0.59, 0.485), (0.59, 0.485),
                                (0.78, 0.394), (0.71, 0.270), (-0.71, 0.270)), 0.02)
            self.face_patch("Rear diffuser", diffuser, "Rubber", rear=True, offset=0.029)
            for side in (-1, 1):
                self.face_patch(f"{side:+d} rectangular exhaust surround",
                                rectangle(side * 0.635, 0.315, 0.253, 0.082, 0.025),
                                "Chrome", rear=True, offset=0.043)
                self.face_patch(f"{side:+d} dark exhaust outlet",
                                rectangle(side * 0.635, 0.316, 0.216, 0.050, 0.016),
                                "Rubber", rear=True, offset=0.049)
        plate_z = 0.928 if suv else 0.565
        self.face_patch("Rear registration recess", rectangle(0, plate_z, 0.51, 0.205, 0.025),
                        "Panel seams", rear=True, offset=0.022)
        self.face_patch("Unmarked registration plate", rectangle(0, plate_z, 0.455, 0.155, 0.014),
                        "Body paint", rear=True, offset=0.031)
        if suv:
            self.face_patch("Tailgate release recess", rectangle(0, 0.728, 0.18, 0.035, 0.010),
                            "Rubber", rear=True, offset=0.004)
        for side in (-1, 1):
            self.face_patch(f"{side:+d} bumper reflector",
                            rectangle(side * 0.678, 0.563 if suv else 0.473,
                                      0.184, 0.040, 0.010), "Red lens", rear=True, offset=0.044)

    def build_interior(self):
        suv = self.spec.suv
        base = 0.635 if suv else 0.515
        self.box("Cabin floor", (0, 0.36, base - 0.18), (1.43, 2.56, 0.045),
                 "Cabin", "Interior", radius=0.03)
        self.box("Dashboard", (0, -0.735, base + 0.32), (1.49, 0.43, 0.18),
                 "Cabin", "Interior", radius=0.065, segments=4, smooth=True)
        self.box("Center console", (0, -0.24, base + 0.06), (0.25, 0.84, 0.28),
                 "Cabin", "Interior", radius=0.035, segments=3)
        self.box("Center display", (0, -0.509, base + 0.365), (0.25, 0.015, 0.13),
                 "Rubber", "Interior", radius=0.014, segments=3, rotation=(-10, 0, 0))
        for side in (-1, 1):
            x = side * 0.405
            self.box(f"{side:+d} seat cushion", (x, -0.15, base), (0.455, 0.51, 0.14),
                     "Upholstery", "Interior", radius=0.052, segments=4, smooth=True)
            self.box(f"{side:+d} seat back", (x, 0.115, base + 0.285), (0.44, 0.17, 0.52),
                     "Upholstery", "Interior", radius=0.062, segments=4,
                     rotation=(-11, 0, 0), smooth=True)
            self.box(f"{side:+d} headrest", (x, 0.182, base + 0.650), (0.245, 0.155, 0.195),
                     "Upholstery", "Interior", radius=0.045, segments=4, smooth=True)
            for edge in (-1, 1):
                self.box(f"{side:+d} seat bolster {edge:+d}",
                         (x + edge * 0.186, -0.125, base + 0.065), (0.07, 0.39, 0.12),
                         "Cabin", "Interior", radius=0.028, segments=3)
        rear_y = 1.06 if suv else 0.93
        self.box("Rear bench cushion", (0, rear_y, base), (1.33, 0.44, 0.14),
                 "Upholstery", "Interior", radius=0.045, segments=3)
        self.box("Rear bench backrest", (0, rear_y + 0.205, base + 0.25), (1.33, 0.15, 0.49),
                 "Upholstery", "Interior", radius=0.043, segments=3, rotation=(-8, 0, 0))
        for x in (-0.445, 0, 0.445):
            self.box("Rear headrest", (x, rear_y + 0.205, base + 0.555), (0.22, 0.14, 0.17),
                     "Upholstery", "Interior", radius=0.032, segments=3)
        wheel_center = (0.405, -0.498, base + 0.51)
        self.torus("Steering wheel", wheel_center, 0.148, 0.015, "Cabin", "Interior",
                   segments=48, sides=8, rotation=(75, 0, 0))
        self.cylinder("Steering hub", wheel_center, 0.058, 0.045, "Cabin", "Interior",
                      segments=32, rotation=(75, 0, 0))
        paths = []
        for angle in (0, math.pi, math.pi * 1.5):
            paths.append([wheel_center, (wheel_center[0] + 0.135 * math.cos(angle),
                                         wheel_center[1], wheel_center[2] + 0.135 * math.sin(angle))])
        self.lines("Steering spokes", paths, 0.010, "Alloy", "Interior")
        self.box("Interior rearview mirror", (0, -0.52, self.spec.cabin_height - 0.16),
                 (0.25, 0.035, 0.09), "Cabin", "Interior", radius=0.018, segments=3)
        for side in (-1, 1):
            self.box(f"{side:+d} interior door panel", (side * 0.759, -0.15, base + 0.075),
                     (0.048, 0.95, 0.28), "Cabin", "Interior", radius=0.026, segments=3)

    def build_studio(self):
        self.studio(
            target=(0, 0, self.spec.cabin_height * 0.5),
            lights=(
                ("Key softbox", (1.7, -4.5, 5.5), 850, 4.0, (1.0, 0.94, 0.86), "RECTANGLE", 2.6),
                ("Side strip", (4.0, 1.0, 3.1), 650, 4.5, (0.84, 0.92, 1.0), "RECTANGLE", 1.6),
                ("Roof rim", (-2.7, 3.2, 5.0), 1000, 4.0, (1.0, 0.96, 0.90), "RECTANGLE", 2.2),
                ("Front fill", (-3.0, -4.1, 2.2), 410, 3.0, (0.86, 0.93, 1.0), "DISK", 3.0),
                ("Rear fill", (1.2, 4.4, 2.9), 470, 3.0, (1.0, 0.98, 0.95), "RECTANGLE", 2.0),
            ),
            cameras=(
                (1, "Front three-quarter", (6.4, -8.6, 3.0), "PERSP", 6.0, 62),
                (2, "Rear three-quarter", (-6.0, 8.4, 3.0), "PERSP", 6.0, 62),
                (3, "Left elevation", (9.0, 0.0, 0.9), "ORTHO", 5.7, 62),
                (4, "Front elevation", (0.0, -9.0, 0.9), "ORTHO", 3.0, 62),
                (5, "Rear elevation", (0.0, 9.0, 0.9), "ORTHO", 3.0, 62),
            ),
            preview=HERE / f"{self.spec.key}_preview.png",
            background=(0.075, 0.095, 0.12), strength=0.35,
            samples=48, resolution=(1600, 1100), floor=(200, "Studio floor"),
        )
        self.scene.cycles.max_bounces = 8
        self.scene.cycles.transmission_bounces = 6
        self.scene.render.threads_mode = "FIXED"
        self.scene.render.threads = 8
        self.scene.frame_set(1)

    def validate_model(self):
        bpy.context.view_layer.update()
        if set(self.wheels) != {"LF", "RF", "LR", "RR"}:
            raise ValueError("All four separate wheel pivots are required.")
        for code, pivot in self.wheels.items():
            if len(pivot.children) < 20 or pivot.parent != self.root:
                raise ValueError(f"Incomplete wheel hierarchy: {code}.")
            tire = next(obj for obj in pivot.children if obj.name.endswith("grooved tire"))
            low = min((tire.matrix_world @ vertex.co).z for vertex in tire.data.vertices)
            if abs(low) > 0.0001:
                raise ValueError(f"{code} tire does not contact the ground plane: {low}.")
        meshes = [obj for obj in self.root.children_recursive if obj.type == "MESH"]
        for obj in meshes:
            if not obj.data.polygons or not obj.data.materials:
                raise ValueError(f"Empty or unshaded part: {obj.name}.")
            if any(not math.isfinite(value) for v in obj.data.vertices for value in v.co):
                raise ValueError(f"Non-finite geometry: {obj.name}.")
        if len(self.scene.timeline_markers) != 5:
            raise ValueError("The studio must have five inspection cameras.")
        for material in self.materials.values():
            if any(node.type == "TEX_IMAGE" for node in material.node_tree.nodes):
                raise ValueError("Reference car materials must not embed images.")
        print("AUTHORED_CAR", json.dumps({
            "model": self.spec.key, "parts": len(self.root.children_recursive),
            "mesh_parts": len(meshes), "wheelbase_m": self.root["wheelbase_m"],
            "tire_radius_m": self.spec.tire_radius,
        }), flush=True)

    def build(self):
        self.build_body()
        self.build_glazing()
        self.build_wheels()
        self.build_sides()
        self.build_front()
        self.build_rear()
        self.build_interior()
        self.build_studio()
        self.validate_model()
        self.save(HERE / f"{self.spec.key}.blend", expected_objects=200)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--car", choices=tuple(SPECS), required=True)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if bpy.app.background:
        bpy.context.preferences.filepaths.save_version = 0
    ReferenceCar(SPECS[arguments.car]).build()


if __name__ == "__main__":
    main()
