extends Node
## Boot scene: wires the input layer to the fixed-step driver and starts a session. Views attach
## to the driver's [signal SimDriver.ticked] (later tasks add them here).

const LAST_REPLAY_PATH: String = "user://replays/last_session.wrp"

@onready var input_layer: InputLayer = $InputLayer
@onready var driver: SimDriver = $SimDriver


func _ready() -> void:
	driver.input_layer = input_layer
	driver.start(Scenario.make(int(Time.get_unix_time_from_system())))


func _exit_tree() -> void:
	# Every session leaves a replay behind, so any bug the director meets can be reproduced.
	driver.save_replay(LAST_REPLAY_PATH)
