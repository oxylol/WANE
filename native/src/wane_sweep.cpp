#include "wane_sweep.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace wane {

namespace {

Body make_body(int64_t x, int64_t y, int64_t half_w, int64_t height, bool on_ground, int64_t ground_tile, bool on_slope, bool hit_ceiling, int64_t hit_wall, int64_t nudge_x, int64_t nudge_y) {
	Body b;
	b.x = x;
	b.y = y;
	b.half_w = half_w;
	b.height = height;
	b.on_ground = on_ground;
	b.ground_tile = ground_tile;
	b.on_slope = on_slope;
	b.hit_ceiling = hit_ceiling;
	b.hit_wall = hit_wall;
	b.nudge_x = nudge_x;
	b.nudge_y = nudge_y;
	return b;
}

Body at_rest(int64_t x, int64_t y, int64_t half_w, int64_t height) {
	return make_body(x, y, half_w, height, false, -1, false, false, 0, 0, 0);
}

} // namespace

WaneSweep::WaneSweep() {
	result.resize(10);
	walk_result.resize(5);
	patrol_result.resize(4);
}

void WaneSweep::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_grid", "width", "height", "tiles"), &WaneSweep::set_grid);
	ClassDB::bind_method(D_METHOD("set_spike_inset", "inset_sp"), &WaneSweep::set_spike_inset);
	ClassDB::bind_method(D_METHOD("set_boxes", "flat"), &WaneSweep::set_boxes);
	ClassDB::bind_method(D_METHOD("set_box", "slot", "left", "top", "right", "bottom", "flags"), &WaneSweep::set_box);
	ClassDB::bind_method(D_METHOD("walk", "x", "y", "half_w", "height", "nudge_y", "dx", "lift_sp"), &WaneSweep::walk);
	ClassDB::bind_method(D_METHOD("move_x", "x", "y", "half_w", "height", "on_ground", "ground_tile", "on_slope", "hit_ceiling", "hit_wall", "nudge_x", "nudge_y", "dx", "lift_sp", "duck_sp"), &WaneSweep::move_x);
	ClassDB::bind_method(D_METHOD("move_y", "x", "y", "half_w", "height", "on_ground", "ground_tile", "on_slope", "hit_ceiling", "hit_wall", "nudge_x", "nudge_y", "dy", "corner_sp"), &WaneSweep::move_y);
	ClassDB::bind_method(D_METHOD("refresh_ground", "x", "y", "half_w"), &WaneSweep::refresh_ground);
	ClassDB::bind_method(D_METHOD("landing_contact", "x", "y", "half_w", "height", "on_ground", "dx", "dy", "lift_sp", "slide_sp"), &WaneSweep::landing_contact);
	ClassDB::bind_method(D_METHOD("can_drop_through", "x", "y", "half_w", "on_ground", "on_slope"), &WaneSweep::can_drop_through);
	ClassDB::bind_method(D_METHOD("wall_near", "x", "y", "half_w", "height", "dir", "reach", "include_smooth"), &WaneSweep::wall_near);
	ClassDB::bind_method(D_METHOD("touches_spikes", "l", "r", "t", "b"), &WaneSweep::touches_spikes);
	ClassDB::bind_method(D_METHOD("touches_hazard", "l", "r", "t", "b"), &WaneSweep::touches_hazard);
	ClassDB::bind_method(D_METHOD("region_blocked", "l", "r", "t", "b"), &WaneSweep::region_blocked);
	ClassDB::bind_method(D_METHOD("body_fits", "cx", "bottom", "half_w", "height"), &WaneSweep::body_fits);
	ClassDB::bind_method(D_METHOD("point_solid", "x", "y"), &WaneSweep::point_solid);
	ClassDB::bind_method(D_METHOD("floor_top_in", "l", "r", "y0", "y1"), &WaneSweep::floor_top_in);
	ClassDB::bind_method(D_METHOD("headroom", "x", "y", "half_w", "height", "new_height"), &WaneSweep::headroom);
	ClassDB::bind_method(D_METHOD("patrol_walk", "x", "y", "half_w", "height", "dir", "step", "drop", "falls"), &WaneSweep::patrol_walk);
	ClassDB::bind_method(D_METHOD("patrol_many", "ops", "count"), &WaneSweep::patrol_many);
}

void WaneSweep::set_grid(int64_t width, int64_t height, const PackedByteArray &tiles) {
	sweep.set_grid(width, height, tiles.ptr(), tiles.size());
}

void WaneSweep::set_spike_inset(int64_t inset_sp) {
	sweep.set_spike_inset(inset_sp);
}

void WaneSweep::set_boxes(const PackedInt64Array &flat) {
	const int64_t n = flat.size() / 6;
	sweep.resize_boxes(n);
	const int64_t *p = flat.ptr();
	for (int64_t i = 0; i < n; i++) {
		const int64_t *q = p + i * 6;
		sweep.set_box(i, q[0], q[1], q[2], q[3], (q[4] & 1) != 0, (q[4] & 2) != 0);
	}
}

void WaneSweep::set_box(int64_t slot, int64_t left, int64_t top, int64_t right, int64_t bottom, int64_t flags) {
	sweep.set_box(slot, left, top, right, bottom, (flags & 1) != 0, (flags & 2) != 0);
}

PackedInt64Array WaneSweep::answer(int64_t moved, const Body &b) {
	int64_t *w = result.ptrw();
	w[0] = moved;
	w[1] = b.x;
	w[2] = b.y;
	w[3] = b.on_ground ? 1 : 0;
	w[4] = b.ground_tile;
	w[5] = b.on_slope ? 1 : 0;
	w[6] = b.hit_ceiling ? 1 : 0;
	w[7] = b.hit_wall;
	w[8] = b.nudge_x;
	w[9] = b.nudge_y;
	return result;
}

PackedInt64Array WaneSweep::walk(int64_t x, int64_t y, int64_t half_w, int64_t height, int64_t nudge_y, int64_t dx, int64_t lift_sp) {
	Body b = at_rest(x, y, half_w, height);
	b.nudge_y = nudge_y;
	const int64_t moved = sweep.walk(b, dx, lift_sp);
	int64_t *w = walk_result.ptrw();
	w[0] = moved;
	w[1] = b.x;
	w[2] = b.y;
	w[3] = b.nudge_y;
	w[4] = (b.on_ground ? 1 : 0) | (b.on_slope ? 2 : 0) | (b.hit_wall != 0 ? 4 : 0) | ((b.ground_tile + 1) << 3);
	return walk_result;
}

PackedInt64Array WaneSweep::move_x(int64_t x, int64_t y, int64_t half_w, int64_t height, bool on_ground, int64_t ground_tile, bool on_slope, bool hit_ceiling, int64_t hit_wall, int64_t nudge_x, int64_t nudge_y, int64_t dx, int64_t lift_sp, int64_t duck_sp) {
	Body b = make_body(x, y, half_w, height, on_ground, ground_tile, on_slope, hit_ceiling, hit_wall, nudge_x, nudge_y);
	const int64_t moved = sweep.move_x(b, dx, lift_sp, duck_sp);
	return answer(moved, b);
}

PackedInt64Array WaneSweep::move_y(int64_t x, int64_t y, int64_t half_w, int64_t height, bool on_ground, int64_t ground_tile, bool on_slope, bool hit_ceiling, int64_t hit_wall, int64_t nudge_x, int64_t nudge_y, int64_t dy, int64_t corner_sp) {
	Body b = make_body(x, y, half_w, height, on_ground, ground_tile, on_slope, hit_ceiling, hit_wall, nudge_x, nudge_y);
	const int64_t moved = sweep.move_y(b, dy, corner_sp);
	return answer(moved, b);
}

int64_t WaneSweep::refresh_ground(int64_t x, int64_t y, int64_t half_w) {
	Body b = at_rest(x, y, half_w, 0);
	sweep.refresh_ground(b);
	return (b.on_ground ? 1 : 0) | (b.on_slope ? 2 : 0) | ((b.ground_tile + 1) << 2);
}

int64_t WaneSweep::landing_contact(int64_t x, int64_t y, int64_t half_w, int64_t height, bool on_ground, int64_t dx, int64_t dy, int64_t lift_sp, int64_t slide_sp) {
	Body b = at_rest(x, y, half_w, height);
	b.on_ground = on_ground;
	return sweep.landing_contact(b, dx, dy, lift_sp, slide_sp);
}

bool WaneSweep::can_drop_through(int64_t x, int64_t y, int64_t half_w, bool on_ground, bool on_slope) const {
	Body b = at_rest(x, y, half_w, 0);
	b.on_ground = on_ground;
	b.on_slope = on_slope;
	return sweep.can_drop_through(b);
}

bool WaneSweep::wall_near(int64_t x, int64_t y, int64_t half_w, int64_t height, int64_t dir, int64_t reach, bool include_smooth) const {
	return sweep.wall_near(at_rest(x, y, half_w, height), dir, reach, include_smooth);
}

bool WaneSweep::touches_spikes(int64_t l, int64_t r, int64_t t, int64_t b) const {
	return sweep.touches_spikes(l, r, t, b);
}

bool WaneSweep::touches_hazard(int64_t l, int64_t r, int64_t t, int64_t b) const {
	return sweep.touches_hazard(l, r, t, b);
}

bool WaneSweep::region_blocked(int64_t l, int64_t r, int64_t t, int64_t b) const {
	return sweep.region_blocked(l, r, t, b);
}

bool WaneSweep::body_fits(int64_t cx, int64_t bottom, int64_t half_w, int64_t height) {
	return sweep.body_fits(cx, bottom, half_w, height);
}

bool WaneSweep::point_solid(int64_t x, int64_t y) const {
	return sweep.point_solid(x, y);
}

int64_t WaneSweep::floor_top_in(int64_t l, int64_t r, int64_t y0, int64_t y1) const {
	return sweep.floor_top_in(l, r, y0, y1);
}

bool WaneSweep::headroom(int64_t x, int64_t y, int64_t half_w, int64_t height, int64_t new_height) const {
	return sweep.headroom(at_rest(x, y, half_w, height), new_height);
}

PackedInt64Array WaneSweep::patrol_walk(int64_t x, int64_t y, int64_t half_w, int64_t height, int64_t dir, int64_t step, int64_t drop, bool falls) {
	Body b = at_rest(x, y, half_w, height);
	const int64_t flags = sweep.patrol_walk(b, dir, step, drop, falls);
	int64_t *w = patrol_result.ptrw();
	w[0] = flags;
	w[1] = b.x;
	w[2] = b.y;
	w[3] = (b.on_ground ? 1 : 0) | (b.on_slope ? 2 : 0) | ((b.ground_tile + 1) << 2);
	return patrol_result;
}

PackedInt64Array WaneSweep::patrol_many(const PackedInt64Array &ops, int64_t count) {
	many_result.resize(4 * count);
	int64_t *w = many_result.ptrw();
	const int64_t *p = ops.ptr();
	for (int64_t k = 0; k < count; k++) {
		const int64_t *q = p + 8 * k;
		Body b = at_rest(q[1], q[2], q[3], q[4]);
		int64_t flags = 0;
		if (q[0] == 0) {
			sweep.refresh_ground(b);
		} else {
			flags = sweep.patrol_walk(b, q[5], q[6], q[7], q[0] == 2);
		}
		int64_t *o = w + 4 * k;
		o[0] = b.x;
		o[1] = b.y;
		o[2] = (b.on_ground ? 1 : 0) | (b.on_slope ? 2 : 0) | ((b.ground_tile + 1) << 2);
		o[3] = flags;
	}
	return many_result;
}

} // namespace wane
