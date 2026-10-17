# 2026-10-17: Pogo chain window, frame 6 to frame 14 and back to frame 6

- Author: Claude
- BUILD.md section and table row:
  - section 5, Pogo, "Chain window: Next down-strike can start on frame 6 after a bounce; Cadence of about 4 bounces per second at its fastest";
  - section 15, "Pogo keeps full horizontal speed; a 10-bounce chain across the zone 1 spike pit is possible at 4 bounces per second".
- Fixture(s):
  - `tests/replay/movement/pogo_chain_window.fixture`;
  - `tests/replay/movement/pogo_chain_window_early_press.fixture`;
  - `tests/replay/movement/pogo_down_dash_pogo.fixture`;
  - `tests/replay/tech/tech04_pogo_dash_reset.fixture`;
  - the illustration `docs/feel_log/fixtures/pogo_skim_window6.fixture`.
- Contact sheet: `docs/feel_log/2026-10-17-pogo-chain-window.png`:
  - panel 1: the fastest pogo-dash skim at frame 6, a bounce every 11 frames;
  - panel 2: the pogo-dash chain at a 15-frame rhythm (4 a second), which frame 14 enforced;
  - panel 3: pogo off the bell, dash down-left, pogo the spikes, at frame 6;
  - panel 4: the same inputs at frame 14: the second strike starts too late and the player lands in the spikes;
  - panel 5: the feet's height over time for panels 1 to 4 in blue, orange, green and pink. Each white tick is an event.

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Pogo chain window | 6, then 14 | 6 (BUILD.md's value, restored) | frames after a bounce (the bounce frame is frame 1) |

## Why

Frame 14 was tried to make the window match its note's cadence of about 4 bounces a second. It is reverted, for three reasons that the first task-3 review found and the sheet shows.

- **It did not remove the skim.**
  - The fast chains come from pogo, dash, pogo: every pogo restores the air dash, and the dash cancels the bounce's rise.
  - At either window, the feet skim 2 to 23 u above the spikes at 16 u/f (panels 1 and 2, and the flat blue and orange traces in panel 5).
  - Frame 14 changed only how often the skim bounces (every 11 frames against every 15), not what it looks like.
- **It broke a real tech.**
  - Pogo off a target, dash down past it, pogo what is below: the dash takes the player to the spikes before frame 14.
  - So the strike's pogo frames come too late, and the player is hurt (panel 4 against panel 3, `pogo_down_dash_pogo`).
- **It dropped presses.**
  - A down-strike pressed on bounce frames 1 to 5 aged out of the 8-frame buffer before frame 14, so it was lost silently.
  - At frame 6 the press waits and fires on frame 6 (`pogo_chain_window_early_press`).
  - CLAUDE.md prefers a wider cancel window over a narrower one.

## How it plays now

- The next down-strike can start 6 frames after a bounce. A press on bounce frames 1 to 5 starts on frame 6.
- Pogo, dash, pogo can skim as fast as the player can press. The 4-a-second rhythm the checklist asks for is one way to play it (`tech04_pogo_dash_reset`: fourteen bounces exactly 15 frames apart across the 3360 u pit).
- Pogo, down-dash, pogo works.

## Open questions for the director

- **Cadence.** BUILD.md's note says "about 4 bounces per second at its fastest". The pogo-dash skim can bounce every 8 to 11 frames: 5.5 to 7.5 a second, a stutter along the spikes at 16 u/f (panel 1).
  - **Is that skim the intended tech?** It crosses any spike pit.
  - **If not, it needs its own rule**, because no chain window removes it without breaking pogo, down-dash, pogo. For example, a dash cancelling a bounce's rise could restore no air dash until the next landing.
- **Pure pogo.** Pogo alone over level ground cannot exceed 1.64 bounces a second at these numbers. The checklist's 10-bounce chain at 4 a second is met by the pogo-dash rhythm. Please confirm that is the intent.
