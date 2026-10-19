extends VotiveListener
## A test Votive (never content): its proc hits the enemy the event's hit landed on, so it raises a
## proc event of its own one level deeper. With a sure chance it proves the chain's depth: one
## Taper hit fires it at levels 1, 2 and 3, and the hit at level 3 raises nothing (BUILD.md
## section 6: "to a depth of 3, then stop"; docs/adr/0015).

const DAMAGE: String = "damage"


func on_proc(api: ProcApi) -> void:
	api.hit(api.target(), api.param(DAMAGE))


func params_used() -> PackedStringArray:
	return PackedStringArray([DAMAGE])
