"""Original workshop and yard geometry, authored against car-body-shop.png.

Run in a fresh Blender process with --python <this file> -- --build-shop.
The reference is a visual drafting aid, never a texture or geometry input.
The subject is the building and its service yard, not the background forest
or the parked vehicle. Lettering uses Blender's built-in font.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from prop_kit import Asset, srgb  # noqa: E402


HERE = Path(__file__).resolve().parent
SCENE_NAME = "Car Body Shop - Studio"
ROOT_NAME = "Car Body Shop | Assembly"
PREFIX = "Shop"
FLOOR = 0.24
EAVES = 4.30
RIDGE = 6.05


def build_materials(app):
    palette = (
        ("Wall cladding", "#A0A5A6", 0.05, 0.76),
        ("Wall seams", "#717A80", 0.05, 0.80),
        ("Oxide red", "#A14535", 0.10, 0.57),
        ("Roof slate", "#354650", 0.40, 0.58),
        ("Edge steel", "#293239", 0.55, 0.48),
        ("Hardware", "#98A2A4", 0.75, 0.35),
        ("Concrete", "#9D9482", 0.00, 0.90),
        ("Asphalt", "#53575A", 0.00, 0.95),
        ("Rubber", "#20272B", 0.00, 0.88),
        ("Tool blue", "#395D76", 0.35, 0.48),
        ("Safety yellow", "#E8B538", 0.10, 0.50),
        ("Sign cream", "#F5DFB3", 0.00, 0.56),
        ("Timber", "#8D623D", 0.00, 0.82),
        ("Grass", "#65843B", 0.00, 0.84),
        ("Rock", "#888B81", 0.00, 0.85),
        ("Studio floor", "#1B2430", 0.00, 0.62),
    )
    for name, color, metallic, roughness in palette:
        app.material(name, srgb(color), metallic, roughness)
    app.material("Window amber", srgb("#E6BA79"), roughness=0.32, emission=0.35)


def front_section(app, name, left, right, bottom, top, y=-4.0):
    count = math.ceil((right - left) / 0.32)
    width = (right - left) / count
    for index in range(count):
        x = left + width * (index + 0.5)
        for lower, upper, mat in ((bottom, min(top, 1.15), "Oxide red"),
                                  (max(bottom, 1.15), top, "Wall cladding")):
            if upper > lower:
                app.box(f"{name} board {index + 1} {mat}", (x, y, (lower + upper) / 2),
                        (width - 0.012, 0.18, upper - lower), mat, "Structure")


def build_structure(app):
    site = [(-8.8, -8.5), (8.6, -8.5), (9.2, -6.0), (9.2, 4.8),
            (7.9, 5.4), (-8.2, 5.4), (-9.0, 3.5)]
    app.prism("Forecourt", site, 0.16, "Asphalt", "Yard")
    app.box("Workshop slab", (0, 0, 0.20), (10.25, 8.25, 0.08), "Concrete", "Structure")
    sections = (
        ("Left pier", -5.0, -4.10, FLOOR, EAVES),
        ("Bay lintel", -4.10, 1.05, 3.42, EAVES),
        ("Door pier", 1.05, 1.70, FLOOR, EAVES),
        ("Entry header", 1.70, 2.70, 2.65, EAVES),
        ("Window pier", 2.70, 3.10, FLOOR, EAVES),
        ("Office sill", 3.10, 4.65, FLOOR, 1.50),
        ("Office header", 3.10, 4.65, 2.65, EAVES),
        ("Right pier", 4.65, 5.0, FLOOR, EAVES),
    )
    for name, left, right, bottom, top in sections:
        front_section(app, name, left, right, bottom, top)
    front_section(app, "Rear wall", -5.0, 5.0, FLOOR, EAVES, y=4.0)
    for side in (-1, 1):
        for index in range(26):
            y = -4 + (index + 0.5) * 8 / 26
            app.box(f"Side {side} lower board {index}", (side * 5.0, y, 0.695),
                    (0.18, 8 / 26 - 0.012, 0.91), "Oxide red", "Structure")
            app.box(f"Side {side} upper board {index}", (side * 5.0, y, 2.725),
                    (0.18, 8 / 26 - 0.012, 3.15), "Wall cladding", "Structure")
        for y in (-4.0, 4.0):
            app.box(f"Corner upright {side} {y}", (side * 5.01, y, 2.27),
                    (0.22, 0.23, 4.06), "Wall seams", "Structure")
    for y in (-4.0, 4.0):
        app.wedge(f"Gable {y}", (0, y, (EAVES + RIDGE) / 2),
                  (10.0, 0.18, RIDGE - EAVES), "Wall cladding", "Structure")
        for index in range(-14, 15):
            x = index * 0.33
            height = (RIDGE - EAVES) * (1 - abs(x) / 5)
            app.box(f"Gable seam {y} {index}", (x, y + math.copysign(0.10, y),
                                              EAVES + height / 2),
                    (0.025, 0.018, height), "Wall seams", "Structure")
    for x in (-4.10, 1.05):
        app.box(f"Bay jamb {x}", (x, -4.15, 1.86), (0.20, 0.35, 3.24),
                "Edge steel", "Structure", radius=0.02)
    app.box("Bay header frame", (-1.525, -4.16, 3.47), (5.42, 0.36, 0.23),
            "Edge steel", "Structure", radius=0.02)
    for index in range(6):
        app.box(f"Raised shutter slat {index}", (-1.525, -3.99, 3.65 + index * 0.085),
                (5.05, 0.12, 0.075), "Roof slate", "Structure")
    print("Built a fully open service bay and paneled workshop shell.")


def build_roof(app):
    half_span = 5.35
    rise = RIDGE - EAVES + 0.10
    length = math.hypot(half_span, rise)
    pitch = math.degrees(math.atan2(rise, half_span))
    for side in (-1, 1):
        app.box(f"Roof slope {side}", (side * half_span / 2, 0, EAVES + rise / 2),
                (length, 8.80, 0.13), "Roof slate", "Roof",
                rotation=(0, side * pitch, 0))
        for index in range(21):
            app.box(f"Standing seam {side} {index}",
                    (side * half_span / 2, -4.32 + index * 0.432, EAVES + rise / 2 + 0.075),
                    (length, 0.034, 0.028), "Edge steel", "Roof",
                    rotation=(0, side * pitch, 0))
        for y in (-4.43, 4.43):
            app.box(f"Raking fascia {side} {y}",
                    (side * half_span / 2, y, EAVES + rise / 2),
                    (length + 0.12, 0.18, 0.24), "Edge steel", "Roof",
                    rotation=(0, side * pitch, 0))
        app.box(f"Eaves gutter {side}", (side * 5.38, 0, EAVES),
                (0.18, 8.98, 0.17), "Edge steel", "Roof")
        app.cylinder(f"Downpipe {side}", (side * 5.17, 3.85, 2.23), 0.07, 3.90,
                     "Edge steel", "Roof", segments=10)
    app.box("Ridge cap", (0, 0, RIDGE + 0.17), (0.22, 8.97, 0.13),
            "Edge steel", "Roof", radius=0.025)
    app.box("Vent curb", (-2.25, 1.60, 5.54), (0.90, 0.90, 0.65),
            "Roof slate", "Roof")
    app.box("Vent head", (-2.25, 1.60, 5.95), (1.12, 1.05, 0.64),
            "Wall seams", "Roof", radius=0.045)
    for index in range(5):
        app.box(f"Vent front louvre {index}", (-2.25, 1.065, 5.75 + index * 0.09),
                (0.89, 0.035, 0.045), "Edge steel", "Roof")
        app.box(f"Vent side louvre {index}", (-2.82, 1.60, 5.75 + index * 0.09),
                (0.035, 0.83, 0.045), "Edge steel", "Roof")
    app.cylinder("Exhaust flue", (1.35, 2.60, 5.89), 0.105, 1.10,
                 "Hardware", "Roof", segments=12)
    app.cone("Exhaust rain cap", (1.35, 2.60, 6.39), 0.22, 0.11,
             "Roof slate", "Roof", segments=12, tip=0.06)


def front_window(app, name, x, z, width, height, y=-4.16):
    outward = 1 if y > 0 else -1
    app.box(name + " frame", (x, y, z), (width + 0.16, 0.15, height + 0.16),
            "Edge steel", "Structure")
    app.box(name + " glass", (x, y + outward * 0.09, z), (width, 0.04, height),
            "Window amber", "Structure")
    app.box(name + " vertical mullion", (x, y + outward * 0.12, z), (0.06, 0.045, height),
            "Edge steel", "Structure")
    app.box(name + " horizontal mullion", (x, y + outward * 0.12, z), (width, 0.045, 0.055),
            "Edge steel", "Structure")


def build_doors_and_windows(app):
    app.box("Office door frame", (2.20, -4.08, 1.445), (1.18, 0.23, 2.47),
            "Edge steel", "Structure")
    app.box("Office door", (2.20, -4.21, 1.445), (0.97, 0.075, 2.27),
            "Roof slate", "Structure")
    front_window(app, "Door pane", 2.20, 1.94, 0.52, 0.64, y=-4.26)
    app.box("Door handle", (2.56, -4.31, 1.25), (0.055, 0.055, 0.22),
            "Hardware", "Structure", radius=0.015)
    front_window(app, "Office window", 3.875, 2.075, 1.51, 1.11)
    app.box("Entry canopy", (2.25, -4.50, 2.96), (2.20, 1.18, 0.11),
            "Roof slate", "Roof", rotation=(8, 0, 0))
    for x in (1.37, 3.13):
        app.box(f"Canopy bracket {x}", (x, -4.30, 2.72), (0.07, 0.66, 0.07),
                "Edge steel", "Roof", rotation=(-38, 0, 0))
    for index in range(5):
        app.box(f"Canopy rib {index}", (1.37 + index * 0.44, -4.50, 3.02),
                (0.025, 1.17, 0.035), "Edge steel", "Roof", rotation=(8, 0, 0))
    app.box("Side shutter surround", (-5.13, 2.37, 1.54), (0.16, 1.80, 2.70),
            "Edge steel", "Structure")
    for index in range(12):
        app.box(f"Side shutter slat {index}", (-5.235, 2.37, 0.37 + index * 0.21),
                (0.05, 1.59, 0.193), "Roof slate", "Structure")
    app.box("Side window frame", (-5.13, -0.78, 2.87), (0.16, 3.44, 0.80),
            "Edge steel", "Structure")
    for index in range(5):
        app.box(f"Side window pane {index}", (-5.23, -2.12 + index * 0.67, 2.87),
                (0.045, 0.58, 0.63), "Window amber", "Structure")
    for index, x in enumerate((-3.65, -1.20, 1.20, 3.65)):
        front_window(app, f"Rear clerestory {index}", x, 3.37, 0.78, 0.39, y=4.25)


def wall_lamp(app, name, x, y, z):
    app.box(name + " mount", (x, y + 0.14, z + 0.15), (0.18, 0.15, 0.32),
            "Edge steel", "Signs")
    app.box(name + " arm", (x, y - 0.07, z + 0.23), (0.065, 0.47, 0.065),
            "Edge steel", "Signs")
    app.cone(name + " shade", (x, y - 0.29, z), 0.25, 0.20,
             "Edge steel", "Signs", segments=12, tip=0.065)
    app.cylinder(name + " lens", (x, y - 0.29, z + 0.008), 0.205, 0.022,
                 "Window amber", "Signs", segments=12)


def build_signs(app):
    outline = [(-2.85, 0), (2.85, 0), (2.85, 0.90)]
    outline += [(1.68 * math.cos(math.pi * i / 12),
                 0.90 + 0.58 * math.sin(math.pi * i / 12)) for i in range(13)]
    outline += [(-2.85, 0.90)]
    app.prism("Sign steel backing", outline, 0.16, "Edge steel", "Signs",
              location=(-0.35, -4.16, 4.08), rotation=(90, 0, 0))
    inset = [(x * 0.966, 0.05 + y * 0.92) for x, y in outline]
    app.prism("Red workshop sign", inset, 0.045, "Oxide red", "Signs",
              location=(-0.35, -4.325, 4.08), rotation=(90, 0, 0))
    app.text("Workshop lettering", "CREEK BODY SHOP", (-0.35, -4.384, 4.56),
             0.49, "Sign cream", "Signs")
    app.text("Workshop sign date", "EST. 2009", (-0.35, -4.384, 5.13),
             0.18, "Sign cream", "Signs")
    for x in (-3.85, 3.88):
        wall_lamp(app, f"Facade lamp {x}", x, -4.30, 3.77)
    app.box("Open sign backing", (2.20, -4.19, 3.35), (0.70, 0.08, 0.32),
            "Oxide red", "Signs")
    app.text("Open sign", "OPEN", (2.20, -4.244, 3.35), 0.19, "Sign cream", "Signs")
    for x in (6.20, 8.43):
        app.box(f"Pylon post {x}", (x, -2.0, 3.31), (0.18, 0.22, 6.30),
                "Edge steel", "Signs")
        app.box(f"Pylon footing {x}", (x, -2.0, 0.29), (0.48, 0.55, 0.25),
                "Concrete", "Yard", radius=0.045)
    app.box("Pylon sign frame", (7.315, -2.0, 5.11), (2.42, 0.25, 2.23),
            "Edge steel", "Signs")
    app.box("Pylon sign face", (7.315, -2.145, 5.11), (2.18, 0.045, 1.99),
            "Oxide red", "Signs")
    for index, text in enumerate(("CREEK", "BODY", "SHOP")):
        app.text("Pylon " + text, text, (7.315, -2.185, 5.70 - index * 0.57),
                 0.48, "Sign cream", "Signs")
    app.box("Service menu", (7.315, -2.0, 3.26), (2.25, 0.20, 1.24),
            "Edge steel", "Signs")
    for index, text in enumerate(("PAINT", "REPAIR", "RESTORE")):
        app.text("Menu " + text, text, (7.315, -2.115, 3.62 - index * 0.36),
                 0.265, "Sign cream", "Signs")
    wall_lamp(app, "Pylon lamp", 7.315, -2.14, 6.29)


def build_workshop(app):
    for x in (-3.35, 0.20):
        app.box(f"Lift post {x}", (x, 0.90, 1.72), (0.27, 0.34, 2.96),
                "Tool blue", "Workshop", radius=0.025)
        app.box(f"Lift base {x}", (x, 0.90, 0.32), (0.66, 0.76, 0.16),
                "Edge steel", "Workshop")
        app.box(f"Lift slide {x}", (x, 0.69, 1.57), (0.17, 0.11, 2.34),
                "Hardware", "Workshop")
        for y in (0.16, 1.64):
            inward = 1 if x < -1 else -1
            app.box(f"Lift arm {x} {y}", (x + inward * 0.63, y, 0.47),
                    (1.50, 0.17, 0.16), "Safety yellow", "Workshop",
                    rotation=(0, 0, -inward * (18 if y < 1 else -18)))
    app.box("Lift overhead", (-1.575, 0.90, 3.18), (3.82, 0.26, 0.21),
            "Tool blue", "Workshop")
    for x in (-2.85, -0.70, 2.60):
        app.box(f"Workbench cabinet {x}", (x, 3.30, 0.78), (1.45, 0.91, 1.08),
                "Oxide red", "Workshop", radius=0.035)
        app.box(f"Workbench top {x}", (x, 3.27, 1.36), (1.56, 1.03, 0.12),
                "Timber", "Workshop")
        for drawer in range(4):
            app.box(f"Drawer {x} {drawer}", (x, 2.83, 0.43 + drawer * 0.24),
                    (1.29, 0.055, 0.19), "Oxide red", "Workshop")
            app.box(f"Drawer pull {x} {drawer}", (x, 2.78, 0.46 + drawer * 0.24),
                    (0.64, 0.038, 0.028), "Hardware", "Workshop")
    app.box("Tool board", (-1.40, 3.84, 2.25), (4.7, 0.075, 1.38),
            "Timber", "Workshop")
    for index in range(10):
        x = -3.34 + index * 0.42
        app.box(f"Hanging tool {index}", (x, 3.765, 2.25), (0.055, 0.04, 0.50),
                "Hardware", "Workshop", rotation=(0, (index % 3 - 1) * 8, 0))
        app.torus(f"Tool head {index}", (x, 3.765, 2.53), 0.067, 0.021,
                  "Hardware", "Workshop", segments=8, sides=4, rotation=(90, 0, 0))
    for x in (-3.0, 0.50):
        app.box(f"Ceiling light {x}", (x, 1.5, 4.04), (1.18, 0.23, 0.10),
                "Edge steel", "Workshop")
        app.box(f"Ceiling diffuser {x}", (x, 1.5, 3.98), (1.08, 0.18, 0.035),
                "Window amber", "Workshop")
    for x in (-4.28, 1.23):
        app.cylinder(f"Safety bollard {x}", (x, -4.57, 0.80), 0.095, 1.28,
                     "Safety yellow", "Yard", segments=12)
        app.cylinder(f"Bollard dark band {x}", (x, -4.57, 1.22), 0.098, 0.16,
                     "Edge steel", "Yard", segments=12)
    app.box("Service threshold marking", (-1.525, -4.48, 0.166), (5.07, 0.11, 0.012),
            "Safety yellow", "Yard")


def tire(app, name, location, upright=False):
    app.torus(name, location, 0.31, 0.135, "Rubber", "Yard", segments=16, sides=6,
              rotation=(90, 0, 0) if upright else (0, 0, 0))


def build_yard(app):
    app.box("Side shelter roof", (6.42, 1.25, 3.24), (3.1, 5.28, 0.13),
            "Roof slate", "Roof", rotation=(0, 7, 0))
    for y in (-1.28, 3.78):
        app.box(f"Shelter post {y}", (7.80, y, 1.68), (0.12, 0.12, 3.04),
                "Edge steel", "Yard")
    for x in (5.22, 6.08, 6.94, 7.80):
        app.box(f"Shelter seam {x}", (x, 1.25, 3.32 - (x - 6.42) * 0.123),
                (0.027, 5.30, 0.035), "Edge steel", "Roof")
    app.box("Dumpster", (-5.92, -0.22, 0.81), (1.35, 2.45, 1.25),
            "Tool blue", "Yard", radius=0.055)
    for index in range(2):
        app.box(f"Dumpster lid {index}", (-5.92, -0.85 + index * 1.25, 1.48),
                (1.48, 1.19, 0.09), "Roof slate", "Yard", radius=0.025)
    for y in (-1.12, 0.65):
        app.box(f"Dumpster foot {y}", (-5.92, y, 0.22), (1.44, 0.20, 0.13),
                "Edge steel", "Yard")
    for index in range(3):
        tire(app, f"Left tire stack {index}", (-5.92, -2.44, 0.30 + index * 0.24))
        tire(app, f"Spare tire stack {index}", (6.94, 2.74, 0.30 + index * 0.24))
    tire(app, "Leaning spare", (-6.31, -3.26, 0.61), upright=True)
    for index, (x, y) in enumerate(((6.05, 1.82), (7.04, 1.47), (-5.79, 3.63))):
        app.cylinder(f"Oil drum {index}", (x, y, 0.68), 0.32, 1.04,
                     "Roof slate", "Yard", segments=16)
        for z in (0.23, 0.48, 0.89, 1.17):
            app.torus(f"Drum hoop {index} {z}", (x, y, z), 0.32, 0.022,
                      "Hardware", "Yard", segments=16, sides=4)
    for index in range(6):
        y = -5.4 + index * 1.75
        app.box(f"Fence post {index}", (-7.67, y, 0.89), (0.18, 0.18, 1.46),
                "Timber", "Yard", radius=0.025)
    for z in (0.70, 1.27):
        app.box(f"Fence rail {z}", (-7.57, -1.02, z), (0.13, 8.96, 0.14),
                "Timber", "Yard")
    for x in (5.42, 7.16, 8.90):
        app.cylinder(f"Mesh fence post {x}", (x, 4.45, 1.33), 0.055, 2.34,
                     "Edge steel", "Yard", segments=8)
    for z in (0.25, 2.45):
        app.box(f"Mesh fence rail {z}", (7.16, 4.45, z), (3.58, 0.06, 0.06),
                "Edge steel", "Yard")
    for sign in (-1, 1):
        for index in range(-10, 19):
            start_x = 5.43 + index * 0.25
            low = max(0.0, (5.43 - start_x) / sign) if sign == 1 else max(0.0, start_x - 8.89)
            high = min(2.18, 8.89 - start_x) if sign == 1 else min(2.18, start_x - 5.43)
            if high <= low:
                continue
            length = (high - low) * math.sqrt(2)
            app.box(f"Fence wire {sign} {index}",
                    (start_x + sign * (low + high) / 2, 4.45, 0.26 + (low + high) / 2),
                    (0.016, 0.016, length), "Hardware", "Yard",
                    rotation=(0, sign * 45, 0))
    for x in (3.55, 6.15):
        app.box(f"Parking line {x}", (x, -6.10, 0.167), (0.065, 3.12, 0.014),
                "Sign cream", "Yard")
    for index, (x, y, radius) in enumerate(((-8.15, -6.6, 0.48), (-8.32, 3.0, 0.50),
                                           (8.28, -6.9, 0.40), (8.50, 3.5, 0.38),
                                           (-6.55, 4.6, 0.33), (4.93, 4.8, 0.28))):
        app.rock(f"Yard boulder {index}", (x, y, 0.16 + radius * 0.45), radius,
                 "Rock", "Yard", scale=(1.4, 1.0, 0.85), ground_z=0.16)
        for blade in range(5):
            angle = index * 1.4 + blade * 1.26
            app.cone(f"Yard grass {index} {blade}",
                     (x + (radius + 0.07) * math.cos(angle),
                      y + (radius + 0.07) * math.sin(angle), 0.16),
                     0.073, 0.35 + 0.12 * math.sin(angle), "Grass", "Yard",
                     segments=3, rotation=(12 * math.sin(angle), 12 * math.cos(angle), 0))
    print("Added lift, tools, service yard, shelter, signs and original mesh lettering.")


def build_studio(app):
    app.studio(
        target=(0, -0.6, 2.8),
        lights=(
            ("Key softbox", (-7, -11, 15), 2600, 9, (1.0, 0.94, 0.82), "RECTANGLE", 7),
            ("Sky fill", (9, -5, 12), 1900, 10, (0.79, 0.88, 1.0), "RECTANGLE", 9),
            ("Roof rim", (-1, 9, 13), 2700, 8, (0.88, 0.95, 1.0), "RECTANGLE", 7),
            ("Bay fill", (-1.5, -3.0, 3.7), 95, 2.3, (1.0, 0.83, 0.61), "RECTANGLE", 1.8),
        ),
        cameras=(
            (1, "Hero three-quarter", (-17, -24, 11), "ORTHO", 22, 55),
            (2, "Front elevation", (0, -28, 3.3), "ORTHO", 21, 60),
            (3, "Left elevation", (-28, 0, 3.3), "ORTHO", 19, 60),
            (4, "Rear elevation", (0, 28, 3.3), "ORTHO", 21, 60),
            (5, "Top plan", (0, -1.5, 32), "ORTHO", 21, 60),
        ),
        preview=HERE / "car_body_shop_preview.png",
        resolution=(1600, 1100),
        samples=64,
        floor=(200, "Studio floor"),
    )
    app.aim(app.groups["Studio"].objects["Shop | Bay fill"], (-1.4, 2.5, 1.4))


def build_all():
    app = Asset(
        PREFIX, SCENE_NAME, ROOT_NAME,
        ("Structure", "Roof", "Signs", "Workshop", "Yard"),
        seed=71,
        notes={
            "reference": "Proportion study of tools\\reference\\car-body-shop.png; no image data embedded.",
            "subject": "Original workshop and service yard; no background forest or parked vehicle.",
            "axes": "Z up, building centered on the origin, front faces -Y. Units are meters.",
        },
    )
    build_materials(app)
    build_structure(app)
    build_roof(app)
    build_doors_and_windows(app)
    build_signs(app)
    build_workshop(app)
    build_yard(app)
    build_studio(app)
    app.root["building_width_m"] = 10.0
    app.root["building_depth_m"] = 8.0
    app.root["service_bay_width_m"] = 5.15
    app.save(HERE / "car_body_shop.blend", expected_objects=350)


if __name__ == "__main__" and "--build-shop" in sys.argv:
    build_all()
