# 2026-10-20: Camera glide jolt (a bounce during a teleport's glide)

- Author: Claude
- BUILD.md section and table row: section 5 ("The camera never fights the player"), section 15 ("never within 80 units of the screen edge")
- Fixture(s): `tests/replay/zone1/04_bypass_toss_wait.fixture` (moved up from `bypass/`; now in the camera sweep), `tests/unit/game/test_camera_review_round8.gd`
- Contact sheet: `docs/feel_log/2026-10-20-camera-glide-jolt.png` (ticks 236 to 258 every 2, 1920x1080 view, camera overlay on, the bounce at tick 247; at sheet scale the ring is small, the numbers below are the measure: Ash rises through the frame steadily across the bounce, with no kick)

## Change

No tuned number in `content/camera.tres` changed. One rule fixed in `game/camera/camera_rig.gd`: through a glide, the view's speed (follow plus glide) now changes by at most `glide_accel_milli_u` (5 u a tick) given the follow's own change that tick. The glide leaves the smootherstep for its catching mode on the first tick the smootherstep's rate would break that bound, and the catching mode's speed bounds are the same exact bound.

| Measure | Before | After | Unit |
| --- | --- | --- | --- |
| View speed change at the bounce 13 ticks into the glide, 1920x1440 (tick 247) | 13.67 (-11.76 to -25.43) | 5.00 (-11.76 to -16.76) | u/f |
| Same at 16:9, 16:10, 21:9 | 15.55 | at most 5.00 | u/f |
| Worst change over the fixture's four glides, 1920x1440 | 15.99 | at most 5.00 | u/f |
| Fastest view speed through the bounce | 25.43 | 21.76 | u/f |

## Why

The follow turns with the player at once (a bounce, a cling, an up-dash out of a fall: ADR-0011, Never outrunning the player): +12.95 to -1.41 here. The glide's offset kept the smootherstep's rate, so the two changes added to 14 u in one tick. The old catching branch spent only `5 - |follow change|` and could not give back more than it had.

## How it plays now

A pogo bounce in the middle of an Ember Toss glide no longer kicks the view; the glide gives back what the follow's turn adds and finishes a little early. A glide whose follow never turns is unchanged.

## Open questions for the director

Toss up room 4's post column and bounce on the next post at once: the view should ease up with Ash, with no kick.
