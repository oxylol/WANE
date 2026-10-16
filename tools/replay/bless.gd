extends SceneTree
## Rewrites tests/replay/golden_hashes.txt from the current simulation.
##
##   godot --headless --path . --script tools/replay/bless.gd
##
## Only bless after every fixture passes and the change to the simulation is intended; commit
## the new golden file in the same commit as the change (ADR-0006).


func _init() -> void:
	var ok: bool = FixtureRunner.new().run_all(true)
	quit(0 if ok else 1)
