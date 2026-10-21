# 2026-10-20: Phase 2 task 1, the art pipeline's design and its spike

- Author: Claude
- BUILD.md section and table row: section 10, Style (ink line, gouache fill), Lighting (ember 420 u, 2400 K, 0.5 Hz ±4%; ray-marched soft shadows; ambient × Dark, 0.15 at Pitch), Pipeline (4x bake, three-size review)
- Fixture(s): none (presentation only; the core and every golden hash are untouched)
- Contact sheet: `docs/feel_log/2026-10-20-art-pipeline-spike.png`

## Change

First design, with no tuned number changed. The decisions are in ADR-0023. Its numbers (line 0.3 to 1.3 u, wobble 0.22 u at 10 u and 4 u wavelengths, lit threshold 0.20, skin 14 u, light radius 8 u for the penumbra) are the spike's starting values, to be tuned one at a time by the shader and lighting builders.

## Why

The ink line has to follow the ember, so the shape is baked as distance fields and the line, the fill and the light are drawn live. The spike proved the risky parts before three builders start: SVG to exact distance fields (deterministic, matching cairosvg), a light-weighted line, normal-mapped two-value fill, and ray-marched soft shadows against the collision layer. Each was rendered headless under xvfb and timed.

The sheet, row by row (1x crops are 800 x 560 of the 1920 x 1080 view):

1. Dusk at 1x; Pitch at 1x. The ember's pool, the ledge's shadow above it, the pillar's shadow to the right, the crate's long shadow to the left; the wall faces turned to the ember carry a lit skin, their interiors stay black. At Pitch the world is the ember.
2. Pitch through Godot's canvas SDF (indistinguishable from row 1, right); the visibility buffer itself (R visibility, G march steps), where the penumbra widens with distance from each occluder.
3. Pitch with the buffer at half scale (indistinguishable at 1x); the probe at 4x, Dusk and Pitch; the 64 px silhouette at 4x and at 1x. The probe is a test figure for the pipeline, not an asset, and is not judged as art.

## How it plays now

Nothing in the game changes yet. The game still runs on the Phase 1 stand-in lighting until the lighting builder replaces it.

## Open questions for the director

- The Dark factor: BUILD.md section 8's `max(0.15, 1 − 0.09 (D − 1))` puts Pitch at 0.86 ambient, not section 10's 0.15. ADR-0023 uses a slope of 0.53 (Pitch at 0.15 from D = 2.6). Confirm, or give the curve.
- Look at row 1: is this the falloff and the darkness you want at Dusk and at Pitch? The violet at Dusk is the zone 1 ambient times 1.0, before any tuning.
