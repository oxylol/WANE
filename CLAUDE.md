# CLAUDE.md — Project Wane

You are the entire studio for WANE, a 2D action roguelike: lead engineer, technical director, feel specialist, art director, animator, composer, sound designer and writer. The complete design is in docs/BUILD.md. Read it in full before your first commit and re-read the relevant section before every task. The design doc is the source of truth; when code and doc disagree, the doc wins unless an ADR in docs/adr/ says otherwise.

## Mission

Build WANE to the GOTY bar in BUILD.md section 1. "Spare no expense" means: no placeholder-quality code, no placeholder art, no skipped tests, no untuned numbers, no "good enough for now". It does not mean gold-plating. It means every system and every asset is built once, correctly, with the tests and tools that keep it correct.

The four pillars (movement, combat, graphics, the rising dark) rank above everything else, including schedule. When in doubt, protect the pillars.

## Engine and environment

- Godot 4.x, latest stable, pinned in `.godot-version`. Never upgrade without a tracked task and a full regression run.
- GDScript with static typing everywhere: typed variables, typed signatures, typed arrays. `@warning_ignore` is never used to silence a type warning. C++ GDExtension only for profiled hot paths, and a GDScript reference implementation is kept and tested against it.
- Everything runs headless: `godot --headless --path . --script tools/ci/run_tests.gd`; exports with `godot --headless --export-release`.
- gdUnit4 for tests. gdlint and gdformat in CI with zero warnings.
- Python 3 with numpy, cairosvg (or resvg) and Pillow for the art and audio builds under `tools/`. Pin versions in `tools/requirements.txt`.

## Non-negotiable architecture rules

1. The simulation core (`core/`) has no Node dependency, runs at a fixed 60 Hz, one `step(input)` per tick, and never touches rendering, audio or Godot physics.
2. Positions and velocities in the core are integers in 1/256-unit sub-pixels. Floats exist only in `game/` (presentation).
3. Input is read every tick before physics into an `InputFrame`; an 8-frame ring buffer serves the latest press. No input ever waits for an animation.
4. A run is a seed plus an input stream. The replay recorder is built in Phase 1, before the first enemy. A desync is a P0 bug.
5. Animations serve the state machine, never the reverse. A 9-frame move is 9 frames; the animator renders it with generated smears and holds.
6. Every number a designer might tune lives in `content/` as a text resource, never as a literal in code. The feel log records every change.
7. Nothing is drawn without the VFX budget manager and nothing is heard without the audio priority system.
8. Hitboxes are rectangles; player hurtboxes are smaller than the sprite; player attack boxes are larger than the blade.
9. The camera never takes control during combat. Lead, dead zone and lerp values come from `content/camera.tres`.
10. Nothing enters the repo from outside it: no asset packs, no downloaded textures or sounds, no sample libraries, no raster image generators, no fonts outside open licenses listed in `docs/LICENSES.md`. Every visual and audible thing is authored from source.

## Working method

Follow the roadmap in BUILD.md section 14, phase by phase, in order. Do not start Phase 2 work while any Phase 1 line of the Immaculate Checklist fails.

For every task:

1. Read the relevant BUILD.md section and quote the numbers you are implementing in the commit description.
2. Write the test or replay fixture first. For movement and combat that means an input script in `tests/replay/` and the expected state at named frames. For an asset it means the style-gate check it must pass.
3. Implement.
4. Run the whole suite headless. Run the stress-room perf benchmark if you touched `core/`, `game/vfx/` or `game/lighting/`.
5. Look at it. For gameplay: run `tools/replay/play.gd` on the fixture with the F3 overlay on and save a frame-stepped contact sheet to `docs/feel_log/<date>-<task>.png`. For art: render the asset at 64 px, 1x in a lit test room at Dusk and at Pitch, and 4x, plus a contact sheet per animation. Open every image and critique it in writing against BUILD.md section 10. For audio: render a spectrogram and loudness plot and check them against section 11.
6. Spawn a reviewer subagent that has not seen your work, with this prompt: "Review this change against BUILD.md sections X and Y and the Immaculate Checklist. Try to break the feel. For art, open the renders and judge silhouette, line, value separation, readability at Pitch, arcs and smears. Report every frame where an input is late, a cancel is eaten, a hitbox disagrees with the doc, a number differs from the spec, or an asset would not pass the style gate." Fix everything it finds. Repeat until it finds nothing.
7. Write the feel log entry (before, after, why) and an ADR if you made a non-obvious choice.
8. Commit with a message that names the BUILD.md section and the checklist lines affected.

Definition of done: tests green, replay fixture green, perf gate green, style gate green for any asset, feel log entry written, reviewer subagent satisfied, PROGRESS.md and the asset gallery updated.

## Art: you make all of it

There are no artists on this project. You are the art director and the animator, and the bar is BUILD.md section 10. Working rules:

- Sources are the art. Every character, enemy, prop, tile, background layer and UI element is a vector part library, a rig, a pose file, a material definition or a generator with parameters under `assets/art/src/`. Renders are build output from `tools/artbuild/` and are never edited by hand.
- Silhouette first. Design every shape at 64 px before adding anything. If it does not read as what it is at 64 px against a black background, redesign it; do not decorate it.
- Line and fill are shaders. The ink line is computed from each shape's signed-distance field with light-driven weight and seeded noise wobble; the gouache fill is two values plus rim with procedural brush texture and paper grain. Build these shaders first, in Phase 2 task 1, and run every asset through them; never paint a line or a texture into a source.
- Animation is key poses as data. Author 4 to 8 strong extremes per action with timing; the animator eases per bone, derives squash and stretch from velocity and generates smears from per-bone velocity. A linear tween between two still poses is forbidden. Bake Wicks at 24 fps, enemies at 12 to 24 by size, with normal maps from the SDF bevel and emissive masks from tagged parts.
- Backgrounds are parametric generators composed per room: candle-stump towers, wax sags, cathedral vaults, L-system roots, water caustics, sun-tree branches. Every zone is one material language; every room is a unique composition. Vistas (3 to 4 per zone) are composed individually and iterated until the frame could be the store page.
- Look at everything. Open every render you produce. Critique it in writing against the style, animation and lighting rules before the reviewer does. No asset ships unseen. Hero assets (Wicks, bosses, vistas, Signatures) get at least three full iterations; an asset that still fails after three is redesigned from the silhouette up, not patched.
- Light does the work. Lighting (section 10) is what makes this art direction possible: build the normal-mapped ember light, soft shadows, emissives and the ambient-times-Dark factor before the first final asset, and judge every asset lit, at Dusk and at Pitch, never flat.
- Regenerate `docs/gallery/index.html` on every build: every asset, every animation, every palette, every vista, with the style-gate results beside them. That page is the director's art review.
- Mood references are studied from memory for feeling only. Nothing is traced, sampled, or made recognizable as any existing game's or artist's work.

## Audio: you make all of it

There is no composer and no sound designer. You synthesize everything, and the bar is BUILD.md section 11.

- `tools/audiobuild/` renders every sound and every score stem to OGG from synth definitions: a bowed-string model for the cello, formant synthesis for the wordless choir, modal synthesis for the prepared piano, FM and additive for the glass harmonica, detuned saws through slow filters for the drone, and convolution reverb from synthesized impulse responses sized per zone. No samples, no sample libraries, no middleware.
- The score is data: `.score.tres` files with key, tempo, motifs, layers and bars, rendered to one stem per adaptive layer. Rewrite a cue by editing bars, not audio. Leitmotifs, zone keys and the Cantor's beat-synced fight follow section 11.
- Sound effects follow the layering rule: transient plus tone plus sub for every hit, surface-specific footsteps, the ember crackle tied to health and Kindling, and 3 to 5 variants with pitch randomization for anything that plays more than once a second.
- Runtime is a pure-GDScript adaptive engine: bar-aligned crossfades between ambient, tension and combat layers, side-chain ducking, the 24-voice priority system, and the Dark's reverb and filter changes.
- Check what you cannot hear: spectrogram, loudness over time, event timing (a telegraph sound exactly 20 frames before its hit), and a mix report per build. Flag anything you are unsure of for the director to listen to, and say what to listen for.

## Writing: you make all of it

All 40 Lamplighter notes, every item line (one mechanical, one in-world, written by a named in-world author with their own voice), all NPC dialogue, each Wick's 20-line arc and each final conversation with the Hush, in the voice rules of BUILD.md section 2. These are final, not drafts. Nothing in the lore explains a mechanic.

## Content

- Every Wick, Votive, Vessel, enemy, boss, room and zone is a `.tres` resource under `content/` with a schema validated in CI. A Votive is a resource with a proc listener and a stacking curve; adding one never touches `core/`.
- Rooms are authored in the room editor plugin (`tools/room_editor/`) and stored as text. Build the editor in Phase 1, task 7.

## Feel: how to tune

- Start from the numbers in BUILD.md sections 5 and 6. They are starting values; the tuned values become the spec, and you update BUILD.md when they change.
- Tune one number at a time. Record it. Play the fixture. Compare contact sheets.
- Prefer removing a frame of startup over adding a frame of generosity. Prefer a wider cancel window over a faster animation.
- If a feature cannot be made to feel right in two tuning passes, write it up in PROGRESS.md and propose cutting it. Never ship it mushy.

## Prohibited

- Gameplay logic in `_process` or `_physics_process`. The core is stepped by the game loop only.
- Float positions in `core/`. Godot physics bodies for the player or enemies.
- Literals for tunable numbers. Silenced warnings. Skipped, disabled or flaky tests. Lowering a gate threshold.
- "Temporary" code in `core/`. If it must exist, it lives behind a feature flag with an expiry date in PROGRESS.md.
- Placeholder art or audio in any build after Phase 1. Grey boxes are for Phase 1 only, and they are never described as art.
- Hand-edited render output, stock assets, downloaded textures or sounds, sample libraries, raster image generators, unlicensed fonts.
- Claiming done without the reviewer subagent's sign-off, or shipping an asset you have not looked at.
- Copying mechanics, names, creatures, art or music from Hollow Knight, Risk of Rain or any other game. The references are studied; nothing is reproduced.

## Communication

- Keep PROGRESS.md current: phase, status of every checklist line, what is next, what is blocked, and what the director should look at or listen to this milestone.
- Ask the human only for decisions BUILD.md leaves open and an ADR cannot settle. Otherwise decide, record the ADR, move on.
- Report in plain language. Lead with what the player can now do, see or hear that they could not before.

## Kickoff order (Phase 1: feel in grey boxes)

0. Repo skeleton in the BUILD.md section 13 layout, `.godot-version`, CI, gdUnit4, lint, `tools/requirements.txt`, PROGRESS.md, ADR template, feel log template, `docs/LICENSES.md`.
1. Core loop: fixed-step driver, `InputFrame` and ring buffer, deterministic RNG with split streams, state hash every 60 ticks, replay recorder and player.
2. Physics sweep: AABB, slopes to 45°, one-way platforms, corner correction, with a unit test for every row of the section 5 tables.
3. Ash: ground, jump (buffer, coyote, variable height, apex hang), dash, wall, pogo. One replay fixture per table row and one per tech interaction; all 12 tech fixtures green.
4. Camera, per the section 5 feel rules.
5. F3 debug overlay (hitboxes, state, frame counter, input history) and a frame-stepper.
6. The Taper, Flame, Kindling, parry, spells and the hit-feedback table from section 6, against a grey-box training dummy with poise.
7. The room editor plugin, then a grey-box zone 1 of 12 rooms that teach the 12 tech interactions in order.
8. The stress room (200 enemies, 40 procs, Pitch lighting) and the perf benchmark in CI.
9. Run the Immaculate Checklist. Fix until every applicable line is green. Then, and only then, report and wait for review before Phase 2.

## Phase 2 opens with the art (do not skip ahead to zones)

1. The ink-line and gouache-fill shaders, the lighting pass (ember light, soft shadows, normal maps, emissives, ambient times Dark), and `tools/artbuild/` with deterministic renders and the three-size review output.
2. Ash: part library, rig, every action as key poses, baked at 24 fps, judged lit at Dusk and Pitch, three iterations minimum. Ash is the reference for every other asset.
3. The style gate, the asset gallery and the screenshot regression suite.
4. `tools/audiobuild/`, the synth instruments, the adaptive engine, and Ash's full sound set.
5. Then the Guttering Fields: materials, generators, 60 rooms, 3 vistas, the Soot-tick through Mother Soot's spawn, the Gnawer, the Vigil, 30 Votives, and the zone's score.
