# Cube Trials — the very unreasonable commute

A brown Nissan Cube. A very unreasonable commute.

Cube Trials is an original **2.5D** physics-driving game inspired by classic
elastic-suspension trials games: a real 3D environment and car driven with
side-view controls and rules. One handcrafted course, **Copper Creek**, runs a
node-free sprung-chassis model at a fixed 120 Hz under the shared DeskCanSaw
HUD.

## This repository

This is its own Git repository, published standalone at
[`jraleman/cube_trials`](https://github.com/jraleman/cube_trials) and consumed
as a **submodule** by the [`jraleman/dcs_games`](https://github.com/jraleman/dcs_games)
superproject at `godot-base/games/cube_trials/`.

It is a game folder, not a standalone Godot project: there is no `project.godot`
here. Every path resolves as `res://games/cube_trials/…`, so the game only runs
from inside a `godot-base` checkout. A nested repository keeps its own index,
so the superproject's `.gitignore` and `.gitattributes` do not reach in here —
the local copies beside this file are the ones that apply.

A change that spans this repository and the host is **two commits**: one here,
then the updated gitlink in `dcs_games`.

Everything the game needs is in this folder — manifest, scenes, physics, 3D
models, generated art, synthesized audio, tests and its modeling reference. The
only cube_trials-related state outside it is registration in the shared
`godot-base/project.godot` and `godot-base/export_presets.cfg`, which every game
in the collection requires.

```
game.gd                    # GameManifest: title, copy, theme, achievements, credits
cube_trials_options.gd     # constants-only tunables and rebindable actions
gameplay.gd / .tscn        # round logic on top of the shared GameShell
intro.tscn                 # shared boot intro
trial_state.gd             # 120 Hz suspension, traction, collision and tilt
course.gd                  # single source of terrain, pickups and checkpoints
course_view.gd             # isolated SubViewport + orthographic follow camera
drive_controls.gd          # keyboard, gamepad and multitouch input
cube_audio.gd              # synthesized engine hum and event cues
cube_art.gd                # palette and daylight shared by every renderer
share_art.gd / .tscn       # score-share portrait in its own 3D studio viewport
world/copper_creek.gd      # terrain extruded from the exact collision profile
world/cube_model.gd        # imported car, four physics-driven wheels and visible struts
world/nissan_cube.tscn     # reusable lifted car scene using the same adapter
world/mesh_builder.gd      # batches original geometry into lit surfaces
assets/                    # game-icon.png, tutorial_poster.png (both generated)
assets/models/             # portable nissan_cube.glb and Godot import settings
tests/                     # four suites plus driver_fixture.gd
tools/capture_art.gd       # dev-only art capture; excluded from exports
tools/reference/           # dev-only modeling reference; see its README
tools/blender/             # editable reference-based Blender car and studio views
```

## Running

From the `godot-base` directory of a `dcs_games` checkout:

```powershell
godot --path . -- --game=cube_trials
godot --path . -- --game=all            # the full collection
```

## Controls

| Input | Action |
| --- | --- |
| `W` / `S` | Throttle / reverse |
| `A` / `D` | Tilt nose up / down |
| `Space` | Brake |
| `R` | Recover to the last checkpoint (+5 seconds) |
| `Escape` | Shared pause menu |
| Gamepad RT / LT, left stick, A, Y, Start | Throttle / reverse, tilt, brake, recover, pause |
| On-screen pedals and tilt buttons | Mouse, or independent simultaneous touch contacts |

Keyboard bindings are generated from `cube_trials_options.gd` and are
rebindable. The settings **Game** tab exposes live **air control** strength
(50–150%) and an **engine sound** toggle.

## Rules

Collect all **five numbered spark plugs**, then brake inside the garage. The two
checkpoints only activate once every earlier plug is collected, so a recovery
can never strand a missing pickup across the quarry. Roof strikes and falls
recover automatically, and manual recovery is available when stuck; pickups
survive either kind, and each recovery adds **five seconds**.

The clock starts on the first drive or tilt input and pauses with the shared
shell. There is no time limit and no life pool — the manifest declares
`uses_shell_round_rules = false`.

Gold is an adjusted time of **45 seconds or less**, Silver **70 or less**, and
any other finish earns Bronze. Each plug scores 1,000 points; finishing adds
`max(0, 3000 - ceil(adjusted_seconds * 40))`. Three persistent achievements
reward finishing (`HOME`), a no-recovery run (`CLEAN`) and Gold (`GOLD`).
Assists never block an achievement.

## Accessibility

Reduced motion parks clouds, water ripples, pickup and flag motion and tire
dust, and removes camera smoothing; driving, wheel rotation, suspension travel
and necessary camera tracking remain. The shallow camera angle keeps the quarry
landing visible either way. Intense effects independently suppress tire dust.
Every meaningful sound also has visible feedback and an audio caption.

## Tests

Run from `godot-base`, sequentially, using an isolated user profile for suites
that complete real rounds.

```powershell
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_scene_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_3d_test.gd -- --game=cube_trials
```

| Suite | Covers |
| --- | --- |
| `cube_trials_test.gd` | Fixed-step physics, recoveries and a complete input-only drive |
| `cube_trials_scene_test.gd` | Live rebinding, multitouch, pause, assists, results and achievements |
| `cube_trials_3d_test.gd` | Volumetric bodywork, normals, wheel/strut poses, terrain alignment, 3D pickups and effects |
| `cube_trials_view_test.gd` | **Graphics window required** — see below |

`driver_fixture.gd` is a shared helper, not a suite; skip `*_fixture.gd` when
enumerating tests.

`cube_trials_view_test.gd` needs a **real graphics window** and deliberately
exits 1 under `--headless`, where it guards `DisplayServer.get_name() == "headless"`
and says so. Never read that headless exit code as a regression:

```powershell
godot --path . --script res://games/cube_trials/tests/cube_trials_view_test.gd -- --game=cube_trials
```

It checks actual 3D geometry and brown bodywork, landscape/portrait/ultrawide
layouts, minimum physical touch-target sizes, an input-driven quarry jump,
results, 3D share art and the standalone title, and measures the viewport's
200-draw / 120,000-triangle budget. Pass an optional
`--cube-capture-dir=<absolute directory>` to save rendered examples.

## Regenerating art

The icon and picker poster in `assets/` are captures of the actual meshes, not a
second interpretation of the car. Regenerate them with a real graphics window,
from `godot-base`:

```powershell
godot --path . --script res://games/cube_trials/tools/capture_art.gd -- --game=cube_trials
```

`tools/` is development-only and is excluded from every export preset.

### Blender authoring model

Open `tools/blender/nissan_cube.blend` for the bronze 2009-generation Nissan
Cube study. The model includes a hollow cabin, asymmetric wraparound rear
glass, detailed five-spoke wheels with individual rotation pivots, lights,
door seams, mirrors and interior geometry. Scene units are meters, with Z up
and the nose pointing along -Y. Timeline frames 1-5 select front three-quarter,
rear three-quarter, side, front and rear cameras; frame 1 is the studio view.
The file opens in a lightweight, material-colored solid viewport; the PNG
previews show the full rendered materials and lighting.

`tools/blender/nissan_cube_preview.png` and `nissan_cube_rear.png` show the
rendered model. To regenerate the editable scene in a fresh Blender process:

```powershell
blender --background --python .\tools\blender\generate_nissan_cube.py -- --build-cube
```

The `.blend` remains a development-only source file. Its original geometry and
materials contain no reference-image pixels, textures or manufacturer
wordmarks. The folder's `.gdignore` prevents Godot from importing the Blender
file or previews.

### Exporting and using the Godot car

The game, score portrait and generated artwork now use
`assets/models/nissan_cube.glb` through `world/cube_model.gd`. To export the
current saved Blender model without overwriting it, run from this repository:

```powershell
blender --background .\tools\blender\nissan_cube.blend --python .\tools\blender\export_nissan_cube.py
```

Then open the host Godot project, or run `godot --headless --path . --import`
from `godot-base`. Commit the GLB and its `.import` sidecar, not `.godot/`.
After changing the model, regenerate the icon and poster with the capture
command above.

The self-contained GLB is meter-scaled, Y-up and faces +X. It has a `Chassis`
and four independent wheel pivots under `NissanCube`; no studio cameras,
lights, floor, animation tracks or collision bodies are exported. The current
asset contains **44,398 triangles in 16 mesh nodes / 41 material surfaces**.
The exporter removes subpixel detailing, simplifies curves and meshes, batches
by finish and rejects exports above 45,000 triangles or 48 surfaces. Glass
uses alpha transparency rather than Cycles transmission/refraction, so it
works with Godot's Compatibility renderer. Godot also generates mesh LODs.

Instance `world/nissan_cube.tscn` for this game's lifted assembly. The adapter
fits the stock body to the existing roof/belly envelope and wheelbase, scales
the tires to the collision radius, and drives wheel travel, spin, struts and
brake lights from `trial_state.gd`. It does not change the simulation. To reuse
the stock-proportion car in another Godot project, copy just the GLB and let
that project import it; the lifted scene depends on Cube Trials' scripts.

## Engine notes

The renderer stays `gl_compatibility`; do not change the physics or add
framework game-name branches to alter this game's presentation. The 3D view uses
4x MSAA and caps its render target to 1920x1600 while matching the window's
physical pixel density. `.uid` and `.import` files are project state and are
committed on purpose; only the generated `.godot/` cache is ignored.

## Credits and rights

Original game design, code, meshes, synthesized audio and art by DeskCanSaw
Games. The 3D Nissan Cube is original Blender geometry exported to glTF;
the terrain and roadside scenery are original geometry built in code.

Inspired by classic elastic-suspension trials games, including Elasto Mania. No
Elasto Mania levels, code, artwork or audio are included.

Nissan and Cube are trademarks of their respective owners. Cube Trials is an
unofficial tribute and is not affiliated with, endorsed by or sponsored by
Nissan. `tools/reference/car.png` is third-party reference imagery, is not
covered by this repository's licence and is never shipped in a build — see
[`tools/reference/README.md`](tools/reference/README.md).