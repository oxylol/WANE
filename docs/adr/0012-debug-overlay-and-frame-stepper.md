# ADR-0012: Draw the F3 overlay from the latest tick, and step frames through the driver

- Status: Accepted
- Date: 2026-10-17
- BUILD.md sections:
  - 5: "A debug overlay (F3) shows hitboxes, state, frame counters and input history on every build, forever";
  - 13, tooling: "the F3 debug overlay, a frame-stepper";
  - 15: "Items are checked by playing, with the F3 overlay on";
  - 12: "no text under 18 px at 1080p".
- Checklist lines:
  - Process, "The F3 overlay shows hitboxes, state, frame counter and input history in the build";
  - Movement, "Landing on a 1-pixel ledge edge lands; the corner-correction nudge is invisible"

## Context

Every checklist line is checked with the F3 overlay on, and every contact sheet is filmed with it (CLAUDE.md working method, step 5). So the overlay must show exactly what the simulation resolved on a tick, and stepping must not change what happens.

BUILD.md leaves open:
- the keys;
- what "input history" looks like;
- whether boxes are interpolated like the views;
- how the overlay gets text onto the screen without importing a font (CLAUDE.md rule 10).

## Decision

**Keys** (`game/debug/debug_controls.gd`, keyboard only, on every build):
- F3 shows and hides the overlay.
- F4 pauses and resumes the simulation.
- While paused, F5 steps exactly one tick and F6 steps ten.
- No debug key takes a modifier, and no game binding uses one of them (a test checks the bindings). Ten steps were Shift+F5 until the first review: Shift is the keyboard's dash, and held through the ten steps it dashed 190 u.
- Stepping goes through `SimDriver.step_once`, the same path play uses. It polls the controller for that tick, records the tick in the replay, and fires the views' tick signal. A press made while paused is latched by the input layer and lands on the next step, exactly as a press between two ticks does in play.

**Boxes** (`game/debug/debug_boxes.gd`):
- player: the collider, the hurtbox, the live strike box, the live pogo box, the ember;
- room: every enabled solid box with its tag;
- hazards: the part of every spike tile in view that hurts (below the world's spike inset);
- a mark where a pogo bounced, on the bounce's tick: the down-strike hands control back then, so its box is already gone on the frame the hit resolved.
- They are read from the latest tick, never interpolated. The overlay shows what the simulation resolved, so at 144 Hz the boxes step once per tick while the grey boxes glide.

**Text** (`game/debug/debug_overlay.gd`) uses Godot's embedded default font at 18 px, already listed in docs/LICENSES.md for exactly this use, on 26 px lines (the font's height). It shows:
- the frame counter, numbered as fixtures, `trace.gd` and `film.gd` number frames (frame F is the state after input frame F; the first review found the overlay one ahead of them), the frame rate, whether the driver is locked to the display or interpolating (with alpha), and PAUSED;
- the player's state, crouch, facing, position (units) and velocity (units per tick);
- the current strike, its frame, its total, its active frames, and the next strike in the chain;
- the dash frame, cooldown and carry; the jump frame; frames airborne, or "on the ground";
- air jumps and dashes left, the wall side and frames, invulnerability, the ember and its cooldown;
- the camera's centre, focus, glide state and follow misses (ADR-0011).

**Input history** (`game/debug/input_history.gd`):
- the frame each tick consumed (`Simulation.last_input`), not the input ring, which folds presses together during hitstop: one tap showed on every frozen tick;
- runs of identical ticks, newest first, 24 kept;
- a run is the stick in numpad notation (5 neutral, 6 right, 8 up, 3 down-right), the held buttons with a star on those newly pressed, and the length in ticks;
- a new press always starts a new run, so a re-press while held shows, and a tap (pressed and let go within a tick) is a run of its own, never merged with the ticks after it;
- the stick reads at the player's own threshold in the eight equal sectors the dash and the toss read (`PlayerInput.dir8`). A strike reads four (`dir4`): a stick the history shows as 9 (up-right) is an up-strike when it is at least as far up as across.

The overlay records the input history every tick even while hidden, so it is complete the moment F3 opens. It reads the simulation and never writes it; tests check that the state hash does not move.

**The frame-stepped contact sheet** (`tools/replay/film.gd --overlay on`). CLAUDE.md's working method names `tools/replay/play.gd` for it. `play.gd` draws a whole run's path in one panel from the simulation alone, headless, and stays as it is. The sheet that shows "the F3 overlay on" has to show the overlay itself, so it is filmed by `film.gd`, which already films fixtures through the game's own views:
- `--overlay on` puts the overlay on the stage instead of the camera's working (`DebugOverlay.attach_sim` watches a bare simulation, since a film has no driver), captures it every tick, and lets it print the tick itself;
- `--zoom Z` magnifies the world Z times around the player so the boxes can be read against each other at sheet size, while the text stays on the screen;
- `--set <res path>:<prop>=<int>`, shared with `play.gd` (`TuningOverride`), films a feel-log "before" next to its "after".

**The drawn player and a corner-correction nudge** (`game/player/player_view.gd`). The simulation moves the collider by a whole nudge (a step up or down a lip, a lift onto a ledge's corner, a slide round a ceiling corner; up to 18 u) in one tick, and the overlay shows it on that tick. The drawn player does not hop:
- On the tick of the nudge it moves only as it was moving anyway: it is drawn where the collider would have been without the nudge.
- It then eases onto the collider over `nudge_ease_frames` (3, `content/player_view.tres`; feel log 2026-10-17 corner-correction ease), along a cubic that from rest is a smoothstep.
- A nudge arriving during an ease adds to what is left and starts a new cubic from the speed the drawn player already has (a Hermite cubic), so a staircase of lips is followed, not stalled at each lip.
- The offset never exceeds the largest single nudge of the run on either axis. Without the cap and the carried speed, the first version fell 64 u behind on a dashed staircase, then hopped 31 u (first review).
- Teleports and `begin` clear it.

The simulation never sees this, so no hash moves.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Interpolate the boxes like the views | At high refresh the overlay would show positions the simulation never had; a hitbox that "looks" overlapping between ticks never was |
| A frame-stepper that freezes the scene tree (`get_tree().paused`) | The input layer treats a paused tree as a menu and drops presses (ADR-0004), so a press made while stepping would be lost; stepping must look like play |
| Arrow glyphs for directions | The embedded font's arrows vary by platform; numpad notation is exact, compact and what fighting-game players read |
| Import a monospace font | CLAUDE.md rule 10; the embedded font is enough for 18 px debug text |
| A `--film` mode in `play.gd` | `play.gd` is headless and draws from the simulation alone; the overlay needs the real views and a display. Two tools that each do one thing beat one tool with two renderers. CLAUDE.md names `play.gd`; this ADR records the change |
| Draw the nudge as it happens (snap) | An 8 to 18 u hop in one tick is exactly what "the nudge is invisible" rules out |
| Ease the nudge over 1 or 6 frames | 1 is the snap one tick late. 6 leaves the feet inside the floor, or over it, for five ticks (83 ms), long enough to read as a pose |
| A critically damped spring for the ease | It follows staircases about as well, but never quite reaches the collider (an endless tail), where the cubic meets it on an exact frame that tests can check |
| Keep the drawn body out of solid ground | Clamping it out of the step it was nudged onto is the hop again |
| Ease in the simulation | The collider must be where the physics put it, or the hitboxes would disagree with what the overlay shows; presentation stays out of `core/` |

## Feel reason

The overlay is how every feel claim gets checked. A late input, an eaten cancel or a box that disagrees with the doc has to be visible frame by frame, on the frame it happened, in the build that ships.

## Consequences

- `tools/replay/film.gd --overlay on --zoom 3` films fixtures through the real views with the overlay on: the frame-stepped contact sheet the working method asks for, from task 5 on. It needs a display, or `xvfb-run` on a headless machine.
- The overlay's collider (white) and the drawn player can differ for three ticks after a nudge, by no more than the largest nudge of the run; that is the ease, not a bug. The drawn body can overlap the step it was nudged onto for those ticks: a whole lip deep on a dashed staircase.
- The keys are keyboard only, as BUILD.md's "F3" says; a pad chord waits for a need on the Deck.
- Every new system adds its boxes and lines here: enemies, their attack boxes and parry windows in task 6.
- The overlay is part of every build, so it must stay cheap. It draws only while shown, and the boxes come from one pass over the simulation's lists.
