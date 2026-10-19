extends VotiveListener
## A test Votive (never content) for the one state a listener may keep: its counter, held by the bus
## in the state hash. Every proc counts one; every so many it hits the enemy the event's hit landed
## on and starts counting again (docs/adr/0015).

const EVERY: String = "every"
const DAMAGE: String = "damage"


func on_proc(api: ProcApi) -> void:
	var count: int = api.counter() + 1
	if count >= api.param(EVERY):
		count = 0
		api.hit(api.target(), api.param(DAMAGE))
	api.set_counter(count)


func params_used() -> PackedStringArray:
	return PackedStringArray([EVERY, DAMAGE])
