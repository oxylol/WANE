class_name Replay
extends RefCounted
## A recorded run: the [Scenario], one packed [InputFrame] per tick, and the state hashes the
## simulation produced every 60 ticks (BUILD.md section 13, "Determinism and replays"; ADR-0006).
##
## Binary layout (little-endian), version 1:
##   "WRPL"  magic
##   u16     format version
##   varint  simulation version ([constant Simulation.VERSION] of the build that recorded it)
##   u32     content hash ([member Simulation.content_hash] when it was recorded)
##   scenario: varint seed (zigzag), string wick, string room, varint spawn x and y (zigzag),
##             varint option count, then (string key, varint value (zigzag)) sorted by key
##   varint  frame count
##   stream  buttons: each frame's held and pressed bits (low 14 bits of the packed frame)
##   stream  stick: each frame's stick (the packed frame's upper bits)
##   A stream is a sequence of runs of identical values until frame count is reached. A value is
##   named by a tag: 0..126 is its position in a move-to-front list of recently seen distinct
##   values, 127 means a new value (sent as a varint after the run); the value then moves to the
##   front. A short run (1 to 8 frames) of one of the 16 most recent values is one byte,
##   0rrrtttt (r = run - 1, t = tag); any other run is the byte 1ttttttt followed by a varint run
##   length and, for tag 127, the varint value. Buttons and stick are separate streams so a
##   moving analog stick does not turn every button state into a new value.
##   varint  hash count
##   hashes: (varint tick delta from the previous hashed tick, u32 hash): every 60th tick, then
##           the final tick
## Decoding rejects anything malformed or implausible (more than [constant MAX_FRAMES] frames,
## counts larger than the bytes left could hold) without allocating for it.
## Strings are a varint byte length then UTF-8 bytes. Runs of identical frames, plus the
## move-to-front list (a player cycles through a handful of input states), keep a minute of
## human play near the 2 KB the doc budgets: about two bytes per input change.

const MAGIC: String = "WRPL"
const VERSION: int = 1
## Move-to-front list length; tag [constant LITERAL_TAG] marks a frame not in the list.
const RECENT: int = 127
const LITERAL_TAG: int = 127
## Split of a packed InputFrame into the button stream and the stick stream.
const BUTTON_BITS: int = (1 << 14) - 1
const STICK_SHIFT: int = 14
## Four hours at 60 Hz: the longest replay the decoder will accept (a full run is 35 to 60
## minutes). Hostile input can make the decoder allocate at most this many frames.
const MAX_FRAMES: int = 864000
## Exclusive upper bounds of the two streams' values.
const BUTTON_LIMIT: int = 1 << 14
const STICK_LIMIT: int = 1 << 16

## Simulation version and content fingerprint of the build that recorded the replay.
var sim_version: int = Simulation.VERSION
var content_hash: int = 0
var scenario: Scenario = Scenario.new()
## One packed InputFrame per tick (see [method InputFrame.pack]).
var frames: PackedInt32Array = PackedInt32Array()
var hash_ticks: PackedInt32Array = PackedInt32Array()
var hash_values: PackedInt64Array = PackedInt64Array()


func frame_count() -> int:
	return frames.size()


func frame(i: int) -> InputFrame:
	return InputFrame.unpack(frames[i])


func encode() -> PackedByteArray:
	var w := _Writer.new()
	w.bytes.append_array(MAGIC.to_ascii_buffer())
	w.u16(VERSION)
	w.varint(sim_version)
	w.u32(content_hash)
	w.svarint(scenario.seed_value)
	w.string(scenario.wick)
	w.string(scenario.room)
	w.svarint(scenario.spawn_x)
	w.svarint(scenario.spawn_y)
	var keys: Array[String] = scenario.sorted_option_keys()
	w.varint(keys.size())
	for key: String in keys:
		w.string(key)
		w.svarint(scenario.options[key])
	w.varint(frames.size())
	var buttons: PackedInt32Array = PackedInt32Array()
	var sticks: PackedInt32Array = PackedInt32Array()
	for packed: int in frames:
		buttons.append(packed & BUTTON_BITS)
		sticks.append(packed >> STICK_SHIFT)
	_encode_stream(w, buttons)
	_encode_stream(w, sticks)
	w.varint(hash_ticks.size())
	var previous: int = 0
	for j: int in range(hash_ticks.size()):
		w.varint(hash_ticks[j] - previous)
		previous = hash_ticks[j]
		w.u32(hash_values[j])
	return w.bytes


## Parses [param bytes]; returns null if they are not a valid version-1 replay.
static func decode(bytes: PackedByteArray) -> Replay:
	var r := _Reader.new(bytes)
	if bytes.size() < 6 or bytes.slice(0, 4) != MAGIC.to_ascii_buffer():
		return null
	r.pos = 4
	if r.u16() != VERSION:
		return null
	var replay := Replay.new()
	replay.sim_version = r.varint()
	replay.content_hash = r.u32()
	var s := Scenario.new()
	s.seed_value = r.svarint()
	s.wick = r.string()
	s.room = r.string()
	s.spawn_x = r.svarint()
	s.spawn_y = r.svarint()
	var option_count: int = r.varint()
	if option_count > r.remaining():
		return null
	for _k: int in range(option_count):
		var key: String = r.string()
		s.options[key] = r.svarint()
		if r.failed:
			return null
	replay.scenario = s
	var count: int = r.varint()
	if r.failed or count < 0 or count > MAX_FRAMES:
		return null
	var buttons: PackedInt32Array = _decode_stream(r, count, BUTTON_LIMIT)
	var sticks: PackedInt32Array = _decode_stream(r, count, STICK_LIMIT)
	if buttons.size() != count or sticks.size() != count:
		return null
	replay.frames.resize(count)
	for i: int in range(count):
		replay.frames[i] = buttons[i] | (sticks[i] << STICK_SHIFT)
	var hash_count: int = r.varint()
	if r.failed or hash_count < 0 or hash_count * 5 > r.remaining():
		return null
	var tick: int = 0
	for _h: int in range(hash_count):
		tick += r.varint()
		replay.hash_ticks.append(tick)
		replay.hash_values.append(r.u32())
		if r.failed:
			return null
	if r.failed or r.pos != bytes.size():
		return null
	return replay


## Run-length and move-to-front coding of one stream of small integers (see the class notes).
static func _encode_stream(w: _Writer, values: PackedInt32Array) -> void:
	var recent: PackedInt32Array = PackedInt32Array()
	var i: int = 0
	while i < values.size():
		var run: int = 1
		while i + run < values.size() and values[i + run] == values[i]:
			run += 1
		var k: int = recent.find(values[i])
		if k >= 0 and k < 16 and run <= 8:
			w.bytes.append(((run - 1) << 4) | k)
		elif k >= 0:
			w.bytes.append(0x80 | k)
			w.varint(run)
		else:
			w.bytes.append(0x80 | LITERAL_TAG)
			w.varint(run)
			w.varint(values[i])
		if k >= 0:
			recent.remove_at(k)
		elif recent.size() == RECENT:
			recent.remove_at(RECENT - 1)
		recent.insert(0, values[i])
		i += run


## Inverse of [method _encode_stream]; returns fewer than [param count] values on bad input,
## including any value outside [0, [param limit]).
static func _decode_stream(r: _Reader, count: int, limit: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var recent: PackedInt32Array = PackedInt32Array()
	while out.size() < count and not r.failed:
		var head: int = r.byte()
		var run: int = ((head >> 4) & 7) + 1
		var tag: int = head & 15
		if head & 0x80 != 0:
			tag = head & 0x7F
			run = r.varint()
		var value: int = 0
		if tag == LITERAL_TAG:
			value = r.varint()
			if value < 0 or value >= limit:
				break
			if recent.size() == RECENT:
				recent.remove_at(RECENT - 1)
		elif tag < recent.size():
			value = recent[tag]
			recent.remove_at(tag)
		else:
			break
		recent.insert(0, value)
		if r.failed or run <= 0 or out.size() + run > count:
			break
		for _n: int in range(run):
			out.append(value)
	return out


class _Writer:
	var bytes: PackedByteArray = PackedByteArray()

	func u16(v: int) -> void:
		bytes.append(v & 0xFF)
		bytes.append((v >> 8) & 0xFF)

	func u32(v: int) -> void:
		for shift: int in [0, 8, 16, 24]:
			bytes.append((v >> shift) & 0xFF)

	func varint(v: int) -> void:
		var x: int = v
		while true:
			var b: int = x & 0x7F
			x = (x >> 7) & 0x01FFFFFFFFFFFFFF
			if x == 0:
				bytes.append(b)
				return
			bytes.append(b | 0x80)

	func svarint(v: int) -> void:
		varint((v << 1) ^ (v >> 63))

	func string(s: String) -> void:
		var utf8: PackedByteArray = s.to_utf8_buffer()
		varint(utf8.size())
		bytes.append_array(utf8)


class _Reader:
	var bytes: PackedByteArray
	var pos: int = 0
	var failed: bool = false

	func _init(p_bytes: PackedByteArray) -> void:
		bytes = p_bytes

	func remaining() -> int:
		return bytes.size() - pos

	func byte() -> int:
		if pos >= bytes.size():
			failed = true
			return 0
		pos += 1
		return bytes[pos - 1]

	func u16() -> int:
		var lo: int = byte()
		var hi: int = byte()
		return lo | (hi << 8)

	func u32() -> int:
		var result: int = 0
		for shift: int in [0, 8, 16, 24]:
			result |= byte() << shift
		return result

	func varint() -> int:
		var result: int = 0
		var shift: int = 0
		while shift < 64:
			var b: int = byte()
			if failed:
				return 0
			result |= (b & 0x7F) << shift
			if (b & 0x80) == 0:
				return result
			shift += 7
		failed = true
		return 0

	func svarint() -> int:
		var z: int = varint()
		return ((z >> 1) & 0x7FFFFFFFFFFFFFFF) ^ -(z & 1)

	func string() -> String:
		var n: int = varint()
		if failed or n < 0 or pos + n > bytes.size():
			failed = true
			return ""
		var s: String = bytes.slice(pos, pos + n).get_string_from_utf8()
		pos += n
		return s
