class_name RunApi
extends VotiveApi
## What a Votive may change about the whole run ("run" trigger; docs/adr/0015): the standing
## numbers the bus collects from every "run" Votive ([RunMods]) and the simulation applies to the
## Wick whenever the run's Votives change.

var _mods: RunMods = RunMods.new()


## Run speed +[param per_mille] per-mille of the Wick's own (80 is +8%): the most it runs at, on
## the ground and in the air, with its acceleration times kept (docs/adr/0015).
func add_run_speed_permille(per_mille: int) -> void:
	_mods.run_speed_permille += per_mille


## The ground dash's cooldown is gone, as at Kindling White.
func remove_dash_cooldown() -> void:
	_mods.dash_free = true


## The Wick's maximum hearts change by [param hearts] (never below one heart).
func add_max_hearts(hearts: int) -> void:
	_mods.max_hearts_delta += hearts
