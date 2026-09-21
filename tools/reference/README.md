# Modeling reference

Development-only imagery used while authoring the original Cube meshes in
`tools/blender/nissan_cube.blend`. The runtime car is the separate
`assets/models/nissan_cube.glb` export. Nothing in this reference folder is
loaded at runtime, shipped in a build, or imported by the engine.

| File | What it is |
| --- | --- |
| `car.png` | Multi-view sheet of a 2009-generation Nissan Cube — front, rear, both flanks, roof and two three-quarter views — used to check proportions, glasshouse shape, wheel placement and body radii. |

## Why it lives here and not in `assets/`

`assets/` is for files the game actually loads; this is a drafting aid. Three
separate mechanisms keep it out of the product:

- **`.gdignore`** (beside this file) stops Godot's filesystem scan from
  descending into the folder, so `car.png` is never imported, never gets an
  `.import` sidecar, and never lands in `.godot/imported/` as a `.ctex`. Without
  it, a 1.7 MB texture would be compressed into every export's resource set.
- **Export presets** already exclude `tools/*` and `games/*/tools/*` in every
  preset in `godot-base/export_presets.cfg`, including
  **Windows - Cube Trials (standalone)**.
- **No runtime code path references it.** The car's GLB contains original
  geometry and portable material colors, not textures sampled from this file.

Verify the first point after any engine reimport — `car.png.import` must not
exist, and `.godot/imported/` must hold no `car.png-*.ctex`.

## Provenance and rights

`car.png` is a third-party promotional/press composite of a Nissan Cube. It is
**not** original work, it is **not** covered by this repository's licence, and
it must not be redistributed as part of a build or derived into shipped texture
data.

Its only sanctioned use is as an on-screen dimensional reference while hand-
authoring geometry. The Blender model and its GLB export are original geometry
and contain no traced outlines, no scanned surfaces and no sampled pixels
from this image. Nissan badges, the grille emblem and the `cube` wordmark
visible in the reference are deliberately **not** reproduced by the exported
model; the car wears the game's own unbranded chrome.

Cube Trials is an unofficial tribute and is not affiliated with, endorsed by or
sponsored by Nissan. If this repository is ever published under terms that
cannot accommodate a third-party image, delete `car.png` and substitute an
orthographic reference you hold the rights to — the geometry code does not
depend on the file existing.
