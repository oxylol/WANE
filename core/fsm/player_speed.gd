class_name PlayerSpeed
extends RefCounted
## A Wick's horizontal speed for one tick, on the ground and in the air (BUILD.md section 5): static
## helpers on a [Player], kept apart from the state machine so it stays under its size cap; the
## turnaround state they change ([member Player.turn_left]) is the player's.


static func ground_speed(pl: Player, vx: int, input_x: int) -> int:
	if pl.knock_left > 0:
		return _knocked(pl)
	return _horizontal(pl, vx, input_x, pl.p.run_accel, pl.p.run_decel, true)


static func air_speed(pl: Player, vx: int, input_x: int) -> int:
	if pl.knock_left > 0:
		return _knocked(pl)
	return _horizontal(pl, vx, input_x, pl.p.air_accel, pl.p.air_decel, false)


## A hit's knockback holds its speed, whatever the stick says (docs/adr/0013).
static func _knocked(pl: Player) -> int:
	pl.turn_left = 0
	return pl.knock_vx


## Horizontal speed for one tick. On the ground a reversal flips to 60% of the speed in the new
## direction on the input frame (never a dead frame) and recovers the rest over the next
## turn_frames frames (BUILD.md Ground: "Turnaround"). In the air a reversal is ordinary air
## control (BUILD.md Jump: "0 to max in 8 f"). Above run speed the ground slows back to it; the air
## keeps the extra speed (dash-jump and pogo momentum) while the stick holds that way.
static func _horizontal(
	pl: Player, vx: int, input_x: int, accel: int, decel: int, on_ground: bool
) -> int:
	if input_x == 0 or not on_ground:
		pl.turn_left = 0
	if input_x == 0:
		return Fx.approach(vx, 0, decel)
	if vx != 0 and signi(vx) != input_x:
		if not on_ground:
			return Fx.approach(vx, input_x * pl.p.run_speed, accel)
		pl.turn_left = pl.p.turn_frames
		return input_x * Fx.percent(mini(absi(vx), pl.p.run_speed), pl.p.turn_keep_percent)
	if absi(vx) < pl.p.run_speed:
		var a: int = accel
		if pl.turn_left > 0:
			pl.turn_left -= 1
			a = maxi(
				accel,
				Fx.per_tick(
					pl.p.run_speed - Fx.percent(pl.p.run_speed, pl.p.turn_keep_percent),
					pl.p.turn_frames
				)
			)
		return Fx.approach(vx, input_x * pl.p.run_speed, a)
	pl.turn_left = 0
	if on_ground:
		return Fx.approach(vx, input_x * pl.p.run_speed, decel)
	return vx
