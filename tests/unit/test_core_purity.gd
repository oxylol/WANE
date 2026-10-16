extends GdUnitTestSuite
## CorePurity: the mechanical gate for CLAUDE.md architecture rules 1 and 2.


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
	)
	assert_array(Array(_problems(code))).is_empty()


func test_strip_line() -> void:
	assert_str(CorePurity.strip_line('a = "x # y" # c')).is_equal('a = "" ')
	assert_str(CorePurity.strip_line("b = 'q\\'s' + 1")).is_equal("b = '' + 1")
