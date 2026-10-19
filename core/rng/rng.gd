class_name Rng
extends RefCounted
## Deterministic random numbers for the core: xoshiro128** (Blackman and Vigna), 32-bit state
## words held in 64-bit integers and masked after every operation, so results are identical on
## every platform (ADR-0005). Never seeded from time; every stream derives from the run seed.

var _s0: int = 0
var _s1: int = 0
var _s2: int = 0
var _s3: int = 0


## A generator whose state is derived from [param seed_value] and [param stream_id].
static func seeded(seed_value: int, stream_id: int = 0) -> Rng:
	var r := Rng.new()
	# The seed's low and high words and the stream id are mixed separately, so distinct
	# (seed, stream) pairs never collapse to the same state.
	var lo: int = Fx.fmix32(seed_value & Fx.MASK32)
	var hi: int = Fx.fmix32(((seed_value >> 32) & Fx.MASK32) ^ 0x6A09E667)
	var sid: int = Fx.fmix32(Fx.mul32(stream_id + 1, 0x9E3779B9))
	var x: int = Fx.fmix32(lo ^ Fx.rotl32(hi, 16) ^ sid)
	r._s0 = Fx.fmix32(x ^ 0x243F6A88)
	r._s1 = Fx.fmix32(x ^ 0x85A308D3 ^ lo)
	r._s2 = Fx.fmix32(x ^ 0x13198A2E ^ hi)
	r._s3 = Fx.fmix32(x ^ 0x03707344 ^ sid)
	if (r._s0 | r._s1 | r._s2 | r._s3) == 0:
		r._s0 = 1
	return r


## Next raw 32-bit value in [0, 2^32). The state words are below 2^32, so x5, x9 and the rotations'
## shifts stay well inside 64 bits: plain integer maths with a mask is exactly the generator's
## modulo-2^32 arithmetic, without a function call per operation (the proc bus draws here on every
## chance it rolls: docs/adr/0015). test_rng.gd pins the outputs.
func next_u32() -> int:
	var x: int = (_s1 * 5) & Fx.MASK32
	x = ((x << 7) | (x >> 25)) & Fx.MASK32
	var result: int = (x * 9) & Fx.MASK32
	var t: int = (_s1 << 9) & Fx.MASK32
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = ((_s3 << 11) | (_s3 >> 21)) & Fx.MASK32
	return result


## Uniform integer in [0, n). Unbiased (rejection sampling). [param n] must be in [1, 2^32];
## larger spans are a programming error.
func below(n: int) -> int:
	assert(n <= 0x100000000, "Rng.below: the span exceeds 2^32")
	if n <= 1 or n > 0x100000000:
		return 0
	var limit: int = (0x100000000 / n) * n
	var r: int = next_u32()
	while r >= limit:
		r = next_u32()
	return r % n


## Uniform integer in [lo, hi] inclusive. The span must be at most 2^32.
func between(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + below(hi - lo + 1)


## True with probability [param per_mille] / 1000.
func chance_permille(per_mille: int) -> bool:
	if per_mille <= 0:
		return false
	if per_mille >= 1000:
		return true
	return below(1000) < per_mille


func hash_into(h: StateHasher) -> void:
	h.add_int(_s0)
	h.add_int(_s1)
	h.add_int(_s2)
	h.add_int(_s3)


func get_state() -> PackedInt64Array:
	return PackedInt64Array([_s0, _s1, _s2, _s3])


func set_state(state: PackedInt64Array) -> void:
	_s0 = state[0] & Fx.MASK32
	_s1 = state[1] & Fx.MASK32
	_s2 = state[2] & Fx.MASK32
	_s3 = state[3] & Fx.MASK32
