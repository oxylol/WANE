extends VotiveListener
## Hollow Step (Soot; BUILD.md section 8, Tiers: "dash has no cooldown; max hearts -1 per stack"):
## the ground dash's cooldown is gone, as at Kindling White, and the maximum hearts fall by the
## curve's value, never below one heart (docs/adr/0015).


func on_run(api: RunApi) -> void:
	api.remove_dash_cooldown()
	api.add_max_hearts(-api.value())
