class_name PlayerViewTuning
extends Resource
## How the drawn player follows its collider (presentation only; the core never reads it).

const PATH: String = "res://content/player_view.tres"

## Frames over which the drawn player catches up with a corner-correction nudge (not in
## BUILD.md, whose checklist asks for "the corner-correction nudge is invisible"). A step up or
## down a lip, a lift onto a ledge's corner or a slide round a ceiling corner moves the collider
## up to 18 u in one tick; the drawn player stays where it was on that tick and eases onto the
## collider over these frames with a smoothstep, so it never snaps.
@export var nudge_ease_frames: int = 3


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if nudge_ease_frames < 1 or nudge_ease_frames > 30:
		e.append("nudge_ease_frames must be 1 to 30")
	return e
