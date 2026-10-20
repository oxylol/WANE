extends GdUnitTestSuite
## A run is a seed plus an input stream, and the native sweep must not change what it does
## (CLAUDE.md rule 4, docs/adr/0022): the stress room's run (200 enemies, 3840 ticks, a state hash
## every 60 ticks) is played once on the GDScript sweep and once on the native one, and the 64
## hashes must be the same. Every committed fixture's golden hash is held to the same standard by
## the fixtures stage, which CI runs with the native path on and off against one golden file.

const STRESS: String = "res://tests/perf/stress_run.fixture"

var _saved_mode: NativeBackend.Mode = NativeBackend.Mode.AUTO


func before_test() -> void:
	_saved_mode = NativeBackend.mode()


func after_test() -> void:
	NativeBackend.configure(_saved_mode)


func test_the_stress_run_gives_the_same_hashes_native_and_reference() -> void:
	if not NativeBackend.available():
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	var fx: Fixture = Fixture.parse_file(STRESS)
	assert_array(fx.errors).is_empty()
	var reference: Simulation = _play(fx, NativeBackend.Mode.OFF)
	var native: Simulation = _play(fx, NativeBackend.Mode.ON)
	assert_object(reference.world.native).is_null()
	assert_object(native.world.native).is_not_null()
	assert_int(reference.hash_values.size()).is_equal(64)
	assert_int(native.hash_values.size()).is_equal(reference.hash_values.size())
	for i: int in range(reference.hash_values.size()):
		if reference.hash_values[i] != native.hash_values[i]:
			fail(
				(
					"stress run desync at tick %d: native %d, reference %d"
					% [reference.hash_ticks[i], native.hash_values[i], reference.hash_values[i]]
				)
			)
			return
	assert_int(native.state_hash()).is_equal(reference.state_hash())


func _play(fx: Fixture, mode: NativeBackend.Mode) -> Simulation:
	NativeBackend.configure(mode)
	var sim := Simulation.new(fx.scenario)
	for i: int in range(fx.frame_total):
		sim.step(fx.input_frame(i))
	return sim
