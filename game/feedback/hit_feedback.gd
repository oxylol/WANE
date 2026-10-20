class_name HitFeedback
extends Node
## The presentation half of BUILD.md section 6's hit-feedback table, driven by the simulation's
## events each tick: directional screen shake, the parry's full-screen flash, the charged hit's
## chromatic split, the red vignette when the player is hit, slow motion, sparks through the VFX
## budget manager and sounds through the voice priority system (CLAUDE.md rule 7). Hitstop and
## knockback are the simulation's; this only shows them. Randomness here (spark variants, the
## +-3% pitch) never reaches the simulation.
##
## A Votive's proc shows as its look ([ProcLooks]) at [constant VfxBudget.PROC] priority, below
## every hit, burn and telegraph (docs/adr/0015). A proc on the point a hit landed this tick is
## part of that hit's feedback: it joins the hit's group, so the hit's own spark never refuses it,
## and each Votive shows once per hit however many times it fired there; anywhere else (a chain's
## arc to another enemy, Radiance's reach, a bounce) it takes its cell only if nothing more
## important holds it. A proc's damage shows by its proc's mark, never a hit spark.

## Asks the driver to run at [param scale] of real time for [param ticks] ticks.
signal slow_motion(scale: float, ticks: int)
## Asks the controller to rumble.
signal rumble(strength: float, msec: int)

## Hit sparks per Kindling tier (Ember, Flame, Blaze, White), by the tier the hit's damage used.
const SPARK_TINTS: Array[Color] = [
	Color(1.0, 0.95, 0.8), Color(1.0, 0.6, 0.2), Color(1.0, 0.75, 0.25), Color(1.0, 1.0, 0.95)
]

var tuning: FeedbackTuning
var looks: ProcLooks
var shake: ScreenShake
var vfx: VfxBudget
var voices: Voices
## Ticks left of each full-screen effect.
var flash_ticks: int = 0
var chroma_ticks: int = 0
var vignette_ticks: int = 0
## The player's flash setting, 0..1 (section 15: "with flashes set to 0").
var flash_scale: float = 1.0

## The player's centre this tick (units): where a finisher's slash arc is centred, so it sweeps
## along the blade's reach and not beyond the enemy it struck.
var _origin: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
## One hit's feedback is one bright thing for the VFX budget: its spark, smear and burst (and a
## stagger it causes) share a group, which is how a finisher's arc and burst survive the spark
## that claims the cell first. Groups are numbered across ticks, 0 meaning none.
var _next_group: int = 1
var _group: int = 0
## The priority the latest group's effects carry: a Taper or spell hit is the player's own
## feedback; a burn ranks below it (a burn tick, a Blaze trail or the AoE never displaces a
## Taper spark).
var _group_priority: int = VfxBudget.PLAYER
## This tick: the group of the hit at each point (sub-pixels), and the procs already shown in each
## group (by group and Votive slot).
var _hit_groups: Dictionary[Vector2i, int] = {}
var _procs_shown: Dictionary[Vector2i, bool] = {}


func _init(p_tuning: FeedbackTuning = null, p_looks: ProcLooks = null) -> void:
	tuning = p_tuning if p_tuning != null else load(FeedbackTuning.PATH) as FeedbackTuning
	looks = p_looks if p_looks != null else load(ProcLooks.PATH) as ProcLooks
	shake = ScreenShake.new(tuning)
	flash_scale = tuning.flash_default_scale


## Wires the effect outputs (any may be null in tests).
func attach(p_vfx: VfxBudget, p_voices: Voices) -> void:
	vfx = p_vfx
	voices = p_voices


## One tick: ages running effects (the budget's too, so an effect born this tick is drawn from
## its age 0 and lives its whole tuned lifetime: task 6 review, L1), then starts the ones this
## tick's events call for.
func on_tick(sim: Simulation) -> void:
	if vfx != null:
		vfx.step()
		# Through a door the effects of the room behind are gone with it (docs/adr/0014).
		if sim.events.has(SimEvents.ROOM):
			vfx.clear()
	shake.step()
	flash_ticks = maxi(flash_ticks - 1, 0)
	chroma_ticks = maxi(chroma_ticks - 1, 0)
	vignette_ticks = maxi(vignette_ticks - 1, 0)
	_rng.seed = sim.tick
	_group = 0
	if sim.player != null:
		var b: Body = sim.player.body
		_origin = Vector2(float(b.x), float(b.y - b.height / 2)) / Fx.SUB
	_hit_groups.clear()
	_procs_shown.clear()
	var e: SimEvents = sim.events
	for i: int in range(e.count()):
		var at := Vector2(float(e.xs[i]) / Fx.SUB, float(e.ys[i]) / Fx.SUB)
		match e.kinds[i]:
			SimEvents.HIT:
				if HitKind.kind_of(e.values[i]) == HitKind.PROC:
					continue
				_on_hit(at, e.values[i])
				_hit_groups[Vector2i(e.xs[i], e.ys[i])] = _group
			SimEvents.PROC:
				_on_proc(sim, Vector2i(e.xs[i], e.ys[i]), e.values[i])
			SimEvents.KILL:
				_on_kill(at, e.values[i])
			SimEvents.PARRY:
				_on_parry(at, e.values[i])
			SimEvents.PLAYER_HIT:
				_on_player_hit(at, e.values[i])
			SimEvents.TELEGRAPH_CUE:
				# 20 ticks before the swing lands, hitstop or not (the core's cue): BUILD.md
				# section 11, "every telegraph has a sound 20 f before the hit".
				_play("telegraph" if e.values[i] == 0 else "telegraph_red", at, Voices.TELEGRAPH)
			SimEvents.EMBER_HOME:
				_play("ember", at, Voices.PLAYER)
			SimEvents.HAZARD:
				# A hazard costs a heart as a hit does (docs/adr/0013), and reads as one.
				_on_player_hit(at, HitKind.encode(HitKind.PLAYER, 0, -1))
			SimEvents.DEATH:
				_vignette()
				_flash()
			SimEvents.RADIANCE:
				_new_group(VfxBudget.SPELL)
				_flash()
				_spark(
					VfxBudget.BURST,
					at,
					Vector2.UP,
					0,
					tuning.radiance_burst_size,
					0,
					_group_priority
				)
				_spark(
					VfxBudget.RING, at, Vector2.UP, 0, tuning.radiance_ring_size, 0, _group_priority
				)
				_play("radiance", at, Voices.PLAYER)
			SimEvents.HEAL:
				_new_group(VfxBudget.PLAYER)
				_spark(VfxBudget.BURST, at, Vector2.UP, 0, tuning.heal_burst_size)
				_play("heal", at, Voices.PLAYER)
			SimEvents.STAGGER:
				# Always comes with the hit that broke the poise: one group with its spark.
				if _group == 0:
					_new_group(VfxBudget.PLAYER)
				_spark(
					VfxBudget.BURST,
					at,
					Vector2.UP,
					0,
					tuning.stagger_burst_size,
					0,
					_group_priority
				)


## The view offset this tick (added to the drawn camera, never to the camera rig).
func shake_offset() -> Vector2:
	return shake.offset()


func _on_hit(at: Vector2, value: int) -> void:
	var kind: int = HitKind.kind_of(value)
	var dir := Vector2(HitKind.dir_of(value))
	var tier: int = HitKind.tier_of(value)
	var variant: int = _rng.randi_range(0, tuning.spark_variants - 1)
	_new_group(VfxBudget.BURN if kind == HitKind.BURN else VfxBudget.PLAYER)
	_spark(VfxBudget.SPARK, at, dir, variant, tuning.hit_spark_size, tier, _group_priority)
	match kind:
		HitKind.FINISHER:
			# The slash arc: centred on the player, its radius the reach to the struck enemy,
			# swept through the strike's direction (presentation review r2, L9: drawn on the
			# enemy it read as a shockwave beyond it).
			_spark(
				VfxBudget.SMEAR,
				_origin,
				dir,
				0,
				maxf(at.distance_to(_origin), tuning.smear_min_radius_u)
			)
			_spark(VfxBudget.BURST, at, dir, 0, tuning.finisher_burst_size)
			shake.add(dir, tuning.finisher_shake_u, tuning.finisher_shake_frames)
			_play("thump", at, Voices.HIT)
		HitKind.CHARGED:
			_spark(VfxBudget.BURST, at, dir, 0, tuning.charged_burst_size)
			shake.add(dir, tuning.charged_shake_u, tuning.charged_shake_frames)
			_split()
			_play("thump", at, Voices.HIT)
	_play("hit", at, Voices.HIT, variant)


## A Votive's proc: its look's mark, in the group of the hit at its point if there is one (once
## per Votive per hit), else on its own at [constant VfxBudget.PROC] priority.
func _on_proc(sim: Simulation, point: Vector2i, value: int) -> void:
	if vfx == null:
		return
	var slot: int = value % ProcBus.LEVEL_SHIFT
	if slot >= sim.procs.votives.size():
		return
	var group: int = _hit_groups.get(point, 0)
	if group != 0:
		var key := Vector2i(group, slot)
		if _procs_shown.has(key):
			return
		_procs_shown[key] = true
	var look: ProcLook = looks.look_for(sim.procs.votives[slot].id, slot)
	var at := Vector2(point) / Fx.SUB
	vfx.spawn(
		VfxBudget.PROC_MARK,
		VfxBudget.PROC,
		at,
		Vector2.UP,
		look.shape,
		float(look.size_u),
		look.colour,
		group,
		look.frames
	)


func _on_kill(at: Vector2, value: int) -> void:
	var dir := Vector2(HitKind.dir_of(value))
	shake.add(dir, tuning.kill_shake_u, tuning.kill_shake_frames)
	_play("kill", at, Voices.HIT)
	if HitKind.kind_of(value) == HitKind.CHARGED:
		slow_motion.emit(tuning.charged_kill_time_scale, tuning.charged_kill_slow_frames)


func _on_parry(at: Vector2, value: int) -> void:
	var dir := Vector2(HitKind.dir_of(value))
	_new_group(VfxBudget.PLAYER)
	_flash()
	shake.add(dir, tuning.parry_shake_u, tuning.parry_shake_frames)
	_spark(VfxBudget.BURST, at, dir, 0, tuning.parry_burst_size)
	_play("chime", at, Voices.PLAYER)
	slow_motion.emit(tuning.parry_time_scale, tuning.parry_slow_frames)


func _on_player_hit(at: Vector2, value: int) -> void:
	var dir := Vector2(HitKind.dir_of(value))
	_vignette()
	shake.add(dir, tuning.player_hit_shake_u, tuning.player_hit_shake_frames)
	_play("player_hit", at, Voices.PLAYER)
	rumble.emit(tuning.player_hit_rumble, tuning.player_hit_rumble_ms)


## Starts a new group: the effects of one hit, at [param priority].
func _new_group(priority: int) -> void:
	_group = _next_group
	_next_group += 1
	_group_priority = priority


## The full-screen flash: one tick whatever the flash setting, at that setting's opacity (the
## overlay scales it), and none at all at 0%. The VFX budget admits it (one bright screen
## effect per few ticks).
func _flash() -> void:
	if flash_scale > 0.0 and _admit(VfxBudget.SCREEN_FLASH):
		flash_ticks = tuning.parry_flash_frames


func _split() -> void:
	if flash_scale > 0.0 and _admit(VfxBudget.SCREEN_SPLIT):
		chroma_ticks = tuning.chromatic_frames


func _vignette() -> void:
	if _admit(VfxBudget.SCREEN_VIGNETTE):
		vignette_ticks = tuning.vignette_frames


func _admit(screen_kind: int) -> bool:
	return vfx == null or vfx.claim_screen(screen_kind, VfxBudget.PLAYER)


## A spark, burst, smear or ring of the current group; sparks are tinted by the Kindling
## [param tier] the hit's damage used.
func _spark(
	kind: int,
	at: Vector2,
	dir: Vector2,
	variant: int,
	size: float = 1.0,
	tier: int = 0,
	priority: int = VfxBudget.PLAYER
) -> void:
	if vfx != null:
		var tint: Color = Color(0, 0, 0, 0)
		if kind == VfxBudget.SPARK:
			tint = SPARK_TINTS[clampi(tier, 0, SPARK_TINTS.size() - 1)]
		vfx.spawn(kind, priority, at, dir, variant, size, tint, _group)


## Plays a variant of the sound [param base] ([param variant] picked at random unless given: a
## hit plays the variant its spark drew), at the tuned +-3% pitch: no sound repeats identically
## (section 11).
func _play(base: String, at: Vector2, priority: int, variant: int = -1) -> void:
	if voices == null:
		return
	var v: int = variant if variant >= 0 else _rng.randi_range(0, Synth.variants(base) - 1)
	var spread: float = tuning.sound_pitch_spread
	var pitch: float = 1.0 + _rng.randf_range(-spread, spread)
	voices.play(Synth.variant(base, v), at, priority, 0.0, pitch)
