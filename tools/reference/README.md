# Modeling reference

Development-only imagery used while authoring the original meshes in
`tools\blender\`. The separate, portable GLB exports live in `assets\models\`;
the car and all four props are used by the game and gallery. Shared runtime
factories fit the props to the course and add its live indicators without
reading these images. Nothing in this reference folder is loaded at runtime,
shipped in a build, or imported by the engine.

| File | Subject | Authored model |
| --- | --- | --- |
| `car.png` | Multi-view 2009-generation Nissan Cube: proportions, glasshouse, wheel placement and body radii. | `nissan_cube.blend` |
| `tree.png` | Faceted conifer with layered green fronds and a flared trunk. | `pine_tree.blend` |
| `spark-plug.png` | Ribbed ceramic spark plug with a hex shell, thread profile and hooked electrode; maker marks omitted. | `spark_plug.blend` |
| `check-flag.png` | Yellow checker swallowtail, wooden pole, clamps, rock footing and grass. | `checkpoint_flag.blend` |
| `car-body-shop.png` | Gabled workshop, open service bay, interior equipment, signs and yard props. The background forest and parked vehicle are not part of this assembly. | `car_body_shop.blend` |

Every model has a matching GLB and a rendered `*_preview.png`. Geometry is
authored parametrically against the visible proportions, not extracted from
pixels: the generators never open, trace, sample or pack these sheets. The flag
checker and workshop lettering are mesh geometry, not image textures. The
root README documents generation, export, scale and the five inspection
cameras in each Blender file.

## Why it lives here and not in `assets/`

`assets/` is for runtime-ready resources; these are drafting aids. Three
separate mechanisms keep it out of the product:

- **`.gdignore`** (beside this file) stops Godot's filesystem scan from
  descending into the folder, so `car.png` is never imported, never gets an
  `.import` sidecar, and never lands in `.godot/imported/` as a `.ctex`. Without
  it, a 1.7 MB texture would be compressed into every export's resource set.
- **Export presets** already exclude `tools/*` and `games/*/tools/*` in every
  preset in `godot-base/export_presets.cfg`, including
  **Windows - Cube Trials (standalone)**.
- **No runtime code path references these images.** The GLBs contain original
  geometry and portable material colors, not textures sampled from the sheets.

Verify the first point after any engine reimport: no reference PNG should gain
an `.import` sidecar or a corresponding `.ctex` in the host's `.godot/imported/`.

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

The four additional sheets are user-supplied modeling references; their
presence does not establish a redistribution licence. Keep them
development-only as well. The spark plug's printed maker name and logo are
not reproduced. The workshop uses original, generic Creek signage, and none
of the new Blender or GLB files embeds reference imagery.
