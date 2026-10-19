extends VotiveListener
## The stress set's listener (tests/votives/stress_arc_*.tres; never content): its proc arcs to the
## living enemy nearest the hit within its reach, other than the one hit (that one if no other is
## in reach), and hits it. Three of them at a sure chance fire 3 + 9 + 27 = 39 procs from one Taper
## hit, to the chain's depth of 3: the burst of about 40 the stress room stacks (BUILD.md section
## 13, "a stress room (200 enemies, 40 procs, Pitch lighting)"; docs/adr/0015).

const REACH: String = "reach_u"
const DAMAGE: String = "damage"


func on_proc(api: ProcApi) -> void:
	var to: int = api.nearest_enemy(api.param(REACH), true)
	if to < 0:
		to = api.target()
	api.hit(to, api.param(DAMAGE))


func params_used() -> PackedStringArray:
	return PackedStringArray([REACH, DAMAGE])
