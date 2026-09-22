"""Original conifer geometry, authored against the multi-view foliage reference.

Run in Blender with --python <this file> -- --build-tree. The reference sheet in
tools/reference/tree.png is a drafting aid only: it is not read, traced,
sampled, packed or used as a texture by this script.

Layout follows the sheet's four elevations: a faceted low-poly spruce roughly
six meters tall, a flared brown trunk visible for the lowest fifth, and thirteen
drooping branch skirts whose leaf tips are split between three greens so the
crown reads light and the interior reads dark without a single texture.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402  (Blender's module resolves after the path shim)

from prop_kit import Asset, srgb  # noqa: E402


HERE = Path(__file__).resolve().parent
SCENE_NAME = "Pine Tree - Studio"
ROOT_NAME = "Pine Tree | Assembly"
PREFIX = "Pine"
HEIGHT = 6.03
FOLIAGE_BASE = 1.05
LAYERS = 13
SPIKES = 16


def build_materials(app):
    app.material("Foliage shadow", srgb("#2D4A31"), 0.0, 0.70)
    app.material("Foliage midtone", srgb("#537B38"), 0.0, 0.62)
    app.material("Foliage highlight", srgb("#82A844"), 0.0, 0.54)
    app.material("Bark", srgb("#9A6440"), 0.0, 0.78)
    app.material("Bark shadow", srgb("#6C462B"), 0.0, 0.82)
    app.material("Studio floor", srgb("#1B2430"), 0.0, 0.62)


def build_trunk(app):
    profile = [(0.000, 0.300), (0.090, 0.232), (0.240, 0.196), (0.520, 0.172),
               (1.050, 0.152), (1.900, 0.128), (2.900, 0.104), (4.000, 0.078),
               (5.000, 0.048), (5.620, 0.014)]
    app.lathe("Trunk", profile, "Bark", "Trunk", segments=9, smooth=False, caps=True)
    for index in range(7):
        angle = math.tau * index / 7 + 0.31
        app.mesh(f"Root flare {index + 1}",
                 [(0.08, -0.08, 0), (0.43, -0.09, 0), (0.46, 0.06, 0),
                  (0.08, 0.08, 0), (0.14, 0.0, 0.66), (0.29, 0.0, 0.15)],
                 [(3, 2, 1, 0), (0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4)],
                 "Bark shadow" if index % 2 else "Bark", "Trunk",
                 rotation=(0, 0, math.degrees(angle)))
    print("Built a faceted tapering trunk with seven root flares.")


def layer_shape(index):
    """Height, spread and droop of one branch skirt, bottom layer first."""
    t = index / (LAYERS - 1)
    base = FOLIAGE_BASE + (HEIGHT - 0.70 - FOLIAGE_BASE) * t
    apex = HEIGHT if index == LAYERS - 1 else base + 0.80 - 0.28 * t
    radius = 1.38 * (1 - t) ** 0.85 + 0.09
    return t, base, apex, radius


def skirt_geometry(app, base, apex, radius):
    """One drooping branch whorl: an apex, an inner collar and leaf tips."""
    vertices = [(0.0, 0.0, apex)]
    inner_z = apex - 0.30 * (apex - base)
    for index in range(SPIKES):
        angle = math.tau * index / SPIKES
        vertices.append((0.30 * radius * math.cos(angle),
                         0.30 * radius * math.sin(angle), inner_z))
    for index in range(SPIKES):
        angle = math.tau * index / SPIKES
        long_spike = index % 2 == 0
        reach = radius * (1.0 if long_spike else 0.66)
        reach *= 1.0 + app.rng.uniform(-0.07, 0.07)
        droop = (-0.09 if long_spike else 0.02) + app.rng.uniform(-0.04, 0.04)
        vertices.append((reach * math.cos(angle), reach * math.sin(angle),
                         base + droop))
    collar = [(0, 1 + index, 1 + (index + 1) % SPIKES) for index in range(SPIKES)]
    tips = []
    for index in range(SPIKES):
        nxt = (index + 1) % SPIKES
        tips.append((1 + index, 1 + SPIKES + index, 1 + SPIKES + nxt, 1 + nxt))
    return vertices, collar, tips


def build_foliage(app):
    tones = ("Foliage shadow", "Foliage midtone", "Foliage highlight")
    for index in range(LAYERS):
        t, base, apex, radius = layer_shape(index)
        vertices, collar, tips = skirt_geometry(app, base, apex, radius)
        spin = 360.0 * ((index * 0.37) % 1.0)
        app.mesh(f"Whorl {index + 1:02d} shaded core", vertices, collar + tips,
                 "Foliage shadow", "Foliage", rotation=(0, 0, spin))
        assigned = {tone: ([], []) for tone in tones}
        for branch in range(8):
            angle = math.tau * branch / 8 + math.radians(spin)
            for feather in (-1, 0, 1):
                reach = radius * (0.82 if feather == 0 else 0.55)
                start = radius * (0.12 if feather == 0 else 0.38)
                direction = angle + feather * 0.36
                origin = (start * math.cos(angle), start * math.sin(angle),
                          base + (apex - base) * (0.82 if feather == 0 else 0.62))
                tone = app.rng.choices(tones, weights=(1.1 - t * 0.5, 2.0, 0.6 + t))[0]
                points, faces = assigned[tone]
                leaf_geometry(points, faces, origin, direction, reach,
                              radius * (0.23 if feather == 0 else 0.15),
                              (apex - base) * (0.88 if feather == 0 else 0.70))
        for tone, (points, faces) in assigned.items():
            if not faces:
                continue
            app.mesh(f"Whorl {index + 1:02d} {tone.split()[-1]} fronds",
                     points, faces, tone, "Foliage", smooth=False)
        if index < 6:
            for twig in range(3):
                angle = math.tau * ((index * 0.37 + twig / 3) % 1.0)
                length = radius * 0.82
                app.cylinder(f"Whorl {index + 1:02d} twig {twig + 1}",
                             (0.5 * length * math.cos(angle),
                              0.5 * length * math.sin(angle),
                              base + 0.56 * (apex - base)),
                             0.028, length, "Bark shadow", "Foliage", segments=5,
                             rotation=(0, 90, math.degrees(angle)), taper=0.012)
    print(f"Built {LAYERS} branch whorls with serrated, creased foliage in three greens.")


def leaf_geometry(vertices, faces, origin, angle, length, width, drop):
    edge = [(0.0, 0.0), (0.18, 0.35), (0.32, 0.70), (0.41, 0.38),
            (0.53, 1.0), (0.63, 0.48), (0.76, 0.82), (0.84, 0.38), (1.0, 0.0)]
    outline = edge + [(along, -across) for along, across in reversed(edge[1:-1])]
    offset = len(vertices)

    def point(along, across, ridge=0):
        x, y = length * along, width * across
        return (origin[0] + x * math.cos(angle) - y * math.sin(angle),
                origin[1] + x * math.sin(angle) + y * math.cos(angle),
                origin[2] - drop * along ** 1.15 + ridge)

    vertices.append(point(0.46, 0.0, length * 0.055))
    vertices.extend(point(along, across) for along, across in outline)
    faces.extend((offset, offset + 1 + index, offset + 1 + (index + 1) % len(outline))
                 for index in range(len(outline)))


def build_studio(app):
    app.studio(
        target=(0, 0, HEIGHT * 0.47),
        lights=(
            ("Key softbox", (4.2, -6.4, 8.4), 900, 5.0, (1.0, 0.95, 0.86), "RECTANGLE", 4.0),
            ("Sky fill", (-5.6, -3.0, 7.0), 430, 6.0, (0.78, 0.87, 1.0), "RECTANGLE", 5.0),
            ("Rim light", (-3.0, 6.2, 6.6), 620, 4.0, (0.92, 0.98, 1.0), "RECTANGLE", 3.4),
            ("Ground bounce", (0.0, -2.2, 0.6), 110, 4.0, (0.86, 0.90, 0.82), "DISK", 4.0),
        ),
        cameras=(
            (1, "Front elevation", (0.0, -16.0, 2.83), "ORTHO", 7.6, 70),
            (2, "Right elevation", (16.0, 0.0, 2.83), "ORTHO", 7.6, 70),
            (3, "Back elevation", (0.0, 16.0, 2.83), "ORTHO", 7.6, 70),
            (4, "Left elevation", (-16.0, 0.0, 2.83), "ORTHO", 7.6, 70),
            (5, "Three-quarter", (6.9, -8.6, 4.60), "ORTHO", 7.6, 62),
        ),
        preview=HERE / "pine_tree_preview.png",
        resolution=(1200, 1600),
        floor=(200, "Studio floor"),
    )
    print("Created four elevations, a three-quarter view and a softbox studio.")


def build_all():
    app = Asset(
        PREFIX, SCENE_NAME, ROOT_NAME,
        ("Trunk", "Foliage"),
        seed=17,
        notes={
            "reference": "Proportion study of tools\\reference\\tree.png; no image data embedded.",
            "subject": "Stylized low-poly spruce; original geometry, flat palette colors.",
            "axes": "Z up, base at the origin. Model dimensions are in meters.",
        },
    )
    build_materials(app)
    build_trunk(app)
    build_foliage(app)
    build_studio(app)
    app.root["height_m"] = HEIGHT
    app.root["canopy_radius_m"] = 1.47
    app.save(HERE / "pine_tree.blend", expected_objects=30)


if __name__ == "__main__" and "--build-tree" in sys.argv:
    build_all()
