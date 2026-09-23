extends RefCounted

## Preload-safe controls and assists; the shared settings screen owns persistence.

## The shelf quotes the finish module for every look, so a card's
## swatch and the car's actual paint cannot disagree.
const Finish = preload("res://games/cube_trials/world/cube_finish.gd")
const Course = preload("res://games/cube_trials/course.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")

const GAME_ID := "cube_trials"
const AIR_CONTROL_KEY := "game/cube_trials_air_control"
const ENGINE_AUDIO_KEY := "game/cube_trials_engine_audio"
const DAY_NIGHT_KEY := "game/cube_trials_day_night"
const THROTTLE := &"cube_trials_throttle"
const REVERSE := &"cube_trials_reverse"
const NOSE_UP := &"cube_trials_nose_up"
const NOSE_DOWN := &"cube_trials_nose_down"
const JUMP := &"cube_trials_jump"
const HAZARDS := &"cube_trials_hazards"
const BRAKE := &"cube_trials_brake"
const RECOVER := &"cube_trials_recover"
const CAMERA := &"cube_trials_camera"
const DRIVE_ACTIONS: Array[StringName] = [NOSE_UP, NOSE_DOWN, REVERSE, THROTTLE, JUMP, HAZARDS, BRAKE]

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
	{
		"key": DAY_NIGHT_KEY, "type": GameManifest.OPTION_TOGGLE,
		"default": true, "title": "Day / night cycle", "heading": "Cube Trials - live",
		"description": (
			"A gentle four-minute cycle with automatic headlights. "
			+ "Turn off for steady afternoon light. Reduced motion also keeps daylight."
		),
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
		"description": "Hold in the air to backflip. Release to slow the spin, then land on both wheels.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_nose_down", "action": NOSE_DOWN,
		"default": KEY_D, "title": "Tilt nose down", "player": 0,
		"description": "Hold in the air to frontflip. Release to slow the spin, then land on both wheels.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_jump", "action": JUMP,
		"default": KEY_SPACE, "title": "Jump", "player": 0,
		"description": "Jump high from the trail. Release between jumps; tilt for flips and level landings.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_hazards", "action": HAZARDS,
		"default": KEY_F, "title": "Hazard lights", "player": 0,
		"description": "Toggle hazards. Switch on during a jump for 1.15x aerial points; land to bank them.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_brake", "action": BRAKE,
		"default": KEY_SHIFT, "title": "Brake", "player": 0,
		"description": "Slow both wheels. Brake inside the garage to finish.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_recover", "action": RECOVER,
		"default": KEY_R, "title": "Recover (+5 seconds)", "player": 0,
		"description": "Return to the last checkpoint. Keep plugs and banked points; lose unlanded tricks.",
		"heading": "Cube Trials",
	},
	{
		"key": "controls/cube_trials_camera", "action": CAMERA,
		"default": KEY_C, "title": "Change camera", "player": 0,
		"description": "Cycle Side, Chase and Cockpit views. Driving controls stay the same.",
		"heading": "Cube Trials",
	},
]

# --------------------------------------------------------------------------
# The paint shop
# --------------------------------------------------------------------------

## Cargo, banked aerial points and the shrinking finish bonus share the same Sparks rate.
## Score and payout stay uncapped; repeated clean tricks can earn more cosmetics.
const STORE_CURRENCY := {
	"name": "Spark",
	"plural": "Sparks",
	"points_per_score": 0.006,
	"round_bonus": 4,
	"win_bonus": 0,
	"max_per_round": 0,
}

const PAINT_KIND := "paint"
const SONATA_PAINT_KIND := "sonata_paint"
const CRV_PAINT_KIND := "crv_paint"
const RIM_KIND := "rim"
const PAINT_SLOT := "cube_body_paint"
const SONATA_PAINT_SLOT := "cube_sonata_body_paint"
const CRV_PAINT_SLOT := "cube_crv_body_paint"
const RIM_SLOT := "cube_wheel_finish"
const STORE_PRICE_MULTIPLIER := 21
const PAINT_KINDS := {
	Profiles.CUBE: PAINT_KIND,
	Profiles.SONATA: SONATA_PAINT_KIND,
	Profiles.CRV: CRV_PAINT_KIND,
}
const PAINT_SLOTS := {
	Profiles.CUBE: PAINT_SLOT,
	Profiles.SONATA: SONATA_PAINT_SLOT,
	Profiles.CRV: CRV_PAINT_SLOT,
}

const PAINT_FACTORY := "cube_paint_factory"
const PAINT_CREEK := "cube_paint_creek"
const PAINT_QUARRY := "cube_paint_quarry"
const PAINT_CERAMIC := "cube_paint_ceramic"
const PAINT_SIGNAL := "cube_paint_signal"
const PAINT_MIDNIGHT := "cube_paint_midnight"
const PAINT_COPPER := "cube_paint_copper"
const PAINT_GOLD := "cube_paint_gold"

const SONATA_PAINT_FACTORY := "cube_sonata_paint_factory"
const SONATA_PAINT_LAGOON := "cube_sonata_paint_lagoon"
const SONATA_PAINT_CORAL := "cube_sonata_paint_coral"
const SONATA_PAINT_AZURE := "cube_sonata_paint_azure"
const SONATA_PAINT_BURGUNDY := "cube_sonata_paint_burgundy"
const SONATA_PAINT_LILAC := "cube_sonata_paint_lilac"
const SONATA_PAINT_ROSE := "cube_sonata_paint_rose"
const SONATA_PAINT_CHAMPAGNE := "cube_sonata_paint_champagne"

const CRV_PAINT_FACTORY := "cube_crv_paint_factory"
const CRV_PAINT_FOREST := "cube_crv_paint_forest"
const CRV_PAINT_GLACIER := "cube_crv_paint_glacier"
const CRV_PAINT_CANYON := "cube_crv_paint_canyon"
const CRV_PAINT_TUNDRA := "cube_crv_paint_tundra"
const CRV_PAINT_AURORA := "cube_crv_paint_aurora"
const CRV_PAINT_STORM := "cube_crv_paint_storm"
const CRV_PAINT_ARCTIC := "cube_crv_paint_arctic"

const RIM_FACTORY := "cube_rim_factory"
const RIM_GRAPHITE := "cube_rim_graphite"
const RIM_BRONZE := "cube_rim_bronze"
const RIM_WHITE := "cube_rim_white"
const RIM_BLACK := "cube_rim_black"

const PAINT_HEADING := "Nissan Cube - Body paint"
const SONATA_PAINT_HEADING := "Hyundai Sonata - Body paint"
const CRV_PAINT_HEADING := "Honda CR-V - Body paint"
const RIM_HEADING := "Wheels - All cars"

## Separate kinds prevent buying or equipping one car's paint for another.
## The Cube keeps the legacy ids, so existing purchases and its chosen coat survive.
const STORE_SLOTS: Array[Dictionary] = [
	{
		"id": PAINT_SLOT,
		"kind": PAINT_KIND,
		"title": "Nissan Cube",
		"description": "Body paint owned and equipped only for the Nissan Cube.",
	},
	{
		"id": SONATA_PAINT_SLOT,
		"kind": SONATA_PAINT_KIND,
		"title": "Hyundai Sonata",
		"description": "Body paint owned and equipped only for the Hyundai Sonata.",
	},
	{
		"id": CRV_PAINT_SLOT,
		"kind": CRV_PAINT_KIND,
		"title": "Honda CR-V",
		"description": "Body paint owned and equipped only for the Honda CR-V.",
	},
	{
		"id": RIM_SLOT,
		"kind": RIM_KIND,
		"title": "Wheels",
		"description": "One shared finish for the alloys on every car.",
	},
]

## Everything the garage will respray.
##
## Nothing sold here is worth a single second on the clock, and nothing changes
## the car's mass, grip or suspension: the trial is the same trial in every
## colour. That is the point of spending Sparks on paint rather than on parts.
##
## Factory looks are free, owned from the start and worn by default,
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
			"The Nissan Cube's original bronze coat, straight from the factory. "
			+ "Hot-seat trials always use the driver's blue, red or green instead."
		),
		"badge": "STOCK",
		"color": Finish.FACTORY_COAT,
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_CREEK,
		"kind": PAINT_KIND,
		"price": 25 * STORE_PRICE_MULTIPLIER,
		"title": "Creek Green",
		"description": (
			"Mixed to the hillside the trail is cut into. Excellent camouflage "
			+ "for a car that spends a lot of time off the road."
		),
		"badge": "CREEK",
		"color": Finish.PAINTS[PAINT_CREEK]["color"],
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_QUARRY,
		"kind": PAINT_KIND,
		"price": 25 * STORE_PRICE_MULTIPLIER,
		"title": "Quarry Slate",
		"description": (
			"The grey of the stone either side of the jump. Sensible, sober, "
			+ "and the exact colour of the thing you are trying to clear."
		),
		"badge": "SLATE",
		"color": Finish.PAINTS[PAINT_QUARRY]["color"],
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_CERAMIC,
		"kind": PAINT_KIND,
		"price": 40 * STORE_PRICE_MULTIPLIER,
		"title": "Plug Ceramic",
		"description": (
			"Off-white, flatter than the rest of the shelf, matched to the "
			+ "ribbed ceramic on the cargo. A delivery van in spirit."
		),
		"badge": "PLUG",
		"color": Finish.PAINTS[PAINT_CERAMIC]["color"],
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_SIGNAL,
		"kind": PAINT_KIND,
		"price": 40 * STORE_PRICE_MULTIPLIER,
		"title": "Signal Orange",
		"description": (
			"Roadworks orange. Visible from the far side of the quarry, which "
			+ "is where the car often ends up."
		),
		"badge": "SIGNAL",
		"color": Finish.PAINTS[PAINT_SIGNAL]["color"],
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_MIDNIGHT,
		"kind": PAINT_KIND,
		"price": 55 * STORE_PRICE_MULTIPLIER,
		"title": "Quarry Midnight",
		"description": (
			"Deep blue with a wet clear coat, so the late-afternoon sun runs "
			+ "along the roof rail on every landing."
		),
		"badge": "NIGHT",
		"color": Finish.PAINTS[PAINT_MIDNIGHT]["color"],
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_COPPER,
		"kind": PAINT_KIND,
		"price": 70 * STORE_PRICE_MULTIPLIER,
		"title": "Copper Flake",
		"description": (
			"The creek's own copper, laid on thick and polished hard. Nearly "
			+ "bare metal, and it behaves like it under the sun."
		),
		"badge": "FLAKE",
		"color": Finish.PAINTS[PAINT_COPPER]["color"],
		"heading": PAINT_HEADING,
	},
	{
		"id": PAINT_GOLD,
		"kind": PAINT_KIND,
		"price": 120 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": "cube_trials_gold",
		"title": "Express Gold",
		"description": (
			"Reserved for cars that have earned a Gold delivery. "
			+ "The garage checks before it opens the tin."
		),
		"badge": "GOLD",
		"color": Finish.PAINTS[PAINT_GOLD]["color"],
		"heading": PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_FACTORY,
		"kind": SONATA_PAINT_KIND,
		"price": 0,
		"default": true,
		"title": "Factory Pearl",
		"description": "The Sonata's original pearl-white finish. Always available for this car.",
		"badge": "STOCK",
		"color": Finish.FACTORY_COATS[Profiles.SONATA],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_LAGOON,
		"kind": SONATA_PAINT_KIND,
		"price": 25 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Lagoon Teal",
		"description": "A clear coastal teal for the Sonata's long, sculpted panels.",
		"badge": "LAGOON",
		"color": Finish.PAINTS[SONATA_PAINT_LAGOON]["color"],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_CORAL,
		"kind": SONATA_PAINT_KIND,
		"price": 25 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Sunset Coral",
		"description": "Warm coral with a soft sheen, made for the Sonata's beach commute.",
		"badge": "CORAL",
		"color": Finish.PAINTS[SONATA_PAINT_CORAL]["color"],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_AZURE,
		"kind": SONATA_PAINT_KIND,
		"price": 40 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Pacific Azure",
		"description": "Bright metallic blue that follows the Sonata's creases like a wave.",
		"badge": "AZURE",
		"color": Finish.PAINTS[SONATA_PAINT_AZURE]["color"],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_BURGUNDY,
		"kind": SONATA_PAINT_KIND,
		"price": 40 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Burgundy Pearl",
		"description": "A deep wine-red pearl, exclusive to the Sonata's paint shelf.",
		"badge": "WINE",
		"color": Finish.PAINTS[SONATA_PAINT_BURGUNDY]["color"],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_LILAC,
		"kind": SONATA_PAINT_KIND,
		"price": 55 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Coastal Lilac",
		"description": "A light lilac finish for a Sonata that refuses to blend into traffic.",
		"badge": "LILAC",
		"color": Finish.PAINTS[SONATA_PAINT_LILAC]["color"],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_ROSE,
		"kind": SONATA_PAINT_KIND,
		"price": 70 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Rose Alloy",
		"description": "Polished rose-metal paint that catches the light along the Sonata's roof.",
		"badge": "ROSE",
		"color": Finish.PAINTS[SONATA_PAINT_ROSE]["color"],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": SONATA_PAINT_CHAMPAGNE,
		"kind": SONATA_PAINT_KIND,
		"price": 120 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Champagne Pearl",
		"description": "The Sonata's premium pale-gold pearl: a quiet finish for a loud landing.",
		"badge": "PEARL",
		"color": Finish.PAINTS[SONATA_PAINT_CHAMPAGNE]["color"],
		"heading": SONATA_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_FACTORY,
		"kind": CRV_PAINT_KIND,
		"price": 0,
		"default": true,
		"title": "Factory Deep Blue",
		"description": "The Honda CR-V's original deep blue. Restores its unmodified factory coat.",
		"badge": "STOCK",
		"color": Finish.FACTORY_COATS[Profiles.CRV],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_FOREST,
		"kind": CRV_PAINT_KIND,
		"price": 25 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Evergreen",
		"description": "A dark blue-green finish for the CR-V's woodland detours.",
		"badge": "FOREST",
		"color": Finish.PAINTS[CRV_PAINT_FOREST]["color"],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_GLACIER,
		"kind": CRV_PAINT_KIND,
		"price": 25 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Glacier Silver",
		"description": "Cold blue-silver metallic paint, reserved for the CR-V's alpine run.",
		"badge": "GLACIER",
		"color": Finish.PAINTS[CRV_PAINT_GLACIER]["color"],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_CANYON,
		"kind": CRV_PAINT_KIND,
		"price": 40 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Canyon Red",
		"description": "A rugged red metallic finish that stands out against alpine snow.",
		"badge": "CANYON",
		"color": Finish.PAINTS[CRV_PAINT_CANYON]["color"],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_TUNDRA,
		"kind": CRV_PAINT_KIND,
		"price": 40 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Tundra Sand",
		"description": "A flatter expedition tan, made for the CR-V rather than the city sedan.",
		"badge": "TUNDRA",
		"color": Finish.PAINTS[CRV_PAINT_TUNDRA]["color"],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_AURORA,
		"kind": CRV_PAINT_KIND,
		"price": 55 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Aurora Violet",
		"description": "A cool violet metallic coat for the CR-V under the northern sky.",
		"badge": "AURORA",
		"color": Finish.PAINTS[CRV_PAINT_AURORA]["color"],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_STORM,
		"kind": CRV_PAINT_KIND,
		"price": 70 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Storm Graphite",
		"description": "A dark graphite clear coat with a restrained metallic edge on the CR-V.",
		"badge": "STORM",
		"color": Finish.PAINTS[CRV_PAINT_STORM]["color"],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": CRV_PAINT_ARCTIC,
		"kind": CRV_PAINT_KIND,
		"price": 120 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Arctic Ice",
		"description": "The CR-V's premium ice-mint metallic finish, bright even in winter shade.",
		"badge": "ARCTIC",
		"color": Finish.PAINTS[CRV_PAINT_ARCTIC]["color"],
		"heading": CRV_PAINT_HEADING,
	},
	{
		"id": RIM_FACTORY,
		"kind": RIM_KIND,
		"price": 0,
		"default": true,
		"title": "Factory Alloy",
		"description": (
			"Restore the original alloys on every car. Each model keeps "
			+ "its own factory wheel geometry and finish."
		),
		"badge": "ALLOY",
		"color": Finish.FACTORY_ALLOY,
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_GRAPHITE,
		"kind": RIM_KIND,
		"price": 30 * STORE_PRICE_MULTIPLIER,
		"title": "Graphite",
		"description": (
			"Dark grey spokes under a lighter lip. Hides the Copper Creek dust "
			+ "that the polished set advertises."
		),
		"badge": "GRAPH",
		"color": Finish.RIMS[RIM_GRAPHITE]["face"],
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_BRONZE,
		"kind": RIM_KIND,
		"price": 45 * STORE_PRICE_MULTIPLIER,
		"title": "Bronze Face",
		"description": (
			"Warm bronze spokes with a bright edge. Matches the factory paint "
			+ "closely enough to look intentional, which it is."
		),
		"badge": "BRONZE",
		"color": Finish.RIMS[RIM_BRONZE]["face"],
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_WHITE,
		"kind": RIM_KIND,
		"price": 45 * STORE_PRICE_MULTIPLIER,
		"title": "Trail White",
		"description": (
			"Painted rather than polished, so the spokes read flat and the "
			+ "rim edge is the only thing still catching the light."
		),
		"badge": "WHITE",
		"color": Finish.RIMS[RIM_WHITE]["face"],
		"heading": RIM_HEADING,
	},
	{
		"id": RIM_BLACK,
		"kind": RIM_KIND,
		"price": 60 * STORE_PRICE_MULTIPLIER,
		"requires_achievement": "cube_trials_clean",
		"title": "Gloss Black",
		"description": (
			"Lacquered black, kept for cars that finished without a scratch. "
			+ "It shows every mark, which is rather the point."
		),
		"badge": "GLOSS",
		"color": Finish.RIMS[RIM_BLACK]["face"],
		"heading": RIM_HEADING,
	},
]

# --------------------------------------------------------------------------
# The gallery
# --------------------------------------------------------------------------

const EXHIBIT_CUBE := "cube_car"
const EXHIBIT_WHEEL := "cube_wheel"
const EXHIBIT_SUSPENSION := "cube_suspension"
const EXHIBIT_SONATA := "cube_sonata"
const EXHIBIT_CRV := "cube_crv"
const EXHIBIT_PLUG := "cube_plug"
const EXHIBIT_CHECKPOINT := "cube_checkpoint"
const EXHIBIT_SIGN := "cube_sign"
const EXHIBIT_PINE := "cube_pine"
const EXHIBIT_FENCE := "cube_fence"
const EXHIBIT_GARAGE := "cube_garage"

## The cast of Copper Creek and two reference-car studies, on plinths.
##
## A trials course is driven past at speed and read from one fixed side, so
## almost nothing here is ever seen from more than one angle in play. Course
## exhibits are therefore the models the game itself builds — the imported car
## settled on its own suspension solver, the scenery straight out of
## `copper_creek.gd` — rather than nicer ones made for a display case. The two
## additional cars show their saved GLBs without changing the playable Cube.
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
			"Original Blender geometry: 44,266 triangles in 16 mesh nodes",
			"A 2.53 m wheelbase and about 23 cm of clearance at rest",
			"Hollow cabin, driver, mirrors, door seams and bounded rear glass",
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
			"The hidden wheel-well coilover revealed during jumps: a continuous gold "
			+ "spring around a telescoping chrome shaft and rigid damper housing. "
			+ "Shown with the same preload as the parked car."
		),
		"facts": [
			"One per wheel; the car carries four",
			"Wheels droop slightly in flight to reveal the spring",
			"Visible in flight; tucked away again as soon as a wheel lands",
			"Physics travel runs from 6.75 to 14.5 units, parked at 8.44",
			"Stiffness 160 against 980 of gravity, damped at 12",
			"Stepped at a fixed 120 Hz, so the ride is frame-rate independent",
		],
	},
	{
		"id": EXHIBIT_SONATA,
		"requires_achievement": Course.COPPER_COMPLETE,
		"title": "Hyundai Sonata",
		"heading": "Reference cars",
		"badge": "SEDAN",
		"color": Color("e7ebf0"),
		"description": "A white sedan study with swept lights, curved glazing and split-spoke wheels.",
		"facts": [
			"42,726 triangles in 16 mesh nodes",
			"2.84 m wheelbase; four wheel pivots",
			"Playable in solo and hot-seat trials",
		],
	},
	{
		"id": EXHIBIT_CRV,
		"requires_achievement": Course.SUNSET_COMPLETE,
		"title": "Honda CR-V",
		"heading": "Reference cars",
		"badge": "CR-V",
		"color": Color("07387f"),
		"description": "A blue crossover study with roof rails, black cladding and tall rear lamps.",
		"facts": [
			"43,696 triangles in 16 mesh nodes",
			"2.62 m wheelbase; four wheel pivots",
			"Playable in solo and hot-seat trials",
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
			"Imported ceramic ribs, blue bands, hex shell and hooked electrode",
			"Worth 1,000 points each",
			"A gold pickup ring and real 3D number surround the enlarged model",
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
			"Four flags on Sunset Ridge; seven on Copper Creek and Alpine Pass",
			"Imported checker cloth, wooden pole, gold finial and stone footing",
			"Gold until the checkpoint saves, then teal - and it says so too",
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
		"color": Color("537b38"),
		"description": (
			"The tree the hillside is planted with, standing behind the road's "
			+ "shoulder where the car cannot reach it."
		),
		"facts": [
			"Original Blender foliage: 6,064 triangles with a flared trunk",
			"Thirteen branch whorls with serrated fronds in three greens",
			"Fitted to trail height, then varied from 0.80x to 1.32x; shown at 1.06x",
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
		"title": "Copper Creek Body Shop",
		"heading": "The finish",
		"badge": "HOME",
		"color": Color("a14535"),
		"description": (
			"The end of the commute, shown with every plug delivered. Brake "
			+ "inside it and the drive is over."
		),
		"facts": [
			"Imported open service bay, lift, office, signs and furnished yard",
			"Five bulbs over the door, one per plug delivered",
			"Its sign is the finish rule, and it changes when all five arrive",
		],
		"requires_achievement": "cube_trials_home",
	},
]
