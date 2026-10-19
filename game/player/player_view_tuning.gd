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
## How far behind the collider the drawn player may fall while it eases, as a percentage of the
## run's largest nudge (task 5 review 2, H1). Its catch-up speed changes by a set share of the
## nudge a tick, so a staircase of lips run up faster than it catches up would leave it ever
## further behind; past this it moves by the excess at once. 200: only a dash up a staircase three
## lips a tick comes near it.
@export var nudge_lag_percent: int = 200


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if nudge_ease_frames < 1 or nudge_ease_frames > 30:
		e.append("nudge_ease_frames must be 1 to 30")
	if nudge_lag_percent < 100 or nudge_lag_percent > 400:
		e.append("nudge_lag_percent must be 100 to 400")
	return e
