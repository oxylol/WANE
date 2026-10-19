class_name HitKind
extends RefCounted
## The kinds of hit in BUILD.md section 6's hit-feedback table, and how a hit event's value
## carries the kind and the direction of the hit, so presentation can shake along it and fan
## its sparks the right way, and the Kindling tier the hit's damage was boosted by, so its sparks
## are tinted by the tier the hit used (task 6 review, presentation L3).

## BURN is the small damage that is not a hit: a burn tick, a Blaze trail, a finisher's AoE.
## PLAYER is an enemy's hit on the player. PROC is a Votive's proc damage (docs/adr/0015), shown by
## its proc's own effect rather than a hit spark.
enum { LIGHT, FINISHER, CHARGED, POGO, SPELL, PARRY, BURN, PLAYER, PROC }


## The event value for a hit of [param kind] travelling along ([param dx], [param dy]), each -1,
## 0 or 1, boosted by Kindling tier [param tier].
static func encode(kind: int, dx: int, dy: int, tier: int = 0) -> int:
	return kind + 16 * ((signi(dx) + 1) + 3 * (signi(dy) + 1)) + 144 * tier


static func kind_of(value: int) -> int:
	return value % 16


static func dir_of(value: int) -> Vector2i:
	var d: int = (value / 16) % 9
	return Vector2i(d % 3 - 1, d / 3 - 1)


static func tier_of(value: int) -> int:
	return value / 144
