# ADR-0007: Step each tick at the start of its period; snap vsync jitter and repay it

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 1 (GOTY bar: input-to-photon latency at most 2 frames; "unlocked to 240 on PC, with deterministic 60 Hz simulation"), 5 (feel rules: "acted on the same frame"), 13 ("Rendering interpolates between the last two simulation states for high refresh rates")
- Checklist lines: Graphics and feel, "No frame-time spike above 20 ms ..." (indirectly); Movement, every line (no added latency)

## Summary

- `SimDriver` steps a tick as soon as any of its 1/60 s has begun; views draw `lerp(previous, newest, alpha)` with alpha in (0, 1] (see Decision 1).
- Input is polled once per tick right before its step; catch-up frames poll per tick and never lose a latched press (see Decision 2).
- After 120 frames in a row within 0.6 ms of a whole tick count the driver locks to whole ticks and repays drift in whole ticks (see Decision 3).
- Unlocked frames are counted exactly and interpolated; over 6 misses in 60 unlocks; 30 vsync frames relock after a stutter (see Decision 4).
- After a hitch the driver steps at most 4 ticks in one frame and drops the remaining time (see Decision 5).
- The frame-stepper (paused driver) draws the newest state with alpha 1 (see Decision 6).
- Views keep the previous and newest state of what they interpolate; the contract is tested in `tests/unit/game/test_sim_driver.gd` (see Consequences).

## Context

The simulation runs at exactly 60 Hz; displays run at 60, 120, 144, 240 Hz or odd rates such as 59.94 or 62 Hz. The textbook fixed-step loop ("step while the accumulator holds a full tick, then draw lerp(previous, current, accumulator / tick)") always draws the previous tick at 60 Hz, adding a full frame (16.7 ms) of display latency to every input, which the GOTY bar's 2-frame latency budget cannot afford.

## Decision

1. `SimDriver` steps a tick as soon as any of its 1/60 s period has begun (`while accumulator > 0`), so the newest simulation state is never behind real time. Views draw `lerp(previous, newest, alpha)` with `alpha = 1 + accumulator / tick` in (0, 1]. At 60 Hz every frame steps once and draws the state it just produced (alpha 1). At 120 Hz frames alternate between stepping (alpha 0.5) and not stepping (alpha 1), so the drawn position always matches real time.
2. Input is polled once per tick, immediately before that tick's step; catch-up frames poll per tick and never lose a latched press.
3. **Locking to a fixed-refresh display.** A frame time within 0.6 ms of a whole number of ticks (one, or two to four after a hitch) looks like a vsync frame. After 120 such frames in a row (two seconds) the driver locks: each frame then counts as exactly a whole number of ticks, so a 60 Hz display with vsync jitter steps exactly once per frame, never 0 or 2 times, and draws the newest state (alpha 1). The time this rounds away is carried as drift and repaid only in whole ticks (one frame steps an extra time, or one fewer), never as a fraction, so a 59.94, 59, 61.5 or 62 Hz display runs at real speed with alpha 1 on every frame (unit-tested). While locked, a lone late, early or hitched frame counts as the nearest whole number of ticks, so it neither steps twice nor shifts later frames off the tick (unit-tested: one odd frame, then ten minutes of jittered 60 Hz).
4. **Unlocked, time is exact.** The decision is per display, not per frame: a variable-refresh display at 55 to 66 fps lands near a tick only by chance and never produces 120 such frames in a row, so it is never locked and every frame is counted exactly and drawn interpolated, without judder (unit-tested). A locked driver unlocks once more than 6 of the last 60 frames did not look like vsync frames (the window moved to a 144 Hz display, or a steady menu gave way to uncapped variable-refresh play); the drift it owed becomes ordinary owed time. A rate rather than a run, because variable-refresh frames land near a tick often enough to break up any run. The lock describes the display, so it survives the start of a new session, and when a burst of slow frames (a stutter: every miss within the last 10 frames of an otherwise clean window) unlocks it, 30 vsync-like frames (half a second) relock it, while scattered misses (jitter just past the window) need the full 120, so the driver does not flap; only the first two seconds after the game launches are drawn interpolated.
5. After a hitch the driver steps at most 4 ticks in one frame and then drops the remaining time (the game slows briefly rather than spiralling).
6. The frame-stepper (paused driver) draws the exact newest state (alpha 1).

## Alternatives considered

| Option | Why not |
| --- | --- |
| Classic accumulator, draw the previous state blended toward the current | One frame of latency at 60 Hz, on every input |
| Step from `_physics_process` at 60 ticks per second | Godot's physics tick is decoupled from vsync and would jitter against a 60 Hz display; CLAUDE.md forbids gameplay in `_physics_process` |
| No snapping | Vsync jitter makes some frames step twice and others not at all: visible judder at exactly the refresh rate the Deck and consoles lock to |
| Snap each frame that is near a tick | Tried; the third and fourth reviews found that one stray frame shifted the phase for good (a full frame of added latency) and that variable-refresh displays, whose frames are only sometimes near a tick, juddered by up to a tick on about one frame in six |

## Feel reason

The player's input appears on screen in the frame it was acted on. At high refresh rates motion stays smooth without lagging behind input.

## Consequences

Views must keep the previous and newest state of everything they interpolate. The interpolation contract is tested in `tests/unit/game/test_sim_driver.gd`.
