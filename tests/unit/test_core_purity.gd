extends GdUnitTestSuite
## CorePurity: the mechanical gate for CLAUDE.md architecture rules 1 and 2.

const LISTENER: String = (
	"extends VotiveListener\n## A doc comment may say 120 u and 10%.\n\n"
	+ 'const RADIUS: String = "radius_u"\n\n\n'
	+ "func on_proc(api: ProcApi) -> void:\n"
	+ "\tvar n: int = api.counter() + 1\n"
	+ "\tif api.source() == ProcSource.TAPER and api.roll_permille(api.param(RADIUS)):\n"
	+ "\t\tapi.stun_within(api.param(RADIUS), -1)\n"
	+ "\tapi.set_counter(n)\n\n\n"
	+ "func params_used() -> PackedStringArray:\n"
	+ "\treturn PackedStringArray([RADIUS])\n"
)


func _problems(code: String) -> PackedStringArray:
	return CorePurity.new().check_source(code)


func test_clean_integer_code_passes() -> void:
	var code: String = (
		"var x: int = 256\nvar v: Vector2i = Vector2i(1, 2)\n"
		+ "func f(a: int) -> int:\n\treturn Fx.div_round(a, 3) + absi(a)\n"
	)
	assert_array(Array(_problems(code))).is_empty()


func test_comments_and_strings_are_ignored() -> void:
	var code: String = 'var s: String = "1.5 float sin(x) Node"  # 0.2% of gravity, float\n'
	assert_array(Array(_problems(code))).is_empty()


func test_each_rule_fires() -> void:
	var cases: Array[String] = [
		"var a: float = 0",
		"var a: int = 1.5",
		"var a: int = .5",
		"var a: int = 1e3",
		"var v := Vector2(1, 2)",
		"var a: int = sqrt(4)",
		"var a: int = randi()",
		"var n: Node = null",
		"var t: int = Time.get_ticks_msec()",
		"func _process(d: int) -> void:",
		"var a: int = PI",
		"await something",
		"var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)",
		"f.store_buffer(bytes)",
		"DirAccess.remove_absolute(p)",
		"ResourceSaver.save(res, p)",
		"var c := ConfigFile.new()",
		"var f: FileAccess = FileAccess.open(p, 2)",
	]
	for code: String in cases:
		(
			assert_array(Array(_problems(code)))
			. override_failure_message("expected a problem in: " + code)
			. is_not_empty()
		)


func test_lookalikes_are_allowed() -> void:
	var code: String = (
		"var r: int = Fx.div_round(1, 2) + Fx.div_floor(3, 4)\n"
		+ "var f: InputFrame = InputFrame.new()\nvar s: int = scenario.seed_value\n"
		+ "var x: int = 0x7FFF\nvar r2: Rng = Rng.seeded(1, 2)\n"
		+ "var t: String = FileAccess.get_file_as_string(p)\n"
		+ "var f: FileAccess = FileAccess.open(p, FileAccess.READ)\n"
	)
	assert_array(Array(_problems(code))).is_empty()


func test_strip_line() -> void:
	assert_str(CorePurity.strip_line('a = "x # y" # c')).is_equal('a = "" ')
	assert_str(CorePurity.strip_line("b = 'q\\'s' + 1")).is_equal("b = '' + 1")


# --- Votive listeners: the API boundary (docs/adr/0015) -------------------------------------


func _listener_problems(code: String) -> PackedStringArray:
	return CorePurity.new().check_listener(code)


func test_a_listener_within_the_api_passes() -> void:
	assert_array(Array(_listener_problems(LISTENER))).is_empty()


func test_every_listener_rule_fires() -> void:
	var cases: Array[String] = [
		"var held: int = 0",
		"static var held: int = 0",
		"class_name Sneaky",
		"class Inner:",
		"signal rang",
		"@tool",
		"func f(api: ProcApi) -> void:\n\tapi._bus.votives.clear()",
		'func f() -> void:\n\tvar s: Script = load("res://x.gd")',
		'func f(api: ProcApi) -> void:\n\tapi.call("hit", 0, 1)',
		'func f(api: ProcApi) -> void:\n\tapi.set("_level", 0)',
		"func f() -> void:\n\tprint(self)",
		"func f(api: ProcApi) -> void:\n\tapi.hit(api.target(), 12)",
		"func f(api: ProcApi) -> void:\n\tapi.stun_within(0x40, 1)",
		"func f(api: ProcApi) -> void:\n\tvar c: Combat = null",
		"func f(api: ProcApi) -> void:\n\tvar r: Rng = Rng.seeded(1, 2)",
		"func f() -> void:\n\tvar x: float = 0",
		"func f() -> void:\n\tvar t: int = Time.get_ticks_msec()",
	]
	for code: String in cases:
		var source: String = "extends VotiveListener\n\n\n" + code + "\n"
		(
			assert_array(Array(_listener_problems(source)))
			. override_failure_message("expected a problem in: " + code)
			. is_not_empty()
		)


func test_a_listener_extends_votive_listener() -> void:
	assert_array(Array(_listener_problems("extends RefCounted\n"))).is_not_empty()
	assert_array(Array(_listener_problems("func on_proc() -> void:\n\tpass\n"))).is_not_empty()


func test_the_repository_listeners_pass() -> void:
	assert_array(Array(CorePurity.new().check_votives())).is_empty()
