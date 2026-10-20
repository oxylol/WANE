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
const VERSION: int = 12

## Where a Wick's content lives: <root><wick>/movement.tres, kit.tres, taper.tres.
const WICK_ROOT: String = "res://content/wicks/"
## Where an enemy kind's numbers live: <root><kind>.tres ([EnemyDef]).
const ENEMY_ROOT: String = "res://content/enemies/"
## The room entity kinds that are enemies.
const ENEMY_KINDS: Array[String] = ["dummy"]
## A scenario option naming a Votive: "votive_<id>" with its stacks (docs/adr/0015).
const VOTIVE_OPTION: String = "votive_"

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
## The rooms this run can reach through doors, the room the player is in, its collision, the
## player, and this tick's events.
var rooms: RoomSet = RoomSet.new()
var room: RoomData
var world: CollisionWorld
var player: Player
var events: SimEvents = SimEvents.new()
## The combat rules, and the combat in this room: its enemies and effects (docs/adr/0013).
var combat_params: CombatParams
var combat: Combat
## Steps the room's enemies, with one native call for the plain ones ([EnemyBatch]); not state.
var enemy_batch: EnemyBatch = EnemyBatch.new()
## The run's Votives and the proc event bus (docs/adr/0015). A run starts with none; a scenario
## gives them with "votive_<id>" options.
var procs: ProcBus
## The input frame the latest tick consumed, exactly as given (the F3 overlay's input history
## reads it: during hitstop the ring folds presses together). Presentation only; never read by
## the simulation.
var last_input: InputFrame = InputFrame.new()
## Problems found while building the simulation (a missing room, invalid content). A simulation
## with load errors still runs, but tools must treat it as a failure.
var load_errors: PackedStringArray = PackedStringArray()

var _world_tuning: WorldTuning
## The Wick's movement as authored, recompiled when a Votive changes its run speed.
var _movement: MovementTuning
## Every enemy kind's numbers, for the rooms this run can reach.
var _enemy_defs: Dictionary[String, EnemyDef] = {}


func _init(p_scenario: Scenario) -> void:
	scenario = p_scenario.copy()
	rng = RngStreams.new(scenario.seed_value)
	input = InputRing.new()
	room = RoomData.new()
	if scenario.room != "":
		rooms = RoomSet.reach(scenario.room)
		room = rooms.rooms[scenario.room]
		load_errors.append_array(room.errors)
		load_errors.append_array(rooms.errors)
	world = room.build_world()
	var content := StateHasher.new()
	ContentHash.add_room(content, room)
	for room_id: String in rooms.order.slice(1):
		ContentHash.add_room(content, rooms.rooms[room_id])
	var tuning: WorldTuning = _load_content(WorldTuning.PATH) as WorldTuning
	if tuning == null:
		load_errors.append("missing world tuning at %s" % WorldTuning.PATH)
	else:
		_world_tuning = tuning
		tuning.apply(world)
		ContentHash.add_resource(content, tuning)
		var band: int = Fx.units(tuning.join_band_u)
		var reach_sp: int = Fx.units(tuning.join_reach_u)
		load_errors.append_array(RoomJoins.errors(room, band, reach_sp))
		for room_id: String in rooms.order.slice(1):
			for problem: String in RoomJoins.errors(rooms.rooms[room_id], band, reach_sp):
				load_errors.append("%s: %s" % [room_id, problem])
	var combat_tuning: CombatTuning = _load_content(CombatTuning.PATH) as CombatTuning
	if combat_tuning == null:
		load_errors.append("missing combat tuning at %s" % CombatTuning.PATH)
		combat_tuning = CombatTuning.new()
	ContentHash.add_resource(content, combat_tuning)
	combat_params = combat_tuning.compile()
	var proc_tuning: ProcTuning = _load_content(ProcTuning.PATH) as ProcTuning
	if proc_tuning == null:
		load_errors.append("missing proc tuning at %s" % ProcTuning.PATH)
		proc_tuning = ProcTuning.new()
	ContentHash.add_resource(content, proc_tuning)
	procs = ProcBus.new(proc_tuning, events, rng.procs())
	combat = Combat.new(combat_params, events, procs)
	_load_votives(content)
	player = _build_player(content)
	_load_enemy_defs(content)
	_build_enemies()
	content_hash = content.value()
	if player != null:
		var sx: int = scenario.spawn_x if scenario.spawn_x >= 0 else room.spawn_x_u
		var sy: int = scenario.spawn_y if scenario.spawn_y >= 0 else room.spawn_y_u
		player.spawn(Fx.units(sx), Fx.units(sy))
		player.kindle_dash = scenario.option("kindle") != 0
		player.procs = procs
		_apply_run_mods()
		_apply_vitals_options(player.vitals)


## Gives the run [param count] stacks of [param votive] (a pickup, later; a scenario's Votives at
## the start) and applies what its "run" trigger changes. False if it could not be given.
func give_votive(votive: Votive, count: int) -> bool:
	if not procs.give(votive, count):
		return false
	_apply_run_mods()
	return true


## The Votives a scenario names ("votive_<id>" options, with their stacks), in the order of their
## option keys: that is their run order. Each Votive's resource and listener script join the
## content fingerprint.
func _load_votives(content: StateHasher) -> void:
	for key: String in scenario.sorted_option_keys():
		if not key.begins_with(VOTIVE_OPTION):
			continue
		var votive_id: String = key.trim_prefix(VOTIVE_OPTION)
		var count: int = scenario.option(key)
		var path: String = Votive.path_for(votive_id)
		var votive: Votive = _load_content(path) as Votive
		if votive == null:
			load_errors.append("option %s: no Votive at %s" % [key, path])
			continue
		ContentHash.add_resource(content, votive)
		if count < 1 or not procs.give(votive, count):
			load_errors.append("option %s: cannot give %d stacks of %s" % [key, count, path])


## What the run's "run" Votives change, applied to the Wick: its movement recompiled with the run
## speed, the ground dash's cooldown, its maximum hearts (docs/adr/0015).
func _apply_run_mods() -> void:
	if player == null:
		return
	var mods: RunMods = procs.run_mods()
	player.p = _movement.compile(mods.run_speed_permille)
	player.dash_free = mods.dash_free
	player.vitals.hearts.set_max(combat_params.hearts + mods.max_hearts_delta)


## Starting vitals a scenario may set (fixtures, and later modes): options "hearts", "flame" and
## "kindling", within their limits.
func _apply_vitals_options(v: Vitals) -> void:
	if scenario.options.has("hearts"):
		v.hearts.current = clampi(scenario.option("hearts"), 1, v.hearts.max_hearts)
	if scenario.options.has("flame"):
		v.flame.value = clampi(scenario.option("flame"), 0, v.flame.cap)
	if scenario.options.has("kindling"):
		v.kindling.hits = maxi(scenario.option("kindling"), 0)


## The numbers of every enemy kind the reachable rooms hold, in the order first met (the first
## room's markers, then each room's in [member RoomSet.order]).
func _load_enemy_defs(content: StateHasher) -> void:
	for r: RoomData in _reachable():
		for e: RoomData.RoomEntity in r.entities:
			if not ENEMY_KINDS.has(e.kind) or _enemy_defs.has(e.kind):
				continue
			var path: String = ENEMY_ROOT + e.kind + ".tres"
			# Every enemy is a training dummy until the zones' enemies arrive: its content is a
			# DummyDef (an EnemyDef with its respawn and swing period).
			var def: DummyDef = _load_content(path) as DummyDef
			if def == null:
				load_errors.append("missing dummy content (a DummyDef) at %s" % path)
				continue
			ContentHash.add_resource(content, def)
			_enemy_defs[e.kind] = def


## The rooms this run can reach, the first first; with no room, the empty one it runs in.
func _reachable() -> Array[RoomData]:
	var out: Array[RoomData] = []
	for room_id: String in rooms.order:
		out.append(rooms.rooms[room_id])
	if out.is_empty():
		out.append(room)
	return out


## One enemy per enemy marker in the room, in the room's order (an enemy's index is its place
## here, in events and probes).
func _build_enemies() -> void:
	for e: RoomData.RoomEntity in room.entities:
		if _enemy_defs.has(e.kind):
			combat.enemies.append(
				TrainingDummy.from_entity(
					e, _enemy_defs[e.kind] as DummyDef, combat_params, world, events
				)
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
	_movement = movement
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
	world.begin_tick()
	procs.begin_tick(tick)
	last_input = frame
	if player != null and player.freeze > 0:
		input.merge(frame)
	else:
		input.push(frame)
	if player != null:
		player.step(input)
	enemy_batch.run(combat.enemies, player, world)
	combat.resolve(player, input)
	_take_door()
	tick += 1
	if tick % HASH_INTERVAL == 0:
		hash_ticks.append(tick)
		hash_values.append(state_hash())


## The player goes through a door when the whole body is inside the door's strip at the end of a
## tick (docs/adr/0014).
func _take_door() -> void:
	if player == null or room.doors.is_empty():
		return
	var b: Body = player.body
	var box := Rect2i(b.left(), b.top(), b.right() - b.left(), b.height)
	var w_u: int = room.grid.width * TileGrid.TILE
	var h_u: int = room.grid.height * TileGrid.TILE
	for d: RoomData.Door in room.doors:
		var strip_u: Rect2i = d.strip_u(w_u, h_u)
		if Rect2i(strip_u.position * Fx.SUB, strip_u.size * Fx.SUB).encloses(box):
			_go_through(d)
			return


## Through [param d] into the room beyond: the player arrives just inside the door it leads to,
## as far along the opening as they were along this one, with the speed, state and action they
## had; the room's enemies, embers and trails are left behind (an ember in flight reaches the
## player as they go), and the new room's enemies start fresh. A door whose room failed to load
## or whose pair is broken leads nowhere (the load errors say why).
func _go_through(d: RoomData.Door) -> void:
	var beyond: RoomData = rooms.rooms.get(d.target_room, null)
	if beyond == null or not beyond.errors.is_empty():
		return
	var back: RoomData.Door = beyond.door(d.target_door)
	if back == null or back.side != d.facing_side() or back.span_u() != d.span_u():
		return
	var b: Body = player.body
	var depth: int = Fx.units(RoomData.DOOR_DEPTH_TILES * TileGrid.TILE)
	var along: int = b.y if d.side == RoomData.LEFT or d.side == RoomData.RIGHT else b.x
	along += Fx.units(back.from_u - d.from_u)
	var x: int = along
	var y: int = along
	match back.side:
		RoomData.LEFT:
			x = depth + b.half_w
		RoomData.RIGHT:
			x = Fx.units(beyond.grid.width * TileGrid.TILE) - depth - b.half_w
		RoomData.TOP:
			y = depth + b.height
		RoomData.BOTTOM:
			y = Fx.units(beyond.grid.height * TileGrid.TILE) - depth
	room = beyond
	world = room.build_world()
	if _world_tuning != null:
		_world_tuning.apply(world)
	combat.leave_room(player)
	PlayerContacts.arrive(player, world, x, y, Fx.units(room.spawn_x_u), Fx.units(room.spawn_y_u))
	_build_enemies()
	events.add(SimEvents.ROOM, x, y)


## Hash of every piece of state that can influence a future tick.
func state_hash() -> int:
	var h := StateHasher.new()
	h.add_int(tick)
	h.add_string(room.id)
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
	procs.hash_into(h)
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
		"room":
			# A fixture word: the room's id with its slashes as underscores.
			value = room.id.replace("/", "_")
		"procs":
			value = procs.fired()
		"proc_events":
			value = procs.raised
		"proc_level":
			value = procs.deepest()
		_:
			if key.begins_with("enemy"):
				return EnemyProbe.read(combat, key)
			if key.begins_with("proc.") or key.begins_with("votive."):
				return _probe_votive(key)
			value = _probe_input(key)
			if value == null and player != null:
				value = PlayerProbe.read(player, events, key)
	return value


## The names a String-valued probe key can take (for fixture validation); empty for keys whose
## values are integers.
func probe_words(key: String) -> PackedStringArray:
	if key == "room":
		var ids: PackedStringArray = []
		for r: RoomData in _reachable():
			ids.append(r.id.replace("/", "_"))
		return ids
	if key.begins_with("enemy"):
		return EnemyProbe.words(key)
	if player == null:
		return PackedStringArray()
	return PlayerProbe.words(player, key)


## "proc.<id>": the procs Votive <id> fired this tick; "votive.<id>": its stacks. Null for an id
## that names no Votive file, so a misspelt id fails a fixture rather than reading 0.
func _probe_votive(key: String) -> Variant:
	var dot: int = key.find(".")
	var votive_id: String = key.substr(dot + 1)
	if not Votive.exists(votive_id):
		return null
	if key.begins_with("proc."):
		return procs.fired(votive_id)
	return procs.stacks_of(votive_id)


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
