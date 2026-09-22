extends RefCounted

## Cube Trials registers itself through game-owned data, not framework conditionals.

const Options = preload("res://games/cube_trials/cube_trials_options.gd")
const Art = preload("res://games/cube_trials/cube_art.gd")


## The shell supplies pause, settings, achievements, results and score sharing.
static func manifest() -> GameManifest:
	var game := GameManifest.new()
	game.id = Options.GAME_ID
	game.title = "Cube Trials"
	game.tagline = "A brown Nissan Cube. A very unreasonable commute."
	game.menu_order = 8
	game.gameplay_scene_path = "res://games/cube_trials/gameplay.tscn"
	game.intro_scene_path = "res://games/cube_trials/intro.tscn"
	game.control_style = GameManifest.CONTROL_STYLE_CUSTOM_KEYS
	game.supports_multiplayer = false
	game.supports_cpu_opponent = false
	game.uses_shell_round_rules = false
	game.tunables = Options.TUNABLES
	game.control_bindings = Options.CONTROL_BINDINGS
	game.tutorial_poster_path = "res://games/cube_trials/assets/tutorial_poster.png"
	game.share_art_scene_path = "res://games/cube_trials/share_art.tscn"
	# Runs pay Sparks; Sparks pay the garage to respray the car. Two slots,
	# because the only car on the trail wears one paint and one wheel finish.
	game.store_currency = Options.STORE_CURRENCY
	game.store_slots = Options.STORE_SLOTS
	game.store_items = Options.STORE_ITEMS
	game.store_preview_scene_path = "res://games/cube_trials/store_preview.tscn"
	# The museum for a game that is only ever seen from one side at speed: the
	# same models, standing still, at whatever angle you like.
	game.gallery_exhibits = Options.GALLERY_EXHIBITS
	game.gallery_stage_scene_path = "res://games/cube_trials/gallery_stage.tscn"
	game.stats_url = "https://deskcansaw.com"
	game.copy = {
		"single_player_description": (
			"One handcrafted 3D trail, five spark plugs and a brown Nissan Cube "
			+ "with more suspension than common sense."
		),
		"player_one_control_description": (
			"Throttle and reverse drive the wheels; tilt balances the cabin. "
			+ "Jump the gaps, release between hops, and brake inside the garage."
		),
		"instructions_headline": "THE VERY UNREASONABLE COMMUTE",
		"instructions_rules": (
			"Bring the brown Nissan Cube home through Copper Creek: rolling hills, "
			+ "washboard, four ravines, Sawtooth Ridge and one last climb. "
			+ "The trail is twice as long as the original commute.\n"
			+ "Collect all FIVE numbered spark plugs, then slow down inside the garage. "
			+ "Keep your roof off the rocks. Carry speed up the quarry ramp, hold the "
			+ "nose up at takeoff, then level the car for landing. "
			+ "The wider gaps need a deliberate jump: build speed, jump at the gold stripes, "
			+ "then tilt to land on both wheels. Release before jumping again; no double jumps.\n"
			+ "Four checkpoint flags save your place only after you collect the earlier plugs. "
			+ "Start with FIVE lives. A roof strike or fall costs one life and recovers the car; "
			+ "the last life ends the run. Recover also works when stuck without costing a life. "
			+ "Pickups are kept. Every recovery adds FIVE seconds. Hard landings only damage "
			+ "the bodywork, not your lives or handling.\n"
			+ "The heart shows lives, the star shows points, and the plug shows your cargo. "
			+ "The clock starts when you drive, tilt or jump and stops while paused. There is no time limit. "
			+ "Gold: 45 seconds or less including penalties; Silver: 70; Bronze: any finish.\n"
			+ "Each plug scores 1,000 points. Finishing adds up to 3,000 more, minus 40 "
			+ "per adjusted second (rounded up), never below zero. "
			+ "Air control and engine sound can be changed live in Settings."
		),
		"instructions_demo_prompt": "SMALL CAR. BIG DETOUR.",
		"store_intro": (
			"Every delivery pays Sparks — one per plug brought in and the rest "
			+ "for how quickly you did it. Spend them at the garage on paint "
			+ "and wheels. None of it makes the car any faster."
		),
		"gallery_intro": (
			"Every model Copper Creek is made of, up close. Turn them, zoom in, "
			+ "and get a proper look at the little brown car for once."
		),
		"instructions_player_one_controls": (
			"Use the rebindable controls below or the on-screen pedals, tilt and jump buttons. "
			+ "By default, Space jumps and Shift brakes. "
			+ "Touch supports multiple fingers. On a gamepad: right trigger accelerates, "
			+ "left trigger reverses, left stick tilts, A jumps, B brakes and Y recovers. "
			+ "Escape / gamepad Start pauses; touch has a Pause button. "
			+ "The camera button, Change camera binding or right-stick click cycles "
			+ "Side, Chase and Cockpit views. Views do not change the driving rules: "
			+ "tilt balances the car, not steering."
		),
	}
	game.achievements = {
		"cube_trials_home": {
			"title": "Home in One Piece", "badge": "HOME",
			"description": "Deliver all five spark plugs to the Copper Creek garage.",
		},
		"cube_trials_clean": {
			"title": "Not a Scratch", "badge": "CLEAN",
			"description": "Finish Copper Creek without a crash or manual recovery.",
		},
		"cube_trials_gold": {
			"title": "Express Delivery", "badge": "GOLD",
			"description": "Finish in 45 seconds or less, including recovery penalties.",
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
			"Copper Creek: an original 3D landscape with side-view trials physics.",
		]},
		{"heading": "Art and sound", "lines": [
			"Original 3D Nissan Cube model, extruded terrain and roadside scenery.",
			"Real-model studio portraits, warm daylight and Compatibility shadows.",
			"Original synthesized engine and event sounds.",
			"Shared DeskCanSaw framework, menus and accessibility.",
		]},
		{"heading": "Acknowledgements", "lines": [
			"Inspired by classic elastic-suspension trials games, including Elasto Mania.",
			"No Elasto Mania levels, code, art or sound are used.",
			"Nissan and Cube are trademarks of their respective owners.",
			"An unofficial tribute; not affiliated with or endorsed by Nissan.",
		]},
	]
	return game
