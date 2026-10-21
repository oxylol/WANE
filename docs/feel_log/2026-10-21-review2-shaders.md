# 2026-10-21: Phase 2 task 1, review 2: the shaders and the lighting

- Author: Claude (the shaders and lighting fixer of the second review)
- BUILD.md section and table row: section 10, Style (the ember: "a soft bloom over the ink"; the art is "resolution-independent"; the pressure taper; two values), Lighting (Beacons, fire, the Ember in the Gutter "the only light that casts up"; "At Pitch, ambient is 0.15 and the world is the ember"); section 8, The Dark
- Fixture(s): none (presentation only; `core/` and `tests/replay/golden_hashes.txt` are untouched)
- Contact sheet: `docs/feel_log/2026-10-21-review2-shaders/` (before and after pairs; the decisions are ADR-0026's addendum of today)

## Change

One number moved into content; no tuned number changed.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `wall_bevel_u` (`content/lighting.tres`, was a literal in `lit_flat.gdshader` and `gpu_check.gd`) | 6 | 6 | u |
| `wane_view.zw` (a global's meaning, not a number) | u per canvas pixel | the view's size in u | |

## Why: each finding, the measurement and the picture

**T1, the bloom's reach followed the window.** The post pass turned `bloom_radius_u` into pixels of the 1920 x 1080 canvas and then stepped in the output's own pixels. `bloom_outputs_before.png` (one 40 u emissive at 960 x 540, 1920 x 1080 and 2880 x 1620, the same 160 x 80 u of world each): at 960 x 540 the glow is a faint ring 27 u out; at 2880 x 1620 a tight 9.7 u rim. After (`bloom_outputs_after.png`): 13.0, 14.5 and 14.3 u, the same soft halo three times; the 960 x 540 one is a little blockier, as its mip blocks are 2 u. The project's default window is 1280 x 720, so the game as shipped had the long faint bloom.

**T12, the ember turned yellow.** The shoulder kept the hue in HDR, but a red above 1 clipped alone on its way to the screen. `ember_core_pitch_post_before.png`: at Pitch, post on, the chest around the ember and the hand are butter-yellow, the core a yellow blob. After: the robe stays orange, the core is the palette's peach (`#ffbe78`) at full value, hue within 0.01 of what it was before the post pass (g/r 0.710 against 0.717). The same clip turned the candle's wax yellow (`stump_flame_4x_before_after.png`, left yellow, right orange as a 1800 K flame lights it) and Ash's blue box cyan beside the ember at Dusk (`ash_box_before_after.png`: cyan, blue; at Pitch blue either way). Only those pixels moved: rooms 01 and 05 rendered before and after differ in 700 to 864 pixels, all on Ash's box.

**T3, three shadow channels were never rendered by a check, and one was broken.** Holding channels G, B and A to the twin found that the Gutter Ember's channel had four levels: an opaque viewport's target on GL Compatibility is RGB10_A2, so alpha has two bits (buffer A was 0.087 off the twin in its penumbra, 94 points off by more than 0.1). `gutter_shadow_pitch_before.png`: the red light's shadow edge behind the pillar steps; after, it is soft. The buffer is now transparent (RGBA8) and all four channels are within 0.0001 mean, 0.001 to 0.002 in their penumbras, read at the texels' centres. Each kind of light now lights a grey surface as the maths say through its own channel, and the Gutter Ember lights 0.174 above itself and only ambient below.

**T4, the key and the carrier.** `key_values_dusk_pitch.png` draws the two-value choice (shader mode 5) of a figure beyond every light: white where it faces the key at Dusk, 0.16 grey at Pitch, the key's strength times the Dark through the gate. `carrier_values_pitch.png`: a Wick's two values with its ember 30 u left, at its chest and 30 u right are the same picture (mean change 0.000), the crescent on the side away from the key.

**T5 and T6, nothing pinned the post pass, the taper, ink under fill or the smear's value.** They are pinned now (below). `smear_lit_age_value.png`: the swing frame lit at Dusk; the same with only the age able to thin the line (the outer edge thins toward the tail, 27 dark pixels against 222 at the blade end); and the smear's two values at Pitch, white over the ribbon while the figure is 0.16 grey.

**T10.** `wall_bevel_u` is content; the unit test checks that the tiles' material carries it.

## Critique of the pictures (BUILD.md section 10)

- Bloom: soft and round enough at 1x; at 960 x 540 its corners show 2 u blocks, invisible at play distance.
- The ember at Pitch (`probe_pitch_post_1x_after.png`): a peach point with an orange halo, the figure stands off the wall, the head keeps its crescent. It is less white than before; the "white" of "orange-white" is now the palette's choice, not a clip. Look at it.
- The candle (`stump_pitch1x.png`, `stump_dusk1x.png`): the flame reads as the brightest shape, the wax is the flame's orange, the pillars throw long soft shadows at Pitch and the backdrop's open line drops out near both lights.
- The Gutter Ember's light (`gutter_shadow_pitch_after.png`, 3x): faint contour lines radiate through its own light. They are the march's samples close to a light that stands 10 u above a floor (the twin draws them too). Not fixed here (ADR-0026 addendum, Known and left).
- The smear (`smear_lit_age_value.png`, left): the fill shows only on the blade's side of the fan, the half nearest the tail edge is empty and the tail edge is a dotted hairline, so the fan reads as a V, not a ribbon fading along its arc. Cause: artbuild writes each pixel the age of its nearest visible edge. Not a shader fix; reported to the lead for the artbuild owner.

## Tests that pin it (each mutated and caught)

`tools/lighting/post_check.gd` (in `ci/lighting.sh`): bloom reach at three outputs, `bloom_radius_u` doubled gives 1.83 times the reach, `bloom_strength` halved gives 0.500 of the bloom, nothing under `bloom_threshold`, the vignette within 0.0004 of its maths at six points, grain spread 0.00342 against 0.00346 and a new seed each boil step (correlation -0.009), the ember's colour past the shoulder at six gains within 0.01. `gpu_check.gd`: four channels and their penumbras; Beacon, fire and Gutter Ember shading through their own channels; the Gutter Ember's up-only edge. `run_form_render_tests.gd` (36 checks): the key times the Dark, the carrier's crescent, the ember's hue, the line at Pitch (7 px against 9; 2 when the key ignores the Dark), ink at most 0.48 of the fill at Pitch (2.03 when the ink ignores the fill), the smear's single value and its thinning with age. `run_ink_render_tests.gd` (32): the blade's taper (head untouched). Mutants killed: the channel swap, the flag decode with `& 1`, the up-only edge flipped, the penumbra's smoothstep removed, the opaque buffer, the bloom in canvas pixels, the bloom off, the vignette off, its squash, the grain without the boil, the hue clamp removed, the key's gate and the line light without the Dark, the carrier lit from its ember's direction, ink not held under the fill, the smear's `lit = 1` removed, the smear's width rule removed, the taper removed.

## How it plays now

Nothing the player holds changed. On the default 1280 x 720 window, and at 4K, the ember's bloom is the size it is at 1080p. Near a strong light colours keep their hue: the ember and the candle stay orange, Ash's box stays blue. A Gutter Ember's shadows are as soft as the ember's.

## Open questions for the director

- Look at `probe_pitch_post_1x_after.png` and `ember_core_pitch_post_after.png`: is the peach core the "orange-white point" you want? Whiter means a lighter palette emissive, not a clip.
- At Pitch the room key still lifts a surface beyond every light to 0.16 of its lit value (`key_values_dusk_pitch.png`, right). For none at Pitch, `key_strength` 0.33 or less (or `gate_lo` 0.075) does it; one number, your call.
- The smear's shape (`smear_lit_age_value.png`, left) and the Gutter Ember's contour lines are open (ADR-0026 addendum).
