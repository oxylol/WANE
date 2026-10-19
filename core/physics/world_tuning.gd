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
## Joins between a solid box and the terrain closer than this are invalid content (docs/adr/0008,
## decision 10; [RoomJoins]): a box's top buried this far or less under the ground, or a one-way
## this far or less above a box's top beside it. More than any Wick's corner lift (Ash 8 u) or
## ledge-grab (10 u), with BUILD.md section 4's 15% between Wicks.
@export_range(1, 31) var join_band_u: int = 12


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if spike_inset_u < 0 or spike_inset_u >= TileGrid.TILE:
		errors.append("spike_inset_u must be in 0..%d" % (TileGrid.TILE - 1))
	if join_band_u < 1 or join_band_u >= TileGrid.TILE:
		errors.append("join_band_u must be in 1..%d" % (TileGrid.TILE - 1))
	return errors


## Sets this tuning on [param world].
func apply(world: CollisionWorld) -> void:
	world.spike_inset_sp = Fx.units(spike_inset_u)
