# 2026-10-17: Phase 1 task 5, the F3 overlay and the frame-stepper

- Author: Claude
- BUILD.md section and table row:
  - section 5: "A debug overlay (F3) shows hitboxes, state, frame counters and input history on every build, forever";
  - section 13, tooling: "the F3 debug overlay, a frame-stepper";
  - section 15: "Items are checked by playing, with the F3 overlay on"; Process, "The F3 overlay shows hitboxes, state, frame counter and input history in the build"; Movement, "the corner-correction nudge is invisible".
- Fixture(s) on the sheet: `tech01_dash_slash`, `tech03_pogo_chain`, `tech10_crouch_dash_under`, `tech11_ember_toss_cancel`, `physics/walk_up_ramp45_onto_door_at_crest`, `physics/walk_up_lip_stairs`.
- Tests:
  - `tests/unit/game/test_debug_boxes.gd`:
    - which boxes show on which frames;
    - the bounce mark;
    - the down-strike's one label;
    - every tech and physics fixture (over 40) played with the overlay reading boxes, text and history on every tick, its state hash equal to a plain run's.
  - `test_debug_overlay.gd`:
    - the keys and stepping;
    - no game binding on a debug key;
    - the text;
    - one press shown once through hitstop;
    - never changing the simulation.
  - `test_input_history.gd`:
    - runs, taps and re-presses;
    - the 8-way read;
    - a fixture read back as its script.
  - `test_views.gd`:
    - the main scene carries the overlay and the stepper;
    - the corner-correction ease, over ten fixtures, two of them staircases of lips.
- Contact sheet: `docs/feel_log/2026-10-17-task5-debug-overlay.png`.
  - Filmed by `tools/replay/film.gd --overlay on --zoom 3` through the game's own views and the overlay itself, frame by frame. This is CLAUDE.md working method step 5, "a frame-stepped contact sheet ... with the F3 overlay on" (docs/adr/0012 says why `film.gd` and not `play.gd`).
  - Each frame is half the screen, with the world magnified 3 times around Ash. The overlay's text stays where it is on the screen, at 9 px on the sheet; open the image at full size to read it.
  - The overlay's colours:
    - white: the collider;
    - green inside it: the hurtbox, with the word "invulnerable" above it while Ash is;
    - orange, filled: the strike box, with the strike's name ("down + pogo" when the down-strike's box is its pogo box);
    - yellow, filled: the pogo box;
    - white, filled, labelled "bounce": where a pogo hit, on the bounce's tick;
    - orange dot: the ember;
    - pale blue: solid boxes, with their tags;
    - red, filled: the part of a spike tile that hurts;
    - violet rectangle with a yellow dot: the camera's dead zone and focus.
  - The fill under the boxes is the drawn player, the grey box the game shows: blue on the ground, yellow in the air, magenta dashing.
  - Frames are numbered as fixtures number them: frame F is the state after input frame F. The overlay prints the same number.
  - Rows:
    1. Tech 1, the dash-slash, every other frame from frame 4: the invulnerable dash, side1's startup, its box, side2's startup, side2's box;
    2. Tech 3, the pogo chain over spikes, every frame from frame 51: a down-strike from its first frame to the bounce, its one box live from its frame 3, then the bounce mark;
    3. Tech 10, the crouch-dash under a low ceiling;
    4. Tech 11, the ember toss and its cancel: the ember flying, the teleport;
    5. walking up a 45-degree ramp onto a door at its crest, every frame: the collider steps up 11 u in one frame and the drawn player eases after it;
    6. walking up the 45-degree staircase of 8 u lips, every frame from frame 88: the collider climbs a lip or two at a time, and the drawn player rises steadily (see [corner-correction ease](2026-10-17-nudge-ease.md)).
  - Each row ends with the player's track on screen (`film.gd`'s header has the key).

## Change

First implementation. The overlay has no tunable numbers: its text size (18 px, BUILD.md section 12's minimum) is fixed. The presentation number this task added is `nudge_ease_frames`, tuned from 6 to 3 in its own entry: [corner-correction ease](2026-10-17-nudge-ease.md).

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `nudge_ease_frames` (`content/player_view.tres`) | none | 3 | frames |

## Why

The overlay is how every checklist line is judged, so it shows what the simulation resolved and nothing else.

- **The boxes are from the latest tick, never interpolated.** At 144 Hz they step once per tick while the drawn player glides between ticks. A box that looked overlapping between two ticks never was.
- **The stepper steps through the driver's own path** (`SimDriver.step_once`): F4 pauses, F5 steps one tick, F6 ten.
  - A press made while paused lands on the next step, as a press between two ticks does in play. Freezing the scene tree would have dropped it (docs/adr/0012).
  - Ten steps used to be Shift+F5. Shift is the keyboard's dash, so stepping ten ticks dashed 190 u (first review). The debug keys now take no modifier, and a test checks that no game binding uses one of them.
- **The input history shows the input each tick consumed, as the game read it.**
  - The stick reads in the eight sectors the dash and the toss use, in numpad notation (5 neutral, 6 right, 3 down-right).
  - A new press always starts a new run, so a re-press while held shows. A tap (pressed and let go within a tick) is a run of its own.
  - The history reads the frame the tick consumed, not the input ring. During hitstop the ring folds presses together, so a single tap would have shown on every frozen tick.
- **A bounce is marked.** The down-strike hands control back on the bounce's tick, so its box is already gone on the frame where the hit resolved; the overlay marks where it hit.

Filming the overlay at the camera sheet's scale (a quarter of the view) left Ash 10 px tall: the boxes could not be told apart. Hence `--zoom`. The world is magnified around Ash and the text stays on the screen. On row 1 the side1 box can now be read against the collider, frame by frame.

What the sheet shows was checked frame by frame against BUILD.md sections 5 and 6, the kit (`content/wicks/ash/`) and `tools/replay/trace.gd`.
- Row 1:
  - Frame 4 is dash frame 5, labelled invulnerable (frames 1 to 7 are).
  - The attack was pressed on dash frame 3. It waits in the buffer and cancels the dash into side1 on dash frame 6, frame 5 (BUILD.md section 5, "attack cancel from frame 6").
  - Frame 6 is side1's frame 2: no box (startup).
  - Frames 8 and 10 are its frames 4 and 6: the box shows, labelled side1 (active 3 to 6).
  - Frame 12 is side2's frame 2: no box.
  - Frame 14 is side2's frame 4: its box shows.
- Row 2:
  - The down-strike starts on frame 51.
  - Its box, labelled "down + pogo", shows from its frame 3 (frame 53) through its frame 6.
  - On frame 57 Ash bounces off the spikes, the strike ends, and the bounce mark shows where.
- Row 5: the collider steps 11 u up onto the crest's door in one frame (frame 17). The drawn player is below it by 11, 8.25 and 2.75 u on frames 17 to 19, and meets it on frame 20.
- Row 6: up the staircase the collider rises 8, 8, 16, 8 and 8 u on frames 90 to 94. The drawn player rises 0, 2, 4, 8 and 12 u, its speed changing by at most a quarter of the run's nudge a frame, and is at most 26 u behind (re-filmed with the ease's rule for runs: feel log 2026-10-19).

## How it plays now

- F3 shows or hides the overlay in any build. F4 pauses. F5 steps one tick, F6 ten.
- A press made while paused lands on the next step.
- The history is complete the moment F3 opens: it records while the overlay is hidden.
- The overlay never writes the simulation. Every tech and physics fixture plays to the same state hash with the overlay reading every tick.
- `film.gd --overlay on` films any fixture frame by frame through the same overlay, at any zoom, for every task's contact sheet from here on.

## Open questions for the director

- The debug keys are keyboard only, as BUILD.md's "F3" says: a pad-only device cannot open the overlay. A pad chord can be added if playtests on the Deck need it.
- For the nudge ease, see its own entry.
