class_name WorldTuning
extends Resource
## Physics numbers that belong to the world rather than to a Wick. Units as the editor shows them;
## [method apply] converts to sub-pixels.

## The game's world tuning.
const PATH: String = "res://content/physics/world.tres"

## How far below a spike tile's top edge its hazard volume begins. Not in BUILD.md: the spikes are
## drawn in the lower part of the tile, and the down-strike's 24 u pogo box reaches 12 u into the
## spikes' tile before the player's hurtbox does (docs/feel_log, task 2).
@export_range(0, 31) var spike_inset_u: int = 12


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if spike_inset_u < 0 or spike_inset_u >= TileGrid.TILE:
		errors.append("spike_inset_u must be in 0..%d" % (TileGrid.TILE - 1))
	return errors


## Sets this tuning on [param world].
func apply(world: CollisionWorld) -> void:
	world.spike_inset_sp = Fx.units(spike_inset_u)
