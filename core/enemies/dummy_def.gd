class_name DummyDef
extends EnemyDef
## The training dummy's numbers (Phase 1 task 6; docs/adr/0013): an enemy's, plus how long a kill
## keeps it down and the rhythm of its swing. Every tunable number lives in content (CLAUDE.md
## rule 6; task 6 core review 2, L2: these two were literals in core/enemies/training_dummy.gd).

## Ticks after a kill before the dummy comes back whole at its marker.
@export var respawn_frames: int = 60
## Ticks between the end of one swing and the start of the next; a room marker's `period=`
## overrides it for that dummy.
@export var swing_period: int = 90


func validate() -> PackedStringArray:
	var e: PackedStringArray = super.validate()
	if respawn_frames < 1 or swing_period < 1:
		e.append("%s: respawn_frames and swing_period must be at least 1" % kind)
	return e
