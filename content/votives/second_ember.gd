extends VotiveListener
## Second Ember (Lantern; BUILD.md section 8, Tiers: "pogo bounces grant 1 extra air dash per
## stack"): a bounce, off an enemy or off the world, leaves the Wick its own air dashes plus the
## curve's value, until it lands (a cling or a wall-jump keeps them: docs/adr/0015).


func on_bounce(api: BounceApi) -> void:
	api.add_air_dashes(api.value())
