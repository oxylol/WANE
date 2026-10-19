class_name EnemyView
extends Node2D
## Grey-box enemies, drawn from the simulation (a placeholder until the enemy art, BUILD.md
## sections 7 and 10). The body is a box coloured by state; it flashes white for the tuned frames
## after a hit (BUILD.md section 6, "white flash 2 f": [member FeedbackTuning.enemy_flash_frames]),
## at the player's flash setting's strength, and at 0% shows an outline colour change instead
## (section 12); a telegraph shows its silhouette change as a raised bar, white and straight for
## a parryable attack, red and jagged (a saw-toothed bar and a jagged outline) for an
## unparryable one (section 12: "parryable and unparryable differ in shape and sound as well as
## color"; section 15: distinguishable "with flashes set to 0"). The cue stays through the
## landing frame, the last of the parry window, and the live swing keeps its colour and outline
## while it is active. A staggered enemy slumps; a stunned one (a Votive's stun, docs/adr/0015)
## slumps in its own colour under a row of three small diamonds; health and poise show as two thin
## bars. Reads the simulation, never writes it.

const BODY := Color(0.55, 0.52, 0.48)
const STAGGERED := Color(0.4, 0.55, 0.75)
const STUNNED := Color(0.75, 0.68, 0.4)
const STUN_MARK := Color(1.0, 0.92, 0.55)
## The stun's diamonds: their half size and the gap above the body.
const STUN_MARK_PX: float = 4.0
const STUN_GAP_PX: float = 26.0
const DEAD := Color(0.35, 0.33, 0.3, 0.35)
const HIT_FLASH := Color(1.0, 1.0, 1.0)
## What a hit shows at a flash setting of 0: an outline colour change, no flash.
const HIT_OUTLINE := Color(0.3, 0.85, 1.0)
const WHITE_CUE := Color(1.0, 1.0, 1.0)
const RED_CUE := Color(1.0, 0.15, 0.1)
const WHITE_SWING := Color(1.0, 1.0, 1.0, 0.4)
const RED_SWING := Color(1.0, 0.15, 0.1, 0.45)
## The telegraph's bar: its gap above the body, how far it rises over the telegraph, its
## thickness; and the unparryable cue's teeth (width along the edge, depth).
const CUE_GAP_PX: float = 8.0
const CUE_RISE_PX: float = 24.0
const CUE_BAR_PX: float = 6.0
const JAG_TOOTH_PX: float = 8.0
const JAG_DEPTH_PX: float = 5.0
## Health is tan, never red: red is the unparryable cue (BUILD.md section 15), and the bar sits
## where a telegraph raises its cue bar.
const HP := Color(0.85, 0.75, 0.6)
const POISE := Color(0.9, 0.8, 0.3)

var tuning: FeedbackTuning
## The player's flash setting, 0..1 ([member HitFeedback.flash_scale]).
var flash_scale: float = 1.0
## What the latest tick showed of each enemy, and where each was after the tick before it.
var shown: Array[Shown] = []
var _alpha: float = 1.0
var _before: Array[Rect2] = []


## One enemy as the latest tick left it: a snapshot, so the view never holds the simulation's
## objects.
class Shown:
	var box: Rect2 = Rect2()
	var alive: bool = true
	var state: int = Enemy.IDLE
	var facing: int = -1
	var since_hit: int = 1000
	## The attack's telegraph progress (0..1) and whether it is parryable, while telegraphing.
	var telegraph: float = -1.0
	var parryable: bool = true
	var attack: Rect2 = Rect2()
	var hp: float = 1.0
	var poise: float = 1.0


func _init(p_tuning: FeedbackTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else load(FeedbackTuning.PATH) as FeedbackTuning
	flash_scale = tuning.flash_default_scale


## Reads the latest tick's enemies. (It takes the simulation rather than the enemy list: a typed
## Array[Enemy] passed in as a parameter leaked the core's scripts at exit in Godot 4.7.)
func capture(sim: Simulation) -> void:
	var count: int = sim.combat.enemies.size()
	var fresh: bool = count != shown.size()
	_before.clear()
	for s: Shown in shown:
		_before.append(s.box)
	shown.clear()
	for i: int in range(count):
		shown.append(_snapshot(sim.combat.enemies[i]))
	if fresh:
		_before.clear()
		for s: Shown in shown:
			_before.append(s.box)


static func _snapshot(e: Enemy) -> Shown:
	var s := Shown.new()
	var b: Body = e.body
	s.box = Rect2(
		float(b.left()) / Fx.SUB,
		float(b.top()) / Fx.SUB,
		float(b.right() - b.left()) / Fx.SUB,
		float(b.height) / Fx.SUB
	)
	s.alive = e.is_alive()
	s.state = e.state
	s.facing = e.facing
	s.since_hit = e.since_hit
	s.telegraph = cue_progress(e)
	if e.attack != null:
		s.parryable = e.attack.parryable
	var hit: Rect2i = e.attack_box()
	if hit.size != Vector2i.ZERO:
		s.attack = Rect2(Vector2(hit.position) / Fx.SUB, Vector2(hit.size) / Fx.SUB)
	s.hp = float(e.hp) / float(e.max_hp)
	s.poise = float(e.poise) / float(e.max_poise)
	return s


## How far the telegraph has risen, 0..1, while its cue shows: through the telegraph and on the
## landing frame (the strike's first, the last of the parry window), or -1.
static func cue_progress(e: Enemy) -> float:
	if e.attack == null:
		return -1.0
	if e.state == Enemy.TELEGRAPH:
		return float(e.attack_frame) / float(e.attack.telegraph)
	if e.state == Enemy.STRIKE and e.attack_frame == e.attack.landing_frame():
		return 1.0
	return -1.0


## The most the cue reaches above a body's top edge, in px (the F3 label is drawn above it).
static func cue_extent_px() -> float:
	return CUE_GAP_PX + CUE_RISE_PX + CUE_BAR_PX + JAG_DEPTH_PX


## The cue's raised bar for a body [param box] at telegraph [param progress]: a plain rectangle
## for a parryable attack, a saw-toothed one for an unparryable attack.
static func cue_bar(box: Rect2, progress: float, parryable: bool) -> PackedVector2Array:
	var top: float = box.position.y - CUE_GAP_PX - CUE_RISE_PX * progress - CUE_BAR_PX
	var x0: float = box.position.x
	var x1: float = box.end.x
	var base: float = top + CUE_BAR_PX
	var pts := PackedVector2Array([Vector2(x0, base), Vector2(x1, base)])
	if parryable:
		pts.append_array(PackedVector2Array([Vector2(x1, top), Vector2(x0, top)]))
		return pts
	var n: int = maxi(2, roundi((x1 - x0) / JAG_TOOTH_PX / 2.0) * 2)
	for k: int in range(n + 1):
		var x: float = lerpf(x1, x0, float(k) / float(n))
		pts.append(Vector2(x, top - (JAG_DEPTH_PX if k % 2 == 1 else 0.0)))
	return pts


## The cue's closed outline round [param box]: straight for a parryable attack, jagged
## (saw-toothed, pushed outward) for an unparryable one.
static func cue_outline(box: Rect2, parryable: bool) -> PackedVector2Array:
	var corners: Array[Vector2] = [
		box.position,
		Vector2(box.end.x, box.position.y),
		box.end,
		Vector2(box.position.x, box.end.y),
	]
	var pts := PackedVector2Array()
	if parryable:
		pts.append_array(PackedVector2Array(corners))
		pts.append(corners[0])
		return pts
	var outward: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for side: int in range(4):
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var n: int = maxi(2, roundi(a.distance_to(b) / JAG_TOOTH_PX / 2.0) * 2)
		for k: int in range(n):
			var p: Vector2 = a.lerp(b, float(k) / float(n))
			pts.append(p + outward[side] * (JAG_DEPTH_PX if k % 2 == 1 else 0.0))
	pts.append(pts[0])
	return pts


## The body colour [param base] as a hit leaves it: blended toward white for the tuned frames
## after the hit, by the flash setting (a setting of 0 never flashes).
func body_colour(s: Shown, base: Color) -> Color:
	if flash_scale > 0.0 and s.since_hit < tuning.enemy_flash_frames:
		return base.lerp(HIT_FLASH, flash_scale)
	return base


## True while the hit's outline colour change shows: the non-flash alternative at a flash
## setting of 0, for the same tuned frames.
func shows_hit_outline(s: Shown) -> bool:
	return flash_scale <= 0.0 and s.since_hit < tuning.enemy_flash_frames


## Shows the enemies at [param alpha] between the last two ticks.
func show_at(alpha: float) -> void:
	_alpha = alpha
	queue_redraw()


## Shows [param sim]'s enemies as they are now, with no interpolation (tools that draw one state).
## Three small diamonds in a row above a stunned enemy.
func _draw_stun_mark(box: Rect2) -> void:
	var y: float = box.position.y - STUN_GAP_PX
	var h: float = STUN_MARK_PX
	for k: int in range(3):
		var x: float = box.get_center().x + (k - 1) * h * 3.0
		var pts := PackedVector2Array(
			[Vector2(x, y - h), Vector2(x + h, y), Vector2(x, y + h), Vector2(x - h, y)]
		)
		draw_colored_polygon(pts, STUN_MARK)


func show_now(sim: Simulation) -> void:
	capture(sim)
	capture(sim)
	show_at(1.0)


func _draw() -> void:
	for i: int in range(shown.size()):
		var s: Shown = shown[i]
		_draw_enemy(s, Rect2(_before[i].position.lerp(s.box.position, _alpha), s.box.size))


func _draw_enemy(s: Shown, at: Rect2) -> void:
	var box: Rect2 = at
	if not s.alive:
		draw_rect(box, DEAD)
		return
	var colour: Color = BODY
	if s.state == Enemy.STAGGER or s.state == Enemy.STUN:
		colour = STAGGERED if s.state == Enemy.STAGGER else STUNNED
		box = Rect2(box.position + Vector2(0, box.size.y * 0.3), box.size * Vector2(1, 0.7))
	draw_rect(box, body_colour(s, colour))
	if s.state == Enemy.STUN:
		_draw_stun_mark(box)
	# The facing side.
	var eye_x: float = box.end.x - 8.0 if s.facing > 0 else box.position.x + 2.0
	draw_rect(Rect2(eye_x, box.position.y + 10.0, 6.0, 6.0), Color(0.1, 0.1, 0.12))
	if s.telegraph >= 0.0:
		var cue: Color = WHITE_CUE if s.parryable else RED_CUE
		draw_colored_polygon(cue_bar(box, s.telegraph, s.parryable), cue)
		draw_polyline(cue_outline(box, s.parryable), cue, 3.0)
	if s.attack.size != Vector2.ZERO:
		# The live swing keeps the cue's colour and shape through its active frames.
		draw_rect(s.attack, WHITE_SWING if s.parryable else RED_SWING)
		draw_polyline(
			cue_outline(s.attack, s.parryable), WHITE_CUE if s.parryable else RED_CUE, 2.0
		)
	if shows_hit_outline(s):
		draw_rect(box, HIT_OUTLINE, false, 3.0)
	var w: float = box.size.x
	var top: float = box.position.y - 16.0
	draw_rect(Rect2(box.position.x, top, w * s.hp, 3), HP)
	draw_rect(Rect2(box.position.x, top + 4, w * s.poise, 3), POISE)
