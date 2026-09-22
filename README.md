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
vehicle_tuning.gd          # shared dimensions, stock-like ride height and suspension
course.gd                  # single source of terrain, pickups and checkpoints
course_view.gd             # isolated SubViewport, follow camera and scenery blur
drive_controls.gd          # keyboard, gamepad and multitouch input
cube_audio.gd              # synthesized engine hum and event cues
cube_art.gd                # palette and lighting entry point shared by every renderer
share_art.gd / .tscn       # score-share portrait in its own 3D studio viewport
gallery_stage.gd / .tscn   # turntable for the shared Gallery screen's plinths
store_preview.gd / .tscn   # the car or wheel on a shared Store screen card
world/copper_creek.gd      # exact terrain, shared imported prop factories and live feedback
world/daylight.gd          # shared sun/sky rig and the optional day/night cycle
world/cube_model.gd        # imported car, suspension, brake lights and automatic headlights
world/cube_finish.gd       # what each bought paint and wheel finish looks like
world/nissan_cube.tscn     # reusable stock-proportion car using the same adapter
world/mesh_builder.gd      # batches original geometry into lit surfaces
assets/                    # game-icon.png, tutorial_poster.png (both generated)
assets/models/             # portable car and reference-prop GLBs, plus Godot import settings
assets/shaders/            # scenery-only speed blur and a bloom-free parking outline
tests/                     # five suites plus driver_fixture.gd
tools/capture_art.gd       # dev-only art capture; excluded from exports
tools/reference/           # dev-only modeling reference; see its README
tools/blender/             # editable reference-based car/props, generators and studio views
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
(50–150%), an **engine sound** toggle, and a **Day / night cycle** toggle.

Braking smoothly brightens the red rear lamps and adds a short-range red glow.
At speed, a restrained five-sample blur affects scenery only, leaving the car
and HUD sharp. Blur is capped at 2.25 render pixels and clears when parking,
pausing, recovering, restarting or finishing.

## Parking and atmosphere

The shop's parking bay has a soft glowing outline aligned with the **actual
finish interval**, not the decorative stalls beside the building. An amber
outline counts missing plugs; a mint outline says **PARK HERE** once all five
are aboard. Entering too quickly shows **SLOW DOWN**, and a successful stop
changes the signs to **DELIVERED! / DELIVERY COMPLETE**. A crisp, phone-sized
callout points at the bay instead of relying on small 3D lettering. The five
delivery bulbs light individually, and pickup rings remain readable after dark.

The shadow-casting sun now follows an optional **four-minute day/night cycle**:
warm afternoon, sunset, a readable blue night, dawn, then afternoon again.
Headlights and warm workshop lighting fade on automatically at dusk. The cycle
starts with the first driving input, freezes during pause and results, and
resets on replay. Recovery penalties do not advance it. Switch it off in
**Settings > Game** for steady afternoon light; the gallery, store previews
and share portraits always keep that studio daylight. Lighting never changes
the physics, finish requirements, score or achievements.

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

## The garage

Finishing a run pays **Sparks**, and the main menu's **Store** button spends
them at the Copper Creek garage. The pause menu reaches the same screen, so a
car can be resprayed mid-run and comes back wearing the new coat.

A delivered run pays `round(score × 0.006) + 4`, which is about 41 Sparks for a
Gold commute and 34 for a slow one; an abandoned run still pays for the plugs
collected. There is no payout ceiling, because this score cannot be farmed —
five plugs, one finish line, and a bonus that only shrinks with time.

| Slot | Sells |
| --- | --- |
| Body paint | Factory Bronze (free), Creek Green, Quarry Slate, Plug Ceramic, Signal Orange, Quarry Midnight, Copper Flake, Express Gold |
| Wheels | Factory Alloy (free), Graphite, Bronze Face, Trail White, Gloss Black |

**Nothing on sale is worth a second on the clock.** No item changes mass, grip,
ride height, suspension or scoring — the trial is the same trial in every
colour, which is the point of spending Sparks on paint rather than on parts.
Express Gold is gated behind `cube_trials_gold` and Gloss Black behind
`cube_trials_clean`.

`world/cube_finish.gd` is the only place that knows what a colour *is*. A
finish restates two of the surfaces the GLB exporter already batched — matched
by material name, so `cube_trials_3d_test.gd` fails loudly if a Blender rename
breaks the link — and the two free looks apply no override at all, so the
factory car wears the materials Blender wrote rather than a copy of them. Their
shelf swatches are quoted from the same module rather than retyped as hex, and
the test checks both against the export. Store cards, the round and the share
portrait all call the same function, so a swatch on the shelf cannot promise a
colour the trail fails to deliver.

## Gallery

The main menu carries a **Gallery** button, and the pause menu reaches the same
screen mid-round. It is a museum, not an advert: nine exhibits sit on a plinth
under Copper Creek's own late-afternoon daylight, and every one of them is built
by the same code the trail runs, so the gallery can never quietly show a nicer
version of the game than the one you drive.

| Heading | Exhibits |
| --- | --- |
| The car | The Brown Nissan Cube, Alloy Wheel and Tire, Coilover Strut |
| The trail | Numbered Spark Plug, Checkpoint Flag, Trail Sign Board |
| Copper Creek | Roadside Pine, Trail Fence |
| The finish | Copper Creek Body Shop |

The car is shown after its suspension has settled under its own weight, the
strut at the length a parked car holds it at, and the plug carries the same
3D-text number the trail hands out. The garage stays locked until the
`cube_trials_home` achievement is earned, so the finish is not spoiled.
The pine, plug, checkpoint and workshop use the same generated GLBs as the
course, including its pickup ring, checkpoint wording and delivery indicators.

Drag the model to turn it, scroll to zoom, or use the on-screen turn, tilt and
zoom buttons; **Reset** returns to the default framing. Auto-spin is on by
default and is parked by **Reduced motion**, which leaves the model still and
fully controllable.

## Accessibility
Reduced motion parks clouds, water ripples, pickup and flag motion and tire
dust, and removes camera smoothing, speed blur and decorative brake-light spill.
It also keeps afternoon light and stops the parking outline's gentle pulse.
Driving, wheel rotation, suspension travel and necessary camera tracking remain;
essential brake lamps respond immediately instead of fading. The shallow camera
angle keeps the quarry landing visible either way. Disabling intense effects
independently suppresses tire dust, speed blur and brake-light spill without
removing the brake lamps. It removes the parking halo and pulse, but keeps the
solid outline, written instructions and essential night lighting. Every
meaningful sound also has visible feedback and an audio caption.

## Tests

Run from `godot-base`, sequentially, using an isolated user profile for suites
that complete real rounds.

```powershell
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_scene_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_3d_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/reference_models_test.gd -- --game=cube_trials
```

| Suite | Covers |
| --- | --- |
| `cube_trials_test.gd` | Fixed-step physics, stock ride height and contacts, recoveries and a complete input-only drive |
| `cube_trials_scene_test.gd` | Live rebinding, multitouch, braking, day/night settings and lifecycle, pause, assists, replay, results and achievements |
| `cube_trials_3d_test.gd` | Car geometry/animation, sun/sky transitions, automatic lights, parking feedback and alignment, imported prop provenance, planting, yard clearance and the nine shared gallery exhibits |
| `reference_models_test.gd` | The four source GLBs: geometry budgets, finite unit normals, outward-facing plug threads, meter scale, grounded origins, two-sided foliage/cloth and texture-free Compatibility materials |
| `cube_trials_view_test.gd` | **Graphics window required** — see below |

`driver_fixture.gd` is a shared helper, not a suite; skip `*_fixture.gd` when
enumerating tests.

`cube_trials_view_test.gd` needs a **real graphics window** and deliberately
exits 1 under `--headless`, where it guards `DisplayServer.get_name() == "headless"`
and says so. Never read that headless exit code as a regression:

```powershell
godot --path . --script res://games/cube_trials/tests/cube_trials_view_test.gd -- --game=cube_trials
```

It checks actual 3D geometry and brown bodywork, rendered brake-lamp brightness,
scenery blur with sharp car/HUD pixels, effect accessibility and reset behavior,
landscape/portrait/ultrawide layouts, minimum physical touch-target sizes, an
input-driven quarry jump, results, 3D share art and the standalone title. It
compares rendered day/night parking outlines, headlight and workshop illumination,
nighttime car readability, and the portrait parking target with a minimum
13-physical-pixel callout font. It also checks actual instanced tree transforms,
imported gallery framing across
screen sizes and orbit angles, and the viewport's 200-draw / 120,000-triangle
budget at the start, checkpoints, jump and workshop. Pass an optional
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

Instance `world/nissan_cube.tscn` for this game's stock-proportion assembly.
The adapter uniformly scales the body and detailed five-spoke wheels, keeping
the tires tucked beneath the fenders rather than stretching or lifting the car.
`vehicle_tuning.gd` synchronizes the model with its collision tire radius,
short suspension, bump stops, roof/belly contacts and checkpoint ride height.
The runtime tires have an approximately 0.34 m radius, with about 0.23 m of
body clearance at rest. Wheel travel, spin and brake animation follow
`trial_state.gd`; each car has its own brake material and optional glow lights.
To reuse the car in another Godot project, copy just the GLB and let that
project import it; the reusable scene depends on Cube Trials' scripts.

### Reference-based Blender props

The other four sheets use the same process as the Cube: original,
script-authored geometry, an editable Blender studio with five inspection
cameras, a rendered preview, and a separate optimized GLB. The sheets are
visual drafting aids only; no reference pixels or manufacturer marks are
embedded in the models.

Each model name below has a `.blend` and `*_preview.png` in `tools\blender\`,
and a `.glb` with its Godot `.import` sidecar in `assets\models\`.

| Reference | Model name | Exported triangles | Material surfaces |
| --- | --- | ---: | ---: |
| `tree.png` | `pine_tree` | 6,064 | 5 |
| `spark-plug.png` | `spark_plug` | 4,246 | 7 |
| `check-flag.png` | `checkpoint_flag` | 2,016 | 8 |
| `car-body-shop.png` | `car_body_shop` | 17,440 | 16 |

The pine has layered, serrated fronds in three greens and a flared trunk. The
plug has ceramic ribs, blue bands, a hex shell, a faceted thread profile and
separate electrodes, without the reference's printed logo. The flag has a
geometric checker on waving swallowtail cloth, a wooden pole, metal clamps,
finial, stone footing and grass. The workshop includes an open service bay,
lift, tool cabinets, paneled walls, standing-seam roof, office, signage,
shelter, bins, tires, barrels, fences and a small forecourt. Its background
forest and parked vehicle are not included.

Blender uses meters and Z up; the GLBs use meters and Y up, with their base at
the origin. The pine is 6.03 m tall, the flag 3.60 m tall, and the plug is
**95.5 mm long**, not pre-enlarged to pickup size. The shop building is
10 by 8 m, within an approximately 18.30 by 13.90 m yard. Its front points
along +Z in Godot; the flag flies toward +X. Named mesh groups under
`PineTree`, `SparkPlug`, `CheckpointFlag` and `CarBodyShop` preserve the main
parts while batching hundreds of authored objects.

These GLBs now **replace the corresponding course and gallery props** through
the shared factories in `world\copper_creek.gd`. The source assets remain
unscaled and reusable: the runtime fits pines to a 4.19 m base height before
applying the trail's 0.80-1.32 variation, centers a 1 m plug inside its gold
pickup ring, and uses the workshop at 0.90 scale. The gallery uses those same
fits rather than a second interpretation of the models.

The forest draws the original trunk and foliage meshes in spatial groups of
up to three trees using `MultiMeshInstance3D`, keeping both material fidelity
and local culling. Checkpoint feedback duplicates only each flag's gold field
material: saving turns it teal without repainting its dark checkers or another
flag. Cloth sway, pickup spin/bob, visibility and numbers still follow the
round state and Reduced motion; replay restores the authored colors.

The workshop's furnished yard stays behind the driving lane. Background
ridges are leveled below its footprint, overlapping roadside clutter is
cleared, and nearby pines are replanted behind it. Its live instruction board
and five delivery lamps sit above the open bay, while the added finish
markings match `Course.FINISH_X` and `Course.FINISH_WIDTH` exactly. Driving
physics, pickup/checkpoint ownership and finish requirements are unchanged.
The gallery fits the complete yard while turning and tilting it.

The GLBs themselves have no collision bodies, animation tracks, studio
objects, texture dependencies or glTF extensions. The pine's foliage and the
flag's cloth and grass use two-sided materials. Godot generates mesh LODs;
animation import and unnecessary tangent generation remain disabled.

To rebuild the editable scenes, run from this repository in fresh Blender
processes. Regeneration replaces the corresponding `.blend`; export alone
preserves any manual edits to it.

```powershell
blender --background --factory-startup --python-exit-code 1 --python .\tools\blender\generate_pine_tree.py -- --build-tree
blender --background --factory-startup --python-exit-code 1 --python .\tools\blender\generate_spark_plug.py -- --build-plug
blender --background --factory-startup --python-exit-code 1 --python .\tools\blender\generate_checkpoint_flag.py -- --build-flag
blender --background --factory-startup --python-exit-code 1 --python .\tools\blender\generate_car_body_shop.py -- --build-shop
```

Export the **saved files**, optionally refreshing their previews:

```powershell
foreach ($name in "pine_tree", "spark_plug", "checkpoint_flag", "car_body_shop") {
    blender --background --factory-startup ".\tools\blender\$name.blend" --python-exit-code 1 --python .\tools\blender\export_reference_props.py -- --render-preview
    if ($LASTEXITCODE -ne 0) { throw "Export failed: $name" }
}
```

Omit `--render-preview` to export without rendering. The exporter hashes the
source before and after, batches by material group, enforces per-model
triangle/surface budgets and validates a temporary GLB before replacing the
previous export. It never saves the authoring file. Previews use frame 5
(three-quarter) for the tree, plug and flag, and frame 1 for the shop.
The remaining camera markers provide elevations and detail views; the plug's
bottom view automatically hides the studio floor.

Reimport from `godot-base` with `godot --headless --path . --import`, then run
the source, 3D integration and graphics suites in **Tests**. Regenerate the
game artwork after changing a visible model. Only the GLBs and
their `.import` sidecars belong in runtime assets; the `.blend` files,
previews and references remain under the development-only `tools` folder.

## Engine notes

The renderer stays `gl_compatibility`; keep visual dimensions and collision
geometry synchronized through `vehicle_tuning.gd`, without adding framework
game-name branches. The 3D view uses 4x MSAA and caps its render target to
1920x1600 while matching the window's physical pixel density. Speed blur runs
only on the world's TextureRect, never over shell controls or the HUD.
`.uid` and `.import` files are project state and are committed on purpose;
only the generated `.godot/` cache is ignored.

## Credits and rights

Original game design, code, meshes, synthesized audio and art by DeskCanSaw
Games. The Nissan Cube, pines, spark plugs, checkpoints and body shop use
original Blender geometry exported to glTF. Terrain, trail signs, fences,
gameplay indicators and remaining roadside detail are original geometry
built in code.

Inspired by classic elastic-suspension trials games, including Elasto Mania. No
Elasto Mania levels, code, artwork or audio are included.

Nissan and Cube are trademarks of their respective owners. Cube Trials is an
unofficial tribute and is not affiliated with, endorsed by or sponsored by
Nissan. `tools/reference/car.png` is third-party reference imagery, is not
covered by this repository's licence and is never shipped in a build — see
[`tools/reference/README.md`](tools/reference/README.md).