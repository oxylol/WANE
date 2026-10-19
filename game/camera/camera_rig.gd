class_name CameraRig
extends RefCounted
## The camera's logic, stepped once per simulation tick so it behaves the same at any frame rate
## and can be checked against every replay fixture (BUILD.md section 5: "The camera never fights
## the player"; ADR-0011). Units are world units, y down.
##
## Horizontally the view follows the player plus a lead in the facing direction: inside the dead
## zone the player moves freely, beyond it the view moves with the player exactly, so the player
## holds still on screen at speed. The lead swings smoothly when Ash turns and never pulls the
## view against the player's own motion.
##
## Vertically the view rests on the last height the player stood, clung, kicked or bounced at,
## so a jump does not bob it. That rest height follows the feet down at once and eases up to a
## higher support; in the air it rises with the feet only beyond a window, and comes back down
## with them. The dead zone holds the view still for small changes of the rest height; beyond
## it the view catches up at the lerp, never changing speed faster than a set acceleration.
## Two looks are added after the dead zone, so they move the view exactly as far as they say:
## ahead of a fall (never past the ground the fall will land on) and down while the player asks
## to look down.
##
## The view keeps within the room grown by the edge margin, easing into those bounds rather than
## stopping dead, so the player is never nearer the view's edge than the margin (section 15)
## without the margin having to push. A hazard respawn cuts; a teleport glides.

const TUNING_PATH: String = "res://content/camera.tres"
## The peak speed of a smootherstep over its length, as a multiple of the average: a glide of
## distance d over n ticks peaks at 1.875 * d / n.
const SMOOTHERSTEP_PEAK: float = 1.875

var tuning: CameraTuning
## The view centre after the latest tick, and after the one before (views draw between them).
var center: Vector2 = Vector2.ZERO
var previous: Vector2 = Vector2.ZERO
## The size of the view on screen, in units: at least the tuning's 1920 x 1080; a wider screen
## sees more (set by [GameCamera]).
var view_size: Vector2 = Vector2.ZERO
## Ticks on which the margin had to move the view. The follow and the bounds are built never to
## need it.
var follow_misses: int = 0
## The point the follow aimed at on the latest tick (for overlays and tests).
var focus: Vector2 = Vector2.ZERO

## Where the follow puts the view; [member center] adds what is left of a teleport's glide.
var _base: Vector2 = Vector2.ZERO
## The follow's vertical speed last tick (for the acceleration limit).
var _vy: float = 0.0
## The player's vertical speed last tick: whether the player stopped or turned this tick.
var _player_vy: float = 0.0
## The dead-zone anchors: the horizontal focus and the vertical rest focus the view holds to.
var _anchor: Vector2 = Vector2.ZERO
var _lead: float = 0.0
## The direction the lead follows, and how long and how far Ash has been turned the other way
## (see [member CameraTuning.lead_commit_frames]).
var _lead_dir: int = 1
var _turn_ticks: int = 0
var _turn_from_x: float = 0.0
var _look: float = 0.0
var _fall_lead: float = 0.0
var _up_look: float = 0.0
var _look_ticks: int = 0
## The look-down has been asked for its whole delay and is still wanted: it carries on through a
## crouched strike (held) and a drop with the stick held down (camera review 5, H3), and ends when
## Ash stands up, lets the stick go or does anything else on the ground (camera review 6, H1).
var _look_on: bool = false
## Ash stood on the ground on the look's last tick (the landing tick itself is not yet a crouch).
var _look_grounded: bool = false
## The rest window has raised the view above the support; on the next support the dead zone
## re-centres instead of holding the view where the window left it.
var _raised: bool = false
## Ash has touched a wall since last standing on the ground: turns do not commit the lead until
## Ash stands again (a shaft climb faces each wall in turn without choosing a way to go).
var _off_wall: bool = false
## Where Ash last touched a wall (across).
var _wall_x: float = 0.0
## Ash stood on the ground last tick (continuous ground carries the rest height directly).
var _grounded: bool = false
## The last support height (feet), and the rest height easing toward it.
var _support_y: float = 0.0
var _eased_y: float = 0.0
var _last_x: float = 0.0
## The glide: the offset from the follow when it started, its length and the ticks since.
var _glide_from: Vector2 = Vector2.ZERO
var _glide_frames: int = 0
var _glide_tick: int = 0
## The glide's vertical offset from the follow last tick and its change that tick, and whether the
## player has made it finish early (see [method _glide_offset_y]).
var _glide_y: float = 0.0
var _glide_rate_y: float = 0.0
var _catching: bool = false
## Whether the glide moved the view this tick, whether it did on the tick before the follow took
## over again, and the view's own speed on that last glide tick (the follow's first tick after a
## glide starts from it, so the view's speed changes by no more than the follow's acceleration;
## camera review 7, L1).
var _glide_applied: bool = false
var _after_glide: bool = false
var _glide_exit_vy: float = 0.0


func _init(p_tuning: CameraTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else load(TUNING_PATH) as CameraTuning
	view_size = Vector2(tuning.view_w_u, tuning.view_h_u)


func half_view() -> Vector2:
	return view_size * 0.5


## Where the follow alone puts the view's centre (without what is left of a glide).
func base() -> Vector2:
	return _base


## The point the dead zone holds the view to (the dead zone is centred on it); the focus is this
## plus the looks (for overlays).
func anchor() -> Vector2:
	return _anchor


## True on every tick a teleport's glide moved the view, its last included (the tick on which the
## view's speed still carries the glide's final change; camera review 7, L1).
func gliding() -> bool:
	return _glide_applied


## True while a teleport's glide has more to move (before this tick's move).
func _glide_pending() -> bool:
	return _glide_tick < _glide_frames or (_catching and _glide_y != 0.0)


## Places the view on [param s] at once (a new room, a respawn).
func reset(s: CameraSubject, room: Rect2) -> void:
	_place(s, room)
	_base = _keep_player_clear(_base, s.box, float(tuning.edge_margin_u))
	_glide_frames = 0
	_glide_tick = 0
	_glide_y = 0.0
	_catching = false
	_glide_applied = false
	_after_glide = false
	center = _base
	previous = center


## One tick: [param s] is this tick's subject, [param room] the room's bounds.
func step(s: CameraSubject, room: Rect2) -> void:
	if s.respawned or s.entered:
		reset(s, room)
		return
	previous = center
	var follow_vy: float = _vy
	if s.teleported:
		_start_glide(s, room)
	else:
		_track(s, room)
	var c: Vector2 = _base
	_glide_applied = _glide_pending()
	if _glide_applied:
		var eased: float = 1.0
		if _glide_tick < _glide_frames:
			_glide_tick += 1
			var t: float = float(_glide_tick) / float(_glide_frames)
			# Smootherstep: the glide starts and ends with no speed and no acceleration.
			eased = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
		c.x += _glide_from.x * (1.0 - eased)
		# Across, a glide yields to the margin: a player who outruns it toward the view's edge
		# (a dash toward an edge with no border tile, where the follow itself holds the player on
		# the margin) takes the view along, as the rigid follow across would (camera review 5, M3).
		var margin: float = float(tuning.edge_margin_u)
		c.x = _keep_player_clear(c, s.box, margin).x
		var budget: float = float(tuning.glide_accel_milli_u) / 1000.0 - absf(_vy - follow_vy)
		c.y += _glide_offset_y(s, _glide_from.y * (1.0 - eased), budget)
	center = _clear_player(c, s.box)
	_after_glide = _glide_applied and not _glide_pending()
	_glide_exit_vy = center.y - previous.y


## The glide's vertical offset from the follow this tick, [param nominal] (the smootherstep's)
## until the player comes nearer than [member CameraTuning.glide_cut_u] to the edge the view is
## gliding toward (a dash, an up-dash or a fall on, the way the view has yet to go: a borderless
## top or a ceiling holds the follow, and the glide's offset held the view behind it, needing the
## backstop; camera review 6, M1). From then on the rest of the offset is closed as fast as
## [param budget] allows (what the glide's acceleration leaves after the follow's own change this
## tick, up to the glide's peak speed) and met at rest: the view gains on the player smoothly, and
## the glide ends early.
func _glide_offset_y(s: CameraSubject, nominal: float, budget: float) -> float:
	if not _catching:
		var view_y: float = _base.y + nominal
		var gap: float = (
			s.box.position.y - (view_y - half_view().y)
			if nominal > 0.0
			else view_y + half_view().y - s.box.end.y
		)
		if nominal == 0.0 or gap >= float(tuning.glide_cut_u):
			_glide_rate_y = nominal - _glide_y
			_glide_y = nominal
			return nominal
		_catching = true
	var left: float = absf(_glide_y)
	var dir: float = -signf(_glide_y)
	var speed: float = maxf(_glide_rate_y * dir, 0.0)
	# The plan brakes with what the glide's acceleration leaves after the follow's most, so it
	# can always be kept.
	var brake: float = float(tuning.glide_accel_milli_u - tuning.vertical_accel_milli_u) / 1000.0
	var change: float = maxf(budget, 0.0)
	var slowest: float = maxf(speed - change, 0.0)
	var fastest: float = maxf(minf(speed + change, float(tuning.glide_peak_u)), slowest)
	var move: float = clampf(EaseMath.braking_speed(left, brake), slowest, fastest)
	move = minf(move, left)
	_glide_rate_y = move * dir
	_glide_y += _glide_rate_y
	if absf(_glide_y) < 0.001:
		_glide_y = 0.0
	return _glide_y


## The follow restarts where the player now is; the view glides there from where it was, over
## a time that keeps the glide's peak speed within [member CameraTuning.glide_peak_u]. On an axis
## where the old view would leave the player nearer its edge than
## [member CameraTuning.glide_cut_u], the view cuts at once (and is not interpolated across).
func _start_glide(s: CameraSubject, room: Rect2) -> void:
	var old: Vector2 = center
	_place(s, room)
	var start: Vector2 = old
	var clear: Vector2 = _keep_player_clear(old, s.box, float(tuning.glide_cut_u))
	# Where the room's bound holds the follow itself with the player within glide_cut_u of the
	# view's edge (an edge with no border tile), any glide inward would carry the player past the
	# margin: that axis cuts too (camera review 5, M3).
	var held: Vector2 = _keep_player_clear(_base, s.box, float(tuning.glide_cut_u))
	# The view cuts all the way to the follow: cutting only to the margin would leave the player
	# on it, and a glide from just outside it starts too slowly for a dash or an up-dash onward
	# (the follow trails a sudden move by the dead zone and its acceleration's lag).
	if not is_equal_approx(clear.x, old.x) or not is_equal_approx(held.x, _base.x):
		start.x = _base.x
	if not is_equal_approx(clear.y, old.y) or not is_equal_approx(held.y, _base.y):
		start.y = _base.y
	if start != old:
		previous = start
	_glide_from = start - _base
	_glide_y = _glide_from.y
	_glide_rate_y = 0.0
	_catching = false
	var peak_frames: int = ceili(
		SMOOTHERSTEP_PEAK * _glide_from.length() / float(tuning.glide_peak_u)
	)
	_glide_frames = maxi(tuning.glide_frames, peak_frames)
	_glide_tick = 0


## The follow set straight on [param s], as if the camera had always followed it.
func _place(s: CameraSubject, room: Rect2) -> void:
	_lead_dir = signi(s.facing)
	_lead = float(tuning.lead_u * _lead_dir)
	_turn_ticks = 0
	_look = 0.0
	_fall_lead = 0.0
	_up_look = 0.0
	_look_ticks = 0
	_look_on = false
	_look_grounded = s.on_ground
	_raised = false
	_off_wall = false
	_grounded = s.on_ground
	_support_y = s.box.end.y
	_eased_y = _support_y
	_last_x = s.box.get_center().x
	_anchor = Vector2(s.anchor().x + _lead, _rest_y(s) - s.stand_height * 0.5)
	focus = _anchor
	_base = _bounded(_anchor, room)
	_vy = 0.0
	_player_vy = s.vy


func _track(s: CameraSubject, room: Rect2) -> void:
	_update_lead(s)
	_update_rest(s)
	var half_dead := Vector2(tuning.dead_zone_w_u, tuning.dead_zone_h_u) * 0.5
	var raw := Vector2(s.anchor().x + _lead, _rest_y(s) - s.stand_height * 0.5)
	var anchor_y: float = _anchor.y
	_anchor.x = _hold(_anchor.x, raw.x, half_dead.x)
	if _raised and s.on_ground and _rest_y(s) >= _eased_y:
		# The window let the view rise with the feet and has let go again; back on the ground, the
		# view comes back to centre rather than resting the dead zone's half-height off it (a
		# double jump in place). A climb's clings are left alone, so it climbs steadily.
		_raised = false
		_anchor.y = raw.y
	else:
		_anchor.y = _hold(_anchor.y, raw.y, half_dead.y)
	_update_looks(s, _anchor.y - anchor_y)
	focus = Vector2(_anchor.x, _anchor.y + _look + _fall_lead - _up_look)
	var target: Vector2 = _bounded(focus, room)
	var c := Vector2(target.x, _base.y)
	var lerp_w: float = float(tuning.vertical_lerp_permille) / 1000.0
	var accel: float = float(tuning.vertical_accel_milli_u) / 1000.0
	# The tick after a glide the follow starts from the view's own speed, with the glide's last
	# change in it (camera review 7, L1).
	var own_vy: float = _glide_exit_vy if _after_glide else _vy
	var bounds: Vector2 = _speed_bounds(s.vy, accel, own_vy)
	var vy: float = clampf((target.y - _base.y) * lerp_w, bounds.x, bounds.y)
	if not s.supported and s.vy > 0.0 and s.box.end.y >= _support_y - 0.5:
		# Ash is falling at or below the last support: the view never rises against the fall,
		# even while it is still catching up from below (a climb it lagged, then a walk off the
		# top). On the way down of a hop above it (in place, or up a staircase) the view carries on
		# as it was, easing up to the support: the hop does not move it (camera review 6, M2).
		vy = maxf(vy, 0.0)
	elif not s.supported and s.vy > 0.0 and not _lands_at_support(s):
		# Above the last support but falling away from it (off a ledge, off a climb, after a
		# wall-jump: the ground the fall lands on is below the support): the view's rise only
		# shrinks, at the follow's own acceleration, so it never lifts a tile against the fall
		# (camera review 7, H1).
		vy = maxf(vy, minf(own_vy + accel, 0.0))
	elif not s.supported and s.vy < 0.0:
		# Ash is rising: the view never sinks against the rise, even while it is still catching up
		# with a fall it lagged (an air jump just above the floor; camera review 5, H2).
		vy = minf(vy, 0.0)
	c.y += vy
	var clear: Vector2 = _clear_player(c, s.box)
	_vy = clear.y - _base.y
	_base = clear
	_player_vy = s.vy


## The vertical speeds the view may take this tick: within the acceleration of last tick's, except
## that a view outrunning the player (falling faster than the player now falls, or rising faster
## than the player now rises) may slow at once to the player's own speed. It turns with the player
## at once only when the player turned, from moving the view's way (a bounce, a cling, an up-dash
## out of a fall); otherwise it may stop at once but no more. A jump out of a held look-down, the
## view still sinking into the look, stops the view and does not snap it into a rise (camera
## review 5). It never carries on against the player, and a jump or a kick, which the view lags
## anyway, loosens nothing.
func _speed_bounds(player_vy: float, accel: float, own_vy: float) -> Vector2:
	var lo: float = own_vy - accel
	var hi: float = own_vy + accel
	if own_vy > 0.0 and player_vy < own_vy:
		lo = minf(lo, player_vy if _player_vy > 0.0 else maxf(player_vy, 0.0))
	elif own_vy < 0.0 and player_vy > own_vy:
		hi = maxf(hi, player_vy if _player_vy < 0.0 else minf(player_vy, 0.0))
	return Vector2(lo, hi)


## The lead eases toward the facing direction, but never faster than lets the focus keep moving
## the way the player moves: a strike backward in the air, which turns Ash while the jump still
## carries them forward, never pulls the view back.
func _update_lead(s: CameraSubject) -> void:
	var x: float = s.box.get_center().x
	var moved: float = x - _last_x
	_last_x = x
	_commit_turn(s, x)
	var swing: float = clampf(
		float(tuning.lead_u * _lead_dir) - _lead,
		-float(tuning.lead_speed_u),
		float(tuning.lead_speed_u)
	)
	if moved > 0.0:
		swing = maxf(swing, -moved)
	elif moved < 0.0:
		swing = minf(swing, -moved)
	_lead += swing


## The lead takes a new facing once Ash has gone [member CameraTuning.lead_commit_u] that way
## since turning (the lead's whole swing), or kept facing it
## [member CameraTuning.lead_commit_frames] ticks: turning back and forth in place, or striking
## both ways in a fight, leaves the lead (and the view) where it is. Between touching a wall and
## next standing on the ground no turn commits, unless Ash gets
## [member CameraTuning.lead_wall_release_u] from that wall: a cling faces Ash away from the wall
## it holds, so a climb up a shaft turns at every wall without choosing a way to go.
func _commit_turn(s: CameraSubject, x: float) -> void:
	if s.walled:
		_off_wall = true
		_wall_x = x
	elif s.on_ground or absf(x - _wall_x) > float(tuning.lead_wall_release_u):
		_off_wall = false
	var dir: int = signi(s.facing)
	if dir == _lead_dir or dir == 0 or _off_wall:
		_turn_ticks = 0
		return
	if _turn_ticks == 0:
		_turn_from_x = x
	_turn_ticks += 1
	var travelled: float = (x - _turn_from_x) * float(dir)
	if _turn_ticks >= tuning.lead_commit_frames or travelled >= float(tuning.lead_commit_u):
		_lead_dir = dir
		_turn_ticks = 0


## True when the fall Ash is in lands no lower than the last support: a hop toward it (the way
## down of a hop in place, up a staircase, onto a ledge), where the view carries on easing up to
## it, not a fall away from it ([member CameraSubject.ground_below], the steering envelope
## included).
func _lands_at_support(s: CameraSubject) -> bool:
	return s.box.end.y + s.ground_below <= _support_y + 0.5


## The support height: the feet on the last support, or the feet whenever they fall below it.
## The eased height follows it down at once and up at a limited speed, so landing higher never
## starts the view with a jolt and a wall climb moves it steadily.
func _update_rest(s: CameraSubject) -> void:
	var feet: float = s.box.end.y
	# Walking up continuous ground (a ramp, a step) carries the rest height with it at once, as a
	# fall carries it down; only a jump up to a new support eases.
	var climbed: float = _support_y - feet if s.on_ground and _grounded else 0.0
	_grounded = s.on_ground
	if s.supported or feet > _support_y:
		_support_y = feet
	if _support_y > _eased_y:
		_eased_y = _support_y
	elif s.supported or s.vy <= 0.0 or (feet < _support_y - 0.5 and _lands_at_support(s)):
		# Easing up to a higher support pauses while Ash falls away from it (walking off the top
		# of a climb, a hop off the far side of a ledge, a wall-jump away), so the view never rises
		# while Ash drops; only a hop's way down toward it, onto that support or higher ground, does
		# not pause it (camera review 6, M2; 7, H1: told apart by the ground the fall lands on).
		_eased_y = maxf(_support_y, _eased_y - maxf(climbed, 0.0) - float(tuning.rest_rise_u))
	if _rest_y(s) < _eased_y:
		_raised = true


## The rest height: the eased support, raised with the feet once they rise more than the window
## above it and lowered with them again as they come back down.
func _rest_y(s: CameraSubject) -> float:
	return minf(_eased_y, s.box.end.y + float(tuning.support_window_u))


## Look-down while the player asks for it; the look ahead of a fall below the rest height, never
## reaching past the ground the fall will land on and dropped the moment the fall ends; and the
## look ahead of an up-dash.
func _update_looks(s: CameraSubject, anchor_drop: float) -> void:
	var look_before: float = _look
	var total_before: float = _look + _fall_lead
	var landed: bool = s.on_ground and not _look_grounded
	_look_grounded = s.on_ground
	if s.looking_down:
		_look_ticks += 1
		_look_on = _look_on or _look_ticks >= tuning.look_down_delay_frames
	else:
		_look_ticks = 0
		# Standing up, letting the stick go or a dash ends the look, and asking again waits the
		# whole delay, so nothing done in a fight pumps the view (camera review 6, H1); a crouched
		# strike or spell with the stick held down keeps it. In the air a look still showing carries on if
		# Ash lands asking for it (down held through a drop and the landing, whose first tick is
		# not yet a crouch; camera review 5, H3).
		if (s.on_ground and not landed and not s.look_held) or _look <= 0.0:
			_look_on = false
	# During a crouched strike or spell the look stays where it is: neither starts, grows or ends one
	# (BUILD.md section 5: "never during a strike"). So does a carried look on the landing tick.
	if not s.look_held and not (landed and _look_on):
		var look_target: float = float(tuning.look_down_u) if _look_on and s.looking_down else 0.0
		_look = move_toward(_look, look_target, float(tuning.look_speed_u))
	if not s.on_ground and s.vy < 0.0:
		# Leaving the ground upward (a jump) ends a look at once, like the end of a fall's: the
		# view, which eases, turns back to the player now rather than finishing the look while
		# they rise.
		_look = 0.0
		_look_on = false
	# The look starts once the feet fall below the last support (camera review 5, M4: from the
	# eased rest, which lags a climb, a drop over the top of a wall went 250 u with no look).
	var falling: bool = (
		not s.supported and s.vy > 0.0 and s.box.end.y >= minf(_rest_y(s), _support_y)
	)
	if falling:
		var fall_target: float = minf(s.vy * tuning.fall_lead_frames, maxf(s.ground_below, 0.0))
		_fall_lead = move_toward(_fall_lead, fall_target, float(tuning.fall_lead_speed_u))
		_fall_lead = minf(_fall_lead, maxf(s.ground_below, 0.0))
	else:
		# The fall is over (a landing, a cling, a bounce, a jump or a dash out of it): the look
		# goes at once, and the view, which eases, turns back toward the player with it.
		_fall_lead = 0.0
	if not s.on_ground and s.vy >= 0.0:
		# Dropping or walking off into the space looked at: the looks together shrink no faster
		# than the view's anchor goes down with Ash, so the view never turns up against the drop;
		# what is left of the look eases out once Ash stands again.
		var least: float = total_before - maxf(anchor_drop, 0.0)
		if _look + _fall_lead < least:
			_look = clampf(least - _fall_lead, _look, look_before)
	var up_target: float = float(tuning.up_dash_look_u) if s.dashing_up else 0.0
	_up_look = move_toward(_up_look, up_target, float(tuning.fall_lead_speed_u))


## A dead-zone hold: [param held] stays put while [param target] is within [param half] of it,
## and is pushed along once it is not.
static func _hold(held: float, target: float, half: float) -> float:
	if target > held + half:
		return target - half
	if target < held - half:
		return target + half
	return held


## [param c] eased into the bounds the view's centre may take: the room grown by the edge
## margin, so the player can come right up to a thin border wall without the margin having to
## push, or centred on that grown room where it is smaller than the view.
func _bounded(c: Vector2, room: Rect2) -> Vector2:
	var half: Vector2 = half_view()
	var grown: Rect2 = room.grow_individual(
		float(tuning.edge_margin_u),
		float(tuning.edge_margin_u + tuning.edge_slack_u),
		float(tuning.edge_margin_u),
		float(tuning.edge_margin_u + tuning.edge_slack_u)
	)
	var soft: float = float(tuning.edge_ease_u)
	return Vector2(
		_soft_clamp(c.x, grown.position.x + half.x, grown.end.x - half.x, soft),
		_soft_clamp(c.y, grown.position.y + half.y, grown.end.y - half.y, soft)
	)


## [param v] held within [param lo]..[param hi], easing into each bound over [param soft] units
## (continuous and smooth, with no corner): the view slows as it nears a room's edge instead of
## stopping dead, and reaches the bound itself, so a player against a room's outermost edge is
## exactly the margin from the view's. Within [param soft] of a bound the view moves at a share of
## the target's speed that falls linearly to nothing at [param soft] beyond it. Centred if the
## range is empty.
static func _soft_clamp(v: float, lo: float, hi: float, soft: float) -> float:
	if hi <= lo:
		return (lo + hi) * 0.5
	var e: float = minf(soft, (hi - lo) * 0.5)
	if e <= 0.0:
		return clampf(v, lo, hi)
	if v > hi - e:
		var past: float = minf(v - (hi - e), 2.0 * e)
		return hi - e + past - past * past / (4.0 * e)
	if v < lo + e:
		var short: float = minf((lo + e) - v, 2.0 * e)
		return lo + e - short + short * short / (4.0 * e)
	return v


## The backstop: moves [param c] the least it takes to keep [param player] the edge margin from
## every edge of the view, and counts it.
func _clear_player(c: Vector2, player: Rect2) -> Vector2:
	var out: Vector2 = _keep_player_clear(c, player, float(tuning.edge_margin_u))
	if not out.is_equal_approx(c):
		follow_misses += 1
	return out


## [param c] moved the least it takes to keep [param player] at least [param margin] from every
## edge of the view.
func _keep_player_clear(c: Vector2, player: Rect2, margin: float) -> Vector2:
	var half: Vector2 = half_view() - Vector2(margin, margin)
	var lo: Vector2 = player.end - half
	var hi: Vector2 = player.position + half
	return Vector2(clampf(c.x, lo.x, hi.x), clampf(c.y, lo.y, hi.y))


## The view's rectangle in units, between the last two ticks at [param alpha] (0..1).
func view_rect(alpha: float = 1.0) -> Rect2:
	var c: Vector2 = previous.lerp(center, alpha)
	return Rect2(c - half_view(), view_size)
