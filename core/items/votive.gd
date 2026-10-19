class_name Votive
extends Resource
## A Votive as content (BUILD.md section 8; section 13, layer 3: "a Votive is a resource with a
## proc listener script and a stacking curve"; CLAUDE.md, Content: "adding one never touches
## core/"; docs/adr/0015). One file per Votive: content/votives/<id>.tres with its listener
## script beside it. Test Votives live in tests/votives/<name>.tres and their ids start "test_".
##
## Every number the Votive uses is here: its curve's amounts, and [member params] for the rest (a
## radius, a stun's length). The item lines (BUILD.md section 2, Lore delivery rules: "Every item
## description is two lines: one mechanical, one in-world. The in-world line is written by a
## character") are required for content Votives. In the mechanical line "{per_stack}" stands for
## the per-stack amount, "{total}" for the live total at the stacks counted (section 8: "A tooltip
## shows the live number with stacks counted. No hidden math") and "{<param>}" for one of
## [member params], so the line never states a number of its own that tuning could leave stale.

enum Tier { CANDLE, LANTERN, STAR, RELIC, SOOT }

const TIER_NAMES: Array[String] = ["candle", "lantern", "star", "relic", "soot"]
## The triggers a listener can hear ([VotiveListener]) and the hook each needs.
const TRIGGERS: Array[String] = ["hit", "blade_hit", "bounce", "run"]
const HOOKS: Array[String] = ["on_proc", "on_blade_hit", "on_bounce", "on_run"]
const CONTENT_ROOT: String = "res://content/votives/"
const TEST_ROOT: String = "res://tests/votives/"
const TEST_PREFIX: String = "test_"
## How a mechanical line's numbers are shown: a plain integer, or per-mille as a percent.
const UNITS: Array[String] = ["count", "permille"]

## Its id: the file's name (content), or "test_" and the file's name (tests/votives/).
@export var id: String = ""
## The name shown to the player.
@export var display_name: String = ""
@export var tier: Tier = Tier.CANDLE
@export var curve: StackingCurve
## How the curve's per-stack amount reads in the mechanical line.
@export var unit: String = "count"
## The triggers its listener hears, from [constant TRIGGERS].
@export var listens_to: PackedStringArray = PackedStringArray()
## The listener: a script extending [VotiveListener].
@export var listener: Script
## The Votive's other numbers, by name ([method VotiveListener.params_used] lists the ones its
## listener reads; validation requires exactly those).
@export var params: Dictionary[String, int] = {}
## The coefficient, per-mille, of the proc events its own hits raise (0 for a Votive whose effect
## lands no hit).
@export var hit_coefficient_permille: int = 0
## The two item lines and the in-world line's author.
@export_multiline var mechanical_line: String = ""
@export_multiline var in_world_line: String = ""
@export var author: String = ""


## The file a Votive id names: content/votives/<id>.tres, or tests/votives/<name>.tres for an id
## starting "test_".
static func path_for(votive_id: String) -> String:
	if votive_id.begins_with(TEST_PREFIX):
		return TEST_ROOT + votive_id.trim_prefix(TEST_PREFIX) + ".tres"
	return CONTENT_ROOT + votive_id + ".tres"


## The id a Votive file at [param path] must carry.
static func id_for_path(path: String) -> String:
	var base: String = path.get_file().get_basename()
	if path.begins_with(TEST_ROOT):
		return TEST_PREFIX + base
	return base


## True if [param votive_id] names a Votive file.
static func exists(votive_id: String) -> bool:
	return votive_id.is_valid_identifier() and ResourceLoader.exists(path_for(votive_id))


## A new instance of its listener, or null if the script is not a [VotiveListener].
func make_listener() -> VotiveListener:
	var script: GDScript = listener as GDScript
	if script == null or not script.can_instantiate():
		return null
	var made: Object = script.new()
	return made as VotiveListener


## True if it listens to [param trigger].
func hears(trigger: String) -> bool:
	return listens_to.has(trigger)


## The mechanical line with its numbers filled in at [param stacks].
func mechanical_text(stacks: int) -> String:
	var per: int = curve.per_stack if curve != null else 0
	var total: int = 0
	if curve != null:
		total = curve.value(stacks)
		if curve.kind != StackingCurve.LINEAR:
			total /= StackingCurve.PPM / StackingCurve.PERMILLE
	var text: String = mechanical_line.replace("{per_stack}", _shown(per))
	text = text.replace("{total}", _shown(total))
	for param_name: String in params:
		text = text.replace("{%s}" % param_name, str(params[param_name]))
	return text


## The "{...}" tokens in the mechanical line that name nothing it can fill in.
func unknown_tokens() -> PackedStringArray:
	var out: PackedStringArray = []
	var re := RegEx.create_from_string("\\{([^}]*)\\}")
	for m: RegExMatch in re.search_all(mechanical_line):
		var token: String = m.get_string(1)
		if token != "per_stack" and token != "total" and not params.has(token):
			out.append(token)
	return out


func _shown(amount: int) -> String:
	if unit != "permille":
		return str(amount)
	var whole: int = amount / 10
	var tenth: int = amount % 10
	return ("%d%%" % whole) if tenth == 0 else ("%d.%d%%" % [whole, tenth])


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	var where: String = resource_path
	if id == "" or not id.is_valid_identifier():
		e.append("a Votive needs an id that is an identifier")
	elif where != "" and id != id_for_path(where):
		e.append("id '%s' must be '%s' (its file's name)" % [id, id_for_path(where)])
	if display_name.strip_edges() == "":
		e.append("%s: a Votive needs a name" % id)
	if curve == null:
		e.append("%s: a Votive needs a stacking curve" % id)
	else:
		for problem: String in curve.validate():
			e.append("%s: %s" % [id, problem])
	if not UNITS.has(unit):
		e.append("%s: unit must be one of %s" % [id, ", ".join(UNITS)])
	_validate_triggers(e)
	_validate_listener(e)
	if hit_coefficient_permille < 0 or hit_coefficient_permille > StackingCurve.PERMILLE:
		e.append("%s: hit_coefficient_permille must be 0 to 1000" % id)
	if not where.begins_with(TEST_ROOT):
		_validate_lines(e)
	return e


func _validate_triggers(e: PackedStringArray) -> void:
	if listens_to.is_empty():
		e.append("%s: a Votive listens to at least one trigger" % id)
	for trigger: String in listens_to:
		if not TRIGGERS.has(trigger):
			e.append("%s: unknown trigger '%s' (%s)" % [id, trigger, ", ".join(TRIGGERS)])
		elif listens_to.count(trigger) > 1:
			e.append("%s: trigger '%s' listed twice" % [id, trigger])
	if curve == null:
		return
	# The bus rolls a "hit" Votive's chance from its curve; nothing else rolls a curve.
	var chance: bool = curve.kind == StackingCurve.CHANCE
	if hears("hit") != chance:
		e.append("%s: a Votive listens to 'hit' exactly when its curve is a chance" % id)


## The listener extends [VotiveListener], defines the hook of every trigger it hears and no other,
## and its resource holds exactly the numbers it reads.
func _validate_listener(e: PackedStringArray) -> void:
	var made: VotiveListener = make_listener()
	if made == null:
		e.append("%s: its listener must be a script extending VotiveListener" % id)
		return
	for i: int in range(TRIGGERS.size()):
		var has_hook: bool = declares(listener, HOOKS[i])
		if hears(TRIGGERS[i]) and not has_hook:
			e.append("%s: listens to '%s' but its listener has no %s" % [id, TRIGGERS[i], HOOKS[i]])
		elif has_hook and not hears(TRIGGERS[i]):
			e.append("%s: its listener has %s but does not list '%s'" % [id, HOOKS[i], TRIGGERS[i]])
	var used: PackedStringArray = made.params_used()
	for param_name: String in used:
		if not params.has(param_name):
			e.append(
				"%s: its listener reads param '%s', which the resource lacks" % [id, param_name]
			)
	for param_name: String in params:
		if not used.has(param_name):
			e.append("%s: param '%s' is not read by its listener" % [id, param_name])


func _validate_lines(e: PackedStringArray) -> void:
	if mechanical_line.strip_edges() == "":
		e.append("%s: a content Votive needs its mechanical line" % id)
	if in_world_line.strip_edges() == "":
		e.append("%s: a content Votive needs its in-world line" % id)
	if author.strip_edges() == "":
		e.append("%s: a content Votive's in-world line needs its author" % id)
	if in_world_line.contains("{") or author.contains("{"):
		e.append("%s: only the mechanical line takes numbers" % id)
	for token: String in unknown_tokens():
		e.append("%s: the mechanical line's {%s} names no number of the Votive" % [id, token])


## True if [param script]'s own source declares the method [param method_name] (an override of a
## [VotiveListener] hook, not the base's empty one).
static func declares(script: Script, method_name: String) -> bool:
	var re := RegEx.create_from_string("(?m)^func\\s+" + method_name + "\\s*\\(")
	return re.search(script.source_code) != null
