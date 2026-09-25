extends RefCounted

## Each run owns one route, shared by drawing, suspension, cameras and recovery.

const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const Trail = preload("res://games/cube_trials/trail_layout.gd")
const COPPER := "copper_creek"
const SUNSET := "sunset_ridge"
const ALPINE := "alpine_pass"
## The player's own trail, built in the Trail Builder.
const CUSTOM := "my_trail"
const COPPER_COMPLETE := "cube_trials_home"
const SUNSET_COMPLETE := "cube_trials_sunset"
const ALPINE_COMPLETE := "cube_trials_alpine"

enum Scenery { MOUNTAIN, BEACH, SNOW }

## Stills of each route for the shared setup screen's level row, captured from
## the real course by `tools/capture_art.gd`.
const LEVEL_ART := "res://games/cube_trials/assets/levels/"

const LEVELS: Array[Dictionary] = [
	{
		"id": COPPER, "title": "Level 1 - Copper Creek",
		"icon": LEVEL_ART + "copper_creek.png",
		"description": "The original mountain commute. Deliver five plugs to unlock Sunset Ridge and the Hyundai Sonata.",
		"completion_achievement": COPPER_COMPLETE,
		"unlock_text": "Level 2 - Sunset Ridge and Hyundai Sonata unlocked!",
	},
	{
		"id": SUNSET, "title": "Level 2 - Sunset Ridge",
		"icon": LEVEL_ART + "sunset_ridge.png",
		"description": "A sandy beach drive past palms, turquoise surf and four coastal jumps. Finish to unlock Alpine Pass, the Honda CR-V and the Trail Builder.",
		"requires_achievement": COPPER_COMPLETE,
		"locked_description": "Complete Level 1 - Copper Creek.",
		"completion_achievement": SUNSET_COMPLETE,
		"unlock_text": "Level 3 - Alpine Pass, Honda CR-V and Trail Builder unlocked!",
	},
	{
		"id": ALPINE, "title": "Level 3 - Alpine Pass",
		"icon": LEVEL_ART + "alpine_pass.png",
		"description": "Climb through snowy peaks and frosted pines, cross seven summit gaps, then bring all five plugs home.",
		"requires_achievement": SUNSET_COMPLETE,
		"locked_description": "Complete Level 2 - Sunset Ridge.",
		"completion_achievement": ALPINE_COMPLETE,
		"unlock_text": "All three levels complete!",
	},
]
## The setup screen's last level choice. It opens with the last car, so every
## car can drive it, and it is not in LEVELS: a player's own trail has no
## fixed route and earns no completion reward.
const BUILDER := {
	"id": CUSTOM, "title": "Trail Builder",
	"icon": LEVEL_ART + "my_trail.png",
	"description": "Build your own trail from blocks, then drive it. Just for fun: no Sparks or awards.",
	"requires_achievement": SUNSET_COMPLETE,
	"locked_description": "Free all three cars: complete Level 2 - Sunset Ridge.",
}
const TITLE := "COPPER CREEK"
const START_X := 180.0
const FINISH_X := 16400.0
const FINISH_WIDTH := 240.0
const END_X := 17000.0
const FALL_Y := 1050.0
const PLUG_X: Array[float] = [690.0, 1610.0, 2530.0, 6660.0, 16090.0]
const CHECKPOINT_X: Array[float] = [
	START_X, 2070.0, 3430.0, 6120.0, 7930.0, 9900.0, 12420.0, 13940.0,
]
const ROADS := [
	[
		Vector2(-600, 650), Vector2(550, 650), Vector2(820, 570),
		Vector2(1060, 650), Vector2(1250, 650), Vector2(1400, 600),
		Vector2(1520, 650), Vector2(1660, 585), Vector2(1810, 650),
		Vector2(2160, 650), Vector2(2350, 610), Vector2(2590, 490),
		Vector2(2760, 410),
	],
	[
		Vector2(2950, 610), Vector2(3270, 620), Vector2(3560, 620),
		Vector2(3790, 530), Vector2(4030, 465), Vector2(4230, 540),
		Vector2(4480, 610), Vector2(4640, 560), Vector2(4810, 610),
		Vector2(4970, 610), Vector2(5160, 560), Vector2(5330, 610),
		Vector2(5510, 610),
	],
	[
		Vector2(5860, 590), Vector2(6200, 590), Vector2(6410, 520),
		Vector2(6570, 435), Vector2(6740, 435), Vector2(6920, 545),
		Vector2(7080, 475), Vector2(7230, 570), Vector2(7470, 570),
	],
	[
		Vector2(7820, 550), Vector2(8270, 550),
	],
	[
		Vector2(8640, 570), Vector2(8890, 570), Vector2(9060, 460),
		Vector2(9260, 610), Vector2(9450, 530), Vector2(9640, 610),
		Vector2(10100, 610), Vector2(10600, 400), Vector2(11100, 170),
		Vector2(11520, -40), Vector2(11820, -40),
	],
	[
		Vector2(12260, -40), Vector2(12560, -40), Vector2(13020, -250),
		Vector2(13340, -250),
	],
	[
		Vector2(13800, -250), Vector2(14100, -250), Vector2(14600, -40),
		Vector2(15100, 180), Vector2(15580, 410), Vector2(15980, 610),
		Vector2(17250, 610),
	],
]
const SIGNS := [
	{"x": 360.0, "title": "COPPER CREEK", "detail": "JUMP / FLIP / LAND FOR POINTS"},
	{"x": 1130.0, "title": "WASHBOARD", "detail": "EASY ON THE THROTTLE"},
	{"x": 2240.0, "title": "QUARRY JUMP", "detail": "BUILD SPEED / LEVEL YOUR LANDING"},
	{"x": 3570.0, "title": "THE HIGH ROAD", "detail": "KEEP THE ROOF OFF THE ROCKS"},
	{"x": 4880.0, "title": "BROKEN CAUSEWAY", "detail": "PRESS JUMP BEFORE THE EDGE"},
	{"x": 6280.0, "title": "SAWTOOTH RIDGE", "detail": "EASE OFF / BALANCE THE LANDING"},
	{"x": 7210.0, "title": "TWIN RAVINES", "detail": "JUMP / LAND / RELEASE / JUMP"},
	{"x": 8110.0, "title": "ONE MORE LEAP", "detail": "BUILD SPEED / JUMP THE STRIPES"},
	{"x": 8790.0, "title": "RIDGE RUN", "detail": "SAVE A LITTLE FOR THE CLIMB"},
	{"x": 9970.0, "title": "SKYLINE ASCENT", "detail": "THE COMMUTE JUST GOT TALLER"},
	{"x": 11200.0, "title": "FLIP SCHOOL", "detail": "FLIP +500 / HAZARDS x1.15"},
	{"x": 11630.0, "title": "SKYLINE GAP", "detail": "BUILD SPEED / JUMP THE STRIPES"},
	{"x": 12730.0, "title": "SUMMIT RUN", "detail": "CLIMB ABOVE THE CLOUDS"},
	{"x": 13170.0, "title": "HIGH WIRE", "detail": "JUMP / FIND BOTH WHEELS"},
	{"x": 14450.0, "title": "LONG WAY DOWN", "detail": "LEVEL OUT / WATCH YOUR SPEED"},
	{"x": 16200.0, "title": "HOME STRETCH", "detail": "BRAKE IN THE GARAGE"},
]
const ROUTES := {
	COPPER: {
		"title": "Copper Creek", "finish_x": FINISH_X, "end_x": END_X,
		"plug_x": PLUG_X, "checkpoint_x": CHECKPOINT_X, "roads": ROADS, "signs": SIGNS,
	},
	SUNSET: {
		"title": "Sunset Ridge", "finish_x": 14200.0, "end_x": 14800.0,
		"scenery": Scenery.BEACH, "hill_color": Color("ead3a1"),
		"plug_x": [700.0, 3990.0, 6910.0, 9830.0, 13760.0],
		"checkpoint_x": [START_X, 4100.0, 7040.0, 9960.0, 12800.0],
		"roads": [
			[
				Vector2(-600, 650), Vector2(850, 650), Vector2(1450, 480),
				Vector2(2000, 480), Vector2(2500, 580), Vector2(3040, 580),
			],
			[
				Vector2(3360, 560), Vector2(4220, 560), Vector2(4800, 360),
				Vector2(5160, 360), Vector2(5580, 480), Vector2(5920, 480),
			],
			[
				Vector2(6280, 480), Vector2(7160, 480), Vector2(7760, 240),
				Vector2(8120, 240), Vector2(8520, 400), Vector2(8800, 400),
			],
			[
				Vector2(9220, 400), Vector2(10080, 400), Vector2(10600, 200),
				Vector2(10960, 200), Vector2(11480, 380), Vector2(11820, 380),
			],
			[
				Vector2(12260, 380), Vector2(13000, 380), Vector2(13520, 550),
				Vector2(15050, 550),
			],
		],
		"signs": [
			{"x": 360.0, "title": "SUNSET RIDGE", "detail": "LEVEL 2 / THE COAST ROAD"},
			{"x": 2200.0, "title": "SANDSPIT JUMP", "detail": "BUILD SPEED / JUMP THE STRIPES"},
			{"x": 4400.0, "title": "ROLLING DUNES", "detail": "BALANCE OVER THE CRESTS"},
			{"x": 5540.0, "title": "TIDAL CHANNEL", "detail": "RELEASE / BUILD SPEED / JUMP"},
			{"x": 7360.0, "title": "PALM OVERLOOK", "detail": "FIVE PLUGS / ONE DELIVERY"},
			{"x": 8490.0, "title": "WIDE CROSSING", "detail": "JUMP / LEVEL YOUR LANDING"},
			{"x": 11040.0, "title": "LAST LIGHT", "detail": "ONE MORE GAP TO CLEAR"},
			{"x": 13990.0, "title": "BEACH GARAGE", "detail": "BRAKE TO UNLOCK LEVEL 3"},
		],
	},
	ALPINE: {
		"title": "Alpine Pass", "finish_x": 20400.0, "end_x": 21000.0,
		"scenery": Scenery.SNOW, "hill_color": Color("e5eff5"),
		"plug_x": [680.0, 3710.0, 8830.0, 13960.0, 20120.0],
		"checkpoint_x": [START_X, 3740.0, 6300.0, 8880.0, 11420.0, 13980.0, 16500.0, 18860.0],
		"roads": [
			[
				Vector2(-600, 650), Vector2(850, 650), Vector2(1500, 350),
				Vector2(2100, 80), Vector2(2620, 80),
			],
			[
				Vector2(3020, 80), Vector2(3860, 80), Vector2(4560, -210),
				Vector2(5100, -210),
			],
			[
				Vector2(5560, -210), Vector2(6400, -210), Vector2(7100, -530),
				Vector2(7640, -530),
			],
			[
				Vector2(8140, -530), Vector2(8980, -530), Vector2(9660, -670),
				Vector2(10200, -670),
			],
			[
				Vector2(10680, -670), Vector2(11520, -670), Vector2(12220, -350),
				Vector2(12760, -350),
			],
			[
				Vector2(13260, -350), Vector2(14100, -350), Vector2(14700, -80),
				Vector2(15240, -80),
			],
			[
				Vector2(15760, -80), Vector2(16600, -80), Vector2(17200, 210),
				Vector2(17740, 210),
			],
			[
				Vector2(18180, 210), Vector2(19020, 210), Vector2(19640, 550),
				Vector2(21250, 550),
			],
		],
		"signs": [
			{"x": 360.0, "title": "ALPINE PASS", "detail": "LEVEL 3 / THROUGH THE SNOW"},
			{"x": 1640.0, "title": "FROSTED PINES", "detail": "CARRY SPEED UP THE CLIMB"},
			{"x": 2380.0, "title": "FIRST CROSSING", "detail": "JUMP THE GOLD STRIPES"},
			{"x": 4790.0, "title": "CLOUD BRIDGE", "detail": "BUILD SPEED / LAND LEVEL"},
			{"x": 7320.0, "title": "HIGH ALTITUDE", "detail": "WIDE GAP / DELIBERATE JUMP"},
			{"x": 9850.0, "title": "THE SUMMIT", "detail": "1320 UNITS ABOVE THE START"},
			{"x": 12400.0, "title": "SWITCHBACK RUN", "detail": "LEVEL OUT BEFORE THE EDGE"},
			{"x": 14900.0, "title": "LONG LEAP", "detail": "BUILD SPEED / JUMP / RELEASE"},
			{"x": 17400.0, "title": "FINAL RAVINE", "detail": "KEEP BOTH WHEELS BELOW YOU"},
			{"x": 20200.0, "title": "ALPINE GARAGE", "detail": "FIVE PLUGS / BRAKE TO FINISH"},
		],
	},
}

var id: String
## 1-3 for the handcrafted levels, 0 for a player's own trail.
var number: int
var title: String
## Identifies the scenery to build: the level id, or the id plus the shape of
## a built trail, so an edited trail gets fresh scenery and an unchanged one
## is reused.
var layout_key: String
var finish_x: float
var end_x: float
var finish_width := FINISH_WIDTH
var fall_y := FALL_Y
var plug_x: Array[float] = []
var checkpoint_x: Array[float] = []
var roads: Array = []
var signs: Array = []
var scenery := Scenery.MOUNTAIN
var hill_color := Color("657b55")


## [param route] is a built trail's `Trail.to_route()`. A CUSTOM course
## without one drives the trail the builder last saved.
func _init(level_id := COPPER, route: Dictionary = {}) -> void:
	assert(level_id == CUSTOM or ROUTES.has(level_id), "Unknown trial level: " + level_id)
	id = level_id
	for index in LEVELS.size():
		if LEVELS[index]["id"] == id:
			number = index + 1
	var data := route
	if data.is_empty():
		data = ROUTES[id] if ROUTES.has(id) else _saved_trail()
	layout_key = "%s:%d" % [id, data.hash()] if id == CUSTOM else id
	title = data["title"]
	finish_x = data["finish_x"]
	end_x = data["end_x"]
	plug_x.assign(data["plug_x"])
	checkpoint_x.assign(data["checkpoint_x"])
	roads = data["roads"]
	signs = data["signs"]
	scenery = data.get("scenery", scenery)
	hill_color = data.get("hill_color", hill_color)


## The handcrafted levels, then the Trail Builder, for the setup screen.
static func setup_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = LEVELS.duplicate(true)
	levels.append(BUILDER.duplicate(true))
	return levels


static func _saved_trail() -> Dictionary:
	var trail := Trail.new()
	trail.load_file()
	return trail.to_route()


func is_custom() -> bool:
	return id == CUSTOM


## The achievement a first delivery earns, or "" on a player's own trail.
func completion_achievement() -> String:
	return "" if number == 0 else str(LEVELS[number - 1]["completion_achievement"])


## "Level 2 - Sunset Ridge", or just the title of a player's own trail.
func label() -> String:
	return title if number == 0 else "Level %d - %s" % [number, title]


## The HUD's shorter form: "L2 / Sunset Ridge".
func short_label() -> String:
	return title if number == 0 else "L%d / %s" % [number, title]


func gap_intervals() -> Array[Vector2]:
	var gaps: Array[Vector2] = []
	for index in range(roads.size() - 1):
		gaps.append(Vector2(roads[index][-1].x, roads[index + 1][0].x))
	return gaps


## INF represents open air, never an invisible floor across the quarry.
func ground_height(x: float) -> float:
	for road: Array in roads:
		for index in range(road.size() - 1):
			var a: Vector2 = road[index]
			var b: Vector2 = road[index + 1]
			if x >= a.x and x <= b.x:
				return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return INF


## Bumper contacts use the same sloped surface as the tires.
func ground_normal(x: float) -> Vector2:
	for road: Array in roads:
		for index in range(road.size() - 1):
			var a: Vector2 = road[index]
			var b: Vector2 = road[index + 1]
			if x >= a.x and x <= b.x:
				var edge := b - a
				return Vector2(edge.y, -edge.x).normalized()
	return Vector2.ZERO


## Plugs sit within the cabin's reach even when a wheel is riding a crest.
func plug_position(index: int) -> Vector2:
	var x := plug_x[index]
	return Vector2(x, ground_height(x) - Tuning.RIDE_HEIGHT - 36.0)


## Checkpoints are level pull-offs, with room for the suspension to settle.
func spawn_position(checkpoint: int) -> Vector2:
	var x := checkpoint_x[checkpoint]
	return Vector2(x, ground_height(x) - Tuning.RIDE_HEIGHT)


## Cast against the tire-radius-offset surface, allowing compressed springs.
func wheel_contact(
	anchor: Vector2, down: Vector2, reach: float, radius: float
) -> Dictionary:
	var start := anchor - down * 45.0
	var end := anchor + down * reach
	var nearest := INF
	var result := {}
	for road: Array in roads:
		for index in range(road.size() - 1):
			var a: Vector2 = road[index]
			var b: Vector2 = road[index + 1]
			var edge := b - a
			var normal := Vector2(edge.y, -edge.x).normalized()
			if down.dot(normal) > -0.15:
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(
				start, end, a + normal * radius, b + normal * radius
			)
			if hit == null:
				continue
			var point: Vector2 = hit
			var distance := (point - anchor).dot(down)
			if distance < nearest:
				nearest = distance
				result = {"length": distance, "normal": normal, "point": point}
	return result
