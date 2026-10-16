# ADR-0005: xoshiro128** on 32-bit words, split into five streams

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 13 (simulation core: "a seeded RNG with split streams (loot, spawns, VFX, AI)")
- Checklist lines: Run tension, "A seeded replay ... reproduces bit-for-bit"

## Context

A run is a seed plus an input stream. Randomness must be identical on every platform, cheap in GDScript, and split so that one system's draws never shift another's.

## Decision

1. Generator: xoshiro128** (Blackman and Vigna). State is four 32-bit words kept in 64-bit ints and masked after each operation; multiplications use `Fx.mul32`, so nothing approaches signed overflow.
2. Seeding: each stream's state words are `fmix32(x + constant)` where `x` mixes the run seed with the stream id. An all-zero state is impossible.
3. Streams: loot, spawns, vfx, ai, and a fifth, procs, for Votive proc rolls, so how often items fire never changes what a run finds.
4. Unbiased ranges by rejection sampling. Chances are per-mille integers.
5. Presentation never draws from core streams; when the core emits an event that presentation decorates (a hit spark), it attaches a seed drawn from the vfx stream, so visuals are deterministic for screenshots without feeding back into the simulation.
6. The first outputs for seed 1 are pinned in a unit test against an independent Python implementation. Changing the generator invalidates every replay, so it never changes.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Godot's RandomNumberGenerator (PCG32) | Opaque engine implementation that could change between versions; a pinned engine still makes our replays depend on engine internals |
| PCG32 in GDScript | Needs 64-bit multiplication modulo 2^64, which overflows signed ints |
| One shared stream | Adding a VFX roll would change loot; replays and balance would drift with every cosmetic change |

## Feel reason

None directly; it protects "a desync is a P0 bug" and seeded dailies.

## Consequences

New random systems pick a stream (or add one, which changes no existing stream's sequence).
