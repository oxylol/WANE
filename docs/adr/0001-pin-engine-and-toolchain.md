# ADR-0001: Pin Godot 4.7.2, vendor gdUnit4 6.2.2, start on the Compatibility renderer

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 13 (engine choice, testing and CI), 12 (performance targets)
- Checklist lines: Process, "CI is green: unit, replay, perf, screenshot, style gate, lint"

## Summary

- Godot 4.7.2-stable is pinned in `.godot-version`; fetch scripts verify the official SHA-512 in `ci/godot.sha512` (see Decision 1).
- gdUnit4 6.2.2 is vendored at `addons/gdUnit4/` without its self-test folder or `src/asserts/CLAUDE.md`; exports must exclude it (see Decision 2).
- gdtoolkit 4.5.0 (gdlint, gdformat) and every Python dependency are pinned exactly in `tools/requirements.txt` (see Decision 3).
- Phase 1 runs on the GL Compatibility renderer; Phase 2 task 1 re-measures it against Mobile in the stress room and gets its own ADR (see Decision 4).
- Upgrading Godot or gdUnit4 is a tracked task that re-runs the full suite, replay fixtures and perf benchmark (see Consequences).

## Context

CLAUDE.md: "Godot 4.x, latest stable, pinned in `.godot-version`. Never upgrade without a tracked task and a full regression run." "gdUnit4 for tests. gdlint and gdformat in CI with zero warnings." On 2026-10-16 the latest stable Godot is 4.7.2 and the latest gdUnit4 release is 6.2.2, which lists Godot 4.7 and 4.7.1 as supported.

The build environment cannot reach GitHub release downloads or godotengine.org directly. The official release files are mirrored on SourceForge (`godot-engine.mirror`), together with the official `SHA512-SUMS.txt`.

## Decision

1. `.godot-version` holds `4.7.2-stable`. Every script that fetches Godot (`ci/setup_godot.sh`, the CI workflow) reads that file and verifies the archive against the official SHA-512 before use. The Linux x86_64 archive checksum is `9aa00f7a…54c65` (full value in `ci/godot.sha512`).
2. gdUnit4 6.2.2 is vendored at `addons/gdUnit4/` without its own self-test folder and without the upstream agent guidance file (`src/asserts/CLAUDE.md`), which contradicts this project's warning rules. It is a development dependency only; when export presets are added, every preset must exclude it.
3. gdtoolkit 4.5.0 (gdlint, gdformat) and every Python dependency are pinned exactly in `tools/requirements.txt`.
4. Phase 1 runs on the GL Compatibility renderer. It is the renderer available everywhere we must run (Steam Deck, minimum-spec GTX 1050, headless CI machines with Mesa llvmpipe for contact sheets) and Godot's 2D lights, occluders and canvas shaders work on it. Phase 2 task 1 (the lighting pass) re-evaluates Compatibility against Mobile with a measured comparison in the stress room before any final art is built on it; that choice gets its own ADR.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Godot 4.8 dev snapshot | Not stable; CLAUDE.md requires latest stable |
| gdUnit4 master (7.0.0, unreleased) | Unreleased; pin to a tagged release |
| Install gdUnit4 at CI time instead of vendoring | Needs network access to GitHub on every run and makes test results depend on a moving download |
| Forward+ renderer | Built for 3D; heavier on the Deck and minimum spec for no 2D gain; unavailable on our CI rendering path |

## Feel reason

None directly. A pinned engine is what makes "a desync is a P0 bug" enforceable: the same binary, the same results.

## Consequences

- Upgrading Godot or gdUnit4 is a tracked task that re-runs the full suite, the replay fixtures and the perf benchmark.
- The renderer decision is provisional until Phase 2 task 1 and is flagged in PROGRESS.md.
