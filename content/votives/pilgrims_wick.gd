extends VotiveListener
## Pilgrim's Wick (Candle; BUILD.md section 8, Tiers: "+8% run speed per stack"): the run speed
## rises by its curve's value, per-mille. "Run speed" is the most the Wick runs at, on the ground
## and in the air, with the acceleration times kept; the dash, the jumps, the wall and the pogo are
## untouched (docs/adr/0015).


func on_run(api: RunApi) -> void:
	api.add_run_speed_permille(api.value())
