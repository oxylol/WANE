# ADR-0006: Replay format, the fixture language, and golden hashes

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 13 (determinism and replays; testing and CI)
- Checklist lines: Run tension, "A seeded replay of a full run reproduces bit-for-bit on Windows, Linux and the Deck"; Process, "CI is green"

## Summary

- `.wrp` replays hold versions, content fingerprint, `Scenario`, two coded input streams and a hash every 60 ticks; under 2 KB a minute (see Replay files).
- The decoder rejects malformed data and more than four hours of frames; the game writes `user://replays/last_session.wrp` on exit (see Replay files).
- `ReplayPlayer` needs hashes at every 60th tick plus the last; an older build or different content is reported, not a desync (see Verification).
- `tools/replay/bless.gd` refuses to re-bless moved state hashes with unchanged inputs and content unless `Simulation.VERSION` is bumped (see Verification).
- Every fixture is encoded and decoded; full playback runs for `tests/replay/core/` and every fourth fixture, `FixtureRunner.PLAYBACK_EVERY` (see Cost).
- The suite runs in up to four processes (`FixtureRunner.MAX_SHARDS`) inside a 10 s budget, judged on wall time and on CPU time together (a busy machine stretches the first, not the second; ADR-0020 Decision 17, F3); fixture time is printed beside it (see Shards).
- `StateHasher` takes the first 32 bits of the native SHA-256 of a buffer of 64-bit words, 56 us a hash (see State hash).
- `.fixture` is a text language (`input`, then `expect` with at, during, never, mark); anything undefined fails and nothing passes vacuously (see Fixtures).
- CI runs fixtures on Linux, Windows and macOS against `tests/replay/golden_hashes.txt`; `bless.gd` rewrites it (see Determinism checks).

## Context

BUILD.md section 13: "Every run records seed, Wick, difficulty, pacts and the input stream (about 2 KB per minute). A replay reproduces the run bit-for-bit on any platform; a desync is a P0 bug caught by a state hash every 60 ticks. All 12 tech interactions and every boss phase are replay fixtures in tests/replay/: an input script and the expected state at named frames. They run headless in under 10 seconds total."

## Decision

**Replay files (`.wrp`)**: a binary format documented in `core/sim/replay.gd`: magic, format version, the simulation version and the content fingerprint (`ContentHash` of every tuning resource and room the simulation loaded) of the build that recorded it, the `Scenario` (seed, Wick, room, spawn, sorted integer options such as difficulty and pacts), the input as two streams (buttons, stick) each coded as runs over a move-to-front list of recent values, and the state hash every 60 ticks plus the hash of the final tick. Unit tests hold two input models to the 2 KB a minute budget: fast digital play (about 360 actions a minute) and a constantly moving analog stick with sensor noise; both encode under 2048 bytes. The decoder rejects malformed or implausible data: counts larger than the remaining bytes could hold, stream values outside their ranges, and more than four hours of frames (a full run is 35 to 60 minutes; hostile input can make it allocate at most those four hours). `ReplayRecorder` is attached to every session the game runs; the game writes `user://replays/last_session.wrp` on exit (file I/O lives in `game/replay_files.gd`; the core only encodes and decodes).

**Verification**: `ReplayPlayer` accepts a replay only if its hashes are exactly every 60th tick plus the final tick, so even a replay shorter than a second and the tail of every replay are checked, and a replay stripped of its hashes is rejected as malformed. A replay recorded by a different `Simulation.VERSION` is reported as "recorded by an older build", and one recorded with different content as "recorded with different content"; neither is a desync. Each golden line also stores a hash of the fixture's inputs and scenario and the content hash. `tools/replay/bless.gd` refuses to re-bless when a fixture's state hashes moved while its inputs and content did not (only a code change does that) unless `Simulation.VERSION` was bumped; a changed fixture or a content change needs no bump.

**Cost.** BUILD.md section 13 gives the whole fixture suite 10 seconds. Every fixture's recorded replay is encoded and decoded, and must come back exactly: its inputs, scenario, simulation version, content fingerprint and every recorded state hash. Played back, such a replay reproduces the run, because the golden check holds the simulation to the committed hashes for those very inputs, and `ReplayPlayer`'s own stepping is unit-tested (`tests/unit/core/test_replay.gd`). So a full playback of every fixture, which used to be half the suite's time, is kept for a deterministic sample: the replay system's own fixtures (`tests/replay/core/`) and every fourth fixture in path order (`FixtureRunner.PLAYBACK_EVERY`). The sample still catches anything a run does that its replay cannot reproduce, such as a probe with a side effect. With 275 fixtures the suite went from 10.4 to 11.3 s to 6.5 to 6.9 s on this container. Each sampled fixture builds two simulations, so building one has to stay cheap. It takes 1.4 ms on a 160 x 100 room, down from 14.6 ms:
- room parsing reads each distinct tile row once, and the slope rules visit only the slope tiles, which the native byte search finds (8.9 ms to 0.3 ms);
- the content hash digests each tuning resource with the native SHA-256 over Godot's portable `var_to_bytes` encoding, rather than feeding every byte of every property name through the state hasher (3.7 ms to 1.0 ms). Re-blessing for this change moved only the golden lines' `content:` field, never a state hash.
- the content digest lists each script's variable names once instead of asking each resource for its whole property list (task 6).

**Shards (task 7's prerequisite).** The suite runs in up to four processes at once, one per processor (`FixtureRunner.MAX_SHARDS`, `shards`): each runs an interleaved share of the fixtures (`tools/replay/fixture_shard.gd`; the playback sample is chosen by a fixture's place in the whole suite, as before) and prints each result as a line of escaped, tab-separated fields; the runner reads them back in path order, checks them against the golden file, blesses and keeps the time, which is the wall clock the developer waits for. A fixture whose result never comes back (its process died) fails. An instrumented coverage run (`--no-time-budget`) runs everything in one process. Why: on Windows, CI's slowest runner, the suite took 9.9 s of its 10 s with 378 fixtures, and 13.4 s with 328 two commits earlier, before task 6's speed work; task 7's zone rooms and every later boss phase add more. The fixture time itself is printed beside the wall clock (`378 fixtures, 0 failed, 4147 ms (7800 ms of fixture time in 4 processes)`), so its growth stays visible; the simulation's own cost is held by the stress room's perf gate (task 8), not by this budget. Here: 4.1 to 4.6 s for 378 fixtures (7.7 s in one process).

**State hash.** `StateHasher` appends every value to a buffer of 64-bit words and takes the first 32 bits of the buffer's native SHA-256 (little-endian bytes: Godot runs only on little-endian machines). The first version mixed each word with MurmurHash3 in GDScript: 480 us per state hash, once a second in the game and 7 us a tick in the fixtures; now 56 us. The change moved every hash (`Simulation.VERSION` 7) and no behaviour: every fixture's per-tick player, enemy and event state is identical before and after.

**Fixtures (`tests/replay/**/*.fixture`)**: a small text language so that inputs and expectations are data the replay viewer can also play:

```
fixture <unique name>
doc <the BUILD.md section, table and row it proves>
seed <int>   room <id>   spawn <x> <y>   wick <id|none>   option <key> <int>
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
| Keep the suite in one process and play back fewer fixtures in full | Halves only the playback's sixth of the time, loses coverage, and the suite still grows with every room and boss phase |
| Run the shards as threads in one process | The simulation's statics (the content digest's script table) and Godot's resource cache are not built for concurrent use; processes share nothing |

## Feel reason

Every movement and combat number is pinned by a frame-exact script, so a tuning change shows exactly which frames moved.

## Consequences

Changing the simulation means re-blessing; the diff of `golden_hashes.txt` lists every fixture whose behaviour changed.
