extends GdUnitTestSuite
## EnemyView.capture keeps one snapshot object per enemy and rewrites it each tick, so a crowd of
## 200 costs no allocation a tick (BUILD.md s13 Frame budget: the views' script time, 2.3 ms of
## the stress run's presentation before this; docs/adr/0020 Decision 17).

const ROOMS: Array[String] = ["test/dummy_swing", "test/dummy_red"]
const TICKS: int = 90


func _sim(room: String) -> Simulation:
	var sc: Scenario = Scenario.make(1)
	sc.room = room
	return Simulation.new(sc)


func _same_fields(a: EnemyView.Shown, b: EnemyView.Shown) -> bool:
	return (
		a.box == b.box
		and a.alive == b.alive
		and a.state == b.state
		and a.facing == b.facing
		and a.since_hit == b.since_hit
		and is_equal_approx(a.telegraph, b.telegraph)
		and a.parryable == b.parryable
		and a.attack == b.attack
		and is_equal_approx(a.hp, b.hp)
		and is_equal_approx(a.poise, b.poise)
	)


func test_a_rewritten_snapshot_is_what_a_fresh_one_would_be_on_every_tick() -> void:
	for room: String in ROOMS:
		var sim: Simulation = _sim(room)
		var view: EnemyView = auto_free(EnemyView.new())
		for tick: int in range(TICKS):
			sim.step(InputFrame.new())
			view.capture(sim)
			assert_int(view.shown.size()).is_equal(sim.combat.enemies.size())
			for i: int in range(view.shown.size()):
				var fresh: EnemyView.Shown = EnemyView.snapshot_of(sim.combat.enemies[i])
				(
					assert_bool(_same_fields(view.shown[i], fresh))
					. override_failure_message(
						"%s tick %d enemy %d: the rewritten snapshot differs" % [room, tick, i]
					)
					. is_true()
				)


func test_capture_keeps_the_same_snapshot_objects_while_the_crowd_is_the_same_size() -> void:
	var sim: Simulation = _sim(ROOMS[0])
	var view: EnemyView = auto_free(EnemyView.new())
	sim.step(InputFrame.new())
	view.capture(sim)
	var first: EnemyView.Shown = view.shown[0]
	sim.step(InputFrame.new())
	view.capture(sim)
	assert_object(view.shown[0]).is_same(first)


func test_the_previous_boxes_follow_the_crowd_when_it_grows_and_shrinks() -> void:
	var sim: Simulation = _sim(ROOMS[0])
	var all: Array[Enemy] = []
	all.assign(sim.combat.enemies)
	var view: EnemyView = auto_free(EnemyView.new())
	for size: int in [1, 1, 0, 1, 1]:
		var some: Array[Enemy] = []
		some.assign(all.slice(0, size))
		sim.combat.enemies.assign(some)
		view.capture(sim)
		assert_int(view.shown.size()).is_equal(size)
		assert_int(view._before.size()).is_equal(size)
	# A move between two captures is what _before keeps: the box one tick back.
	var e: Enemy = all[0]
	sim.combat.enemies.assign([e])
	view.capture(sim)
	var was: Rect2 = view.shown[0].box
	e.body.x += 256 * 8
	view.capture(sim)
	assert_object(view._before[0]).is_equal(was)
	assert_bool(view.shown[0].box != was).is_true()
