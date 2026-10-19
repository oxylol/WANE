# core/: the deterministic simulation

Everything that decides what happens in a run lives here, and nothing else does (BUILD.md section 13, CLAUDE.md architecture rules 1 to 4).

- No `Node`, no `_process`, no rendering, audio, `Input` or Godot physics. Classes extend `RefCounted` (or `Resource` for content schemas).
- Stepped exactly once per 60 Hz tick by `Simulation.step(input)`.
- Positions and velocities are integers in 1/256-unit sub-pixels (ADR-0003). No floats anywhere in this folder: the compile stage of `tools/ci/run_tests.gd` rejects float types, literals and maths, engine singletons, frame callbacks and unseeded randomness here (`tools/ci/core_purity.gd`).
- Every tunable number arrives from `content/`; there are no tuning literals here.
- Randomness only through the split streams in `core/rng/`.

| Folder | Owns |
| --- | --- |
| `sim/` | Fixed-point helpers, `InputFrame`, the input ring buffer, the `Simulation`, state hashing, events handed to presentation |
| `physics/` | The AABB sweep against the room's collision grid: slopes to 45 degrees, one-way platforms, corner correction |
| `fsm/` | Player (and later enemy) state machines |
| `combat/` | Hitboxes, hurtboxes, damage, hitstop, Flame, Kindling, parry, spells |
| `items/` | The proc event bus, Votive stacking, the Votive resource and the API its listener script is handed (docs/adr/0015). Votives themselves are content: `content/votives/` |
| `clock/` | The Wane Clock and the Dark |
| `rng/` | Seeded RNG with split streams |
| `rooms/` | Room data, as loaded from `content/rooms/` |

A map of this folder's entry points (with file:line), the commands and the rules that trip agents up: `docs/CODEMAP.md`.
