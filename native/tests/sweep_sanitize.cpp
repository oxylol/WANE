// Sanitiser run of the native sweep core (ADR-0022): 3000 random rooms, 18,000 bodies, a million
// moves and queries through native/src/sweep.cpp built with UBSan and ASan (no recovery), so a signed
// overflow, an out-of-range read or a shift of a negative fails the build. The checksum it prints is
// a function of the sweep alone (a fixed xorshift stream, no platform input): ci/sanitize_native.sh
// compares it with the value below, so a change of behaviour shows here as well as in the replay
// hashes. Not part of the library.
#include "sweep.h"
#include <cstdio>
using namespace wane;
static uint64_t st = 88172645463325252ull;
static uint64_t rnd() { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; }
static int64_t below(int64_t n) { return (int64_t)(rnd() % (uint64_t)n); }
static int64_t between(int64_t a, int64_t b) { return a + below(b - a + 1); }
int main() {
	int64_t acc = 0;
	for (int room = 0; room < 3000; room++) {
		Sweep sw;
		int64_t W = 30, H = 14;
		std::vector<uint8_t> t(W * H, 0);
		for (int64_t j = 0; j < H; j++)
			for (int64_t i = 0; i < W; i++) {
				uint8_t k = (j >= 12 || i == 0 || i == W - 1 || j == 0) ? 1 : (uint8_t)below(12);
				if (k >= 4 && k <= 9 && below(2)) k = 0;
				t[j * W + i] = k;
			}
		sw.set_grid(W, H, t.data(), (int64_t)t.size());
		sw.set_spike_inset(below(31) * SUB);
		int64_t nb = below(8);
		sw.resize_boxes(nb);
		for (int64_t b = 0; b < nb; b++) {
			int64_t l = between(2, 40) * 32 * SUB + below(256);
			int64_t tp = between(2, 12) * 32 * SUB + below(256);
			sw.set_box(b, l, tp, l + between(1, 4) * 32 * SUB, tp + between(1, 3) * 16 * SUB, below(4) != 0, below(2));
		}
		for (int body = 0; body < 6; body++) {
			Body b;
			b.half_w = (below(3) == 0 ? 16 : 10) * SUB;
			b.height = between(20, 70) * SUB;
			b.x = between(1, 800) * SUB + below(256);
			b.y = between(1, 420) * SUB + below(256);
			for (int tick = 0; tick < 60; tick++) {
				b.hit_wall = 0; b.hit_ceiling = false; b.nudge_x = 0; b.nudge_y = 0;
				int64_t dx = (below(2) ? 1 : -1) * between(1, 40 * 256);
				int64_t dy = between(-12, 16) * SUB + below(256);
				int64_t lift = below(2) ? 8 * SUB : 0;
				switch (below(8)) {
					case 0: case 1: acc += sw.walk(b, dx, lift); break;
					case 2: acc += sw.move_x(b, dx, lift, 6 * SUB); break;
					case 3: acc += sw.move_y(b, dy, 6 * SUB); break;
					case 4: acc += sw.landing_contact(b, dx, between(1, 16) * SUB, lift, 6 * SUB) & 0xffff; break;
					case 5: sw.refresh_ground(b); break;
					case 6: acc += sw.drop_through(b); break;
					default: acc += sw.floor_top_in(b.x - 100, b.x + 100, b.y - 1000, b.y + 5000) & 0xff; acc += sw.wall_near(b, 1, 256, true); acc += sw.headroom(b, 70 * SUB); acc += sw.body_fits(b.x, b.y, b.half_w, b.height); acc += sw.point_solid(b.x, b.y); acc += sw.touches_hazard(b.x, b.x + 1000, b.y, b.y + 1000); break;
				}
				if (b.y > H * 32 * SUB || b.y < 0) { b.y = between(1, 400) * SUB; b.x = between(1, 800) * SUB; }
			}
		}
	}
	printf("%lld\n", (long long)acc);
	return 0;
}
