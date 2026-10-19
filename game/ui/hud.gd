class_name Hud
extends CanvasLayer
## The grey-box HUD: BUILD.md section 12's conventional fallback ("5 heart icons, top-left";
## "A vertical bar beside the hearts" for Flame), plus the Kindling tier, until the diegetic
## versions (the ember's size, the blade's glow) arrive with the art. The Flame bar eases toward
## its value and flashes on a gain, so "the Flame bar visibly reacts" (section 15) when a kill's
## ember arrives. Text is never under 18 px.

const HEART := Color(0.95, 0.35, 0.3)
const HEART_EMPTY := Color(0.3, 0.2, 0.2)
const FLAME := Color(1.0, 0.6, 0.2)
const FLAME_GAIN := Color(1.0, 0.95, 0.7)
const FRAME := Color(0.9, 0.9, 0.85, 0.6)
const TIER_COLOURS: Array[Color] = [
	Color(0.55, 0.55, 0.6), Color(1.0, 0.6, 0.2), Color(1.0, 0.35, 0.15), Color(1.0, 1.0, 1.0)
]
const MARGIN_PX: float = 32.0
const HEART_PX: float = 28.0
const BAR_W_PX: float = 14.0
const BAR_H_PX: float = 120.0
const FONT_SIZE: int = 20
## Ticks the bar flashes for, counting the tick of the gain.
const GAIN_FLASH_TICKS: int = 12

var vitals: Vitals
## The bar's drawn fill, easing toward the value, and the flash after a gain.
var shown_flame: float = 0.0
var gain_flash: int = 0

var _canvas: Node2D
var _last_flame: int = 0


func _ready() -> void:
	layer = 80
	_canvas = Node2D.new()
	add_child(_canvas)
	_canvas.draw.connect(_draw_hud)


## Called once per simulation tick.
func on_tick() -> void:
	if vitals == null:
		return
	var value: int = vitals.flame.value
	gain_flash = maxi(gain_flash - 1, 0)
	if value > _last_flame:
		gain_flash = GAIN_FLASH_TICKS
	_last_flame = value
	shown_flame = move_toward(shown_flame, float(value), 4.0)
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_hud() -> void:
	if vitals == null:
		return
	var font: Font = ThemeDB.fallback_font
	var h: Hearts = vitals.hearts
	for i: int in range(h.max_hearts):
		var at := Vector2(MARGIN_PX + i * (HEART_PX + 8.0), MARGIN_PX)
		var c: Color = HEART if i < h.current else HEART_EMPTY
		_canvas.draw_colored_polygon(_heart(at, HEART_PX), c)
	var bar_x: float = MARGIN_PX + h.max_hearts * (HEART_PX + 8.0) + 8.0
	var bar := Rect2(bar_x, MARGIN_PX, BAR_W_PX, BAR_H_PX)
	var fill: float = BAR_H_PX * shown_flame / float(vitals.flame.cap)
	_canvas.draw_rect(
		Rect2(bar.position.x, bar.end.y - fill, BAR_W_PX, fill),
		FLAME_GAIN if gain_flash > 0 else FLAME
	)
	_canvas.draw_rect(bar, FRAME, false, 2.0)
	var k: Kindling = vitals.kindling
	var tier: int = k.tier()
	var text: String = "%s %d" % [Kindling.TIER_NAMES[tier], k.hits]
	var at_text := Vector2(MARGIN_PX, MARGIN_PX + HEART_PX + 30.0)
	_canvas.draw_string(
		font, at_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TIER_COLOURS[tier]
	)


## A heart shape [param s] pixels wide with its top-left at [param at].
static func _heart(at: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k: int in range(24):
		var t: float = TAU * float(k) / 24.0
		var x: float = 16.0 * pow(sin(t), 3)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(at + Vector2(s * 0.5, s * 0.45) + Vector2(x, y) * (s / 34.0))
	return pts
