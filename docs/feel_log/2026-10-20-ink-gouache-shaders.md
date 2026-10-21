# 2026-10-20: Phase 2 task 1, the ink-line and gouache-fill shaders

- Author: Claude
- BUILD.md section and table row: section 10, Style ("Ink line as a shader", "Gouache fill as a shader"), Lighting ("Every sprite ships with a normal map and an emissive map", "ambient"), Pipeline ("Review": three sizes); ADR-0023 Decisions 2 and 7.2
- Fixture(s): none (presentation only; the core and every golden hash are untouched)
- Contact sheet: `docs/feel_log/2026-10-20-ink-gouache-shaders.png` (regenerate with `ci/render.sh --review <dir>`)

## Change

First implementation of the shaders half of ADR-0023, on the probe figure and stage built in GDScript at the ADR's channel layout (tools/artbuild/ is another builder's). One number moved from the ADR's starting values:

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `brush_noise` (`wane_fill.z`, how far the brush noise moves the terminator) | 0.10 | 0.05 | irradiance |

Every other number is the ADR's starting value, unchanged: line 0.3 u lit and 1.3 u shadow, at least 0.8 px; wobble 0.22 u at 10 u and 4 u waves, reseeded at 12 Hz from the tick; lit threshold 0.20 (soft 0.03); brush streaks 14:1, value 12%; edge darkening 22% within 1.0 u of the line; paper grain 7%; rim 1.2 u. They live in `content/art/ink.tres` (`InkTuning`, validated by the content stage) and reach the shaders as global parameters.

## Why

Looked at the renders (probe figure and stage, Dusk and Pitch at 1x, Dusk and Pitch at 4x, the 64 px silhouette, the channel view) against section 10:

- Silhouette first: the figure reads at 64 px (head, wick, blade, arm), and the 1x and 4x sheets agree on the silhouette to 2% of its area.
- Ink line: heavy on the side facing away from the key (about 1.3 u, 5 px at 4x), a hairline on the lit side (one pixel at 1x, the 0.8 px floor), tapering at the wick and the blade tip, never lighter than the fill it covers. Measured on a head at 4x: 1 px on the lit edge, 5 px on the shadow edge, the same with the sprite mirrored; the wobble moves nothing but the edges between boil steps (checked pixel by pixel against the baked distance field).
- Gouache fill: two values with a brush-edged terminator (the head's lit upper left and shadow crescent), streaks along each part's own axis (horizontal on the head, vertical on the body, along the blade), rim under the lit edge, paper grain at screen scale. On the stage, the ember's pool breaks into a dry-brush edge on the floor and the ledge. At the ADR's 0.10 the terminator broke into saw teeth tens of pixels long where the light falls off slowly (a 0.1 swing against a 0.20 threshold); at 0.05 it still reads as a brush and no longer as a saw. One number, one change.
- The ember carries no ink (it is a light; with ink it read as a button); the rim starts under the line, not under the silhouette (on the lit side the line covered most of it).
- Pitch: the world is the ember. Ambient alone at Pitch is 0.15 of Dusk's (measured on the HDR image, 0.10 to 0.25 allowed); the ember is white-hot at both.

What is not judged: the probe is test data, not art; its palette is test colours; the ember is a flat white disc until the post pass blooms it; shadows are the lighting builder's. The light here is a stub (`shaders/lighting/light_common.gdshaderinc`) with one ember and the room's key, until the lighting builder's file replaces it.

## How it plays now

Nothing in the game changes yet: the game still draws grey boxes through the Phase 1 stand-in lighting, and no sprite uses these shaders until task 2 (Ash) and the lighting builder land. `ci/render.sh` runs 28 render checks under xvfb (determinism, the boil, the silhouette against the bake, the line against the light, Pitch, instance values on one shared material, scale agreement, the tuning reaching the shader); 14 headless cases check that both shaders compile, every global is declared, nothing reads a clock, and the sheet and sprite lay a frame out as the ADR says.

## Open questions for the director

- Look at the contact sheet's top row: is the line weight right (a hairline on the lit side, 1.3 u on the shadow side)? It is the first thing the art direction hangs on, and it is a one-number change in `content/art/ink.tres`.
- The terminator on the floor (top row, left of the figure) is a dry-brush edge. If it reads too ragged, `brush_noise` is the knob; if it reads too clean, raise it back toward 0.10.
