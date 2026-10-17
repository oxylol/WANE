class_name StateHasher
extends RefCounted
## Order-dependent 32-bit hash of simulation state, for replay desync detection (BUILD.md
## section 13, "a desync is a P0 bug caught by a state hash every 60 ticks").
##
## MurmurHash3 (x86, 32-bit) block mixing over 32-bit words; each 64-bit integer contributes its
## low and high words. Pure integer arithmetic within the signed 64-bit range, so the result is
## identical on every platform.

const _C1: int = 0xCC9E2D51
const _C2: int = 0x1B873593

var _h: int = 0
var _words: int = 0


func _init(seed_value: int = 0) -> void:
	_h = seed_value & Fx.MASK32


func add_int(v: int) -> void:
	_add_word(v & Fx.MASK32)
	_add_word((v >> 32) & Fx.MASK32)


func add_bool(v: bool) -> void:
	_add_word(1 if v else 0)


func add_string(s: String) -> void:
	var bytes: PackedByteArray = s.to_utf8_buffer()
	add_int(bytes.size())
	# _add_word inlined: content hashing feeds every byte of every name through here.
	var h: int = _h
	for b: int in bytes:
		var k: int = Fx.rotl32(Fx.mul32(b, _C1), 15)
		h = Fx.rotl32(h ^ Fx.mul32(k, _C2), 13)
		h = (Fx.mul32(h, 5) + 0xE6546B64) & Fx.MASK32
	_h = h
	_words += bytes.size()


## The finished hash, a non-negative integer below 2^32.
func value() -> int:
	return Fx.fmix32(_h ^ (_words & Fx.MASK32))


func _add_word(k: int) -> void:
	k = Fx.mul32(k, _C1)
	k = Fx.rotl32(k, 15)
	k = Fx.mul32(k, _C2)
	_h ^= k
	_h = Fx.rotl32(_h, 13)
	_h = (Fx.mul32(_h, 5) + 0xE6546B64) & Fx.MASK32
	_words += 1
