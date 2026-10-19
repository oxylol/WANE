extends GdUnitTestSuite
## The Votive's schema (CLAUDE.md, Content: "every ... Votive ... is a .tres resource ... with a
## schema validated in CI"; docs/adr/0015): what validation refuses, the item lines, the ids and
## where a Votive's file lives.

const TEST_VOTIVES: String = "res://tests/votives"
const CHAIN: String = "res://tests/votives/chain_spark.tres"
const HIT_SOURCE: String = (
	"extends VotiveListener\n\n\nfunc on_proc(api: ProcApi) -> void:\n"
	+ "\tapi.hit(api.target(), 1)\n"
)


## The chain spark as a Votive with no file, which validation holds to content's rules: with its
## item lines and an id of its own it is valid.
func _good() -> Votive:
	var v: Votive = _chain().duplicate(true)
	v.id = "sparkler"
	v.mechanical_line = "Hits arc for {damage} damage, {total} chance. +{per_stack} per stack."
	v.in_world_line = "It hums."
	v.author = "a chandler"
	return v


func _chain() -> Votive:
	return load(CHAIN) as Votive


func _problems(v: Votive) -> PackedStringArray:
	return v.validate()


func test_every_test_votive_validates() -> void:
	var found: int = 0
	for path: String in FileWalk.find(TEST_VOTIVES, [".tres"]):
		var v: Votive = load(path) as Votive
		assert_object(v).override_failure_message("%s is not a Votive" % path).is_not_null()
		assert_array(Array(v.validate())).override_failure_message(path).is_empty()
		assert_str(v.id).is_equal(Votive.id_for_path(path))
		found += 1
	assert_int(found).is_greater_equal(6)


func test_ids_and_paths() -> void:
	assert_str(Votive.path_for("bell_of_the_vigil")).is_equal(
		"res://content/votives/bell_of_the_vigil.tres"
	)
	assert_str(Votive.path_for("test_chain_spark")).is_equal("res://tests/votives/chain_spark.tres")
	assert_str(Votive.id_for_path("res://tests/votives/chain_spark.tres")).is_equal(
		"test_chain_spark"
	)
	assert_str(Votive.id_for_path("res://content/votives/hollow_step.tres")).is_equal("hollow_step")
	assert_bool(Votive.exists("test_chain_spark")).is_true()
	assert_bool(Votive.exists("test_no_such_votive")).is_false()
	assert_bool(Votive.exists("../escape")).is_false()


func test_validation_refuses_what_the_schema_forbids() -> void:
	var cases: Dictionary[String, Callable] = {
		"no id": func(v: Votive) -> void: v.id = "",
		"an id that is no identifier": func(v: Votive) -> void: v.id = "a-b",
		"no name": func(v: Votive) -> void: v.display_name = " ",
		"no curve": func(v: Votive) -> void: v.curve = null,
		"a bad curve": func(v: Votive) -> void: v.curve.first_stack = 0,
		"unknown unit": func(v: Votive) -> void: v.unit = "hearts",
		"no trigger": func(v: Votive) -> void: v.listens_to = PackedStringArray(),
		"unknown trigger": func(v: Votive) -> void: v.listens_to = PackedStringArray(["kill"]),
		"a trigger twice": func(v: Votive) -> void: v.listens_to.append("hit"),
		"hit without a chance": func(v: Votive) -> void: v.curve.kind = StackingCurve.LINEAR,
		"a hook it does not list":
		func(v: Votive) -> void: v.listens_to = PackedStringArray(["bounce"]),
		"no listener": func(v: Votive) -> void: v.listener = null,
		"a param it never reads": func(v: Votive) -> void: v.params["extra"] = 1,
		"a param it reads, missing": func(v: Votive) -> void: v.params.erase("damage"),
		"a coefficient over 1.0": func(v: Votive) -> void: v.hit_coefficient_permille = 1001,
	}
	assert_array(Array(_problems(_good()))).is_empty()
	for label: String in cases:
		var v: Votive = _good()
		var change: Callable = cases[label]
		change.call(v)
		assert_array(Array(_problems(v))).override_failure_message(label).is_not_empty()


func test_a_votive_in_a_file_carries_the_files_id() -> void:
	var v: Votive = _chain()
	assert_array(Array(_problems(v))).is_empty()
	v.id = "test_other"
	var problems: PackedStringArray = _problems(v)
	v.id = "test_chain_spark"
	assert_array(Array(problems)).is_not_empty()


func test_a_listener_that_is_not_one_is_refused() -> void:
	var v: Votive = _good()
	var script := GDScript.new()
	script.source_code = "extends RefCounted\n\n\nfunc on_proc(_api: ProcApi) -> void:\n\tpass\n"
	script.reload()
	v.listener = script
	assert_array(Array(_problems(v))).is_not_empty()
	assert_object(v.make_listener()).is_null()


func test_a_hook_is_found_in_the_listeners_own_source() -> void:
	var script := GDScript.new()
	script.source_code = HIT_SOURCE
	script.reload()
	assert_bool(Votive.declares(script, "on_proc")).is_true()
	assert_bool(Votive.declares(script, "on_bounce")).is_false()


func test_a_content_votive_needs_its_lines() -> void:
	var bare: Votive = _good()
	assert_array(Array(_problems(bare))).is_empty()
	for field: String in ["mechanical_line", "in_world_line", "author"]:
		var missing: Votive = bare.duplicate(true)
		missing.set(field, "")
		assert_array(Array(_problems(missing))).override_failure_message(field).is_not_empty()
	var numbered: Votive = bare.duplicate(true)
	numbered.in_world_line = "It hums {total} times."
	assert_array(Array(_problems(numbered))).is_not_empty()
	var stale: Votive = bare.duplicate(true)
	stale.mechanical_line = "Hits arc for {radius_u} units."
	assert_array(Array(stale.unknown_tokens())).is_equal(["radius_u"])
	assert_array(Array(_problems(stale))).is_not_empty()


func test_the_mechanical_line_shows_the_live_numbers() -> void:
	var v: Votive = _good()
	v.mechanical_line = "{total} chance, {damage} damage. +{per_stack} per stack."
	assert_str(v.mechanical_text(1)).is_equal("10% chance, 1 damage. +10% per stack.")
	assert_str(v.mechanical_text(15)).is_equal("150% chance, 1 damage. +10% per stack.")
	v.curve.first_stack = 25
	v.curve.per_stack = 25
	assert_str(v.mechanical_text(1)).is_equal("2.5% chance, 1 damage. +2.5% per stack.")
	v.unit = "count"
	v.curve.kind = StackingCurve.LINEAR
	v.curve.first_stack = 3
	v.curve.per_stack = 3
	assert_str(v.mechanical_text(4)).is_equal("12 chance, 1 damage. +3 per stack.")
