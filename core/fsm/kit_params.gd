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
## Kindle (BUILD.md section 6, Spells).
var kindle_cost: int = 0
var kindle_length: int = 0
var kindle_damage: int = 0
var kindle_startup: int = 0
var kindle_active: int = 0
var kindle_recovery: int = 0
var kindle_cancel_from: int = 0
var kindle_sections: int = 0
var kindle_width_near: int = 0
var kindle_width_far: int = 0
## Burning, after Kindle ignites an enemy.
var burn_frames: int = 0
var burn_period: int = 0
var burn_damage: int = 0
## Mend.
var mend_cost: int = 0
var mend_frames: int = 0
var mend_hearts: int = 0
## Radiance.
var radiance_cost: int = 0
var radiance_push: int = 0
var radiance_light: int = 0
var radiance_startup: int = 0
var radiance_recovery: int = 0


func kindle_total() -> int:
	return kindle_startup + kindle_active + kindle_recovery


func radiance_total() -> int:
	return radiance_startup + 1 + radiance_recovery
