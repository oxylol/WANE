class_name StateHasher
extends RefCounted
## Order-dependent 32-bit hash of simulation state, for replay desync detection (BUILD.md
## section 13, "a desync is a P0 bug caught by a state hash every 60 ticks").
##
## Every value is appended to a buffer of 64-bit words (a bool as 0 or 1; a string as its UTF-8
## length, then its bytes zero-padded to whole words), and the value is the first four bytes of
## the buffer's SHA-256, read as an unsigned little-endian integer. The buffer's bytes are the
## words in little-endian order: Godot runs only on little-endian machines, so the result is the
## same on every platform. The SHA-256 is Godot's native one: mixing each word in GDScript
## (MurmurHash3, the first version) took about 440 us per state hash (docs/adr/0006).

var _words: PackedInt64Array = PackedInt64Array()


func _init(seed_value: int = 0) -> void:
	_words.append(seed_value)


func add_int(v: int) -> void:
	_words.append(v)


## Appends [param values] in order, as the same number of [method add_int] calls would (a state
## with many fields adds them in one call: the hash of 200 enemies is the cost of a tick).
func add_ints(values: PackedInt64Array) -> void:
	_words.append_array(values)


func add_bool(v: bool) -> void:
	_words.append(1 if v else 0)


func add_string(s: String) -> void:
	var bytes: PackedByteArray = s.to_utf8_buffer()
	_words.append(bytes.size())
	bytes.resize((bytes.size() + 7) & ~7)
	_words.append_array(bytes.to_int64_array())


## A copy of the words appended since the seed. A part of a hash that is the same every time (a
## room's content) is hashed into a hasher of its own once, and these words are added to each
## hasher that needs them with [method add_ints].
func words_after_seed() -> PackedInt64Array:
	return _words.slice(1)


## The finished hash, a non-negative integer below 2^32.
func value() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(_words.to_byte_array())
	return ctx.finish().decode_u32(0)
