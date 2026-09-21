extends RefCounted

## Preload-safe controls and assists; the shared settings screen owns persistence.

## The shelf quotes the finish module for the two free looks, so a card's
## swatch and the car's actual paint cannot disagree.
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")

const GAME_ID := "cube_trials"
const AIR_CONTROL_KEY := "game/cube_trials_air_control"
const ENGINE_AUDIO_KEY := "game/cube_trials_engine_audio"
const THROTTLE := &"cube_trials_throttle"
const REVERSE := &"cube_trials_reverse"
const NOSE_UP := &"cube_trials_nose_up"
const NOSE_DOWN := &"cube_trials_nose_down"
const BRAKE := &"cube_trials_brake"
const RECOVER := &"cube_trials_recover"
const DRIVE_ACTIONS: Array[StringName] = [NOSE_UP, NOSE_DOWN, REVERSE, THROTTLE, BRAKE]

const TUNABLES: Array[Dictionary] = [
	{
		"key": AIR_CONTROL_KEY, "default": 1.0, "min": 0.5, "max": 1.5,
		"step": 0.1, "format": GameManifest.FORMAT_PERCENT,
		"title": "Air control", "heading": "Cube Trials - live",
		"description": "How strongly the tilt controls rotate the car. Takes effect immediately.",
	},
	{
		"key": ENGINE_AUDIO_KEY, "type": GameManifest.OPTION_TOGGLE,
		"default": true, "title": "Engine sound", "heading": "Cube Trials - live",
		"description": "Play the car's continuous engine hum. Event sounds remain enabled.",
	},
]

const CONTROL_BINDINGS: Array[Dictionary] = [
	{
		"key": "controls/cube_trials_throttle", "action": THROTTLE,
		"default": KEY_W, "title": "Accelerate", "player": 0,
		"description": "Drive toward the garage.", "heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_reverse", "action": REVERSE,
		"default": KEY_S, "title": "Reverse", "player": 0,
		"description": "Drive backward to retrieve a missed spark plug.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_nose_up", "action": NOSE_UP,
		"default": KEY_A, "title": "Tilt nose up", "player": 0,
		"description": "Rotate counterclockwise, especially during a jump.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_nose_down", "action": NOSE_DOWN,
		"default": KEY_D, "title": "Tilt nose down", "player": 0,
		"description": "Rotate clockwise to land on both wheels.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_brake", "action": BRAKE,
		"default": KEY_SPACE, "title": "Brake", "player": 0,
		"description": "Slow both wheels. Brake inside the garage to finish.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_recover", "action": RECOVER,
		"default": KEY_R, "title": "Recover (+5 seconds)", "player": 0,
		"description": "Return to the last checkpoint, keeping collected plugs.",
		"heading": "Cube Trials",
	},
]

# --------------------------------------------------------------------------
# The paint shop
# --------------------------------------------------------------------------

## What a finished run pays, and what that money is called.
##
## Sparks are named for the cargo: the five plugs are worth 1,000 each, and
## finishing adds up to 3,000 more, so a delivered run scores between 5,000 and
## roughly 7,400 and an abandoned one scores whatever was collected. At this
## rate a Gold delivery pays about 41 Sparks and the cheapest respray costs
## most of one run.
##
## There is deliberately no ceiling. A payout cap exists to stop an open-ended
## score being farmed, and this one cannot be: Copper Creek has five plugs, one
## finish line and a bonus that only shrinks with time, so the round caps
## itself. Nor is there a win bonus — the trail has no opponent to beat.
const STORE_CURRENCY := {
	"name": "Spark",
	"plural": "Sparks",
	"points_per_score": 0.006,
	"round_bonus": 4,
	"win_bonus": 0,
	"max_per_round": 0,
}

const PAINT_KIND := "paint"
const RIM_KIND := "rim"
const PAINT_SLOT := "cube_body_paint"
const RIM_SLOT := "cube_wheel_finish"

const PAINT_FACTORY := "cube_paint_factory"
const PAINT_CREEK := "cube_paint_creek"
const PAINT_QUARRY := "cube_paint_quarry"
const PAINT_CERAMIC := "cube_paint_ceramic"
const PAINT_SIGNAL := "cube_paint_signal"
const PAINT_MIDNIGHT := "cube_paint_midnight"
const PAINT_COPPER := "cube_paint_copper"
const PAINT_GOLD := "cube_paint_gold"

const RIM_FACTORY := "cube_rim_factory"
const RIM_GRAPHITE := "cube_rim_graphite"
const RIM_BRONZE := "cube_rim_bronze"
const RIM_WHITE := "cube_rim_white"
const RIM_BLACK := "cube_rim_black"

const PAINT_HEADING := "Body paint"
const RIM_HEADING := "Wheels"

## Two slots, because the garage does two jobs. They take different kinds
## rather than the same one, so a wheel finish can never be sprayed onto the
## bodywork: the only car on Copper Creek wears one of each at a time.
const STORE_SLOTS: Array[Dictionary] = [
	{
		"id": PAINT_SLOT,
		"kind": PAINT_KIND,
		"title": "Body paint",
		"description": "What colour the Cube leaves the garage in.",
	},
	{
		"id": RIM_SLOT,
		"kind": RIM_KIND,
		"title": "Wheels",
		"description": "The finish on all four alloys.",
	},
]

## Everything the garage will respray.
##
## Nothing sold here is worth a single second on the clock, and nothing changes
## the car's mass, grip or suspension: the trial is the same trial in every
## colour. That is the point of spending Sparks on paint rather than on parts.
##
## The two factory looks are free, owned from the start and worn by default,
## and they apply no override at all — they are the materials the exporter
## wrote, not a copy of them. `world/cube_finish.gd` holds every other colour.
const STORE_ITEMS: Array[Dictionary] = [
	{
		"id": PAINT_FACTORY,
		"kind": PAINT_KIND,
		"price": 0,
		"default": true,
		"title": "Factory Bronze",
		"description": (
			"The brown the Cube was delivered in, and the brown it will be "
			+ "described as forever. Warm metallic with a darker seam coat."
		),
		"badge": "STOCK",
		"color": Finish.FACTORY_COAT,
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_CREEK,
		"kind": PAINT_KIND,
		"price": 25,
		"title": "Creek Green",
		"description": (
			"Mixed to the hillside the trail is cut into. Excellent camouflage "
			+ "for a car that spends a lot of time off the road."
		),
		"badge": "CREEK",
		"color": Color("4a5f3c"),
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_QUARRY,
		"kind": PAINT_KIND,
		"price": 25,
		"title": "Quarry Slate",
		"description": (
			"The grey of the stone either side of the jump. Sensible, sober, "
			+ "and the exact colour of the thing you are trying to clear."
		),
		"badge": "SLATE",
		"color": Color("6d757a"),
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_CERAMIC,
		"kind": PAINT_KIND,
		"price": 40,
		"title": "Plug Ceramic",
		"description": (
			"Off-white, flatter than the rest of the shelf, matched to the "
			+ "ribbed ceramic on the cargo. A delivery van in spirit."
		),
		"badge": "PLUG",
		"color": Color("ded6c4"),
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_SIGNAL,
		"kind": PAINT_KIND,
		"price": 40,
		"title": "Signal Orange",
		"description": (
			"Roadworks orange. Visible from the far side of the quarry, which "
			+ "is where the car often ends up."
		),
		"badge": "SIGNAL",
		"color": Color("c7601c"),
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_MIDNIGHT,
		"kind": PAINT_KIND,
		"price": 55,
		"title": "Quarry Midnight",
		"description": (
			"Deep blue with a wet clear coat, so the late-afternoon sun runs "
			+ "along the roof rail on every landing."
		),
		"badge": "NIGHT",
		"color": Color("27384d"),
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_COPPER,
		"kind": PAINT_KIND,
		"price": 70,
		"title": "Copper Flake",
		"description": (
			"The creek's own copper, laid on thick and polished hard. Nearly "
			+ "bare metal, and it behaves like it under the sun."
		),
		"badge": "FLAKE",
		"color": Color("b0642c"),
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_GOLD,
		"kind": PAINT_KIND,
		"price": 120,
		"requires_achievement": "cube_trials_gold",
		"title": "Express Gold",
		"description": (
			"Reserved for cars that have done the commute in under "
			+ "45 seconds. The garage checks before it opens the tin."
		),
		"badge": "GOLD",
		"color": Color("d9a441"),
		"heading": PAINT_HEADING,
	},
	{
		"id": RIM_FACTORY,
		"kind": RIM_KIND,
		"price": 0,
		"default": true,
		"title": "Factory Alloy",
		"description": (
			"Five polished spokes and a chrome lip, exactly as exported. The "
			+ "wheel every other finish on this shelf is sprayed over."
		),
		"badge": "ALLOY",
		"color": Finish.FACTORY_ALLOY,
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_GRAPHITE,
		"kind": RIM_KIND,
		"price": 30,
		"title": "Graphite",
		"description": (
			"Dark grey spokes under a lighter lip. Hides the Copper Creek dust "
			+ "that the polished set advertises."
		),
		"badge": "GRAPH",
		"color": Color("4d5357"),
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_BRONZE,
		"kind": RIM_KIND,
		"price": 45,
		"title": "Bronze Face",
		"description": (
			"Warm bronze spokes with a bright edge. Matches the factory paint "
			+ "closely enough to look intentional, which it is."
		),
		"badge": "BRONZE",
		"color": Color("9a6a36"),
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_WHITE,
		"kind": RIM_KIND,
		"price": 45,
		"title": "Trail White",
		"description": (
			"Painted rather than polished, so the spokes read flat and the "
			+ "rim edge is the only thing still catching the light."
		),
		"badge": "WHITE",
		"color": Color("e4e6e0"),
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_BLACK,
		"kind": RIM_KIND,
		"price": 60,
		"requires_achievement": "cube_trials_clean",
		"title": "Gloss Black",
		"description": (
			"Lacquered black, kept for cars that finished without a scratch. "
			+ "It shows every mark, which is rather the point."
		),
		"badge": "GLOSS",
		"color": Color("1e2226"),
		"heading": RIM_HEADING,
	},
]

# --------------------------------------------------------------------------
# The gallery
# --------------------------------------------------------------------------

const EXHIBIT_CUBE := "cube_car"
const EXHIBIT_WHEEL := "cube_wheel"
const EXHIBIT_SUSPENSION := "cube_suspension"
const EXHIBIT_PLUG := "cube_plug"
const EXHIBIT_CHECKPOINT := "cube_checkpoint"
const EXHIBIT_SIGN := "cube_sign"
const EXHIBIT_PINE := "cube_pine"
const EXHIBIT_FENCE := "cube_fence"
const EXHIBIT_GARAGE := "cube_garage"

## The cast of Copper Creek, on plinths.
##
## A trials course is driven past at speed and read from one fixed side, so
## almost nothing here is ever seen from more than one angle in play. Every
## exhibit is therefore the model the game itself builds — the imported car
## settled on its own suspension solver, the scenery straight out of
## `copper_creek.gd` — rather than a nicer one made for a display case.
##
## The facts are each exhibit's label card. They exist so a model is never
## carried by the picture alone, which is the same reason the signs, the plugs
## and the garage all say their state in words out on the trail.
const GALLERY_EXHIBITS: Array[Dictionary] = [
	{
		"id": EXHIBIT_CUBE,
		"title": "The Brown Nissan Cube",
		"heading": "The car",
		"badge": "CUBE",
		"color": Color("805234"),
		"description": (
			"The whole car, parked on its own springs. Nothing is posed: it is "
			+ "settled here by the same solver that drives it."
		),
		"facts": [
			"Original Blender geometry: 44,398 triangles in 16 mesh nodes",
			"A 2.53 m wheelbase and about 23 cm of clearance at rest",
			"Hollow cabin, driver, mirrors, door seams and wraparound glass",
			"The rear lamps are a live material, not a painted-on glow",
		],
	},
	{
		"id": EXHIBIT_WHEEL,
		"title": "Alloy Wheel and Tire",
		"heading": "The car",
		"badge": "WHEEL",
		"color": Color("bfc8b8"),
		"description": (
			"One of the four wheel pivots, lifted out of the same export the "
			+ "car is assembled from."
		),
		"facts": [
			"A five-spoke alloy inside its own tire, both modelled",
			"Scaled by the body's own factor, so it is never stretched to fit",
			"In play its rim angle is the distance the wheel has really rolled",
		],
	},
	{
		"id": EXHIBIT_SUSPENSION,
		"title": "Coilover Strut",
		"heading": "The car",
		"badge": "SPRING",
		"color": Color("dda368"),
		"description": (
			"The part the whole game is about, shown at the length the parked "
			+ "car's own weight settles it to."
		),
		"facts": [
			"One per wheel; the car carries four",
			"Travel runs from 6.75 to 14.5 units, parked at 8.44",
			"Stiffness 160 against 980 of gravity, damped at 12",
			"Stepped at a fixed 120 Hz, so the ride is frame-rate independent",
		],
	},
	{
		"id": EXHIBIT_PLUG,
		"title": "Numbered Spark Plug",
		"heading": "The trail",
		"badge": "PLUG",
		"color": Color("e6c77d"),
		"description": (
			"The pickup the commute is built around. Five are scattered along "
			+ "Copper Creek and all five have to reach the garage."
		),
		"facts": [
			"Ceramic ribs, a six-sided collar, an electrode and a gold ring",
			"Worth 1,000 points each",
			"Its number is real 3D text, so a plug is never only a shape",
			"Turns and bobs in play unless Reduced motion parks it",
		],
	},
	{
		"id": EXHIBIT_CHECKPOINT,
		"title": "Checkpoint Flag",
		"heading": "The trail",
		"badge": "FLAG",
		"color": Color("558b87"),
		"description": (
			"Where a recovery puts you back. It only arms once every earlier "
			+ "plug has been collected, so it can never strand one."
		),
		"facts": [
			"Two stand on the trail; the start line is the third",
			"A 3.70-unit mast under a copper finial",
			"Cream until the checkpoint saves, then teal — and it says so too",
		],
	},
	{
		"id": EXHIBIT_SIGN,
		"title": "Trail Sign Board",
		"heading": "The trail",
		"badge": "SIGN",
		"color": Color("2f5146"),
		"description": (
			"The trailhead board. Five of these name each stretch of the "
			+ "course and say what it is about to do to you."
		),
		"facts": [
			"A rounded board over a cream plate and a recessed panel",
			"Both lines are 3D text, not painted into the board",
			"Set back out of the driving plane, on two leaning posts",
		],
	},
	{
		"id": EXHIBIT_PINE,
		"title": "Roadside Pine",
		"heading": "Copper Creek",
		"badge": "PINE",
		"color": Color("456c53"),
		"description": (
			"The tree the hillside is planted with, standing behind the road's "
			+ "shoulder where the car cannot reach it."
		),
		"facts": [
			"A tapered trunk under four cones, each turned a little further",
			"Each tier is lightened slightly toward the top",
			"Planted between 0.80x and 1.32x along the trail; shown at 1.06x",
		],
	},
	{
		"id": EXHIBIT_FENCE,
		"title": "Trail Fence",
		"heading": "Copper Creek",
		"badge": "RAIL",
		"color": Color("b29c70"),
		"description": (
			"One bay of the waist-high rail that marks the far shoulder of "
			+ "Copper Creek. They are markers rather than a barrier, so they "
			+ "come in short runs with the hillside showing between them."
		),
		"facts": [
			"A leaning post and the single rail it carries",
			"Planted on every third stake, 6.15 units apart",
			"Stands 2.92 units back from the road, well clear of the car",
		],
	},
	{
		"id": EXHIBIT_GARAGE,
		"title": "Copper Creek Trail Service",
		"heading": "The finish",
		"badge": "HOME",
		"color": Color("517060"),
		"description": (
			"The end of the commute, shown with every plug delivered. Brake "
			+ "inside it and the drive is over."
		),
		"facts": [
			"Roller door, side door, fascia, gate posts and three oil drums",
			"Five bulbs over the door, one per plug delivered",
			"Its sign is the finish rule, and it changes when all five arrive",
		],
		"requires_achievement": "cube_trials_home",
	},
]
