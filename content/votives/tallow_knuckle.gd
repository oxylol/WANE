extends VotiveListener
## Tallow Knuckle (Candle; BUILD.md section 8, Tiers: "hits deal +3 flat damage per stack"):
## every Taper and pogo hit deals its curve's value more, before Kindling's bonus. The hit's
## hitstop is weighed without it (docs/adr/0015: items change what a hit does, never how it
## feels).


func on_blade_hit(api: BladeHitApi) -> void:
	api.add_damage(api.value())
