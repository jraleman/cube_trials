extends RefCounted

## Copper Creek's original geometry is shared by drawing, suspension and tests.

const TITLE := "COPPER CREEK"
const START_X := 180.0
const FINISH_X := 5150.0
const FINISH_WIDTH := 240.0
const END_X := 5750.0
const FALL_Y := 1050.0
const PLUG_X: Array[float] = [690.0, 1610.0, 2530.0, 3820.0, 4750.0]
const CHECKPOINT_X: Array[float] = [START_X, 2070.0, 3430.0]
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
		Vector2(6000, 610),
	],
]
const SIGNS := [
	{"x": 360.0, "title": "COPPER CREEK", "detail": "5 PLUGS. ONE LITTLE CUBE."},
	{"x": 1130.0, "title": "WASHBOARD", "detail": "EASY ON THE THROTTLE"},
	{"x": 2240.0, "title": "QUARRY JUMP", "detail": "BUILD SPEED / LEVEL YOUR LANDING"},
	{"x": 3570.0, "title": "THE HIGH ROAD", "detail": "KEEP THE ROOF OFF THE ROCKS"},
	{"x": 4900.0, "title": "HOME STRETCH", "detail": "BRAKE IN THE GARAGE"},
]


## INF represents open air, never an invisible floor across the quarry.
static func ground_height(x: float) -> float:
	for road: Array in ROADS:
		for index in range(road.size() - 1):
			var a: Vector2 = road[index]
			var b: Vector2 = road[index + 1]
			if x >= a.x and x <= b.x:
				return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return INF


## Bumper contacts use the same sloped surface as the tires.
static func ground_normal(x: float) -> Vector2:
	for road: Array in ROADS:
		for index in range(road.size() - 1):
			var a: Vector2 = road[index]
			var b: Vector2 = road[index + 1]
			if x >= a.x and x <= b.x:
				var edge := b - a
				return Vector2(edge.y, -edge.x).normalized()
	return Vector2.ZERO


## Plugs sit within the cabin's reach even when a wheel is riding a crest.
static func plug_position(index: int) -> Vector2:
	var x := PLUG_X[index]
	return Vector2(x, ground_height(x) - 106.0)


## Checkpoints are level pull-offs, with room for the suspension to settle.
static func spawn_position(checkpoint: int) -> Vector2:
	var x := CHECKPOINT_X[checkpoint]
	return Vector2(x, ground_height(x) - 77.0)


## Cast against the tire-radius-offset surface, allowing compressed springs.
static func wheel_contact(
	anchor: Vector2, down: Vector2, reach: float, radius: float
) -> Dictionary:
	var start := anchor - down * 45.0
	var end := anchor + down * reach
	var nearest := INF
	var result := {}
	for road: Array in ROADS:
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
