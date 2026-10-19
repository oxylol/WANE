class_name KillEmber
extends RefCounted
## The ember a kill releases (BUILD.md section 6, hit feedback, Kill: "Enemy ember released as a
## particle that flies to the player (+Flame)"; section 15: "A kill releases an ember that reaches
## the player within 20 frames and the Flame bar visibly reacts"). It is simulated, not drawn
## only, because the Flame it carries is granted when it arrives.
##
## Its flight takes exactly [member frames] ticks wherever the player goes: each tick it sits
## between where it was released and the player's centre now, a smoothstep of the way along, so
## it leaves gently, speeds up and settles onto the player, and can never miss or circle.

## Where it was released, sub-pixels.
var start: Vector2i = Vector2i.ZERO
## Where it is now.
var at: Vector2i = Vector2i.ZERO
## Ticks flown, and the ticks the flight takes.
var age: int = 0
var frames: int = 1


func _init(p_start: Vector2i, p_frames: int) -> void:
	start = p_start
	at = p_start
	frames = maxi(1, p_frames)


## Flies one tick toward [param target]; true on the tick it arrives.
func fly(target: Vector2i) -> bool:
	age += 1
	if age >= frames:
		at = target
		return true
	# Smoothstep in per-mille: s = t * t * (3 - 2t).
	var t: int = age * 1000 / frames
	var s: int = t * t * (3000 - 2 * t) / 1000000
	at = (
		start
		+ Vector2i(
			Fx.div_round((target.x - start.x) * s, 1000),
			Fx.div_round((target.y - start.y) * s, 1000)
		)
	)
	return false


func hash_into(h: StateHasher) -> void:
	h.add_int(start.x)
	h.add_int(start.y)
	h.add_int(at.x)
	h.add_int(at.y)
	h.add_int(age)
	h.add_int(frames)
