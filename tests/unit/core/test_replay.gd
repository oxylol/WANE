extends GdUnitTestSuite
## Replay codec, recorder and player (BUILD.md section 13, "Determinism and replays").


func _scenario() -> Scenario:
	var s: Scenario = Scenario.make(123456789, "test_room")
	s.spawn_x = 64
	s.spawn_y = -32
	s.options["difficulty"] = 2
	s.options["assist"] = -1
	return s


## Records [param frames] ticks of pseudo-random input and returns the finished replay.
func _record(frames: int, seed_value: int = 5) -> Replay:
	var scenario: Scenario = _scenario()
	var sim := Simulation.new(scenario)
	var recorder := ReplayRecorder.new(scenario)
	var rng: Rng = Rng.seeded(seed_value, 9)
	var held: int = 0
	for i: int in range(frames):
		if i % 7 == 0:
			held = rng.below(128)
		var frame := InputFrame.make(held, held if i % 7 == 0 else 0, rng.between(-127, 127), 0)
		if i % 3 != 0:
			frame.stick_x = 0
		sim.step(frame)
		recorder.record(frame)
	return recorder.finish(sim)


func test_encode_decode_round_trip() -> void:
	var replay: Replay = _record(600)
	var decoded: Replay = Replay.decode(replay.encode())
	assert_object(decoded).is_not_null()
	assert_bool(decoded.scenario.equals(replay.scenario)).is_true()
	assert_bool(decoded.frames == replay.frames).is_true()
	assert_bool(decoded.hash_ticks == replay.hash_ticks).is_true()
	assert_bool(decoded.hash_values == replay.hash_values).is_true()
	assert_int(decoded.hash_ticks.size()).is_equal(10)


func test_replay_reproduces_every_hash() -> void:
	var replay: Replay = _record(900)
	var player := ReplayPlayer.new(Replay.decode(replay.encode()))
	assert_bool(player.run_to_end()).is_true()
	assert_int(player.checked).is_equal(15)
	assert_int(player.desync_tick).is_equal(-1)


func test_tampered_input_is_caught_at_the_next_hash() -> void:
	var replay: Replay = _record(600)
	# Change one frame just before the third hash; the hash at tick 180 must catch it. (Until the
	# player exists an input only lives in the 9-frame input ring.)
	replay.frames[176] = InputFrame.make(InputFrame.TOSS, InputFrame.TOSS, 99, 0).pack()
	var player := ReplayPlayer.new(replay)
	assert_bool(player.run_to_end()).is_false()
	assert_int(player.desync_tick).is_equal(180)


func test_tampered_seed_is_caught() -> void:
	var replay: Replay = _record(120)
	replay.scenario.seed_value += 1
	assert_bool(ReplayPlayer.verify(replay)).is_false()


func test_rejects_garbage() -> void:
	assert_object(Replay.decode(PackedByteArray())).is_null()
	assert_object(Replay.decode("not a replay".to_utf8_buffer())).is_null()
	var bytes: PackedByteArray = _record(60).encode()
	assert_object(Replay.decode(bytes.slice(0, bytes.size() - 1))).is_null()
	bytes.append(0)
	assert_object(Replay.decode(bytes)).is_null()


func test_size_budget_two_kilobytes_per_minute() -> void:
	# BUILD.md section 13: "about 2 KB per minute". Model fast human play: on average 4 button
	# presses a second (each held 2 to 20 frames, sometimes overlapping) and 2 stick direction
	# changes a second, about 360 actions a minute, for one minute.
	var scenario: Scenario = _scenario()
	var sim := Simulation.new(scenario)
	var recorder := ReplayRecorder.new(scenario)
	var rng: Rng = Rng.seeded(77, 0)
	var buttons: Array[int] = [
		InputFrame.JUMP, InputFrame.ATTACK, InputFrame.DASH, InputFrame.SPELL
	]
	var release_at: Array[int] = [0, 0, 0, 0]
	var held: int = 0
	var stick_x: int = 0
	for i: int in range(3600):
		var pressed: int = 0
		for b: int in range(buttons.size()):
			if held & buttons[b] != 0 and i >= release_at[b]:
				held &= ~buttons[b]
		if rng.below(15) == 0:
			var b: int = rng.below(buttons.size())
			if held & buttons[b] == 0:
				held |= buttons[b]
				pressed |= buttons[b]
				release_at[b] = i + rng.between(2, 20)
		if rng.below(30) == 0:
			stick_x = (rng.below(3) - 1) * InputFrame.STICK_MAX
		var frame := InputFrame.make(held, pressed, stick_x, 0)
		sim.step(frame)
		recorder.record(frame)
	var size: int = recorder.finish(sim).encode().size()
	assert_int(size).is_less_equal(2048)


func test_encoding_is_compact_for_long_runs_and_many_states() -> void:
	# Worst cases still round-trip: very long runs and more distinct frames than the
	# move-to-front list holds.
	var replay := Replay.new()
	for i: int in range(300):
		replay.frames.append(InputFrame.make(i % 128, 0, (i * 7) % 255 - 127, 0).pack())
	for _i: int in range(5000):
		replay.frames.append(InputFrame.new().pack())
	var decoded: Replay = Replay.decode(replay.encode())
	assert_object(decoded).is_not_null()
	assert_bool(decoded.frames == replay.frames).is_true()


func test_short_replays_and_the_tail_are_verified() -> void:
	# A replay under a second carries its final hash, so tampering anywhere is caught.
	var short: Replay = _record(59)
	assert_array(Array(short.hash_ticks)).is_equal([59])
	short.frames[58] = InputFrame.make(InputFrame.TOSS, InputFrame.TOSS, 99, 0).pack()
	var player := ReplayPlayer.new(short)
	assert_bool(player.run_to_end()).is_false()
	assert_int(player.desync_tick).is_equal(59)
	# The last frames after the final multiple of 60 are covered too.
	var tail: Replay = _record(130)
	assert_array(Array(tail.hash_ticks)).is_equal([60, 120, 130])
	tail.frames[129] = InputFrame.make(InputFrame.TOSS, InputFrame.TOSS, 99, 0).pack()
	assert_bool(ReplayPlayer.verify(tail)).is_false()


func test_a_replay_without_its_hashes_is_rejected() -> void:
	var replay: Replay = _record(300)
	replay.hash_ticks.clear()
	replay.hash_values.clear()
	var player := ReplayPlayer.new(replay)
	assert_bool(player.run_to_end()).is_false()
	assert_int(player.status).is_equal(ReplayPlayer.Status.MALFORMED)


func test_older_simulation_version_is_not_a_desync() -> void:
	var replay: Replay = _record(120)
	replay.sim_version = Simulation.VERSION - 1
	var decoded: Replay = Replay.decode(replay.encode())
	assert_int(decoded.sim_version).is_equal(Simulation.VERSION - 1)
	var player := ReplayPlayer.new(decoded)
	assert_bool(player.run_to_end()).is_false()
	assert_int(player.status).is_equal(ReplayPlayer.Status.VERSION_MISMATCH)
	assert_str(player.describe()).contains("simulation version")


func test_different_content_is_not_a_desync() -> void:
	var replay: Replay = _record(120)
	replay.content_hash ^= 1
	var player := ReplayPlayer.new(Replay.decode(replay.encode()))
	assert_bool(player.run_to_end()).is_false()
	assert_int(player.status).is_equal(ReplayPlayer.Status.CONTENT_MISMATCH)


func test_out_of_range_stream_values_are_rejected() -> void:
	var frames: PackedByteArray = _header(0)
	frames.append_array(_varint(1))
	frames.append(0x80 | Replay.LITERAL_TAG)
	frames.append_array(_varint(1))
	frames.append_array(_varint(Replay.BUTTON_LIMIT))
	assert_object(Replay.decode(frames)).is_null()


func test_hostile_counts_are_rejected_without_work() -> void:
	var huge: int = 1 << 40
	var started: int = Time.get_ticks_msec()
	# Option count, frame count, run length and hash count each claim 2^40 entries.
	assert_object(Replay.decode(_header(huge))).is_null()
	var frames: PackedByteArray = _header(0)
	frames.append_array(_varint(huge))
	assert_object(Replay.decode(frames)).is_null()
	var run: PackedByteArray = _header(0)
	run.append_array(_varint(100))
	run.append(0x80 | Replay.LITERAL_TAG)
	run.append_array(_varint(huge))
	assert_object(Replay.decode(run)).is_null()
	var hashes: PackedByteArray = _header(0)
	hashes.append_array(_varint(0))
	hashes.append_array(_varint(huge))
	assert_object(Replay.decode(hashes)).is_null()
	assert_int(Time.get_ticks_msec() - started).is_less(500)


func test_analog_stick_play_fits_the_budget() -> void:
	# A partly deflected analog stick as the input layer reports it (quantised to steps of 8 with
	# hysteresis, game/input/input_layer.gd), drifting slowly with sensor noise, plus presses.
	var scenario: Scenario = _scenario()
	var sim := Simulation.new(scenario)
	var recorder := ReplayRecorder.new(scenario)
	var rng: Rng = Rng.seeded(91, 0)
	var stick := Vector2i.ZERO
	var held: int = 0
	for i: int in range(3600):
		var raw_x: float = 0.55 + 0.35 * sin(float(i) / 90.0) + float(rng.between(-10, 10)) / 1000.0
		var raw_y: float = 0.2 * sin(float(i) / 150.0) + float(rng.between(-10, 10)) / 1000.0
		stick = InputLayer.quantize_stick(Vector2(raw_x, raw_y), stick, 8)
		var pressed: int = 0
		if rng.below(20) == 0:
			var bit: int = InputFrame.BUTTONS[rng.below(3)]
			pressed = bit & ~held
			held ^= bit
		var frame := InputFrame.make(held, pressed, stick.x, stick.y)
		sim.step(frame)
		recorder.record(frame)
	assert_int(recorder.finish(sim).encode().size()).is_less_equal(2048)


func _varint(v: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var x: int = v
	while true:
		var b: int = x & 0x7F
		x >>= 7
		if x == 0:
			out.append(b)
			return out
		out.append(b | 0x80)
	return out


## A valid replay header up to and including an option count of [param options].
func _header(options: int) -> PackedByteArray:
	var b: PackedByteArray = Replay.MAGIC.to_ascii_buffer()
	b.append_array(PackedByteArray([Replay.VERSION, 0]))
	b.append_array(_varint(Simulation.VERSION))
	b.append_array(PackedByteArray([0, 0, 0, 0]))
	b.append_array(_varint(2))
	b.append_array(_varint(0))
	b.append_array(_varint(0))
	b.append_array(_varint(0))
	b.append_array(_varint(0))
	b.append_array(_varint(options))
	return b
