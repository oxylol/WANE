class_name NativeRef
extends RefCounted
## The GDScript reference for every native method (ADR-0021). A native method of the same name
## must return, for every input, exactly what its reference here returns: the reference is the
## specification, the native code the optimisation. tests/unit/core/test_native_parity.gd runs
## both on fixed vectors and on a seeded sweep, and fails if a native method has no reference.
## This is also the code that runs when the library is absent or the switch is off.
##
## Rules for a reference (and so for its native twin): integers only, 32-bit values masked after
## every operation, 64-bit values never allowed to overflow, no unordered iteration.


## The native library's own version, which the library must report (NativeBackend refuses a
## stale binary). Bumped together with NATIVE_VERSION in native/src/native_probe.h.
static func version() -> int:
	return NativeBackend.EXPECTED_VERSION


## MurmurHash3's 32-bit finaliser (Fx.fmix32).
static func fmix32(h: int) -> int:
	return Fx.fmix32(h)


## [method fmix32] folded over [param values] from [param seed_value]: h = fmix32(h ^ v).
static func fold32(seed_value: int, values: PackedInt64Array) -> int:
	var h: int = seed_value & Fx.MASK32
	for v: int in values:
		h = Fx.fmix32(h ^ (v & Fx.MASK32))
	return h
