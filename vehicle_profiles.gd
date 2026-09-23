extends RefCounted

## Authored geometry only. Engine, grip, springs, jump and assists stay shared.

const Tuning = preload("res://games/cube_trials/vehicle_tuning.gd")
const Course = preload("res://games/cube_trials/course.gd")
const CUBE := "cube_car"
const SONATA := "cube_sonata"
const CRV := "cube_crv"
const CHARACTERS: Array[Dictionary] = [
	{"id": CUBE, "title": "Nissan Cube", "description": "The boxy original. Factory bronze."},
	{
		"id": SONATA, "title": "Hyundai Sonata",
		"description": "Long and low: hop over sharp crests. Factory pearl white.",
		"requires_achievement": Course.COPPER_COMPLETE,
		"locked_description": "Complete Level 1 - Copper Creek.",
	},
	{
		"id": CRV, "title": "Honda CR-V", "description": "A compact SUV. Factory deep blue.",
		"requires_achievement": Course.SUNSET_COMPLETE,
		"locked_description": "Complete Level 2 - Sunset Ridge.",
	},
]
const CUBE_PARTS: Array[String] = [
	"BrownBodywork", "CabinAndDriver", "ChromeHandlesGrilleAndBadges",
	"HeadlightsAndIndicators", "LampGlazing", "RearBrakeLights",
	"RubberTrimAndUnderbody", "WraparoundGlazing",
]
const MODERN_PARTS: Array[String] = [
	"BodyPaint", "CabinAndSeats", "Metalwork", "HeadlightsAndIndicators",
	"LampGlazing", "RearBrakeLights", "RubberTrimAndUnderbody", "Glazing",
]
const DEFINITIONS := {
	CUBE: {
		"file": "nissan_cube", "root": "NissanCube", "title": "Nissan Cube",
		"wheelbase": 2.53, "tire_radius": 0.324, "axle_height": 0.323,
		"half_track": 0.744, "half_width": 0.85, "eye": Vector3(0.12, 1.35, -0.377),
	},
	SONATA: {
		"file": "hyundai_sonata", "root": "HyundaiSonata", "title": "Hyundai Sonata",
		"wheelbase": 2.84, "tire_radius": 0.338, "axle_height": 0.338,
		"half_track": 0.795, "half_width": 0.934, "eye": Vector3(0.12, 1.22, -0.39),
		"roof": [Vector2(-1.10, 1.335), Vector2(-0.40, 1.465), Vector2(0.20, 1.44)],
		"body": [Vector2(-2.23, 0.225), Vector2(-0.15, 0.17), Vector2(2.11, 0.18)],
	},
	CRV: {
		"file": "honda_crv", "root": "HondaCRV", "title": "Honda CR-V",
		"wheelbase": 2.62, "tire_radius": 0.355, "axle_height": 0.355,
		"half_track": 0.780, "half_width": 0.917, "eye": Vector3(0.12, 1.40, -0.39),
		"roof": [Vector2(-1.46, 1.63), Vector2(-0.55, 1.645), Vector2(0.13, 1.615)],
		"body": [Vector2(-2.15, 0.305), Vector2(-0.15, 0.25), Vector2(2.02, 0.28)],
	},
}

var id: String
var title: String
var file: String
var root_node: String
var body_part: String
var glass_part: String
var cabin_part: String
var headlight_material: String
var parts: Array[String] = []
var wheelbase: float
var tire_radius: float
var axle_height: float
var half_track: float
var half_width: float
var driver_eye: Vector3
var wheel_radius: float
var ride_height: float
var body_origin_height: float
var axles: Array[Vector2] = []
var roof: Array[Vector2] = []
var body_contacts: Array[Vector2] = []


func _init(vehicle_id := CUBE) -> void:
	assert(DEFINITIONS.has(vehicle_id), "Unknown playable car: " + vehicle_id)
	id = vehicle_id
	var data: Dictionary = DEFINITIONS[id]
	title = data["title"]
	file = data["file"]
	root_node = data["root"]
	wheelbase = data["wheelbase"]
	tire_radius = data["tire_radius"]
	axle_height = data["axle_height"]
	half_track = data["half_track"]
	half_width = data["half_width"]
	driver_eye = data["eye"]
	body_part = "BrownBodywork" if id == CUBE else "BodyPaint"
	glass_part = "WraparoundGlazing" if id == CUBE else "Glazing"
	cabin_part = "CabinAndDriver" if id == CUBE else "CabinAndSeats"
	headlight_material = "Cube Bulb" if id == CUBE else "Cube Headlight"
	parts.assign(CUBE_PARTS if id == CUBE else MODERN_PARTS)
	wheel_radius = tire_radius * Tuning.UNITS_PER_METER
	ride_height = Tuning.AXLE_MOUNT_HEIGHT + Tuning.STATIC_LENGTH + wheel_radius
	body_origin_height = (
		(Tuning.AXLE_MOUNT_HEIGHT + Tuning.STATIC_LENGTH) / Tuning.UNITS_PER_METER + axle_height
	)
	if id == CUBE:
		axles.assign(Tuning.AXLES)
		roof.assign(Tuning.ROOF)
		body_contacts.assign(Tuning.BODY_CONTACTS)
		return
	for direction: float in [-1.0, 1.0]:
		axles.append(Vector2(
			direction * wheelbase * Tuning.UNITS_PER_METER * 0.5, Tuning.AXLE_MOUNT_HEIGHT
		))
	for point: Vector2 in data["roof"]:
		roof.append(Vector2(point.x, body_origin_height - point.y) * Tuning.UNITS_PER_METER)
	for point: Vector2 in data["body"]:
		body_contacts.append(Vector2(point.x, body_origin_height - point.y) * Tuning.UNITS_PER_METER)
