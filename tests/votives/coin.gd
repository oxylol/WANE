extends VotiveListener
## A test Votive (never content) whose proc asks for a roll of its own: the roll is drawn from the
## PROCS stream there and then, between the bus's rolls, so the order of every draw is fixed by the
## order the procs fire (docs/adr/0015). Heads, it stuns the enemy it fired on.

const CHANCE: String = "chance_permille"
const STUN: String = "stun_frames"


func on_proc(api: ProcApi) -> void:
	if api.roll_permille(api.param(CHANCE)):
		api.stun_within(0, api.param(STUN))


func params_used() -> PackedStringArray:
	return PackedStringArray([CHANCE, STUN])
