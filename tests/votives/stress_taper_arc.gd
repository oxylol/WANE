extends VotiveListener
## The gated stress set's listener (tests/votives/stress_taper_*.tres; never content): the same arc
## as [code]stress_arc.gd[/code] (it arcs to the nearest other enemy and hits it), held to the
## spec's size of burst. BUILD.md section 13 asks the
## stress room for "40 procs", section 6 gives a spell tick a coefficient of 0.2 (Radiance) to 0.5
## (Kindle), and a real Votive carries an internal cooldown, so this one
##   - answers a Taper hit or a pogo (and the chain below them), never a spell tick;
##   - starts one chain per [constant COOLDOWN] ticks (the Votive's counter holds the tick of its
##     last, plus one): the other dummies a swing lands on in that window take their hit and raise
##     no chain. Three of them make 3 + 9 + 27 = 39 procs, once, however many dummies a swing
##     reaches. The storm set (stress_arc_*, no cooldown) is measured apart and not gated
##     (docs/adr/0020, Decision 15).

const COOLDOWN: String = "cooldown_ticks"
const REACH: String = "reach_u"
const DAMAGE: String = "damage"


func on_proc(api: ProcApi) -> void:
	if api.level() == 1:
		if not _starts_a_chain(api.source()):
			return
		var ready_at: int = api.counter() + api.param(COOLDOWN)
		if api.counter() > 0 and api.tick() + 1 < ready_at:
			return
		api.set_counter(api.tick() + 1)
	var to: int = api.nearest_enemy(api.param(REACH), true)
	if to < 0:
		to = api.target()
	api.hit(to, api.param(DAMAGE))


func params_used() -> PackedStringArray:
	return PackedStringArray([REACH, DAMAGE, COOLDOWN])


static func _starts_a_chain(source: int) -> bool:
	return source == ProcSource.TAPER or source == ProcSource.POGO
