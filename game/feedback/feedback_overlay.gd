class_name FeedbackOverlay
extends CanvasLayer
## The screen-space part of the hit feedback, read from a [HitFeedback] each frame: the parry's
## full-screen white flash, the charged hit's chromatic split and the red vignette when the
## player is hit (BUILD.md section 6, "Hit feedback"). It draws only what the VFX budget admitted
## ([method VfxBudget.claim_screen], through [HitFeedback]): CLAUDE.md rule 7. A flash lasts one
## tick whatever the flash setting; the setting scales its opacity (0 draws nothing). The split's
## offset and opacity and the vignette's depth and opacity are in content/feedback.tres. Grey-box
## versions; the lighting pass and the final post effects replace them in Phase 2.

const FLASH := Color(1.0, 1.0, 1.0, 1.0)
const SPLIT_RED := Color(1.0, 0.1, 0.1)
const SPLIT_CYAN := Color(0.1, 1.0, 1.0)
const VIGNETTE := Color(0.85, 0.05, 0.05)

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
		var d: float = minf(size.x, size.y) * feedback.tuning.vignette_depth
		var bands: int = feedback.tuning.vignette_bands
		for k: int in range(bands):
			var c := Color(
				VIGNETTE, feedback.tuning.vignette_alpha * a * (1.0 - float(k) / float(bands))
			)
			var inset: float = d * float(k) / float(bands)
			var band: float = d / float(bands)
			_canvas.draw_rect(Rect2(0, inset, size.x, band), c)
			_canvas.draw_rect(Rect2(0, size.y - inset - band, size.x, band), c)
			_canvas.draw_rect(Rect2(inset, 0, band, size.y), c)
			_canvas.draw_rect(Rect2(size.x - inset - band, 0, band, size.y), c)
	if feedback.chroma_ticks > 0:
		var k: float = feedback.flash_scale * feedback.tuning.split_alpha
		var off: float = feedback.tuning.split_offset_px
		_canvas.draw_rect(Rect2(Vector2(-off, 0), size), Color(SPLIT_RED, k))
		_canvas.draw_rect(Rect2(Vector2(off, 0), size), Color(SPLIT_CYAN, k))
	if feedback.flash_ticks > 0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(FLASH, flash_opacity()))


## How opaque the full-screen flash is now: the tuned opacity at the flash setting, 0 when no
## flash is running.
func flash_opacity() -> float:
	if feedback == null or feedback.flash_ticks <= 0:
		return 0.0
	return feedback.flash_scale * feedback.tuning.flash_alpha
