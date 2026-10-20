// NativeProbe: the toolchain's canary and the pattern every native port follows (ADR-0021).
//
// It proves the chain end to end (godot-cpp, SCons, the .gdextension, the load from GDScript)
// and it is the first parity pair: each method has a GDScript reference of the same name in
// core/native/native_ref.gd, and tests/unit/core/test_native_parity.gd runs both on the same
// inputs. Determinism rules for everything in native/src (ADR-0021 Decision 4): int64_t and
// uint32_t only, no float or double, no unordered containers in anything that is hashed or
// iterated, no time, no threads, no randomness except the core's own streams.
#ifndef WANE_NATIVE_PROBE_H
#define WANE_NATIVE_PROBE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace wane {

// Bumped whenever any native behaviour changes. core/native/native_backend.gd refuses a library
// whose version differs from its EXPECTED_VERSION, so a stale binary can never run a replay.
constexpr int64_t NATIVE_VERSION = 3;

class NativeProbe : public godot::RefCounted {
	GDCLASS(NativeProbe, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	int64_t version() const;
	godot::String describe() const;
	// MurmurHash3's 32-bit finaliser: Fx.fmix32.
	int64_t fmix32(int64_t h) const;
	// fmix32 folded over values, starting from seed: NativeRef.fold32.
	int64_t fold32(int64_t seed, const godot::PackedInt64Array &values) const;
};

} // namespace wane

#endif
