class_name AttackDef
extends Resource
## One strike of a Wick's weapon (BUILD.md section 6, "The Taper" table). Frames count from 1 on
## the tick the strike starts: frames 1..startup wind up, the next [member active] frames carry
## the hitbox, then [member recovery] frames finish it. Cancel windows name the first frame (of
## this strike) on which another action may interrupt it. Hitboxes are rectangles in units,
## relative to the player's bottom-centre, with +x pointing the way the strike faces.

## Strike id: side1, side2, side3, up, down, charged.
@export var id: String = ""
@export var startup: int = 2
@export var active: int = 4
@export var recovery: int = 8
@export var damage: int = 10
## Knockback dealt (u/s) and recoil taken by the player (u/s), along the strike.
@export var knockback_ups: int = 0
@export var recoil_ups: int = 0
## Launches light enemies (finisher).
@export var launches: bool = false
## Hitbox: left edge forward of the centre, top relative to the feet (negative is up), size.
@export var box_x_u: int = 0
@export var box_y_u: int = -44
@export var box_w_u: int = 68
@export var box_h_u: int = 44
## Pogo hitbox frames (down-strike: 3 to 9); 0 means no pogo.
@export var pogo_first: int = 0
@export var pogo_last: int = 0
## Next strike in the chain and the first frame it may start (side1 -> side2 from f6).
@export var chain_to: String = ""
@export var chain_from: int = 0
## First frame a dash cancels this strike (0 = never).
@export var dash_from: int = 0
## Jump allowed on every frame of this strike (the strike carries on in the air).
@export var jump_any: bool = false
## Another air strike may replace this one on any frame (up-strike).
@export var air_attack_any: bool = false
## Air only (down-strike).
@export var air_only: bool = false
## Frames the attack button must be held to release this strike (charged: 24); 0 = a press.
@export var charge_frames: int = 0


func total_frames() -> int:
	return startup + active + recovery


func is_active(frame: int) -> bool:
	return frame > startup and frame <= startup + active


func pogo_live(frame: int) -> bool:
	return pogo_first > 0 and frame >= pogo_first and frame <= pogo_last


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if id == "":
		e.append("attack needs an id")
	if startup < 1 or active < 1 or recovery < 0:
		e.append("%s: startup and active must be at least 1" % id)
	if box_w_u <= 0 or box_h_u <= 0:
		e.append("%s: hitbox must have positive size" % id)
	if pogo_first > 0 and (pogo_last < pogo_first or pogo_last > total_frames()):
		e.append("%s: pogo window must lie inside the strike" % id)
	if dash_from < 0 or dash_from > total_frames():
		e.append("%s: dash_from must lie inside the strike" % id)
	return e
