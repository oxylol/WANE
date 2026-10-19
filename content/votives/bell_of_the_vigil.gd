extends VotiveListener
## Bell of the Vigil (Lantern; BUILD.md section 8, Tiers: "10% chance on hit to ring, stunning
## everything in 120 u; stacks add chance"): the bus rolls its chance on every proc event; a ring
## stuns every living enemy whose centre is within the radius of the hit, for the stun's length
## (docs/adr/0015: a stun is a stagger poise did not cause).

const RADIUS: String = "radius_u"
const STUN: String = "stun_frames"


func on_proc(api: ProcApi) -> void:
	api.stun_within(api.param(RADIUS), api.param(STUN))


func params_used() -> PackedStringArray:
	return PackedStringArray([RADIUS, STUN])
