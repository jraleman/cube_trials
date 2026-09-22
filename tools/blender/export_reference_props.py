"""Export a saved reference prop without rebuilding or resaving its .blend.

blender --background <prop>.blend --python this_file.py -- --render-preview

The optional flag renders the source studio before the export-only scene is
created. Run once per prop; the Nissan Cube retains its specialized exporter.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402

from export_kit import export_asset  # noqa: E402


HERE = Path(__file__).resolve().parent
ASSETS = {
    "pine_tree": {
        "scene_name": "Pine Tree - Studio",
        "root_name": "Pine Tree | Assembly",
        "prefix": "Pine",
        "root_node": "PineTree",
        "groups": {
            "Foliage shadow": "Foliage",
            "Foliage midtone": "Foliage",
            "Foliage highlight": "Foliage",
            "Bark": "Trunk",
            "Bark shadow": "Trunk",
        },
        "max_triangles": 8000,
        "max_surfaces": 5,
        "keep_dense": ("Foliage", "Trunk"),
        "double_sided": ("Foliage shadow", "Foliage midtone", "Foliage highlight"),
    },
    "spark_plug": {
        "scene_name": "Spark Plug - Studio",
        "root_name": "Spark Plug | Assembly",
        "prefix": "Plug",
        "root_node": "SparkPlug",
        "groups": {
            "Ceramic": "Ceramic",
            "Ceramic shadow": "Ceramic",
            "Insulator band": "InsulatorBands",
            "Plated shell": "Metalwork",
            "Dark steel": "Metalwork",
            "Electrode": "Metalwork",
            "Seal": "Metalwork",
        },
        "max_triangles": 6000,
        "max_surfaces": 7,
        "keep_dense": ("Ceramic", "InsulatorBands", "Metalwork"),
    },
    "checkpoint_flag": {
        "scene_name": "Checkpoint Flag - Studio",
        "root_name": "Checkpoint Flag | Assembly",
        "prefix": "Flag",
        "root_node": "CheckpointFlag",
        "groups": {
            "Flag field": "FlagCloth",
            "Flag check": "FlagCloth",
            "Pole wood": "PoleAndHardware",
            "Finial gold": "PoleAndHardware",
            "Clamp metal": "PoleAndHardware",
            "Rock light": "Footing",
            "Rock dark": "Footing",
            "Grass": "Footing",
        },
        "max_triangles": 4000,
        "max_surfaces": 8,
        "keep_dense": ("FlagCloth", "PoleAndHardware", "Footing"),
        "double_sided": ("Flag field", "Flag check", "Grass"),
    },
    "car_body_shop": {
        "scene_name": "Car Body Shop - Studio",
        "root_name": "Car Body Shop | Assembly",
        "prefix": "Shop",
        "root_node": "CarBodyShop",
        "groups": {
            "Wall cladding": "Cladding",
            "Wall seams": "Cladding",
            "Oxide red": "RedPanels",
            "Roof slate": "Metalwork",
            "Edge steel": "Metalwork",
            "Hardware": "Metalwork",
            "Concrete": "Forecourt",
            "Asphalt": "Forecourt",
            "Rubber": "Workshop",
            "Tool blue": "Workshop",
            "Safety yellow": "SignsAndMarkings",
            "Sign cream": "SignsAndMarkings",
            "Window amber": "Windows",
            "Timber": "Landscaping",
            "Grass": "Landscaping",
            "Rock": "Landscaping",
        },
        "max_triangles": 24000,
        "max_surfaces": 16,
        "keep_dense": ("SignsAndMarkings", "Windows"),
        "reduction": {"Metalwork": 0.65, "Workshop": 0.65},
    },
}


def main():
    name = Path(bpy.data.filepath).stem
    if name not in ASSETS:
        raise ValueError(f"Open one of these saved authoring files: {', '.join(ASSETS)}.")
    config = ASSETS[name]
    if "--render-preview" in sys.argv:
        scene = bpy.data.scenes.get(config["scene_name"])
        if scene is None:
            raise ValueError(f"Missing source studio: {config['scene_name']}")
        bpy.context.window.scene = scene
        scene.frame_set(1 if name == "car_body_shop" else 5)
        scene.render.filepath = str(HERE / f"{name}_preview.png")
        bpy.ops.render.render(write_still=True)
    export_asset(output=HERE.parents[1] / "assets" / "models" / f"{name}.glb", **config)


if __name__ == "__main__":
    main()
