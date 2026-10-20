class_name Main
extends Node
## Boot scene: wires the input layer to the fixed-step driver, starts a session in the sandbox
## room, and attaches the views to the driver's ticks (the camera, the player, the enemies and
## combat's objects step once per tick and draw between ticks at the driver's interpolation
## factor). The hit feedback reads each tick's events: shake on the drawn camera only, sparks
## through the VFX budget, sounds through the voices, slow motion through the driver
## (docs/adr/0013). The F3 debug overlay and its frame-stepper are part of every build: F3
## overlay, F4 pause, F5 one tick, F6 ten (docs/adr/0012).

const LAST_REPLAY_PATH: String = "user://replays/last_session.wrp"
## The zone the game boots into: its start room, the Kindle Votive in hand (Phase 1 has no
## Votive pickups; the zone's twelfth room teaches the kindle-dash: docs/adr/0014). Run with
## `-- --room=<id>` to start in any room instead (the room editor's Play does), the sandbox
## included. A session starts with no Votives; `-- --votive=<id>:<stacks>` (as often as wanted)
## gives it some, to play them before pickups exist (docs/adr/0015).
const START_ZONE: String = "res://content/zones/zone1.tres"
const ROOM_ARG: String = "--room="
const VOTIVE_ARG: String = "--votive="
## `-- --lighting=pitch` draws the room under the Phase 1 stand-in lighting at Pitch (the ember
## and its shadows, ambient 0.15; game/lighting). The default is the unlit grey box.
const LIGHTING_ARG: String = "--lighting="

## Set by a harness (the frame bench) before the scene is added: the session to start in place of
## the zone's, and the lighting word to use in place of the command line's ("" reads the command
## line; "off" is the unlit grey box).
static var scenario_override: Scenario = null
static var lighting_word: String = ""

## Built only when the command line, or a harness, asks for Pitch.
var lighting: LightingRig = null
## Whether the session's replay is written when the scene leaves the tree (a harness turns it off).
var save_on_exit: bool = true

@onready var input_layer: InputLayer = $InputLayer
@onready var driver: SimDriver = $SimDriver
@onready var room_view: RoomView = $World/RoomView
@onready var player_view: PlayerView = $World/PlayerView
@onready var game_camera: GameCamera = $World/GameCamera
@onready var debug_overlay: DebugOverlay = $World/DebugOverlay
@onready var debug_controls: DebugControls = $DebugControls
@onready var enemy_view: EnemyView = $World/EnemyView
@onready var combat_view: CombatView = $World/CombatView
@onready var vfx: VfxBudget = $World/Vfx
@onready var voices: Voices = $World/Voices
@onready var hit_feedback: HitFeedback = $HitFeedback
@onready var hud: Hud = $Hud
@onready var feedback_overlay: FeedbackOverlay = $FeedbackOverlay


func _ready() -> void:
	driver.input_layer = input_layer
	driver.ticked.connect(_on_ticked)
	var scenario: Scenario = _scenario()
	driver.start(scenario)
	for problem: String in driver.sim.load_errors:
		push_error("%s: %s" % [scenario.room, problem])
	room_view.show_world(driver.sim.world, driver.sim.room.doors)
	_start_lighting()
	player_view.begin(driver.sim)
	game_camera.begin(driver.sim)
	debug_overlay.attach(driver, game_camera)
	debug_controls.driver = driver
	debug_controls.overlay = debug_overlay
	enemy_view.capture(driver.sim)
	combat_view.player_view = player_view
	combat_view.vfx = vfx
	hit_feedback.attach(vfx, voices)
	hit_feedback.slow_motion.connect(driver.slow)
	hit_feedback.rumble.connect(_on_rumble)
	feedback_overlay.feedback = hit_feedback
	if driver.sim.player != null:
		hud.vitals = driver.sim.player.vitals
		var kit: KitParams = driver.sim.player.kit
		hud.spell_costs = [kit.kindle_cost, kit.mend_cost, kit.radiance_cost]


## The session to start: the room named on the command line, or zone 1's start room with the
## Kindle Votive.
func _scenario() -> Scenario:
	if scenario_override != null:
		return scenario_override
	var seed_value: int = int(Time.get_unix_time_from_system())
	var zone: ZoneDef = load(START_ZONE) as ZoneDef
	var scenario: Scenario = Scenario.make(seed_value, zone.start_room)
	scenario.options["kindle"] = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(ROOM_ARG):
			scenario.room = arg.trim_prefix(ROOM_ARG)
			scenario.options.erase("kindle")
		elif arg.begins_with(VOTIVE_ARG):
			var spec: PackedStringArray = arg.trim_prefix(VOTIVE_ARG).split(":")
			var stacks: int = spec[1].to_int() if spec.size() > 1 else 1
			scenario.options[Simulation.VOTIVE_OPTION + spec[0]] = stacks
	return scenario


func _on_ticked() -> void:
	var sim: Simulation = driver.sim
	if sim.events.has(SimEvents.ROOM):
		enter_room(sim)
	player_view.capture(sim)
	enemy_view.capture(sim)
	game_camera.step(sim)
	# The feedback ages the VFX budget before it starts this tick's effects, so each is drawn from
	# its first frame.
	hit_feedback.on_tick(sim)
	# After the feedback has aged the budget: the combat view's objects are drawn from tick 0.
	combat_view.capture(sim)
	enemy_view.flash_scale = hit_feedback.flash_scale
	hud.flash_scale = hit_feedback.flash_scale
	hud.on_tick(sim.events)
	if sim.player != null:
		voices.listener = Vector2(sim.player.body.x, sim.player.body.y) / Fx.SUB
	debug_overlay.capture()


## Shows the room the player has come into ([param sim]'s current room): its tiles, and under
## Pitch its occluders.
func enter_room(sim: Simulation) -> void:
	room_view.show_world(sim.world, sim.room.doors)
	if lighting != null:
		lighting.show_world(sim.world, sim.room.id)


func _process(delta: float) -> void:
	room_view.refresh()
	player_view.show_at(driver.alpha)
	if lighting != null:
		lighting.follow(player_view.box_at(driver.alpha).get_center(), delta)
	enemy_view.show_at(driver.alpha)
	combat_view.show_at(driver.alpha)
	game_camera.show_at(driver.alpha)
	# The shake moves the drawn view only, never the camera rig (BUILD.md section 6).
	game_camera.apply_shake(hit_feedback.shake_offset())
	debug_overlay.refresh()


func _start_lighting() -> void:
	var word: String = lighting_word
	if word == "":
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with(LIGHTING_ARG):
				word = arg.trim_prefix(LIGHTING_ARG)
	if LightingRig.asks_for_pitch(word):
		lighting = LightingRig.new()
		$World.add_child(lighting)
		lighting.show_world(driver.sim.world, driver.sim.room.id)
		# Every room a door leads to is built now, hidden, so that a crossing builds nothing.
		for id: String in driver.sim.rooms.rooms:
			var beyond: RoomData = driver.sim.rooms.rooms[id]
			if beyond.errors.is_empty():
				lighting.prebuild(id, beyond.grid)


func _on_rumble(strength: float, msec: int) -> void:
	Input.start_joy_vibration(0, strength, strength, float(msec) / 1000.0)


func _exit_tree() -> void:
	# Every session leaves a replay behind, so any bug the director meets can be reproduced.
	if save_on_exit:
		driver.save_replay(LAST_REPLAY_PATH)
