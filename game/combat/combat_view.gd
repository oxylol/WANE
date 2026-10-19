class_name CombatView
extends Node2D
## Grey-box drawing of combat's world objects (docs/adr/0013), read from the simulation once per
## tick and drawn between ticks at the driver's interpolation factor (BUILD.md section 13): Kindle's
## cone, Blaze's fire trails, kill embers flying home, the blade's heat
## (Kindling's tier: dull iron to white), the Charged strike's glow once the hold is long enough,
## and Mend's channel. Placeholders until the art (Phase 2): plain shapes in the fire palette.
## Decorative effects (sparks, bursts, Radiance's ring, flashes) are [HitFeedback]'s, through the
## VFX budget manager (CLAUDE.md rule 7). It reads the simulation and never writes it.

## The blade's colour per Kindling tier (Ember, Flame, Blaze, White).
const HEAT: Array[Color] = [
	Color(0.45, 0.45, 0.5), Color(1.0, 0.55, 0.15), Color(1.0, 0.8, 0.3), Color(1.0, 1.0, 0.95)
]
const CONE := Color(1.0, 0.55, 0.1, 0.45)
const TRAIL := Color(1.0, 0.35, 0.05)
const EMBER := Color(1.0, 0.75, 0.3)
const CHARGE := Color(1.0, 1.0, 0.95)
const MEND := Color(0.5, 1.0, 0.6)

## The player view, whose interpolated box the cone and the blade follow.
var player_view: PlayerView
var _alpha: float = 1.0
## The cone's sections relative to the player's centre (so they follow the drawn player).
var _cone: Array[Rect2] = []
var _trails: Array[Rect2] = []
var _trail_left: PackedFloat32Array = PackedFloat32Array()
## Each kill ember's position before and after the latest tick, keyed by where it was released.
var _ember_before: Dictionary[Vector2i, Vector2] = {}
var _ember_after: Dictionary[Vector2i, Vector2] = {}
var _tier: int = 0
var _facing: int = 1
var _charged: bool = false
var _mend: float = -1.0


## Reads the latest tick.
func capture(sim: Simulation) -> void:
	var pl: Player = sim.player
	if pl == null:
		return
	var b: Body = pl.body
	var centre := Vector2(float(b.x), float(b.y - b.height / 2)) / Fx.SUB
	_cone.clear()
	for r: Rect2i in PlayerSpells.kindle_boxes(pl):
		var u: Rect2 = DebugBoxes.units(r)
		_cone.append(Rect2(u.position - centre, u.size))
	_trails.clear()
	_trail_left.clear()
	for t: FireTrail in sim.combat.trails:
		_trails.append(DebugBoxes.units(t.box))
		_trail_left.append(float(t.left) / float(sim.combat_params.blaze_trail_frames))
	_ember_before = _ember_after
	_ember_after = {}
	for ember: KillEmber in sim.combat.embers:
		_ember_after[ember.start] = Vector2(ember.at) / Fx.SUB
	_tier = pl.vitals.kindling.tier()
	_facing = pl.facing
	var charged: AttackDef = pl.attacks.find("charged")
	_charged = charged != null and pl.charge_held >= charged.charge_frames
	_mend = -1.0
	if pl.spell == PlayerSpells.MEND:
		_mend = float(pl.spell_frame) / float(pl.kit.mend_frames)


func show_at(alpha: float) -> void:
	_alpha = alpha
	queue_redraw()


func _draw() -> void:
	var box: Rect2 = player_view.box_at(_alpha) if player_view != null else Rect2()
	var centre: Vector2 = box.get_center()
	for r: Rect2 in _cone:
		draw_rect(Rect2(centre + r.position, r.size), CONE)
	for i: int in range(_trails.size()):
		draw_rect(_trails[i], Color(TRAIL, 0.5 * _trail_left[i]))
	for key: Vector2i in _ember_after:
		var to: Vector2 = _ember_after[key]
		var from: Vector2 = _ember_before.get(key, to)
		draw_circle(from.lerp(to, _alpha), 5.0, EMBER)
	if box.size != Vector2.ZERO:
		# The blade: a short bar at the front edge, heating with Kindling.
		var front: float = box.end.x if _facing > 0 else box.position.x - 4.0
		draw_rect(Rect2(front, box.position.y + 18.0, 4.0, 14.0), HEAT[_tier])
		if _charged:
			draw_rect(box.grow(3.0), CHARGE, false, 2.0)
		if _mend >= 0.0:
			var h: float = 30.0 * clampf(_mend, 0.0, 1.0)
			draw_rect(Rect2(box.position.x - 8.0, box.end.y - h, 4.0, h), MEND)
