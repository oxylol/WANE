extends GdUnitTestSuite
## The combat rules of docs/adr/0013 that need a loop or a sweep rather than one fixture: the parry
## ten times in a row and its window frame by frame, White's tenth hit, Blaze's trail and burst,
## Kindle's cone, Mend's conditions, the dash's invulnerability against a swing, the knockback
## ended by an action, death by hazard, the Charged strike out of a dash, and the order of hits
## within a tick. The fixtures in tests/replay/combat/ pin the rest.

const S: int = InputFrame.STICK_MAX


func _sim(room_id: String, options: Dictionary[String, int] = {}) -> Simulation:
	var sc: Scenario = Scenario.make(1)
	sc.room = room_id
	for key: String in options:
		sc.options[key] = options[key]
	var sim := Simulation.new(sc)
	assert_array(Array(sim.load_errors)).is_empty()
	return sim


## A frame holding [param held] with [param pressed] pressed on it, the stick at ([param x],
## [param y]) in -1..1.
func _in(held: int = 0, pressed: int = 0, x: int = 0, y: int = 0) -> InputFrame:
	return InputFrame.make(held | pressed, pressed, x * S, y * S)


## Steps with neutral input until [param kind] fires or [param limit] ticks pass; the tick it
## fired on (as a fixture frame), or -1.
func _until(sim: Simulation, kind: String, limit: int) -> int:
	for i: int in range(limit):
		sim.step(_in())
		if sim.events.has(kind):
			return sim.tick - 1
	return -1


## The kinds ([HitKind]) of this tick's hit events.
func _hit_kinds(sim: Simulation) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(sim.events.count()):
		if sim.events.kinds[i] == SimEvents.HIT:
			out.append(HitKind.kind_of(sim.events.values[i]))
	return out


func test_a_parry_succeeds_ten_times_in_a_row() -> void:
	# BUILD.md s15 Combat: "Parry succeeds on the 8-frame window ... 10 times in a row". The press
	# turns Ash away from the dummy, so its strike never lands: three hits on the dummy during its
	# telegraph would break its poise and cancel the swing instead (an up-strike reaches it from
	# under 45 u). Between swings Ash walks back into the swing's reach after each parry's
	# knockback.
	var sim: Simulation = _sim("test/dummy_swing")
	var parries: int = 0
	for n: int in range(10):
		# Back within 40 u of the dummy, then stand.
		var guard: int = 0
		while sim.combat.enemies[0].body.x - sim.player.body.x > Fx.units(40) and guard < 400:
			sim.step(_in(0, 0, 1, 0))
			guard += 1
		var tel: int = _until(sim, SimEvents.TELEGRAPH, 400)
		assert_int(tel).override_failure_message("swing %d never came" % n).is_greater(0)
		var lands: int = tel + sim.combat.enemies[0].attack.telegraph
		while sim.tick - 1 < lands - 4:
			sim.step(_in())
		sim.step(_in(0, InputFrame.ATTACK, -1, 0))
		var parried: bool = false
		for i: int in range(8):
			sim.step(_in())
			assert_bool(sim.events.has(SimEvents.PLAYER_HIT)).is_false()
			if sim.events.has(SimEvents.PARRY):
				parried = true
				break
		assert_bool(parried).override_failure_message("swing %d not parried" % n).is_true()
		parries += 1
	assert_int(parries).is_equal(10)
	assert_int(sim.player.vitals.hearts.current).is_equal(5)


func test_the_parry_window_is_the_eight_frames_ending_on_the_landing() -> void:
	# The dummy's swing lands on frame 53; a press at age 0 to 7 there parries, one at age 8 or
	# more is too early and the swing hits.
	for age: int in range(10):
		var sim: Simulation = _sim("test/dummy_swing")
		while sim.tick < 53 - age:
			sim.step(_in())
		sim.step(_in(0, InputFrame.ATTACK, -1, 0))
		while sim.tick < 54:
			sim.step(_in())
		var parried: bool = sim.player.vitals.hearts.current == 5
		(
			assert_bool(parried)
			. override_failure_message("press at age %d on the landing" % age)
			. is_equal(age <= 7)
		)


func test_white_turns_every_tenth_hit_into_a_charged_strike() -> void:
	# BUILD.md s6 Kindling, White: "every 10th hit is an automatic Charged strike". A bot walks
	# into reach and presses attack whenever no strike runs. White is above Blaze, so each strike's
	# fire trail also burns the dummy once, on the tick the strike lands (a burn, not a hit).
	var sim: Simulation = _sim("test/dummy", {"kindling": 40})
	var e: Enemy = sim.combat.enemies[0]
	# Enough health that ten White hits and their trails never kill it.
	e.max_hp = 1000
	e.hp = 1000
	var hits: int = 0
	var guard: int = 0
	while hits < 10 and guard < 2000:
		guard += 1
		var pl: Player = sim.player
		var hp: int = e.hp
		if e.body.x - pl.body.x > Fx.units(50):
			sim.step(_in(0, 0, 1, 0))
		elif pl.action == Player.NO_ACTION and pl.freeze == 0:
			sim.step(_in(0, InputFrame.ATTACK))
		else:
			sim.step(_in())
		var kinds: Array[int] = _hit_kinds(sim)
		var struck: bool = (
			kinds.has(HitKind.LIGHT) or kinds.has(HitKind.FINISHER) or kinds.has(HitKind.CHARGED)
		)
		if not struck:
			continue
		hits += 1
		assert_bool(kinds.has(HitKind.CHARGED)).override_failure_message("hit %d" % hits).is_equal(
			hits == 10
		)
		if hits == 10:
			# 36 with White's +30%: 46.8, rounded to 47; and the trail's 4 + 30%, rounded to 5.
			assert_int(hp - e.hp).is_equal(47 + (5 if kinds.has(HitKind.BURN) else 0))
	assert_int(hits).is_equal(10)


func test_a_blaze_trail_burns_an_enemy_once_per_strike() -> void:
	# BUILD.md s6 Kindling, Blaze: "attacks leave a 10 f fire trail that damages". Side 1 at Blaze
	# deals 12 (10 + 20%), and its trail 5 (4 + 20%, rounded) once, however long it lies there.
	var sim: Simulation = _sim("test/dummy", {"kindling": 20})
	sim.step(_in(0, InputFrame.ATTACK))
	var burns: int = 0
	for i: int in range(30):
		sim.step(_in())
		for k: int in _hit_kinds(sim):
			if k == HitKind.BURN:
				burns += 1
	assert_int(burns).is_equal(1)
	assert_int(sim.combat.enemies[0].hp).is_equal(200 - 12 - 5)


func test_a_finisher_at_blaze_burns_the_enemies_near_the_one_it_hits() -> void:
	# "finishers cause a small AoE" (docs/adr/0013: 8 damage within 96 u). The far dummy is out of
	# the Taper's reach; only side 3's burst touches it, for 10 (8 + 20%).
	var sim: Simulation = _sim("test/dummy_pair", {"kindling": 20})
	var far: Enemy = sim.combat.enemies[1]
	for f: int in range(40):
		var press: int = InputFrame.ATTACK if f == 0 or f == 7 or f == 14 else 0
		sim.step(_in(0, press))
		if sim.player.current_attack() != null and sim.player.current_attack().id != "side3":
			assert_int(far.hp).override_failure_message("frame %d" % f).is_equal(200)
	assert_int(far.hp).is_equal(190)


func test_a_new_ignition_restarts_the_burn_without_stacking() -> void:
	var sim: Simulation = _sim("test/dummy_far", {"flame": 66})
	sim.step(_in(0, InputFrame.SPELL))
	for i: int in range(40):
		sim.step(_in())
	var e: Enemy = sim.combat.enemies[0]
	assert_int(e.burn_left).is_between(1, 80)
	sim.step(_in(0, InputFrame.SPELL))
	while e.burn_left < 80:
		sim.step(_in())
		assert_int(sim.tick).is_less(60)
	assert_int(e.burn_left).is_equal(90)


func test_the_kindle_cone_is_three_rectangles_widening_along_the_stick() -> void:
	var pl: Player = _sim("test/flat").player
	pl.spell = PlayerSpells.KINDLE
	pl.spell_frame = pl.kit.kindle_startup + 1
	var b: Body = pl.body
	var c := Vector2i(b.x, b.y - b.height / 2)
	var widths: Array[int] = [40, 68, 96]
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		pl.spell_dir = dir
		var boxes: Array[Rect2i] = PlayerSpells.kindle_boxes(pl)
		assert_int(boxes.size()).is_equal(3)
		for i: int in range(3):
			var r: Rect2i = boxes[i]
			var across: int = r.size.y if dir.x != 0 else r.size.x
			assert_int(across).is_equal(Fx.units(widths[i]))
			# Along the stick, the sections tile the 180 u from the centre outward.
			var near: Vector2i = c + dir * Fx.units(60 * i)
			var far: Vector2i = c + dir * Fx.units(60 * (i + 1))
			var lo: int = mini(near.x, far.x) if dir.x != 0 else mini(near.y, far.y)
			var hi: int = maxi(near.x, far.x) if dir.x != 0 else maxi(near.y, far.y)
			var r_lo: int = r.position.x if dir.x != 0 else r.position.y
			var r_hi: int = r.end.x if dir.x != 0 else r.end.y
			assert_int(r_lo).is_equal(lo)
			assert_int(r_hi).is_equal(hi)
	pl.spell_frame = pl.kit.kindle_startup
	assert_array(PlayerSpells.kindle_boxes(pl)).is_empty()
	pl.spell_frame = pl.kit.kindle_startup + pl.kit.kindle_active + 1
	assert_array(PlayerSpells.kindle_boxes(pl)).is_empty()


func test_kindle_goes_down_only_in_the_air() -> void:
	var sim: Simulation = _sim("test/flat", {"flame": 66})
	sim.step(_in(0, InputFrame.SPELL, 0, 1))
	assert_int(sim.player.spell).is_equal(PlayerSpells.KINDLE)
	assert_that(sim.player.spell_dir).is_equal(Vector2i(1, 0))
	var air: Simulation = _sim("test/flat", {"flame": 66})
	air.step(_in(0, InputFrame.JUMP))
	for i: int in range(5):
		air.step(_in(InputFrame.JUMP))
	air.step(_in(InputFrame.JUMP, InputFrame.SPELL, 0, 1))
	assert_that(air.player.spell_dir).is_equal(Vector2i(0, 1))


func test_a_strike_or_a_toss_pressed_during_kindle_waits_for_its_frame_8() -> void:
	for button: int in [InputFrame.ATTACK, InputFrame.TOSS]:
		var sim: Simulation = _sim("test/flat", {"flame": 33})
		sim.step(_in(0, InputFrame.SPELL))
		sim.step(_in())
		sim.step(_in(0, button))
		while sim.player.spell_frame < 7:
			sim.step(_in())
			assert_int(sim.player.action).is_equal(Player.NO_ACTION)
			assert_bool(sim.player.toss.active or sim.player.toss.startup > 0).is_false()
		sim.step(_in())
		var started: bool = (
			sim.player.action != Player.NO_ACTION
			or sim.player.toss.startup > 0
			or sim.player.toss.active
		)
		assert_bool(started).override_failure_message("button %d" % button).is_true()
		assert_int(sim.player.spell).is_equal(PlayerSpells.NONE)


func test_a_spell_pressed_late_in_a_strike_casts_when_the_strike_ends() -> void:
	var sim: Simulation = _sim("test/flat", {"flame": 33})
	sim.step(_in(0, InputFrame.ATTACK))
	for f: int in range(1, 20):
		sim.step(_in(0, InputFrame.SPELL if f == 8 else 0))
		if f < 14:
			assert_int(sim.player.spell).override_failure_message("frame %d" % f).is_equal(0)
	assert_int(sim.player.spell).is_equal(PlayerSpells.KINDLE)


func test_mend_needs_the_ground_a_missing_heart_and_the_flame() -> void:
	var full: Simulation = _sim("test/flat", {"flame": 33})
	full.step(_in(0, InputFrame.MEND))
	assert_int(full.player.spell).is_equal(PlayerSpells.NONE)
	var poor: Simulation = _sim("test/flat", {"flame": 32, "hearts": 4})
	poor.step(_in(0, InputFrame.MEND))
	assert_int(poor.player.spell).is_equal(PlayerSpells.NONE)
	var air: Simulation = _sim("test/flat", {"flame": 33, "hearts": 4})
	air.step(_in(0, InputFrame.JUMP))
	air.step(_in(InputFrame.JUMP, InputFrame.MEND))
	assert_int(air.player.spell).is_equal(PlayerSpells.NONE)
	assert_int(air.player.vitals.flame.value).is_equal(33)


func test_a_hit_ends_mend_and_the_flame_is_lost() -> void:
	var sim: Simulation = _sim("test/dummy_swing", {"flame": 33, "hearts": 4})
	while sim.tick < 20:
		sim.step(_in())
	sim.step(_in(0, InputFrame.MEND))
	while sim.tick < 54:
		sim.step(_in(InputFrame.MEND))
	assert_int(sim.player.spell).is_equal(PlayerSpells.NONE)
	assert_int(sim.player.vitals.hearts.current).is_equal(3)
	assert_int(sim.player.vitals.flame.value).is_equal(0)


func test_mend_stands_still_whatever_the_stick() -> void:
	var sim: Simulation = _sim("test/flat", {"flame": 33, "hearts": 4})
	sim.step(_in(0, InputFrame.MEND))
	var x: int = sim.player.body.x
	for i: int in range(20):
		sim.step(_in(InputFrame.MEND, 0, 1, 0))
	assert_int(sim.player.body.x).is_equal(x)
	assert_int(sim.player.spell).is_equal(PlayerSpells.MEND)


func test_the_dash_invulnerability_dodges_a_whole_swing() -> void:
	# The swing is live on frames 53 to 56; a dash from frame 50 is invulnerable on its frames 1 to
	# 7 (frames 50 to 56) and passes through the dummy, which is not solid.
	var sim: Simulation = _sim("test/dummy_swing")
	while sim.tick < 50:
		sim.step(_in())
	sim.step(_in(0, InputFrame.DASH, 1, 0))
	for i: int in range(20):
		sim.step(_in())
		assert_bool(sim.events.has(SimEvents.PLAYER_HIT)).is_false()
	assert_int(sim.player.vitals.hearts.current).is_equal(5)


func test_any_action_ends_the_knockback() -> void:
	var sim: Simulation = _sim("test/dummy_swing")
	assert_int(_until(sim, SimEvents.PLAYER_HIT, 60)).is_equal(53)
	while sim.player.freeze > 0:
		sim.step(_in())
	sim.step(_in())
	assert_int(sim.player.knock_left).is_greater(0)
	sim.step(_in(0, InputFrame.JUMP))
	assert_int(sim.player.knock_left).is_equal(0)
	assert_int(sim.player.body.vy).is_less(0)


func test_a_hazard_on_the_last_heart_returns_to_the_spawn() -> void:
	var sim: Simulation = _sim("test/spikes", {"hearts": 1, "flame": 40})
	var died: bool = false
	for i: int in range(60):
		sim.step(_in(0, 0, 1, 0))
		if sim.events.has(SimEvents.DEATH):
			died = true
			break
	assert_bool(died).is_true()
	assert_int(sim.player.body.x).is_equal(Fx.units(sim.room.spawn_x_u))
	assert_int(sim.player.vitals.hearts.current).is_equal(5)
	assert_int(sim.player.vitals.flame.value).is_equal(0)


func test_the_charged_strike_waits_for_the_dash_to_allow_a_strike() -> void:
	var sim: Simulation = _sim("test/flat")
	sim.step(_in(0, InputFrame.ATTACK))
	while sim.tick < 26:
		sim.step(_in(InputFrame.ATTACK))
	sim.step(_in(0, InputFrame.DASH))
	assert_int(sim.player.loco).is_equal(Player.DASH)
	while sim.player.loco == Player.DASH and sim.player.dash_frame < 5:
		sim.step(_in())
		assert_int(sim.player.action).is_equal(Player.NO_ACTION)
	sim.step(_in())
	assert_str(sim.player.current_attack().id).is_equal("charged")


func test_a_kill_on_the_landing_tick_takes_the_swing_away() -> void:
	# The player's hits resolve before the enemies' (docs/adr/0013): side 1 pressed on frame 51
	# lands its box on frame 53, the swing's landing frame, and kills the 10 hp dummy first.
	var sim: Simulation = _sim("test/dummy_frail_swing")
	while sim.tick < 51:
		sim.step(_in())
	sim.step(_in(0, InputFrame.ATTACK))
	sim.step(_in())
	sim.step(_in())
	assert_bool(sim.events.has(SimEvents.KILL)).is_true()
	assert_bool(sim.events.has(SimEvents.PLAYER_HIT)).is_false()
	assert_int(sim.player.vitals.hearts.current).is_equal(5)
