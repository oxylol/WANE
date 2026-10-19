class_name CombatTuning
extends Resource
## The combat rules shared by every Wick (BUILD.md section 6: Flame, Kindling, parry, the
## hit-feedback table's hitstop and knockback, enemy poise). A Wick's own strikes are its
## [AttackSet]; its spells are in its kit. Units as BUILD.md gives them; [method compile] converts
## to sub-pixels per tick. Presentation-only feedback (shake, flashes, slow motion) lives in
## content/feedback.tres.

const PATH: String = "res://content/combat/combat.tres"

@export_group("Flame")
## "A bar of 100. Each Taper hit grants 11 Flame; each pogo 8; each parry 33."
@export var flame_cap: int = 100
@export var flame_per_hit: int = 11
@export var flame_per_pogo: int = 8
@export var flame_per_parry: int = 33
## Not in BUILD.md ("Enemy ember released as a particle that flies to the player (+Flame)"): what
## a kill's ember grants when it arrives, and the ticks its flight takes, wherever the player is
## (section 15: "reaches the player within 20 frames").
@export var flame_per_kill: int = 11
@export var kill_ember_frames: int = 16

@export_group("Hearts")
## "the player's 5 base hearts".
@export var hearts: int = 5

@export_group("Kindling")
## Hits at which each tier starts: Flame 8, Blaze 20, White 40.
@export var kindling_flame_at: int = 8
@export var kindling_blaze_at: int = 20
@export var kindling_white_at: int = 40
## Extra damage per tier, per-mille: +10%, +20%, +30%.
@export var kindling_flame_bonus_permille: int = 100
@export var kindling_blaze_bonus_permille: int = 200
@export var kindling_white_bonus_permille: int = 300
## A parry adds 5 hits.
@export var kindling_per_parry: int = 5
## White: every 10th hit is an automatic Charged strike.
@export var white_charged_every: int = 10
## Blaze: "attacks leave a 10 f fire trail that damages; finishers cause a small AoE". The trail's
## damage and the AoE's size and damage are not in BUILD.md.
@export var blaze_trail_frames: int = 10
@export var blaze_trail_damage: int = 4
@export var blaze_aoe_radius_u: int = 96
@export var blaze_aoe_damage: int = 8

@export_group("Hitstop")
## "Light hit 2 f both", "Finisher 4 f both", "Charged 6 f both", "Parry 12 f both", "Player hit
## 8 f player only", "Kill 3 f".
@export var hitstop_light: int = 2
@export var hitstop_finisher: int = 4
@export var hitstop_charged: int = 6
@export var hitstop_parry: int = 12
@export var hitstop_player_hit: int = 8
@export var hitstop_kill: int = 3
## "damage above 30 adds 1 f of hitstop per 10 damage, capped at 8".
@export var weight_from_damage: int = 30
@export var weight_damage_per_frame: int = 10
@export var hitstop_cap: int = 8

@export_group("Player hit")
## "300 u/s away, 20 f of invulnerability".
@export var player_hit_knockback_ups: int = 300
@export var player_hit_invuln_frames: int = 20
## Not in BUILD.md: the frames the knockback holds the stick's sideways push off, after the
## hitstop (docs/adr/0013). Any action ends it.
@export var player_hit_knock_frames: int = 12
## Not in BUILD.md: the hearts a hazard costs (docs/adr/0013).
@export var hazard_damage: int = 1

@export_group("Parry")
## "Press attack in the 8 f before an enemy's hit lands", "enemy knocked back 200 u/s and
## staggered for 40 f".
@export var parry_window_frames: int = 8
@export var parry_knockback_ups: int = 200
@export var parry_stagger_frames: int = 40

@export_group("Enemies")
## "at 0 the enemy staggers for 30 f and resets".
@export var poise_stagger_frames: int = 30
## BUILD.md section 11: "every telegraph has a sound 20 f before the hit". The cue is sent when the
## swing lands in exactly this many ticks; from then the attack is committed, so hitstop cannot
## delay it and the cue keeps its word (task 6 review, M4).
@export var telegraph_cue_frames: int = 20
## The finisher "launches light enemies": how fast up (not in BUILD.md).
@export var finisher_launch_ups: int = 600
## Not in BUILD.md: how fast an enemy's knockback bleeds off, u/s per second.
@export var knockback_decel_ups2: int = 2400


func compile() -> CombatParams:
	var c := CombatParams.new()
	c.flame_cap = flame_cap
	c.flame_per_hit = flame_per_hit
	c.flame_per_pogo = flame_per_pogo
	c.flame_per_parry = flame_per_parry
	c.flame_per_kill = flame_per_kill
	c.kill_ember_frames = kill_ember_frames
	c.hearts = hearts
	c.kindling_tiers = PackedInt32Array(
		[0, kindling_flame_at, kindling_blaze_at, kindling_white_at]
	)
	c.kindling_bonus_permille = PackedInt32Array(
		[
			0,
			kindling_flame_bonus_permille,
			kindling_blaze_bonus_permille,
			kindling_white_bonus_permille
		]
	)
	c.kindling_per_parry = kindling_per_parry
	c.white_charged_every = white_charged_every
	c.blaze_trail_frames = blaze_trail_frames
	c.blaze_trail_damage = blaze_trail_damage
	c.blaze_aoe_radius = Fx.units(blaze_aoe_radius_u)
	c.blaze_aoe_damage = blaze_aoe_damage
	c.hitstop_light = hitstop_light
	c.hitstop_finisher = hitstop_finisher
	c.hitstop_charged = hitstop_charged
	c.hitstop_parry = hitstop_parry
	c.hitstop_player_hit = hitstop_player_hit
	c.hitstop_kill = hitstop_kill
	c.weight_from_damage = weight_from_damage
	c.weight_damage_per_frame = weight_damage_per_frame
	c.hitstop_cap = hitstop_cap
	c.player_hit_knockback = Fx.speed(player_hit_knockback_ups)
	c.player_hit_invuln_frames = player_hit_invuln_frames
	c.player_hit_knock_frames = player_hit_knock_frames
	c.hazard_damage = hazard_damage
	c.parry_window_frames = parry_window_frames
	c.parry_knockback = Fx.speed(parry_knockback_ups)
	c.parry_stagger_frames = parry_stagger_frames
	c.poise_stagger_frames = poise_stagger_frames
	c.telegraph_cue_frames = telegraph_cue_frames
	c.finisher_launch = Fx.speed(finisher_launch_ups)
	c.knockback_decel = Fx.accel(knockback_decel_ups2)
	return c


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if flame_cap <= 0 or hearts <= 0:
		e.append("the Flame cap and the hearts must be positive")
	for v: int in [flame_per_hit, flame_per_pogo, flame_per_parry, flame_per_kill]:
		if v < 0:
			e.append("Flame gains must not be negative")
			break
	if not (0 < kindling_flame_at and kindling_flame_at < kindling_blaze_at):
		e.append("Kindling tiers must rise: 0 < flame < blaze < white")
	elif kindling_blaze_at >= kindling_white_at:
		e.append("Kindling tiers must rise: 0 < flame < blaze < white")
	if kill_ember_frames < 1 or kill_ember_frames > 20:
		e.append("kill_ember_frames must be 1 to 20 (BUILD.md section 15: within 20 frames)")
	if white_charged_every < 1 or weight_damage_per_frame < 1:
		e.append("white_charged_every and weight_damage_per_frame must be >= 1")
	# The window's oldest press must still be in the input ring (task 6 review, L2).
	if parry_window_frames < 1 or parry_window_frames > InputRing.HISTORY + 1:
		e.append(
			"parry_window_frames must be 1 to %d (the input ring's depth)" % (InputRing.HISTORY + 1)
		)
	# Every telegraph is at least 20 f (BUILD.md section 6), so a cue up to 20 f ahead always plays.
	if telegraph_cue_frames < 1 or telegraph_cue_frames > EnemyAttack.MIN_TELEGRAPH:
		e.append(
			(
				"telegraph_cue_frames must be 1 to %d (the shortest telegraph)"
				% EnemyAttack.MIN_TELEGRAPH
			)
		)
	for v: int in [
		hitstop_light,
		hitstop_finisher,
		hitstop_charged,
		hitstop_parry,
		hitstop_player_hit,
		hitstop_kill,
		hitstop_cap,
		parry_window_frames,
		parry_stagger_frames,
		poise_stagger_frames,
		telegraph_cue_frames,
		player_hit_invuln_frames,
		player_hit_knock_frames,
		hazard_damage,
		blaze_trail_frames,
		blaze_trail_damage,
		blaze_aoe_radius_u,
		blaze_aoe_damage,
		finisher_launch_ups
	]:
		if v < 0:
			e.append("frame counts, damage, sizes and speeds must not be negative")
			break
	return e
