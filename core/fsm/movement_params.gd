class_name MovementParams
extends RefCounted
## [MovementTuning] compiled to sub-pixels per tick (ADR-0003). Read-only after compile; the
## field comments give the units.

## Half the collider width; standing and crouching heights (sub-pixels).
var half_w: int = 0
var height: int = 0
var crouch_height: int = 0
## Stick deflection (of 127) that counts as a direction.
var stick_threshold: int = 0
## Ground: max speed (sp/tick), acceleration and deceleration (sp/tick^2), turnaround keep (%).
var run_speed: int = 0
var run_accel: int = 0
var run_decel: int = 0
var turn_keep_percent: int = 0
var turn_frames: int = 0
## Corner correction distances (sp).
var corner_lift: int = 0
var corner_slide: int = 0
## Jump (sp/tick, sp/tick^2, frames).
var jump_speed: int = 0
var jump_min_frames: int = 0
var gravity_rise: int = 0
var gravity_fall: int = 0
var release_gravity: int = 0
var apex_hang_permille: int = 0
var apex_hang_speed: int = 0
var apex_hang_start: int = 0
var apex_hang_frames: int = 0
var terminal: int = 0
var coyote_frames: int = 0
var jump_buffer_frames: int = 0
var dash_buffer_frames: int = 0
var attack_buffer_frames: int = 0
var air_jumps: int = 0
var air_jump_speed: int = 0
var air_accel: int = 0
var air_decel: int = 0
## Dash (sp/tick, frames, percent).
var dash_speed: int = 0
var dash_frames: int = 0
var dash_carry_frames: int = 0
var dash_carry_percent: int = 0
var dash_invuln_first: int = 0
var dash_invuln_last: int = 0
var dash_ground_cooldown: int = 0
var air_dashes: int = 0
var dash_jump_first: int = 0
var dash_jump_last: int = 0
var dash_jump_keep_percent: int = 0
var dash_attack_cancel_from: int = 0
## Wall (sp/tick, sp, frames).
var wall_slide_speed: int = 0
var wall_slide_frames: int = 0
var wall_jump_reach: int = 0
var wall_coyote_frames: int = 0
var wall_jump_up: int = 0
var wall_jump_away: int = 0
var wall_jump_lock: int = 0
var wall_kick_up: int = 0
var wall_kick_away: int = 0
var wall_kick_lock: int = 0
var ledge_grab: int = 0
## Pogo (sp/tick, frames).
var pogo_bounce: int = 0
var pogo_chain_frame: int = 0
