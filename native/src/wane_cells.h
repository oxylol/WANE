// WaneCells: the enemy query cells as a GDExtension class (docs/adr/0020 Decision 15). The
// GDScript EnemyCells (core/combat/enemy_cells.gd) builds the enemies' centres once a tick it is
// asked about them and hands them over here; the questions of a proc, a Blaze burst or a trail
// are then answered natively. EnemyCells is the reference: each method here is named for the
// EnemyCells method it answers, and tests/unit/core/combat/test_native_cells.gd holds them to
// identical answers.
#ifndef WANE_WANE_CELLS_H
#define WANE_WANE_CELLS_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include "cells.h"

namespace wane {

class WaneCells : public godot::RefCounted {
	GDCLASS(WaneCells, godot::RefCounted)

	Cells cells;
	std::vector<int32_t> found;
	godot::PackedInt32Array answer;

protected:
	static void _bind_methods();

public:
	// The enemies' centres (x, y pairs), 1 for a living enemy and 0 for a dead one in alive, and
	// the widest half-width and tallest height among the enemies.
	void build_from(const godot::PackedInt32Array &centres, const godot::PackedByteArray &alive, int64_t reach_x, int64_t reach_y);
	void kill(int64_t k);
	godot::PackedInt32Array within(int64_t x, int64_t y, int64_t radius, int64_t skip);
	int64_t nearest(int64_t x, int64_t y, int64_t radius, int64_t skip) const;
	godot::PackedInt32Array touching(int64_t l, int64_t r, int64_t t, int64_t b);
};

} // namespace wane

#endif
