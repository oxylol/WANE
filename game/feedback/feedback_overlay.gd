class_name FeedbackOverlay
extends CanvasLayer
## The screen-space part of the hit feedback, read from a [HitFeedback] each frame: the parry's
## full-screen white flash, the charged hit's chromatic split and the red vignette when the
## player is hit (BUILD.md section 6, "Hit feedback"). It draws only what the VFX budget admitted
## ([method VfxBudget.claim_screen], through [HitFeedback]): CLAUDE.md rule 7. A flash lasts one
## tick whatever the flash setting; the setting scales its opacity (0 draws nothing). Grey-box
## versions; the lighting pass and the final post effects replace them in Phase 2.

const FLASH := Color(1.0, 1.0, 1.0, 1.0)
const SPLIT_RED := Color(1.0, 0.1, 0.1, 0.18)
const SPLIT_CYAN := Color(0.1, 1.0, 1.0, 0.18)
const VIGNETTE := Color(0.85, 0.05, 0.05)
## The vignette's depth, as a share of the screen's shorter side.
const VIGNETTE_DEPTH: float = 0.12

var feedback: HitFeedback
var _canvas: Node2D


func _ready() -> void:
	layer = 90
	_canvas = Node2D.new()
	add_child(_canvas)
	_canvas.draw.connect(_draw_effects)


func _process(_delta: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_effects() -> void:
	if feedback == null:
		return
	var size: Vector2 = _canvas.get_viewport_rect().size
	if feedback.vignette_ticks > 0:
		var a: float = float(feedback.vignette_ticks) / float(feedback.tuning.vignette_frames)
		var d: float = minf(size.x, size.y) * VIGNETTE_DEPTH
		for k: int in range(4):
			var c := Color(VIGNETTE, 0.5 * a * (1.0 - float(k) / 4.0))
			var inset: float = d * float(k) / 4.0
			var band: float = d / 4.0
			_canvas.draw_rect(Rect2(0, inset, size.x, band), c)
			_canvas.draw_rect(Rect2(0, size.y - inset - band, size.x, band), c)
			_canvas.draw_rect(Rect2(inset, 0, band, size.y), c)
			_canvas.draw_rect(Rect2(size.x - inset - band, 0, band, size.y), c)
	if feedback.chroma_ticks > 0:
		var k: float = feedback.flash_scale
		_canvas.draw_rect(Rect2(Vector2(-6, 0), size), Color(SPLIT_RED, SPLIT_RED.a * k))
		_canvas.draw_rect(Rect2(Vector2(6, 0), size), Color(SPLIT_CYAN, SPLIT_CYAN.a * k))
	if feedback.flash_ticks > 0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(FLASH, flash_opacity()))


## How opaque the full-screen flash is now: the tuned opacity at the flash setting, 0 when no
## flash is running.
func flash_opacity() -> float:
	if feedback == null or feedback.flash_ticks <= 0:
		return 0.0
	return feedback.flash_scale * feedback.tuning.flash_alpha
