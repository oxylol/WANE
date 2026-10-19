class_name FeedbackTuning
extends Resource
## The presentation half of BUILD.md section 6's hit-feedback table: screen shake, flashes, slow
## motion, rumble, sparks and sound variation. (Hitstop and knockback change the simulation, so
## they live in content/combat/combat.tres.) Presentation may use floats; units are world units
## and simulation ticks.

const PATH: String = "res://content/feedback.tres"

@export_group("Screen shake")
## "Screen shake has a global scaler in settings and is capped at 6 u. Shake is directional
## (along the hit) not random." Section 15: "Screen shake at the default 50% never moves the frame
## more than 3 units". Amplitudes are at 100%; the setting defaults to 50%.
@export var shake_cap_u: float = 6.0
@export var shake_default_scale: float = 0.5
@export var finisher_shake_u: float = 1.5
@export var finisher_shake_frames: int = 4
@export var charged_shake_u: float = 3.0
@export var charged_shake_frames: int = 6
@export var parry_shake_u: float = 2.0
@export var parry_shake_frames: int = 6
@export var player_hit_shake_u: float = 4.0
@export var player_hit_shake_frames: int = 8
@export var kill_shake_u: float = 1.0
@export var kill_shake_frames: int = 3
## Not in BUILD.md: ticks per back-and-forth of a directional shake.
@export var shake_period_frames: int = 4

@export_group("Flashes")
## "white flash 2 f" on a light hit; "Full-screen white flash 1 f" on a parry; "Brief chromatic
## split 1 f" on a charged hit. A setting scales flashes to 0 (section 15).
@export var enemy_flash_frames: int = 2
@export var parry_flash_frames: int = 1
@export var chromatic_frames: int = 1
@export var flash_default_scale: float = 1.0
## Not in BUILD.md: how opaque the full-screen flash is at the full setting. A solid white frame
## hid the parried attack and Ash on the very frame the parry is read (task 6 contact sheet);
## at 0.55 both show through it (docs/feel_log/2026-10-19-task6-combat.md).
@export var flash_alpha: float = 0.55
## Not in BUILD.md: the red vignette pulse when the player is hit.
@export var vignette_frames: int = 20

@export_group("Slow motion")
## "slow-motion 0.8x for 8 f on kill" (charged), "time to 0.5x for 6 f" (parry).
@export var charged_kill_time_scale: float = 0.8
@export var charged_kill_slow_frames: int = 8
@export var parry_time_scale: float = 0.5
@export var parry_slow_frames: int = 6

@export_group("Rumble")
## "controller rumble 0.6 for 100 ms" when the player is hit.
@export var player_hit_rumble: float = 0.6
@export var player_hit_rumble_ms: int = 100

@export_group("VFX budget")
## BUILD.md section 10: "one bright thing per 100x100 u region per 3 frames, enforced by a VFX
## budget manager that culls the least important". Not in BUILD.md: how many effects may live at
## once in all.
@export var vfx_cell_u: int = 100
@export var vfx_cell_frames: int = 3
@export var vfx_capacity: int = 256
## Not in BUILD.md: the screen-space rule, at most one bright full-screen effect (flash or
## chromatic split) per this many ticks, the same window as a cell's.
@export var vfx_screen_frames: int = 3
## Not in BUILD.md: Radiance's ring, how many ticks it grows for and how far it reaches (the
## burst "lights the room": docs/adr/0013).
@export var radiance_ring_frames: int = 18
@export var radiance_ring_radius_u: float = 640.0

@export_group("Sparks and sound")
## "Hit spark (3 variants), hit sound pitch randomized +-3%".
@export var spark_variants: int = 3
@export var hit_pitch_spread: float = 0.03
## BUILD.md section 11: "Hard cap of 24 simultaneous voices; a priority system drops the
## furthest, quietest sound first."
@export var voice_cap: int = 24


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if shake_cap_u < 0.0 or shake_default_scale < 0.0 or shake_default_scale > 1.0:
		e.append("the shake cap must not be negative and the default scale must be in 0..1")
	if shake_default_scale * player_hit_shake_u > 3.0 + 0.0001:
		e.append("at the default scale a player hit would shake more than section 15's 3 units")
	for f: float in [
		finisher_shake_u, charged_shake_u, parry_shake_u, player_hit_shake_u, kill_shake_u
	]:
		if f < 0.0 or f > shake_cap_u:
			e.append("shake amplitudes must be within 0 and the cap")
			break
	if vfx_cell_u <= 0 or vfx_cell_frames < 1 or vfx_capacity < 1 or vfx_screen_frames < 1:
		e.append("the VFX budget needs a cell size, a window and a capacity")
	if radiance_ring_frames < 1 or radiance_ring_radius_u <= 0.0:
		e.append("Radiance's ring needs a lifetime and a reach")
	if enemy_flash_frames < 0:
		e.append("the enemy's hit flash must not be negative")
	if voice_cap < 1:
		e.append("there must be at least one voice")
	if shake_period_frames < 2 or spark_variants < 1:
		e.append("shake_period_frames must be at least 2 and there must be a spark variant")
	for s: float in [charged_kill_time_scale, parry_time_scale]:
		if s <= 0.0 or s > 1.0:
			e.append("slow-motion scales must be in (0, 1]")
			break
	if flash_alpha <= 0.0 or flash_alpha > 1.0 or flash_default_scale < 0.0:
		e.append("flash_alpha must be in (0, 1] and the flash scale must not be negative")
	return e
