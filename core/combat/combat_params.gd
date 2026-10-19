class_name CombatParams
extends RefCounted
## [CombatTuning] compiled to sub-pixels and ticks.

var flame_cap: int = 0
var flame_per_hit: int = 0
var flame_per_pogo: int = 0
var flame_per_parry: int = 0
var flame_per_kill: int = 0
var kill_ember_frames: int = 0
var hearts: int = 0
## Hits at which each Kindling tier starts (Ember, Flame, Blaze, White), and its damage bonus.
var kindling_tiers: PackedInt32Array = PackedInt32Array()
var kindling_bonus_permille: PackedInt32Array = PackedInt32Array()
var kindling_per_parry: int = 0
var white_charged_every: int = 0
var blaze_trail_frames: int = 0
var blaze_trail_damage: int = 0
var blaze_aoe_radius: int = 0
var blaze_aoe_damage: int = 0
var hitstop_light: int = 0
var hitstop_finisher: int = 0
var hitstop_charged: int = 0
var hitstop_parry: int = 0
var hitstop_player_hit: int = 0
var hitstop_kill: int = 0
var weight_from_damage: int = 0
var weight_damage_per_frame: int = 0
var hitstop_cap: int = 0
var player_hit_knockback: int = 0
var player_hit_invuln_frames: int = 0
var player_hit_knock_frames: int = 0
var hazard_damage: int = 0
var recoil_frames: int = 0
var parry_window_frames: int = 0
var parry_knockback: int = 0
var parry_stagger_frames: int = 0
var poise_stagger_frames: int = 0
var telegraph_cue_frames: int = 0
var finisher_launch: int = 0
var knockback_decel: int = 0


## Hitstop for a hit of [param damage] whose kind gives [param base] frames: "damage above 30
## adds 1 f of hitstop per 10 damage, capped at 8".
func hitstop_for(base: int, damage: int) -> int:
	var extra: int = 0
	if damage > weight_from_damage:
		extra = (damage - weight_from_damage) / weight_damage_per_frame
	return mini(base + extra, maxi(base, hitstop_cap))
