#include "cells.h"

#include <algorithm>

namespace wane {

namespace {

int64_t floor_div(int64_t a, int64_t b) {
	int64_t q = a / b;
	if ((a % b != 0) && ((a < 0) != (b < 0))) {
		q -= 1;
	}
	return q;
}

} // namespace

void Cells::build(const int32_t *c, const uint8_t *a, int64_t count, int64_t rx, int64_t ry) {
	n = count;
	reach_x = rx;
	reach_y = ry;
	centres.assign(c, c + 2 * n);
	alive.assign(a, a + n);
	next.assign(static_cast<size_t>(n), -1);
	if (n == 0) {
		cols = 0;
		rows = 0;
		heads.clear();
		return;
	}
	int64_t lo_x = 0x7FFFFFFF;
	int64_t lo_y = 0x7FFFFFFF;
	int64_t hi_x = -0x7FFFFFFF;
	int64_t hi_y = -0x7FFFFFFF;
	for (int64_t k = 0; k < n; k++) {
		const int64_t cx = centres[2 * k];
		const int64_t cy = centres[2 * k + 1];
		lo_x = std::min(lo_x, cx);
		hi_x = std::max(hi_x, cx);
		lo_y = std::min(lo_y, cy);
		hi_y = std::max(hi_y, cy);
	}
	x0 = floor_div(lo_x, CELL_SP);
	y0 = floor_div(lo_y, CELL_SP);
	cols = floor_div(hi_x, CELL_SP) - x0 + 1;
	rows = floor_div(hi_y, CELL_SP) - y0 + 1;
	heads.assign(static_cast<size_t>(cols * rows), -1);
	const int64_t ox = x0 * CELL_SP;
	const int64_t oy = y0 * CELL_SP;
	for (int64_t k = 0; k < n; k++) {
		const int64_t cell = (centres[2 * k] - ox) / CELL_SP * rows + (centres[2 * k + 1] - oy) / CELL_SP;
		next[static_cast<size_t>(k)] = heads[static_cast<size_t>(cell)];
		heads[static_cast<size_t>(cell)] = static_cast<int32_t>(k);
	}
}

void Cells::kill(int64_t k) {
	if (k >= 0 && k < n) {
		alive[static_cast<size_t>(k)] = 0;
	}
}

void Cells::within(int64_t x, int64_t y, int64_t radius, int64_t skip, std::vector<int32_t> &out) const {
	out.clear();
	if (cols == 0) {
		return;
	}
	const int64_t r2 = radius * radius;
	const int64_t cx0 = std::max(floor_div(x - radius, CELL_SP) - x0, int64_t(0));
	const int64_t cx1 = std::min(floor_div(x + radius, CELL_SP) - x0, cols - 1);
	const int64_t cy0 = std::max(floor_div(y - radius, CELL_SP) - y0, int64_t(0));
	const int64_t cy1 = std::min(floor_div(y + radius, CELL_SP) - y0, rows - 1);
	for (int64_t cx = cx0; cx <= cx1; cx++) {
		for (int64_t cy = cy0; cy <= cy1; cy++) {
			for (int32_t k = heads[static_cast<size_t>(cx * rows + cy)]; k >= 0; k = next[static_cast<size_t>(k)]) {
				const int64_t dx = centres[2 * k] - x;
				const int64_t dy = centres[2 * k + 1] - y;
				if (dx * dx + dy * dy <= r2 && k != skip && alive[static_cast<size_t>(k)] != 0) {
					out.push_back(k);
				}
			}
		}
	}
	std::sort(out.begin(), out.end());
}

int64_t Cells::nearest(int64_t x, int64_t y, int64_t radius, int64_t skip) const {
	if (cols == 0) {
		return -1;
	}
	const int64_t r2 = radius * radius;
	const int64_t cx0 = std::max(floor_div(x - radius, CELL_SP) - x0, int64_t(0));
	const int64_t cx1 = std::min(floor_div(x + radius, CELL_SP) - x0, cols - 1);
	const int64_t cy0 = std::max(floor_div(y - radius, CELL_SP) - y0, int64_t(0));
	const int64_t cy1 = std::min(floor_div(y + radius, CELL_SP) - y0, rows - 1);
	int64_t best = -1;
	int64_t best_d = 0;
	for (int64_t cx = cx0; cx <= cx1; cx++) {
		for (int64_t cy = cy0; cy <= cy1; cy++) {
			for (int32_t k = heads[static_cast<size_t>(cx * rows + cy)]; k >= 0; k = next[static_cast<size_t>(k)]) {
				const int64_t dx = centres[2 * k] - x;
				const int64_t dy = centres[2 * k + 1] - y;
				const int64_t dd = dx * dx + dy * dy;
				if (dd <= r2 && k != skip && alive[static_cast<size_t>(k)] != 0 && (best < 0 || dd < best_d || (dd == best_d && k < best))) {
					best = k;
					best_d = dd;
				}
			}
		}
	}
	return best;
}

void Cells::touching(int64_t l, int64_t r, int64_t t, int64_t b, std::vector<int32_t> &out) const {
	out.clear();
	if (cols == 0) {
		return;
	}
	l -= reach_x;
	r += reach_x;
	t -= reach_y;
	b += reach_y;
	const int64_t cx0 = std::max(floor_div(l, CELL_SP) - x0, int64_t(0));
	const int64_t cx1 = std::min(floor_div(r, CELL_SP) - x0, cols - 1);
	const int64_t cy0 = std::max(floor_div(t, CELL_SP) - y0, int64_t(0));
	const int64_t cy1 = std::min(floor_div(b, CELL_SP) - y0, rows - 1);
	for (int64_t cx = cx0; cx <= cx1; cx++) {
		for (int64_t cy = cy0; cy <= cy1; cy++) {
			for (int32_t k = heads[static_cast<size_t>(cx * rows + cy)]; k >= 0; k = next[static_cast<size_t>(k)]) {
				const int64_t x = centres[2 * k];
				const int64_t y = centres[2 * k + 1];
				if (x >= l && x <= r && y >= t && y <= b) {
					out.push_back(k);
				}
			}
		}
	}
	std::sort(out.begin(), out.end());
}

} // namespace wane
