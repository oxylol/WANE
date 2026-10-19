class_name RunMods
extends RefCounted
## The run's standing changes from its "run" Votives (docs/adr/0015), collected by
## [method ProcBus.run_mods] and applied by the simulation to the Wick: the movement recompiled
## with the run speed, the ground dash's cooldown, the maximum hearts.

## Added run speed, per-mille of the Wick's own.
var run_speed_permille: int = 0
## The ground dash has no cooldown.
var dash_free: bool = false
## Hearts added to (negative: taken from) the Wick's maximum.
var max_hearts_delta: int = 0
