extends GdUnitTestSuite
## How procs show (BUILD.md section 10: "Every proc has a short, distinct, sub-10-frame VFX ... one
## bright thing per 100x100 u region per 3 frames"; docs/adr/0015): a proc's mark at PROC
## priority, part of its own hit's feedback, culled by anything else that holds its cell, once per
## Votive per hit, each Votive distinct; and the F3 overlay's proc lines and marks.

const AT := Vector2i(500 * Fx.SUB, 300 * Fx.SUB)


func _tuning() -> FeedbackTuning:
	return load(FeedbackTuning.PATH) as FeedbackTuning


## A simulation holding [param votives] (test Votive ids, one stack each), stepped once, with no
## events of its own.
func _sim(votives: Array[String]) -> Simulation:
	var sc: Scenario = Scenario.make(1, "test/dummy")
	for votive_id: String in votives:
		sc.options["votive_" + votive_id] = 1
	var sim := Simulation.new(sc)
	sim.step(InputFrame.new())
	sim.events.clear()
	return sim


## [param sim]'s events gain a light hit at [param at].
static func _hit(sim: Simulation, at: Vector2i) -> void:
	sim.events.add(SimEvents.HIT, at.x, at.y, HitKind.encode(HitKind.LIGHT, 1, 0))


func _fed(sim: Simulation) -> VfxBudget:
	var fb: HitFeedback = auto_free(HitFeedback.new(_tuning()))
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	fb.attach(vfx, null)
	fb.on_tick(sim)
	return vfx


func _marks(vfx: VfxBudget) -> Array[VfxBudget.Effect]:
	var out: Array[VfxBudget.Effect] = []
	for e: VfxBudget.Effect in vfx.effects:
		if e.kind == VfxBudget.PROC_MARK:
			out.append(e)
	return out


static func _proc(slot: int, level: int) -> int:
	return slot + ProcBus.LEVEL_SHIFT * level


func test_a_proc_on_its_own_hit_joins_the_hit() -> void:
	var sim: Simulation = _sim(["test_chain_spark"])
	_hit(sim, AT)
	sim.events.add(SimEvents.PROC, AT.x, AT.y, _proc(0, 1))
	var vfx: VfxBudget = _fed(sim)
	assert_int(_marks(vfx).size()).is_equal(1)
	assert_int(vfx.refused).is_zero()
	var mark: VfxBudget.Effect = _marks(vfx)[0]
	assert_int(mark.priority).is_equal(VfxBudget.PROC)
	assert_int(mark.life).is_less_equal(ProcLook.MAX_FRAMES)


func test_a_votive_shows_once_per_hit_however_often_it_fired() -> void:
	var sim: Simulation = _sim(["test_chain_spark", "test_tally"])
	_hit(sim, AT)
	for level: int in [1, 2, 3]:
		sim.events.add(SimEvents.PROC, AT.x, AT.y, _proc(0, level))
		sim.events.add(SimEvents.PROC, AT.x, AT.y, _proc(1, level))
	var vfx: VfxBudget = _fed(sim)
	var marks: Array[VfxBudget.Effect] = _marks(vfx)
	assert_int(marks.size()).is_equal(2)
	# Distinct per Votive: two Votives with no authored look differ by their slot's fallback.
	(
		assert_bool(marks[0].variant != marks[1].variant or marks[0].colour != marks[1].colour)
		. is_true()
	)


func test_a_proc_elsewhere_is_culled_by_a_hit_holding_its_cell() -> void:
	var near := Vector2i(AT.x + 20 * Fx.SUB, AT.y)
	var sim: Simulation = _sim(["test_chain_spark"])
	_hit(sim, AT)
	sim.events.add(SimEvents.PROC, near.x, near.y, _proc(0, 2))
	var vfx: VfxBudget = _fed(sim)
	assert_int(_marks(vfx).size()).is_equal(0)
	assert_int(vfx.refused).is_equal(1)


func test_procs_in_an_empty_cell_are_one_bright_thing() -> void:
	var sim: Simulation = _sim(["test_chain_spark", "test_tally"])
	sim.events.add(SimEvents.PROC, AT.x, AT.y, _proc(0, 1))
	sim.events.add(SimEvents.PROC, AT.x, AT.y, _proc(1, 1))
	var vfx: VfxBudget = _fed(sim)
	assert_int(_marks(vfx).size()).is_equal(1)
	assert_int(vfx.refused).is_equal(1)


func test_a_proc_never_displaces_a_hit_spark_arriving_after_it() -> void:
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	var at := Vector2(AT) / Fx.SUB
	assert_bool(vfx.spawn(VfxBudget.PROC_MARK, VfxBudget.PROC, at, Vector2.UP, 0, 20.0)).is_true()
	assert_bool(vfx.spawn(VfxBudget.SPARK, VfxBudget.HIT, at)).is_true()
	assert_int(vfx.displaced).is_equal(1)
	assert_bool(vfx.spawn(VfxBudget.PROC_MARK, VfxBudget.PROC, at, Vector2.UP, 1, 20.0)).is_false()


func test_a_proc_damage_hit_shows_no_spark() -> void:
	var sim: Simulation = _sim(["test_chain_spark"])
	sim.events.add(SimEvents.HIT, AT.x, AT.y, HitKind.encode(HitKind.PROC, 0, 0))
	var vfx: VfxBudget = _fed(sim)
	assert_int(vfx.effects.size()).is_zero()


func test_every_shape_draws() -> void:
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	add_child(vfx)
	for shape: int in range(ProcLook.SHAPE_NAMES.size()):
		var at := Vector2(150.0 * shape, 0.0)
		vfx.spawn(
			VfxBudget.PROC_MARK, VfxBudget.PROC, at, Vector2.UP, shape, 20.0, Color.WHITE, 0, 8
		)
	assert_int(_marks(vfx).size()).is_equal(ProcLook.SHAPE_NAMES.size())
	vfx.queue_redraw()
	await get_tree().process_frame


func test_looks_validate() -> void:
	var looks: ProcLooks = load(ProcLooks.PATH) as ProcLooks
	assert_array(Array(looks.validate())).is_empty()
	var long := ProcLook.new()
	long.votive_id = "x"
	long.frames = ProcLook.MAX_FRAMES + 1
	assert_array(Array(long.validate())).is_not_empty()
	var twins: ProcLooks = looks.duplicate(true)
	var a := ProcLook.new()
	a.votive_id = "a"
	var b := ProcLook.new()
	b.votive_id = "b"
	twins.looks.append(a)
	twins.looks.append(b)
	var problems: PackedStringArray = twins.validate()
	var alike: bool = false
	for p: String in problems:
		alike = alike or p.contains("same shape and colour")
	assert_bool(alike).is_true()


func test_the_fallback_differs_by_slot() -> void:
	var looks: ProcLooks = load(ProcLooks.PATH) as ProcLooks
	var seen: Dictionary[String, int] = {}
	for slot: int in range(ProcLook.SHAPE_NAMES.size() * looks.fallback_colours.size()):
		var look: ProcLook = looks.look_for("test_none", slot)
		var key: String = "%d %s" % [look.shape, look.colour.to_html()]
		assert_bool(seen.has(key)).override_failure_message("slot %d" % slot).is_false()
		seen[key] = slot
		assert_int(look.frames).is_less_equal(ProcLook.MAX_FRAMES)


func test_the_overlay_lists_the_votives_and_this_ticks_procs() -> void:
	var sc: Scenario = Scenario.make(1, "test/dummy")
	sc.options["votive_test_chain_spark"] = 10
	var sim := Simulation.new(sc)
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	overlay.attach_sim(sim, null)
	var press := InputFrame.make(InputFrame.ATTACK, InputFrame.ATTACK, 0, 0)
	sim.step(press)
	var lines: PackedStringArray = overlay.proc_lines(sim)
	assert_str(lines[0]).is_equal("votives test_chain_spark x10")
	assert_str(lines[1]).is_equal("procs this tick 0 from 0 events, deepest L0")
	sim.step(InputFrame.new())
	sim.step(InputFrame.new())
	lines = overlay.proc_lines(sim)
	assert_str(lines[1]).is_equal(
		"procs this tick 3 from 4 events, deepest L3: test_chain_spark x3"
	)
	var marks: Array[DebugBoxes.Box] = []
	for box: DebugBoxes.Box in DebugBoxes.collect(sim, Rect2(0, 0, 4000, 4000)):
		if box.kind == DebugBoxes.PROC:
			marks.append(box)
	assert_int(marks.size()).is_equal(1)
	assert_str(marks[0].label).is_equal("test_chain_spark L1 L2 L3")
	var none := Simulation.new(Scenario.make(1, "test/dummy"))
	assert_str(overlay.proc_lines(none)[0]).is_equal("votives none")


func test_a_burst_of_several_votives_has_a_short_label() -> void:
	var sc: Scenario = Scenario.make(1, "test/dummy_pair")
	for votive_id: String in ["test_stress_arc_a", "test_stress_arc_b", "test_stress_arc_c"]:
		sc.options["votive_" + votive_id] = 1
	var sim := Simulation.new(sc)
	sim.step(InputFrame.make(InputFrame.ATTACK, InputFrame.ATTACK, 0, 0))
	sim.step(InputFrame.new())
	sim.step(InputFrame.new())
	var labels: Array[String] = []
	for box: DebugBoxes.Box in DebugBoxes.collect(sim, Rect2(0, 0, 4000, 4000)):
		if box.kind == DebugBoxes.PROC:
			labels.append(box.label)
	# Level 1 and 3 fire on the near dummy's hits, level 2 on the far one's (39 in all).
	assert_array(labels).contains_exactly(["30 procs, 3 Votives, L1 L3", "9 procs, 3 Votives, L2"])
