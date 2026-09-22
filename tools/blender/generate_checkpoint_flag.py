"""Original checkpoint flag geometry, authored against the multi-view reference.

Run in Blender with --python <this file> -- --build-flag. The reference sheet in
tools/reference/check-flag.png is a drafting aid only: it is not read, traced,
sampled, packed or used as a texture by this script.

The sheet's front, side, back, top and detail views set the proportions: a
faceted rock footing with grass, a tapered wooden pole, a gold finial, two
bolted clamps and a swallowtail flag. The checker is not a texture — the cloth
patch is tessellated once and its faces are split between two flat colors, so
the pattern follows the wave from both sides.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402  (Blender's module resolves after the path shim)

from prop_kit import Asset, srgb  # noqa: E402


HERE = Path(__file__).resolve().parent
SCENE_NAME = "Checkpoint Flag - Studio"
ROOT_NAME = "Checkpoint Flag | Assembly"
PREFIX = "Flag"
POLE_TOP = 3.32
POLE_RADIUS = 0.078
FLAG_BOTTOM = 2.06
FLAG_HEIGHT = 1.06
FLAG_LENGTH = 1.62
FLAG_NOTCH = 0.34
COLUMNS, ROWS = 32, 18
CLAMPS = (2.10, 3.02)


def build_materials(app):
    app.material("Flag field", srgb("#F2BB2A"), 0.0, 0.52)
    app.material("Flag check", srgb("#2B2F36"), 0.0, 0.58)
    app.material("Pole wood", srgb("#8B5A33"), 0.0, 0.72)
    app.material("Finial gold", srgb("#E7B32C"), 0.35, 0.40)
    app.material("Clamp metal", srgb("#4C525A"), 0.72, 0.46)
    app.material("Rock light", srgb("#A9AEB3"), 0.0, 0.76)
    app.material("Rock dark", srgb("#7B8189"), 0.0, 0.80)
    app.material("Grass", srgb("#7FB03A"), 0.0, 0.66)
    app.material("Studio floor", srgb("#1B2430"), 0.0, 0.62)


def build_base(app):
    """Faceted boulder footing with satellite rocks and grass tufts."""
    outline = [(0.87 * math.cos(math.tau * i / 15),
                0.84 * math.sin(math.tau * i / 15)) for i in range(15)]
    app.prism("Ground cover", outline, 0.018, "Grass", "Base")
    app.rock("Boulder", (0, 0, 0.33), 0.46, "Rock light", "Base",
             jitter=0.20, scale=(1.50, 1.40, 1.02), segments=9, rings=5)
    satellites = ((0.70, -0.18, 0.12, 0.20), (-0.60, 0.34, 0.10, 0.17),
                  (0.18, 0.66, 0.09, 0.15), (-0.34, -0.62, 0.08, 0.14),
                  (0.76, 0.39, 0.07, 0.12), (-0.76, -0.21, 0.07, 0.13))
    for index, (x, y, z, radius) in enumerate(satellites):
        app.rock(f"Footing rock {index + 1}", (x, y, z), radius,
                 "Rock dark" if index % 2 else "Rock light", "Base",
                 jitter=0.28, scale=(1.3, 1.15, 0.85), segments=7, rings=4,
                 rotation=(0, 0, index * 37))
    for index in range(18):
        angle = math.tau * index / 18 + 0.21
        spread = 0.60 + 0.22 * math.sin(index * 2.7)
        build_tuft(app, index, (spread * math.cos(angle), spread * math.sin(angle),
                                0.07 + 0.04 * math.cos(index * 1.7)), angle)
    print("Built the boulder footing, satellite rocks and grass tufts.")


def build_tuft(app, index, origin, angle):
    vertices, faces = [], []
    for blade in range(3):
        lean = angle + (blade - 1) * 0.55
        height = 0.34 + 0.12 * math.sin(index * 1.3 + blade)
        width = 0.042
        bend = 0.13
        base = len(vertices)
        vertices += [
            (-width * math.sin(lean), width * math.cos(lean), 0.0),
            (width * math.sin(lean), -width * math.cos(lean), 0.0),
            (width * 0.5 * math.sin(lean) + bend * 0.45 * math.cos(lean),
             -width * 0.5 * math.cos(lean) + bend * 0.45 * math.sin(lean), height * 0.6),
            (-width * 0.5 * math.sin(lean) + bend * 0.45 * math.cos(lean),
             width * 0.5 * math.cos(lean) + bend * 0.45 * math.sin(lean), height * 0.6),
            (bend * math.cos(lean), bend * math.sin(lean), height),
        ]
        faces += [(base, base + 1, base + 2, base + 3), (base + 3, base + 2, base + 4)]
    app.mesh(f"Grass tuft {index + 1}", vertices, faces, "Grass", "Base",
             smooth=False, location=origin)


def build_pole(app):
    octagon = [(POLE_RADIUS * math.cos(math.tau * i / 8 + math.pi / 8),
                POLE_RADIUS * math.sin(math.tau * i / 8 + math.pi / 8)) for i in range(8)]
    app.prism("Pole", octagon, POLE_TOP - 0.02, "Pole wood", "Pole",
              location=(0, 0, 0.02), taper=0.86)
    app.lathe("Finial collar", [(POLE_TOP - 0.02, 0.070), (POLE_TOP + 0.03, 0.062)],
              "Clamp metal", "Hardware", 12, smooth=False)
    app.sphere("Finial", (0, 0, POLE_TOP + 0.145), 0.135, "Finial gold", "Pole",
               segments=9, rings=6, smooth=False)
    for index, height in enumerate(CLAMPS):
        app.box(f"Clamp {index + 1}", (0, 0, height), (0.196, 0.196, 0.136),
                "Clamp metal", "Hardware", radius=0.016)
        app.cylinder(f"Clamp bolt {index + 1}", (0, -0.104, height), 0.030, 0.026,
                     "Clamp metal", "Hardware", 10, rotation=(90, 0, 0))
        app.cylinder(f"Clamp lug {index + 1}", (0.098, 0.0, height), 0.038, 0.034,
                     "Clamp metal", "Hardware", 8, rotation=(0, 90, 0))
    print("Built the tapered pole, finial and two bolted clamps.")


def cloth(u, v):
    """Parametric swallowtail cloth: straight at the hoist, waving at the fly.

    The notch is confined to the fly section past `SPLIT` so the checker block
    nearer the hoist stays on an even, unsheared grid.
    """
    split = 0.60
    fly = FLAG_LENGTH - FLAG_NOTCH * (1 - abs(2 * v - 1))
    if u <= split:
        reach = u * FLAG_LENGTH
    else:
        reach = split * FLAG_LENGTH + (u - split) / (1 - split) * (fly - split * FLAG_LENGTH)
    x = POLE_RADIUS * 0.75 + reach
    y = (0.255 * u ** 1.35 * math.sin(4.3 * u - 1.05 + 0.5 * v)
         + 0.025 * u * math.sin(13 * u + 6 * v))
    z = (FLAG_BOTTOM + v * FLAG_HEIGHT
         + 0.075 * u ** 1.2 * math.sin(3.3 * u + 2.05)
         + 0.055 * (v - 0.5) * u)
    return (x, y, z)


def checker(u, v):
    column, row = int(u * COLUMNS), int(v * ROWS)
    if not (3 <= column < 19 and 3 <= row < 15):
        return False
    return (((column - 3) // 4) + ((row - 3) // 4)) % 2 == 0


def build_flag(app):
    app.surface("Flag cloth", COLUMNS, ROWS, cloth, "Flag field", "Cloth",
                smooth=False, keep=lambda u, v: not checker(u, v))
    app.surface("Flag checkers", COLUMNS, ROWS, cloth, "Flag check", "Cloth",
                smooth=False, keep=checker)
    hoist = [(FLAG_BOTTOM - 0.012, 0.010), (FLAG_BOTTOM + FLAG_HEIGHT + 0.012, 0.010)]
    app.lathe("Hoist rope", hoist, "Clamp metal", "Hardware", 6,
              location=(POLE_RADIUS * 0.75, 0, 0), smooth=False, caps=False)
    print("Built the waving swallowtail cloth with a face-split checker.")


def build_studio(app):
    app.studio(
        target=(0.35, 0, 1.80),
        lights=(
            ("Key softbox", (3.0, -4.2, 5.6), 480, 3.4, (1.0, 0.95, 0.86), "RECTANGLE", 2.6),
            ("Sky fill", (-3.6, -2.4, 4.6), 240, 4.0, (0.78, 0.87, 1.0), "RECTANGLE", 3.4),
            ("Rim light", (-1.8, 4.0, 4.4), 300, 2.8, (0.94, 0.98, 1.0), "RECTANGLE", 2.4),
            ("Ground bounce", (0.4, -1.4, 0.4), 46, 2.4, (0.86, 0.90, 0.82), "DISK", 2.4),
        ),
        cameras=(
            (1, "Front elevation", (0.0, -12.0, 1.95), "ORTHO", 4.5, 70),
            (2, "Side elevation", (12.0, 0.0, 1.95), "ORTHO", 4.5, 70),
            (3, "Back elevation", (0.0, 12.0, 1.95), "ORTHO", 4.5, 70),
            (4, "Top", (0.0, 0.0, 12.0), "ORTHO", 2.6, 70),
            (5, "Hero three-quarter", (3.6, -5.0, 2.70), "ORTHO", 4.5, 58),
        ),
        preview=HERE / "checkpoint_flag_preview.png",
        resolution=(1200, 1500),
        floor=(200, "Studio floor"),
    )
    print("Created three elevations, a top view and a hero three-quarter.")


def build_all():
    app = Asset(
        PREFIX, SCENE_NAME, ROOT_NAME,
        ("Base", "Pole", "Hardware", "Cloth"),
        seed=53,
        notes={
            "reference": "Proportion study of tools\\reference\\check-flag.png; no image data embedded.",
            "subject": "Stylized checkpoint flag; original geometry, flat palette colors.",
            "axes": "Z up, footing centred on the origin, flag flying toward +X.",
        },
    )
    build_materials(app)
    build_base(app)
    build_pole(app)
    build_flag(app)
    build_studio(app)
    app.root["pole_height_m"] = POLE_TOP
    app.root["flag_span_m"] = FLAG_LENGTH
    app.save(HERE / "checkpoint_flag.blend", expected_objects=28)


if __name__ == "__main__" and "--build-flag" in sys.argv:
    build_all()
