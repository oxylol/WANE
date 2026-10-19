class_name EaseMath
extends RefCounted
## Shared easing arithmetic for the presentation's followers (the drawn player's catch-up on a
## nudge, the camera's catch-up at the end of a teleport's glide): a gap closed under a limit on
## how fast the speed may change, and met at rest.


## The fastest speed a gap of [param gap] can be closed at this tick and still be met at rest,
## slowing by at most [param accel] a tick: after a step of v the speeds can fall no faster than
## v - accel, v - 2 accel, ... to a last step of at most accel, so the gap must hold all of them.
## With m such steps after this one the gap holds at most (m + 1) v - accel m (m + 1) / 2, which
## sets v for the m that fits.
static func braking_speed(gap: float, accel: float) -> float:
	if gap <= 0.0 or accel <= 0.0:
		return 0.0
	var m: int = ceili((sqrt(1.0 + 8.0 * gap / accel) - 1.0) * 0.5) - 1
	return (gap + accel * m * (m + 1) * 0.5) / (m + 1)
