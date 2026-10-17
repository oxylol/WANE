# Replay fixtures

An input script and the expected state at named frames (BUILD.md section 13). The language is specified in `docs/adr/0006-replays-and-fixtures.md`; in short:

```
fixture jump_buffer_8f
doc BUILD.md s5 Jump table, "Jump buffer 8 f"; s15 Movement line 1
seed 1
room test/flat
spawn 200 100
frames 90

input
  20 jump          # pressed in the air, 8 frames before the landing
end

expect
  # The landing frame (28) is pinned by a control fixture with no press; here the jump fires on
  # that same frame, so the player never stands on the ground at all.
  at 28 state=air vy<0
  never 20..40 ground=1
end
```

- `wick none` runs the core without a player (for fixtures about input and the loop alone); the default is Ash.
- Frames not listed in `input` are neutral. `!jump` is a press and release within one tick; `jump !jump` is a re-press while held (released and pressed again between two ticks).
- "Frame F" is the state after the simulation consumed input frame F.
- `mark` names the first frame in a range where every condition holds; later lines use the name with an optional `+n` or `-n`.
- Values: integers, `12u` (units, times 256 sub-pixels), `key@m` (a probe value at frame or mark `m`), `key@(m+3)` (at an offset from it), sums of those (`180u+x@start`), or words for states. A `+` or `-` straight after `key@m` is an error because it is ambiguous; put literals first or use parentheses.
- Every input frame may be set by only one line; directives take exactly their words; a word value must be one the key can take. Anything else is a parse error, and an expectation that cannot be evaluated fails, so nothing passes vacuously.

Run: `godot --headless --path . --script tools/ci/run_tests.gd -- --stage fixtures`.
After an intended simulation change: `godot --headless --path . --script tools/replay/bless.gd`, then commit `golden_hashes.txt` with the change.
Watch one: `tools/replay/play.gd` (Phase 1 task 5) plays a fixture with the F3 overlay and writes a contact sheet.
