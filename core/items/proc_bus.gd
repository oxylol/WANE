class_name ProcBus
extends RefCounted
## The proc event bus and the run's Votives (BUILD.md section 13, layer 2: "the proc event bus,
## Votive stacking"; section 6, Item procs; section 8, Stacking math; docs/adr/0015).
##
## The run's Votives are held in run order (the order they were given; a scenario's in the order of
## their option keys), each with its stacks, its curve's value at them, a counter it may keep, and
## an instance of its listener script. A Votive's slot is its place in that order.
##
## Proc events: every Taper hit, pogo off an enemy, Kindle tick and Radiance reaching an enemy is
## [method raise]d by combat as it lands, with its coefficient and the Kindling tier the hit used.
## [method resolve] runs once a tick, after the player's hits and before the enemies' (so a proc
## that stuns or kills an enemy on the tick its swing would land takes the swing away, as the
## player's own hits do), and works through the events in the order they were raised. For each
## event, each Votive listening to "hit", in run order:
##   1. its chance in parts per million: its curve's value x the event's coefficient x (1 + the
##      Flame tier's bonus, at Kindling Flame and above), rounded down once, at the end;
##   2. a whole million is a proc on this event for certain, each one; what remains is one draw
##      from the PROCS stream ([method Rng.below] of a million), made only when something remains;
##   3. each proc fires in turn: a PROC event for presentation, then the listener's on_proc, whose
##      own rolls (if it asks for any) draw there and then.
## A proc that lands a hit raises a proc event one level deeper, queued after every event already
## raised. A proc fires at level 1 on a hit's event and one level deeper on a Votive's; the deepest
## is [member ProcTuning.chain_depth] (3), and a hit at that level raises nothing ("to a depth of
## 3, then stop"). Every roll is a PROCS draw in this order, so a run is still a seed and its
## inputs.
##
## Its methods whose names start with an underscore and act for a proc (a hit, a stun, a roll, a
## param, the counter, the air dashes) are the listener API's: [VotiveApi] and its kinds call them
## for a listener, which never names them itself (tools/ci/core_purity.gd).

## Queued event fields, [constant STRIDE] integers each.
enum { Q_SOURCE, Q_COEFFICIENT, Q_DEPTH, Q_TARGET, Q_X, Q_Y, Q_DAMAGE, Q_TIER, STRIDE }

## A PROC event's value is the Votive's slot plus this times the proc's level.
const LEVEL_SHIFT: int = 256
const PPM: int = StackingCurve.PPM
const PERMILLE: int = StackingCurve.PERMILLE

var tuning: ProcTuning
var events: SimEvents
## The PROCS stream (ADR-0005): what a run finds never depends on how often its items fire.
var rng: Rng
## The run's Votives, in run order, with their stacks and counters (state, hashed).
var votives: Array[Votive] = []
var stacks: PackedInt32Array = PackedInt32Array()
var counters: PackedInt32Array = PackedInt32Array()
## This tick's proc events and procs, for presentation, probes and the F3 overlay (not state:
## cleared every tick, never read by the simulation): how many events were raised, and each proc
## fired, by its Votive's slot and its level.
var raised: int = 0
## The tick being played (the simulation's, as [method begin_tick] was given it): read by a
## listener through [method ProcApi.tick] for an internal cooldown. Derived, never hashed.
var tick: int = 0
var fired_slots: PackedInt32Array = PackedInt32Array()
var fired_levels: PackedInt32Array = PackedInt32Array()

var _listeners: Array[VotiveListener] = []
## Each Votive's curve at its stacks, kept with the stacks.
var _values: PackedInt32Array = PackedInt32Array()
## The slots listening to each trigger, in run order.
var _hit_slots: PackedInt32Array = PackedInt32Array()
var _blade_slots: PackedInt32Array = PackedInt32Array()
var _bounce_slots: PackedInt32Array = PackedInt32Array()
var _run_slots: PackedInt32Array = PackedInt32Array()
## Each source's coefficient, per-mille ([ProcTuning]).
var _coefficients: PackedInt32Array = PackedInt32Array()
## This tick's unresolved events, [constant STRIDE] integers each; the array keeps its size from
## tick to tick, [member _queued] says how many are in use.
var _queue: PackedInt32Array = PackedInt32Array()
var _queued: int = 0
## While a listener runs: the combat and player it acts on, the queued event a proc fires on, and
## the API it was handed (one of each, reused).
var _combat: Combat
var _player: Player
var _event: int = 0
var _proc_api: ProcApi = ProcApi.new()
var _blade_api: BladeHitApi = BladeHitApi.new()
var _bounce_api: BounceApi = BounceApi.new()
var _run_api: RunApi = RunApi.new()


func _init(p_tuning: ProcTuning, p_events: SimEvents, p_rng: Rng) -> void:
	tuning = p_tuning
	events = p_events
	rng = p_rng
	for source: int in range(ProcSource.NAMES.size()):
		_coefficients.append(tuning.coefficient(source))


# --- the run's Votives -----------------------------------------------------------------------


## Gives the run [param count] stacks of [param votive]; one already held gains them. False, and
## nothing given, for no stacks or a listener that cannot be made.
func give(votive: Votive, count: int) -> bool:
	if count <= 0 or votive == null or votive.curve == null:
		return false
	var slot: int = slot_of(votive.id)
	if slot >= 0:
		stacks[slot] += count
		_values[slot] = votive.curve.value(stacks[slot])
		return true
	var made: VotiveListener = votive.make_listener()
	if made == null:
		return false
	slot = votives.size()
	votives.append(votive)
	stacks.append(count)
	counters.append(0)
	_values.append(votive.curve.value(count))
	_listeners.append(made)
	if votive.hears("hit"):
		_hit_slots.append(slot)
	if votive.hears("blade_hit"):
		_blade_slots.append(slot)
	if votive.hears("bounce"):
		_bounce_slots.append(slot)
	if votive.hears("run"):
		_run_slots.append(slot)
	return true


## The slot of the Votive [param votive_id], or -1 if the run has none.
func slot_of(votive_id: String) -> int:
	for i: int in range(votives.size()):
		if votives[i].id == votive_id:
			return i
	return -1


func stacks_of(votive_id: String) -> int:
	var slot: int = slot_of(votive_id)
	return stacks[slot] if slot >= 0 else 0


func _param_of(slot: int, param_name: String) -> int:
	var params: Dictionary[String, int] = votives[slot].params
	# Validation holds a listener to the params it lists; the message is built only on a failure.
	if not params.has(param_name):
		assert(false, "%s reads a param it lacks: %s" % [votives[slot].id, param_name])
	return params.get(param_name, 0)


func _counter_of(slot: int) -> int:
	return counters[slot]


func _set_counter_of(slot: int, v: int) -> void:
	counters[slot] = v


## The run's standing changes from every "run" Votive, in run order.
func run_mods() -> RunMods:
	var api: RunApi = _run_api
	api._mods = RunMods.new()
	api._bus = self
	for slot: int in _run_slots:
		api._set_slot(slot, stacks[slot], _values[slot])
		_listeners[slot].on_run(api)
	api._bus = null
	return api._mods


# --- proc events -----------------------------------------------------------------------------


## The start of tick [param p_tick]: this tick's counts start again.
func begin_tick(p_tick: int = 0) -> void:
	tick = p_tick
	raised = 0
	fired_slots.clear()
	fired_levels.clear()


## A proc event: [param source] ([ProcSource]) on enemy [param target], at ([param x], [param y])
## sub-pixels, its hit dealing [param damage], at Kindling tier [param tier] (the tier the hit's
## damage used), [param depth] procs deep, with [param coefficient] per-mille (-1: the source's).
## Queued for [method resolve] if a Votive rolls on proc events and a proc on it would still be
## within the chain's depth.
func raise(
	source: int,
	target: int,
	x: int,
	y: int,
	damage: int,
	tier: int,
	depth: int = 0,
	coefficient: int = -1
) -> void:
	raised += 1
	if _hit_slots.is_empty() or depth >= tuning.chain_depth:
		return
	var at: int = _queued * STRIDE
	if _queue.size() < at + STRIDE:
		_queue.resize(at + STRIDE)
	_queue[at + Q_SOURCE] = source
	_queue[at + Q_COEFFICIENT] = coefficient if coefficient >= 0 else _coefficients[source]
	_queue[at + Q_DEPTH] = depth
	_queue[at + Q_TARGET] = target
	_queue[at + Q_X] = x
	_queue[at + Q_Y] = y
	_queue[at + Q_DAMAGE] = damage
	_queue[at + Q_TIER] = tier
	_queued += 1


## Rolls and fires every proc this tick's events call for, chains included (see the class
## description for the order). [param combat] and [param pl] are what the procs act on.
func resolve(combat: Combat, pl: Player) -> void:
	if _queued == 0:
		return
	_combat = combat
	_player = pl
	var i: int = 0
	while i < _queued:
		var at: int = i * STRIDE
		# chance_ppm, with the event's part worked out once for every Votive rolling on it.
		var scale: int = _queue[at + Q_COEFFICIENT] * (PERMILLE + _bonus(_queue[at + Q_TIER]))
		for slot: int in _hit_slots:
			var chance: int = _values[slot] * scale / (PERMILLE * PERMILLE)
			var procs: int = chance / PPM
			var rest: int = chance % PPM
			if rest > 0 and rng.below(PPM) < rest:
				procs += 1
			for _k: int in range(procs):
				_fire(slot, at)
		i += 1
	_queued = 0
	_combat = null
	_player = null


## True while [method resolve] runs: combat's proc queries may keep what they found until it ends.
func resolving() -> bool:
	return _combat != null


## The chance, in parts per million, that the Votive in [param slot] procs on an event of
## [param coefficient] per-mille at Kindling tier [param tier]: its curve's value, scaled by the
## coefficient and, from the Flame tier up, by the tier's bonus ("Votive procs +10% chance"),
## rounded down once. A million or more is a proc for certain for each whole million.
func chance_ppm(slot: int, coefficient: int, tier: int) -> int:
	return _values[slot] * coefficient * (PERMILLE + _bonus(tier)) / (PERMILLE * PERMILLE)


## The Flame tier's bonus to proc chances, per-mille, at Kindling tier [param tier].
func _bonus(tier: int) -> int:
	return tuning.flame_tier_chance_permille if tier >= Kindling.FLAME else 0


func _fire(slot: int, at: int) -> void:
	var level: int = _queue[at + Q_DEPTH] + 1
	_shown(slot, level, _queue[at + Q_X], _queue[at + Q_Y])
	var api: ProcApi = _proc_api
	api._bus = self
	api._set_slot(slot, stacks[slot], _values[slot])
	api._level = level
	api._source = _queue[at + Q_SOURCE]
	api._coefficient = _queue[at + Q_COEFFICIENT]
	api._target = _queue[at + Q_TARGET]
	api._damage = _queue[at + Q_DAMAGE]
	_event = at
	_listeners[slot].on_proc(api)
	api._bus = null


## A proc of [param slot] at [param level], at ([param x], [param y]): the PROC event and this
## tick's record of it.
func _shown(slot: int, level: int, x: int, y: int) -> void:
	events.add(SimEvents.PROC, x, y, slot + LEVEL_SHIFT * level)
	fired_slots.append(slot)
	fired_levels.append(level)


# --- what a proc may do ([ProcApi]) ----------------------------------------------------------


## A proc hit on enemy [param handle] for [param amount] (see [method Combat.proc_hit]); it raises
## a proc event one level deeper, with the firing Votive's own coefficient.
func _proc_hit(handle: int, amount: int) -> bool:
	if _combat == null or amount <= 0:
		return false
	var dealt: int = _combat.proc_hit(_player, handle, amount)
	if dealt < 0:
		return false
	var c: Vector2i = _combat.enemies[handle].centre()
	var slot: int = _proc_api._slot
	raise(
		ProcSource.VOTIVE,
		handle,
		c.x,
		c.y,
		dealt,
		_player.vitals.kindling.tier(),
		_proc_api._level,
		votives[slot].hit_coefficient_permille
	)
	return true


func _stun_within(radius_u: int, frames: int) -> int:
	if _combat == null:
		return 0
	return _combat.stun_within(_event_point(), Fx.units(radius_u), frames)


func _nearest_enemy(radius_u: int, skip_target: bool) -> int:
	if _combat == null:
		return -1
	var skip: int = _queue[_event + Q_TARGET] if skip_target else -1
	return _combat.nearest_enemy(_event_point(), Fx.units(radius_u), skip)


func _roll_permille(per_mille: int) -> bool:
	return rng.chance_permille(per_mille)


func _event_point() -> Vector2i:
	return Vector2i(_queue[_event + Q_X], _queue[_event + Q_Y])


# --- the blade and the bounce ----------------------------------------------------------------


## The damage every "blade_hit" Votive adds to a Taper ([constant ProcSource.TAPER]) or pogo
## ([constant ProcSource.POGO]) hit on enemy [param target].
func blade_bonus(source: int, target: int) -> int:
	if _blade_slots.is_empty():
		return 0
	var api: BladeHitApi = _blade_api
	api._bus = self
	api._source = source
	api._target = target
	api._added = 0
	for slot: int in _blade_slots:
		api._set_slot(slot, stacks[slot], _values[slot])
		_listeners[slot].on_blade_hit(api)
	api._bus = null
	return api._added


## A pogo bounce of [param pl]: every "bounce" Votive hears it; one that gave the player anything
## shows as its proc, at the player's centre.
func bounced(pl: Player) -> void:
	if _bounce_slots.is_empty():
		return
	_player = pl
	var api: BounceApi = _bounce_api
	api._bus = self
	var b: Body = pl.body
	for slot: int in _bounce_slots:
		api._set_slot(slot, stacks[slot], _values[slot])
		api._granted = false
		_listeners[slot].on_bounce(api)
		if api._granted:
			_shown(slot, 1, b.x, b.y - b.height / 2)
	api._bus = null
	_player = null


## Tops the player's air dashes up to their own plus [param extra]; true if that added any.
func _top_up_air_dashes(extra: int) -> bool:
	if _player == null:
		return false
	var want: int = _player.p.air_dashes + extra
	if _player.air_dashes_left >= want:
		return false
	_player.air_dashes_left = want
	return true


# --- reading -----------------------------------------------------------------------------------


## Procs fired this tick, by every Votive or by [param votive_id] alone.
func fired(votive_id: String = "") -> int:
	if votive_id == "":
		return fired_slots.size()
	return fired_slots.count(slot_of(votive_id)) if slot_of(votive_id) >= 0 else 0


## The deepest level a proc fired at this tick (0 if none did).
func deepest() -> int:
	var deepest_level: int = 0
	for level: int in fired_levels:
		deepest_level = maxi(deepest_level, level)
	return deepest_level


func hash_into(h: StateHasher) -> void:
	h.add_int(votives.size())
	for i: int in range(votives.size()):
		h.add_string(votives[i].id)
		h.add_int(stacks[i])
		h.add_int(counters[i])
