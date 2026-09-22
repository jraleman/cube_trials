"""Shared authoring primitives for the reference-based Cube Trials props.

The multi-view sheets in `tools/reference` are read on screen while writing the
generator scripts that import this module. No image file is ever opened,
sampled, traced, packed or used as a texture by this code: every prop is
parametric geometry with flat material colors, exactly like the car in
`generate_nissan_cube.py`.

Every generator is deterministic. Randomness goes through `Asset.rng`, seeded
per asset, so rebuilding a `.blend` twice produces the same vertices.
"""

import math
import random

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector


def _euler(rotation):
    return tuple(math.radians(angle) for angle in rotation)


def srgb(value):
    """Convert a palette hex string into the linear color Blender stores."""
    digits = value.lstrip("#")
    channels = [int(digits[index:index + 2], 16) / 255 for index in (0, 2, 4)]
    return tuple(channel / 12.92 if channel <= 0.04045
                 else ((channel + 0.055) / 1.055) ** 2.4 for channel in channels)


class Asset:
    """One editable prop scene: collections, materials and mesh primitives."""

    def __init__(self, prefix, scene_name, root_name, groups, seed=0, notes=None):
        if bpy.data.scenes.get(scene_name):
            raise RuntimeError(f"{scene_name} already exists; refusing to replace it.")
        if bpy.context.object and bpy.context.object.mode != "OBJECT":
            bpy.ops.object.mode_set(mode="OBJECT")
        self.prefix = prefix
        self.materials = {}
        self.groups = {}
        self.rng = random.Random(seed)
        self.scene = bpy.data.scenes.new(scene_name)
        bpy.context.window.scene = self.scene
        self.scene.unit_settings.system = "METRIC"
        self.scene.unit_settings.length_unit = "METERS"
        for key, value in (notes or {}).items():
            self.scene[key] = value
        self.model = bpy.data.collections.new(f"{prefix} | Editable model")
        self.scene.collection.children.link(self.model)
        for index, name in enumerate(groups):
            collection = bpy.data.collections.new(f"{index + 1:02d} | {name}")
            self.model.children.link(collection)
            self.groups[name] = collection
        self.groups["Studio"] = bpy.data.collections.new("Studio | Cameras and softboxes")
        self.scene.collection.children.link(self.groups["Studio"])
        self.root = bpy.data.objects.new(root_name, None)
        self.model.objects.link(self.root)
        self.root.empty_display_type = "PLAIN_AXES"
        self.root.empty_display_size = 0.4
        self.default_group = groups[0]

    # ------------------------------------------------------------------ setup

    def material(self, name, color, metallic=0.0, roughness=0.5, coat=0.0,
                 emission=0.0, alpha=1.0):
        mat = bpy.data.materials.new(f"{self.prefix} | {name}")
        mat.diffuse_color = (*color, alpha)
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (*color, 1.0)
        shader.inputs["Metallic"].default_value = metallic
        shader.inputs["Roughness"].default_value = roughness
        shader.inputs["Coat Weight"].default_value = coat
        shader.inputs["Coat Roughness"].default_value = 0.18
        shader.inputs["Alpha"].default_value = alpha
        shader.inputs["IOR"].default_value = 1.45
        if emission:
            shader.inputs["Emission Color"].default_value = (*color, 1.0)
            shader.inputs["Emission Strength"].default_value = emission
        if alpha < 1.0:
            mat.surface_render_method = "BLENDED"
        self.materials[name] = mat
        return mat

    def empty(self, name, location=(0, 0, 0), parent=None, size=0.12):
        obj = bpy.data.objects.new(f"{self.prefix} | {name}", None)
        self.put(obj, self.default_group, parent is None)
        obj.empty_display_type = "PLAIN_AXES"
        obj.empty_display_size = size
        obj.location = location
        if parent is not None:
            obj.parent = parent
        return obj

    def put(self, obj, group=None, parent=True):
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        self.groups[group or self.default_group].objects.link(obj)
        if parent:
            obj.parent = self.root
        return obj

    # ------------------------------------------------------------- primitives

    def mesh(self, name, vertices, faces, mat=None, group=None, smooth=False,
             location=(0, 0, 0), rotation=(0, 0, 0), parent=None,
             recalculate_normals=True):
        data = bpy.data.meshes.new(f"{self.prefix} | {name}")
        data.from_pydata([tuple(vertex) for vertex in vertices], [], faces)
        data.update()
        bm = bmesh.new()
        bm.from_mesh(data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-9)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-9)
        if recalculate_normals:
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.normal_update()
        bm.to_mesh(data)
        bm.free()
        obj = bpy.data.objects.new(f"{self.prefix} | {name}", data)
        self.put(obj, group, parent is None)
        if parent is not None:
            obj.parent = parent
        if mat:
            data.materials.append(self.materials[mat])
        for polygon in data.polygons:
            polygon.use_smooth = smooth
        obj.location = location
        obj.rotation_euler = _euler(rotation)
        return obj

    def box(self, name, location, dimensions, mat, group=None, radius=0.0,
            rotation=(0, 0, 0), segments=2, parent=None, smooth=False):
        x, y, z = [dimension * 0.5 for dimension in dimensions]
        vertices = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
                    (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
        faces = [(3, 2, 1, 0), (0, 1, 5, 4), (1, 2, 6, 5),
                 (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]
        obj = self.mesh(name, vertices, faces, mat, group, smooth, location,
                        rotation, parent)
        if radius:
            self.bevel(obj, radius, segments)
        return obj

    def wedge(self, name, location, dimensions, mat, group=None, rotation=(0, 0, 0),
              parent=None):
        """Gable-roof style prism: a box whose +Z face collapses to a ridge line."""
        x, y, z = [dimension * 0.5 for dimension in dimensions]
        vertices = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
                    (0, -y, z), (0, y, z)]
        faces = [(3, 2, 1, 0), (0, 1, 4), (1, 2, 5, 4), (2, 3, 5), (3, 0, 4, 5)]
        return self.mesh(name, vertices, faces, mat, group, False, location,
                         rotation, parent)

    def prism(self, name, outline, height, mat, group=None, location=(0, 0, 0),
              rotation=(0, 0, 0), parent=None, smooth=False, taper=1.0):
        """Extrude a closed 2D outline along +Z, optionally tapering the cap."""
        count = len(outline)
        vertices = [(x, y, 0.0) for x, y in outline]
        vertices += [(x * taper, y * taper, height) for x, y in outline]
        faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
        faces += [(index, (index + 1) % count, (index + 1) % count + count, index + count)
                  for index in range(count)]
        return self.mesh(name, vertices, faces, mat, group, smooth, location,
                         rotation, parent)

    def lathe(self, name, profile, mat, group=None, segments=32, location=(0, 0, 0),
              rotation=(0, 0, 0), parent=None, smooth=True, caps=True, closed=False,
              phase=0.0):
        """Revolve a (height, radius) profile around the local Z axis."""
        vertices = []
        for height, radius in profile:
            for index in range(segments):
                angle = math.tau * (index / segments) + phase
                vertices.append((radius * math.cos(angle), radius * math.sin(angle), height))
        faces = []
        rows = len(profile) if closed else len(profile) - 1
        for row in range(rows):
            following = (row + 1) % len(profile)
            for index in range(segments):
                nxt = (index + 1) % segments
                faces.append((row * segments + index, row * segments + nxt,
                              following * segments + nxt, following * segments + index))
        if caps and not closed:
            if profile[0][1] > 1e-6:
                faces.append(tuple(reversed(range(segments))))
            if profile[-1][1] > 1e-6:
                last = (len(profile) - 1) * segments
                faces.append(tuple(last + index for index in range(segments)))
        # An open profile has no enclosed volume; preserve its authored outward winding.
        return self.mesh(name, vertices, faces, mat, group, smooth, location,
                         rotation, parent, recalculate_normals=caps or closed)

    def cylinder(self, name, location, radius, height, mat, group=None, segments=24,
                 rotation=(0, 0, 0), parent=None, smooth=True, taper=None):
        top = radius if taper is None else taper
        profile = [(-height / 2, radius), (height / 2, top)]
        return self.lathe(name, profile, mat, group, segments, location, rotation,
                          parent, smooth)

    def cone(self, name, location, radius, height, mat, group=None, segments=16,
             rotation=(0, 0, 0), parent=None, smooth=False, tip=0.0):
        return self.lathe(name, [(0.0, radius), (height, tip)], mat, group, segments,
                          location, rotation, parent, smooth)

    def torus(self, name, location, radius, minor, mat, group=None, segments=32,
              sides=10, rotation=(0, 0, 0), parent=None):
        profile = [(minor * math.sin(math.tau * index / sides),
                    radius + minor * math.cos(math.tau * index / sides))
                   for index in range(sides)]
        return self.lathe(name, profile, mat, group, segments, location, rotation,
                          parent, True, caps=False, closed=True)

    def sphere(self, name, location, radius, mat, group=None, segments=12, rings=7,
               smooth=False, scale=(1, 1, 1), parent=None, jitter=0.0):
        profile = []
        for ring in range(rings + 1):
            angle = math.pi * ring / rings
            profile.append((-radius * math.cos(angle), radius * math.sin(angle)))
        obj = self.lathe(name, profile, mat, group, segments, location, (0, 0, 0),
                         parent, smooth, caps=False)
        if jitter:
            for vertex in obj.data.vertices:
                vertex.co *= 1.0 + self.rng.uniform(-jitter, jitter)
        obj.scale = scale
        return obj

    def rock(self, name, location, radius, mat, group=None, jitter=0.24,
             scale=(1, 1, 1), rotation=(0, 0, 0), parent=None, segments=8, rings=5,
             ground_z=0.0):
        obj = self.sphere(name, location, radius, mat, group, segments, rings,
                          False, scale, parent, jitter)
        obj.rotation_euler = _euler(rotation)
        transform = (Matrix.Translation(Vector(location))
                     @ obj.rotation_euler.to_matrix().to_4x4()
                     @ Matrix.Diagonal((*scale, 1.0)))
        inverse = transform.inverted()
        for vertex in obj.data.vertices:
            point = transform @ vertex.co
            if point.z < ground_z:
                point.z = ground_z
                vertex.co = inverse @ point
        return obj

    def text(self, name, body, location, size, mat, group=None,
             rotation=(90, 0, 0), depth=0.006):
        data = bpy.data.curves.new(f"{self.prefix} | {name}", "FONT")
        data.body = body
        data.align_x = "CENTER"
        data.align_y = "CENTER"
        data.size = size
        data.extrude = depth
        data.resolution_u = 3
        data.materials.append(self.materials[mat])
        obj = bpy.data.objects.new(f"{self.prefix} | {name}", data)
        self.put(obj, group)
        obj.location = location
        obj.rotation_euler = _euler(rotation)
        self.activate(obj)
        bpy.ops.object.convert(target="MESH")
        obj = bpy.context.object
        obj.select_set(False)
        return obj

    def surface(self, name, columns, rows, mapper, mat, group=None, smooth=True,
                keep=None, parent=None, location=(0, 0, 0)):
        """Tessellate a parametric patch; `keep(u, v)` selects the faces built."""
        vertices = [mapper(column / columns, row / rows)
                    for column in range(columns + 1) for row in range(rows + 1)]
        faces = []
        for column in range(columns):
            for row in range(rows):
                if keep and not keep((column + 0.5) / columns, (row + 0.5) / rows):
                    continue
                index = column * (rows + 1) + row
                faces.append((index, index + 1, index + rows + 2, index + rows + 1))
        obj = self.mesh(name, vertices, faces, mat, group, smooth, location,
                        (0, 0, 0), parent)
        obj.data.validate(verbose=False)
        self.clean(obj)
        return obj

    # -------------------------------------------------------------- modifiers

    def clean(self, obj):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(obj.data)
        bm.free()
        return obj

    def activate(self, obj):
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj

    def apply(self, obj, modifier):
        self.activate(obj)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)

    def bevel(self, obj, amount, segments=2, apply=False, angle=40.0):
        mod = obj.modifiers.new("Soft manufactured edges", "BEVEL")
        mod.width = amount
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(angle)
        mod.harden_normals = segments > 1
        if apply:
            self.apply(obj, mod)
        return obj

    def solidify(self, obj, thickness, offset=0.0):
        mod = obj.modifiers.new("Sheet thickness", "SOLIDIFY")
        mod.thickness = thickness
        mod.offset = offset
        return obj

    def mirror(self, obj, axis=(True, False, False)):
        mod = obj.modifiers.new("Mirror", "MIRROR")
        mod.use_axis = axis
        return obj

    def difference(self, obj, cutter):
        mod = obj.modifiers.new("Authored opening", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        self.apply(obj, mod)
        data = cutter.data
        bpy.data.objects.remove(cutter, do_unlink=True)
        if data.users == 0:
            bpy.data.meshes.remove(data)
        return obj

    # ----------------------------------------------------------------- studio

    def studio(self, target, lights, cameras, preview, background=(0.055, 0.070, 0.090),
               strength=0.35, samples=48, resolution=(1600, 1100), floor=None):
        ground = None
        if floor is not None:
            size, color = floor
            ground = self.box("Studio ground", (0, 0, -0.05), (size, size, 0.10),
                              color, "Studio")
            ground.parent = None
        for name, location, power, size, color, shape, size_y in lights:
            data = bpy.data.lights.new(f"{self.prefix} | {name}", "AREA")
            data.energy, data.shape, data.size, data.color = power, shape, size, color
            if shape == "RECTANGLE":
                data.size_y = size_y
            obj = bpy.data.objects.new(f"{self.prefix} | {name}", data)
            self.put(obj, "Studio", parent=False)
            obj.location = location
            self.aim(obj, target)
        for frame, name, position, kind, scale, lens in cameras:
            data = bpy.data.cameras.new(f"{self.prefix} | {name}")
            data.type = kind
            data.ortho_scale = scale
            data.lens = lens
            data.clip_end = 500
            obj = bpy.data.objects.new(f"{self.prefix} | Camera | {name}", data)
            self.put(obj, "Studio", parent=False)
            obj.location = position
            self.aim(obj, target)
            marker = self.scene.timeline_markers.new(name, frame=frame)
            marker.camera = obj
            if frame == 1:
                self.scene.camera = obj
        if ground is not None and any(camera[2][2] < 0 for camera in cameras):
            for frame, _, position, *_ in cameras:
                ground.hide_render = ground.hide_viewport = position[2] < 0
                ground.keyframe_insert(data_path="hide_render", frame=frame)
                ground.keyframe_insert(data_path="hide_viewport", frame=frame)
        world = bpy.data.worlds.new(f"{self.prefix} | Neutral studio")
        world.use_nodes = True
        node = world.node_tree.nodes.get("Background")
        node.inputs["Color"].default_value = (*background, 1.0)
        node.inputs["Strength"].default_value = strength
        self.scene.world = world
        render = self.scene.render
        render.engine = "CYCLES"
        self.scene.cycles.samples = samples
        self.scene.cycles.use_denoising = True
        self.scene.cycles.preview_samples = 16
        self.scene.cycles.use_preview_denoising = True
        self.scene.cycles.max_bounces = 6
        render.resolution_x, render.resolution_y = resolution
        render.resolution_percentage = 100
        render.image_settings.file_format = "PNG"
        render.image_settings.color_mode = "RGBA"
        render.film_transparent = False
        self.scene.view_settings.view_transform = "AgX"
        render.filepath = str(preview)
        self.scene.frame_start = 1
        self.scene.frame_end = len(cameras)
        self.scene.frame_set(1)
        self.frame_cameras()
        self.viewport()

    def aim(self, obj, target):
        direction = Vector(target) - obj.location
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    def frame_cameras(self):
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        points = []
        for obj in self.root.children_recursive:
            if obj.type != "MESH":
                continue
            evaluated = obj.evaluated_get(depsgraph)
            points.extend(evaluated.matrix_world @ vertex.co
                          for vertex in evaluated.data.vertices)
        if not points:
            raise RuntimeError("Cannot frame an empty assembly.")
        low = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
        high = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
        center = (low + high) * 0.5
        for marker in self.scene.timeline_markers:
            camera = marker.camera
            camera.data.clip_start = max(0.0001, (high - low).length * 0.0001)
            self.aim(camera, center)
            for _ in range(12):
                bpy.context.view_layer.update()
                projected = [world_to_camera_view(self.scene, camera, point) for point in points]
                factor = max(max(abs(point.x - 0.5), abs(point.y - 0.5)) * 2 / 0.84
                             for point in projected)
                if factor <= 1.0001 and all(point.z > 0 for point in projected):
                    break
                if camera.data.type == "ORTHO":
                    camera.data.ortho_scale *= max(1.05, factor)
                else:
                    camera.location = center + (camera.location - center) * max(1.05, factor)
            else:
                raise RuntimeError(f"Could not fit the assembly into {camera.name}.")

    def viewport(self):
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type != "VIEW_3D":
                    continue
                space = area.spaces.active
                space.region_3d.view_perspective = "CAMERA"
                space.shading.type = "SOLID"
                space.shading.color_type = "MATERIAL"
                space.shading.light = "STUDIO"
                space.shading.show_cavity = True
                space.overlay.show_overlays = False

    def save(self, path, expected_objects=1):
        built = len(self.root.children_recursive)
        if built < expected_objects:
            raise RuntimeError(f"Only {built} parts were authored; refusing to save "
                               f"an incomplete {self.prefix}.")
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        self.root.select_set(True)
        bpy.context.view_layer.objects.active = self.root
        bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
        print(f"Saved {path} with {built} authored parts.")


def ring_profile(steps, start, end, shape):
    """Sample `shape(t)` between two heights into a lathe profile."""
    return [(start + (end - start) * index / steps,
             shape(index / steps)) for index in range(steps + 1)]
