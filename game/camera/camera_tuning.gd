class_name CameraTuning
extends Resource
## The camera's feel values (BUILD.md section 5 feel rules: "60 u horizontal lead in the facing
## direction, dead zone of 40x30 u, vertical catches up at 0.08 lerp; look-down on crouch hold";
## section 15: "never shows the player within 80 units of the screen edge"; CLAUDE.md rule 9: these
## live here). Units are world units; per-tick values are per 60 Hz tick.

## Where the Wicks' movement tuning lives: [method validate] checks the margins against the
## largest collider among them.
const WICKS_ROOT: String = "res://content/wicks/"

## The view: 1920 x 1080 units at the native art scale (BUILD.md section 5).
@export var view_w_u: int = 1920
@export var view_h_u: int = 1080
## Horizontal lead in the facing direction, and how fast the lead swings when Ash turns (not in
## BUILD.md: 120 u of swing in half a second).
@export var lead_u: int = 60
@export var lead_speed_u: int = 4
## The lead follows a turn once Ash has gone this far the new way (the lead's whole swing), or kept
## facing it this many ticks (not in BUILD.md): turning back and forth in place, or striking either
## way in a fight, does not swing the view.
@export var lead_commit_u: int = 120
@export var lead_commit_frames: int = 20
## The dead zone the camera's focus may move in without the camera moving.
@export var dead_zone_w_u: int = 40
@export var dead_zone_h_u: int = 30
## Vertical catch-up per tick, per-mille of the distance outside the dead zone (0.08).
@export var vertical_lerp_permille: int = 80
## The most the view's vertical speed changes in one tick, in thousandths of a unit per tick per
## tick (not in BUILD.md): 3 u, so reaching dash speed takes at least 7 ticks and nothing jolts.
@export var vertical_accel_milli_u: int = 3000
## Look-down while crouch is held (not in BUILD.md): after this many frames, by this far, easing
## at this many units per tick.
@export var look_down_delay_frames: int = 20
@export var look_down_u: int = 200
@export var look_speed_u: int = 8
## Vertical rest: a player in the air within this far above the height they last stood, clung or
## bounced at does not move the camera (a full jump rises 176 u), so jumps do not bob it.
@export var support_window_u: int = 256
## How fast the rest height rises to a higher support, units per tick.
@export var rest_rise_u: int = 8
## Falling below that height, the camera looks this many frames of fall ahead, the look easing at
## up to this many units per tick; the ground is looked for along that many ticks of the fall's
## path.
@export var fall_lead_frames: int = 20
@export var fall_lead_speed_u: int = 16
## Dashing up, the camera looks this far ahead of the dash (not in BUILD.md: 120 u more head room,
## about six ticks of an up-dash), easing at the fall look's speed.
@export var up_dash_look_u: int = 120
## After a teleport the camera glides to the player over this many ticks, easing in and out,
## or longer if needed to keep the glide's peak speed within this many units per tick.
@export var glide_frames: int = 24
@export var glide_peak_u: int = 32
## A teleport glides from the old view only on an axis where that view leaves the player at least
## this far from its edge; nearer, the axis cuts to the follow (not in BUILD.md). The edge margin
## plus 80 u: a glide starts at rest and the follow trails a sudden move by up to the dead zone
## and its acceleration's lag, so a player who runs, dashes or up-dashes on at once would
## otherwise reach the margin before the glide got going.
@export var glide_cut_u: int = 160
## The view eases into the room's bounds (grown by the edge margin) over this many units.
@export var edge_ease_u: int = 160
## Vertically the bounds are grown this much further (not in BUILD.md: a tile). The vertical
## follow eases (the lerp and the acceleration limit), so it reaches a bound a little after the
## player does; this keeps the margin at an edge with no border tile (a room's opening onto the
## next) when the player falls onto it or climbs into it. Across, the follow is rigid.
@export var edge_slack_u: int = 32
## The player's box is never closer than this to the edge of the view (section 15).
@export var edge_margin_u: int = 80


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if view_w_u <= 0 or view_h_u <= 0:
		errors.append("the view must have a size")
	if lead_u < 0 or lead_speed_u <= 0 or look_speed_u <= 0:
		errors.append("lead and look speeds must be positive")
	if dead_zone_w_u < 0 or dead_zone_h_u < 0:
		errors.append("the dead zone cannot be negative")
	if vertical_lerp_permille <= 0 or vertical_lerp_permille > 1000:
		errors.append("vertical_lerp_permille must be in 1..1000")
	if support_window_u < 0 or fall_lead_frames < 0 or fall_lead_speed_u <= 0 or rest_rise_u <= 0:
		errors.append("rest and fall values cannot be negative")
	if glide_frames <= 0 or glide_peak_u <= 0:
		errors.append("glide_frames and glide_peak_u must be positive")
	if glide_cut_u < edge_margin_u:
		errors.append("glide_cut_u must be at least the edge margin")
	if vertical_accel_milli_u <= 0 or edge_ease_u < 0 or up_dash_look_u < 0:
		errors.append(
			"the acceleration must be positive, the edge ease and up-dash look not negative"
		)
	if look_down_delay_frames < 0 or look_down_u < 0 or lead_commit_frames < 0:
		errors.append("look-down and lead-commit values cannot be negative")
	if lead_commit_u < 0 or edge_slack_u < 0:
		errors.append("lead_commit_u and edge_slack_u cannot be negative")
	errors.append_array(_margin_errors(_largest_collider()))
	return errors


## The follow must never itself bring the player to the margin. Across, it holds the player at most
## the lead plus half the dead zone from the centre; down, the look-down or the up-dash look plus
## half the dead zone; falling at terminal speed, the fall look less the lerp's steady lag (the view
## trails a constant speed by speed / lerp).
func _margin_errors(player: Vector2i) -> PackedStringArray:
	var errors: PackedStringArray = []
	var half_w: int = view_w_u / 2 - edge_margin_u
	var half_h: int = view_h_u / 2 - edge_margin_u
	if lead_u + dead_zone_w_u / 2 + player.x / 2 > half_w:
		errors.append("lead and dead zone leave no room for the edge margin")
	if maxi(look_down_u, up_dash_look_u) + dead_zone_h_u / 2 + player.y > half_h:
		errors.append("the looks and dead zone leave no room for the edge margin")
	var terminal: float = _largest_terminal_u()
	var lag: float = terminal * 1000.0 / float(vertical_lerp_permille)
	if terminal * fall_lead_frames - lag + dead_zone_h_u / 2.0 + player.y > half_h:
		errors.append("the fall look outruns the view at terminal speed")
	return errors


## The largest collider (width, height in units) and the fastest fall (units per tick) among the
## Wicks' movement tuning.
func _largest_collider() -> Vector2i:
	var size := Vector2i.ZERO
	for m: MovementTuning in _wicks():
		size = size.max(Vector2i(m.width_u, m.height_u))
	return size


func _largest_terminal_u() -> float:
	var fastest: float = 0.0
	for m: MovementTuning in _wicks():
		fastest = maxf(fastest, float(m.terminal_ups) / 60.0)
	return fastest


static func _wicks() -> Array[MovementTuning]:
	var out: Array[MovementTuning] = []
	for dir: String in DirAccess.get_directories_at(WICKS_ROOT):
		var path: String = WICKS_ROOT + dir + "/movement.tres"
		if ResourceLoader.exists(path):
			out.append(load(path) as MovementTuning)
	return out
