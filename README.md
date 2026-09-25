# Cube Trials — the very unreasonable commute

Three cars. A very unreasonable commute.

Cube Trials is an original **2.5D** physics-driving game inspired by classic
elastic-suspension trials games: a real 3D environment and car driven with
side-view controls and rules. Three handcrafted courses run a node-free
sprung-chassis model at a fixed 120 Hz, with a compact in-view HUD
and the shared DeskCanSaw menus and results. The first course, **Copper Creek**, covers
**16,220 simulation units from start to finish**, about **63% longer** than the
previous extended trail, with **six real gaps and seven checkpoint flags**.
The terrain spans **900 vertical units**, up from 240, and higher jumps leave
room to earn points with landed frontflips and backflips.

Start in the **Nissan Cube**, then earn the **Hyundai Sonata** and **Honda CR-V**
by completing levels. Freeing all three opens the **Trail Builder**, where you
build a trail of your own from picture blocks and drive it. Choose an unlocked
level and car in the shared
setup screen. Play solo, or take complete turns with **two or
three local players**: P1, then P2, then P3. This is hot-seat play, not
simultaneous driving or split-screen.

## Story

The valley has run out of spark plugs, and one by one its cars have fallen
silent. To keep them safe, the garages locked the stalled cars away behind
roll-up doors and iron bars. Only a brown Nissan Cube still runs, carrying a
crate of spark plugs. Every garage needs five. The first delivery to Copper
Creek's garage frees the Hyundai Sonata, and the first to Sunset Ridge's frees
the Honda CR-V. The boot intro tells the story in four short cards, and the
game's description repeats it.

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
intro.tscn                 # shared boot intro and its four story cards
trial_state.gd             # 120 Hz suspension, jumps, airborne tricks and banked scoring
vehicle_tuning.gd          # shared driving tuning and original Cube dimensions
vehicle_profiles.gd        # roster, authored dimensions, contacts, materials and driver eyes
course.gd                  # three routes, the built trail, unlock milestones, terrain, pickups and checkpoints
trail_layout.gd            # Trail Builder model: blocks, drivability rules, undo, save and route data
trail_canvas.gd            # the builder's picture of a trail: tap to pick, drag or wheel to scroll
trail_editor.gd            # the picture-only Trail Builder screen over the gameplay scene
course_view.gd             # isolated SubViewport, Side/Chase/Cockpit cameras and scenery blur
drive_controls.gd          # keyboard, gamepad and multitouch input
trial_hud.gd               # level and driver/car identity, lives, points, pickups and timer
cube_audio.gd              # synthesized engine hum and event cues
cube_art.gd                # palette and lighting entry point shared by every renderer
share_art.gd / .tscn       # score-share portrait in its own 3D studio viewport
gallery_stage.gd / .tscn   # turntable for the shared Gallery screen's plinths
store_preview.gd / .tscn   # the car or wheel on a shared Store screen card
character_preview.gd / .tscn # selected car and player paint, framed close for the setup plinth
world/copper_creek.gd      # selected-route terrain, shared prop factories and live feedback
world/garage_reveal.gd     # locked car, roll-up door, iron bars and the freeing reveal
world/daylight.gd          # shared sun/sky rig and the optional day/night cycle
world/cube_model.gd        # imported car, staged damage, suspension and working lights
world/tire_particles.gd    # bounded contact dust, snow powder, dirt clods and landing puffs
world/coilover.gd          # shared helical spring, rigid damper and telescoping shaft
world/cube_finish.gd       # what each bought paint and wheel finish looks like
world/nissan_cube.tscn     # reusable stock-proportion car using the same adapter
world/mesh_builder.gd      # batches original geometry into lit surfaces
assets/                    # generated icon/art, plus video/tutorial.ogv and its poster
assets/levels/             # generated route and Trail Builder stills for the shared setup's level row
assets/models/             # portable car and reference-prop GLBs, plus Godot import settings
assets/shaders/            # scenery-only speed blur, parking outline and frosted foliage
tests/                     # thirteen suites plus input-only driver and controller fixtures
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

## Levels and unlocks

| Level | Route | Available after | Completion reward |
| --- | --- | --- | --- |
| 1 | Copper Creek | Available from the start with the Nissan Cube | Level 2 and Hyundai Sonata |
| 2 | Sunset Ridge | Complete Level 1 | Level 3, Honda CR-V and the Trail Builder |
| 3 | Alpine Pass | Complete Level 2 | Top of the Commute achievement |
| — | Trail Builder | Complete Level 2, freeing the last car | None: built trails are just for fun |

**Sunset Ridge (Level 2)** is a 14,020-unit beach route with four real gaps and
four checkpoint flags. Sandy trails and coastal dunes overlook a turquoise
ocean, pale surf and palm groves under bright coastal daylight.
**Alpine Pass (Level 3)** climbs 1,320 vertical units over a 20,220-unit snowy
commute, crossing seven gaps with seven checkpoint flags before its long
descent. Packed-snow trails, snowbanks, frosted pines, blue-gray cliffs and
frozen pools sit under cool winter light, with soft, layered snowfall drifting
on a gentle breeze and powder from the tires. **Copper Creek (Level 1)** kicks up
warm dirt puffs and small clods from each grounded tire; landing lifts
a short surface-colored puff. These scenery themes do not change grip, jumping,
route geometry, checkpoint positions or progression; Copper Creek keeps its
original mountain scenery. Each route has its own terrain, signs, five
numbered pickups and finish garage. Suspension, cameras, scenery, recovery
and the progress strip all use the selected route.

An unlock requires delivering all five plugs and parking, not merely collecting
cargo, reaching a checkpoint or ending a failed run. Completion is saved through
the existing achievements profile. An older save with **Home in One Piece**
already opens Level 2 and the Sonata; it does not skip Level 2 to unlock Level 3.
The corresponding Gallery cars follow the same gates.

Until its car is freed, the finish garages on Levels 1 and 2 stay shut behind a
roll-up door signed with the waiting car's name. The shut door is a single
shadowless mesh plus its sign, and the car behind it is not drawn. The delivery
that unlocks the car plays a short garage scene before the results, framed by a
fixed three-quarter camera:

1. The door rattles up.
2. The iron bars sink into the floor.
3. The freed car blinks its headlights awake, beeps, flashes its hazards and
   hops for joy under floating hearts.

Your own car and the parking outline step out of the shot for the scene. The
unlock is saved before the scene starts. Its fanfare, announcement, screen
flash, confetti and captions wait until the scene ends, then the results open
over the freed car. Replays, failed or abandoned runs and Level 3 go straight to
the results. In hot seat, the scene plays once, after the final player's turn.

Unlocked cars can be used on **any unlocked level**, including earlier courses.
**Play Again** keeps the level and chosen cars; **Levels & cars** on the results
screen returns to setup. In hot seat, everyone drives the same selected level.
Any finisher earns its unlock after the final player's turn; leaving before
the roster finishes grants no new progression.

## Trail Builder

Completing Level 2 frees the CR-V, the last car, and opens the **Trail Builder**,
the fourth entry in the setup screen's level row with its own still
(`assets/levels/my_trail.png`). Until then it is listed greyed out, and its
tooltip says how to open it. Choosing it opens the builder instead of a drive,
in any unlocked car, solo or in hot seat. It is made for players who may not
read yet: every control is a picture, every edit shows on the trail at once,
and words live only in tooltips and screen-reader names.

| Where | Picture | Does |
| --- | --- | --- |
| Top left | Pause | Opens the pause menu, as the Pause key does |
| Top | Pine, palm, snowflake | Mountain, beach or snow scenery, as on Levels 1–3 |
| Top right | Curved arrow, bin, page with a plus | Undo a change, remove the picked block, start a new trail |
| Top right | Wide green play button | Drive the trail |
| Middle | The trail | The car on its start pad, every block, plug and flag, then the garage |
| Bottom | Seven pieces | Flat road, ramp up, ramp down, hill, dip, gap and checkpoint flag |

Tap a piece to add it straight after the glowing, picked block, where a gold
**+** waits. The new block becomes the pick, so tapping pieces one after
another builds the trail from left to right. Tap any block, or the start pad,
to pick it. Drag, the mouse wheel or the arrow buttons scroll a long trail.
**New** needs a second tap: the first turns it into a tick on red, which clears the
trail if tapped again within three seconds, and **Undo** still brings it back.
Undo steps back through the last 50 changes, including scenery. On a keyboard,
focus starts on **Play**, Left and Right move the pick while the trail has
focus, Ctrl+Z undoes and Delete or Backspace removes the picked block. On a
narrow phone the undo, remove and new buttons move to a row of their own.

The builder shows its rules instead of explaining them, so every trail can be
driven at full throttle. A piece that cannot go after the pick is greyed out:

- a trail holds up to 64 blocks, and its road stays between three steps below
  the start and nine above;
- a gap needs flat road right before it and two blocks of level road, flat or a
  flag, after it to land on;
- two gaps in a row make a long jump, which needs two blocks of full-speed road
  (flat, ramp down or a flag) before it; a third never fits;
- a ramp down cannot follow a dip, whose sharp crest would strand the long Sonata.

Removing or undoing a block can leave a later piece that no longer fits, such as
a gap whose flat run-up has gone. That piece is kept but built, and drawn, flat
until the trail around it lets it fit again. Hills and dips are gentle bumps.
The five numbered plugs are placed for you, spread along the road and clear of
every takeoff and landing. Checkpoint flags go wherever you put them, and the
garage always waits at the end with room to park. It holds no car to free.

**Play** drives the trail in the chosen car with the usual HUD, lives,
checkpoints and recoveries. During a solo drive, the HUD's **Build** button,
three stacked blocks, stops it without results and goes back to the builder.
The results offer **Build** right after **Play Again**, which drives the same
trail again. In hot seat everyone drives the same trail, and Build waits for the
results after the final turn. Built trails are just for fun: they pay no Sparks,
earn no achievements or progress, and the results say so. The results and share
card call it **My Trail**. The drive's 3D view stops drawing while the builder
is open.

Every edit, including the scenery, is saved straight away to
`user://cube_trials_trail.cfg`, so the trail is waiting next time. A first visit,
or a missing or damaged file, starts from a sample trail that uses every piece.
The shared **Saves** screen lists the file as **My Trail**, so it is backed up,
restored and deleted with the rest of the game's progress. Every builder button
is at least a 44-physical-pixel touch target, on desktop and on phones down to
320 pixels wide, including at a larger UI scale. **Reduced motion** stops new
blocks rising into place, the **+** pulsing and the trail gliding as it
scrolls.

## Cars and local hot seat

Solo setup selects a level and car before instructions. Multiplayer setup selects
a shared level, two or three humans and a car for each seat, with live model previews.
Players may choose the same car. Selections last for the current app session
and survive replay; each seat defaults to the next unlocked car in the roster.
Mobile keeps solo car selection but does not offer local multiplayer.

| Player | Body paint | Turn |
| --- | --- | --- |
| P1 | Blue | First complete run |
| P2 | Red | Second complete run |
| P3 | Green | Third complete run, when selected |

Each driver starts with five lives, no cargo or trick points, a pristine car and
an independent clock, checkpoint and recovery count. Finishing or exhausting five lives
opens a handoff screen; the next run starts only after the previous controls
are released and the next driver confirms. Handoffs freeze the course and
clock, and a held confirmation cannot become an accidental jump.
Every turn uses the same rebound driving keys. Each seat uses its assigned
gamepad when available, otherwise Player 1's pad can be passed between drivers.

Finishers rank by adjusted time at the displayed hundredth; tied times share
their place. Failed runs rank below finishers, ordered by plugs collected.
Final results, detailed stats and the share image include every driver.
The shared garage pays **once**, after the final turn, using the best score;
completed runs can earn achievements, but exiting early does not pay.
Replay restarts the whole roster with the same chosen cars.

All cars share engine power, grip, springs, jump strength and assists.
`vehicle_profiles.gd` preserves their actual wheelbases, tire sizes, body
contacts and cabin heights instead of stretching them into the Cube's shape.
Geometry still matters: the long, low Sonata needs a hop over sharp crests
that the taller cars can clear. Damage is cosmetic and never changes these
physical profiles.

Solo uses the selected car's factory or purchased paint. Hot-seat body paint
always identifies the player; purchased wheel finishes work in both modes.
The original factory coats are bronze, pearl white and deep blue respectively.

## Controls

| Input | Action |
| --- | --- |
| `W` / `S` | Throttle / reverse |
| `A` / `D` | Tilt nose up / down; hold in the air for backflips / frontflips |
| `Space` | High jump (release before the next hop) |
| `F` | Toggle hazard lights; switch on in mid-air for a 1.15x jump bonus |
| `Shift` | Brake |
| `R` | Recover to the last checkpoint (+5 seconds) |
| `C` | Cycle Side / Chase / Cockpit camera (rebindable) |
| `Escape` | Shared pause menu |
| Gamepad RT / LT, left stick, A, B, X, Y, Start | Throttle / reverse, tilt, jump, brake, hazards, recover, pause |
| Gamepad right-stick click (R3) | Change camera |
| On-screen driving buttons, including the hazard triangle | Mouse, or independent simultaneous touch contacts |
| Camera icon beside Pause | Change camera without releasing a held touch pedal |

Keyboard bindings are generated from `cube_trials_options.gd` and are
rebindable. Older saved layouts that conflict with the Space jump or F hazard binding
are reset to this game's defaults by the shared settings conflict repair;
custom keys can be reapplied in **Settings > Controls**.
The settings **Game** tab exposes live **air control** strength
(50–150%), an **engine sound** toggle, and a **Day / night cycle** toggle.

Braking smoothly brightens the red rear lamps and adds a short-range red glow.
All three cars have brighter running lamps, stronger night beams and low-level
night tail lights. The Sonata and CR-V illuminate their actual projector lenses
as well as their LED trim. Small, depth-tested lamp halos keep the signals
readable at driving distance without requiring bloom or extra shadow passes;
all six halos share one draw batch and follow the damaged lamp geometry.
Hazards flash amber at the front and red at the rear, in sync at 1.25 Hz.
Braking takes priority over the rear blink so the brake signal never disappears.
The hazard button stays highlighted while the toggle is on.
While airborne, the lit hazard lamps leave short, tapered amber and red light
trails. Samples follow the actual lamp positions through flips and damage,
remain behind in world space, and fade over 0.34 seconds. Dark blink phases,
landing and switching the hazards off stop new samples; the scoring rules
and brake-light priority are unchanged.
At speed, a restrained five-sample blur affects scenery only, leaving the car
and HUD sharp. Blur is capped at 2.25 render pixels and clears when parking,
pausing, recovering, restarting or finishing.

## Level 1: the longer, taller Copper Creek route

The familiar washboard, quarry ramp and High Road lead into the **Broken
Causeway**, **Sawtooth Ridge** and **Twin Ravines**, then continue into
**Skyline Ascent**, **Summit Run** and the long descent to the relocated garage.
The two mountain ravines are **440 and 460 simulation units wide**, joining
the original quarry and the 350-, 350- and 370-unit gaps. The wider gaps require
a deliberate jump, not throttle alone. Gold approach stripes and roadside
signs mark takeoffs and explain tricks. Build speed, jump near the edge and
use tilt to land level.

The summit rises 900 units above the lowest road, with deeper rock faces below
the elevated trail. Three additional level checkpoint pull-offs make the
mountain climb and summit crossings recoverable. The final plug is now on the
new home stretch, so delivery requires driving the whole route. All seven
checkpoint flags still require the earlier plugs before saving progress.
Clouds, ravine water and ripples are grouped locally so off-screen sections
can be culled rather than drawing the entire extended landscape at once.

Jump launches at **680 units/second**, reaching about **233 units above level
ground**, nearly twice the previous hop's height. It is still a fixed-step
upward launch, not a second airborne boost. Each press allows one jump;
holding the button never auto-jumps on landing. A 0.12-second
input buffer catches slightly early presses and 0.08 seconds of coyote time
forgives a slightly late takeoff. Recovery, pause, replay and results clear
queued jumps; a held jump must be released before it can launch again.
Jumping alone starts the clock; ordinary landings do not cost lives or
damage the car.

## Aerial tricks

Jump, then hold **nose up** for a backflip or **nose down** for a frontflip.
Firm tilt input during sustained flight has extra rotation power; small
corrections and short suspension hops keep their precise balance controls.
Release tilt during a trick to slow the spin, or counter-tilt to level the car.
The same controls work on keyboard, gamepad and touch.

Every **complete 360-degree airborne turn adds 500 points**. Multiple flips
in the same flight add together. Jumps lasting at least **0.20 seconds** also
accumulate dynamic points at the fixed 120 Hz simulation rate:

`points/second = 80 + 120 * clamp(abs(horizontal_velocity) / 650, 0, 1) + 100 * abs(pitch) / PI`

Longer jumps, faster travel in either direction and steeper airborne angles
therefore earn more. Pitch is the wrapped chassis angle relative to level;
90 degrees adds 50 points/second, upside down adds 100. Motion points round
once per landed attempt, not once per render frame. Ground driving and short
suspension hops earn no aerial points. Partial turns can earn angle points,
but angle wrapping, grounded rolls and back-and-forth rocking cannot count as
a complete flip; separate jumps cannot combine partial turns into one.

**F, gamepad X or the triangle button toggles hazards on or off anywhere.**
Switching them **on while airborne** gives the current jump a **1.15x multiplier**
on its motion and flip subtotal, rounded to the nearest point. It never
multiplies cargo, previously banked points or the finish bonus. Repeated toggles
do not stack, and switching them off does not undo an activation already earned.
Leaving hazards on through takeoff does not earn a bonus: each new jump needs
its own in-air off/on activation. The normal light toggle survives landings
and recoveries; replay and a new hot-seat turn start with it off. Toggling while
parked does not start the race clock.

The HUD continuously shows **LAND +[pending total]**, plus **HAZARDS x1.15**
when qualified, until the car settles on both wheels for **0.12 seconds**.
Only then are the points added to the star counter, with a landing cue.

A crash or recovery discards the current unlanded attempt, but all previously
banked points remain, even if the run ends without a delivery. Pause freezes
both the attempt and the hazard blink. Replay and each hot-seat turn start fresh.
Player stats show landed flips and aerial points, including the hazard bonus;
motion, flip and hazard totals are also retained separately in share data and
included in results,
shared scores and the usual Sparks payout. Hot-seat standings still rank
finishers by time, not by trick score.

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
time**. The points tooltip also reports banked flips, motion points, hazard
bonuses and pending aerial points with their current multiplier.
The pause button is always available as an icon. The trail now fills
the space previously occupied by the title, score cards and permanent
instruction blocks. Short event notices disappear after 2.5 seconds; a pending
trick's landing prompt stays visible until it is banked or lost.

The eight driving buttons use icons, with rebound key hints on wider screens
and icon-only controls on phones. Tooltips and screen-reader descriptions
retain their action names and keys; full controls and rules remain in the
instructions screen. Optional audio captions remain available above the
controls. Touch targets stay at least 44 physical pixels tall, and controls
remain below the road rather than covering it. Narrow HUDs show minutes and
seconds and wrap on the smallest phones; the full timer, tooltips and results
retain hundredths.

## Camera views

One camera button cycles **Side**, **Chase**, then **Cockpit**. Side is
the default for a new scene and each hot-seat turn. The selection survives
pause and recovery, plus solo replay; switching views never starts the clock, spends
a life or changes the simulation. These are different views of the same
2.5D trail, **not a steering or free-roaming mode**. Throttle, reverse, tilt,
braking and jumping retain exactly the same controls and scoring in every view.

**Side** preserves the original orthographic camera and scenery-only speed
blur. **Chase** follows behind and above the car, looks farther ahead at
speed, and keeps both its eye and its line to the car above the exact road,
including crests. Framing uses the active car's real bounds so a longer body
cannot disappear below a hilltop look-ahead target. **Cockpit** looks through the actual windshield from the
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

Snowflakes have soft edges, varied sizes and three depth layers, with gentle
wind drift and faded volume edges rather than hard-edged squares or sudden
wraps. Backdrop flakes and a sparse layer safely ahead of the car keep snow
visible through narrow windshields without entering the cabin. Dirt and powder
detach from actual tire contacts, drift and fade
after takeoff or braking, and kick backward correctly when reversing.
Small solid dirt clods appear only in Level 1. These effects use fixed-size,
shadow-free batches compatible with desktop, web and mobile rendering.
Pause freezes their presentation clocks; recovery, replay, hot-seat changes
and results clear old tire and light trails.

The shop's parking bay has a soft glowing outline aligned with the **actual
finish interval**, not the decorative stalls beside the building. An amber
outline counts missing plugs; a mint outline says **PARK HERE** once all five
are aboard. Entering too quickly shows **SLOW DOWN**, and a successful stop
changes the signs to **DELIVERED! / DELIVERY COMPLETE**. A crisp, phone-sized
callout points at the bay instead of relying on small 3D lettering. The five
delivery bulbs light individually, and pickup rings remain readable after dark.

The shadow-casting sun now follows an optional **four-minute day/night cycle**:
route-colored afternoon, sunset, a readable blue night, dawn, then afternoon again.
Headlights and warm workshop lighting fade on automatically at dusk. The cycle
starts with the first driving input, freezes during pause and results, and
resets on replay. Recovery penalties do not advance it. Switch it off in
**Settings > Game** for steady afternoon light in the selected route's palette; the gallery, store previews
and share portraits always keep that studio daylight. Lighting never changes
the physics, finish requirements or achievements. The hazard scoring action
works identically in daylight, at night and with either accessibility setting.

## Rules

Collect all **five numbered spark plugs**, then brake inside the garage. Each route's
checkpoints only activate once every earlier plug is collected, so a recovery
can never strand a missing pickup across the quarry. Roof strikes and falls
cost **one of five lives** and recover automatically while lives remain.
The fifth crash ends the run after its impact animation, without respawning
or adding a recovery penalty. Pickup and banked aerial points are kept, but a failed run earns
no finish bonus, medal or completion achievement.

Manual recovery is available when stuck and **does not cost a life**; pickups
and banked aerial points survive either kind of recovery, and each actual recovery adds **five seconds**.
Hard landings cause cosmetic damage only and never consume lives. Replay
restores all five lives.

The clock starts on the first drive, tilt or jump input and pauses with the shared
shell. There is no time limit. The trial owns its crash-only lives and finish
rules rather than using the shell's generic round modes — the manifest still
declares `uses_shell_round_rules = false`.

Gold is an adjusted time of **65 seconds or less**, Silver **95 or less**, and
any other finish earns Bronze. The longer route has a gentler time-bonus decay:
each plug scores 1,000 points, landed jumps add motion/flip points and any earned
hazard bonus, and finishing adds
`max(0, 3000 - ceil(adjusted_seconds * 30))`. Five persistent achievements
reward each level's delivery (`HOME`, `RIDGE`, `SUMMIT`), a no-recovery run
on any level (`CLEAN`) and Gold (`GOLD`).
Assists never block an achievement.

## Cosmetic damage

Every car accumulates five visual stages during a run:

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
`trial_state.gd` sets the threshold at **850 simulation units/second**, retuned
for the higher jumps; landing
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

Completing a solo run or the full hot-seat roster pays **Sparks**, and the main menu's **Store** button spends
them at the Copper Creek garage. The pause menu reaches the same screen, so a
solo car can be resprayed mid-run and comes back wearing the new coat.
Hot-seat cars retain their player paint; wheel purchases still apply immediately.

**Body paint is owned and equipped separately for each car.** Buying a Cube
color cannot unlock or equip a Sonata or CR-V color. Each car remembers its
own solo paint in setup, gameplay, replay and score portraits. Existing paint
purchases and the old equipped-paint slot remain with the **Nissan Cube**;
the Sonata and CR-V start in their own free factory coats. Wheel finishes
remain shared across the entire fleet.

A delivered run pays `round(score × 0.006) + 4`: a 50-second commute pays
43 Sparks before tricks, and a slow delivery pays at least 34. Every banked
500-point flip contributes three Sparks before its extra motion/hazard points.
A failed run still pays for pickups and
banked tricks. Scores and the existing payout formula remain uncapped, so
players can keep practicing clean flips to earn more cosmetics; unlanded
attempts earn nothing.

| Paint shelf | Sells |
| --- | --- |
| Nissan Cube | Factory Bronze (free), Creek Green, Quarry Slate, Plug Ceramic, Signal Orange, Quarry Midnight, Copper Flake, Express Gold |
| Hyundai Sonata | Factory Pearl (free), Lagoon Teal, Sunset Coral, Pacific Azure, Burgundy Pearl, Coastal Lilac, Rose Alloy, Champagne Pearl |
| Honda CR-V | Factory Deep Blue (free), Evergreen, Glacier Silver, Canyon Red, Tundra Sand, Aurora Violet, Storm Graphite, Arctic Ice |

Each car's seven paid paints cost **525, 525, 840, 840, 1,155, 1,470 and
2,520 Sparks**, in the order listed above. Shared wheels are **Factory Alloy
(free), Graphite (630), Bronze Face (945), Trail White (945) and Gloss Black
(1,260)**. All paid prices are **21 times the original price tiers**; factory
looks remain free and round payouts are unchanged. Existing owned items are
not charged again.

The Sonata's paid palette opens with Level 1 completion; the CR-V's opens
with Level 2 completion. Every card previews its actual car and finish,
including unowned paints and factory colors, on the first store visit without
buying or equipping anything. Static previews redraw after scene attachment,
layout changes and showing the card, rather than rendering continuously.

**Nothing on sale is worth a second on the clock.** No item changes mass, grip,
ride height, suspension or scoring — the trial is the same trial in every
colour, which is the point of spending Sparks on paint rather than on parts.
Express Gold is gated behind `cube_trials_gold` and Gloss Black behind
`cube_trials_clean`.

`world/cube_finish.gd` is the only place that knows what a colour *is*. A
finish restates the paint surfaces the GLB exporter already batched — matched
by material name, so `cube_trials_3d_test.gd` fails loudly if a Blender rename
breaks the link — and factory looks apply no override at all, so the
factory car wears the materials Blender wrote rather than a copy of them. Their
shelf swatches are quoted from the same module rather than retyped as hex, and
the test checks each car's factory coat against the export. Store cards, the round and the share
portrait all call the same function, so a swatch on the shelf cannot promise a
colour the trail fails to deliver.

## Gallery

The main menu carries a **Gallery** button, and the pause menu reaches the same
screen mid-round. Eleven exhibits sit on a plinth under Copper Creek's own
late-afternoon daylight. Course exhibits use the same assemblies as gameplay,
while two additional car studies show their saved Blender exports directly.

| Heading | Exhibits |
| --- | --- |
| The car | The Brown Nissan Cube, Alloy Wheel and Tire, Coilover Strut |
| Reference cars | Hyundai Sonata, Honda CR-V |
| The trail | Numbered Spark Plug, Checkpoint Flag, Trail Sign Board |
| Copper Creek | Roadside Pine, Trail Fence |
| The finish | Copper Creek Body Shop |

The car is shown after its suspension has settled under its own weight, the
strut at the length a parked car holds it at, and the plug carries the same
3D-text number the trail hands out. The garage stays locked until the
`cube_trials_home` achievement is earned, so the finish is not spoiled.
The pine, plug, checkpoint and workshop use the same generated GLBs as the
course, including its pickup ring, checkpoint wording and delivery indicators.
The Sonata unlocks after Level 1 and the CR-V after Level 2, with their own models,
factory materials and authored scale. These are the same cars earned for solo and
hot-seat selection; Gallery preserves their pristine source appearance rather
than applying player paint or gameplay damage.

Drag the model to turn it, scroll to zoom, or use the on-screen turn, tilt and
zoom buttons; **Reset** returns to the default framing. Auto-spin is on by
default and is parked by **Reduced motion**, which leaves the model still and
fully controllable.

## Accessibility
Reduced motion parks clouds, water ripples, pickup and flag motion, clears tire
dust, dirt clods, landing puffs and airborne light trails, hides snowfall, and
removes camera smoothing, speed blur and decorative brake-light spill.
It also removes the extra driving rock, impact recoil and impact highlight.
It also keeps afternoon light and stops the parking outline's gentle pulse.
Driving, wheel rotation, suspension travel and necessary camera tracking remain;
essential brake lamps respond immediately instead of fading. The shallow camera
angle keeps the quarry landing visible either way. Disabling intense effects
independently suppresses tire effects, snowfall, airborne light trails, speed blur and brake-light spill without
removing the brake lamps. Either setting hides decorative lamp halos and replaces
the hazard blink with steady lit signals; the written ON/OFF state and the full
scoring bonus remain available. It suppresses the impact highlight, parking halo and
pulse, but keeps the
solid outline, written instructions and essential night lighting. Every
meaningful sound also has visible feedback and an audio caption.

The garage reveal has a 44-pixel **Skip** button. After a short grace, Space,
Enter, Jump or gamepad A also skip it, so a key still held from parking cannot.
Skipping lands on the freed car. Pause still opens the menu and freezes the
scene. Reduced motion shortens it from 7.4 to 4 seconds of instant steps: the
door opens at once, the bars drop at once, and the car wakes without hopping.
Switching mid-scene keeps its place. With reduced motion or intense effects
off, three still hearts replace the floating ones. The door, the bars and the
horn each have a caption.

## Tests

Run from `godot-base`, sequentially, using a fresh isolated user profile for
each suite that changes progression or purchases. The headless and graphical
store runs each need their own fresh profile.

```powershell
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_scene_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_3d_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_lights_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_effects_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/reference_models_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_multiplayer_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_levels_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_builder_test.gd -- --game=cube_trials
godot --headless --path . --script res://games/cube_trials/tests/cube_trials_store_test.gd -- --game=cube_trials
```

| Suite | Covers |
| --- | --- |
| `cube_trials_test.gd` | Fixed-step physics at 30/60/144 FPS; 225-240-unit jumps; input-only front/backflips for every car; exact airtime/angle thresholds, velocity scaling, non-stacking 1.15x hazards, pending/banked/crash/recovery and garage scoring; six real gaps, seven level checkpoints and a 900-unit terrain span; stock ride height, lives, damage and complete drives at both assist limits |
| `cube_trials_scene_test.gd` | Icon counters, live rebinding, mouse and three-finger jumping, F/touch/gamepad X hazard toggles, key-repeat and pause gating, keyboard/touch flips with dynamic HUD and banked stats/share data, assigned/unassigned gamepads, braking, jump reset gating, day/night settings, damage/recovery/replay, assists, five-life loss, the labeled shut door and the real finish's garage reveal (held celebration, focus release, skip grace, pause and resume, skip to results), results and achievements |
| `cube_trials_3d_test.gd` | All five chassis variants, geometry budgets, finishes and instance isolation, helical coilover morphs and mount alignment, airborne wheel droop at 30/60/144 FPS with grounded/terrain-clearance checks, driving/takeoff/landing/impact animation, complete-route cameras, summit flip framing for every car and screen aspect with reduced motion, sun/sky transitions, lights, parking, props and all eleven Gallery exhibits |
| `cube_trials_lights_test.gd` | All cars and damage stages, lit projectors, synchronized front/rear hazards, brake priority, per-car material isolation and steady accessibility signals; without `--headless`, actual brake/hazard pixels on desktop and phone across all biomes, stronger night lighting versus the old settings, damaged signals and draw budgets. Supports `--cube-capture-dir=...` |
| `cube_trials_effects_test.gd` | Grounded tire emission, reverse, real landing puffs, biome palettes and bounded clods; all cars/damage stages and 30/60/144 FPS airborne hazard trails; pause, accessibility, recovery, replay, hot-seat and results cleanup. Without `--headless`, actual snow/dirt pixels and trails extending beyond the car on desktop/phone across camera views, plus draw budgets. Supports `--cube-capture-dir=...` |
| `reference_models_test.gd` | All three cars and four prop GLBs: geometry budgets, finite unit normals, outward-facing plug threads, meter scale, grounded origins, car chassis/wheel hierarchies and pivot placement, two-sided foliage/cloth and texture-free Compatibility materials |
| `cube_trials_multiplayer_test.gd` | Every playable car/damage stage, profile geometry, isolated player paint and factory restoration, clean input-only deliveries at both assist limits and 30/60/144 FPS, independent hot-seat runs and trick totals, release-gated handoffs, three-player stats/share/payout, ties, replay and solo selection |
| `cube_trials_levels_test.gd` | **Fresh isolated profile required**: distinct terrain/garages, beach palms/ocean and snowy foliage/particles, biome lighting and accessibility, original Level 1 geometry, recovery and cameras on all routes; input-only new-level deliveries for all cars at 30/60/144 FPS and both assist limits; locked setup, real solo/hot-seat progression, failed/abandoned runs, save reloads, replay and level-aware results/share data; the Sonata and CR-V behind their labeled, single-mesh shut doors and no reveal on Level 3, the reveal's door/bars/wake order in both timings with and without intense effects, cues played once at their moments, Reduced motion mid-scene, skip and reset, and framing on desktop, phone and ultrawide views |
| `cube_trials_builder_test.gd` | **Fresh isolated profile required**: the Trail Builder's rules restated independently and checked on hand-picked trails and 600 seeded random ones, built by edits or raw; adding, picking, removing, undo, clearing, limits and flattening; saving, saves with unknown or too many blocks, unreadable or missing files and the Saves screen entry; route data, terrain and scenery for all three sceneries, including trails without gaps; deliveries from every checkpoint for all cars by the input-only driver at 30 FPS and at full throttle at 60 FPS, with no recoveries; the unlock gate; the picture-only editor through real taps, drags, wheel and keys; 44-pixel layouts on desktop and phones; real solo and hot-seat drives that pay and award nothing; the HUD and results Build buttons, pause and Reduced motion |
| `cube_trials_store_test.gd` | **Fresh isolated profile required**: independent car paints, unique palettes, exact 21x prices, legacy Cube purchases, car gates, shared wheels, saved selections, gameplay/replay/share application; a graphics run also checks first-open routed previews, factory/unowned colors, resizing, reduced motion and configuration before readiness |
| `cube_trials_view_test.gd` | **Graphics window required** — see below |
| `cube_trials_camera_test.gd` | **Graphics window required** — each car's three perspectives, cockpit visibility while jumping at every damage stage, full-course framing/budgets (including the shut garage door on levels that hide a car) and forward-view night parking |
| `cube_trials_multiplayer_view_test.gd` | **Graphics window required** — real shared setup/instructions routing, solo phone selection, three colored car previews, handoffs, all driver HUDs, results and a complete 1200x630 share image |

`driver_fixture.gd` and `input_gameplay_fixture.gd` are helpers, not suites; skip `*_fixture.gd` when
enumerating tests.

Running the level suite without `--headless` also checks uploaded palm and
snowflake transforms and snow-powder colors. Its headless pass checks authored
placements and scenery contracts without relying on the dummy renderer.

`cube_trials_view_test.gd` needs a **real graphics window** and deliberately
exits 1 under `--headless`, where it guards `DisplayServer.get_name() == "headless"`
and says so. Never read that headless exit code as a regression:

```powershell
godot --path . --script res://games/cube_trials/tests/cube_trials_view_test.gd -- --game=cube_trials
godot --path . --script res://games/cube_trials/tests/cube_trials_effects_test.gd -- --game=cube_trials
godot --path . --script res://games/cube_trials/tests/cube_trials_camera_test.gd -- --game=cube_trials
godot --path . --script res://games/cube_trials/tests/cube_trials_camera_test.gd -- --game=cube_trials --cube-vehicle=cube_sonata
godot --path . --script res://games/cube_trials/tests/cube_trials_camera_test.gd -- --game=cube_trials --cube-vehicle=cube_crv
godot --path . --script res://games/cube_trials/tests/cube_trials_camera_test.gd -- --game=cube_trials --cube-vehicle=cube_sonata --cube-level=sunset_ridge
godot --path . --script res://games/cube_trials/tests/cube_trials_camera_test.gd -- --game=cube_trials --cube-vehicle=cube_crv --cube-level=alpine_pass
godot --path . --script res://games/cube_trials/tests/cube_trials_multiplayer_view_test.gd -- --game=cube_trials
godot --path . --script res://games/cube_trials/tests/cube_trials_store_test.gd -- --game=cube_trials
```

It checks actual 3D geometry and brown bodywork, all five damage stages at
landscape and portrait gameplay scale, each stage's rendered brake lamps and
headlight illumination, scenery blur with sharp car/HUD pixels, effect
accessibility and reset behavior,
landscape/portrait/ultrawide layouts, minimum physical touch-target sizes,
input-driven jumps across all six gaps, full-flip framing and pending/banked
trick feedback, results, 3D share art and the standalone title. It
also compares rendered/hidden coilovers at desktop and phone sizes: inboard
springs must be readable in flight and contribute no exposed pixels while
parked, driving, braking, landing or rebounding, including damage and reduced motion.
Paired airborne renders with and without extra wheel travel must show more
visible coilover pixels on both axles, not merely different internal poses.
It compares rendered day/night parking outlines, headlight and workshop illumination,
nighttime car readability, and the portrait parking target with a minimum
13-physical-pixel callout font. It also checks actual instanced tree transforms,
imported Gallery framing and reference-car menu selection, orbit, zoom and reset across
screen sizes and orbit angles, and the viewport's 200-draw / 120,000-triangle
budget at the start, checkpoints, jump, workshop and garage reveal. The
rendered finish plays the Sonata's reveal: at desktop and phone sizes, the
door, bars, hop and hearts stages must keep the freed car in shot, the hopping
car must really render through the fog and bars, and **Skip** must be a legible
44-pixel target that never covers the car. The results must then open over the
freed car. A standalone Sunset Ridge view checks the heaviest shot, the CR-V
behind its half-open door, at both sizes. Pass an optional
`--cube-capture-dir=<absolute directory>` to save rendered examples.

The camera suite accepts `--cube-vehicle=cube_car|cube_sonata|cube_crv`
(default Cube) and `--cube-level=copper_creek|sunset_ridge|alpine_pass`
(default Copper Creek), also accepts that capture argument and rejects `--headless`;
the numerical camera contracts run in the ordinary 3D suite. The scene suite
covers the camera key and live rebinding, mouse input, simultaneous pedal/camera
touches, emulation de-duplication, pause, recovery, replay and results gating.
Use a fresh isolated profile for the multiplayer view suite too: it exercises
locked choices, live unlocks, phone-sized level selection and the results-to-setup route.

## Regenerating art

The icon and original still artwork in `assets/` are captures of the actual meshes, not a
second interpretation of the car. The same run renders the
`assets/levels/*.png` stills that the shared setup screen's level row and list
show beside each route's title (`course.gd` names them as each level's `icon`).
The three route stills are taken on the real course, without a car, because the
car is chosen on the next row. The Trail Builder's `my_trail.png` is drawn by the
builder itself, from a fixed example trail with its top row of buttons hidden.
Regenerate them with a real graphics window, from `godot-base`:

```powershell
godot --path . --script res://games/cube_trials/tools/capture_art.gd -- --game=cube_trials
```

Append `--only=levels` after `--game=cube_trials` to refresh just the level
stills, the Trail Builder's included, or `--only=builder` for only `my_trail.png`.

`tools/` is development-only and is excluded from every export preset.

### Walkthrough recording

The instructions screen and picker use `assets/video/tutorial.ogv` and its
matching WebP poster. The 36-second captioned Copper Creek segment shows actual
throttle, jumps, collected plugs, checkpoint flags, Side/Chase/Cockpit cameras
and a recovery with its five-second penalty. It introduces the delivery goal,
but does not claim to finish the full course.

Re-record from `godot-base` with
`pwsh tools\record_tutorials.ps1 -Godot godot -Games cube_trials`.
The game-owned `tools/tutorial_driver.gd` reuses the input-only regression driver
and never assigns the car's pose, cargo or checkpoint progress. Its milestone
validator rejects incomplete takes. Capture uses an isolated save profile and a
temporary bottom inset for captions; normal gameplay and physics are unchanged.

### Blender authoring model

Open `tools\blender\nissan_cube.blend` for the bronze Nissan Cube
study. Its rounded body edges, cambered roof, bounded rear hatch glass and
body-colored corner pillars follow the supplied sheet. The hollow cabin has
rounded side panes; broader five-spoke wheels retain individual rotation pivots.
Lights, door seams, mirrors, roof pressings and interior geometry are included.
Thin glass and lamp rims have separate shading normals to avoid warped reflections.
Scene units are meters, with Z up
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

The game and score portrait use the selected car's GLB through
`world/cube_model.gd`; generated promotional artwork retains the original Cube.
To export the
current saved Blender model without overwriting it, run from this repository:

```powershell
blender --background --factory-startup .\tools\blender\nissan_cube.blend --python-exit-code 1 --python .\tools\blender\export_nissan_cube.py
```

Append `-- --render-previews` to refresh both the front and rear studio PNGs
from the saved source before exporting. Neither operation resaves the
pristine authoring file.

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
asset contains **44,266 triangles in 16 mesh nodes / 41 material surfaces**.
The exporter removes subpixel detailing, simplifies curves and meshes, batches
by finish and rejects exports above 45,000 triangles or 48 surfaces. Glass
uses alpha transparency rather than Cycles transmission/refraction, so it
works with Godot's Compatibility renderer. Godot also generates mesh LODs.
The legacy `WraparoundGlazing` mesh/material identifiers remain unchanged for
runtime compatibility; the geometry now follows the reference's bounded rear
window rather than the earlier continuous wrap.

The separate damage GLB contains only four replacement chassis variants and
their paint/light markers, not additional wheels or physics. It adds about
3.5 MB on disk. Only one chassis is drawn: complete damaged cars range from
**46,536 to 47,424 triangles and 43-44 surfaces**, within the enforced
**48,000-triangle / 48-surface** limit. Scrapes and cracks are thin, projected
geometry with portable materials, requiring neither textures nor decals.
Unused variants remain shared mesh resources, not hidden full-car instances.

Instance `world/nissan_cube.tscn` for this game's stock-proportion assembly.
The adapter uniformly scales the body and detailed five-spoke wheels, keeping
the tires tucked beneath the fenders rather than stretching or lifting the car.
`vehicle_tuning.gd` synchronizes the model with its collision tire radius,
short suspension, bump stops, roof/belly contacts and checkpoint ride height.
The Cube's runtime tires have a 0.324 m radius, with about 0.23 m of
body clearance at rest. Wheel travel, spin and brake animation follow
`trial_state.gd`; each car has its own brake material and optional glow lights.
The internal runtime coilovers are generated by `world/coilover.gd`, rather than
embedded in the car GLB, and are visible on the car only while airborne. All four
share two travel morph targets and keep their round wire, damper diameter and
mounting hardware at a fixed scale.
To reuse the car in another Godot project, copy just the GLB and let that
project import it; the reusable scene depends on Cube Trials' scripts.

### Sonata and CR-V authoring and damage

`car2.png` and `car3.png` use the Nissan Cube authoring workflow: original,
unbranded geometry based on the visible proportions, editable Blender studios,
front/rear rendered previews, and separate portable GLBs.

| Reference | Study | Model name | Exported triangles | Material surfaces |
| --- | --- | --- | ---: | ---: |
| `car2.png` | White Hyundai Sonata sedan | `hyundai_sonata` | 42,726 | 43 |
| `car3.png` | Blue Honda CR-V crossover | `honda_crv` | 43,696 | 42 |

Each model has a `.blend`, `*_preview.png` and `*_rear.png` under
`tools\blender\`, plus a `.glb` and Godot `.import` sidecar under
`assets\models\`. Both have compound-curved bodywork, shaped bumpers, pressed
door panels and revised glazing outlines instead of box-based cabins.
The sedan has an arched, sloping glasshouse, stacked grille louvres, recessed
projector-style headlights, a connected rear light bar and twin rectangular
exhaust outlets. The crossover has raised bodywork, integrated black bumper
and wheel-arch cladding, chrome grille wings, tall rear lamps with opaque
housings, low roof rails, an inset sunroof and a rear wiper. Both include hollow
cabins, separate glass with clean rim normals, seats, dashboards, mirrors,
door seams and two-tone machined/graphite split-spoke wheels with four
independent rotation pivots.

As with the Cube, Blender uses meters, Z up and a -Y-facing nose. Frames 1-5
select front three-quarter, rear three-quarter, side, front and rear cameras.
The GLBs use meters, Y up and +X forward, with a `Chassis` and four wheel
pivots under `HyundaiSonata` or `HondaCRV`. Their texture-free materials work
with Godot's Compatibility renderer; cameras, lights and studio floors are
excluded. The exporter enforces 45,000 triangles and 48 material surfaces per
car and checks the written wheel hierarchy and meter-scaled pivot positions.
The denser editable Blender surfaces are preserved; runtime-only reduction
keeps each GLB within the existing game budget.

Rebuild each editable source in a fresh Blender process:

```powershell
foreach ($name in "hyundai_sonata", "honda_crv") {
    blender --background --factory-startup --python-exit-code 1 --python .\tools\blender\generate_reference_cars.py -- --car $name
    if ($LASTEXITCODE -ne 0) { throw "Generation failed: $name" }
}
```

Export the **saved sources**, optionally refreshing both rendered previews:

```powershell
foreach ($name in "hyundai_sonata", "honda_crv") {
    blender --background --factory-startup ".\tools\blender\$name.blend" --python-exit-code 1 --python .\tools\blender\export_reference_cars.py -- --render-previews
    if ($LASTEXITCODE -ne 0) { throw "Export failed: $name" }
}
```

Omit `--render-previews` for export alone. Exporting hashes and preserves the
saved `.blend`, including manual edits; regenerating intentionally replaces
it. Shared primitives come from the existing car and prop helpers. The
generators do not read or pack the reference images, and neither model
reproduces manufacturer emblems, badges or lettering.

These are **playable, reusable assets**, also shown under **Gallery > Reference cars**.
The exporter adds one paint marker and four brake/headlight sockets to each
pristine chassis without altering its geometry or materials. Each car has
27 nodes, including 16 mesh nodes, and all five sockets follow its damage.
`vehicle_profiles.gd` connects the original geometry to the shared runtime rig,
driving simulation, garage finishes and score portrait.

Exporting also produces `<model>_damage.glb` and a derived
`<model>_damage.blend` containing the five complete inspection cars.
The pristine `.blend` files remain unchanged. `cube_damage.py` uses a shared
deformation field with per-model dimensions and roof travel; the lower
windshields retain a usable opening above the dashboard. Surface-mapped
scrapes and cracks stay attached to the exact deformed triangles.

| Car | Scuffed triangles | Dented | Crumpled | Battered | Surfaces by damaged stage |
| --- | ---: | ---: | ---: | ---: | --- |
| Nissan Cube | 46,536 | 46,728 | 47,136 | 47,424 | 43 / 43 / 44 / 44 |
| Hyundai Sonata | 44,272 | 44,464 | 44,872 | 45,160 | 45 / 45 / 46 / 46 |
| Honda CR-V | 45,268 | 45,460 | 45,868 | 46,156 | 44 / 44 / 45 / 45 |

These counts include the original wheels, but not the separately generated
runtime coilovers. Every complete car remains below 48,000 triangles and
48 material surfaces. Commit each damage GLB and its `.import` sidecar;
the derived Blender scenes remain development-only. The prop assets are unchanged.

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
markings match the active route's `finish_x` and `finish_width` exactly. Driving
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
Games. The Nissan Cube, additional Sonata and CR-V studies, pines, spark plugs,
checkpoints and body shop use original Blender geometry exported to glTF.
Terrain, trail signs, fences, gameplay indicators and remaining roadside
detail are original geometry built in code.

Inspired by classic elastic-suspension trials games, including Elasto Mania. No
Elasto Mania levels, code, artwork or audio are included.

Nissan and Cube are trademarks of their respective owners. Cube Trials is an
unofficial tribute and is not affiliated with, endorsed by or sponsored by
Nissan. `tools/reference/car.png` is third-party reference imagery, is not
covered by this repository's licence and is never shipped in a build — see
[`tools/reference/README.md`](tools/reference/README.md).
Hyundai, Sonata, Honda and CR-V are also trademarks of their respective
owners; the additional unbranded studies imply no affiliation or endorsement.
Their user-supplied reference sheets remain development-only.