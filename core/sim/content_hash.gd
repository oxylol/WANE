class_name ContentHash
extends RefCounted
## Fingerprint of the content a simulation was built from (a Wick's tuning resources and, from
## Phase 1 task 3, the room), so a replay recorded with different content reports "different
## content" instead of a desync, and golden fixture hashes can tell a content change from a code
## change (ADR-0006). Script variables are hashed in declaration order, which is stable.

## Each script's variable names, listed once (see [method _script_variables]).
static var _names: Dictionary[Script, PackedStringArray] = {}


static func add_resource(h: StateHasher, res: Resource) -> void:
	h.add_ints(resource_words(res))


## The words [method add_resource] appends for [param res]: 0 for none, else the 32-bit words of
## its digest. They depend only on the resource's values, so a batch of simulations that does not
## edit content between builds digests each resource once ([SimCache]).
static func resource_words(res: Resource) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	if res == null:
		out.append(0)
		return out
	var digest: PackedByteArray = _digest(res)
	for k: int in range(0, digest.size(), 4):
		out.append(digest.decode_u32(k))
	return out


## The words [method add_room] appends for [param room], without the seed word of a hasher of its
## own.
static func room_words(room: RoomData) -> PackedInt64Array:
	var own := StateHasher.new()
	add_room(own, room)
	return own.words_after_seed()


static func add_room(h: StateHasher, room: RoomData) -> void:
	h.add_string(room.id)
	h.add_int(room.spawn_x_u)
	h.add_int(room.spawn_y_u)
	room.grid.hash_into(h)
	for s: SolidBox in room.solids:
		s.hash_into(h)
	for e: RoomData.RoomEntity in room.entities:
		h.add_string(e.kind)
		h.add_int(e.x_u)
		h.add_int(e.y_u)
		var keys: Array[String] = []
		for k: String in e.props.keys():
			keys.append(k)
		keys.sort()
		for k: String in keys:
			var value: String = e.props[k]
			h.add_string(k)
			h.add_string(value)


## SHA-256 of a resource's script path and its script variables (each name, then its value), in
## declaration order; a sub-resource contributes its own digest. Hashing natively keeps building a
## simulation cheap: feeding every byte of every name through [StateHasher] took 3.7 ms of the
## 4.2 ms [Simulation] constructor. [method @GlobalScope.var_to_bytes] is Godot's portable binary
## encoding, the same on every platform. A script held as a value (a Votive's listener: its
## behaviour is content, docs/adr/0015) contributes its path and its source text.
static func _digest(res: Resource) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var as_script: Script = res as Script
	if as_script != null:
		ctx.update(var_to_bytes(as_script.resource_path))
		ctx.update(var_to_bytes(as_script.source_code))
		return ctx.finish()
	var script: Script = res.get_script()
	ctx.update(var_to_bytes(script.resource_path if script != null else res.get_class()))
	for prop_name: String in _script_variables(res):
		ctx.update(var_to_bytes(prop_name))
		_update_value(ctx, res.get(prop_name))
	return ctx.finish()


## The names of [param res]'s script variables in declaration order. A script's variables never
## change while the game runs, so they are listed once per script: asking the resource for its
## whole property list was 40% of the digest's time. The values are read afresh every time.
static func _script_variables(res: Resource) -> PackedStringArray:
	var script: Script = res.get_script()
	if script != null and _names.has(script):
		return _names[script]
	var names: PackedStringArray = []
	var props: Array[Dictionary] = res.get_property_list()
	for i: int in range(props.size()):
		var usage: int = props[i]["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var prop_name: String = props[i]["name"]
			names.append(prop_name)
	if script != null:
		_names[script] = names
	return names


static func _update_value(ctx: HashingContext, v: Variant) -> void:
	match typeof(v):
		TYPE_OBJECT:
			var obj: Object = v
			var sub: Resource = obj as Resource
			ctx.update(_digest(sub) if sub != null else var_to_bytes(null))
		TYPE_ARRAY:
			var count: int = 0
			for item: Variant in v:
				_update_value(ctx, item)
				count += 1
			ctx.update(var_to_bytes(count))
		_:
			ctx.update(var_to_bytes(v))
