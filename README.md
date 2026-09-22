# Cube Trials — the very unreasonable commute

A brown Nissan Cube. A very unreasonable commute.

Cube Trials is an original **2.5D** physics-driving game inspired by classic
elastic-suspension trials games: a real 3D environment and car driven with
side-view controls and rules. One handcrafted course, **Copper Creek**, runs a
node-free sprung-chassis model at a fixed 120 Hz, with a compact in-view HUD
and the shared DeskCanSaw menus and results. The extended route is **twice the
original start-to-finish distance**, with four real gaps and four checkpoint flags.

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
course_view.gd             # isolated SubViewport, Side/Chase/Cockpit cameras and scenery blur
drive_controls.gd          # keyboard, gamepad and multitouch input
trial_hud.gd               # in-view life, points, pickup and timer icons
cube_audio.gd              # synthesized engine hum and event cues
cube_art.gd                # palette and lighting entry point shared by every renderer
share_art.gd / .tscn       # score-share portrait in its own 3D studio viewport
gallery_stage.gd / .tscn   # turntable for the shared Gallery screen's plinths
store_preview.gd / .tscn   # the car or wheel on a shared Store screen card
world/copper_creek.gd      # exact terrain, shared imported prop factories and live feedback
world/daylight.gd          # shared sun/sky rig and the optional day/night cycle
world/cube_model.gd        # imported car, staged damage, suspension and working lights
world/coilover.gd          # shared helical spring, rigid damper and telescoping shaft
world/cube_finish.gd       # what each bought paint and wheel finish looks like
world/nissan_cube.tscn     # reusable stock-proportion car using the same adapter
world/mesh_builder.gd      # batches original geometry into lit surfaces
assets/                    # game-icon.png, tutorial_poster.png (both generated)
assets/models/             # portable car and reference-prop GLBs, plus Godot import settings
assets/shaders/            # scenery-only speed blur and a bloom-free parking outline
tests/                     # six suites plus input-only driver and controller fixtures
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
| `Space` | Jump (release before the next hop) |
| `Shift` | Brake |
| `R` | Recover to the last checkpoint (+5 seconds) |
| `C` | Cycle Side / Chase / Cockpit camera (rebindable) |
| `Escape` | Shared pause menu |
| Gamepad RT / LT, left stick, A, B, Y, Start | Throttle / reverse, tilt, jump, brake, recover, pause |
| Gamepad right-stick click (R3) | Change camera |
| On-screen pedals, tilt and jump buttons | Mouse, or independent simultaneous touch contacts |
| Camera icon beside Pause | Change camera without releasing a held touch pedal |

Keyboard bindings are generated from `cube_trials_options.gd` and are
rebindable. Older saved layouts that conflict with the new Space jump binding
are reset to this game's defaults by the shared settings conflict repair;
custom keys can be reapplied in **Settings > Controls**.
The settings **Game** tab exposes live **air control** strength
(50–150%), an **engine sound** toggle, and a **Day / night cycle** toggle.

Braking smoothly brightens the red rear lamps and adds a short-range red glow.
At speed, a restrained five-sample blur affects scenery only, leaving the car
and HUD sharp. Blur is capped at 2.25 render pixels and clears when parking,
pausing, recovering, restarting or finishing.

## The longer route

The familiar washboard, quarry ramp and High Road lead into the **Broken
Causeway**, **Sawtooth Ridge**, **Twin Ravines** and a final climb before the
relocated garage. The three new gaps are 350, 350 and 370 simulation units wide:
throttle alone will not clear them. Gold approach stripes and roadside signs
mark the takeoffs. Build speed, jump near the edge and use tilt to land level.
The last two plugs now sit on the ridge and home stretch, so delivery requires
driving the whole route. Level checkpoint pull-offs keep retries manageable.
Clouds, ravine water and ripples are grouped locally so off-screen sections
can be culled rather than drawing the entire extended landscape at once.

Jump is a fixed-step upward launch, not a second airborne boost. Each press
allows one hop; holding the button never auto-jumps on landing. A 0.12-second
input buffer catches slightly early presses and 0.08 seconds of coyote time
forgives a slightly late takeoff. Recovery, pause, replay and results clear
queued jumps; a held jump must be released before it can launch again.
Jumping alone starts the clock; ordinary landings do not cost lives or
damage the car.

## Driving feedback and HUD

The body leans back under acceleration, dips under braking and gently rocks
with wheel travel. Wheels and suspension still follow the actual simulation;
airborne wheels add a small visual droop, but these extra animations never
change handling or collision geometry. Damaging
impacts add a short, damped body recoil and a single warm highlight over the
new damage mesh, including impacts after the car is already battered. Recovery,
replay and results clear the transient pose; pause freezes it.

Jumping adds a short spring compression and release at takeoff, a gentle
ascent/descent lean, and a damped landing compression and rebound. The response
follows real flight and wheel contact; it does not stretch the car, move tire
contacts or change handling. Reduced motion removes these decorative poses
while retaining the actual jump, chassis pitch, wheel spin and suspension.
Cockpit view keeps the cabin steady around its fixed eye, retaining the real
jump and chassis pitch but omitting decorative body movement. That keeps both
the dashboard and a crumpled roof out of the driver's sight line.

Four **internal coilovers** reveal the jump's suspension travel inside the
wheel wells, not outside the bodywork. They stay concealed while parked,
driving or braking and become visible only in flight, as the wheels drop and
the continuous gold springs extend. The wheels ease an extra **16 cm** down
their suspension axes to open the fender gap, then retract as the tires
approach the trail. This is visual-only: terrain clearance limits each wheel's
extension, and grounded hubs remain at their exact physics contacts. Reduced
motion omits this extra droop while retaining real suspension travel.
Chrome shafts telescope into fixed-size
dark damper housings; spring seats and mounting eyes stay attached to the
chassis and displayed wheel hubs. The coilovers disappear as soon as either
wheel lands, while the body retains its landing compression and rebound.
Their inboard mounts preserve the stock body, tire size, ride height and
physics. No close-up overlay, slow motion or extra input is required.

Each strut uses an instance-local compression/extension morph of one shared,
single-surface mesh. Geometry is not rebuilt per frame. The gallery's
**Coilover Strut** is the same model at the car's parked preload, not a
separate high-detail version. Pause freezes its pose; recovery and replay
restore real resting travel and conceal the coilovers. The standalone gallery
strut remains visible for inspection; parked cars and promotional artwork do
not expose it. Reduced motion and disabled intense effects retain essential
airborne spring and shaft movement.

A small HUD floats over the sky inside the game view: **heart = lives**,
**star = points**, **spark plug = collected / 5**, and **stopwatch = adjusted
time**. The pause button is always available as an icon. The trail now fills
the space previously occupied by the title, score cards and permanent
instruction blocks. Short event notices disappear after 2.5 seconds.

The seven driving buttons use icons, with rebound key hints on wider screens
and icon-only controls on phones. Tooltips and screen-reader descriptions
retain their action names and keys; full controls and rules remain in the
instructions screen. Optional audio captions remain available above the
controls. Touch targets stay at least 44 physical pixels tall, and controls
remain below the road rather than covering it. Narrow HUDs show minutes and
seconds and wrap on the smallest phones; the full timer, tooltips and results
retain hundredths.

## Camera views

One camera button cycles **Side**, **Chase**, then **Cockpit**. Side remains
the default for each new game scene. The selection survives pause, recovery
and replay within that scene; switching views never starts the clock, spends
a life or changes the simulation. These are different views of the same
2.5D trail, **not a steering or free-roaming mode**. Throttle, reverse, tilt,
braking and jumping retain exactly the same controls and scoring in every view.

**Side** preserves the original orthographic camera and scenery-only speed
blur. **Chase** follows behind and above the car, looks farther ahead at
speed, and keeps both its eye and its line to the car above the exact road,
including crests. **Cockpit** looks through the actual windshield from the
driver's seat, retaining the dashboard and steering wheel. Its eye lowers
under the authored damaged roof when needed. It follows essential chassis
pitch but ignores decorative body rocking and impact recoil.

Camera changes are immediate cuts rather than flights through the car.
Recovery snaps tracking to the checkpoint, and pause freezes follow easing.
Reduced motion also removes chase easing and speed look-ahead. The forward
views use a bounded draw distance with day/night-matched distance haze and
omit the side-view blur, keeping the cabin and forward road sharp. Perspective
framing adapts to portrait and ultrawide windows, and the camera/Pause buttons
stay together as the small-screen HUD wraps. A brief view name and the camera
button's tooltip/screen-reader description identify the selected mode without
adding another permanent label.

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

Collect all **five numbered spark plugs**, then brake inside the garage. The four
checkpoints only activate once every earlier plug is collected, so a recovery
can never strand a missing pickup across the quarry. Roof strikes and falls
cost **one of five lives** and recover automatically while lives remain.
The fifth crash ends the run after its impact animation, without respawning
or adding a recovery penalty. Collected points are kept, but a failed run earns
no finish bonus, medal or completion achievement.

Manual recovery is available when stuck and **does not cost a life**; pickups
survive either kind of recovery, and each actual recovery adds **five seconds**.
Hard landings cause cosmetic damage only and never consume lives. Replay
restores all five lives.

The clock starts on the first drive, tilt or jump input and pauses with the shared
shell. There is no time limit. The trial owns its crash-only lives and finish
rules rather than using the shell's generic round modes — the manifest still
declares `uses_shell_round_rules = false`.

Gold is an adjusted time of **45 seconds or less**, Silver **70 or less**, and
any other finish earns Bronze. Each plug scores 1,000 points; finishing adds
`max(0, 3000 - ceil(adjusted_seconds * 40))`. Three persistent achievements
reward finishing (`HOME`), a no-recovery run (`CLEAN`) and Gold (`GOLD`).
Assists never block an achievement.

## Cosmetic damage

The Cube accumulates five visual stages during a run:

| Stage | Appearance |
| --- | --- |
| 0 - Pristine | Original bodywork and glass |
| 1 - Scuffed | Paint chips, bare-metal scrapes and small bumper dents |
| 2 - Dented | Dented doors, a buckled hood and bent bumpers |
| 3 - Crumpled | Compressed roof, displaced trim and cracked windows |
| 4 - Battered | Deep panel creases and a strongly crumpled silhouette |

Roof strikes and off-trail falls add one stage per crash. An unusually hard
landing also adds a stage, without a recovery or time penalty. Ordinary jumps,
the normal quarry landing and clean midair flips do not cause damage. The
fixed-step simulation measures incoming contact speed into the terrain,
including chassis rotation, rather than horizontal speed or orientation.
`trial_state.gd` sets the threshold at **700 simulation units/second**; landing
detection arms after **0.12 seconds airborne** and requires **0.20 seconds of
settled contact** to rearm, so wheel strikes and bounces cannot repeatedly
charge the same landing.

Damage survives both kinds of checkpoint recovery, pausing and mid-run
resprays. Manual recovery alone does not damage the car. A new run or replay
starts pristine, and stage 4 remains drivable while lives remain. The visual
damage stage is independent of the life counter. **Cosmetic damage never
changes handling, collision dimensions, scoring, medals or achievements.**
Score portraits retain the run's damage; gallery and store cars stay pristine.
Reduced motion and disabled intense effects retain the static damage.

The renderer swaps only the active chassis mesh resources. Bodywork, glass,
interior, trim and light sockets share one authored deformation, while wheels
and suspension remain the original assembly. Paint finishes leave the exposed
primer, scratches and glass fractures visible, and the brake lamps and
automatic headlights continue working at every stage.

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
It also removes the extra driving rock, impact recoil and impact highlight.
It also keeps afternoon light and stops the parking outline's gentle pulse.
Driving, wheel rotation, suspension travel and necessary camera tracking remain;
essential brake lamps respond immediately instead of fading. The shallow camera
angle keeps the quarry landing visible either way. Disabling intense effects
independently suppresses tire dust, speed blur and brake-light spill without
removing the brake lamps. It suppresses the impact highlight, parking halo and
pulse, but keeps the
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
| `cube_trials_test.gd` | Fixed-step physics and jumps at 30/60/144 FPS, jump height, press/hold/buffer/coyote rules, four real gaps and level checkpoints, stock ride height, crash-only lives and damage, recoveries and complete input-only drives at both assist limits |
| `cube_trials_scene_test.gd` | Icon counters, live rebinding, mouse and three-finger jumping, assigned/unassigned gamepads, braking, jump reset gating, day/night settings, damage/recovery/replay and score portraits, pause, assists, five-life loss, results and achievements |
| `cube_trials_3d_test.gd` | All five chassis variants, geometry budgets, finishes and instance isolation, helical coilover morphs and mount alignment, airborne wheel droop at 30/60/144 FPS with grounded/terrain-clearance checks, driving, takeoff, landing and impact animation, complete-route camera tracking, sun/sky transitions, automatic lights, parking, imported props and the nine shared gallery exhibits |
| `reference_models_test.gd` | The four source GLBs: geometry budgets, finite unit normals, outward-facing plug threads, meter scale, grounded origins, two-sided foliage/cloth and texture-free Compatibility materials |
| `cube_trials_view_test.gd` | **Graphics window required** — see below |
| `cube_trials_camera_test.gd` | **Graphics window required** — all three perspectives, cockpit visibility while jumping at every damage stage, full-course framing/budgets and forward-view night parking |

`driver_fixture.gd` and `input_gameplay_fixture.gd` are helpers, not suites; skip `*_fixture.gd` when
enumerating tests.

`cube_trials_view_test.gd` needs a **real graphics window** and deliberately
exits 1 under `--headless`, where it guards `DisplayServer.get_name() == "headless"`
and says so. Never read that headless exit code as a regression:

```powershell
godot --path . --script res://games/cube_trials/tests/cube_trials_view_test.gd -- --game=cube_trials
godot --path . --script res://games/cube_trials/tests/cube_trials_camera_test.gd -- --game=cube_trials
```

It checks actual 3D geometry and brown bodywork, all five damage stages at
landscape and portrait gameplay scale, each stage's rendered brake lamps and
headlight illumination, scenery blur with sharp car/HUD pixels, effect
accessibility and reset behavior,
landscape/portrait/ultrawide layouts, minimum physical touch-target sizes,
input-driven jumps across all four gaps, results, 3D share art and the standalone title. It
also compares rendered/hidden coilovers at desktop and phone sizes: inboard
springs must be readable in flight and contribute no exposed pixels while
parked, driving, braking, landing or rebounding, including damage and reduced motion.
Paired airborne renders with and without extra wheel travel must show more
visible coilover pixels on both axles, not merely different internal poses.
It compares rendered day/night parking outlines, headlight and workshop illumination,
nighttime car readability, and the portrait parking target with a minimum
13-physical-pixel callout font. It also checks actual instanced tree transforms,
imported gallery framing across
screen sizes and orbit angles, and the viewport's 200-draw / 120,000-triangle
budget at the start, checkpoints, jump and workshop. Pass an optional
`--cube-capture-dir=<absolute directory>` to save rendered examples.

The camera suite also accepts that capture argument and rejects `--headless`;
the numerical camera contracts run in the ordinary 3D suite. The scene suite
covers the camera key and live rebinding, mouse input, simultaneous pedal/camera
touches, emulation de-duplication, pause, recovery, replay and results gating.

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

The same export command also runs `tools\blender\cube_damage.py`, producing
`assets\models\nissan_cube_damage.glb` and the editable, derived
`tools\blender\nissan_cube_damage.blend`. The pristine `.blend` is not modified.
The damage scene displays five complete cars side by side, sharing wheel
geometry; frames 1-5 select their inspection cameras. Regeneration replaces
this derived scene, so make repeatable deformation and scrape changes in
`cube_damage.py`. Both GLBs and their `.import` sidecars belong in version
control; the damage `.blend` remains development-only.

The self-contained GLB is meter-scaled, Y-up and faces +X. It has a `Chassis`
and four independent wheel pivots under `NissanCube`; no studio cameras,
lights, floor, animation tracks or collision bodies are exported. The current
asset contains **44,398 triangles in 16 mesh nodes / 41 material surfaces**.
The exporter removes subpixel detailing, simplifies curves and meshes, batches
by finish and rejects exports above 45,000 triangles or 48 surfaces. Glass
uses alpha transparency rather than Cycles transmission/refraction, so it
works with Godot's Compatibility renderer. Godot also generates mesh LODs.

The separate damage GLB contains only four replacement chassis variants and
their paint/light markers, not additional wheels or physics. It adds about
3 MB on disk. Only one chassis is drawn: complete damaged cars range from
**46,867 to 47,755 triangles and 43-44 surfaces**, within the enforced
**48,000-triangle / 48-surface** limit. Scrapes and cracks are thin, projected
geometry with portable materials, requiring neither textures nor decals.
Unused variants remain shared mesh resources, not hidden full-car instances.

Instance `world/nissan_cube.tscn` for this game's stock-proportion assembly.
The adapter uniformly scales the body and detailed five-spoke wheels, keeping
the tires tucked beneath the fenders rather than stretching or lifting the car.
`vehicle_tuning.gd` synchronizes the model with its collision tire radius,
short suspension, bump stops, roof/belly contacts and checkpoint ride height.
The runtime tires have an approximately 0.34 m radius, with about 0.23 m of
body clearance at rest. Wheel travel, spin and brake animation follow
`trial_state.gd`; each car has its own brake material and optional glow lights.
The internal runtime coilovers are generated by `world/coilover.gd`, rather than
embedded in the car GLB, and are visible on the car only while airborne. All four
share two travel morph targets and keep their round wire, damper diameter and
mounting hardware at a fixed scale.
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
up to four trees using `MultiMeshInstance3D`, keeping both material fidelity
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