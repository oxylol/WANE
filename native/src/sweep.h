// The physics sweep in C++ (BUILD.md section 13 Architecture; docs/adr/0022). A line-for-line port
// of core/physics/collision_world.gd and core/physics/collision_queries.gd, which stay the
// reference: every function here has the GDScript function of the same name (without the
// underscore) next to which it must be read, and tests/unit/core/physics/test_native_sweep.gd
// holds the two to identical bodies after every move.
//
// Rules (ADR-0021 Decision 4): int64_t only, in the core's 1/256-unit sub-pixels; no floating
// point; no signed overflow (the largest products are a few hundred thousand times a few
// thousand); division and modulo spelled out where the operands can be negative; no containers
// that iterate in an order that depends on addresses.
#ifndef WANE_SWEEP_H
#define WANE_SWEEP_H

#include <cstdint>
#include <vector>

namespace wane {

// Geometry constants of the world (core/physics/tile_grid.gd, core/sim/fx.gd).
constexpr int64_t SUB = 256;
constexpr int64_t TILE = 32;
constexpr int64_t TILE_SP = TILE * SUB;
constexpr int64_t HALF_SP = TILE_SP / 2;

// Tile ids (TileGrid).
constexpr int64_t T_EMPTY = 0;
constexpr int64_t T_SOLID = 1;
constexpr int64_t T_SMOOTH = 2;
constexpr int64_t T_ONE_WAY = 3;
constexpr int64_t T_SLOPE_R = 4;
constexpr int64_t T_SLOPE_L = 5;
constexpr int64_t T_SLOPE_R_LO = 6;
constexpr int64_t T_SLOPE_R_HI = 7;
constexpr int64_t T_SLOPE_L_HI = 8;
constexpr int64_t T_SLOPE_L_LO = 9;
constexpr int64_t T_SPIKES = 10;
constexpr int64_t T_PIT = 11;

// CollisionQueries.NONE and INSIDE.
constexpr int64_t NONE = int64_t(1) << 60;
constexpr int64_t INSIDE = -(int64_t(1) << 60);

// A Body (core/physics/body.gd): the fields a move reads or writes. The velocity is not one of
// them: the world never touches it.
struct Body {
	int64_t x = 0;
	int64_t y = 0;
	int64_t half_w = 0;
	int64_t height = 0;
	bool on_ground = false;
	int64_t ground_tile = -1;
	bool on_slope = false;
	bool hit_ceiling = false;
	int64_t hit_wall = 0;
	int64_t nudge_x = 0;
	int64_t nudge_y = 0;

	int64_t left() const { return x - half_w; }
	int64_t right() const { return x + half_w; }
	int64_t top() const { return y - height; }
};

// A SolidBox (core/physics/solid_box.gd).
struct Box {
	int64_t left = 0;
	int64_t top = 0;
	int64_t right = 0;
	int64_t bottom = 0;
	bool enabled = true;
	bool clingable = true;

	bool overlaps(int64_t l, int64_t r, int64_t t, int64_t b) const {
		return left < r && right > l && top < b && bottom > t;
	}
};

// Fx.div_floor for a positive divisor, and the helpers of TileGrid.
inline int64_t div_floor(int64_t a, int64_t b) {
	int64_t q = a / b;
	if ((a % b != 0) && ((a < 0) != (b < 0))) {
		q -= 1;
	}
	return q;
}
inline int64_t cell(int64_t sp) { return div_floor(sp, TILE_SP); }
inline bool is_wall(int64_t t) { return t == T_SOLID || t == T_SMOOTH; }
inline bool is_slope(int64_t t) { return t >= T_SLOPE_R && t <= T_SLOPE_L_LO; }
inline bool blocks_from_below(int64_t t) { return is_wall(t) || is_slope(t); }
inline int64_t signi(int64_t v) { return v > 0 ? 1 : (v < 0 ? -1 : 0); }
inline int64_t absi(int64_t v) { return v < 0 ? -v : v; }
inline int64_t mini(int64_t a, int64_t b) { return a < b ? a : b; }
inline int64_t maxi(int64_t a, int64_t b) { return a > b ? a : b; }

class Sweep {
public:
	// --- the data, mirrored from the GDScript world when it changes ---
	void set_grid(int64_t width, int64_t height, const uint8_t *tiles, int64_t count);
	void set_spike_inset(int64_t v) { spike_inset = v; }
	void resize_boxes(int64_t n);
	void set_box(int64_t slot, int64_t l, int64_t t, int64_t r, int64_t b, bool enabled, bool clingable);
	int64_t box_count() const { return static_cast<int64_t>(boxes.size()); }

	// --- the public moves and queries of CollisionWorld / CollisionQueries ---
	int64_t move_x(Body &b, int64_t dx, int64_t lift_sp, int64_t duck_sp);
	int64_t move_y(Body &b, int64_t dy, int64_t corner_sp);
	int64_t walk(Body &b, int64_t dx, int64_t lift_sp);
	int64_t landing_contact(const Body &b, int64_t dx, int64_t dy, int64_t lift_sp, int64_t slide_sp);
	bool drop_through(Body &b);
	void refresh_ground(Body &b);
	bool can_drop_through(const Body &b) const;
	bool wall_near(const Body &b, int64_t dir, int64_t reach, bool include_smooth) const;
	bool touches_spikes(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool touches_hazard(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool region_blocked(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool body_fits(int64_t cx, int64_t bottom, int64_t half_w, int64_t height);
	bool point_solid(int64_t x, int64_t y) const;
	int64_t floor_top_in(int64_t l, int64_t r, int64_t y0, int64_t y1) const;
	bool headroom(const Body &b, int64_t new_height) const;
	// One step of a patrolling walker standing on the ground (CollisionWorld.patrol_walk): turn at a
	// ledge unless it falls, walk with the contacts clear before and after. Returns bit 0 if it
	// turned at a ledge, bit 1 if the walk ended against a wall.
	int64_t patrol_walk(Body &b, int64_t dir, int64_t step, int64_t drop, bool falls);

private:
	int64_t width = 0;
	int64_t height = 0;
	std::vector<uint8_t> tiles;
	// The boxes the queries read: all of them, except while a move runs, when they are the enabled
	// boxes the move can reach (CollisionQueries.solids narrowed by CollisionWorld._narrow_solids,
	// the broad phase the reference has, which the port keeps so that the two agree even for a
	// move that carries a body further than the reach).
	std::vector<Box> boxes;
	std::vector<Box> held_boxes;
	int64_t spike_inset = 0;

	// Narrows boxes to what a move of [reach] by [b] can touch for the life of the object.
	struct Narrowed {
		Sweep &sweep;
		bool active;
		Narrowed(Sweep &s, const Body &b, int64_t reach);
		~Narrowed();
	};

	// What the last floor query found (CollisionQueries._hit_*).
	int64_t hit_tile = -1;
	bool hit_slope = false;
	int64_t hit_c = 0;
	int64_t hit_j = 0;
	bool hit_box = false;

	// The box a walking sweep moves, and its findings (CollisionWorld._sw_*).
	int64_t sw_l = 0;
	int64_t sw_r = 0;
	int64_t sw_t = 0;
	int64_t sw_dir = 0;
	int64_t sw_seg = 0;
	int64_t sw_dy = 0;
	bool walk_onto_top = false;
	bool swept_by_y = false;

	// Scratch for edge_run (the held centre ranges), kept to avoid an allocation per walk.
	std::vector<int64_t> held;

	int64_t get_tile(int64_t i, int64_t j) const {
		if (i < 0 || j < 0 || i >= width || j >= height) {
			return T_SOLID;
		}
		return tiles[static_cast<size_t>(j * width + i)];
	}
	static int64_t slope_surface(int64_t t, int64_t i, int64_t j, int64_t x_sp);
	static void slope_edge_heights(int64_t t, int64_t &left_h, int64_t &right_h);

	void set_hit(int64_t t, bool slope, int64_t c, int64_t j, bool box = false) {
		hit_tile = t;
		hit_slope = slope;
		hit_c = c;
		hit_j = j;
		hit_box = box;
	}

	// collision_queries.gd
	int64_t floor_at(int64_t c, int64_t x, int64_t xs, int64_t y_lo, int64_t y_hi, int64_t y_from);
	int64_t flat_under(int64_t l, int64_t r, int64_t y_lo, int64_t y_hi, int64_t y_from, int64_t slope_y, int64_t foot);
	int64_t landing(const Body &b, int64_t y0, int64_t y1);
	void set_ground(Body &b, bool grounded);
	bool slope_overlaps(int64_t t, int64_t c, int64_t j, int64_t l, int64_t r, int64_t b) const;
	bool solid_overlaps(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool walls_overlap(int64_t l, int64_t r, int64_t t, int64_t b) const;
	int64_t clear_up(int64_t l, int64_t r, int64_t t, int64_t dist) const;
	int64_t highest_wall_top(int64_t l, int64_t r, int64_t t, int64_t b) const;
	int64_t wall_top_ahead(int64_t l, int64_t r, int64_t t, int64_t b, int64_t dir) const;
	int64_t lowest_ceiling_bottom(int64_t l, int64_t r, int64_t t, int64_t b) const;
	bool touches_tile(int64_t l, int64_t r, int64_t t, int64_t b, int64_t kind, int64_t inset) const;

	// collision_world.gd, horizontal
	void air_steps(Body &b, int64_t dx, int64_t x0, int64_t lift_sp);
	void move_x_raw(Body &b, int64_t dx, int64_t lift_sp, int64_t duck_sp);
	int64_t sweep_x(int64_t l, int64_t r, int64_t t, int64_t b, int64_t dir, int64_t dist, int64_t foot) const;
	bool column_blocks(int64_t c, int64_t row_a, int64_t row_b, int64_t foot_top, int64_t dir) const;
	void settle_foot(Body &b, int64_t x0, int64_t dir);
	int64_t space_over(const Body &b, int64_t x0, int64_t x1, int64_t limit) const;
	int64_t rise(int64_t x0, int64_t x1, int64_t y, int64_t limit) const;
	bool ride_fits(const Body &b, int64_t rise_by) const;
	int64_t foot_depth(int64_t x0, int64_t x1, int64_t y) const;
	int64_t wall_top(int64_t c, int64_t j) const;
	bool try_lift(Body &b, int64_t dir, int64_t dist, int64_t allowed, int64_t max_lift);
	bool try_duck(Body &b, int64_t dir, int64_t dist, int64_t allowed, int64_t max_duck);

	// vertical
	int64_t move_up(Body &b, int64_t dist, int64_t corner_sp);
	int ceiling_nudges(const Body &b, int64_t allowed, int64_t max_shift, int64_t out[2]) const;
	bool slide_fits(const Body &b, int64_t shift, int64_t rise_by);
	bool plain_step_lands(const Body &b, int64_t dx, int64_t dy, int64_t lift_sp, int64_t slide_sp, int64_t floor_y);
	int64_t move_down(Body &b, int64_t dist);

	// grounded
	int64_t walk_raw(Body &b, int64_t dx, int64_t lift_sp);
	bool step_up(Body &b, int64_t dir, int64_t max_lift);
	bool step_down(Body &b, int64_t dir, int64_t max_drop);
	int64_t until_slope_rises(int64_t c, int64_t x0, int64_t y0, int64_t dir, int64_t seg) const;
	void walk_to(Body &b, int64_t x, int64_t c, int64_t t, int64_t j, bool slope, int64_t y0) const;
	int64_t to_solid_edge(int64_t x0, int64_t dir, int64_t seg) const;
	int64_t edge_run(const Body &b, int64_t dir, int64_t seg);
	int64_t sweep_walk(const Body &b, int64_t dir, int64_t seg, int64_t dy);
	int64_t swept_advance(int64_t b, int64_t ol, int64_t ot, int64_t o_r, int64_t ob);
};

} // namespace wane

#endif
