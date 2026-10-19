class_name VfxBudget
extends Node2D
## The VFX budget manager (CLAUDE.md rule 7: "Nothing is drawn without the VFX budget manager";
## BUILD.md section 10: "one bright thing per 100x100 u region per 3 frames, enforced by a VFX
## budget manager that culls the least important"). Every effect is spawned through
## [method spawn] with a priority:
## - A bright effect (spark, burst, smear) claims its 100 u cell for 3 ticks. Another bright
##   effect there in that time replaces it only if it is more important, and is refused if not.
## - At most [member FeedbackTuning.vfx_capacity] effects live at once; a new one displaces the
##   oldest less important effect, or is refused.
## - Effects of one [param group] (one hit's spark, smear and burst) are one bright thing: they
##   share the cell and none refuses another.
## - Screen-space effects (the full-screen flash, the chromatic split, the vignette) are admitted
##   through [method claim_screen]: at most one bright one per
##   [member FeedbackTuning.vfx_screen_frames] ticks.
## The player's own feedback and enemy telegraphs carry the highest priorities, which is how the
## screen stays readable under 30 Votives (section 15). A burn (a burn tick, a Blaze trail, the
## AoE) ranks below a Taper or spell hit, so it can never displace one.
##
## Phase 1 draws grey-box shapes: sparks are short strokes, bursts are rings, smears are arcs,
## embers are dots, Radiance's ring is a wide arc, and a Votive's proc is its look's shape
## ([ProcLook]: under ten frames, at [constant PROC] priority, so a hit or a telegraph always wins
## its cell; docs/adr/0015). Effects age once per simulation tick, before the tick's new effects
## are born (see [method HitFeedback.on_tick]), so each is drawn from age 0.

enum { SPARK, BURST, SMEAR, EMBER, TELEGRAPH, RING, PROC_MARK }
## Priorities, low to high. SPELL is Radiance's burst and ring, which must show whatever spark
## the cell holds.
enum { AMBIENT, PROC, BURN, HIT, TELEGRAPH_PRIORITY, PLAYER, SPELL }
## Screen-space effects: the white flash and the chromatic split are bright; the vignette is not.
enum { SCREEN_FLASH, SCREEN_SPLIT, SCREEN_VIGNETTE }

const BRIGHT: Array[int] = [SPARK, BURST, SMEAR, RING, PROC_MARK]
const SCREEN_BRIGHT: Array[int] = [SCREEN_FLASH, SCREEN_SPLIT]
const COLOURS: Dictionary[int, Color] = {
	SPARK: Color(1.0, 0.95, 0.8),
	BURST: Color(1.0, 0.75, 0.4),
	SMEAR: Color(1.0, 1.0, 1.0, 0.7),
	EMBER: Color(1.0, 0.55, 0.15),
	TELEGRAPH: Color(1.0, 1.0, 1.0),
	RING: Color(1.0, 0.95, 0.8),
	PROC_MARK: Color(1.0, 1.0, 1.0),
}
## Ticks each kind lives. Radiance's ring is a spell's, not a proc's: its lifetime and reach are
## [member FeedbackTuning.radiance_ring_frames] and [member FeedbackTuning.radiance_ring_radius_u].
## A proc's mark lives its look's frames ([member ProcLook.frames], "sub-10-frame", section 10),
## given to [method spawn].
const LIFETIMES: Dictionary[int, int] = {
	SPARK: 6, BURST: 9, SMEAR: 5, EMBER: 1, TELEGRAPH: 1, PROC_MARK: ProcLook.MAX_FRAMES
}


class Effect:
	var kind: int = SPARK
	var priority: int = HIT
	var at: Vector2 = Vector2.ZERO
	var dir: Vector2 = Vector2.RIGHT
	var variant: int = 0
	var colour: Color = Color.WHITE
	var age: int = 0
	var life: int = 1
	var size: float = 1.0
	var born: int = 0
	## Effects of one non-zero group (one hit's feedback) share a cell.
	var group: int = 0


var tuning: FeedbackTuning
var effects: Array[Effect] = []
## Effects refused or displaced since the start (for the F3 overlay and the stress benchmark).
var refused: int = 0
var displaced: int = 0
var _tick: int = 0
## The bright effect that last claimed each cell.
var _cells: Dictionary[Vector2i, Effect] = {}
## When, and at what priority, the screen's bright effect was last admitted.
var _screen_born: int = -1000000
var _screen_priority: int = AMBIENT


func _init(p_tuning: FeedbackTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else load(FeedbackTuning.PATH) as FeedbackTuning


## Spawns an effect, in [param tint] if one is given (its alpha above 0) or the kind's colour, for
## [param life] ticks if given (above 0) or the kind's lifetime; false if the budget refused it.
## Effects of the same non-zero [param group] share their cell.
func spawn(
	kind: int,
	priority: int,
	at: Vector2,
	dir: Vector2 = Vector2.RIGHT,
	variant: int = 0,
	size: float = 1.0,
	tint: Color = Color(0, 0, 0, 0),
	group: int = 0,
	life: int = 0
) -> bool:
	var cell := Vector2i((at / float(tuning.vfx_cell_u)).floor())
	var shares: bool = false
	if BRIGHT.has(kind):
		var holder: Effect = _cells.get(cell, null)
		if holder != null and _tick - holder.born < tuning.vfx_cell_frames:
			if group != 0 and holder.group == group:
				shares = true
			elif holder.priority >= priority:
				refused += 1
				return false
			else:
				effects.erase(holder)
				displaced += 1
	if effects.size() >= tuning.vfx_capacity:
		var victim: int = _least_important(priority)
		if victim < 0:
			refused += 1
			return false
		effects.remove_at(victim)
		displaced += 1
	var e := Effect.new()
	e.kind = kind
	e.priority = priority
	e.at = at
	e.dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	e.variant = variant
	e.colour = tint if tint.a > 0.0 else COLOURS[kind]
	if life > 0:
		e.life = life
	else:
		e.life = tuning.radiance_ring_frames if kind == RING else LIFETIMES[kind]
	e.size = size
	e.born = _tick
	e.group = group
	effects.append(e)
	if BRIGHT.has(kind) and not shares:
		_cells[cell] = e
	return true


## Admits a screen-space effect of [param kind] ([constant SCREEN_FLASH], [constant SCREEN_SPLIT]
## or [constant SCREEN_VIGNETTE]) at [param priority], or refuses it (false). The bright ones (the
## full-screen flash and the chromatic split share one slot) are admitted at most once per
## [member FeedbackTuning.vfx_screen_frames] ticks, unless the newcomer is more important than
## the one holding the slot; the vignette is a dark edge, not a flash, and always shows (a new
## one restarts the running one).
func claim_screen(kind: int, priority: int = PLAYER) -> bool:
	if not SCREEN_BRIGHT.has(kind):
		return true
	if _tick - _screen_born < tuning.vfx_screen_frames:
		if _screen_priority >= priority:
			refused += 1
			return false
		displaced += 1
	_screen_born = _tick
	_screen_priority = priority
	return true


## Ages every effect by one tick and drops the finished ones.
func step() -> void:
	_tick += 1
	for e: Effect in effects:
		e.age += 1
	effects.assign(effects.filter(func(e: Effect) -> bool: return e.age < e.life))
	for cell: Vector2i in _cells.keys():
		if _tick - _cells[cell].born >= tuning.vfx_cell_frames:
			_cells.erase(cell)
	queue_redraw()


func clear() -> void:
	effects.clear()
	_cells.clear()
	_screen_born = -1000000
	queue_redraw()


## The index of the oldest of the least important effects below [param priority], or -1.
func _least_important(priority: int) -> int:
	var best: int = -1
	for i: int in range(effects.size()):
		var e: Effect = effects[i]
		if e.priority >= priority:
			continue
		if best < 0 or e.priority < effects[best].priority:
			best = i
	return best


func _draw() -> void:
	for e: Effect in effects:
		var t: float = float(e.age) / float(e.life)
		var c := Color(e.colour, e.colour.a * (1.0 - t))
		match e.kind:
			SPARK:
				_draw_spark(e, t, c)
			BURST:
				draw_arc(e.at, (8.0 + 40.0 * t) * e.size, 0.0, TAU, 24, c, 3.0)
			SMEAR:
				var mid: float = e.dir.angle()
				draw_arc(e.at, 56.0 * e.size, mid - 1.1, mid + 1.1, 16, c, 10.0 * (1.0 - t))
			EMBER:
				draw_circle(e.at, 5.0 * e.size, c)
			TELEGRAPH:
				draw_rect(Rect2(e.at - Vector2(4, 4), Vector2(8, 8)), c)
			RING:
				draw_arc(e.at, tuning.radiance_ring_radius_u * t, 0.0, TAU, 64, c, 6.0)
			PROC_MARK:
				_draw_proc(e, t, c)


## A proc's mark ([ProcLook.Shape] in [member Effect.variant]), [member Effect.size] units across
## at full size: it springs out over its first third and fades as it holds.
func _draw_proc(e: Effect, t: float, c: Color) -> void:
	var r: float = e.size * minf(1.0, 0.4 + 1.8 * t)
	var w: float = 3.0
	match e.variant:
		ProcLook.Shape.RING:
			draw_arc(e.at, r, 0.0, TAU, 48, c, w)
		ProcLook.Shape.CROSS:
			draw_line(e.at - Vector2(r, 0), e.at + Vector2(r, 0), c, w)
			draw_line(e.at - Vector2(0, r), e.at + Vector2(0, r), c, w)
		ProcLook.Shape.DIAMOND:
			_draw_polygon_line(e.at, r, 4, 0.0, c, w)
		ProcLook.Shape.SPOKES:
			for k: int in range(6):
				var d := Vector2.from_angle(TAU * k / 6.0)
				draw_line(e.at + d * r * 0.4, e.at + d * r, c, w)
		ProcLook.Shape.SQUARE:
			_draw_polygon_line(e.at, r, 4, PI / 4.0, c, w)
		ProcLook.Shape.TRIANGLE:
			_draw_polygon_line(e.at, r, 3, -PI / 2.0, c, w)
		ProcLook.Shape.CHEVRON:
			var up := Vector2(0, -r * 0.5)
			for k: int in range(2):
				var o := Vector2(0, r * 0.5 * k)
				draw_polyline(
					PackedVector2Array(
						[
							e.at + o + Vector2(-r, r * 0.5),
							e.at + o + up,
							e.at + o + Vector2(r, r * 0.5)
						]
					),
					c,
					w
				)
		_:
			_draw_polygon_line(e.at, r, 10, -PI / 2.0, c, w, 0.45)


## A closed outline of [param n] points round [param at], [param r] out, turned [param turn]; with
## [param inner] below 1 every other point is pulled in to that share of [param r] (a star).
func _draw_polygon_line(
	at: Vector2, r: float, n: int, turn: float, c: Color, w: float, inner: float = 1.0
) -> void:
	var pts := PackedVector2Array()
	for k: int in range(n + 1):
		var reach: float = r if k % 2 == 0 else r * inner
		pts.append(at + Vector2.from_angle(turn + TAU * k / float(n)) * reach)
	draw_polyline(pts, c, w)


## Three stroke patterns, fanned around the hit direction.
func _draw_spark(e: Effect, t: float, c: Color) -> void:
	var count: int = 4 + e.variant
	var spread: float = 0.9 + 0.3 * e.variant
	for k: int in range(count):
		var a: float = e.dir.angle() + spread * (float(k) / float(count - 1) - 0.5)
		var d := Vector2.from_angle(a)
		var from: Vector2 = e.at + d * (6.0 + 30.0 * t) * e.size
		draw_line(from, from + d * 12.0 * (1.0 - t) * e.size, c, 2.0)
