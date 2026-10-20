#include "native_probe.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace wane {

namespace {

constexpr uint32_t MASK32 = 0xFFFFFFFFu;

// Unsigned 32-bit arithmetic wraps by definition in C++; there is no signed overflow anywhere.
inline uint32_t fmix32_u32(uint32_t h) {
	h ^= h >> 16;
	h *= 0x85EBCA6Bu;
	h ^= h >> 13;
	h *= 0xC2B2AE35u;
	h ^= h >> 16;
	return h;
}

inline uint32_t low32(int64_t v) {
	return static_cast<uint32_t>(static_cast<uint64_t>(v) & MASK32);
}

} // namespace

void NativeProbe::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &NativeProbe::version);
	ClassDB::bind_method(D_METHOD("describe"), &NativeProbe::describe);
	ClassDB::bind_method(D_METHOD("fmix32", "h"), &NativeProbe::fmix32);
	ClassDB::bind_method(D_METHOD("fold32", "seed", "values"), &NativeProbe::fold32);
}

int64_t NativeProbe::version() const {
	return NATIVE_VERSION;
}

String NativeProbe::describe() const {
#if defined(__clang__)
	const char *compiler = "clang " __clang_version__;
#elif defined(__GNUC__)
	const char *compiler = "gcc " __VERSION__;
#elif defined(_MSC_VER)
	const char *compiler = "msvc";
#else
	const char *compiler = "unknown compiler";
#endif
#if defined(DEBUG_ENABLED)
	const char *target = "template_debug";
#else
	const char *target = "template_release";
#endif
	return String("wane native ") + String::num_int64(NATIVE_VERSION) + String(", ") + String(compiler) + String(", ") + String(target);
}

int64_t NativeProbe::fmix32(int64_t h) const {
	// The reference masks to 32 bits first; low32 keeps the low 32 bits of any int64.
	return static_cast<int64_t>(fmix32_u32(low32(h)));
}

int64_t NativeProbe::fold32(int64_t seed, const PackedInt64Array &values) const {
	uint32_t h = low32(seed);
	const int64_t n = values.size();
	const int64_t *p = values.ptr();
	for (int64_t i = 0; i < n; i++) {
		h = fmix32_u32(h ^ low32(p[i]));
	}
	return static_cast<int64_t>(h);
}

} // namespace wane
