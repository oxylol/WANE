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

## Summary

- Keys (`game/debug/debug_controls.gd`, keyboard only): F3 shows the overlay; with it shown F4 pauses, F5 steps one tick, F6 ten; no modifiers (see Keys).
- Stepping goes through `SimDriver.step_once`, the play path: it polls, records the replay and fires the tick signal (see Keys).
- Boxes (`game/debug/debug_boxes.gd`): collider, hurtbox, strike, pogo, ember, solids, spikes, pits, bounce and hazard marks; never interpolated (see Boxes).
- Text (`debug_overlay.gd`) uses Godot's embedded default font at 18 px on 26 px lines; frame F is the state after input frame F (see Text).
- Input history (`input_history.gd`) shows `Simulation.last_input` as runs of identical ticks, 24 kept, in numpad stick notation (see Input history).
- The overlay records history every tick even while hidden and never writes the simulation; tests check the state hash does not move (see Input history).
- The frame-stepped contact sheet is `tools/replay/film.gd --overlay on` (`--zoom Z`, `--set`); `play.gd` stays headless (see The frame-stepped contact sheet).
- The drawn player eases a corner nudge over `nudge_ease_frames` (3), lag capped by `nudge_lag_percent` (250); the collider never moves (see The drawn player).
- The overlay collider and the drawn player may differ during an ease by up to two and a half times the run's largest nudge; that is the ease, not a bug (see Consequences).
- Every new system adds its boxes and lines to the overlay, which draws only while shown (see Consequences).

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
- With the overlay shown, F4 pauses and resumes the simulation, and while paused F5 steps exactly one tick and F6 steps ten. The stepper is part of the overlay: with it hidden F4 to F6 do nothing, and hiding it while paused resumes play. A stray F4 used to freeze the game with nothing on screen to say so (second review, M2).
- A pause draws the tick it stopped on, the one the overlay's boxes show (the driver's interpolation factor goes to 1): at 144 Hz a pause mid-dash used to leave the grey box 9 u behind its boxes until the first step (second review, L1).
- No debug key takes a modifier, and no game binding uses one of them (a test checks the bindings). Ten steps were Shift+F5 until the first review: Shift is the keyboard's dash, and held through the ten steps it dashed 190 u.
- Stepping goes through `SimDriver.step_once`, the same path play uses. It polls the controller for that tick, records the tick in the replay, and fires the views' tick signal. A press made while paused is latched by the input layer and lands on the next step, exactly as a press between two ticks does in play.

**Boxes** (`game/debug/debug_boxes.gd`):
- player: the collider, the hurtbox, the live strike box, the live pogo box, the ember;
- room: every enabled solid box with its tag;
- hazards: the part of every spike tile in view that hurts (below the world's spike inset), and every pit tile;
- a mark where a pogo bounced, on the bounce's tick: the down-strike hands control back then, so its box is already gone on the frame the hit resolved;
- a mark of the hurtbox that touched a hazard, on the hazard's tick: the send-back has already moved the player to safe ground then, so the hurtbox drawn that tick touches nothing (second review, M1).
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
- It then closes the gap with a catch-up speed that changes by at most a share of the run's nudge a tick (the largest nudge since it last met the collider), braking so it meets the collider at rest. From rest a nudge eases in exactly `nudge_ease_frames` (3, `content/player_view.tres`; feel log 2026-10-17 corner-correction ease) along a triangle of speeds: a quarter, a half and a quarter of the nudge (2, 4 and 2 u for an 8 u lip).
- A nudge arriving during an ease adds to what is left, and the speed carries on from where it was, so a staircase of lips is climbed steadily, never stalled at each lip and never hopped.
- The gap never exceeds `nudge_lag_percent` (250) of the run's nudge. A speed that may change by a quarter of the nudge a tick, from rest, up a staircase taken a lip a tick, lets the gap grow n, 1.75n, 2.25n and 2.5n and stop there (the speed has then reached the nudge a tick, and the braking limit holds it); a cap of 200 forced the excess through at once, a jolt of twice the allowed speed change and a drawn player riding 16 u off the stair for its length (presentation review 3, H1: walked down, walked up a stair of 9 u treads). 250 is the number at which the speed limit never has to give way on any shipped staircase; past it the drawn player would still move by the excess at once, and no fixture comes past it (`presentation/walk_down_lip_stairs`, `dash_down_lip_stairs`, `walk_up_stairs9`, with the physics staircases, are in `test_a_corner_correction_nudge_never_snaps_the_drawn_player`). The cost is honest: a stair taken a lip a tick (8 u) is drawn 20 u behind the collider for its length, and a stair dashed down three lips a tick up to 46 u (more than Ash is tall, for three ticks). The first version, with no cap and no carried speed, fell 64 u behind on a dashed staircase, then hopped 31 u (first review). The second capped the gap at the run's nudge by moving the drawn player itself, so a nudge arriving at the cap was drawn whole in its tick: a two-step stair walked showed the second lip as an 8 u hop, and a walked staircase hitched every few frames (second review, H1; feel log 2026-10-19 corner-correction ease on runs).
- What it costs: up a staircase the drawn player falls further behind than one lip, up to 12 u on a walked 1:2 stair of 8 u lips and 48 u (a little more than Ash's height) for two frames on a 45-degree staircase dashed three lips a tick (director question).
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
| Follow a stair's own climb rate and ease only the deviation (presentation review 3, a considered alternative) | Starting from rest the drawn speed still cannot reach the stair's rate faster than a quarter of the nudge a tick, so the lag at the start is the same; it only hides the offset after, at the price of a model of terrain in a view. Left for Phase 2's rig, where the feet are planted by animation |
| Cap the gap at the run's nudge by moving the drawn player (the second version) | A nudge arriving at the cap is drawn whole in its tick: the hop again, every few frames up a walked staircase |
| A cap on the catch-up speed (0.625 of the nudge a tick) | It still changes speed at once, and up a dashed staircase it falls ever further behind: the collider climbs 64 u in three ticks there, the cap catches up at most 45 u |
| A soft cap: the speed's limit growing with the gap past one nudge | Every version tried offline on the fixtures' nudges brought back a jolt where the limit grows (the speed changing by up to 0.7 of the nudge in a tick) for 12 to 16 u less lag on the dashed staircase |
| Keep the drawn body out of solid ground | Clamping it out of the step it was nudged onto is the hop again |
| Ease in the simulation | The collider must be where the physics put it, or the hitboxes would disagree with what the overlay shows; presentation stays out of `core/` |

## Feel reason

The overlay is how every feel claim gets checked. A late input, an eaten cancel or a box that disagrees with the doc has to be visible frame by frame, on the frame it happened, in the build that ships.

## Consequences

- `tools/replay/film.gd --overlay on --zoom 3` films fixtures through the real views with the overlay on: the frame-stepped contact sheet the working method asks for, from task 5 on. It needs a display, or `xvfb-run` on a headless machine.
- The overlay's collider (white) and the drawn player can differ while a nudge eases (three ticks after a lone nudge, a few more after a staircase), by no more than two and a half times the largest nudge of the run; that is the ease, not a bug. The drawn body can overlap the step it was nudged onto meanwhile: more than a whole lip deep on a dashed staircase.
- The keys are keyboard only, as BUILD.md's "F3" says; a pad chord waits for a need on the Deck.

### Presentation review 3 (docs/feel_log/2026-10-19-presentation-review-3.md)

- The overlay marks what the simulation resolved on a tick and then forgot: a parry (a contact mark, and the swing that was parried in white, from the swing each telegraphing enemy was about to land, remembered by `DebugBoxes.Memory` after every tick, because the parry staggers the enemy and clears its attack on the tick the swing lands), a hit on the player (its contact point), a lethal one (the hurtbox where Ash stood, before the send-back), a burn, and a Blaze finisher's burst (the bounding square of the 96 u circle, labelled; the test is the distance between centres). An enemy's label says "PARRY WINDOW OPEN" while a press would parry (the ticks to landing within `parry_window_frames`) and "burning N" while it burns.
- Enemy labels sit above the health and poise bars in every state (the cue lifts them further), and an enemy's box is a 1 px line so the white cue outline round the same rectangle shows through (the F3 sheets read the white cue as lavender).
- The boxes are collected once a tick (the cache is keyed by simulation, tick and view), and no label repeats are scanned for: the down-strike's box that is its pogo box is labelled once where it is collected.
- A death by an enemy's hit cuts the drawn player to the spawn like a hazard (`SimEvents.DEATH`). The camera's half of that cut is in `game/camera/camera_subject.gd` and belongs to the camera.
- Resuming the frame-stepper drops the owed phase, so the first frame draws forward from the newest tick (at 144 Hz it drew up to 0.6 of a tick's motion backward).
- The purity test plays every fixture directory. Reading is the cost (the overlay's reads on every tick of all 390 fixtures took 3 min 18 s on a loaded machine), so `combat`, `doors`, `presentation`, `tech` and `physics` are read on every tick (and the state hashed on every tick in the first three, where the task 6 reads are exercised), and the rest every tenth tick and at the end (41 s in all, same machine); every fixture's end hash is compared.
- Every new system adds its boxes and lines here: enemies, their attack boxes and parry windows in task 6.
- The overlay is part of every build, so it must stay cheap. It draws only while shown, and the boxes come from one pass over the simulation's lists.
