# ADR-0006: Replay format, the fixture language, and golden hashes

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 13 (determinism and replays; testing and CI)
- Checklist lines: Run tension, "A seeded replay of a full run reproduces bit-for-bit on Windows, Linux and the Deck"; Process, "CI is green"

## Context

BUILD.md section 13: "Every run records seed, Wick, difficulty, pacts and the input stream (about 2 KB per minute). A replay reproduces the run bit-for-bit on any platform; a desync is a P0 bug caught by a state hash every 60 ticks. All 12 tech interactions and every boss phase are replay fixtures in tests/replay/: an input script and the expected state at named frames. They run headless in under 10 seconds total."

## Decision

**Replay files (`.wrp`)**: a binary format documented in `core/sim/replay.gd`: magic, format version, the simulation version and the content fingerprint (`ContentHash` of every tuning resource and room the simulation loaded) of the build that recorded it, the `Scenario` (seed, Wick, room, spawn, sorted integer options such as difficulty and pacts), the input as two streams (buttons, stick) each coded as runs over a move-to-front list of recent values, and the state hash every 60 ticks plus the hash of the final tick. Unit tests hold two input models to the 2 KB a minute budget: fast digital play (about 360 actions a minute) and a constantly moving analog stick with sensor noise; both encode under 2048 bytes. The decoder rejects malformed or implausible data: counts larger than the remaining bytes could hold, stream values outside their ranges, and more than four hours of frames (a full run is 35 to 60 minutes; hostile input can make it allocate at most those four hours). `ReplayRecorder` is attached to every session the game runs; the game writes `user://replays/last_session.wrp` on exit (file I/O lives in `game/replay_files.gd`; the core only encodes and decodes).

**Verification**: `ReplayPlayer` accepts a replay only if its hashes are exactly every 60th tick plus the final tick, so even a replay shorter than a second and the tail of every replay are checked, and a replay stripped of its hashes is rejected as malformed. A replay recorded by a different `Simulation.VERSION` is reported as "recorded by an older build", and one recorded with different content as "recorded with different content"; neither is a desync. Each golden line also stores a hash of the fixture's inputs and scenario and the content hash. `tools/replay/bless.gd` refuses to re-bless when a fixture's state hashes moved while its inputs and content did not (only a code change does that) unless `Simulation.VERSION` was bumped; a changed fixture or a content change needs no bump.

**Fixtures (`tests/replay/**/*.fixture`)**: a small text language so that inputs and expectations are data the replay viewer can also play:

```
fixture <unique name>
doc <the BUILD.md section, table and row it proves>
seed <int>   room <id>   spawn <x> <y>   wick <id>   option <key> <int>
frames <N>
input
  <frame>[..<frame>] <tokens>     # L R U D, x=<n> y=<n>, jump attack dash spell mend vessel toss,
                                  # !button = press and release within the tick,
                                  # button !button = re-pressed while held, - = nothing
end
expect
  at <ref> <cond>...              # at one frame
  during <ref>..<ref> <cond>...   # every frame in the range
  never <ref>..<ref> <cond>...    # no frame where all conditions hold
  mark <name> <ref>..<ref> <cond>...   # first frame where all hold; later lines use <name>[+-n]
end
```

Frames not listed are neutral; a frame may be set by only one input line. "Frame F" is the state after the simulation consumed input frame F. A condition is `<probe key><op><value>` with ops `= != < <= > >=`; a value is a sum of integers (a `u` suffix multiplies by 256 sub-pixels per unit) and probe values at other frames (`x@start`, or `x@(start+3)` for an offset), or a bare word for a state name. A `+` or `-` straight after `x@start` is a parse error because it could mean either an offset or an addition: write `180u+x@start` or `x@(start+3)`. Probe keys come from `Simulation.probe()`, and a word must be one of the values `Simulation.probe_words()` lists for its key.

The language rejects anything it does not define (unknown tokens, stray words, a directive given twice, a stick value out of range), and an expectation that cannot be evaluated (a value reference outside the run, a word for a numeric key) fails, whatever its kind. Nothing passes vacuously.

**Determinism checks**: every fixture run is recorded, encoded, decoded and played back through `ReplayPlayer`, which must match every state hash. The hashes (every 60 ticks plus the final tick) are also compared with `tests/replay/golden_hashes.txt`. CI runs the fixtures on Linux, Windows and macOS against the same golden file, which is the bit-for-bit cross-platform check. When an intended simulation change moves the hashes, `tools/replay/bless.gd` rewrites the golden file and it is committed with the change, so every behaviour change is visible in review.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Fixtures as GDScript test functions | Inputs become code; the replay viewer and contact-sheet tool could not play them as data |
| JSON fixtures | Godot parses JSON numbers as floats; verbose for frame scripts |
| Cross-platform check by comparing CI artifacts between jobs | Works only inside one CI run; golden files also catch unintended simulation changes |

## Feel reason

Every movement and combat number is pinned by a frame-exact script, so a tuning change shows exactly which frames moved.

## Consequences

Changing the simulation means re-blessing; the diff of `golden_hashes.txt` lists every fixture whose behaviour changed.
