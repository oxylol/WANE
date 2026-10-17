extends GdUnitTestSuite
## Strike and pogo hitboxes (BUILD.md section 5 Pogo "Hitbox: 36 u wide, 24 u tall, under the
## player"; section 6 Taper "the hitbox extends 68 u from the player's center"), and the hurtbox
## inside the collider (CLAUDE.md rule 8).

const U: int = Fx.SUB


func _sim(spawn_y: int) -> Simulation:
	var sc: Scenario = Scenario.make(1)
	sc.room = "test/flat"
	sc.spawn_x = 400
	sc.spawn_y = spawn_y
	return Simulation.new(sc)


func _step(sim: Simulation, held: int, stick_x: int = 0, stick_y: int = 0) -> void:
	sim.step(InputFrame.make(held, held, stick_x, stick_y))


func test_pogo_box_is_36_by_24_under_the_feet_on_frames_3_to_9() -> void:
	var sim: Simulation = _sim(200)
	_step(sim, InputFrame.ATTACK, 0, InputFrame.STICK_MAX)
	assert_object(sim.player.current_attack()).is_not_null()
	assert_str(sim.player.current_attack().id).is_equal("down")
	assert_bool(sim.player.pogo_box().size == Vector2i.ZERO).is_true()
	sim.step(InputFrame.make(InputFrame.ATTACK, 0, 0, InputFrame.STICK_MAX))
	sim.step(InputFrame.make(InputFrame.ATTACK, 0, 0, InputFrame.STICK_MAX))
	var b: Body = sim.player.body
	var box: Rect2i = sim.player.pogo_box()
	assert_int(sim.player.action_frame).is_equal(3)
	assert_int(box.size.x).is_equal(36 * U)
	assert_int(box.size.y).is_equal(24 * U)
	assert_int(box.position.x + box.size.x / 2).is_equal(b.x)
	assert_int(box.position.y).is_equal(b.y)


func test_side_strike_reaches_68_units_from_the_centre_and_mirrors() -> void:
	var sim: Simulation = _sim(544)
	_step(sim, InputFrame.ATTACK)
	sim.step(InputFrame.make(InputFrame.ATTACK, 0, 0, 0))
	sim.step(InputFrame.make(InputFrame.ATTACK, 0, 0, 0))
	var b: Body = sim.player.body
	var right: Rect2i = sim.player.strike_box()
	assert_int(right.position.x).is_equal(b.x)
	assert_int(right.end.x - b.x).is_equal(68 * U)
	var left_sim: Simulation = _sim(544)
	_step(left_sim, InputFrame.ATTACK, -InputFrame.STICK_MAX)
	left_sim.step(InputFrame.make(InputFrame.ATTACK, 0, -InputFrame.STICK_MAX, 0))
	left_sim.step(InputFrame.make(InputFrame.ATTACK, 0, -InputFrame.STICK_MAX, 0))
	var lb: Body = left_sim.player.body
	var left: Rect2i = left_sim.player.strike_box()
	assert_int(left.end.x).is_equal(lb.x)
	assert_int(lb.x - left.position.x).is_equal(68 * U)


func test_hurtbox_sits_inside_the_collider() -> void:
	var sim: Simulation = _sim(544)
	var b: Body = sim.player.body
	var hurt: Rect2i = sim.player.hurtbox()
	assert_bool(Rect2i(b.left(), b.top(), b.right() - b.left(), b.height).encloses(hurt)).is_true()
	assert_int(hurt.size.x).is_less(b.right() - b.left())
	assert_int(hurt.size.y).is_less(b.height)
