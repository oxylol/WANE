extends GdUnitTestSuite
## The rules of task 6 core review 2 that only a content check or a unit call can lose silently:
## a startup over 2 frames needs armor through it (BUILD.md section 5), the armor and recoil
## ranges, the event list's has_since, and the armor and charge-hold state (docs/adr/0010,
## docs/adr/0013). The fixtures in tests/replay/combat/ pin the behaviour in play.


func _strike(startup: int, armor: int) -> AttackDef:
	var a := AttackDef.new()
	a.id = "probe"
	a.startup = startup
	a.active = 4
	a.recovery = 8
	a.armor_frames = armor
	return a


func test_startup_over_two_frames_needs_armor_through_it() -> void:
	assert_array(Array(_strike(2, 0).validate())).is_empty()
	assert_array(Array(_strike(3, 3).validate())).is_empty()
	assert_array(Array(_strike(3, 4).validate())).is_empty()
	var errors: PackedStringArray = _strike(3, 2).validate()
	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0]).contains("needs armor through it")
	assert_int(_strike(4, 0).validate().size()).is_equal(1)


func test_armor_frames_must_lie_inside_the_strike() -> void:
	var negative: PackedStringArray = _strike(2, -1).validate()
	assert_int(negative.size()).is_equal(1)
	assert_str(negative[0]).contains("armor_frames must lie inside")
	var long_armor: AttackDef = _strike(2, 0)
	long_armor.armor_frames = long_armor.total_frames() + 1
	assert_str(long_armor.validate()[0]).contains("armor_frames must lie inside")
	long_armor.armor_frames = long_armor.total_frames()
	assert_array(Array(long_armor.validate())).is_empty()


func test_shipped_strikes_pass_the_armor_rule() -> void:
	var taper: AttackSet = load("res://content/wicks/ash/taper.tres") as AttackSet
	assert_object(taper).is_not_null()
	for a: AttackDef in taper.attacks:
		assert_array(Array(a.validate())).is_empty()
	assert_int(taper.find("side3").armor_frames).is_greater_equal(taper.find("side3").startup)


func test_recoil_frames_must_not_be_negative() -> void:
	var t: CombatTuning = load("res://content/combat/combat.tres") as CombatTuning
	assert_array(Array(t.validate())).is_empty()
	var copy: CombatTuning = t.duplicate() as CombatTuning
	copy.recoil_frames = -1
	assert_int(copy.validate().size()).is_equal(1)
	copy.recoil_frames = 0
	assert_array(Array(copy.validate())).is_empty()


func test_has_since_sees_only_events_from_the_index_on() -> void:
	var ev := SimEvents.new()
	assert_bool(ev.has_since(SimEvents.JUMP, 0)).is_false()
	ev.add(SimEvents.JUMP, 0, 0)
	var mark: int = ev.count()
	assert_bool(ev.has_since(SimEvents.JUMP, 0)).is_true()
	assert_bool(ev.has_since(SimEvents.JUMP, mark)).is_false()
	ev.add(SimEvents.LAND, 0, 0)
	assert_bool(ev.has_since(SimEvents.LAND, mark)).is_true()
	assert_bool(ev.has_since(SimEvents.JUMP, mark)).is_false()
	ev.clear()
	assert_bool(ev.has_since(SimEvents.LAND, 0)).is_false()


func _player() -> Player:
	var sc: Scenario = Scenario.make(1)
	sc.room = "test/flat"
	return Simulation.new(sc).player


func test_armored_covers_only_the_armor_frames_of_a_strike() -> void:
	var pl: Player = _player()
	assert_bool(PlayerCombat.armored(pl)).is_false()
	pl.action = pl.attacks.index_of("side3")
	var armor: int = pl.current_attack().armor_frames
	assert_int(armor).is_greater(0)
	pl.action_frame = armor
	assert_bool(PlayerCombat.armored(pl)).is_true()
	pl.action_frame = armor + 1
	assert_bool(PlayerCombat.armored(pl)).is_false()
	pl.action = pl.attacks.index_of("side1")
	pl.action_frame = 1
	assert_bool(PlayerCombat.armored(pl)).is_false()


func test_break_charge_drops_the_hold_until_it_is_let_go() -> void:
	var pl: Player = _player()
	pl.charge_held = 20
	pl.charge_request = 3
	PlayerCombat.break_charge(pl)
	assert_bool(pl.charge_broken).is_true()
	assert_int(pl.charge_held).is_equal(0)
	assert_int(pl.charge_request).is_equal(0)


func test_recoil_move_ends_on_a_dash_or_a_cling_and_runs_out() -> void:
	var pl: Player = _player()
	pl.recoil_left = 3
	pl.loco = Player.DASH
	PlayerCombat.recoil_move(pl)
	assert_int(pl.recoil_left).is_equal(0)
	pl.recoil_left = 3
	pl.loco = Player.WALL
	PlayerCombat.recoil_move(pl)
	assert_int(pl.recoil_left).is_equal(0)
	pl.loco = Player.GROUND
	pl.recoil_left = 1
	PlayerCombat.recoil_move(pl)
	assert_int(pl.recoil_left).is_equal(0)
