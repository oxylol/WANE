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
## BUILD.md section 12: "the game passes the Harding test at default settings", which fails more
## than 3 general flashes in any second. The screen-space rule above allows one in 3 ticks (20 a
## second), so a rolling window caps it: at most [member screen_flash_max] bright full-screen
## effects in any [member screen_flash_window_frames] ticks (a second at 60 Hz; slow motion only
## stretches it), whatever their priority. A refused flash leaves the hit's own burst and the
## enemy's outline cue to show it (presentation review r2, H1).
@export var screen_flash_window_frames: int = 60
@export var screen_flash_max: int = 3
## Not in BUILD.md: how many ticks each effect kind lives, every one "sub-10-frame" (section 10;
## Radiance's ring has its own below), and the one-tick marks (an ember, a telegraph) are not
## tuned.
@export var vfx_spark_frames: int = 6
@export var vfx_burst_frames: int = 9
@export var vfx_smear_frames: int = 5
## Not in BUILD.md: Radiance's ring, how many ticks it grows for and how far it reaches (the
## burst "lights the room": docs/adr/0013).
@export var radiance_ring_frames: int = 18
@export var radiance_ring_radius_u: float = 640.0

@export_group("HUD and screen effects")
## The grey-box Flame bar (docs/adr/0013): it shows the simulation's Flame at once, and a ghost
## segment shows the change: it trails a spend and leads a gain, closing this many Flame a tick;
## a gain flashes the bar for this many ticks (counting the tick of the gain; at a flash setting
## of 0 the bar outlines instead).
@export var hud_ghost_flame_per_tick: float = 4.0
@export var hud_gain_flash_frames: int = 12
## The chromatic split's offset and opacity, and the red vignette's depth (a share of the
## screen's shorter side) and opacity.
@export var split_offset_px: float = 6.0
@export var split_alpha: float = 0.18
@export var vignette_depth: float = 0.12
@export var vignette_alpha: float = 0.5

@export_group("HUD layout")
## The grey-box HUD's layout, in pixels: the margin from the screen's corner, a heart's width and
## the gap after it, the Flame bar's width and height and the gap before it, a Kindling pip's
## size, the gap after it and how far below the hearts the pips sit, a gain flash's outline, and
## the width of the bar's frame and cost marks.
@export var hud_margin_px: float = 32.0
@export var hud_heart_px: float = 28.0
@export var hud_heart_gap_px: float = 8.0
@export var hud_bar_w_px: float = 14.0
@export var hud_bar_h_px: float = 120.0
@export var hud_bar_gap_px: float = 8.0
@export var hud_pip_px: float = 14.0
@export var hud_pip_gap_px: float = 6.0
@export var hud_pip_drop_px: float = 14.0
@export var hud_gain_outline_px: float = 4.0
@export var hud_line_px: float = 2.0

@export_group("VFX shapes")
## How the budget draws its grey-box effects: a spark's strokes start this far (units) from the
## hit, travel this much further over its life, are this long and this wide (pixels); a burst's
## ring starts at and grows by these radii and is this wide; a smear's arc is this wide when it
## starts; an ember is this radius and a one-tick mark this big; Radiance's ring and a proc's mark
## are this wide.
@export var vfx_spark_start_u: float = 6.0
@export var vfx_spark_travel_u: float = 30.0
@export var vfx_spark_length_u: float = 12.0
@export var vfx_spark_width_px: float = 2.0
@export var vfx_burst_start_u: float = 8.0
@export var vfx_burst_growth_u: float = 40.0
@export var vfx_burst_width_px: float = 3.0
@export var vfx_smear_width_px: float = 10.0
@export var vfx_ember_radius_u: float = 5.0
@export var vfx_mark_size_u: float = 8.0
@export var vfx_ring_width_px: float = 6.0
@export var vfx_proc_width_px: float = 3.0

@export_group("Effect sizes")
## The size each feedback asks of its effect (the spark's, the burst's and the ring's scale; a
## smear is as long as the strike's reach, at least smear_min_radius_u).
@export var hit_spark_size: float = 1.0
@export var radiance_burst_size: float = 3.0
@export var radiance_ring_size: float = 1.0
@export var heal_burst_size: float = 0.8
@export var stagger_burst_size: float = 1.2
@export var charged_burst_size: float = 1.5
@export var parry_burst_size: float = 1.2
@export var finisher_burst_size: float = 1.0
@export var smear_min_radius_u: float = 1.0

@export_group("Combat view")
## The grey-box objects of combat's view (units): the blade's size and how far below the top of
## the box it hangs, the Charged glow's outline (grown round the box) and its width in pixels,
## Mend's channel bar (width, height at full, gap beside the box), and a Blaze trail's opacity
## when fresh.
@export var blade_w_u: float = 4.0
@export var blade_h_u: float = 14.0
@export var blade_drop_u: float = 18.0
@export var charge_grow_u: float = 3.0
@export var charge_width_px: float = 2.0
@export var mend_w_u: float = 4.0
@export var mend_h_u: float = 30.0
@export var mend_gap_u: float = 8.0
@export var trail_alpha: float = 0.5

@export_group("Sparks and sound")
## "Hit spark (3 variants)": 3 to 5 (section 10); the synth has a hit sound for each.
@export var spark_variants: int = 3
## Section 11: "No sound repeats identically: +-3% pitch and 3 to 5 variants on everything that
## plays more than once a second": the pitch spread every sound plays with.
@export var sound_pitch_spread: float = 0.03
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
	if shake_period_frames < 2:
		e.append("shake_period_frames must be at least 2")
	# BUILD.md s6 (3 spark variants) and s11 (3 to 5 variants; the synth makes HIT_VARIANTS).
	if spark_variants < 3 or spark_variants > Synth.HIT_VARIANTS:
		e.append("spark_variants must be 3 to %d (BUILD.md s6, s11)" % Synth.HIT_VARIANTS)
	# BUILD.md s12, the Harding limit: at most 3 full-screen flashes in 60 ticks.
	if screen_flash_window_frames < 60 or screen_flash_max < 1 or screen_flash_max > 3:
		e.append("the flash window must be at least 60 ticks and 1 to 3 flashes (BUILD.md s12)")
	# BUILD.md s6, s11: hit sound pitch randomized within +-3%.
	if sound_pitch_spread < 0.0 or sound_pitch_spread > 0.03:
		e.append("sound_pitch_spread must be 0 to 0.03 (BUILD.md s6, s11)")
	if vfx_spark_frames < 1 or vfx_burst_frames < 1 or vfx_smear_frames < 1:
		e.append("every effect kind lives at least one tick")
	for s: float in [charged_kill_time_scale, parry_time_scale]:
		if s <= 0.0 or s > 1.0:
			e.append("slow-motion scales must be in (0, 1]")
			break
	if flash_alpha <= 0.0 or flash_alpha > 1.0 or flash_default_scale < 0.0:
		e.append("flash_alpha must be in (0, 1] and the flash scale must not be negative")
	if hud_ghost_flame_per_tick <= 0.0 or hud_gain_flash_frames < 1:
		e.append("the Flame bar's ghost needs a speed and a gain flash a length")
	if split_offset_px < 0.0 or split_alpha < 0.0 or vignette_depth < 0.0 or vignette_alpha < 0.0:
		e.append("the split and the vignette must not be negative")
	for px: float in [
		hud_margin_px,
		hud_heart_px,
		hud_bar_w_px,
		hud_bar_h_px,
		hud_pip_px,
		hud_gain_outline_px,
		hud_line_px,
		vfx_spark_length_u,
		vfx_spark_width_px,
		vfx_burst_width_px,
		vfx_smear_width_px,
		vfx_ember_radius_u,
		vfx_mark_size_u,
		vfx_ring_width_px,
		vfx_proc_width_px,
		blade_w_u,
		blade_h_u,
		charge_width_px,
		mend_w_u,
		mend_h_u
	]:
		if px <= 0.0:
			e.append("every HUD, effect and combat view size must be positive")
			break
	for gap: float in [
		hud_heart_gap_px,
		hud_bar_gap_px,
		hud_pip_gap_px,
		hud_pip_drop_px,
		vfx_spark_start_u,
		vfx_spark_travel_u,
		vfx_burst_start_u,
		vfx_burst_growth_u,
		charge_grow_u,
		mend_gap_u,
		blade_drop_u
	]:
		if gap < 0.0:
			e.append("every gap, offset and travel must not be negative")
			break
	for size: float in [
		hit_spark_size,
		radiance_burst_size,
		radiance_ring_size,
		heal_burst_size,
		stagger_burst_size,
		charged_burst_size,
		parry_burst_size,
		finisher_burst_size,
		smear_min_radius_u
	]:
		if size <= 0.0:
			e.append("every effect size must be positive")
			break
	if trail_alpha <= 0.0 or trail_alpha > 1.0:
		e.append("trail_alpha must be in (0, 1]")
	return e
