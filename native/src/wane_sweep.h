// WaneSweep: the physics sweep as a GDExtension class (docs/adr/0022). The geometry (the tile
// grid, the solid boxes, the spike inset) is mirrored into it by core/native/native_world.gd when
// it changes; every move and query then takes the body's fields as plain integers and answers with
// integers. The GDScript CollisionWorld is the reference: each method here is named for the
// CollisionWorld or CollisionQueries method it ports, and
// tests/unit/core/physics/test_native_sweep.gd holds them to identical bodies.
#ifndef WANE_WANE_SWEEP_H
#define WANE_WANE_SWEEP_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

#include "sweep.h"

namespace wane {

class WaneSweep : public godot::RefCounted {
	GDCLASS(WaneSweep, godot::RefCounted)

	Sweep sweep;
	// The answer of a move, reused (see the moves below).
	godot::PackedInt64Array result;
	godot::PackedInt64Array walk_result;

	godot::PackedInt64Array answer(int64_t moved, const Body &b);

protected:
	static void _bind_methods();

public:
	WaneSweep();

	// The data.
	void set_grid(int64_t width, int64_t height, const godot::PackedByteArray &tiles);
	void set_spike_inset(int64_t inset_sp);
	// Six integers per box: left, top, right, bottom, then flags (bit 0 enabled, bit 1 clingable).
	void set_boxes(const godot::PackedInt64Array &flat);
	void set_box(int64_t slot, int64_t left, int64_t top, int64_t right, int64_t bottom, int64_t flags);

	// A walk reads only the body's box and nudge_y (it always sets the ground contact itself, sets
	// hit_wall to the direction of the walk or leaves it, and touches nothing else), so it takes
	// and answers less than the other moves: [moved, x, y, nudge_y, contact], contact being
	// on_ground | on_slope << 1 | hit_wall_set << 2 | (ground_tile + 1) << 3.
	godot::PackedInt64Array walk(int64_t x, int64_t y, int64_t half_w, int64_t height, int64_t nudge_y, int64_t dx, int64_t lift_sp);

	// The other moves: the body's x, y, half_w, height, on_ground, ground_tile, on_slope,
	// hit_ceiling, hit_wall, nudge_x and nudge_y, then the move's own arguments; the answer is
	// [moved, x, y, on_ground, ground_tile, on_slope, hit_ceiling, hit_wall, nudge_x, nudge_y].
	godot::PackedInt64Array move_x(int64_t x, int64_t y, int64_t half_w, int64_t height, bool on_ground, int64_t ground_tile, bool on_slope, bool hit_ceiling, int64_t hit_wall, int64_t nudge_x, int64_t nudge_y, int64_t dx, int64_t lift_sp, int64_t duck_sp);
	godot::PackedInt64Array move_y(int64_t x, int64_t y, int64_t half_w, int64_t height, bool on_ground, int64_t ground_tile, bool on_slope, bool hit_ceiling, int64_t hit_wall, int64_t nudge_x, int64_t nudge_y, int64_t dy, int64_t corner_sp);

	// The ground contact of a body at rest: on_ground | on_slope << 1 | (ground_tile + 1) << 2.
	int64_t refresh_ground(int64_t x, int64_t y, int64_t half_w);
	int64_t landing_contact(int64_t x, int64_t y, int64_t half_w, int64_t height, bool on_ground, int64_t dx, int64_t dy, int64_t lift_sp, int64_t slide_sp);

	// Queries.
	bool can_drop_through(int64_t x, int64_t y, int64_t half_w, bool on_ground, bool on_slope) const;
	bool wall_near(int64_t x, int64_t y, int64_t half_w, int64_t height, int64_t dir, int64_t reach, bool include_smooth) const;
	bool touches_spikes(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool touches_hazard(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool region_blocked(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool body_fits(int64_t cx, int64_t bottom, int64_t half_w, int64_t height);
	bool point_solid(int64_t x, int64_t y) const;
	int64_t floor_top_in(int64_t l, int64_t r, int64_t y0, int64_t y1) const;
	bool headroom(int64_t x, int64_t y, int64_t half_w, int64_t height, int64_t new_height) const;
};

} // namespace wane

#endif
