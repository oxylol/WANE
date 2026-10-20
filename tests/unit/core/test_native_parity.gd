extends GdUnitTestSuite
## The native extension against its GDScript reference (ADR-0021): the reference is pinned to
## independently computed vectors, the native code is held to the reference on those vectors and
## on a seeded sweep, and every native method must have a reference. Run in CI with the library
## built, under WANE_NATIVE=off and WANE_NATIVE=on; mode "on" ends the process at boot if the
## library is missing, so the native cases cannot be skipped there.

## Inputs and, in FMIX_EXPECTED, fmix32 results from an independent Python implementation of
## MurmurHash3's finaliser.
const FMIX_INPUTS: Array[int] = [
	0,
	1,
	-1,
	0xDEADBEEF,
	0x1FFFFFFFF,
	-0x80000000,
	0x7FFFFFFFFFFFFFFF,
	-0x8000000000000000,
]
const FMIX_EXPECTED: Array[int] = [
	0,
	1364076727,
	2180083513,
	233162409,
	2180083513,
	1832674720,
	2180083513,
	0,
]
## [seed, values, fold32] from the same implementation.
const FOLD_SEEDS: Array[int] = [0, 7, -1, 0x123456789]
const FOLD_EXPECTED: Array[int] = [0, 2720193583, 3342073359, 1940800226]
## Native methods with no reference because they return build information, not simulation data.
const NATIVE_ONLY: Array[String] = ["describe"]
## WaneSweep methods that feed the native copy of the world instead of porting a method of it.
const SWEEP_SETUP: Array[String] = ["set_grid", "set_spike_inset", "set_boxes", "set_box"]
## WaneCells methods that hand the enemies' centres over instead of answering a question.
const CELLS_SETUP: Array[String] = ["build_from"]

var _saved_mode: NativeBackend.Mode = NativeBackend.Mode.AUTO


func before_test() -> void:
	_saved_mode = NativeBackend.mode()


func after_test() -> void:
	NativeBackend.configure(_saved_mode)


func _fold_values(index: int) -> PackedInt64Array:
	match index:
		0:
			return PackedInt64Array()
		1:
			return PackedInt64Array([1, -5, 0x1FFFFFFFF, 99])
		2:
			return PackedInt64Array([0, 0, 0])
		_:
			return PackedInt64Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])


func test_reference_matches_independent_vectors() -> void:
	for i: int in range(FMIX_INPUTS.size()):
		assert_int(NativeRef.fmix32(FMIX_INPUTS[i])).is_equal(FMIX_EXPECTED[i])
	for i: int in range(FOLD_SEEDS.size()):
		assert_int(NativeRef.fold32(FOLD_SEEDS[i], _fold_values(i))).is_equal(FOLD_EXPECTED[i])


func test_off_dispatches_to_the_reference() -> void:
	NativeBackend.configure(NativeBackend.Mode.OFF)
	assert_bool(NativeBackend.use_native()).is_false()
	for i: int in range(FMIX_INPUTS.size()):
		assert_int(NativeBackend.fmix32(FMIX_INPUTS[i])).is_equal(FMIX_EXPECTED[i])
	for i: int in range(FOLD_SEEDS.size()):
		assert_int(NativeBackend.fold32(FOLD_SEEDS[i], _fold_values(i))).is_equal(FOLD_EXPECTED[i])


func test_auto_and_on_use_native_exactly_when_the_library_is_current() -> void:
	NativeBackend.configure(NativeBackend.Mode.AUTO)
	assert_bool(NativeBackend.use_native()).is_equal(NativeBackend.available())
	NativeBackend.configure(NativeBackend.Mode.ON)
	assert_bool(NativeBackend.use_native()).is_equal(NativeBackend.available())


func test_native_matches_vectors_and_reference() -> void:
	var probe: Object = NativeBackend.native_probe()
	if probe == null:
		# Only a developer machine without a build gets here; CI's native steps die at boot.
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	NativeBackend.configure(NativeBackend.Mode.ON)
	assert_int(NativeBackend.problem().length()).is_equal(0)
	assert_bool(NativeBackend.use_native()).is_true()
	assert_int(probe.call(&"version")).is_equal(NativeBackend.EXPECTED_VERSION)
	for i: int in range(FMIX_INPUTS.size()):
		assert_int(NativeBackend.fmix32(FMIX_INPUTS[i])).is_equal(FMIX_EXPECTED[i])
	for i: int in range(FOLD_SEEDS.size()):
		assert_int(NativeBackend.fold32(FOLD_SEEDS[i], _fold_values(i))).is_equal(FOLD_EXPECTED[i])


func test_native_matches_reference_on_a_seeded_sweep() -> void:
	if NativeBackend.native_probe() == null:
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	var rng: Rng = Rng.seeded(20261020, 21)
	var bad: int = 0
	for round_index: int in range(200):
		var values := PackedInt64Array()
		# Full 64-bit patterns, so sign extension and the 32-bit masks are both exercised.
		for _i: int in range(round_index % 17):
			values.append((rng.next_u32() << 32) | rng.next_u32())
		var seed_value: int = (rng.next_u32() << 32) | rng.next_u32()
		NativeBackend.configure(NativeBackend.Mode.ON)
		var native_fold: int = NativeBackend.fold32(seed_value, values)
		var native_mix: int = NativeBackend.fmix32(seed_value)
		if native_fold != NativeRef.fold32(seed_value, values):
			bad += 1
		if native_mix != NativeRef.fmix32(seed_value):
			bad += 1
	assert_int(bad).is_equal(0)


func test_every_native_method_has_a_reference() -> void:
	if NativeBackend.native_probe() == null:
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	var reference_methods: Array[String] = []
	var reference_list: Array[Dictionary] = (NativeRef as Script).get_script_method_list()
	for i: int in range(reference_list.size()):
		reference_methods.append(str(reference_list[i]["name"]))
	var missing: Array[String] = []
	var native_list: Array[Dictionary] = ClassDB.class_get_method_list(
		NativeBackend.PROBE_CLASS, true
	)
	for i: int in range(native_list.size()):
		var method_name: String = str(native_list[i]["name"])
		if not NATIVE_ONLY.has(method_name) and not reference_methods.has(method_name):
			missing.append(method_name)
	assert_array(missing).is_empty()


func test_every_sweep_method_is_a_method_of_the_gdscript_world() -> void:
	# The sweep's reference is CollisionWorld itself (docs/adr/0022), not a NativeRef twin: every
	# ported method keeps its name there, and test_native_sweep.gd plays the two side by side.
	if not ClassDB.class_exists(NativeWorld.SWEEP_CLASS):
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	var reference_methods: Array[String] = []
	var reference_list: Array[Dictionary] = (CollisionWorld as Script).get_script_method_list()
	for i: int in range(reference_list.size()):
		reference_methods.append(str(reference_list[i]["name"]))
	var missing: Array[String] = []
	var native_list: Array[Dictionary] = ClassDB.class_get_method_list(
		NativeWorld.SWEEP_CLASS, true
	)
	for i: int in range(native_list.size()):
		var method_name: String = str(native_list[i]["name"])
		if not SWEEP_SETUP.has(method_name) and not reference_methods.has(method_name):
			missing.append(method_name)
	assert_array(missing).is_empty()


func test_every_cells_method_is_a_method_of_enemy_cells() -> void:
	# The cells' reference is EnemyCells itself (docs/adr/0020 Decision 15), not a NativeRef twin:
	# every native question keeps its name there, and test_native_cells.gd plays the two side by
	# side.
	if not ClassDB.class_exists(EnemyCells.NATIVE_CLASS):
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	var reference_methods: Array[String] = []
	var reference_list: Array[Dictionary] = (EnemyCells as Script).get_script_method_list()
	for i: int in range(reference_list.size()):
		reference_methods.append(str(reference_list[i]["name"]))
	var missing: Array[String] = []
	var native_list: Array[Dictionary] = ClassDB.class_get_method_list(
		EnemyCells.NATIVE_CLASS, true
	)
	for i: int in range(native_list.size()):
		var method_name: String = str(native_list[i]["name"])
		if not CELLS_SETUP.has(method_name) and not reference_methods.has(method_name):
			missing.append(method_name)
	assert_array(missing).is_empty()


func test_parse_mode_accepts_the_three_names_and_rejects_the_rest() -> void:
	assert_int(NativeBackend.parse_mode("off")).is_equal(NativeBackend.Mode.OFF)
	assert_int(NativeBackend.parse_mode(" Auto ")).is_equal(NativeBackend.Mode.AUTO)
	assert_int(NativeBackend.parse_mode("ON")).is_equal(NativeBackend.Mode.ON)
	assert_int(NativeBackend.parse_mode("")).is_equal(-1)
	assert_int(NativeBackend.parse_mode("yes")).is_equal(-1)


func test_the_boot_autoload_is_registered() -> void:
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	assert_object(root.get_node_or_null("NativeBoot")).is_not_null()
