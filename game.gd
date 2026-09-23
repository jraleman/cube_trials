extends RefCounted

## Cube Trials registers itself through game-owned data, not framework conditionals.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")
const Profiles = preload("res://games/cube_trials/vehicle_profiles.gd")
const State = preload("res://games/cube_trials/trial_state.gd")
const Course = preload("res://games/cube_trials/course.gd")


## The shell supplies pause, settings, achievements, results and score sharing.
static func manifest() -> GameManifest:
	var game := GameManifest.new()
	game.id = Options.GAME_ID
	game.title = "Cube Trials"
	game.tagline = "Three everyday cars. Three unreasonable commutes."
	game.menu_order = 8
	game.gameplay_scene_path = "res://games/cube_trials/gameplay.tscn"
	game.intro_scene_path = "res://games/cube_trials/intro.tscn"
	game.control_style = GameManifest.CONTROL_STYLE_CUSTOM_KEYS
	game.supports_multiplayer = true
	game.max_local_players = 3
	game.local_multiplayer_turns = true
	game.characters = Profiles.CHARACTERS
	game.levels = Course.LEVELS
	game.character_preview_scene_path = "res://games/cube_trials/character_preview.tscn"
	game.supports_cpu_opponent = false
	game.uses_shell_round_rules = false
	game.tunables = Options.TUNABLES
	game.control_bindings = Options.CONTROL_BINDINGS
	game.tutorial_poster_path = "res://games/cube_trials/assets/tutorial_poster.png"
	game.share_art_scene_path = "res://games/cube_trials/share_art.tscn"
	# Each car keeps its own paint purchases; wheel finishes are shared.
	game.store_currency = Options.STORE_CURRENCY
	game.store_slots = Options.STORE_SLOTS
	game.store_items = Options.STORE_ITEMS
	game.store_preview_scene_path = "res://games/cube_trials/store_preview.tscn"
	# The playable fleet and the trail's original models, at any angle.
	game.gallery_exhibits = Options.GALLERY_EXHIBITS
	game.gallery_stage_scene_path = "res://games/cube_trials/gallery_stage.tscn"
	game.stats_url = "https://deskcansaw.com"
	game.copy = {
		"single_player_description": (
			"Start with the Nissan Cube on Copper Creek. Deliver five spark plugs "
			+ "to unlock more cars and two new handcrafted trails."
		),
		"multiplayer_description": "Two or three players take full turns on the same trail.",
		"solo_confirm_title": "Choose your level and car",
		"solo_confirm_description": (
			"Clear Level 1 for Level 2 and the Sonata; clear Level 2 for Level 3 and the CR-V. "
			+ "All cars share driving tuning. Factory or garage paint is used for solo runs."
		),
		"versus_confirm_title": "Choose a level and each player's car",
		"versus_confirm_description": (
			"Pick one unlocked level and a car for each player. Duplicate choices are welcome. "
			+ "P1 is blue, P2 red and P3 green. Each player gets a full run before passing the controls."
			+ " A delivery unlocks the next level and car after the final turn."
		),
		"player_one_control_description": (
			"Throttle and reverse drive the wheels; tilt balances the cabin. "
			+ "Jump high, tilt for style, switch hazards on in mid-air for a bonus, "
			+ "land to bank points, and brake inside the garage."
		),
		"player_two_control_description": "Take the second turn with the same keys. Pass one controller, or use Controller 2.",
		"player_three_control_description": "Take the third turn with the same keys. Pass one controller, or use Controller 3.",
		"instructions_solo_summary": "Deliver all five spark plugs in your chosen car.",
		"instructions_versus_summary": (
			"Hot seat: P1, then P2, then P3 if selected. Every player starts with five lives, "
			+ "fresh cargo and their own checkpoints. Finish or run out of lives, then pass the controls."
		),
		"instructions_headline": "THE VERY UNREASONABLE COMMUTE",
		"instructions_rules": (
			"Three handcrafted trails: Copper Creek's washboard and six ravines, "
			+ "Sunset Ridge's sandy beaches and four coastal crossings, then Alpine Pass's "
			+ "snow-covered climb and seven summit gaps.\n"
			+ "Start in the Nissan Cube on Level 1. Complete Copper Creek to unlock "
			+ "Level 2 and the Hyundai Sonata. Complete Sunset Ridge to unlock "
			+ "Level 3 and the Honda CR-V. Unlocks are saved, and unlocked cars can replay any open level.\n"
			+ "Collect all FIVE numbered spark plugs, then slow down inside the garage. "
			+ "Keep your roof off the rocks. Carry speed up the quarry ramp, hold the "
			+ "nose up at takeoff, then level the car for landing. "
			+ "The wider gaps need a deliberate jump: build speed, jump at the gold stripes, "
			+ "then tilt to land on both wheels. Release before jumping again; no double jumps.\n"
			+ "In the air, hold nose-up for backflips or nose-down for frontflips. "
			+ "Release tilt to slow the spin, or counter-tilt to level out. "
			+ "Every full turn adds %d points. " % State.FLIP_POINTS
			+ "Flights of at least %.2f seconds also earn points for airtime, travel speed " % State.MIN_SCORING_AIR_TIME
			+ "and tilt angle. More speed and steeper aerial angles earn more; "
			+ "rocking back and forth is not a full flip. "
			+ "All aerial points wait for a stable two-wheel landing.\n"
			+ "Toggle hazards with F, gamepad X or the triangle button. Switch them ON while "
			+ "airborne for %.2fx that jump's points. " % State.HAZARD_MULTIPLIER
			+ "The bonus never stacks and does not carry into the next jump, even if you leave "
			+ "the lights on. Crashes and recovery discard unlanded points and their bonus, "
			+ "but keep previously banked points.\n"
			+ "Checkpoint flags save your place only after you collect the earlier plugs. "
			+ "Start with FIVE lives. A roof strike or fall costs one life and recovers the car; "
			+ "the last life ends the run. Recover also works when stuck without costing a life. "
			+ "Pickups are kept. Every recovery adds FIVE seconds. Hard landings only damage "
			+ "the bodywork, not your lives or handling.\n"
			+ "The heart shows lives, the star shows points, and the plug shows your cargo. "
			+ "The clock starts when you drive, tilt or jump and stops while paused. There is no time limit. "
			+ "Gold: %.0f seconds or less including penalties; Silver: %.0f; Bronze: any finish.\n" % [
				State.GOLD_SECONDS, State.SILVER_SECONDS,
			]
			+ "Each plug scores 1,000 points. Finishing adds up to %d more, minus %.0f " % [
				State.FINISH_BONUS, State.POINTS_PER_SECOND,
			]
			+ "per adjusted second (rounded up), never below zero. Banked aerial points are kept even on a failed run. "
			+ "Air control and engine sound can be changed live in Settings.\n"
			+ "Hot seat uses the same controls and driving tuning for everyone. A connected "
			+ "controller is assigned to each seat in order; an unassigned seat shares Controller 1. "
			+ "Fastest adjusted finishing time wins, with ties at the displayed hundredth. "
			+ "Unfinished runs rank below every finisher, by plugs collected. "
			+ "Standings and one shared Sparks payout appear after the final turn."
		),
		"instructions_demo_prompt": "SMALL CAR. BIG DETOUR.",
		"store_intro": (
			"Completed trials pay Sparks for your score; hot seat pays once after all turns. "
			+ "Each car has its own paint unlocks and equipped color for solo runs. "
			+ "Hot-seat cars keep their player colors. Wheel finishes are shared across all cars. "
			+ "None of it makes the car faster."
		),
		"gallery_intro": (
			"The trails' models and playable cars, up close. "
			+ "Finish Level 1 to reveal the Sonata and Level 2 to reveal the CR-V."
		),
		"instructions_player_one_controls": (
			"Use the rebindable controls below or the on-screen driving buttons. "
			+ "By default, Space jumps, A / D tilt and flip in the air, F toggles hazards, and Shift brakes. "
			+ "Touch supports multiple fingers. On a gamepad: right trigger accelerates, "
			+ "left trigger reverses, left stick tilts, A jumps, B brakes, X toggles hazards and Y recovers. "
			+ "Escape / gamepad Start pauses; touch has a Pause button. "
			+ "The camera button, Change camera binding or right-stick click cycles "
			+ "Side, Chase and Cockpit views. Views do not change the driving rules: "
			+ "tilt balances the car, not steering."
		),
	}
	game.achievements = {
		Course.COPPER_COMPLETE: {
			"title": "Home in One Piece", "badge": "HOME",
			"description": "Complete Copper Creek. Unlock Level 2 and the Hyundai Sonata.",
		},
		Course.SUNSET_COMPLETE: {
			"title": "Sunset Delivery", "badge": "RIDGE",
			"description": "Complete Sunset Ridge. Unlock Level 3 and the Honda CR-V.",
		},
		Course.ALPINE_COMPLETE: {
			"title": "Top of the Commute", "badge": "SUMMIT",
			"description": "Deliver all five spark plugs to the Alpine Pass garage.",
		},
		"cube_trials_clean": {
			"title": "Not a Scratch", "badge": "CLEAN",
			"description": "Finish a level without a crash or manual recovery.",
		},
		"cube_trials_gold": {
			"title": "Express Delivery", "badge": "GOLD",
			"description": "Finish in %.0f seconds or less, including recovery penalties." % State.GOLD_SECONDS,
		},
	}
	var theme := GameTheme.new()
	theme.logo_texture_path = "res://games/cube_trials/assets/game-icon.png"
	theme.accent = Art.COPPER
	theme.light = Art.CREAM
	theme.plaque_color = Color("415b51")
	theme.background_top = Color("293d37")
	theme.background_bottom = Color("142725")
	theme.style_share_card = true
	game.theme = theme
	game.credits = [
		{"heading": "Cube Trials", "lines": [
			"Game design and development: DeskCanSaw Games",
			"Copper Creek, Sunset Ridge and Alpine Pass: original side-view 3D trials.",
		]},
		{"heading": "Art and sound", "lines": [
			"Original unbranded Nissan Cube, Hyundai Sonata and Honda CR-V models.",
			"Extruded terrain, roadside scenery and five-stage car damage.",
			"Real-model studio portraits, warm daylight and Compatibility shadows.",
			"Original synthesized engine and event sounds.",
			"Shared DeskCanSaw framework, menus and accessibility.",
		]},
		{"heading": "Acknowledgements", "lines": [
			"Inspired by classic elastic-suspension trials games, including Elasto Mania.",
			"No Elasto Mania levels, code, art or sound are used.",
			"Vehicle names are trademarks of their respective owners.",
			"Unofficial studies; not affiliated with or endorsed by any manufacturer.",
		]},
	]
	return game
