# ADR-0004: InputFrame with latched presses; a hitstop-aware 8-frame ring buffer

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 5 (feel rules), 6 (hit feedback: "Hitstop is never applied to the player's own input reading"), 12 (input), 13 (input layer)
- Checklist lines: Movement, "Jump pressed 8 frames before landing fires on the landing frame"; Combat, "Hitstop never causes a dropped input; buffered inputs fire on the first free frame"; "Attack comes out on frame 3 from a neutral press, every time, including during hitstop"

## Context

BUILD.md section 13: "polls raw device state every frame before physics into an InputFrame (buttons as a bitfield, stick as fixed-point) and keeps an 8-frame ring buffer that always serves the latest press." Section 5: "Buffers are generous (8 f) and the buffer always stores the latest input." Section 15 requires a jump pressed 8 frames before landing to fire on the landing frame, so a press must still be available when it is 8 frames old. Section 6 requires that hitstop (up to 20 frames) never drops an input.

## Decision

1. `InputFrame` holds `held` and `pressed` bitfields (7 buttons) and an 8-bit signed stick (plus/minus 127, +y down). `pressed` contains every rising edge since the last tick, including a press and release that both happened between two ticks. The frame packs into a 30-bit integer for replays.
2. The input layer (`game/input/`) owns remapping and dead zones and reads `content/input/input_settings.tres`. Each button action is down or up with hysteresis on its combined raw strength (every device bound to it): down at 50% travel, up only below 40% (both in content), so an analog trigger resting near the threshold neither flickers nor re-presses, and a held trigger, which Godot reports as "pressed" on every motion event, presses exactly once. Every poll re-reads each button from the devices, so a release the layer never received as an event (the tree was paused, or another node consumed it) cannot leave a button stuck down and eat its next press; events only add latches, so a press and release between two ticks still reaches the core as a press. The layer keeps processing while the tree is paused, but a button pressed during a pause (in a menu) is treated as already held: it does not jump on resume, and the next real press does. The stick gets a radial dead zone (inner 12%, outer 95%, rescaled; a stick that has left the inner zone stays out until it falls below 10%, so one resting on the edge does not flicker), then is quantised to steps of 8 (of 127) with a full step of hysteresis (a held stick yields identical frames; noise of up to plus or minus 3 units around a level never flips it). Each axis also has a band around zero: it leaves 0 only at half a step, and crossing to the other side of zero with less than that reads 0, so noise on the axis a sideways stick is not pushing never reaches the core (unit-tested: a minute of a held sideways stick with 1% noise is one frame value); a deliberate flick to the other side reads on the same frame. The quantiser keeps both dead-zone edges where they are: the stronger axis reports its first step as soon as the stick leaves the inner dead zone, and 127 is reported only beyond the outer one (unit-tested at 11.9%, 12.5%, 94.9% and 95% raw). The movement axes are remappable. Losing window focus clears every latched and held state.
3. `InputRing` keeps the current frame plus 8 frames of history (9 slots), so ages 0 to 8 are served: "pressed 8 frames before landing" is age 8 on the landing frame. Queries return the latest unconsumed press. `consume` uses that press and every older press of the same button, so one press never fires two actions and an older tap can never fire after a newer one (the buffer serves only the latest input). A query wider than the ring is a programming error (asserted) and content is validated against the ring size.
4. The ring advances in the player's own time. On a tick where the player is frozen by hitstop, the new frame is merged into the newest slot (presses accumulate, held state and stick take the latest values, and a new press un-consumes that slot's button) instead of pushed. Every press made during hitstop is therefore 1 frame old on the first free frame and fires there.
5. How long each button has been held is counted per button, separately from the ring, so holds longer than 9 frames (the 24 f charged strike) are measured exactly.
6. Directions are derived from the stick inside the core with a threshold from content, so keyboard, d-pad and stick behave identically.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Exactly 8 slots including the current frame | Ages 0 to 7 only: a press 8 frames before landing would be lost, failing the first Movement checklist line |
| Ring advances every tick, with buffer windows extended by the hitstop length | Every query would need to know about freezes; merging keeps queries simple and makes "fires on the first free frame" structural |
| Derive presses from held transitions only | Loses taps shorter than one tick at high display refresh rates |
| Latch every event that reports "pressed" | Analog triggers report "pressed" on every motion event above the threshold: a held trigger would press every tick |
| Leave older presses usable after the latest is consumed | Two jump taps in the air would fire a ground jump and then a double jump from the older tap |

## Feel reason

Input is never late and never lost. The latest press always wins, which is what a player mashing a cancel expects.

## Consequences

`Simulation` decides push or merge per tick from the player's freeze state (Phase 1 task 6). The F3 overlay shows the ring, so a tester can see a buffered press waiting.
