# 2026-10-21: Phase 2 task 1, the review's findings fixed at their roots

- Author: Claude
- BUILD.md section and table row: section 10, Style (two values, the ember), Lighting, Animation (smears), Pipeline (Review); section 8, The Dark
- Fixture(s): none (presentation only; the core and every golden hash are untouched)
- Contact sheet: `docs/feel_log/2026-10-21-art-pipeline-fixes/` (stump at the top level, `probe/`, `zone1/`); the before is `docs/feel_log/2026-10-20-art-pipeline/`. `zone1/room01_dusk.png` and `room01_pitch.png` are deleted: they showed an empty world (the room id `zone1/01` does not exist and `render.sh` drew it anyway) and are replaced by the fix2b pictures of `zone1/01_dash_slash` in `docs/feel_log/2026-10-21-fix2b-tools/`.

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `lit_threshold` (now N.L of the form direction) | 0.20 (irradiance) | 0.5 | N.L |
| `terminator_soft` | 0.03 | 0.04 | N.L |
| `form_elevation_deg` (new) | none | 40 | deg |
| `DEFAULT_BEVEL_U` / max | 3 / 8 | 8 / 16 | u |
| `light_r_u` | 8 | 14 | u |
| `wobble_u` | 0.22 | 0.32 | u |
| `bloom_radius_px` to `bloom_radius_u` | 14 px | 14 u | |
| glow (new): share, min, strength, falloff | none | 0.05, 3 u, 0.5, 2 | |
| smear opacity, tail power (new) | none | 0.85, 1.5 | |
| gloss power, strength (new) | none | 24, 0.7 | |

Several numbers moved together because the findings were one fault seen from several sides; each is one line of `content/`. The reasons are ADR-0026.

## Why: each finding, the measurement and the picture

**H1, no surface showed two values.** The probe's head row at Dusk (`probe/dusk1x.png`, y 274): lit 222 across the face, then a step to 160 to 153 and the ink at 40. The robe: lit 142 to 173, then 60 to 49 at the right edge. Before: 236 to 243 flat, then a 2 px band. The terminator is now where the surface turns from the light, a diagonal crescent on the head and a hem shadow under the robe. It does not move with distance (a test puts the ember at 50, 80 and 130 u at Pitch and the step stays within 0.15 radii). Bevel 8 and the 40 degree floor did it.

**H2, no figure and ground at Pitch.** The robe is 93.6 against the wall at 45.0 (before 42 against 52). It holds 64% of its Dusk value at Pitch (before 27%). The head is cream-orange with a shadow crescent on the right, not a flat orange disc.

**H3, the ember.** 1x core (236, 178, 101) at Pitch, (254, 203, 136) at Dusk: warm white, no dark ring (the pixels beside it read 111 to 143 against a robe of 93), and a halo of about 20 u that tints the wall and the body. The 4x picture (`probe/detail4x.png`) shows the same halo at the same size in u, not a quarter of the game's width. The candle's flame has a halo and lights the wall and floor at Pitch (`pitch1x.png`).

**H4, the smear.** In `probe/swing.png` frame 1 the ribbon is solid at the blade, fades toward the tail, has a hairline that thins out and no closed outline. It still reads as a fan from its straight end; the pose file, not the shader, decides its arc, and Ash's swings get three passes in task 2.

**H5, backgrounds.** The review room is now painted: a far wall, three pillars, walls, ledge and crate drawn through `ink_background`. The line is open (whole along 60% of the ledge's edge, thinned along 40%) and is gone where the ember is (0 of the edge keeps it); the wall is brushed along its axis and grained. Looking at `dusk1x.png`: the storybook reads. The crate and the ledge are still simple slabs; real tiles are Phase 2 task 5.

**M1 to M3, L1 to L7.** The line light returns strength 0 beyond every light (test: ink on the lit side is 0.7 or more of the shadow side's at no light, under 0.6 with the ember near). Hairlines at 1x draw at 37% (lit side keeps 0.96 of the fill, shadow side 0.22). The flame is a fire light. The neck highlights are gone (re-read at 8x). Shadow edges are softer (`light_r_u` 14) and the line boils a little more (0.32 u). The floor lens is gone with the painted floor. The probe blade is 3.7 u at the base; the candle's drip is a 5 u bulb that breaks the 64 px outline (`sil64.png`). The grey boxes keep their hue: Ash is blue at Pitch, not green (`zone1/ash_1x_pitch.png`, Phase 1 only).

**F1 to F7.** The layout test names the real constant; the shading maths are pinned (below); tunable literals are in `content/`; a shown room whose field is not baked has no walls; fields are evicted; the sheet reader rejects bad pages, ticks, fps, rects and loop; the manifest hashes pixels. F4 (the unit stage timeout) is below.

## Tests that pin it (each mutated and caught)

`run_form_render_tests.gd` (27): the carrier skipped at Pitch, the smear's alpha off, hairlines at full strength, the line strength forced to 1, the ember's ring back, a per-channel shoulder, and the elevation floor off each fail one of them. `run_ink_render_tests.gd` compares shader mode 4 (the wobble) with a CPU twin: the first octave's weight set to 0.2 fails (worst 0.31). `gpu_check.gd` holds a flat surface at 60, 150 and 300 u to the maths within 0.1% (0.1694 against 0.1695) and a wall bevel within 0.4%; tilt 0.2 and flat share 0.6 each fail, and so does dropping the unbaked-room binding. `ci/lighting.sh` fails if the flame does not light its wall.

## How it plays now

Nothing the player holds changed. A Wick is readable at Pitch; the ember is a warm point with a halo; the zone 1 grey boxes keep their function colours in the dark.

## Open questions for the director

The head question was not answered by the director (their "close that line" referred to the Phase 1 frame-time line). The lead decided it under review finding H2: a Wick keeps its lit value at Pitch, from the key's direction, so its body stands off the wall its own ember lights; the crescent therefore does not move as the ember moves around the Wick. The director approved starting on the art, so Ash is next. Still worth a look: `probe/detail4x.png` for the line weight (heavy side 1.3 u, one number), and `probe/swing.png` for whether the ribbon's fade toward the tail is the motion you want (`smear_opacity`, `smear_tail_pow`).
