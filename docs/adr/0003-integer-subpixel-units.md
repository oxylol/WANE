# ADR-0003: Integer sub-pixel positions, per-tick velocities, design units in content

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 5 (all tables), 13 (simulation core)
- Checklist lines: Run tension, "A seeded replay of a full run reproduces bit-for-bit on Windows, Linux and the Deck"

## Summary

- Core positions are `int` sub-pixels, 256 per unit (`Fx.SUB`); velocities are sub-pixels per tick, 60 ticks per second (`Fx.HZ`) (see Decision 1).
- Content resources store BUILD.md design units (u/s, u/s^2, frames, per-mille); `compile()` converts once at load via `Fx.speed`, `Fx.accel` (see Decision 2).
- Conversion rounds half away from zero; the error is under one sub-pixel per tick squared, 0.2% of gravity (see Decision 2).
- Integer division with a possibly negative operand goes through `Fx.div_floor` or `Fx.div_round`, never `/` (see Decision 3).
- 32-bit hash and RNG arithmetic uses `Fx.mul32`, which stays inside the signed 64-bit range (see Decision 4).
- CI fails if the word `float` or a float literal appears in `core/` (see Decision 5).

## Context

CLAUDE.md rule 2: "Positions and velocities in the core are integers in 1/256-unit sub-pixels. Floats exist only in game/." BUILD.md section 5 states numbers in frames and in units per second (u/s) and units per second squared (u/s^2), where 1 unit is one world pixel at the native 1920x1080 art scale. Some of those do not divide evenly into per-tick integers (2400 u/s^2 is 170.67 sub-pixels per tick squared).

## Decision

1. Positions are `int` sub-pixels, 256 per unit (`Fx.SUB`). Velocities are sub-pixels per tick; accelerations are sub-pixels per tick per tick. Ticks are 60 per second (`Fx.HZ`).
2. Content resources store numbers in BUILD.md's own design units (u/s, u/s^2, frames, units, percent, per-mille), as integers, so a designer reads the doc and the resource side by side. A schema's `compile()` converts them once at load with `Fx.speed`, `Fx.accel`, `Fx.per_tick` and `Fx.permille`, all integer and rounded half away from zero. The rounding error is under one sub-pixel per tick squared (0.2% of gravity).
3. Integer division in the core always goes through `Fx.div_floor` or `Fx.div_round` when either operand can be negative; GDScript's `/` truncates toward zero, which would make leftward and rightward motion asymmetric.
4. Any 32-bit hash or RNG arithmetic uses `Fx.mul32`, which never leaves the signed 64-bit range, so no platform's overflow behaviour is involved.
5. CI fails if the word `float` or a float literal appears in `core/` (tools/ci/run_tests.gd, compile stage).

## Alternatives considered

| Option | Why not |
| --- | --- |
| Velocities in sub-pixels per second | Every position update would divide by 60 and carry a remainder; more state to hash, no feel gain |
| A finer fixed point for accelerations (1/65536 unit) | Exact to the doc's u/s^2 values, but the doc's values are starting points to be tuned anyway; 0.2% is far below what a player can feel and the extra precision doubles the state |
| Floats in the core with careful ordering | Not reproducible across compilers, platforms and SIMD paths; violates CLAUDE.md rule 2 |

## Feel reason

Bit-identical replays are what make every movement tech a regression test. The integer core also makes "dash from standstill and at full run reach the same distance" exactly true rather than true within epsilon.

## Consequences

The helpers named here (`core/sim/fx.gd`) are built in Phase 1 task 1. Every tuning resource has a `compile()` step and a unit test that its compiled values match the doc's numbers. Rendering converts sub-pixels to float pixels only in `game/`.
