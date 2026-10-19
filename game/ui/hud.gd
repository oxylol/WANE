class_name Hud
extends CanvasLayer
## The grey-box HUD: BUILD.md section 12's conventional fallback ("5 heart icons, top-left";
## "A vertical bar beside the hearts" for Flame), plus the Kindling tier, until the diegetic
## versions (the ember's size, the blade's glow) arrive with the art.
## - The Flame bar's solid fill is the simulation's Flame on the tick it changes, never more or
##   less (presentation review r2, M2: an eased fill showed Flame Ash did not hold, and invited
##   spells that fizzle). A ghost segment shows the change: it trails a spend (dim, above the
##   fill) and leads a gain (bright, the part not yet settled), closing at a tuned rate. Marks
##   at the spells' costs make "can I cast" readable from the bar.
## - A gain, and a kill's ember arriving whether or not it adds anything (the bar may be full),
##   flash the bar ("the Flame bar visibly reacts", section 15), scaled by the flash setting;
##   at 0 the bar is outlined instead.
## - The Kindling tier is four pips, lit up to the tier. There is no text in the HUD: the only
##   font in the repository is Godot's embedded one, which docs/LICENSES.md allows for the F3
##   overlay alone; the shipped UI font arrives in Phase 2 with its own row and ADR.
## Every number comes from content/feedback.tres.

const HEART := Color(0.95, 0.35, 0.3)
const HEART_EMPTY := Color(0.3, 0.2, 0.2)
const FLAME := Color(1.0, 0.6, 0.2)
const FLAME_GAIN := Color(1.0, 0.95, 0.7)
const FLAME_GHOST := Color(1.0, 0.6, 0.2, 0.35)
const FRAME := Color(0.9, 0.9, 0.85, 0.6)
const FRAME_GAIN := Color(1.0, 0.95, 0.7)
const COST_MARK := Color(0.05, 0.05, 0.06, 0.9)
const TIER_COLOURS: Array[Color] = [
	Color(0.55, 0.55, 0.6), Color(1.0, 0.6, 0.2), Color(1.0, 0.35, 0.15), Color(1.0, 1.0, 1.0)
]
const PIP_OFF := Color(0.2, 0.2, 0.22)
const MARGIN_PX: float = 32.0
const HEART_PX: float = 28.0
const BAR_W_PX: float = 14.0
const BAR_H_PX: float = 120.0
const PIP_PX: float = 14.0
const PIP_GAP_PX: float = 6.0
const GAIN_OUTLINE_PX: float = 4.0

var vitals: Vitals
var tuning: FeedbackTuning = load(FeedbackTuning.PATH) as FeedbackTuning
## The player's flash setting, 0..1 ([member HitFeedback.flash_scale]).
var flash_scale: float = 1.0
## The Flame costs the bar marks (the player's spells'), in Flame.
var spell_costs: Array[int] = []
## The ghost segment's end: where the bar was, closing on the value, and the gain flash's ticks
## left.
var ghost_flame: float = 0.0
var gain_flash: int = 0

var _canvas: Node2D
var _last_flame: int = -1


func _ready() -> void:
	layer = 80
	_canvas = Node2D.new()
	add_child(_canvas)
	_canvas.draw.connect(_draw_hud)


## Called once per simulation tick; [param events] are that tick's.
func on_tick(events: SimEvents = null) -> void:
	if vitals == null:
		return
	var value: int = vitals.flame.value
	if _last_flame < 0:
		# The first tick: the bar starts at what the player holds.
		_last_flame = value
		ghost_flame = float(value)
	gain_flash = maxi(gain_flash - 1, 0)
	if value > _last_flame or (events != null and events.has(SimEvents.EMBER_HOME)):
		gain_flash = tuning.hud_gain_flash_frames
	_last_flame = value
	ghost_flame = move_toward(ghost_flame, float(value), tuning.hud_ghost_flame_per_tick)
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_hud() -> void:
	if vitals == null:
		return
	var h: Hearts = vitals.hearts
	for i: int in range(h.max_hearts):
		var at := Vector2(MARGIN_PX + i * (HEART_PX + 8.0), MARGIN_PX)
		var c: Color = HEART if i < h.current else HEART_EMPTY
		_canvas.draw_colored_polygon(_heart(at, HEART_PX), c)
	var bar_x: float = MARGIN_PX + h.max_hearts * (HEART_PX + 8.0) + 8.0
	_draw_flame(Rect2(bar_x, MARGIN_PX, BAR_W_PX, BAR_H_PX))
	var tier: int = vitals.kindling.tier()
	for t: int in range(TIER_COLOURS.size()):
		var at := Vector2(MARGIN_PX + t * (PIP_PX + PIP_GAP_PX), MARGIN_PX + HEART_PX + 14.0)
		_canvas.draw_rect(Rect2(at, Vector2(PIP_PX, PIP_PX)), TIER_COLOURS[t] if t <= tier else PIP_OFF)


## The Flame bar in [param bar]: the fill at the true value, the ghost, the cost marks, the frame.
func _draw_flame(bar: Rect2) -> void:
	var cap: float = float(vitals.flame.cap)
	var value: float = BAR_H_PX * float(vitals.flame.value) / cap
	var ghost: float = BAR_H_PX * ghost_flame / cap
	var flashing: bool = gain_flash > 0 and flash_scale > 0.0
	var solid: Color = FLAME.lerp(FLAME_GAIN, flash_scale) if gain_flash > 0 else FLAME
	var base: float = minf(value, ghost)
	_canvas.draw_rect(Rect2(bar.position.x, bar.end.y - base, BAR_W_PX, base), solid)
	if ghost > value:
		# A spend: what was there, not what is.
		_canvas.draw_rect(
			Rect2(bar.position.x, bar.end.y - ghost, BAR_W_PX, ghost - value), FLAME_GHOST
		)
	elif value > ghost:
		# A gain: the part that is already there, shown brighter until it settles.
		_canvas.draw_rect(
			Rect2(bar.position.x, bar.end.y - value, BAR_W_PX, value - ghost), FLAME_GAIN
		)
	for cost: int in spell_costs:
		var y: float = bar.end.y - BAR_H_PX * float(cost) / cap
		_canvas.draw_line(Vector2(bar.position.x, y), Vector2(bar.end.x, y), COST_MARK, 2.0)
	_canvas.draw_rect(bar, FRAME, false, 2.0)
	if gain_flash > 0 and not flashing:
		# Flashes at 0%: the bar is outlined, not lit.
		_canvas.draw_rect(bar.grow(GAIN_OUTLINE_PX * 0.5), FRAME_GAIN, false, GAIN_OUTLINE_PX)


## A heart shape [param s] pixels wide with its top-left at [param at].
static func _heart(at: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k: int in range(24):
		var t: float = TAU * float(k) / 24.0
		var x: float = 16.0 * pow(sin(t), 3)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(at + Vector2(s * 0.5, s * 0.45) + Vector2(x, y) * (s / 34.0))
	return pts
