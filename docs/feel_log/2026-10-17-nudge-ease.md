# 2026-10-17: Corner-correction ease, 6 frames to 3

(The ease's rule for runs of nudges changed on 2026-10-19: see [corner-correction ease on runs](2026-10-19-nudge-ease-runs.md). This entry and its sheet record the 3-frame tuning with the earlier rule.)

- Author: Claude
- BUILD.md section and table row:
  - section 5, Ground, "Corner correction: Horizontal: 8 u nudge over ledge corners; vertical: 6 u nudge around ceiling corners";
  - section 15, Movement: "Landing on a 1-pixel ledge edge lands; the corner-correction nudge is invisible".
- Fixture(s):
  - `tests/replay/physics/walk_up_ramp45_onto_door_at_crest.fixture`: an 11 u lift onto a door at a ramp's crest, frame 17;
  - `tests/replay/physics/walk_steps_down_small_lips.fixture`: an 8 u step down, frame 19;
  - `tests/replay/movement/jump_ceiling_nudge.fixture`: a 4 u slide round a ceiling corner, frame 6;
  - `tests/replay/physics/dash_up_lip_stairs.fixture` and `walk_up_lip_stairs.fixture`: staircases of 8 u lips, up to three lips in a tick (task 5 review, H3);
  - `tests/unit/game/test_views.gd`, `test_a_corner_correction_nudge_never_snaps_the_drawn_player`, over ten fixtures.
- Contact sheet: `docs/feel_log/2026-10-17-nudge-ease.png`, filmed by `tools/replay/film.gd` with the F3 overlay on and the world zoomed 4 times around Ash, every frame.
  - The white outline is the collider, where the simulation has Ash.
  - The fill is the drawn player: blue on the ground, yellow in the air, magenta dashing.
  - Rows:
    1. the ramp crest at 1 frame: the drawn player lags one frame, then snaps 11 u;
    2. the ramp crest at 6 frames;
    3. the ramp crest at 3 frames;
    4. the step down at 6 frames;
    5. the step down at 3 frames;
    6. the ceiling corner at 6 frames;
    7. the ceiling corner at 3 frames;
    8. a ground dash up the 45-degree staircase of lips at 3 frames, frames 60 to 69.

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `nudge_ease_frames` (`content/player_view.tres`) | 6 (first value, never committed) | 3 | frames |

The number is new. Neither BUILD.md nor an earlier task had it. BUILD.md section 5's corner-correction row now names it.

## Why

The simulation moves the collider by the whole nudge in one tick, up to 18 u. Drawn as it is, that is a visible hop: the checklist line asks for the nudge to be invisible. So the view draws Ash where the collider would have been without the nudge, and moves the drawn player onto the collider over `nudge_ease_frames`.

- **1 frame is not an ease.** It is the snap one frame late (row 1).
- **6 frames hides the hop but shows a sink.**
  - On the ramp crest the drawn feet stay inside the door for five frames, 11 u deep at first (row 2).
  - Stepping down a lip, Ash hovers 8 u over the floor for five frames (row 4).
  - Five frames (83 ms) is long enough to read as a pose: Ash sinking into the floor, or floating.
  - The catch-up is slow: at most 0.24 of the nudge a frame, the smoothstep's largest step over six frames.
- **3 frames does both jobs.**
  - The feet are inside the door for three frames, 11, 8 and 3 u deep (row 3).
  - Ash floats over the lower floor for three frames, 8, 6 and 2 u (row 5).
  - The largest catch-up step after a single nudge is 0.48 of the nudge in a frame: 5.3 u for the crest's 11 u, and 8.7 u for the largest nudge, 18 u. That is under Ash's run speed (9 u a frame), motion the eye already accepts on every ramp.
  - The ceiling corner (rows 6 and 7) is a 4 u slide sideways; the drawn head overlaps the block by up to 4, 3 and 1 u for three frames. It reads as the slide, not as a clip.

**Runs of nudges** (first review of task 5, H3). The first version restarted a smoothstep from rest at every nudge. A run of them, a lip every tick up a staircase, stalled the drawn player at each one, and it fell ever further behind: 64 u behind on a dash up a 45-degree stair, its whole body inside the stairs, then a 31 u hop to catch up. Two changes fix it:
- A nudge that arrives while an ease runs starts a new cubic from the speed the drawn player already has (a Hermite cubic; from rest it is the same smoothstep), so it keeps rising instead of stalling.
- The offset never exceeds the largest single nudge of the run on either axis.

Up the 16 u staircase at a walk, the drawn player rises 2 to 8 u every frame where the collider rises 8 u every other frame, and is never more than 16 u behind.

Up the 45-degree stair in a dash (row 8), frames 61 to 67:
- the collider rises 8, 24, 16, 24, 8, 0 and 0 u;
- the drawn player rises 0, 8, 16, 24, 11, 10 and 8 u, never more than 24 u (the largest nudge, three lips at once) behind.

That is smoother than the collider, but not smooth. On frame 64 the cap makes the drawn player rise the whole 24 u with it. The drawn feet are inside the stairs, up to 24 u, for those frames of a dash.

## How it plays now

- The drawn player never lags the collider by more than the largest nudge of the run, and meets it three frames after the last nudge.
- A nudge from rest moves the drawn player on its tick only as it was moving anyway.
- After a single nudge, the catch-up is at most 0.625 of it beyond the collider's own motion in a frame. In a run of nudges it is at most one nudge.
- `test_a_corner_correction_nudge_never_snaps_the_drawn_player` checks each of these, across and down, on every frame of ten fixtures with nudges: six physics fixtures, the two staircases, the ceiling corner and the ground corner lift. Removing the cap, or the ease on either axis, fails it.
- The simulation does not change, so no hash moves. The F3 overlay draws the collider, not the drawn player, so the frame-stepper still shows the nudge on the tick it happened.

## Open questions for the director

- Once Ash is drawn (Phase 2 task 2), watch the ramp crest and the small lips at 1x. The walk cycle's own bob may hide an even shorter ease, or want a slightly longer one. It is one number in `content/player_view.tres`.
- The drawn feet sit inside a step for up to three frames while the ease runs, a whole lip deep on a dashed staircase. The animator can turn that into a step-up pose (the nudge is a known event).
