extends Node
## Boot scene: wires the input layer to the fixed-step driver, starts a session in the sandbox
## room, and attaches the views to the driver's ticks (the camera and the player step once per
## tick and draw between ticks at the driver's interpolation factor).

const LAST_REPLAY_PATH: String = "user://replays/last_session.wrp"
## The room the game boots into until zone 1 exists (Phase 1 task 7).
const START_ROOM: String = "sandbox"

@onready var input_layer: InputLayer = $InputLayer
@onready var driver: SimDriver = $SimDriver
@onready var room_view: RoomView = $World/RoomView
@onready var player_view: PlayerView = $World/PlayerView
@onready var game_camera: GameCamera = $World/GameCamera


func _ready() -> void:
	driver.input_layer = input_layer
	driver.ticked.connect(_on_ticked)
	driver.start(Scenario.make(int(Time.get_unix_time_from_system()), START_ROOM))
	for problem: String in driver.sim.load_errors:
		push_error("%s: %s" % [START_ROOM, problem])
	room_view.show_world(driver.sim.world)
	player_view.begin(driver.sim)
	game_camera.begin(driver.sim)


func _on_ticked() -> void:
	player_view.capture(driver.sim)
	game_camera.step(driver.sim)


func _process(_delta: float) -> void:
	room_view.refresh()
	player_view.show_at(driver.alpha)
	game_camera.show_at(driver.alpha)


func _exit_tree() -> void:
	# Every session leaves a replay behind, so any bug the director meets can be reproduced.
	driver.save_replay(LAST_REPLAY_PATH)
