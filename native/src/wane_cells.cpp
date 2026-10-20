#include "wane_cells.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace wane {

void WaneCells::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_from", "centres", "alive", "reach_x", "reach_y"), &WaneCells::build_from);
	ClassDB::bind_method(D_METHOD("kill", "k"), &WaneCells::kill);
	ClassDB::bind_method(D_METHOD("within", "x", "y", "radius", "skip"), &WaneCells::within);
	ClassDB::bind_method(D_METHOD("nearest", "x", "y", "radius", "skip"), &WaneCells::nearest);
	ClassDB::bind_method(D_METHOD("touching", "l", "r", "t", "b"), &WaneCells::touching);
}

void WaneCells::build_from(const PackedInt32Array &centres, const PackedByteArray &alive, int64_t reach_x, int64_t reach_y) {
	cells.build(centres.ptr(), alive.ptr(), alive.size(), reach_x, reach_y);
}

void WaneCells::kill(int64_t k) {
	cells.kill(k);
}

PackedInt32Array WaneCells::within(int64_t x, int64_t y, int64_t radius, int64_t skip) {
	cells.within(x, y, radius, skip, found);
	answer.resize(static_cast<int64_t>(found.size()));
	int32_t *w = answer.ptrw();
	for (size_t i = 0; i < found.size(); i++) {
		w[i] = found[i];
	}
	return answer;
}

int64_t WaneCells::nearest(int64_t x, int64_t y, int64_t radius, int64_t skip) const {
	return cells.nearest(x, y, radius, skip);
}

PackedInt32Array WaneCells::touching(int64_t l, int64_t r, int64_t t, int64_t b) {
	cells.touching(l, r, t, b, found);
	answer.resize(static_cast<int64_t>(found.size()));
	int32_t *w = answer.ptrw();
	for (size_t i = 0; i < found.size(); i++) {
		w[i] = found[i];
	}
	return answer;
}

} // namespace wane
