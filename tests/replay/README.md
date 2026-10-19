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
Watch one:
- `tools/replay/play.gd` draws a fixture's whole path in one panel, headless.
- `tools/replay/film.gd --overlay on --zoom 3` films it tick by tick through the game's own views with the F3 overlay on: the frame-stepped contact sheet (docs/adr/0012). It needs a display, or `xvfb-run`.

## Probe keys

What a fixture's expectations, `trace.gd` and the F3 overlay can read (`Simulation.probe`). Positions and speeds are sub-pixels (compare with `u` values) unless the key ends in `u`; words are listed.

- Input: `tick`, `stick_x`, `stick_y`, `held.<BUTTON>` (1 or 0), `press_age.<BUTTON>` (the age of the latest unused press, or -1); buttons are JUMP, ATTACK, DASH, SPELL, MEND, VESSEL, TOSS.
- Events this tick: `event.<name>` (1 or 0), names from `core/sim/sim_events.gd` (jump, land, dash, pogo, attack, hazard, hit, kill, parry, player_hit, ember_home, death, cast, radiance, heal, charge_ready, charge_release, ...).
- The player's body: `x`, `y`, `xu`, `yu`, `vx`, `vy`, `height` (units), `ground`, `slope`, `hit_wall`, `hit_ceiling`, `nudge_x`, `nudge_y`.
- Movement: `state` (ground, air, dash, wall), `facing`, `crouch`, `air_frames`, `air_jumps`, `air_dashes`, `dash_frame`, `dash_cooldown`, `carry`, `jump_frame`, `jump_cut`, `wall`, `wall_frames`, `wall_lock`, `invuln` (1 or 0), `invuln_frames`.
- Strikes: `action` (none or a strike id), `chain` (the next side strike), `action_frame`, `action_dir`, `strike` and `pogo_live` (a live box, 1 or 0), `since_bounce`, `charge_held`, `charge_request`.
- The Ember Toss: `ember` (1 while out), `ember_x`, `ember_y`, `toss_cooldown`.
- Combat (docs/adr/0013): `hearts`, `flame`, `kindling` (hits), `tier` (ember, flame, blaze, white), `spell` (none, kindle, radiance, mend), `spell_frame`, `freeze` (hitstop frames left), `knock` (knockback frames left), `embers` (kill embers in flight), `light` (Radiance's ticks left).
- Enemies: `enemy.<key>` reads the room's first enemy, `enemy<n>.<key>` its n-th from 0: `hp`, `poise`, `state` (idle, telegraph, strike, recover, stagger, dead), `x`, `y`, `vx` (its knockback), `vy`, `facing`, `freeze`, `burn`.

Scenario options a fixture may set (`option <name> <value>`): `kindle` (the Kindle Votive's dash, tech 12), and starting vitals `hearts`, `flame` and `kindling`.
