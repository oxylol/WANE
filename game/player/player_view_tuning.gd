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

## Landing squash (BUILD.md section 10 Animation: "squash on landing (3 f, 110% wide)", section 5
## Landing: "a 3 f squash animation that does not block input"). The drawn player only: the core's
## body and boxes are never scaled, and nothing waits for it. It starts on the tick of the core's
## land event, scaled by the impact speed.
@export var landing_squash_frames: int = 3
## The widest the drawn player gets on a full landing, as a percentage of its width; its height
## shrinks by the same factor, so the area is kept.
@export var landing_squash_width_percent: int = 110
## The impact speed (units a second) under which a landing is not squashed at all (a step off a
## lip), and at which and over which it is squashed all the way: between them the squash grows
## smoothly with the speed.
@export var landing_min_impact_ups: int = 300
@export var landing_full_impact_ups: int = 800

## Apex stretch (BUILD.md section 10: "stretch at jump apex (2 f, 94% wide)"). It begins on the
## tick the rise ends, swells and fades over these frames, and is scaled by how fast the jump
## rose (an air jump or a wall kick, which rise slower, stretch less).
@export var apex_stretch_frames: int = 2
@export var apex_stretch_width_percent: int = 94
## The rise speed (units a second) at which the stretch is full: the jump's take-off speed.
@export var apex_full_rise_ups: int = 900

## The grey-box mark on the facing side: its size and where it sits in the box (units from the
## edge it faces, and down from the top), and the ember's radius when it is out.
@export var eye_size_u: float = 4.0
@export var eye_edge_gap_u: float = 2.0
@export var eye_drop_u: float = 6.0
@export var ember_radius_u: float = 6.0
@export var invulnerable_outline_u: float = 2.0


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if nudge_ease_frames < 1 or nudge_ease_frames > 30:
		e.append("nudge_ease_frames must be 1 to 30")
	if nudge_lag_percent < 100 or nudge_lag_percent > 400:
		e.append("nudge_lag_percent must be 100 to 400")
	if landing_squash_frames < 1 or landing_squash_frames > 12:
		e.append("landing_squash_frames must be 1 to 12")
	if landing_squash_width_percent < 100 or landing_squash_width_percent > 150:
		e.append("landing_squash_width_percent must be 100 to 150")
	if landing_min_impact_ups < 0 or landing_full_impact_ups <= landing_min_impact_ups:
		e.append("landing impacts must run from a minimum 0 or more up to a larger full impact")
	if apex_stretch_frames < 1 or apex_stretch_frames > 12:
		e.append("apex_stretch_frames must be 1 to 12")
	if apex_stretch_width_percent < 70 or apex_stretch_width_percent > 100:
		e.append("apex_stretch_width_percent must be 70 to 100")
	if apex_full_rise_ups <= 0:
		e.append("apex_full_rise_ups must be positive")
	if eye_size_u <= 0.0 or eye_edge_gap_u < 0.0 or eye_drop_u < 0.0:
		e.append("the eye needs a positive size and offsets of 0 or more")
	if ember_radius_u <= 0.0 or invulnerable_outline_u <= 0.0:
		e.append("ember_radius_u and invulnerable_outline_u must be positive")
	return e
