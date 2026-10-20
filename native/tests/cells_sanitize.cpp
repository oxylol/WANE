// Sanitiser run of the native query cells (docs/adr/0020 Decision 15): 4000 random crowds, each
// asked a few dozen questions of native/src/cells.cpp built with UBSan and ASan (no recovery),
// every answer checked against a brute force over the same centres. Self-checking: it prints OK or
// the first disagreement and exits non-zero. Not part of the library.
#include "cells.h"
#include <algorithm>
#include <cstdio>
using namespace wane;
static uint64_t st = 1181783497276652981ull;
static uint64_t rnd() { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; }
static int64_t below(int64_t n) { return (int64_t)(rnd() % (uint64_t)n); }
static int64_t between(int64_t a, int64_t b) { return a + below(b - a + 1); }
int main() {
	for (int round = 0; round < 4000; round++) {
		const int64_t n = below(4) == 0 ? below(3) : below(220);
		static const int64_t spreads[3] = {30, 150, 4000};
		const int64_t spread = spreads[round % 3] * 256;
		std::vector<int32_t> c(static_cast<size_t>(2 * n));
		std::vector<uint8_t> alive(static_cast<size_t>(n));
		for (int64_t k = 0; k < n; k++) {
			c[2 * k] = static_cast<int32_t>(between(-3000, spread));
			c[2 * k + 1] = static_cast<int32_t>(between(-3000, 900 * 256));
			if (k > 0 && below(8) == 0) {
				c[2 * k] = c[0];
				c[2 * k + 1] = c[1];
			}
			alive[k] = below(5) == 0 ? 0 : 1;
		}
		const int64_t rx = between(0, 16 * 256);
		const int64_t ry = between(0, 64 * 256);
		Cells cells;
		cells.build(c.data(), alive.data(), n, rx, ry);
		for (int q = 0; q < 40; q++) {
			if (n > 0 && q % 10 == 9) {
				const int64_t d = below(n);
				cells.kill(d);
				alive[d] = 0;
			}
			const int64_t x = between(-5000, spread + 5000);
			const int64_t y = between(-5000, 900 * 256 + 5000);
			const int64_t radius = between(0, 300 * 256);
			const int64_t skip = between(-1, n);
			std::vector<int32_t> want;
			int64_t best = -1;
			int64_t best_d = 0;
			for (int64_t k = 0; k < n; k++) {
				const int64_t dx = c[2 * k] - x;
				const int64_t dy = c[2 * k + 1] - y;
				const int64_t dd = dx * dx + dy * dy;
				if (k != skip && alive[k] != 0 && dd <= radius * radius) {
					want.push_back(static_cast<int32_t>(k));
					if (best < 0 || dd < best_d) {
						best = k;
						best_d = dd;
					}
				}
			}
			std::vector<int32_t> got;
			cells.within(x, y, radius, skip, got);
			if (got != want || cells.nearest(x, y, radius, skip) != best) {
				std::printf("within/nearest disagree: round %d query %d\n", round, q);
				return 1;
			}
			const int64_t w = between(1, 200 * 256);
			const int64_t h = between(1, 120 * 256);
			std::vector<int32_t> touch_want;
			for (int64_t k = 0; k < n; k++) {
				if (c[2 * k] >= x - rx && c[2 * k] <= x + w + rx && c[2 * k + 1] >= y - ry && c[2 * k + 1] <= y + h + ry) {
					touch_want.push_back(static_cast<int32_t>(k));
				}
			}
			std::vector<int32_t> touch_got;
			cells.touching(x, x + w, y, y + h, touch_got);
			if (touch_got != touch_want) {
				std::printf("touching disagrees: round %d query %d\n", round, q);
				return 1;
			}
		}
	}
	std::printf("OK\n");
	return 0;
}
