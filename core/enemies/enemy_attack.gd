class_name EnemyAttack
extends Resource
## One enemy attack (BUILD.md section 6, "Enemy-side rules": "Every enemy attack has a telegraph
## of >= 20 f with a distinct silhouette change and a sound"; "Parry": "The parry window is defined
## on the enemy's attack"). Frames count from 1 on the tick the telegraph starts: the telegraph,
## then the active frames (the first is the tick the hit lands), then recovery. The hitbox is in
## units relative to the enemy's bottom-centre, +x the way it faces.

## BUILD.md section 6, Enemy-side rules: "Every enemy attack has a telegraph of >= 20 f".
const MIN_TELEGRAPH: int = 20

@export var id: String = ""
@export var telegraph: int = 20
@export var active: int = 4
@export var recovery: int = 16
## Hearts taken from the player.
@export var damage: int = 1
## Hitbox: left edge forward of the centre, top relative to the feet (negative is up), size.
@export var box_x_u: int = 0
@export var box_y_u: int = -40
@export var box_w_u: int = 48
@export var box_h_u: int = 40
## Bosses' red attacks cannot be parried ("a red flash instead of white").
@export var parryable: bool = true


func total() -> int:
	return telegraph + active + recovery


## True on the frames the hitbox is live.
func is_active(frame: int) -> bool:
	return frame > telegraph and frame <= telegraph + active


## The frame the hit lands (the first active frame).
func landing_frame() -> int:
	return telegraph + 1


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if id == "":
		e.append("an enemy attack needs an id")
	if telegraph < MIN_TELEGRAPH:
		e.append(
			"%s: telegraph %d f is under BUILD.md's %d f minimum" % [id, telegraph, MIN_TELEGRAPH]
		)
	if active < 1 or recovery < 0 or damage < 0:
		e.append("%s: needs active frames, and recovery and damage must not be negative" % id)
	if box_w_u <= 0 or box_h_u <= 0:
		e.append("%s: the hitbox needs a size" % id)
	return e
