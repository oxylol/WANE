# 2026-10-19: Corner-correction ease on runs of nudges, the cap moved from the position to the speed

- Author: Claude
- BUILD.md section and table row:
  - section 5, Ground, "Corner correction" (the drawn player's ease, `content/player_view.tres`);
  - section 15, Movement: "the corner-correction nudge is invisible".
- Fixture(s):
  - `tests/replay/physics/walk_up_two_lips.fixture` (new): two 8 u lips 9 u apart, nudged on frames 12 and 13 (task 5 review 2, H1);
  - `tests/replay/physics/walk_up_lip_stairs.fixture`: a walked 1:2 staircase of 8 u lips (nudges every one or two frames) and a walked 45-degree one (a lip every frame);
  - `tests/replay/physics/dash_up_lip_stairs.fixture`: the same staircases dashed, up to three lips in a frame;
  - `tests/unit/game/test_views.gd`, `test_a_corner_correction_nudge_never_snaps_the_drawn_player` (eleven fixtures, both axes, followed 30 ticks past their end) and `test_the_ease_from_rest_is_a_triangle_of_speeds_over_its_frames`.
- Contact sheet: `docs/feel_log/2026-10-19-nudge-ease-runs.png`, filmed by `tools/replay/film.gd --overlay on --zoom 4`, every frame. Each scenario is two rows, the old ease above and the new below. The white outline is the collider; the fill is the drawn player.
  - Rows 1 and 2: the two lips, frames 11 to 18.
  - Rows 3 and 4: the walked 1:2 staircase, frames 13 to 24.
  - Rows 5 and 6: the dashed 45-degree staircase, frames 60 to 69.

## Change

The rule, not a number: the ease capped the gap between the drawn player and the collider at the run's largest nudge by moving the drawn player itself; it now limits how fast the drawn player's catch-up speed changes, and caps the gap only far out. The ease from rest keeps its tuned 3 frames.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| How much the catch-up speed may change in a frame | unlimited (the cap moved the drawn player by whatever was over it) | a quarter of the run's nudge (set by `nudge_ease_frames`, 3: from rest that eases a nudge along 1, 2 and 1 quarters of it) | of the nudge |
| `nudge_lag_percent` (`content/player_view.tres`, new) | 100 (the cap, in code) | 200 | % of the run's nudge |

## Why

The second review of task 5 measured the hop the cap made. A nudge arriving while the last one still eased took the gap over the cap, and the cap moved the drawn player by the excess in that same frame:
- the two lips: the drawn player rose 0, then the whole 8 u of the second lip in one frame, then 3.7, 3.1 and 1.3 u;
- the walked 1:2 staircase: rises of 4.3, 8.0, 3.7 u every few frames, a hitch on every pair of lips in a row (rows 1 and 3 of the sheet);
- the dashed staircase: rises of 8, 16 and 24 u, then 11, a jolt as it let go.

The feel log's own rejection of a 1-frame ease ("the snap one frame late") rules this out. Offline, the old ease and a dozen other rules (a speed cap, acceleration limits of three sizes, hard and soft caps on the gap) were run over every nudge of the 33 fixtures that have any (task notes in docs/adr/0012, Alternatives). Limiting the change of speed is the only one that never jolts: it keeps the drawn player's motion smooth through any run, and from rest it is the tuned ease (an 8 u lip: 2, 4 and 2 u; the 11 u crest: 2.75, 5.5 and 2.75 u, where the smoothstep gave 2.85, 5.3 and 2.85). What it costs is lag up a staircase: the drawn player cannot speed up faster than its limit, so it falls further behind than one lip before it catches up. The new cap, 200%, only stops a run the limit cannot follow at all; no fixture reaches past it.

## How it plays now

- The two lips: the drawn player rises 0, 2, 4, 5.3, 3.3 and 1.3 u (row 2), at most 14 u behind.
- The walked 1:2 staircase: a steady 3 to 6 u a frame (rises of 2.0, 4.0, 5.3, 3.3, 5.1, 6.1, 4.1, ...), at most 12 u behind (row 4).
- The walked 45-degree staircase (8 u a frame, one 16 u): 2, 4, 8 and 12 u, then easing down to the collider's 8 u, at most 26 u behind.
- The dashed staircase: 2, 8, 14, 20, 18, 12 and 6 u, meeting the collider three frames after the last lip (row 6). It falls 48 u behind on frame 64, a little more than Ash's height: for two frames the drawn body is inside the steps.
- A lone nudge from rest is unchanged in length: met exactly 3 frames later, the drawn player never moving on the nudge's own frame except as it was moving.

## Open questions for the director

- Look at rows 5 and 6: up a staircase of lips dashed three a frame, is two frames of the body inside the steps (the new ease) better than the old jolt as it let go? Lip staircases are a stress room (rooms climb with ramps), so the common case is rows 1 to 4, where the hitch is gone.
