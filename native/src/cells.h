// The room's enemies bucketed by where their centres stand (docs/adr/0020 Decision 15, stage 2):
// the native twin of core/combat/enemy_cells.gd. Plain C++, no Godot types, int64 only. The
// GDScript class is the reference; tests/unit/core/combat/test_native_cells.gd holds this to it.
#ifndef WANE_CELLS_H
#define WANE_CELLS_H

#include <cstdint>
#include <vector>

namespace wane {

// The side of a cell, in sub-pixels (EnemyCells.CELL: 128 units of 256 sub-pixels).
constexpr int64_t CELL_SP = 128 * 256;

class Cells {
public:
	// Buckets n enemies by their centres (x, y pairs); alive[k] is 0 for a dead one. reach_x and
	// reach_y are the widest half-width and the tallest height among them.
	void build(const int32_t *centres, const uint8_t *alive, int64_t n, int64_t reach_x, int64_t reach_y);
	// Enemy k died: the queries stop finding it (but touching, which asks about colliders and so
	// about the dead too, still does).
	void kill(int64_t k);
	// The living other than skip whose centres are within radius of (x, y), ascending.
	void within(int64_t x, int64_t y, int64_t radius, int64_t skip, std::vector<int32_t> &out) const;
	// The living other than skip nearest (x, y) within radius, ties to the lower index; -1 if none.
	int64_t nearest(int64_t x, int64_t y, int64_t radius, int64_t skip) const;
	// Every enemy, dead too, whose centre lies within the box [l, r] x [t, b] grown by the reach,
	// ascending.
	void touching(int64_t l, int64_t r, int64_t t, int64_t b, std::vector<int32_t> &out) const;

private:
	int64_t n = 0;
	int64_t x0 = 0;
	int64_t y0 = 0;
	int64_t cols = 0;
	int64_t rows = 0;
	int64_t reach_x = 0;
	int64_t reach_y = 0;
	std::vector<int32_t> centres;
	std::vector<uint8_t> alive;
	std::vector<int32_t> heads;
	std::vector<int32_t> next;
};

} // namespace wane

#endif
