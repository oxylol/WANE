# ADR-0026: Light the form, not the distance; draw every light's halo; make the smear a ribbon

- Status: Accepted
- Date: 2026-10-21
- BUILD.md sections: 10 (Style: two values and the ember; Lighting; Animation: smears; Pipeline: Review), 8 (The Dark)
- Checklist lines: Graphics and feel "Every attack has a smear frame", "At Pitch ambient, the ember's light reveals a Clinger 30 frames before it drops"; CI rows "Screenshot regression", "Style gate"

## Summary

- The two values follow the shape: lit where a light reached the surface and N.L of the form direction passes `lit_threshold` 0.5 (Decision 1).
- The form direction is the light's direction at the elevation it really has, never under 40 degrees (`form_elevation_deg`): a flat surface is lit alike at any distance (see Decision 1).
- A Wick is lit by its own ember from the key's direction, so at Pitch it keeps its lit value and stands off the wall (see Decision 2).
- Every light draws a halo in world units (`game/lighting/light_glow.gd`, 5% of its reach, min 3 u); an emissive and the part around it carry no ink (see Decision 3).
- The post shoulder rolls off brightness, not channels, so the ember stays orange; the bloom radius is in u and its taps follow the zoom (see Decision 3).
- `wane_line_light` returns direction and strength (0 beyond every light); a line thinner than `line_min_px` draws as light as it is thin (Decision 4).
- A smear's taper channel is its age along the arc: the fill fades and the line thins toward the tail; gloss is read as a highlight (see Decisions 5 and 6).
- Default bevel 8 u (max 16); every tunable literal of the shading is in `content/` (`wane_shape`, `wane_gate`, `wane_ink_extra`); the review draws a painted backdrop (Decision 7).

## Context

The independent review of Phase 2 task 1 found that no surface showed two values (the shadow was a 1 u band under the line), that at Pitch a Wick's body was as dark as the wall behind it, that the ember was a white square with a dark ring and no bloom at 1x, that the smear was a solid object with a closed outline, that no picture showed a background through the ink shaders, and that tests did not pin the shading. The causes were in the shaders, the bake and the light, not in taste. ADR-0023 Decision 2 and the shaders addendum said "N.L included in the irradiance" and "a unit direction": both made the two-value choice depend on distance.

## Decision

1. **Form lighting** (`wane_key_lit`, `shaders/lighting/light_common.gdshaderinc`). For each light, presence = its energy x attenuation x visibility (before N.L). A surface is lit by it if presence passes the gate (`gate_lo` 0.05 to `gate_hi` 0.15) and `dot(n, L) + jitter` passes `lit_threshold` (0.5, `terminator_soft` 0.04, jitter = brush noise). L is the in-plane direction to the light at elevation `max(real elevation, form_elevation)`; the room key is one more light, scaled by the Dark. A surface facing the viewer reads sin 40 = 0.64, above the threshold, wherever it is; only a tilt away from the light falls to shadow. Distance does its work in `wane_radiance`, the continuous multiplier.
2. **Carriers.** A sprite with `carries_ember` is lit by its own ember with presence = the ember's energy, from the key's direction: the ember is at the sprite and has no direction of its own.
3. **Halos and post.** `LightField` draws one additive quad per light (`glow.gdshader`): radius `glow_radius_share` 0.05 of reach, at least `glow_min_u` 3, strength `glow_strength` 0.5 x energy, falloff power 2. `ink_shade` suppresses ink and edge darkening within the ink's reach of an emissive texel (four taps of the emissive channel) and replaces the fill under an emissive with its colour. The post pass preserves hue above `shoulder_knee` 0.8, takes `bloom_radius_u` (14 u) and picks its mip level from the radius in pixels. The mip bloom needs a source of some size; the halo is what a few-pixel ember gets.
4. **Line light.** `wane_line_light` returns (direction, strength): the strongest light's direction (the key's for a carrier) and its gate. Strength 0 beyond every light draws the heavy line all round. `line_min_px` floors the width, and a line under it draws with coverage w / floor, so a 0.3 u hairline at 1x is a 37% ink line, not a black pixel.
5. **Smear ribbon.** artbuild writes each smear edge's age along the arc (0 tail, 1 the blade) into the parts taper channel (B); the shader (flag bit 3, `INK_FLAG_SMEAR`) scales the alpha by `smear_opacity` 0.85 x age^1.5 (`smear_tail_pow`), draws the hairline, thins it with age and omits the rim and the second value.
6. **Gloss.** `normal.a` drives a highlight where N is near the half vector of the line light and the viewer: `gloss_power` 24, `gloss_strength` 0.7.
7. **Sources and review.** `DEFAULT_BEVEL_U` 3 to 8 (max 8 to 16): a part of a Wick's size is rounded through. The review draws `tests/art/src/lit_test_room` (far wall, pillars, walls, ledge, crate) through `ink_background` and turns a prop's emissive regions into fire lights. Tunable literals moved to `content/lighting.tres` (`flat_share`, `bevel_tilt`, `form_elevation_deg`, `up_only_soft_u`, gates, post weights, vignette shape, flicker phase) and `content/art/ink.tres`. `light_r_u` 8 to 14 (a softer penumbra); `wobble_u` 0.22 to 0.32.
8. **Tests.** `tests/screenshot/run_form_render_tests.gd` (27 checks on the review's pictures), the wobble's CPU twin (shader mode 4) in `run_ink_render_tests.gd`, the flat-surface and bevel radiance against CPU maths and the unbaked-room binding in `tools/lighting/gpu_check.gd`, the flame-lights-its-wall check in `ci/lighting.sh`. Each was mutation-tested: the mutant failed.

Also: an unbaked shown room binds the field of no walls until its own is baked; `LightField` keeps at most `fields_kept` (16) room fields; `SpriteSheet` rejects a page, ticks, fps, rect or loop that lies; the artbuild manifest hashes a PNG by its pixels, so another zlib is not a mismatch; the grey boxes keep their hue in every light (`keep_hue`, Phase 1 only). Known and left: the bake's `get_image()` read-back is synchronous and can cost a frame (it needs a GPU to measure); the geometry still uses libm trig (the pins in `tools/requirements.txt` stand).

## Alternatives considered

| Option | Why not |
| --- | --- |
| Raise `lit_threshold` and keep irradiance | The terminator stays a distance ring around the ember. |
| Bloom at a lower threshold for the ember | A few pixels averaged into an 8 x 8 block fall under any threshold that leaves lit skin unbloomed. |
| Ember halo baked into the sprite | Light is a pass, not paint (CLAUDE.md); a halo must follow zoom and flicker. |
| Smear alpha from a new texture channel | The taper channel was free for a smear's edges and already read per pixel. |

## Feel reason

Form is what the light reveals; a Wick that stays readable at Pitch keeps the dark playable; the ember as a soft bloom is the player's cursor.

## Consequences

Ash starts from these defaults (bevel 8, form lighting). The Wick's shadow crescent is a fixed style: it comes from the key, so it does not move as the ember moves round a carrier. The glow adds up to 16 quads a frame. ADR-0023's irradiance wording is superseded by Decision 1 here.
