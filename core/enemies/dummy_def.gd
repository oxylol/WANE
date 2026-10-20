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
## A walking dummy's speed, in units per second (a room marker's `patrol=1`; docs/adr/0020).
@export var patrol_speed_ups: int = 120
## How far below its feet the floor ahead must be missing before a walking dummy turns back
## instead of walking off (units); a marker's `fall=1` walks off whatever the drop.
@export var patrol_drop_u: int = 16


func validate() -> PackedStringArray:
	var e: PackedStringArray = super.validate()
	if respawn_frames < 1 or swing_period < 1:
		e.append("%s: respawn_frames and swing_period must be at least 1" % kind)
	if patrol_speed_ups < 1 or patrol_drop_u < 1:
		e.append("%s: patrol_speed_ups and patrol_drop_u must be at least 1" % kind)
	return e
