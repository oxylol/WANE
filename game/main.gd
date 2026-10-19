extends Node
## Boot scene: wires the input layer to the fixed-step driver, starts a session in the sandbox
## room, and attaches the views to the driver's ticks (the camera, the player, the enemies and
## combat's objects step once per tick and draw between ticks at the driver's interpolation
## factor). The hit feedback reads each tick's events: shake on the drawn camera only, sparks
## through the VFX budget, sounds through the voices, slow motion through the driver
## (docs/adr/0013). The F3 debug overlay and its frame-stepper are part of every build: F3
## overlay, F4 pause, F5 one tick, F6 ten (docs/adr/0012).

const LAST_REPLAY_PATH: String = "user://replays/last_session.wrp"
## The room the game boots into until zone 1 exists (Phase 1 task 7).
const START_ROOM: String = "sandbox"

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
	driver.start(Scenario.make(int(Time.get_unix_time_from_system()), START_ROOM))
	for problem: String in driver.sim.load_errors:
		push_error("%s: %s" % [START_ROOM, problem])
	room_view.show_world(driver.sim.world)
	player_view.begin(driver.sim)
	game_camera.begin(driver.sim)
	debug_overlay.attach(driver, game_camera)
	debug_controls.driver = driver
	debug_controls.overlay = debug_overlay
	enemy_view.capture(driver.sim)
	combat_view.player_view = player_view
	hit_feedback.attach(vfx, voices)
	hit_feedback.slow_motion.connect(driver.slow)
	hit_feedback.rumble.connect(_on_rumble)
	feedback_overlay.feedback = hit_feedback
	if driver.sim.player != null:
		hud.vitals = driver.sim.player.vitals


func _on_ticked() -> void:
	var sim: Simulation = driver.sim
	player_view.capture(sim)
	enemy_view.capture(sim)
	combat_view.capture(sim)
	game_camera.step(sim)
	# The feedback ages the VFX budget before it starts this tick's effects, so each is drawn from
	# its first frame.
	hit_feedback.on_tick(sim)
	enemy_view.flash_scale = hit_feedback.flash_scale
	hud.on_tick()
	if sim.player != null:
		voices.listener = Vector2(sim.player.body.x, sim.player.body.y) / Fx.SUB
	debug_overlay.capture()


func _process(_delta: float) -> void:
	room_view.refresh()
	player_view.show_at(driver.alpha)
	enemy_view.show_at(driver.alpha)
	combat_view.show_at(driver.alpha)
	game_camera.show_at(driver.alpha)
	# The shake moves the drawn view only, never the camera rig (BUILD.md section 6).
	game_camera.offset = hit_feedback.shake_offset()
	debug_overlay.refresh()


func _on_rumble(strength: float, msec: int) -> void:
	Input.start_joy_vibration(0, strength, strength, float(msec) / 1000.0)


func _exit_tree() -> void:
	# Every session leaves a replay behind, so any bug the director meets can be reproduced.
	driver.save_replay(LAST_REPLAY_PATH)
