class_name CombatView
extends Node2D
## Grey-box drawing of combat's world objects (docs/adr/0013), read from the simulation once per
## tick: Kindle's cone, Blaze's fire trails, kill embers flying home, the Charged strike's glow once
## the hold is long enough, and Mend's channel are spawned into the VFX budget manager each tick
## (CLAUDE.md rule 7: nothing is drawn without it, so a crowd's kills cannot draw without limit);
## the rectangles and outlines among them ([constant VfxBudget.UNDER]) are drawn here, under the
## enemies, where the trails must be (docs/adr/0013, draw order), from the budget's list. The blade
## (Kindling's tier: dull iron to white) is part of the drawn player and is drawn here between
## ticks, at the driver's interpolation factor (BUILD.md section 13). Placeholders until the art
## (Phase 2): plain shapes in the fire palette. Sparks, bursts, Radiance's ring and flashes are
## [HitFeedback]'s. It reads the simulation and never writes it.

## The blade's colour per Kindling tier (Ember, Flame, Blaze, White).
const HEAT: Array[Color] = [
	Color(0.45, 0.45, 0.5), Color(1.0, 0.55, 0.15), Color(1.0, 0.8, 0.3), Color(1.0, 1.0, 0.95)
]
const CONE := Color(1.0, 0.55, 0.1, 0.45)
const TRAIL := Color(1.0, 0.35, 0.05)
const EMBER := Color(1.0, 0.75, 0.3)
const CHARGE := Color(1.0, 1.0, 0.95)
const MEND := Color(0.5, 1.0, 0.6)

## The player view, whose interpolated box the blade follows.
var player_view: PlayerView
## The VFX budget the objects are spawned into (null: nothing but the blade is drawn).
var vfx: VfxBudget
var tuning: FeedbackTuning = load(FeedbackTuning.PATH) as FeedbackTuning
var _alpha: float = 1.0
var _tier: int = 0
var _facing: int = 1


func _ready() -> void:
	# Fire, the blade's heat and the Charged glow are light: the ambient never dims them.
	LightingRig.make_emissive(self)


## Reads the latest tick, and spawns its objects into the budget. Call it after the feedback has
## aged the budget for the tick ([method HitFeedback.on_tick]), so each is drawn from its first
## frame; every object lives one tick and is spawned again by the next.
func capture(sim: Simulation) -> void:
	var pl: Player = sim.player
	if pl == null:
		return
	_tier = pl.vitals.kindling.tier()
	_facing = pl.facing
	if vfx == null:
		return
	var b: Body = pl.body
	var box: Rect2 = DebugBoxes.units(Rect2i(b.left(), b.top(), b.right() - b.left(), b.height))
	for r: Rect2i in PlayerSpells.kindle_boxes(pl):
		vfx.spawn_rect(VfxBudget.AREA, VfxBudget.PLAYER, DebugBoxes.units(r), CONE)
	for t: FireTrail in sim.combat.trails:
		var fade: float = (
			tuning.trail_alpha * float(t.left) / float(sim.combat_params.blaze_trail_frames)
		)
		vfx.spawn_rect(VfxBudget.AREA, VfxBudget.BURN, DebugBoxes.units(t.box), Color(TRAIL, fade))
	for ember: KillEmber in sim.combat.embers:
		vfx.spawn(
			VfxBudget.EMBER,
			VfxBudget.AMBIENT,
			Vector2(ember.at) / Fx.SUB,
			Vector2.RIGHT,
			0,
			1.0,
			EMBER
		)
	var charged: AttackDef = pl.attacks.find("charged")
	if charged != null and pl.charge_held >= charged.charge_frames:
		vfx.spawn_rect(
			VfxBudget.OUTLINE,
			VfxBudget.PLAYER,
			box.grow(tuning.charge_grow_u),
			CHARGE,
			0,
			tuning.charge_width_px
		)
	if pl.spell == PlayerSpells.MEND:
		var h: float = (
			tuning.mend_h_u * clampf(float(pl.spell_frame) / float(pl.kit.mend_frames), 0.0, 1.0)
		)
		vfx.spawn_rect(
			VfxBudget.AREA,
			VfxBudget.PLAYER,
			Rect2(box.position.x - tuning.mend_gap_u, box.end.y - h, tuning.mend_w_u, h),
			MEND
		)


func show_at(alpha: float) -> void:
	_alpha = alpha
	queue_redraw()


func _draw() -> void:
	if vfx != null:
		for e: VfxBudget.Effect in vfx.effects:
			var c := Color(e.colour, e.colour.a * (1.0 - float(e.age) / float(e.life)))
			if e.kind == VfxBudget.AREA:
				draw_rect(e.rect, c)
			elif e.kind == VfxBudget.OUTLINE:
				draw_rect(e.rect, c, false, e.size)
	var box: Rect2 = player_view.box_at(_alpha) if player_view != null else Rect2()
	if box.size != Vector2.ZERO:
		# The blade: a short bar at the front edge, heating with Kindling.
		var front: float = box.end.x if _facing > 0 else box.position.x - tuning.blade_w_u
		draw_rect(
			Rect2(front, box.position.y + tuning.blade_drop_u, tuning.blade_w_u, tuning.blade_h_u),
			HEAT[_tier]
		)
