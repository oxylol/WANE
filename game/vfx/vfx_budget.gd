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
##   [member FeedbackTuning.vfx_screen_frames] ticks, and never more than
##   [member FeedbackTuning.screen_flash_max] in any
##   [member FeedbackTuning.screen_flash_window_frames] (the Harding test, section 12).
## The player's own feedback carries the highest priorities. A burn (a burn tick, a Blaze trail,
## the AoE) ranks below a Taper or spell hit, so it can never displace one.
## Enemy telegraphs do not go through the budget: [EnemyView] draws each cue on a layer above
## this one ([constant EnemyView.CUE_Z]), so no effect of any priority covers one, which is how a
## telegraph stays readable under 30 Votives (section 15).
##
## Phase 1 draws grey-box shapes: sparks are short strokes, bursts are rings, smears are arcs,
## embers are dots, Radiance's ring is a wide arc. Effects age once per simulation tick, before the
## tick's new effects are born (see [method HitFeedback.on_tick]), so each is drawn from age 0.

enum { SPARK, BURST, SMEAR, EMBER, TELEGRAPH, RING }
## Priorities, low to high. SPELL is Radiance's burst and ring, which must show whatever spark
## the cell holds.
enum { AMBIENT, PROC, BURN, HIT, TELEGRAPH_PRIORITY, PLAYER, SPELL }
## Screen-space effects: the white flash and the chromatic split are bright; the vignette is not.
enum { SCREEN_FLASH, SCREEN_SPLIT, SCREEN_VIGNETTE }

const BRIGHT: Array[int] = [SPARK, BURST, SMEAR, RING]
const SCREEN_BRIGHT: Array[int] = [SCREEN_FLASH, SCREEN_SPLIT]
const COLOURS: Dictionary[int, Color] = {
	SPARK: Color(1.0, 0.95, 0.8),
	BURST: Color(1.0, 0.75, 0.4),
	SMEAR: Color(1.0, 1.0, 1.0, 0.7),
	EMBER: Color(1.0, 0.55, 0.15),
	TELEGRAPH: Color(1.0, 1.0, 1.0),
	RING: Color(1.0, 0.95, 0.8),
}
## Half the angle a smear's arc sweeps, in radians.
const SMEAR_HALF_ANGLE: float = 1.1
## Ticks a one-tick mark (an ember, a telegraph) lives.
const MARK_FRAMES: int = 1


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
## When each bright full-screen effect was admitted, within the Harding window.
var _screen_flashes: Array[int] = []
## The bright effect that last claimed each cell.
var _cells: Dictionary[Vector2i, Effect] = {}
## When, and at what priority, the screen's bright effect was last admitted.
var _screen_born: int = -1000000
var _screen_priority: int = AMBIENT


func _init(p_tuning: FeedbackTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else load(FeedbackTuning.PATH) as FeedbackTuning


## Spawns an effect, in [param tint] if one is given (its alpha above 0) or the kind's colour;
## false if the budget refused it. Effects of the same non-zero [param group] share their cell.
func spawn(
	kind: int,
	priority: int,
	at: Vector2,
	dir: Vector2 = Vector2.RIGHT,
	variant: int = 0,
	size: float = 1.0,
	tint: Color = Color(0, 0, 0, 0),
	group: int = 0
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
				_displace(holder)
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
	e.life = lifetime(kind)
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
	# The Harding window: no priority buys a fourth flash in a second.
	while (
		not _screen_flashes.is_empty()
		and _tick - _screen_flashes[0] >= tuning.screen_flash_window_frames
	):
		_screen_flashes.remove_at(0)
	if _screen_flashes.size() >= tuning.screen_flash_max:
		refused += 1
		return false
	if _tick - _screen_born < tuning.vfx_screen_frames:
		if _screen_priority >= priority:
			refused += 1
			return false
		displaced += 1
	_screen_born = _tick
	_screen_priority = priority
	_screen_flashes.append(_tick)
	return true


## Ticks an effect of [param kind] lives (every proc VFX is "sub-10-frame", section 10).
## Radiance's ring is a spell's, not a proc's: its lifetime and reach are
## [member FeedbackTuning.radiance_ring_frames] and [member FeedbackTuning.radiance_ring_radius_u].
func lifetime(kind: int) -> int:
	match kind:
		SPARK:
			return tuning.vfx_spark_frames
		BURST:
			return tuning.vfx_burst_frames
		SMEAR:
			return tuning.vfx_smear_frames
		RING:
			return tuning.radiance_ring_frames
	return MARK_FRAMES


## Removes [param holder] and the rest of its hit's group from the budget (one hit, one bright
## thing: its smear and burst do not stay behind beside the newcomer that displaced its spark).
func _displace(holder: Effect) -> void:
	if holder.group == 0:
		effects.erase(holder)
		displaced += 1
		return
	var kept: Array[Effect] = []
	for e: Effect in effects:
		if e.group == holder.group:
			displaced += 1
		else:
			kept.append(e)
	effects = kept


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
				# Centred on the swing's origin, [member Effect.size] the radius in units.
				draw_arc(
					e.at,
					e.size,
					mid - SMEAR_HALF_ANGLE,
					mid + SMEAR_HALF_ANGLE,
					16,
					c,
					10.0 * (1.0 - t)
				)
			EMBER:
				draw_circle(e.at, 5.0 * e.size, c)
			TELEGRAPH:
				draw_rect(Rect2(e.at - Vector2(4, 4), Vector2(8, 8)), c)
			RING:
				draw_arc(e.at, tuning.radiance_ring_radius_u * t, 0.0, TAU, 64, c, 6.0)


## Three stroke patterns, fanned around the hit direction.
func _draw_spark(e: Effect, t: float, c: Color) -> void:
	var count: int = 4 + e.variant
	var spread: float = 0.9 + 0.3 * e.variant
	for k: int in range(count):
		var a: float = e.dir.angle() + spread * (float(k) / float(count - 1) - 0.5)
		var d := Vector2.from_angle(a)
		var from: Vector2 = e.at + d * (6.0 + 30.0 * t) * e.size
		draw_line(from, from + d * 12.0 * (1.0 - t) * e.size, c, 2.0)
