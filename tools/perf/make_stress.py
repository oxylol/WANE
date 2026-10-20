#!/usr/bin/env python3
"""Writes the stress room and its scripted run (docs/adr/0020).

    python3 tools/perf/make_stress.py

Writes tests/perf/rooms/stress.room, tests/perf/stress_run.fixture (the full run the bench plays)
and tests/replay/perf/stress_pin.fixture (its first ticks, blessed with the fixture suite). The
files are the source of truth; this script is how they were made. It is seeded, so running it
again changes nothing. The expectations of the two fixtures are written by hand after measuring and
are kept when the script runs again.
"""
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
W, H = 128, 30  # tiles
B = 26  # row of the base floor's top
TILE = 32
RUN_TICKS = 3840
PIN_TICKS = 60
INPUT_SEED = 1
LEG = 330  # ticks of a pass in one direction

# The ground: (kind, size). A ramp's size is its height in tiles (a 1:2 ramp is two columns a tile).
PROFILE = [
    ("flat", 8), ("up45", 3), ("flat", 8), ("dn45", 3), ("flat", 6), ("up12", 2), ("flat", 6),
    ("dn12", 2), ("flat", 8), ("up45", 4), ("flat", 5), ("dn45", 4), ("flat", 6), ("up12", 3),
    ("flat", 4), ("dn12", 3), ("flat", 6), ("up45", 2), ("flat", 4), ("dn45", 2),
]
COLUMNS = {"flat": 1, "up45": 1, "dn45": 1, "up12": 2, "dn12": 2}
# One-way platforms of the two tiers: (first column, last column).
TIER1_ROW, TIER2_ROW = B - 6, B - 11
TIER1 = [(4, 11), (15, 24), (29, 36), (41, 52), (57, 64), (69, 80), (85, 93), (98, 107), (112, 122)]
TIER2 = [(8, 17), (24, 31), (38, 49), (55, 63), (72, 83), (90, 99), (105, 116)]
CURBS = [30, 47, 66, 79, 103, 118]  # columns of the 8 u curbs
HUNG = [6, 20, 34, 50, 62, 76, 88, 101, 110, 120]  # columns of the hung boxes
HUNG_ROW = B - 9


def terrain():
    rows = [["."] * W for _ in range(H)]
    height = [0] * W
    slope = {}
    used = sum(COLUMNS[k] * n for k, n in PROFILE)
    c, h = 1, 0
    for kind, n in PROFILE + [("flat", W - 2 - used)]:
        for _ in range(n):
            if kind == "flat":
                height[c] = h
                c += 1
            elif kind == "up45":
                height[c] = h
                slope[c] = "/"
                h += 1
                c += 1
            elif kind == "dn45":
                h -= 1
                height[c] = h
                slope[c] = "\\"
                c += 1
            elif kind == "up12":
                height[c] = height[c + 1] = h
                slope[c], slope[c + 1] = "a", "b"
                h += 1
                c += 2
            else:
                h -= 1
                height[c] = height[c + 1] = h
                slope[c], slope[c + 1] = "c", "d"
                c += 2
    assert c == W - 1 and h == 0, (c, h)
    for col in range(W):
        top = B - height[col] if 0 < col < W - 1 else 0
        for r in range(top, H):
            rows[r][col] = "#"
        if col in slope:
            rows[top - 1][col] = slope[col]
    for col in range(W):
        rows[0][col] = "#"
    for row, spans in ((TIER1_ROW, TIER1), (TIER2_ROW, TIER2)):
        for a, b in spans:
            for col in range(a, b + 1):
                rows[row][col] = "="
    return rows, height, slope


def ground_y(col, dx, height, slope):
    """The ground's height in units at [dx] u into column [col]: the slope's surface on a ramp."""
    base = (B - height[col]) * TILE
    f = dx / TILE
    rise = {"/": f, "\\": 1 - f, "a": f / 2, "b": 0.5 + f / 2, "c": 1 - f / 2, "d": 0.5 - f / 2}
    return base - round(TILE * rise.get(slope.get(col), 0))


def main():
    rng = random.Random(20261019)
    rows, height, slope = terrain()
    lines = [
        "room perf/stress",
        "# The stress room (BUILD.md s13: \"200 enemies, 40 procs, Pitch lighting\"; docs/adr/0020).",
        "# 200 training dummies over a ground of flats, 45-degree and 1:2 ramps, two tiers of one-way",
        "# platforms, curbs and hung solid boxes; 150 of them walk (turn at walls and ledges, or",
        "# fall), 60 swing, white and red. Written by tools/perf/make_stress.py.",
        f"size {W} {H}",
        f"spawn 100 {B * TILE}",
        "tiles",
    ]
    lines += ["".join(r) for r in rows]
    lines.append("end")
    # Curbs 8 u tall on the floor (a wall to a walking dummy, a step to Ash) and boxes hung
    # between the tiers.
    curb_cols = []
    for want in CURBS:
        col = min((c for c in range(2, W - 4) if len(set(height[c - 1:c + 3])) == 1
                  and not any(k in slope for k in range(c - 1, c + 3))),
                  key=lambda c: abs(c - want))
        curb_cols.append(col)
        top = (B - height[col]) * TILE
        lines.append(f"solid {col * TILE} {top - 8} {col * TILE + 64} {top}")
    for col in HUNG:
        top = HUNG_ROW * TILE
        lines.append(f"solid {col * TILE} {top} {col * TILE + 128} {top + 16}")
    entities = []

    def add(x, y, patrol, fall, attack, face):
        props = []
        if patrol:
            props.append("patrol=1")
        if fall:
            props.append("fall=1")
        if attack:
            props.append(f"attack=1 period={rng.randrange(50, 131)}")
            if attack == 2:
                props.append("red=1")
        props.append(f"facing={face}")
        entities.append(f"entity dummy {x} {y} " + " ".join(props))

    def pick_attack():
        r = rng.random()
        return 0 if r < 0.7 else (1 if r < 0.9 else 2)

    # 100 on the ground (70 walkers), 50 on the lower tier (40 walkers, 10 of them falling), 30 on
    # the upper tier (24 walkers, 6 falling), 20 on the hung boxes (16 walkers, 6 falling).
    for i in range(100):
        while True:
            col = min(2 + (i * 125) // 100 + rng.randrange(0, 2), W - 3)
            if not any(c - 1 <= col <= c + 2 for c in curb_cols):
                break
            i += 1
        x = col * TILE + 4 + rng.randrange(0, 24)
        add(x, ground_y(col, x - col * TILE, height, slope) - 3,
            i % 10 < 7, False, pick_attack(), 1 - 2 * (i % 2))
    for tier, row, count, walkers, fallers in ((TIER1, TIER1_ROW, 50, 40, 10),
                                               (TIER2, TIER2_ROW, 30, 24, 6)):
        for i in range(count):
            a, b = tier[i % len(tier)]
            x = a * TILE + 24 + rng.randrange(0, (b - a + 1) * TILE - 48)
            walk = i < walkers
            add(x, row * TILE - 4, walk, walk and i % (walkers // fallers) == 0, pick_attack(),
                1 - 2 * (i % 2))
    for i in range(20):
        col = HUNG[i % len(HUNG)]
        add(col * TILE + 24 + rng.randrange(0, 80), HUNG_ROW * TILE - 4, i < 16,
            i < 16 and i % 3 == 0, pick_attack(), 1 - 2 * (i % 2))
    assert len(entities) == 200
    lines += entities
    (ROOT / "tests/perf/rooms/stress.room").write_text("\n".join(lines) + "\n")
    # python3 tools/perf/make_stress.py [input seed [output path]]: another seed's run, for trying.
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else INPUT_SEED
    inputs = ash_inputs(random.Random(seed))
    if len(sys.argv) > 2:
        write_fixture(Path(sys.argv[2]), RUN_TICKS, inputs, False)
        return
    write_fixture(ROOT / "tests/perf/stress_run.fixture", RUN_TICKS, inputs, False)
    write_fixture(ROOT / "tests/replay/perf/stress_pin.fixture", PIN_TICKS, inputs, True)


def ash_inputs(rng):
    """Per-tick token sets: Ash sweeps the room in passes of LEG ticks, east then west, striking,
    dashing, hopping onto a down-strike pogo, casting and striking up, in seeded random order."""
    ticks = [set() for _ in range(RUN_TICKS)]

    def put(t, *tokens):
        if t < RUN_TICKS:
            ticks[t].update(tokens)

    t = 0
    while t < RUN_TICKS:
        macro = rng.choices(["strike", "chain", "dash", "hop", "cast", "up"], [4, 3, 2, 2, 1, 1])[0]
        if macro == "strike":
            put(t, "attack")
            n = 14
        elif macro == "chain":
            for d in (0, 13, 26):
                put(t + d, "attack")
            n = 40
        elif macro == "dash":
            put(t, "dash")
            if rng.random() < 0.6:
                put(t + 6, "attack")
            n = 24
        elif macro == "hop":
            for d in range(12):
                put(t + d, "jump")
            for d in range(18, 24):
                put(t + d, "D")
            put(t + 20, "attack")
            n = 46
        elif macro == "cast":
            put(t, "spell")
            n = 30
        else:
            for d in range(4):
                put(t + d, "U")
            put(t + 2, "attack")
            n = 22
        t += n
    for i in range(RUN_TICKS):
        if not ({"D", "U"} & ticks[i]):
            ticks[i].add("R" if (i // LEG) % 2 == 0 else "L")
    return ticks


def write_fixture(path, frames, ticks, pin):
    name = path.stem
    kept = []
    if path.exists():
        text = path.read_text().split("\nexpect\n")
        if len(text) == 2:
            kept = text[1].rstrip("\n").split("\n")[:-1]  # drop the closing end
    out = [
        f"fixture {name}",
        ("doc BUILD.md s13 Testing and CI, the stress room (200 enemies, 40 procs): the first "
         f"{frames} ticks of tests/perf/stress_run.fixture, in the fixture suite so that the "
         "scenario stays loadable and bit-exact (docs/adr/0020)."
         if pin else
         "doc BUILD.md s13 Testing and CI, \"a stress room (200 enemies, 40 procs, Pitch "
         f"lighting)\": Ash sweeps perf/stress for {frames} ticks, striking, dashing, pogoing and "
         "casting, with the stress Votive set stacked (39 procs a Taper hit). Played and timed by "
         "tools/bench/stress_bench.gd; the pin of its first ticks is "
         "tests/replay/perf/stress_pin.fixture (docs/adr/0020)."),
        "seed 1", "room perf/stress", "wick ash",
        "option votive_test_stress_arc_a 1", "option votive_test_stress_arc_b 1",
        "option votive_test_stress_arc_c 1", "option kindle 1",
        f"frames {frames}", "input",
    ]
    i = 0
    while i < frames:
        j = i
        while j + 1 < frames and ticks[j + 1] == ticks[i]:
            j += 1
        toks = sorted(ticks[i], key=lambda s: (s not in ("L", "R", "U", "D"), s))
        if toks:
            span = f"{i}..{j}" if j > i else f"{i}"
            out.append(f"  {span} " + " ".join(toks))
        i = j + 1
    out += ["end", "expect"] + kept + ["end"]
    path.write_text("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
