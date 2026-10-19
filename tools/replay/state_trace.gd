extends SceneTree
## Proves that a change moved no behaviour: dumps every fixture's state tick by tick, and compares
## two such dumps field by field (docs/adr/0006: a change that adds a field to the state hash
## moves every golden hash, so the hashes alone cannot say whether anything else moved).
##
##   godot --headless --path . --script tools/replay/state_trace.gd -- dump <out dir> [fixture...]
##   godot --headless --path . --script tools/replay/state_trace.gd -- compare <before> <after>
##
## dump runs each fixture (every fixture under tests/replay/ if none is named) and writes
## <out dir>/<fixture name>.trace: one line per tick holding the player (every script variable of
## the player, its body, its vitals and its ember toss), every enemy (every script variable and
## its body), combat's effects (the kill embers, the fire trails, Radiance's light), the input
## ring, the random streams and the tick's events, each as name=value.
##
## compare reads two dump directories and fails on any fixture whose tick count differs, which is
## missing from the second, or any tick where a field present in both dumps has a different value
## or an event differs. Fields present in only one dump (a field the change added or removed) are
## listed once, by name, never compared. It prints the first difference of each fixture.

const TRACE_SUFFIX: String = ".trace"
## Components dumped through their own fields (by the name the owner holds them under).
const COMPONENTS: Array[String] = ["body", "vitals", "hearts", "flame", "kindling", "toss"]

## Each script's variable names in declaration order, read once.
var _names: Dictionary[Script, PackedStringArray] = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var ok: bool = false
	if args.size() >= 2 and args[0] == "dump":
		ok = _dump(args[1], args.slice(2))
	elif args.size() == 3 and args[0] == "compare":
		ok = _compare(args[1], args[2])
	else:
		printerr("usage: state_trace.gd -- dump <out dir> [fixture...] | compare <before> <after>")
		quit(2)
		return
	quit(0 if ok else 1)


func _dump(out_dir: String, named: PackedStringArray) -> bool:
	var paths: Array[String] = []
	if named.is_empty():
		paths = FileWalk.find(FixtureRunner.FIXTURE_ROOT, [".fixture"])
	else:
		for p: String in named:
			paths.append(p)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ticks: int = 0
	for path: String in paths:
		var fx: Fixture = Fixture.parse_file(path)
		if not fx.errors.is_empty():
			printerr("%s: %s" % [path, "; ".join(fx.errors)])
			return false
		var sim := Simulation.new(fx.scenario)
		var lines: PackedStringArray = []
		for i: int in range(fx.frame_total):
			sim.step(fx.input_frame(i))
			lines.append(_line(sim))
		ticks += fx.frame_total
		var f: FileAccess = FileAccess.open(
			out_dir.path_join(fx.name + TRACE_SUFFIX), FileAccess.WRITE
		)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("dumped %d fixtures, %d ticks, into %s" % [paths.size(), ticks, out_dir])
	return true


## One tick: sections separated by " | ", each "name=value" separated by spaces.
func _line(sim: Simulation) -> String:
	var parts: PackedStringArray = ["tick=%d room=%s" % [sim.tick, sim.room.id]]
	var fields: PackedStringArray = []
	if sim.player != null:
		_fields(sim.player, "player", fields)
	parts.append(" ".join(fields))
	fields = []
	for k: int in range(sim.combat.enemies.size()):
		_fields(sim.combat.enemies[k], "enemy%d" % k, fields)
	parts.append(" ".join(fields))
	fields = ["light=%d" % sim.combat.light_left]
	for k: int in range(sim.combat.embers.size()):
		_fields(sim.combat.embers[k], "ember%d" % k, fields)
	for k: int in range(sim.combat.trails.size()):
		_fields(sim.combat.trails[k], "trail%d" % k, fields)
	parts.append(" ".join(fields))
	fields = []
	_fields(sim.input, "ring", fields)
	for s: int in range(RngStreams.COUNT):
		fields.append("rng%d=%s" % [s, str(sim.rng.stream(s).get_state())])
	parts.append(" ".join(fields))
	var events: PackedStringArray = []
	var e: SimEvents = sim.events
	for i: int in range(e.count()):
		events.append("%s@%d,%d=%d" % [e.kinds[i], e.xs[i], e.ys[i], e.values[i]])
	parts.append("events=" + ",".join(events))
	return " | ".join(parts)


## Appends [param obj]'s script variables as "<prefix>.<name>=<value>", components through their
## own fields; other objects (tuning, the world, the event list) are not state and are skipped.
func _fields(obj: Object, prefix: String, out: PackedStringArray) -> void:
	for field: String in _script_variables(obj):
		var v: Variant = obj.get(field)
		if typeof(v) == TYPE_OBJECT:
			var component: Object = v
			if COMPONENTS.has(field) and component != null:
				_fields(component, prefix + "." + field, out)
			continue
		out.append("%s.%s=%s" % [prefix, field, str(v).replace(" ", "")])


func _script_variables(obj: Object) -> PackedStringArray:
	var script: Script = obj.get_script()
	if _names.has(script):
		return _names[script]
	var names: PackedStringArray = []
	var props: Array[Dictionary] = obj.get_property_list()
	for i: int in range(props.size()):
		var usage: int = props[i]["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var prop_name: String = props[i]["name"]
			names.append(prop_name)
	_names[script] = names
	return names


func _compare(before_dir: String, after_dir: String) -> bool:
	var before: PackedStringArray = DirAccess.get_files_at(before_dir)
	var only_before: Dictionary[String, bool] = {}
	var only_after: Dictionary[String, bool] = {}
	var failed: int = 0
	var compared: int = 0
	var ticks: int = 0
	var fields_compared: int = 0
	for file: String in before:
		if not file.ends_with(TRACE_SUFFIX):
			continue
		compared += 1
		var after_path: String = after_dir.path_join(file)
		if not FileAccess.file_exists(after_path):
			printerr("FAIL %s: missing from %s" % [file, after_dir])
			failed += 1
			continue
		var a: PackedStringArray = _read_lines(before_dir.path_join(file))
		var b: PackedStringArray = _read_lines(after_path)
		if a.size() != b.size():
			printerr("FAIL %s: %d ticks before, %d after" % [file, a.size(), b.size()])
			failed += 1
			continue
		for t: int in range(a.size()):
			var da: Dictionary[String, String] = _parse(a[t])
			var db: Dictionary[String, String] = _parse(b[t])
			var why: String = ""
			for key: String in da:
				if not db.has(key):
					only_before[_schema_key(key)] = true
					continue
				fields_compared += 1
				if da[key] != db[key] and why == "":
					why = "%s: %s before, %s after" % [key, da[key], db[key]]
			for key: String in db:
				if not da.has(key):
					only_after[_schema_key(key)] = true
			if why != "":
				printerr("FAIL %s tick %d: %s" % [file.trim_suffix(TRACE_SUFFIX), t, why])
				failed += 1
				break
		ticks += a.size()
	for key: String in only_before:
		print("field only before (not compared): %s" % key)
	for key: String in only_after:
		print("field only after (not compared): %s" % key)
	print(
		(
			"compared %d fixtures, %d ticks, %d field values: %d differ"
			% [compared, ticks, fields_compared, failed]
		)
	)
	return failed == 0 and compared > 0


func _read_lines(path: String) -> PackedStringArray:
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n", false)
	return lines


## "name=value" tokens of every section, keyed by name; the events as one field.
func _parse(line: String) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for section: String in line.split(" | "):
		for token: String in section.split(" ", false):
			var eq: int = token.find("=")
			if eq > 0:
				out[token.substr(0, eq)] = token.substr(eq + 1)
	return out


## A field's name without the enemy, ember or trail number, for the schema listing.
func _schema_key(key: String) -> String:
	var re := RegEx.create_from_string("^(enemy|ember|trail)\\d+")
	return re.sub(key, "$1")
