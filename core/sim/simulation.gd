class_name Simulation
extends RefCounted
## The deterministic simulation (BUILD.md section 13, layer 2; CLAUDE.md rules 1 to 4).
##
## Constructed from a [Scenario], stepped exactly once per 60 Hz tick with one [InputFrame], and
## hashed every [constant HASH_INTERVAL] ticks. Nothing outside [method step] changes its state.
## Presentation reads it; tools probe it by name with [method probe].

## Ticks between recorded state hashes.
const HASH_INTERVAL: int = 60
## Simulation version. Bump it in the same commit as any change that moves a golden hash
## (tools/replay/bless.gd refuses to re-bless otherwise), so old replays report "recorded by an
## older build" instead of a desync.
const VERSION: int = 7

## Where a Wick's content lives: <root><wick>/movement.tres, kit.tres, taper.tres.
const WICK_ROOT: String = "res://content/wicks/"
## Where an enemy kind's numbers live: <root><kind>.tres ([EnemyDef]).
const ENEMY_ROOT: String = "res://content/enemies/"
## The room entity kinds that are enemies.
const ENEMY_KINDS: Array[String] = ["dummy"]

var scenario: Scenario
## Ticks completed. The input applied by the n-th call to [method step] is input frame n - 1,
## and after that call [member tick] is n.
var tick: int = 0
var rng: RngStreams
## Player one's input buffer.
var input: InputRing
## Ticks and values of every recorded state hash, in order.
var hash_ticks: PackedInt32Array = PackedInt32Array()
var hash_values: PackedInt64Array = PackedInt64Array()
## Fingerprint of the content this simulation was built from: the room and the Wick's tuning
## ([ContentHash]).
var content_hash: int = 0
## The room's collision, the player, and this tick's events.
var room: RoomData
var world: CollisionWorld
var player: Player
var events: SimEvents = SimEvents.new()
## The combat rules, and the combat in this room: its enemies and effects (docs/adr/0013).
var combat_params: CombatParams
var combat: Combat
## The input frame the latest tick consumed, exactly as given (the F3 overlay's input history
## reads it: during hitstop the ring folds presses together). Presentation only; never read by
## the simulation.
var last_input: InputFrame = InputFrame.new()
## Problems found while building the simulation (a missing room, invalid content). A simulation
## with load errors still runs, but tools must treat it as a failure.
var load_errors: PackedStringArray = PackedStringArray()


func _init(p_scenario: Scenario) -> void:
	scenario = p_scenario.copy()
	rng = RngStreams.new(scenario.seed_value)
	input = InputRing.new()
	room = RoomData.new()
	if scenario.room != "":
		room = RoomData.load_id(scenario.room)
		load_errors.append_array(room.errors)
	world = room.build_world()
	var content := StateHasher.new()
	ContentHash.add_room(content, room)
	var tuning: WorldTuning = _load_content(WorldTuning.PATH) as WorldTuning
	if tuning == null:
		load_errors.append("missing world tuning at %s" % WorldTuning.PATH)
	else:
		tuning.apply(world)
		ContentHash.add_resource(content, tuning)
		load_errors.append_array(
			RoomJoins.errors(room, Fx.units(tuning.join_band_u), Fx.units(tuning.join_reach_u))
		)
	var combat_tuning: CombatTuning = _load_content(CombatTuning.PATH) as CombatTuning
	if combat_tuning == null:
		load_errors.append("missing combat tuning at %s" % CombatTuning.PATH)
		combat_tuning = CombatTuning.new()
	ContentHash.add_resource(content, combat_tuning)
	combat_params = combat_tuning.compile()
	combat = Combat.new(combat_params, events)
	player = _build_player(content)
	_build_enemies(content)
	content_hash = content.value()
	if player != null:
		var sx: int = scenario.spawn_x if scenario.spawn_x >= 0 else room.spawn_x_u
		var sy: int = scenario.spawn_y if scenario.spawn_y >= 0 else room.spawn_y_u
		player.spawn(Fx.units(sx), Fx.units(sy))
		player.kindle_dash = scenario.option("kindle") != 0
		_apply_vitals_options(player.vitals)


## Starting vitals a scenario may set (fixtures, and later modes): options "hearts", "flame" and
## "kindling", within their limits.
func _apply_vitals_options(v: Vitals) -> void:
	if scenario.options.has("hearts"):
		v.hearts.current = clampi(scenario.option("hearts"), 1, v.hearts.max_hearts)
	if scenario.options.has("flame"):
		v.flame.value = clampi(scenario.option("flame"), 0, v.flame.cap)
	if scenario.options.has("kindling"):
		v.kindling.hits = maxi(scenario.option("kindling"), 0)


## One enemy per enemy marker in the room, in the room's order (an enemy's index is its place
## here, in events and probes).
func _build_enemies(content: StateHasher) -> void:
	var defs: Dictionary[String, EnemyDef] = {}
	for e: RoomData.RoomEntity in room.entities:
		if not ENEMY_KINDS.has(e.kind):
			continue
		if not defs.has(e.kind):
			var path: String = ENEMY_ROOT + e.kind + ".tres"
			var def: EnemyDef = _load_content(path) as EnemyDef
			if def == null:
				load_errors.append("missing enemy content at %s" % path)
				continue
			ContentHash.add_resource(content, def)
			defs[e.kind] = def
		combat.enemies.append(
			TrainingDummy.from_entity(e, defs[e.kind], combat_params, world, events)
		)


func _build_player(content: StateHasher) -> Player:
	if scenario.wick == "":
		return null
	var dir: String = WICK_ROOT + scenario.wick + "/"
	var movement: MovementTuning = _load_content(dir + "movement.tres") as MovementTuning
	var kit_tuning: KitTuning = _load_content(dir + "kit.tres") as KitTuning
	var taper: AttackSet = _load_content(dir + "taper.tres") as AttackSet
	for res: Resource in [movement, kit_tuning, taper]:
		ContentHash.add_resource(content, res)
	if movement == null or kit_tuning == null or taper == null:
		load_errors.append("wick '%s' has incomplete content in %s" % [scenario.wick, dir])
		return null
	return Player.new(movement.compile(), kit_tuning.compile(), taper, combat_params, world, events)


func _load_content(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res != null and res.has_method("validate"):
		var problems: PackedStringArray = res.call("validate")
		for problem: String in problems:
			load_errors.append("%s: %s" % [path, problem])
	return res


## Advances the world by one tick with [param frame] as player one's input.
func step(frame: InputFrame) -> void:
	events.clear()
	last_input = frame
	if player != null and player.freeze > 0:
		input.merge(frame)
	else:
		input.push(frame)
	if player != null:
		player.step(input)
	for e: Enemy in combat.enemies:
		e.step(player)
	combat.resolve(player, input)
	tick += 1
	if tick % HASH_INTERVAL == 0:
		hash_ticks.append(tick)
		hash_values.append(state_hash())


## Hash of every piece of state that can influence a future tick.
func state_hash() -> int:
	var h := StateHasher.new()
	h.add_int(tick)
	scenario.hash_into(h)
	rng.hash_into(h)
	input.hash_into(h)
	# The tile grid never changes during a run: it is content, hashed once into the content
	# fingerprint, not here.
	for solid: SolidBox in world.solids:
		solid.hash_into(h)
	if player != null:
		player.hash_into(h)
	combat.hash_into(h)
	return h.value()


## The recorded hash at [param at_tick], or -1 if none was recorded there.
func hash_at(at_tick: int) -> int:
	var i: int = hash_ticks.find(at_tick)
	return hash_values[i] if i >= 0 else -1


## Named read-only view of the state, for replay fixtures and the F3 overlay. Returns an int or a
## String, or null for an unknown key. Keys are listed in tests/replay/README.md.
func probe(key: String) -> Variant:
	var value: Variant = null
	match key:
		"tick":
			value = tick
		"stick_x":
			value = input.stick_x()
		"stick_y":
			value = input.stick_y()
		"embers":
			value = combat.embers.size()
		"light":
			value = combat.light_left
		_:
			if key.begins_with("enemy"):
				return EnemyProbe.read(combat, key)
			value = _probe_input(key)
			if value == null and player != null:
				value = PlayerProbe.read(player, events, key)
	return value


## The names a String-valued probe key can take (for fixture validation); empty for keys whose
## values are integers.
func probe_words(key: String) -> PackedStringArray:
	if key.begins_with("enemy"):
		return EnemyProbe.words(key)
	if player == null:
		return PackedStringArray()
	return PlayerProbe.words(player, key)


func _probe_input(key: String) -> Variant:
	var dot: int = key.find(".")
	if dot < 0:
		return null
	var bit: int = _button_bit(key.substr(dot + 1))
	if bit == 0:
		return null
	match key.substr(0, dot):
		"held":
			return 1 if input.is_held(bit) else 0
		"press_age":
			return input.press_age(bit)
	return null


static func _button_bit(button_name: String) -> int:
	var i: int = InputFrame.BUTTON_NAMES.find(button_name.to_upper())
	return InputFrame.BUTTONS[i] if i >= 0 else 0
