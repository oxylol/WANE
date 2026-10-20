#include "sweep.h"

namespace wane {

// --- data ---------------------------------------------------------------------------------

void Sweep::set_grid(int64_t w, int64_t h, const uint8_t *data, int64_t count) {
	width = w;
	height = h;
	tiles.assign(data, data + count);
}

void Sweep::resize_boxes(int64_t n) {
	boxes.resize(static_cast<size_t>(n));
}

void Sweep::set_box(int64_t slot, int64_t l, int64_t t, int64_t r, int64_t b, bool enabled, bool clingable) {
	Box &box = boxes[static_cast<size_t>(slot)];
	box.left = l;
	box.top = t;
	box.right = r;
	box.bottom = b;
	box.enabled = enabled;
	box.clingable = clingable;
}

Sweep::Narrowed::Narrowed(Sweep &s, const Body &b, int64_t reach) :
		sweep(s), active(!s.boxes.empty()) {
	if (!active) {
		return;
	}
	const int64_t m = reach + b.half_w + TILE_SP;
	const int64_t l = b.x - b.half_w - m;
	const int64_t r = b.x + b.half_w + m;
	const int64_t t = b.y - b.height - m;
	const int64_t bot = b.y + m;
	s.held_boxes.swap(s.boxes);
	s.boxes.clear();
	for (const Box &sb : s.held_boxes) {
		if (sb.enabled && sb.left < r && sb.right > l && sb.top < bot && sb.bottom > t) {
			s.boxes.push_back(sb);
		}
	}
}

Sweep::Narrowed::~Narrowed() {
	if (active) {
		sweep.boxes.swap(sweep.held_boxes);
	}
}

// TileGrid.slope_surface: the surface y of slope tile (i, j) at world x.
int64_t Sweep::slope_surface(int64_t t, int64_t i, int64_t j, int64_t x_sp) {
	const int64_t lx = x_sp - i * TILE_SP;
	const int64_t top = j * TILE_SP;
	switch (t) {
		case T_SLOPE_R:
			return top + TILE_SP - lx;
		case T_SLOPE_L:
			return top + lx;
		case T_SLOPE_R_LO:
			return top + TILE_SP - div_floor(lx, 2);
		case T_SLOPE_R_HI:
			return top + HALF_SP - div_floor(lx, 2);
		case T_SLOPE_L_HI:
			return top + div_floor(lx, 2);
		case T_SLOPE_L_LO:
			return top + HALF_SP + div_floor(lx, 2);
		default:
			return top;
	}
}

// TileGrid.slope_edge_heights: the high edge's height at the left and right tile borders.
void Sweep::slope_edge_heights(int64_t t, int64_t &left_h, int64_t &right_h) {
	switch (t) {
		case T_SLOPE_R:
			left_h = 0;
			right_h = TILE_SP;
			return;
		case T_SLOPE_L:
			left_h = TILE_SP;
			right_h = 0;
			return;
		case T_SLOPE_R_LO:
			left_h = 0;
			right_h = HALF_SP;
			return;
		case T_SLOPE_R_HI:
			left_h = HALF_SP;
			right_h = TILE_SP;
			return;
		case T_SLOPE_L_HI:
			left_h = TILE_SP;
			right_h = HALF_SP;
			return;
		case T_SLOPE_L_LO:
			left_h = HALF_SP;
			right_h = 0;
			return;
		default:
			left_h = TILE_SP;
			right_h = TILE_SP;
			return;
	}
}

// --- floor queries (collision_queries.gd) ---------------------------------------------------

int64_t Sweep::floor_at(int64_t c, int64_t x, int64_t xs, int64_t y_lo, int64_t y_hi, int64_t y_from) {
	set_hit(-1, false, 0, 0);
	int64_t found = NONE;
	int64_t j = cell(y_lo - 1);
	const int64_t last = cell(y_hi);
	while (j <= last) {
		const int64_t t = get_tile(c, j);
		const int64_t top = j * TILE_SP;
		if (is_wall(t)) {
			if (top < y_lo) {
				return INSIDE;
			}
			found = top;
			set_hit(t, false, c, j);
			break;
		}
		if (is_slope(t)) {
			const int64_t s = slope_surface(t, c, j, x);
			if (s < y_lo) {
				return INSIDE;
			}
			if (s <= y_hi) {
				found = s;
				set_hit(t, true, c, j);
				break;
			}
		} else if (t == T_ONE_WAY && top >= y_lo && top >= y_from && top <= y_hi) {
			found = top;
			set_hit(t, false, c, j);
			break;
		}
		j += 1;
	}
	for (const Box &sb : boxes) {
		if (!sb.enabled || xs < sb.left || xs >= sb.right) {
			continue;
		}
		if (sb.top < y_lo && sb.bottom >= y_lo) {
			return INSIDE;
		}
		if (sb.top >= y_lo && sb.top <= y_hi && sb.top < found) {
			found = sb.top;
			set_hit(T_SOLID, false, 0, 0, true);
		}
	}
	return found;
}

int64_t Sweep::flat_under(int64_t l, int64_t r, int64_t y_lo, int64_t y_hi, int64_t y_from, int64_t slope_y, int64_t foot) {
	int64_t found = NONE;
	const int64_t first = -div_floor(-y_lo, TILE_SP);
	const int64_t last = cell(y_hi);
	int64_t hit_t = -1;
	int64_t hit_cc = 0;
	int64_t hit_jj = 0;
	if (first <= last) {
		// The row holding y_lo - 1, just above the first candidate row.
		const int64_t inside_row = first - 1;
		const int64_t c_last = cell(r - 1);
		for (int64_t c = cell(l); c <= c_last; c++) {
			if (is_wall(get_tile(c, inside_row))) {
				continue;
			}
			for (int64_t j = first; j <= last; j++) {
				const int64_t top = j * TILE_SP;
				if (top >= found) {
					break;
				}
				const int64_t t = get_tile(c, j);
				const bool wall = is_wall(t);
				if (wall && top < slope_y && slope_y - top <= foot) {
					break;
				}
				if (wall || (t == T_ONE_WAY && top >= y_from)) {
					found = top;
					hit_t = t;
					hit_cc = c;
					hit_jj = j;
					break;
				}
				if (is_slope(t)) {
					break;
				}
			}
		}
	}
	for (const Box &sb : boxes) {
		if (sb.enabled && sb.left < r && sb.right > l && sb.top >= y_lo && sb.top <= y_hi) {
			if (sb.top < found) {
				found = sb.top;
				hit_t = T_SOLID;
				hit_cc = 0;
				hit_jj = 0;
			}
		}
	}
	set_hit(hit_t, false, hit_cc, hit_jj);
	return found;
}

int64_t Sweep::landing(const Body &b, int64_t y0, int64_t y1) {
	const int64_t foot = b.half_w;
	int64_t centre = floor_at(cell(b.x), b.x, b.x, y0, y1 + foot, y0);
	const int64_t c_tile = hit_tile;
	const bool c_slope = hit_slope;
	const int64_t c_c = hit_c;
	const int64_t c_j = hit_j;
	const int64_t slope_y = (c_slope && centre != INSIDE) ? centre : NONE;
	if (centre == INSIDE || centre > y1) {
		centre = NONE;
	}
	const int64_t edge = flat_under(b.left(), b.right(), y0, y1, y0, slope_y, foot);
	if (centre != NONE && centre <= edge) {
		set_hit(c_tile, c_slope, c_c, c_j);
		return centre;
	}
	return edge;
}

void Sweep::set_ground(Body &b, bool grounded) {
	b.on_ground = grounded;
	b.ground_tile = grounded ? hit_tile : -1;
	b.on_slope = grounded ? hit_slope : false;
}

void Sweep::refresh_ground(Body &b) {
	set_ground(b, landing(b, b.y, b.y) == b.y);
}

// --- region queries -------------------------------------------------------------------------

bool Sweep::region_blocked(int64_t l, int64_t r, int64_t t, int64_t b) const {
	if (r <= l || b <= t) {
		return false;
	}
	const int64_t c_last = cell(r - 1);
	const int64_t j_first = cell(t);
	const int64_t j_last = cell(b - 1);
	for (int64_t c = cell(l); c <= c_last; c++) {
		for (int64_t j = j_first; j <= j_last; j++) {
			const int64_t tile = get_tile(c, j);
			if (is_wall(tile)) {
				return true;
			}
			if (is_slope(tile) && slope_overlaps(tile, c, j, l, r, b)) {
				return true;
			}
		}
	}
	return solid_overlaps(l, r, t, b);
}

bool Sweep::slope_overlaps(int64_t t, int64_t c, int64_t j, int64_t l, int64_t r, int64_t b) const {
	const int64_t xa = maxi(l, c * TILE_SP);
	const int64_t xb = mini(r, (c + 1) * TILE_SP) - 1;
	const int64_t s = mini(slope_surface(t, c, j, xa), slope_surface(t, c, j, xb));
	return s < b;
}

bool Sweep::solid_overlaps(int64_t l, int64_t r, int64_t t, int64_t b) const {
	for (const Box &sb : boxes) {
		if (sb.enabled && sb.overlaps(l, r, t, b)) {
			return true;
		}
	}
	return false;
}

bool Sweep::walls_overlap(int64_t l, int64_t r, int64_t t, int64_t b) const {
	const int64_t c_last = cell(r - 1);
	const int64_t j_first = cell(t);
	const int64_t j_last = cell(b - 1);
	for (int64_t c = cell(l); c <= c_last; c++) {
		for (int64_t j = j_first; j <= j_last; j++) {
			if (is_wall(get_tile(c, j))) {
				return true;
			}
		}
	}
	return solid_overlaps(l, r, t, b);
}

bool Sweep::body_fits(int64_t cx, int64_t bottom, int64_t half_w, int64_t body_height) {
	if (region_blocked(cx - half_w, cx + half_w, bottom - body_height, bottom)) {
		return false;
	}
	return floor_at(cell(cx), cx, cx, bottom, bottom, bottom) != INSIDE;
}

bool Sweep::point_solid(int64_t x_sp, int64_t y_sp) const {
	const int64_t c = cell(x_sp);
	const int64_t j = cell(y_sp);
	const int64_t t = get_tile(c, j);
	if (is_wall(t)) {
		return true;
	}
	if (is_slope(t) && y_sp >= slope_surface(t, c, j, x_sp)) {
		return true;
	}
	return solid_overlaps(x_sp, x_sp + 1, y_sp, y_sp + 1);
}

int64_t Sweep::floor_top_in(int64_t l, int64_t r, int64_t y0, int64_t y1) const {
	int64_t best = NONE;
	if (r <= l || y1 < y0) {
		return best;
	}
	const int64_t c_last = cell(r - 1);
	const int64_t j_first = cell(y0);
	const int64_t j_last = cell(y1);
	for (int64_t c = cell(l); c <= c_last; c++) {
		for (int64_t j = j_first; j <= j_last; j++) {
			const int64_t top = j * TILE_SP;
			if (top >= best) {
				break;
			}
			const int64_t t = get_tile(c, j);
			int64_t y = NONE;
			if (is_wall(t)) {
				// A span already reaching into a wall stands on it at once.
				y = maxi(top, y0);
			} else if (t == T_ONE_WAY) {
				y = top;
			} else if (is_slope(t)) {
				const int64_t xa = maxi(l, c * TILE_SP);
				const int64_t xb = mini(r, (c + 1) * TILE_SP) - 1;
				y = mini(slope_surface(t, c, j, xa), slope_surface(t, c, j, xb));
			}
			if (y >= y0 && y <= y1) {
				best = mini(best, y);
				break;
			}
		}
	}
	for (const Box &sb : boxes) {
		if (sb.enabled && sb.left < r && sb.right > l && sb.top >= y0 && sb.top <= y1) {
			best = mini(best, sb.top);
		}
	}
	return best;
}

// --- obstacles above and ahead --------------------------------------------------------------

int64_t Sweep::clear_up(int64_t l, int64_t r, int64_t t, int64_t dist) const {
	int64_t best = dist;
	int64_t j = cell(t) - 1;
	const int64_t j_end = cell(t - dist);
	const int64_t c0 = cell(l);
	const int64_t c1 = cell(r - 1);
	while (j >= j_end) {
		bool blocked = false;
		for (int64_t c = c0; c <= c1; c++) {
			if (blocks_from_below(get_tile(c, j))) {
				blocked = true;
				break;
			}
		}
		if (blocked) {
			best = t - (j + 1) * TILE_SP;
			break;
		}
		j -= 1;
	}
	for (const Box &s : boxes) {
		if (s.enabled && s.bottom <= t && s.right > l && s.left < r) {
			best = mini(best, t - s.bottom);
		}
	}
	return maxi(best, 0);
}

int64_t Sweep::highest_wall_top(int64_t l, int64_t r, int64_t t, int64_t b) const {
	int64_t best = b;
	const int64_t c_last = cell(r - 1);
	const int64_t j_first = cell(t);
	const int64_t j_last = cell(b - 1);
	for (int64_t c = cell(l); c <= c_last; c++) {
		for (int64_t j = j_first; j <= j_last; j++) {
			if (is_wall(get_tile(c, j))) {
				best = mini(best, j * TILE_SP);
				break;
			}
		}
	}
	for (const Box &s : boxes) {
		if (s.enabled && s.overlaps(l, r, t, b)) {
			best = mini(best, s.top);
		}
	}
	return best;
}

int64_t Sweep::wall_top_ahead(int64_t l, int64_t r, int64_t t, int64_t b, int64_t dir) const {
	const int64_t x = dir > 0 ? r : l - 1;
	return highest_wall_top(x, x + 1, t, b);
}

int64_t Sweep::lowest_ceiling_bottom(int64_t l, int64_t r, int64_t t, int64_t b) const {
	int64_t best = t;
	const int64_t c_last = cell(r - 1);
	const int64_t j_first = cell(t);
	for (int64_t c = cell(l); c <= c_last; c++) {
		int64_t j = cell(b - 1);
		while (j >= j_first) {
			if (blocks_from_below(get_tile(c, j))) {
				best = maxi(best, (j + 1) * TILE_SP);
				break;
			}
			j -= 1;
		}
	}
	for (const Box &s : boxes) {
		if (s.enabled && s.overlaps(l, r, t, b)) {
			best = maxi(best, s.bottom);
		}
	}
	return best;
}

// --- contacts -------------------------------------------------------------------------------

bool Sweep::can_drop_through(const Body &b) const {
	if (!b.on_ground || b.on_slope) {
		return false;
	}
	const int64_t y = b.y;
	const int64_t j = div_floor(y, TILE_SP);
	if (j * TILE_SP != y) {
		return false;
	}
	bool one_way = false;
	bool other = false;
	const int64_t c_last = cell(b.right() - 1);
	for (int64_t c = cell(b.left()); c <= c_last; c++) {
		const int64_t t = get_tile(c, j);
		other = other || is_wall(t);
		one_way = one_way || t == T_ONE_WAY;
	}
	for (const Box &sb : boxes) {
		if (sb.enabled && sb.top == y && sb.left < b.right() && sb.right > b.left()) {
			other = true;
		}
	}
	return one_way && !other;
}

bool Sweep::drop_through(Body &b) {
	if (!can_drop_through(b)) {
		return false;
	}
	b.y += 1;
	b.on_ground = false;
	b.ground_tile = -1;
	b.on_slope = false;
	return true;
}

bool Sweep::wall_near(const Body &b, int64_t dir, int64_t reach, bool include_smooth) const {
	const int64_t l = dir > 0 ? b.right() : b.left() - reach;
	const int64_t r = dir > 0 ? b.right() + reach : b.left();
	const int64_t t = b.top();
	const int64_t bot = b.y - b.half_w;
	const int64_t c_last = cell(r - 1);
	const int64_t j_first = cell(t);
	const int64_t j_last = cell(bot - 1);
	for (int64_t c = cell(l); c <= c_last; c++) {
		for (int64_t j = j_first; j <= j_last; j++) {
			const int64_t tile = get_tile(c, j);
			if (tile == T_SOLID || (include_smooth && tile == T_SMOOTH)) {
				return true;
			}
		}
	}
	for (const Box &s : boxes) {
		if (s.enabled && s.clingable && s.overlaps(l, r, t, bot)) {
			return true;
		}
	}
	return false;
}

bool Sweep::touches_spikes(int64_t l, int64_t r, int64_t t, int64_t b) const {
	return touches_tile(l, r, t, b, T_SPIKES, spike_inset);
}

bool Sweep::touches_hazard(int64_t l, int64_t r, int64_t t, int64_t b) const {
	return touches_spikes(l, r, t, b) || touches_tile(l, r, t, b, T_PIT, 0);
}

bool Sweep::touches_tile(int64_t l, int64_t r, int64_t t, int64_t b, int64_t kind, int64_t inset) const {
	const int64_t c_last = cell(r - 1);
	const int64_t j_first = cell(t);
	const int64_t j_last = cell(b - 1);
	for (int64_t c = cell(l); c <= c_last; c++) {
		for (int64_t j = j_first; j <= j_last; j++) {
			if (get_tile(c, j) == kind) {
				if (b > j * TILE_SP + inset) {
					return true;
				}
			}
		}
	}
	return false;
}

bool Sweep::headroom(const Body &b, int64_t new_height) const {
	const int64_t top = b.y - new_height;
	return !(region_blocked(b.left(), b.right(), top, b.y - b.half_w) || solid_overlaps(b.left(), b.right(), top, b.y));
}

// --- horizontal, airborne (collision_world.gd) ------------------------------------------------

int64_t Sweep::move_x(Body &b, int64_t dx, int64_t lift_sp, int64_t duck_sp) {
	if (dx == 0) {
		return 0;
	}
	Narrowed narrowed(*this, b, absi(dx));
	const int64_t x0 = b.x;
	const bool airborne = !b.on_ground;
	move_x_raw(b, dx, lift_sp, duck_sp);
	if (airborne && lift_sp > 0 && b.hit_wall == signi(dx)) {
		air_steps(b, dx, x0, lift_sp);
	}
	return b.x - x0;
}

void Sweep::air_steps(Body &b, int64_t dx, int64_t x0, int64_t lift_sp) {
	const int64_t dir = signi(dx);
	bool stepped = false;
	while (b.hit_wall == dir) {
		const int64_t left = absi(dx) - absi(b.x - x0);
		if (left <= 0 || !step_up(b, dir, lift_sp)) {
			break;
		}
		stepped = true;
		b.hit_wall = 0;
		move_x_raw(b, dir * left, 0, 0);
	}
	if (stepped) {
		refresh_ground(b);
	}
}

void Sweep::move_x_raw(Body &b, int64_t dx, int64_t lift_sp, int64_t duck_sp) {
	const int64_t dir = dx > 0 ? 1 : -1;
	int64_t left = absi(dx);
	const int64_t y0 = b.y;
	int64_t allowed = sweep_x(b.left(), b.right(), b.top(), b.y, dir, left, b.half_w);
	if (allowed < left && !b.on_ground) {
		if (lift_sp > 0 && try_lift(b, dir, left, allowed, lift_sp)) {
			return;
		}
		if (duck_sp > 0 && try_duck(b, dir, left, allowed, duck_sp)) {
			return;
		}
	}
	while (true) {
		const int64_t xs = b.x;
		const int64_t ys = b.y;
		const int64_t target = xs + dir * allowed;
		b.x = target;
		settle_foot(b, xs, dir);
		left -= absi(b.x - xs);
		if (left == 0 || allowed == 0 || b.x != target || b.y == ys) {
			break;
		}
		allowed = sweep_x(b.left(), b.right(), b.top(), b.y, dir, left, b.half_w);
	}
	if (left > 0) {
		b.hit_wall = dir;
	}
	if (b.on_ground || b.y != y0) {
		refresh_ground(b);
	}
}

int64_t Sweep::sweep_x(int64_t l, int64_t r, int64_t t, int64_t b, int64_t dir, int64_t dist, int64_t foot) const {
	int64_t best = dist;
	const int64_t row_a = cell(t);
	const int64_t row_b = cell(b - 1);
	const int64_t foot_top = b - foot;
	if (dir > 0) {
		int64_t c = cell(r - 1) + 1;
		const int64_t c_end = cell(r + dist - 1);
		while (c <= c_end) {
			if (column_blocks(c, row_a, row_b, foot_top, dir)) {
				best = c * TILE_SP - r;
				break;
			}
			c += 1;
		}
	} else {
		int64_t c = cell(l) - 1;
		const int64_t c_end = cell(l - dist);
		while (c >= c_end) {
			if (column_blocks(c, row_a, row_b, foot_top, dir)) {
				best = l - (c + 1) * TILE_SP;
				break;
			}
			c -= 1;
		}
	}
	for (const Box &sb : boxes) {
		if (!sb.enabled || sb.bottom <= t || sb.top >= b) {
			continue;
		}
		if (dir > 0 && sb.left >= r) {
			best = mini(best, sb.left - r);
		} else if (dir < 0 && sb.right <= l) {
			best = mini(best, l - sb.right);
		}
	}
	return best;
}

bool Sweep::column_blocks(int64_t c, int64_t row_a, int64_t row_b, int64_t foot_top, int64_t dir) const {
	for (int64_t j = row_a; j <= row_b; j++) {
		if (!is_wall(get_tile(c, j))) {
			continue;
		}
		if (j * TILE_SP < foot_top) {
			return true;
		}
		const int64_t before = get_tile(c - dir, j);
		if (!is_slope(before)) {
			return true;
		}
		int64_t left_h = 0;
		int64_t right_h = 0;
		slope_edge_heights(before, left_h, right_h);
		return (dir > 0 ? right_h : left_h) != TILE_SP;
	}
	return false;
}

void Sweep::settle_foot(Body &b, int64_t x0, int64_t dir) {
	const int64_t x1 = b.x;
	if (x1 == x0) {
		return;
	}
	const int64_t y = b.y;
	const int64_t limit = maxi(absi(x1 - x0) + SUB, b.half_w);
	const int64_t depth = rise(x0, x1, y, limit);
	if (depth <= 0) {
		return;
	}
	if (depth <= limit && ride_fits(b, depth)) {
		b.y = y - depth;
		return;
	}
	b.hit_wall = dir;
	// The furthest point at which the rise fits under the lowest ceiling over the path travelled
	// to it (and is no steeper than the slopes allow).
	int64_t ok = 0;
	int64_t bad = absi(x1 - x0);
	while (bad - ok > 1) {
		const int64_t mid = (ok + bad) / 2;
		const int64_t most = mini(space_over(b, x0, x0 + dir * mid, limit), maxi(mid + SUB, b.half_w));
		if (rise(x0, x0 + dir * mid, y, most) <= most) {
			ok = mid;
		} else {
			bad = mid;
		}
	}
	b.x = x0 + dir * ok;
	b.y = y - rise(x0, b.x, y, space_over(b, x0, b.x, limit));
}

int64_t Sweep::space_over(const Body &b, int64_t x0, int64_t x1, int64_t limit) const {
	return clear_up(mini(x0, x1) - b.half_w, maxi(x0, x1) + b.half_w, b.top(), limit);
}

int64_t Sweep::rise(int64_t x0, int64_t x1, int64_t y, int64_t limit) const {
	int64_t depth = foot_depth(x0, x1, y);
	int64_t more = depth;
	while (more > 0 && depth <= limit) {
		more = foot_depth(x0, x1, y - depth);
		depth += more;
	}
	return depth;
}

bool Sweep::ride_fits(const Body &b, int64_t rise_by) const {
	if (clear_up(b.left(), b.right(), b.top(), rise_by) < rise_by) {
		return false;
	}
	return !region_blocked(b.left(), b.right(), b.top() - rise_by, b.y - rise_by - b.half_w);
}

int64_t Sweep::foot_depth(int64_t x0, int64_t x1, int64_t y) const {
	const int64_t lo = mini(x0, x1);
	const int64_t hi = maxi(x0, x1);
	int64_t depth = 0;
	const int64_t j = cell(y - 1);
	const int64_t c_last = cell(hi);
	for (int64_t c = cell(lo); c <= c_last; c++) {
		const int64_t t = get_tile(c, j);
		if (is_wall(t)) {
			depth = maxi(depth, y - wall_top(c, j));
		} else if (is_slope(t)) {
			const int64_t xa = maxi(lo, c * TILE_SP);
			const int64_t xb = mini(hi, (c + 1) * TILE_SP - 1);
			const int64_t s = mini(slope_surface(t, c, j, xa), slope_surface(t, c, j, xb));
			depth = maxi(depth, y - s);
		}
	}
	return depth;
}

int64_t Sweep::wall_top(int64_t c, int64_t j) const {
	int64_t k = j;
	while (k > j - 3 && is_wall(get_tile(c, k - 1))) {
		k -= 1;
	}
	return k * TILE_SP;
}

bool Sweep::try_lift(Body &b, int64_t dir, int64_t dist, int64_t allowed, int64_t max_lift) {
	const int64_t x0 = b.x;
	const int64_t y0 = b.y;
	const int64_t xs = x0 + dir * allowed;
	const int64_t l = xs - b.half_w;
	const int64_t r = xs + b.half_w;
	const int64_t top = y0 - b.height;
	const int64_t obstacle_top = wall_top_ahead(l, r, top, y0, dir);
	const int64_t lift = y0 - obstacle_top;
	if (lift <= 0 || lift > max_lift) {
		return false;
	}
	if (clear_up(l, r, top, lift) < lift) {
		return false;
	}
	const int64_t rest = dist - allowed;
	const int64_t after = sweep_x(l, r, top - lift, y0 - lift, dir, rest, b.half_w);
	if (after <= 0) {
		return false;
	}
	b.x = xs + dir * after;
	b.y = y0 - lift;
	settle_foot(b, xs, dir);
	if (after < rest || b.x != xs + dir * after) {
		b.hit_wall = dir;
	}
	b.nudge_y -= lift;
	refresh_ground(b);
	return true;
}

bool Sweep::try_duck(Body &b, int64_t dir, int64_t dist, int64_t allowed, int64_t max_duck) {
	const int64_t x0 = b.x;
	const int64_t y0 = b.y;
	const int64_t xs = x0 + dir * allowed;
	const int64_t l = xs - b.half_w;
	const int64_t r = xs + b.half_w;
	const int64_t top = y0 - b.height;
	const int64_t duck = lowest_ceiling_bottom(l + dir, r + dir, top, y0) - top;
	if (duck <= 0 || duck > max_duck) {
		return false;
	}
	b.x = xs;
	if (landing(b, y0, y0 + duck) != NONE || walls_overlap(l, r, y0, y0 + duck)) {
		b.x = x0;
		return false;
	}
	const int64_t rest = dist - allowed;
	const int64_t after = sweep_x(l, r, top + duck, y0 + duck, dir, rest, b.half_w);
	if (after <= 0) {
		b.x = x0;
		return false;
	}
	b.x = xs + dir * after;
	if (landing(b, y0, y0 + duck) != NONE || foot_depth(xs, b.x, y0 + duck) > 0) {
		b.x = x0;
		return false;
	}
	b.y = y0 + duck;
	b.nudge_y = duck;
	if (after < rest) {
		b.hit_wall = dir;
	}
	refresh_ground(b);
	return true;
}

// --- vertical ---------------------------------------------------------------------------------

int64_t Sweep::move_y(Body &b, int64_t dy, int64_t corner_sp) {
	if (dy == 0) {
		refresh_ground(b);
		return 0;
	}
	Narrowed narrowed(*this, b, absi(dy));
	return dy < 0 ? move_up(b, -dy, corner_sp) : move_down(b, dy);
}

int64_t Sweep::move_up(Body &b, int64_t dist, int64_t corner_sp) {
	int64_t allowed = clear_up(b.left(), b.right(), b.top(), dist);
	if (allowed < dist && corner_sp > 0) {
		int64_t shifts[2];
		const int n = ceiling_nudges(b, allowed, corner_sp, shifts);
		for (int i = 0; i < n; i++) {
			const int64_t shift = shifts[i];
			const int64_t after = clear_up(b.left() + shift, b.right() + shift, b.top(), dist);
			if (after > allowed && slide_fits(b, shift, after)) {
				b.x += shift;
				b.nudge_x = shift;
				allowed = after;
				break;
			}
		}
	}
	if (allowed < dist) {
		b.hit_ceiling = true;
	}
	if (allowed == 0) {
		// Under a flush ceiling the box has not left wherever it was: read that again.
		refresh_ground(b);
		return 0;
	}
	b.y -= allowed;
	b.on_ground = false;
	b.ground_tile = -1;
	b.on_slope = false;
	return -allowed;
}

int Sweep::ceiling_nudges(const Body &b, int64_t allowed, int64_t max_shift, int64_t out[2]) const {
	const int64_t t = b.top() - allowed - 1;
	const int64_t l = b.left();
	const int64_t r = b.right();
	const int64_t j = cell(t);
	int64_t lo = r;
	int64_t hi = l;
	const int64_t c_last = cell(r - 1);
	for (int64_t c = cell(l); c <= c_last; c++) {
		if (blocks_from_below(get_tile(c, j))) {
			lo = mini(lo, maxi(c * TILE_SP, l));
			hi = maxi(hi, mini((c + 1) * TILE_SP, r));
		}
	}
	for (const Box &s : boxes) {
		if (s.enabled && s.overlaps(l, r, t, t + 1)) {
			lo = mini(lo, maxi(s.left, l));
			hi = maxi(hi, mini(s.right, r));
		}
	}
	int n = 0;
	if (lo == l && hi - l <= max_shift) {
		out[n++] = hi - l;
	}
	if (hi == r && r - lo <= max_shift) {
		out[n++] = lo - r;
	}
	return n;
}

bool Sweep::slide_fits(const Body &b, int64_t shift, int64_t rise_by) {
	const int64_t x = b.x + shift;
	const int64_t y = b.y - rise_by;
	const int64_t hw = b.half_w;
	const int64_t top = y - b.height;
	const int64_t sl = shift > 0 ? b.right() : b.left() + shift;
	if (walls_overlap(sl, sl + absi(shift), top, b.y) || walls_overlap(x - hw, x + hw, top, y)) {
		return false;
	}
	if (region_blocked(x - hw, x + hw, top, y - hw)) {
		return false;
	}
	return floor_at(cell(x), x, x, y, y, y) != INSIDE;
}

int64_t Sweep::landing_contact(const Body &b, int64_t dx, int64_t dy, int64_t lift_sp, int64_t slide_sp) {
	if (dx == 0 || dy <= 0) {
		return NONE;
	}
	const int64_t x0 = b.x;
	const int64_t y0 = b.y;
	const int64_t floor_y = landing(b, y0, y0 + dy);
	if (floor_y == NONE || hit_slope) {
		return NONE;
	}
	int64_t contact = NONE;
	Body w = b;
	w.x = x0 + dx;
	const int64_t across = landing(w, y0, y0 + dy);
	if (across == NONE || across > floor_y) {
		const int64_t at = signi(dx) * div_floor(absi(dx) * (floor_y - y0), dy);
		w.x = x0 + at;
		const int64_t l = mini(x0, w.x) - w.half_w;
		const int64_t r = maxi(x0, w.x) + w.half_w;
		if (landing(w, floor_y, floor_y) == floor_y && !region_blocked(l, r, y0 - w.height, floor_y)) {
			contact = at;
		}
	}
	if (contact != NONE && plain_step_lands(b, dx, dy, lift_sp, slide_sp, floor_y)) {
		return NONE;
	}
	return contact;
}

bool Sweep::plain_step_lands(const Body &b, int64_t dx, int64_t dy, int64_t lift_sp, int64_t slide_sp, int64_t floor_y) {
	Body trial = b;
	trial.hit_ceiling = false;
	trial.hit_wall = 0;
	trial.nudge_x = 0;
	trial.nudge_y = 0;
	move_x(trial, dx, lift_sp, slide_sp);
	move_y(trial, dy, slide_sp);
	return trial.on_ground && trial.y <= floor_y;
}

int64_t Sweep::move_down(Body &b, int64_t dist) {
	const int64_t landing_y = landing(b, b.y, b.y + dist);
	if (landing_y != NONE) {
		const int64_t moved = landing_y - b.y;
		b.y = landing_y;
		set_ground(b, true);
		return moved;
	}
	b.y += dist;
	set_hit(-1, false, 0, 0);
	set_ground(b, false);
	return dist;
}

// --- grounded movement ------------------------------------------------------------------------

int64_t Sweep::walk(Body &b, int64_t dx, int64_t lift_sp) {
	if (dx == 0) {
		refresh_ground(b);
		return 0;
	}
	// Twice the distance: a walk that runs off a ledge carries on through the air from up to dx
	// away, and that move looks a further dx ahead.
	Narrowed narrowed(*this, b, 2 * absi(dx));
	return walk_raw(b, dx, lift_sp);
}

int64_t Sweep::walk_raw(Body &b, int64_t dx, int64_t lift_sp) {
	const int64_t dir = dx > 0 ? 1 : -1;
	int64_t remaining = absi(dx);
	const int64_t x_start = b.x;
	// Whether the last step stood on the floor under the centre (whose kind is then known).
	bool on_centre = false;
	int64_t st = -1;
	bool slope = false;
	while (remaining > 0) {
		const int64_t x0 = b.x;
		const int64_t y0 = b.y;
		const int64_t c = dir > 0 ? cell(x0) : cell(x0 - 1);
		const int64_t xs = dir > 0 ? x0 : x0 - 1;
		const int64_t to_edge = dir > 0 ? (c + 1) * TILE_SP - x0 : x0 - c * TILE_SP;
		int64_t seg = to_solid_edge(x0, dir, mini(remaining, to_edge));
		const int64_t entry = floor_at(c, x0, xs, y0, y0 + seg, y0);
		if (entry == INSIDE) {
			b.hit_wall = dir;
			on_centre = false;
			break;
		}
		slope = hit_slope;
		st = hit_tile;
		const int64_t sj = hit_j;
		int64_t airborne_after = -1;
		// Level: the floor under the centre drops away (or runs under a solid box's top the box
		// has come down onto), and the box carries on at its height while a flat floor there is
		// under it.
		bool level = entry != y0;
		if (level || hit_box) {
			seg = maxi(1, until_slope_rises(c, x0, y0, dir, seg));
		}
		int64_t x1 = x0 + dir * seg;
		int64_t y1 = y0;
		int64_t adv = seg;
		if (!level) {
			if (slope) {
				y1 = slope_surface(st, c, sj, x1);
			}
			adv = sweep_walk(b, dir, seg, y1 - y0);
			if (adv < seg && walk_onto_top) {
				if (adv > 0) {
					// Walking downhill onto a solid box's top: step down to it first.
					walk_to(b, x0 + dir * adv, c, st, sj, slope, y0);
					remaining -= absi(b.x - x0);
					continue;
				}
				level = true;
			}
		}
		on_centre = !level;
		if (level) {
			slope = false;
			const int64_t run = edge_run(b, dir, seg);
			if (run <= seg) {
				seg = run;
				airborne_after = run;
			}
			x1 = x0 + dir * seg;
			y1 = y0;
			adv = sweep_walk(b, dir, seg, 0);
		}
		if (adv < seg) {
			walk_to(b, x0 + dir * adv, c, st, sj, slope, y0);
			if (lift_sp > 0 && step_up(b, dir, lift_sp)) {
				remaining -= absi(b.x - x0);
				on_centre = false;
				continue;
			}
			b.hit_wall = dir;
			break;
		}
		b.x = x1;
		b.y = y1;
		remaining -= seg;
		if (airborne_after >= 0 && lift_sp > 0 && step_down(b, dir, lift_sp)) {
			// The floor dropped by no more than the lift: the box stays on the ground.
			on_centre = false;
			continue;
		}
		if (airborne_after >= 0) {
			b.on_ground = false;
			b.ground_tile = -1;
			b.on_slope = false;
			if (remaining > 0) {
				// The rest of the move is airborne. A fast walk can carry the box over a gap onto
				// the next ledge within the tick.
				move_x_raw(b, dir * remaining, 0, 0);
				refresh_ground(b);
			}
			return b.x - x_start;
		}
	}
	if (on_centre) {
		b.on_ground = true;
		b.ground_tile = st;
		b.on_slope = slope;
	} else {
		refresh_ground(b);
	}
	return b.x - x_start;
}

bool Sweep::step_up(Body &b, int64_t dir, int64_t max_lift) {
	const int64_t l = b.left();
	const int64_t r = b.right();
	const int64_t top = b.top();
	const int64_t y = b.y;
	const int64_t lift = y - wall_top_ahead(l, r, top, y, dir);
	const int64_t lead = dir > 0 ? r - 1 : l;
	const int64_t under = floor_at(cell(lead), lead, lead, y - b.half_w, y, y);
	const int64_t rise_v = (under != NONE && under != INSIDE) ? y - under : 0;
	if (lift <= 0 || lift > max_lift + rise_v || clear_up(l, r, top, lift) < lift) {
		return false;
	}
	if (sweep_x(l, r, top - lift, y - lift, dir, 1, b.half_w) <= 0) {
		return false;
	}
	b.y = y - lift;
	b.nudge_y -= lift;
	return true;
}

bool Sweep::step_down(Body &b, int64_t dir, int64_t max_drop) {
	const int64_t y = b.y;
	int64_t floor_y = landing(b, y, y + max_drop);
	if (floor_y == NONE) {
		// Any flat floor under the box within the drop was found above, so a floor under the
		// trailing edge within it is a slope's surface.
		const int64_t trail = dir > 0 ? b.left() : b.right() - 1;
		const int64_t under = floor_at(cell(trail), trail, trail, y, y + max_drop, y);
		if (under == NONE || under == INSIDE) {
			return false;
		}
		floor_y = landing(b, y, y + max_drop + b.half_w);
		if (floor_y == NONE) {
			return false;
		}
	}
	if (floor_y <= y) {
		return false;
	}
	b.y = floor_y;
	b.nudge_y += floor_y - y;
	set_ground(b, true);
	return true;
}

int64_t Sweep::until_slope_rises(int64_t c, int64_t x0, int64_t y0, int64_t dir, int64_t seg) const {
	const int64_t j = cell(y0 - 1);
	const int64_t t = get_tile(c, j);
	if (!is_slope(t) || slope_surface(t, c, j, x0 + dir * seg) >= y0) {
		return seg;
	}
	int64_t ok = 0;
	int64_t bad = seg;
	while (bad - ok > 1) {
		const int64_t mid = (ok + bad) / 2;
		if (slope_surface(t, c, j, x0 + dir * mid) >= y0) {
			ok = mid;
		} else {
			bad = mid;
		}
	}
	return ok;
}

void Sweep::walk_to(Body &b, int64_t x, int64_t c, int64_t t, int64_t j, bool slope, int64_t y0) const {
	b.x = x;
	b.y = slope ? slope_surface(t, c, j, x) : y0;
}

int64_t Sweep::to_solid_edge(int64_t x0, int64_t dir, int64_t seg) const {
	for (const Box &sb : boxes) {
		if (!sb.enabled) {
			continue;
		}
		int64_t d = (sb.left - x0) * dir;
		if (d > 0 && d < seg) {
			seg = d;
		}
		d = (sb.right - x0) * dir;
		if (d > 0 && d < seg) {
			seg = d;
		}
	}
	return seg;
}

int64_t Sweep::edge_run(const Body &b, int64_t dir, int64_t seg) {
	const int64_t y = b.y;
	const int64_t hw = b.half_w;
	const int64_t lo = b.x - hw - (dir < 0 ? seg : 0);
	const int64_t hi = b.x + hw + (dir > 0 ? seg : 0);
	// Pairs (first, last) of centre positions each span holds.
	held.clear();
	if (div_floor(y, TILE_SP) * TILE_SP == y) {
		const int64_t j = div_floor(y, TILE_SP);
		const int64_t c_last = cell(hi - 1);
		for (int64_t c = cell(lo); c <= c_last; c++) {
			const int64_t t = get_tile(c, j);
			if (is_wall(t) || t == T_ONE_WAY) {
				held.push_back(c * TILE_SP - hw + 1);
				held.push_back((c + 1) * TILE_SP + hw - 1);
			}
		}
	}
	for (const Box &sb : boxes) {
		if (sb.enabled && sb.top == y && sb.right > lo && sb.left < hi) {
			held.push_back(sb.left - hw + 1);
			held.push_back(sb.right + hw - 1);
		}
	}
	int64_t p = b.x + dir;
	const size_t n = held.size();
	while (absi(p - b.x) <= seg) {
		int64_t reach = p;
		for (size_t k = 0; k < n; k += 2) {
			if (held[k] <= p && p <= held[k + 1]) {
				reach = dir > 0 ? maxi(reach, held[k + 1] + 1) : mini(reach, held[k] - 1);
			}
		}
		if (reach == p) {
			return absi(p - b.x);
		}
		p = reach;
	}
	return seg + 1;
}

int64_t Sweep::sweep_walk(const Body &b, int64_t dir, int64_t seg, int64_t dy) {
	walk_onto_top = false;
	const int64_t l = b.left();
	const int64_t r = b.right();
	const int64_t t = b.top();
	if (dy == 0) {
		return sweep_x(l, r, t, b.y, dir, seg, b.half_w);
	}
	sw_l = l;
	sw_r = r;
	sw_t = t;
	sw_dir = dir;
	sw_seg = seg;
	sw_dy = dy;
	const int64_t foot_top = b.y - b.half_w;
	int64_t best = seg;
	const int64_t mx = dir * seg;
	const int64_t x_lo = mini(l, l + mx);
	const int64_t x_hi = maxi(r, r + mx);
	const int64_t y_lo = mini(t, t + dy);
	const int64_t y_hi = maxi(b.y, b.y + dy);
	const int64_t c_last = cell(x_hi - 1);
	const int64_t j_first = cell(y_lo);
	const int64_t j_last = cell(y_hi - 1);
	for (int64_t c = cell(x_lo); c <= c_last; c++) {
		const int64_t ol = c * TILE_SP;
		const int64_t o_r = ol + TILE_SP;
		const bool crest = dy < 0 || (ol < r && o_r > l);
		const int64_t bottom = crest ? foot_top : b.y;
		for (int64_t j = j_first; j <= j_last; j++) {
			if (is_wall(get_tile(c, j))) {
				const int64_t ot = j * TILE_SP;
				best = mini(best, swept_advance(bottom, ol, ot, o_r, ot + TILE_SP));
			}
		}
	}
	bool onto = false;
	for (const Box &sb : boxes) {
		if (!sb.enabled) {
			continue;
		}
		const int64_t adv = swept_advance(b.y, sb.left, sb.top, sb.right, sb.bottom);
		const bool top_contact = swept_by_y && dy > 0;
		if (adv < best) {
			best = adv;
			onto = top_contact;
		} else if (adv == best && !top_contact) {
			onto = false;
		}
	}
	walk_onto_top = onto && best < seg;
	return best;
}

int64_t Sweep::swept_advance(int64_t b, int64_t ol, int64_t ot, int64_t o_r, int64_t ob) {
	const int64_t l = sw_l;
	const int64_t r = sw_r;
	const int64_t t = sw_t;
	const int64_t seg = sw_seg;
	const int64_t dy = sw_dy;
	// The overlap is the open interval of a between the largest lower bound and the smallest
	// upper bound; each bound is a fraction n / d with d > 0.
	swept_by_y = false;
	int64_t lo_n = sw_dir > 0 ? (ol - r) : (l - o_r);
	int64_t lo_d = 1;
	int64_t hi_n = sw_dir > 0 ? (o_r - l) : (r - ol);
	int64_t hi_d = 1;
	const int64_t dn = absi(dy);
	// Bounds from the vertical extent, as fractions of seg.
	const int64_t y_lo = (dy < 0 ? (t - ob) : (ot - b)) * seg;
	const int64_t y_hi = (dy < 0 ? (b - ot) : (ob - t)) * seg;
	if (y_lo * lo_d >= lo_n * dn) {
		lo_n = y_lo;
		lo_d = dn;
		swept_by_y = true;
	}
	if (y_hi * hi_d < hi_n * dn) {
		hi_n = y_hi;
		hi_d = dn;
	}
	// No overlap at all, overlap only before a = 0 or already under way (lo < 0), or none within
	// this segment.
	if (hi_n * lo_d <= lo_n * hi_d || lo_n < 0 || lo_n >= seg * lo_d) {
		return seg;
	}
	return div_floor(lo_n, lo_d);
}

} // namespace wane
