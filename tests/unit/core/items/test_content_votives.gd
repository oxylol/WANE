extends GdUnitTestSuite
## The content Votives (content/votives/; docs/adr/0015): each validates, carries the doc's numbers
## in its resource, reads its numbers in its mechanical line, and has an in-world line in a voice of
## its own that states no number (BUILD.md section 2: "Nothing in the lore explains a mechanic").

const ROOT: String = "res://content/votives"
## Each Votive's mechanical line at one stack, and at three.
const ONE: Dictionary[String, String] = {
	"tallow_knuckle": "Taper and pogo hits deal +3 damage. +3 per stack.",
	"pilgrims_wick": "Run speed +8%. +8% per stack.",
	"bell_of_the_vigil":
	(
		"Hits have a 10% chance to ring. Past 100%, each whole 100% is a sure ring"
		+ " and the rest a chance of one more; a Kindle tick rolls at half, and Flame and"
		+ " above add a tenth. A ring stuns every enemy within 120 u for 30 frames."
		+ " +10% chance per stack."
	),
	"second_ember": "Air dashes after a pogo bounce: +1 until you land. +1 per stack.",
	"hollow_step": "Your dash has no cooldown. Max hearts -1, never below one. -1 per stack.",
}
const THREE: Dictionary[String, String] = {
	"tallow_knuckle": "Taper and pogo hits deal +9 damage. +3 per stack.",
	"pilgrims_wick": "Run speed +24%. +8% per stack.",
	"bell_of_the_vigil":
	(
		"Hits have a 30% chance to ring. Past 100%, each whole 100% is a sure ring"
		+ " and the rest a chance of one more; a Kindle tick rolls at half, and Flame and"
		+ " above add a tenth. A ring stuns every enemy within 120 u for 30 frames."
		+ " +10% chance per stack."
	),
	"second_ember": "Air dashes after a pogo bounce: +3 until you land. +1 per stack.",
	"hollow_step": "Your dash has no cooldown. Max hearts -3, never below one. -1 per stack.",
}


func _votives() -> Array[Votive]:
	var out: Array[Votive] = []
	for path: String in FileWalk.find(ROOT, [".tres"]):
		out.append(load(path) as Votive)
	return out


func test_every_content_votive_validates() -> void:
	var votives: Array[Votive] = _votives()
	assert_int(votives.size()).is_equal(ONE.size())
	for v: Votive in votives:
		assert_object(v).is_not_null()
		assert_array(Array(v.validate())).override_failure_message(v.id).is_empty()


func test_the_mechanical_lines_read_the_numbers() -> void:
	for v: Votive in _votives():
		assert_str(v.mechanical_text(1)).is_equal(ONE[v.id])
		assert_str(v.mechanical_text(3)).is_equal(THREE[v.id])


func test_the_doc_numbers_are_in_the_resources() -> void:
	var by_id: Dictionary[String, Votive] = {}
	for v: Votive in _votives():
		by_id[v.id] = v
	# BUILD.md section 8, Tiers.
	assert_int(by_id["tallow_knuckle"].curve.value(1)).is_equal(3)
	assert_int(by_id["tallow_knuckle"].tier).is_equal(Votive.Tier.CANDLE)
	assert_int(by_id["pilgrims_wick"].curve.value(1)).is_equal(80)
	assert_int(by_id["pilgrims_wick"].tier).is_equal(Votive.Tier.CANDLE)
	assert_int(by_id["bell_of_the_vigil"].curve.value(1)).is_equal(100000)
	assert_int(by_id["bell_of_the_vigil"].params["radius_u"]).is_equal(120)
	assert_int(by_id["bell_of_the_vigil"].tier).is_equal(Votive.Tier.LANTERN)
	assert_int(by_id["second_ember"].curve.value(2)).is_equal(2)
	assert_int(by_id["second_ember"].tier).is_equal(Votive.Tier.LANTERN)
	assert_int(by_id["hollow_step"].curve.value(1)).is_equal(1)
	assert_int(by_id["hollow_step"].tier).is_equal(Votive.Tier.SOOT)


func test_each_in_world_line_has_its_own_author_and_no_numbers() -> void:
	var authors: Array[String] = []
	var digits := RegEx.create_from_string("[0-9%]")
	for v: Votive in _votives():
		assert_bool(authors.has(v.author)).override_failure_message(v.author).is_false()
		authors.append(v.author)
		assert_object(digits.search(v.in_world_line)).override_failure_message(v.id).is_null()
		assert_bool(v.in_world_line.to_lower().contains(v.display_name.to_lower())).is_false()


func test_every_votive_that_procs_has_its_own_look() -> void:
	var looks: ProcLooks = load(ProcLooks.PATH) as ProcLooks
	assert_array(Array(looks.validate())).is_empty()
	assert_array(Array(ProcLooks.content_proc_ids())).contains_exactly_in_any_order(
		["bell_of_the_vigil", "second_ember"]
	)
	for look: ProcLook in looks.looks:
		assert_int(look.frames).is_less(10)
