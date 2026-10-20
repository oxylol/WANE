extends SceneTree
## Rewrites tests/replay/golden_hashes.txt from the current simulation.
##
##   godot --headless --path . --script tools/replay/bless.gd
##
## Only bless after every fixture passes and the change to the simulation is intended; commit
## the new golden file in the same commit as the change (ADR-0006).


# _initialize, not _init: the NativeBoot autoload (WANE_NATIVE) exists only from there on.
func _initialize() -> void:
	var ok: bool = FixtureRunner.new().run_all(true)
	quit(0 if ok else 1)
