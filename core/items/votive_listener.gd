class_name VotiveListener
extends RefCounted
## The script half of a Votive (BUILD.md section 13, layer 3: "a Votive is a resource with a proc
## listener script and a stacking curve"; CLAUDE.md, Content: "adding one never touches core/";
## docs/adr/0015). A Votive's listener extends this class and overrides the hook for each trigger
## its resource lists in [member Votive.listens_to]:
##
## - "hit": [method on_proc], once for every proc that fires on a proc event (the bus rolls the
##   chance from the Votive's chance curve; the listener only says what the proc does).
## - "blade_hit": [method on_blade_hit], before every Taper or pogo hit lands, to change its damage.
## - "bounce": [method on_bounce], on every pogo bounce, off an enemy or off the world.
## - "run": [method on_run], whenever the run's Votives change (and at the start), to change the
##   run's standing numbers.
##
## A listener acts only through the API it is handed: integer maths, rolls from the PROCS stream,
## enemies by handle. It has no state of its own (no member variables: its Votive's counter, kept
## and hashed by the bus, is the one place it may remember anything), no Nodes, no floats, no
## numbers of its own (every number comes from its resource through [method VotiveApi.param] or
## its curve). tools/ci/votive_rules.gd checks all of this on every listener in CI.


## A proc of this Votive fired ("hit" trigger).
func on_proc(_api: ProcApi) -> void:
	pass


## A Taper or pogo hit is about to land ("blade_hit" trigger).
func on_blade_hit(_api: BladeHitApi) -> void:
	pass


## A pogo bounce ("bounce" trigger).
func on_bounce(_api: BounceApi) -> void:
	pass


## The run's Votives changed ("run" trigger).
func on_run(_api: RunApi) -> void:
	pass


## The names of the numbers this listener reads from its resource's
## [member Votive.params]; validation requires exactly these.
func params_used() -> PackedStringArray:
	return PackedStringArray()
