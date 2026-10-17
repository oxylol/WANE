class_name KitParams
extends RefCounted
## [KitTuning] compiled to sub-pixels and frames.

var hurt_inset_x: int = 0
var hurt_inset_top: int = 0
var hurt_inset_bottom: int = 0
var hazard_invuln_frames: int = 0
var safe_ground_margin: int = 0
var toss_speed: int = 0
var toss_startup: int = 0
var toss_invuln: int = 0
var toss_cooldown: int = 0
var toss_flight: int = 0
var toss_linger: int = 0
var toss_buffer: int = 0
## The teleport fit search: its reach in whole units, and the candidate offsets as (x, y) pairs
## in sub-pixels, nearest first.
var toss_fit_reach_u: int = 0
var toss_fit_offsets: PackedInt32Array = PackedInt32Array()
