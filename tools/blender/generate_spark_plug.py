"""Original spark plug geometry, authored against the multi-view part reference.

Run in Blender with --python <this file> -- --build-plug. The reference sheet in
tools/reference/spark-plug.png is a drafting aid only: it is not read, traced,
sampled, packed or used as a texture by this script.

The sheet's front, side, top, bottom and two angled views set the proportions of
a 14 mm plug: ribbed ceramic insulator, hex, seat washer, rolled thread and a
hooked ground electrode over the centre pin. The manufacturer wordmark and logo
printed on the reference insulator are deliberately **not** modelled, the same
rule the car follows for its badges.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402  (Blender's module resolves after the path shim)

from prop_kit import Asset, srgb  # noqa: E402


HERE = Path(__file__).resolve().parent
SCENE_NAME = "Spark Plug - Studio"
ROOT_NAME = "Spark Plug | Assembly"
PREFIX = "Plug"
LENGTH = 0.0955
HEX_FLATS = 0.0160
SEGMENTS = 24


def build_materials(app):
    app.material("Ceramic", srgb("#EDE4D6"), 0.0, 0.34, coat=0.45)
    app.material("Ceramic shadow", srgb("#C9BCA8"), 0.0, 0.42)
    app.material("Insulator band", srgb("#2F5EA8"), 0.0, 0.38, coat=0.30)
    app.material("Plated shell", srgb("#B0A694"), 0.88, 0.34)
    app.material("Dark steel", srgb("#6B6E75"), 0.92, 0.44)
    app.material("Electrode", srgb("#CFC8BA"), 1.00, 0.26)
    app.material("Seal", srgb("#4A4B50"), 0.30, 0.66)
    app.material("Studio floor", srgb("#1B2430"), 0.0, 0.62)


def build_insulator(app):
    """Cream ceramic: nose, long barrel, four corrugations and the top neck."""
    profile = [(0.0048, 0.0000), (0.0052, 0.0030), (0.0110, 0.0036),
               (0.0300, 0.0040), (0.0460, 0.0044), (0.0494, 0.0052),
               (0.0502, 0.0057), (0.0628, 0.0057), (0.0640, 0.0059)]
    ribs = 4
    top_of_ribs = 0.0640
    for index in range(ribs):
        base = top_of_ribs + index * 0.0034
        profile += [(base, 0.0059), (base + 0.0009, 0.0069),
                    (base + 0.0019, 0.0069), (base + 0.0029, 0.0059)]
    neck = top_of_ribs + ribs * 0.0034
    profile += [(neck, 0.0058), (0.0800, 0.0052), (0.0812, 0.0047)]
    app.lathe("Insulator", profile, "Ceramic", "Insulator", SEGMENTS, smooth=True)
    for index, rib in enumerate((2, 3)):
        height = top_of_ribs + rib * 0.0034
        app.lathe(f"Insulator band {index + 1}",
                  [(height + 0.0009, 0.00693), (height + 0.0019, 0.00693)],
                  "Insulator band", "Insulator", SEGMENTS, smooth=True, caps=False)
    app.lathe("Insulator seat", [(0.0428, 0.0072), (0.0450, 0.0072)],
              "Ceramic shadow", "Insulator", SEGMENTS, smooth=True, caps=False)
    print("Built the ribbed ceramic insulator with two colored bands.")


def build_shell(app):
    """Hex, seat washer and rolled thread, all on one axis like the reference."""
    hexagon = [(HEX_FLATS / 2 / math.cos(math.radians(30)) * math.cos(math.tau * i / 6 + 0.5236),
                HEX_FLATS / 2 / math.cos(math.radians(30)) * math.sin(math.tau * i / 6 + 0.5236))
               for i in range(6)]
    hex_shell = app.prism("Hex", hexagon, 0.0098, "Plated shell", "Shell",
                          location=(0, 0, 0.0392))
    app.bevel(hex_shell, 0.00045, segments=1)
    app.lathe("Hex crown", [(0.0490, 0.0074), (0.0496, 0.0080)],
              "Plated shell", "Shell", SEGMENTS, smooth=False)
    app.lathe("Seat flange",
              [(0.0300, 0.0086), (0.0316, 0.0089), (0.0344, 0.0089), (0.0360, 0.0082),
               (0.0392, 0.0082)],
              "Plated shell", "Shell", SEGMENTS, smooth=True)
    app.lathe("Seat washer", [(0.0296, 0.0074), (0.0298, 0.0090), (0.0308, 0.0090),
                              (0.0310, 0.0074)],
              "Seal", "Shell", SEGMENTS, smooth=False, caps=False)

    threads = []
    turns = 13
    start, end = 0.0055, 0.0296
    step = (end - start) / turns
    threads.append((start - 0.0012, 0.0052))
    for index in range(turns):
        base = start + index * step
        threads += [(base, 0.0062), (base + step * 0.45, 0.0071),
                    (base + step * 0.55, 0.0071)]
    threads += [(end, 0.0062), (end, 0.0074)]
    app.lathe("Thread", threads, "Dark steel", "Shell", 20, smooth=True, caps=False)
    app.lathe("Thread bore", [(0.0043, 0.0052), (0.0055, 0.0052)],
              "Dark steel", "Shell", 20, smooth=True, caps=False)
    print("Built the hex, seat washer and rolled 14 mm thread.")


def build_electrodes(app):
    """Centre pin, hooked ground strap and the stepped terminal stud on top."""
    app.cylinder("Centre electrode", (0, 0, 0.0041), 0.0011, 0.0032,
                 "Electrode", "Electrodes", 12)
    strap = [(0.0000, 0.0000), (0.0064, 0.0000), (0.0064, 0.0100),
             (0.0048, 0.0100), (0.0048, 0.0015), (0.0000, 0.0015)]
    ground = app.prism("Ground strap", strap, 0.0026, "Electrode", "Electrodes",
                       location=(0, 0.0013, 0), rotation=(90, 0, 0))
    app.bevel(ground, 0.0004, 2)
    terminal = [(0.0790, 0.0031), (0.0826, 0.0031), (0.0831, 0.0040),
                (0.0844, 0.0040), (0.0849, 0.0031), (0.0877, 0.0031),
                (0.0882, 0.0040), (0.0919, 0.0041), (0.0945, 0.0036),
                (LENGTH, 0.0029), (LENGTH, 0.0000)]
    app.lathe("Terminal stud", terminal, "Dark steel", "Electrodes", SEGMENTS,
              smooth=True)
    print("Built the centre pin, hooked ground strap and terminal stud.")


def build_studio(app):
    app.studio(
        target=(0, 0, LENGTH * 0.48),
        lights=(
            ("Key softbox", (0.10, -0.16, 0.20), 0.95, 0.16, (1.0, 0.96, 0.90), "RECTANGLE", 0.11),
            ("Edge strip", (-0.13, -0.05, 0.12), 0.34, 0.16, (0.80, 0.88, 1.0), "RECTANGLE", 0.05),
            ("Rim light", (-0.05, 0.15, 0.16), 0.52, 0.12, (0.94, 0.98, 1.0), "RECTANGLE", 0.09),
            ("Base bounce", (0.02, -0.06, 0.01), 0.05, 0.10, (0.88, 0.90, 0.86), "DISK", 0.10),
        ),
        cameras=(
            (1, "Front elevation", (0.0, -0.45, 0.0478), "ORTHO", 0.118, 80),
            (2, "Side elevation", (0.45, 0.0, 0.0478), "ORTHO", 0.118, 80),
            (3, "Top", (0.0, 0.0, 0.50), "ORTHO", 0.034, 80),
            (4, "Bottom", (0.0, 0.0, -0.44), "ORTHO", 0.034, 80),
            (5, "Angled", (0.17, -0.20, 0.145), "PERSP", 0.118, 85),
        ),
        preview=HERE / "spark_plug_preview.png",
        resolution=(1100, 1500),
        floor=(3, "Studio floor"),
    )
    print("Created elevations, top, bottom and an angled view.")


def build_all():
    app = Asset(
        PREFIX, SCENE_NAME, ROOT_NAME,
        ("Insulator", "Shell", "Electrodes"),
        seed=29,
        notes={
            "reference": "Proportion study of tools\\reference\\spark-plug.png; no image data embedded.",
            "subject": "Generic 14 mm spark plug; original geometry, no maker marks reproduced.",
            "axes": "Z up, electrode tip at the origin. Model dimensions are in meters.",
        },
    )
    build_materials(app)
    build_insulator(app)
    build_shell(app)
    build_electrodes(app)
    build_studio(app)
    app.root["length_m"] = LENGTH
    app.root["hex_across_flats_m"] = HEX_FLATS
    app.save(HERE / "spark_plug.blend", expected_objects=10)


if __name__ == "__main__" and "--build-plug" in sys.argv:
    build_all()
