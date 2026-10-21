# ADR-0023: Bake shapes as distance fields offline, and draw ink, gouache and light in canvas shaders

- Status: Accepted (the architecture, proved by the spike below); Decision 3.5's slope is in BUILD.md section 8 (the lead's decision; the director may pick another curve: addendum of 2026-10-21)
- Date: 2026-10-20
- BUILD.md sections: 10 (Style, Lighting, Animation's baking line, Pipeline), 8 (The Wane Clock's ambient row, The Dark), 13 (Layers, Frame budget, Testing and CI), 12 (Performance targets)
- Checklist lines: Graphics and feel "At Pitch ambient, the ember's light reveals a Clinger 30 frames before it drops", "The ember's flicker is visible on nearby normal-mapped surfaces as the player walks", "Every enemy is identifiable by silhouette alone at 64 pixels tall", "The game holds 60 fps in the stress room on the Deck profile with the lighting pass on"; CI rows "Screenshot regression" and "Style gate"

## Summary

- `tools/artbuild/` evaluates posed SVG parts exactly into 3 RGBA8 atlases per scale (shape, normal, parts); 4x masters, ships 1x and 2x (Decision 1).
- shape = signed silhouette SDF, unsigned visible-edge distance U, front-side flag, emissive; a signed line field drew seams (see Decision 1.3, Spike).
- Light- and time-dependent work is in canvas shaders: line weight, wobble, taper, open lines, two values, rim, brush, grain (see Decision 2).
- Shaders read light only from `wane_*` global shader parameters and are all `unshaded`; Light2D and CanvasModulate leave the game (Decision 3).
- Shadows: a world-space room SDF, baked once per room on the GPU, marched into a screen-space buffer at 1.0/0.75/0.5 scale, up to 4 casters (Decision 4).
- Godot's canvas SDF is rejected by measurement: it rebuilds on every panning frame, is screen-space only and has no CPU twin (see Decision 4.6).
- `ShadowTwin` (GDScript bake and march) matches the GPU buffer to a mean 0.0003, so the Clinger line becomes a headless test (see Decision 4.5).
- `tools/artbuild/review.gd` under xvfb renders the 64 px silhouette, 1x Dusk and Pitch, the 4x detail and a contact sheet per action (Decision 5).
- Determinism: integer-hash noise, pinned tools, a manifest check; two builds and two llvmpipe renders were byte-identical (see Decision 6).
- ADR-0026 revises how the two values, the carrier, the line light, the smear and the ember's halo work (form lighting, glow); read it with Decisions 2 and 3.
- Three parallel builders (artbuild, shaders, lighting) with fixed files and names; the Dark slope 0.53 is in BUILD.md section 8 (Decisions 7, 3.5).

## Context

BUILD.md section 10 is the brief. Style: "Outlines are never drawn. They are computed from each shape's signed-distance field: weight driven by the light direction (thick on the shadow side, hairline on the lit side), a two-octave noise wobble along the edge so no two frames of line are identical, and a pressure taper at shape ends. Characters get a closed line; backgrounds get an open, broken line that drops out where light hits." "Two flat values per surface (lit and shadow) plus a rim, with a procedural brush texture (directional streaks aligned to the shape's major axis, tiled noise, slight edge darkening where fill meets line) and screen-space paper grain. No gradients in source; all gradation comes from the lighting pass."

Lighting: "Every sprite ships with a normal map and an emissive map"; "the player's ember (radius 420 u at base, warm 2400 K, flicker at 0.5 Hz with ±4% amplitude), Beacons (cool white, huge), enemy eyes (point lights, tiny), fire (orange, animated), the Ember in the Gutter (red, the only light that casts up)"; "2D ray-marched soft shadows from the ember against the collision layer. Shadows are the game's depth cue and its horror cue: a Clinger is a shadow before it is a sprite"; "a per-zone ambient color multiplied by the Wane Clock's darkness factor (section 8). At Pitch, ambient is 0.15 and the world is the ember."

Pipeline: "`tools/artbuild/` renders sources through the ink and gouache shaders at 4× native (4K-ready from day one), downsamples to 1080p native with a nearest-plus-bicubic hybrid that keeps the line crisp, packs sprite sheets with metadata JSON (hitboxes, hurtboxes, pogo boxes, emissive regions, smear flags) and writes normal and emissive maps. Noise is seeded, so builds are deterministic and screenshot regression works." Review: "every asset renders at three sizes (64 px silhouette, 1× in a lit test room at Dusk and Pitch, 4× detail) plus a contact sheet per animation."

What the doc leaves open, or gets wrong:

1. **What is baked and what is live.** The doc says sources are rendered "through the ink and gouache shaders" offline, and also that line weight follows the light direction and the wobble changes every frame. A baked line cannot follow a moving ember. Decision 1 and 2 split the work: the shape is baked, everything the ember or the clock touches is live.
2. **The Dark factor contradicts itself.** Section 8's table: ambient `base × max(0.15, 1 − 0.09 × (D − 1))`. That is 0.86 when Pitch begins (D = 2.6) and reaches 0.15 only at D = 10.4, but section 10 says "At Pitch, ambient is 0.15", and section 8 itself says "by D = 4 only the player's ember and enemy eyes are visible". Decision 3.5.
3. **Which SDF the shadows march.** "Against the collision layer" admits Godot's canvas SDF (LightOccluder2D `sdf_collision`, `texture_sdf()`) or our own; the task asked for a choice by measurement. Decision 4.
4. **Renderer.** ADR-0001 Decision 4 left GL Compatibility to be "re-measured against Mobile in the stress room" in this task. This container has no Vulkan driver (`mesa-vulkan-drivers` has no candidate; no lavapipe), so Mobile cannot be run here, and CI renders on GL under xvfb (llvmpipe). Decision 3.6.
5. **The Phase 1 stand-in** (`game/lighting/`, ADR-0020 part B: a `PointLight2D` with PCF shadows from merged `LightOccluder2D`s and a `CanvasModulate` at 0.15) is replaced.

Units: 1 world unit u is 1 px at 1080p (the camera has no zoom); Ash's collider is 20 x 44 u; a tile is 32 u.

## Decision

### 1. What `tools/artbuild/` bakes

1.1 **Sources** (`assets/art/src/<asset>/`): `parts.svg`, the part library; `rig.tres` and `<action>.pose.tres` (task 2, the animator); `palette.tres`; generator parameters for backgrounds. One SVG user unit is 1 u. The SVG is a lint-checked subset: `path` (M L H V C Q Z, absolute and relative), `circle`, `ellipse`, `rect`, `polygon` and `g` with `transform`. Each part is one element with `id` (the part name), `data-z` (draw order), `data-pivot` (x y, for the rig), `data-tags` (any of `emissive`, `blade`, `eye`, `pogo`, `wax`, `smear`), and optional `data-bevel-u` (default 3) and `data-tilt-deg` (default 62). Fills, strokes and gradients in the SVG are ignored and rejected by the lint: colour comes from the palette, line and grain from the shaders (CLAUDE.md: "never paint a line or a texture into a source").

1.2 **Geometry.** Parse, apply the frame's pose (per-part affine from the animator; a smear is the union of the part at sub-frame poses along its arc), flatten curves to 0.01 u, split edges to 0.25 u for the visibility test. Every channel is then evaluated **exactly at the pixel centres of each output scale**, in float64 numpy:
- each part's signed distance (exact distance to its segments; sign by nonzero winding);
- the **silhouette edges**: segments not inside any other part;
- the **visible edges**: segments not covered by a part with higher `data-z` (the silhouette plus every interior overlap, such as an arm over the body).

The search is banded: per 16 x 16 px tile, only segments within the channel's range (8.5 u for S, 16.5 u for U) are tested. The spike measured it identical inside the band and 36 times faster than brute force.

1.3 **Channels and packing.** Three RGBA8 PNG atlases per sheet per scale, plus a palette:

| File | Sampled | R | G | B | A |
| --- | --- | --- | --- | --- | --- |
| `<asset>@<s>x.shape.png` | linear | S: silhouette SDF, signed, outward positive; byte = 128 + 16·d, d in u, range −8 to +7.94 u, step 1/16 u | U: distance to the nearest visible edge, unsigned; byte = 16·d, range 0 to 15.94 u | side: 255 where the pixel lies in the part that owns that nearest visible edge (the edge's front side), else 0 | emissive coverage of `emissive`-tagged parts, 0 to 1 |
| `<asset>@<s>x.normal.png` | linear | bevel normal x | bevel normal y (y down) | normal z (toward the viewer); encoding 0.5 + 0.5·n | gloss (palette material; wax is high) |
| `<asset>@<s>x.parts.png` | nearest | part index into the palette, 0 = none | brush angle: the part's posed major axis, 0 to π as 0 to 255 | pressure taper of the nearest visible edge, 0 to 1 | flags: bit 0 pogo, 1 blade, 2 eye, 3 smear ribbon, 4 wax |
| `<asset>.palette.png` | nearest | 16 columns (part index); each palette variant is 4 rows: lit value, shadow value, rim, emissive colour (alpha = emissive strength). sRGB; the shader samples it with `source_color` | | | |

The normal is the part's own bevel: `tilt = data-tilt-deg × (1 − clamp(depth / data-bevel-u))`, tilted toward the part's outward distance gradient, so each limb reads as a rounded slab and the ember rakes along its edges. A hero asset may override it per part with authored normal parts (`data-normal="bulge|flat|crease"` profiles), which is the "painted, not generated" correction. The taper is the part's half-thickness found by walking inward from each visible edge (the spike walked 24 steps of 0.25 u), divided by 2.5 u and clamped: thin at blade tips and fingers, full on the body.

U plus a side flag, not one signed line field, because the signed field P (negative on the front part's side) jumps from −d to +d wherever the nearest visible edge changes owner. That happens on medial ridges far from any edge. Bilinear filtering then crosses zero there, and the shader drew hairline seams (the spike's first render, an X on the head). U is continuous everywhere. The side flag is discontinuous only on those ridges, where U is far beyond any line width, so nothing is drawn there. The edge's outward normal is recovered in the shader as −∇U on the front side and +∇U on the back, so it is not stored.

1.4 **Scales and the downsample.** The 4x master (4 texels per u) feeds the 4x review and is the reference for the reductions; the game ships 1x (1080p native) and 2x (2160p). The "nearest-plus-bicubic hybrid" is, per channel:
- S, U and side are re-evaluated exactly at each scale's pixel centres (exact evaluation is the ideal downsample of a distance field);
- part index, brush angle, taper and flags are point-sampled (nearest) at the scale's pixel centre;
- emissive is area-averaged;
- normal and gloss are reduced from the 4x master with a Mitchell–Netravali bicubic (B = C = 1/3), then the normals are renormalised.

The line stays crisp because the shader draws it from S and U at whatever scale is on screen. The view binds the 2x set when the window's height is at least 1440 px.

1.5 **Sheets.** Frames go in fixed cells per action: the action's largest posed bounds, rounded up to 4 u, plus 8 u of padding on each side, so that the S range never reads a neighbour under linear filtering. Rows are actions. Atlases are at most 4096 px at 2x; a larger sheet is split by action into pages.

1.6 **Metadata** `<asset>.sheet.json` (schema `tools/artbuild/sheet_schema.json`, validated in CI):
- `version`, `asset`, `source_sha256`, `tools` (pinned versions), `scales`, `cell_u`, `origin_u` (the feet pivot), `parts` (index, id, tags);
- `actions`: name to `fps`, `loop`, `frames[]`. Each frame has `rect` per scale, `ticks` (its duration in 60 Hz ticks, from the pose timing), `key`, `smear` (bone to bool), `silhouette_box`, `part_boxes` (each tagged part's posed bounds, including `blade`, `pogo` and `eye`) and `emissive_regions[]` (part, centre, radius, colour, kind: ember, eye, blade, pogo).

All boxes are in u relative to the origin. The core's hitboxes, hurtboxes and pogo boxes stay in `content/` (CLAUDE.md rule 6; art never moves the simulation): the metadata reports what the art measures, and a test checks rule 8 against content on every active frame (the hurtbox lies inside the silhouette box and is smaller than the sprite; the attack box contains the blade box). Enemy eye lights take their per-frame positions from `emissive_regions` of kind `eye`.

1.7 **Shared textures.** `assets/art/build/noise/noise.png` is 256 x 256, tileable and seeded, built from an integer hash (no RNG state):
- R: paper grain (128 and 64 cells);
- G: brush (32, 64 and 16 cells);
- B: wobble octave 1 (16 cells);
- A: wobble octave 2 (32 cells).

The cell counts are part of the interface: the shader turns a wavelength in u into texture coordinates with them.

1.8 **Output and cache.** Build output is committed under `assets/art/build/` so that Godot imports it and reviewers see it. Every file's SHA-256 is in `assets/art/build/MANIFEST.json`. Each frame is cached under the hash of the sources it reads plus the tool version. `python3 tools/artbuild/build.py --check` rebuilds everything and fails on any byte difference; it runs in CI (renders are never hand-edited). Frames build in parallel processes, each independent, so the output is the same in any order.

1.9 **cairosvg's role** is the independent reference. A unit test renders each part library with cairosvg and requires the SDF's sign to agree on every pixel cairo's coverage calls firmly inside or outside (above 0.98 or below 0.02); the spike measured 100% at 1x, 2x and 4x. It also renders the gallery's flat source thumbnails. It never produces a shipped channel.

### 2. What the canvas shaders compute at runtime

Everything that depends on a light, the view or time:

2.1 **Ink line (closed, `shaders/ink/ink_sprite.gdshader`).** For a pixel, the line light direction `l` (Decision 3.3) and the visible edge's outward normal `n_edge = (side ? −1 : +1) · normalize(∇U)` (∇U by four taps of U):
- weight `w = mix(line_lit_u, line_shadow_u, shadow_side) × mix(0.2, 1, taper)`, with `shadow_side = 1 − smoothstep(−0.2, 0.4, n_edge·l) × line_strength`;
- the weight never falls below `line_min_px` screen pixels (0.8), because the spike's 0.3 u hairline is 0.3 px at 1x;
- ink covers `U + wobble ≤ mix(aa, w, side)` with `aa = 0.75 fwidth(U)`, so the line lies on the front side of every visible edge and the side ramp anti-aliases its outer boundary;
- the sprite's alpha is `1 − smoothstep(−aa, aa, S + wobble)`;
- ink is never lighter than the fill it covers: `min(ink, fill × 0.6)` (at Pitch the spike's black ink read as a grey outline on blacker fill).

2.2 **Wobble.** Two octaves of the noise's B and A channels at wavelengths 10 u and 4 u (weights 0.66 and 0.34), amplitude 0.22 u, applied to S and U alike. It is reseeded every boil step, `wane_boil = floor(tick × boil_hz / 60)` with `boil_hz` 12, so no two boil steps match and every frame is reproducible from the tick. The spike's first wavelength, 0.7 u by accident, made the edges look hairy; wavelengths are specified in u.

2.3 **Open, broken line (backgrounds, `ink_background.gdshader`).** The same U on the layer's own SDF, broken where a low-frequency noise mask is below 0.42 to 0.5, thinned to 35% and dropped out where the light reaching it exceeds 0.15 to 0.55 of the ember's energy. The spike drew it on the room SDF's tile edges.

2.4 **Gouache fill.**
- Value: `mix(shadow, lit, smoothstep(t − 0.03, t + 0.03, E_key·(N·L) + 0.1·brush))`, with t = `lit_threshold` 0.20. `E_key` is the key light's energy times attenuation times shadow visibility; the brush noise breaks the terminator like a brush edge.
- Brush streaks: the noise's G channel stretched 1:14 along the part's major axis, ±12% on the value.
- Edge darkening: −22% within 1.0 u of the line band, measured from the band as `|U − w/2| − w/2`, never from U alone. The spike's first try darkened the whole back side of every overlap.
- Paper grain: ±7% from `FRAGCOORD`, in screen space.
- Rim: the palette's rim colour times the light colour in a 1.2 u band inside the silhouette facing the light. Its direction comes from ∇S, not from `n_edge`, because `n_edge` flips at T-junctions and the spike showed bright spikes there.
- Final colour: `value × radiance + rim`, then emissive on top (`emissive × palette emissive × instance boost`, unaffected by ambient). Its bloom comes from the post pass (Decision 3.4).

2.5 **Per-instance values** ride on the vertex colour (`self_modulate`) so that every sprite of a sheet shares one material and batches: r = hit or parry flash, g = emissive boost (Kindling tiers, wax softening), b = dissolve (death), a = alpha. The shader builder verifies this on Compatibility first (the spike did not); if Godot's batching breaks it, the fallback is one material per live sprite.

2.6 **Numbers** are starting values from the spike, not tuned. They live in `content/art/ink.tres` (`InkTuning`, with `validate()`) and reach the shaders as packed global vec4s (Decision 7.2). Tuning follows CLAUDE.md: one number at a time, with a feel-log entry.

### 3. The lighting pass

3.1 **Lights.** `game/lighting/light_field.gd` (`LightField`) owns a light table of at most 16 lights. It culls by distance to the view, then by priority: ember, Beacons, fire, Gutter Ember, eyes. Each frame it writes the `RGBA32F` texture (16 x 4 texels, `ImageTexture.update`) bound to the global `wane_light_table`:
- row 0: x, y (u), radius (u), height (u);
- row 1: rgb × energy, then the flags (bit 0 casts a shadow; bits 1-2 the shadow-buffer channel; bit 3 lights only points above it, for the Gutter Ember, "the only light that casts up").

| Light | Radius | Colour | Energy, motion | Shadow |
| --- | --- | --- | --- | --- |
| Ember (light 0, also `wane_ember`) | 420 u (`ember_radius_u`, scaled by the kit later) | blackbody 2400 K (`ember_kelvin`; the spike's function gives (1.00, 0.61, 0.24)) | 1.6 × (1 + 0.04 sin(2π · 0.5 Hz · t)), t from the tick plus the interpolation fraction | channel R |
| Beacon | 900 u | cool white, about 6500 K | steady | channel G |
| Fire | 160 u | about 1800 K | flickers from noise on the tick | channel B, if within the cap |
| Gutter Ember | 600 u | red | slow pulse, up only | channel A |
| Enemy eye | 24 u | per enemy | from the sheet's `eye` regions | none |

Light height is 40 u (`light_height_u`): low enough that the ember rakes across bevels. All of these numbers are in `content/lighting.tres`.

3.2 **Shading** is in the ink shaders (Decision 2) through `shaders/lighting/light_common.gdshaderinc`: radiance = ambient + Σ light rgb × energy × attenuation × visibility × (0.35 + 0.65·N·L). Attenuation is `(1 − d/r)^1.6` (`falloff_power`). Every lit shader is `render_mode unshaded`; the game no longer uses `PointLight2D`, `LightOccluder2D` or `CanvasModulate`, so nothing is lit twice and nothing depends on Godot's per-light `light()` callback (which cannot make the two-value choice, a threshold on the summed light).

3.3 **The line light.** A sprite that carries an ember (`carries_ember`, the Wicks) has its own ember inside its silhouette, so every edge would face away from it and every line would be thick (the spike showed exactly that). For such a sprite, the line is weighted by the strongest other light, or else by the room's key direction `wane_key` (xy toward the key, z strength; per room in its composition, upper left by default). Other sprites use the strongest light reaching them.

3.4 **Emissives and post.** The root viewport renders 2D in HDR (`use_hdr_2d`; the spike's bake viewport proved HDR 2D on Compatibility), so emissives exceed 1.0. `shaders/post/post.gdshader` blooms above 1.0, adds grain and the vignette, within the 1.0 ms Post budget (BUILD.md section 13). The palette is sampled with `source_color` (linear); data textures are not.

3.5 **Ambient times the Dark.** `wane_ambient` = the zone's ambient colour × dark factor (the colour is `LightingTuning.ambient_colour` in `content/lighting.tres`, not a field of `ZoneDef`: addendum of 2026-10-21). We use `factor(D) = max(0.15, 1 − 0.53 × (D − 1))` (`dark_slope` 0.53, `dark_floor` 0.15), which is 1.0 at D = 1, about 0.68 at D = 1.6 (Gloam begins) and 0.15 from D = 2.6 (Pitch). Section 10's "At Pitch, ambient is 0.15" and section 8's "by D = 4 only the player's ember and enemy eyes are visible" both hold; section 8's 0.09 was the outlier. BUILD.md section 8 now carries this curve (the lead's decision at the Phase 2 task 1 merge); the director may still pick another (one number, `dark_slope`). Review renders use Dusk = 1.0 and Pitch = 0.15. `wane_dark` carries the factor for the parallax fades.

3.6 **Renderer.** The pass uses only what both GL Compatibility and Mobile provide: canvas shaders, global shader parameters (sampler2D globals set at runtime work, measured), SubViewports, HDR 2D, `texelFetch`, `#define`. So ADR-0001's Compatibility-versus-Mobile measurement stays open without blocking this work; it is owed on GPU hardware with BUILD.md section 15's Deck line (PROGRESS Blocked 2). CI and every review render use Compatibility under xvfb.

### 4. Shadows: a room SDF of our own, marched into a screen-space buffer

4.1 **The room SDF** (`game/lighting/room_sdf.gd`, `RoomSdf`).
- Shapes: the room's `TileGrid` is partitioned into solid and empty shapes. These are row runs of wall tiles (merged downward where the runs match, as `OccluderBuilder` already does) and row runs of empty tiles; each slope tile is two solid and two empty triangles (from `TileGrid.slope_edge_heights`); the border is a 64 u solid band.
- Shape texture: `RGBA32F`, (count x 2): row 0 holds a, b; row 1 holds c and the kind (0 solid rectangle, 1 empty rectangle, 2 solid triangle, 3 empty triangle).
- Bake: one draw of `shaders/lighting/room_sdf_bake.gdshader` into an HDR SubViewport at `sdf_texel_u` 4 u (`UPDATE_ONCE`). It is exact: outside the walls, the distance to the nearest solid shape; inside, minus the distance to the nearest empty one, so merged runs leave no inner seams. The result is read back once and kept as an `RH` `ImageTexture` (2 bytes a texel; 304 KB for a 60 x 34 room), bound to `wane_room_sdf` with `wane_room_rect`.
- When: built at prebuild, cached by room id and grid stamp exactly like the Phase 1 walls (ADR-0020 Decision 13), never on a door frame.

Zone 1's rooms have 56 to 330 shapes and 0.16 to 0.33 M texels; the spike room had 130.

4.2 **Dynamic occluders** (solid boxes that burn away; enemies whose `EnemyDef` says `casts_shadow`, Clingers and bosses first, so that "a Clinger is a shadow before it is a sprite") are at most 16 analytic boxes or circles. They go to `uniform vec4 occluders[16]` (centre, half size; negative w means a circle) on the march material, and the march takes the minimum of the texture and them.

4.3 **The shadow buffer** (`game/lighting/shadow_buffer.gd`, `ShadowBuffer`) is a SubViewport covering the view at `shadow_scale`:
- 1.0 on PC and consoles, 0.75 on Switch 2 and the Deck profile, 0.5 on the minimum PC (BUILD.md section 12), with 3 casters there;
- RGBA8, one visibility channel per shadow-casting light (R is the ember), bound to `wane_shadow`;
- sprites read it at `SCREEN_UV`, so the march runs once per buffer texel whatever the overdraw. Lit parallax layers share it (the screen-projected 2D shadow).

The march (`shaders/lighting/shadow_march.gdshader`), for each pixel and each caster:
- If the pixel starts inside a wall, walk out toward the light (at most 12 steps). Past `skin_u` 14 u of depth it is dark; within it, it is lit at `1 − depth/skin_u`. This gives wall faces turned to the ember a lit skin and heavy black interiors.
- Then sphere-trace at most 48 steps (minimum step 1.5 u), keeping `res = min(res, h · dist / (light_r_u · (t − t0)))` with the ember's `light_r_u` 8 u, so the penumbra widens with distance from the occluder;
- visibility = `smoothstep(res)`.

All of these numbers are in `content/lighting.tres`.

4.4 **Headless.** Under `--headless` (the dummy renderer: fixtures, unit tests, the frame bench), the field still runs its script work (that is what the frame bench gates) but skips the bake and the buffer.

4.5 **The CPU twin** (`game/lighting/shadow_twin.gd`, `ShadowTwin`) evaluates the same shapes exactly and runs the same march in GDScript, 0.2 to 0.4 ms a query. It is for tests only: the core knows nothing of light. It turns BUILD.md section 15's "At Pitch ambient, the ember's light reveals a Clinger 30 frames before it drops" into a headless test: the ember's path from a replay fixture, the Clinger's drop point, visibility at least `reveal_threshold` for 30 ticks before the drop. An xvfb test holds the GPU buffer to the twin: the spike measured a mean difference of 0.0003 over 720 points, 1 point above 0.1 (0.131, on a penumbra edge).

4.6 **Why not Godot's canvas SDF** (measured; the Spike section has the numbers):
1. It is rebuilt every frame the camera moves. With a panning camera on llvmpipe it cost 41 ms over an empty buffer pass at 0.5 scale; the room SDF's march cost 9 ms.
2. It is screen-space with a 20% margin, so walls off screen do not occlude lights off screen (a Beacon, fire behind the view edge).
3. A GPU jump-flood result has no CPU twin, so the Clinger line could only be judged by eye.
4. On Compatibility, `texture_sdf()` and `screen_uv_to_sdf()` exist only inside `fragment()`; called from a helper function the shader fails to compile ("no function with name 'screen_uv_to_sdf'"), which the spike worked around with a `#define`.

Its march cost per pixel and its look were otherwise equal (2.7 against 3.0 fetches per marched pixel; the two renders are indistinguishable).

### 5. The three-size review output

`tools/artbuild/review.gd` (a SceneTree script, like `tools/replay/film.gd`) renders with the game's own shaders:

```
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
  --audio-driver Dummy --resolution 1920x1080 --script tools/artbuild/review.gd -- <asset> [action...]
```

Output goes to `docs/gallery/<asset>/`:
- `sil64.png`: shader mode 1 (alpha from S, white on black), scaled so that the asset's tallest frame is 64 px; the style gate's contrast is measured on it.
- `dusk1x.png` and `pitch1x.png`: the 1x set in the lit test room `tests/screenshot/rooms/lit_test.room` (floor, wall, ledge, crate, as in the spike). The asset sits on a fixed mark; an asset without an ember is lit by an ember 120 u to its left at chest height. The view is cropped to 640 x 360 around the asset, at Dusk (factor 1.0) and Pitch (0.15).
- `detail4x.png`: the 4x masters, camera zoom 4, lit at Dusk.
- `<action>.png`, the contact sheet: every frame of the action at 1x, lit at Dusk, in one row with tick numbers, smear frames marked, and the blade tip's arc drawn over the row; the key poses again at 4x below.

`docs/gallery/index.html` (task 3) links them with the style-gate results.

### 6. Determinism, and what screenshot regression (task 3) needs from this task

6.1 **artbuild** uses only IEEE-exact float64 operations (+, −, ×, ÷, sqrt, comparisons) for distances and channels. Angles use Python's `math` and are quantised to 8 bits. Noise comes from an integer hash seeded by `crc32(asset id) xor build seed`. PNGs are written by Pillow at `compress_level=9` with no ancillary chunks. Byte identity is gated on the pinned CI image (Linux x86-64, `tools/requirements.txt`); other machines are expected to match, not required to.

6.2 **The runtime has no clock of its own.** Everything time-varying (boil step, ember flicker, fire, the Hush's pulse) derives from `Simulation.tick` and the interpolation fraction, set by `LightField`. A grep gate rejects `TIME` in `shaders/`.

6.3 **For task 3.** `LightField.freeze(tick, dark_factor)` renders any room at a chosen Dark and tick. References are rendered at `shadow_scale` 1.0 on the CI image with llvmpipe: the spike rendered nine images twice and every pair was byte-identical. Each reference records the art manifest's hash and the Mesa version, so a diff names its cause. The 0.5% per-pixel tolerance (BUILD.md section 13) then covers real change only.

6.4 **The style gate's inputs are this ADR's channels:**
- line-weight range: from `InkTuning` and U;
- two-value separation: the palette's lit and shadow luminance;
- 64 px silhouette contrast: from `sil64.png`;
- emissive mask present: shape A or the `emissive` tags;
- reads at Pitch: from `pitch1x.png`.

### 7. The builder split

Three builders work in parallel against this ADR. Each owns its files; nobody edits another's.

7.1 **artbuild (Python)**, `tools/artbuild/`:
- `build.py`: CLI `python3 tools/artbuild/build.py [--check] [--jobs N] [asset...]`;
- modules: `svg.py` (the subset parser and lint), `geometry.py` (transforms, flattening), `sdf.py` (banded exact distances, scanline winding in place of the spike's per-pixel test), `channels.py`, `pack.py`, `noise.py`, `meta.py`, `manifest.py`; `sheet_schema.json`;
- tests: `tools/artbuild/tests/test_*.py`, run by `ci/test.sh` with the other Python tests;
- outputs: Decision 1's files plus `assets/art/build/noise/noise.png` and `MANIFEST.json`.

Its first deliverable is the probe: the spike's test figure as `tools/artbuild/tests/data/probe.svg`, built to `tests/screenshot/data/probe/` (committed test data, not art), which the other two builders render. Until the animator exists, a frame's pose is a list of per-part affines in a test `.pose.json`. Gates: the sign agrees with cairosvg; two builds are byte-identical; a 4x frame of the probe takes at most 1.0 s (the spike: 6.6 s, dominated by the per-pixel winding test).

7.2 **shaders (Godot shading language and the view side)**:
- shaders: `shaders/ink/ink_common.gdshaderinc` (decode constants 128 and 16, wobble, line, gouache), `shaders/ink/ink_sprite.gdshader`, `shaders/ink/ink_background.gdshader`;
- `game/art/sprite_sheet.gd` (`SpriteSheet`: loads the JSON and the textures for a scale) and `game/art/ink_sprite.gd` (`InkSprite`: draws one frame of a sheet with the shared material);
- `content/art/ink.tres` (`InkTuning`) and `game/art/ink_globals.gd`.

Material uniforms: `shape_tex`, `normal_tex`, `parts_tex` (`filter_nearest`), `palette_tex` (`source_color`, `filter_nearest`), `noise_tex` (repeat), `frame_u` (vec2, the cell in u), `carries_ember` (bool), `palette_row` (int), `mode` (0 lit, 1 silhouette, 2 visibility, 3 channel debug).

Its globals, packed vec4s:
- `wane_ink` (line_lit_u, line_shadow_u, line_min_px, wobble_u);
- `wane_ink_wave` (wave1_u, wave2_u, edge_dark_u, edge_dark);
- `wane_fill` (lit_threshold, terminator_soft, brush_noise, brush_strength);
- `wane_fill_more` (brush_stretch, rim_u, grain_strength, back_line_u).

Tests: every shader compiles headless; the probe renders under xvfb match the committed references; a Python test checks that the decode constants match `tools/artbuild/channels.py`.

7.3 **lighting (Godot)**:
- `game/lighting/`: `light_field.gd`, `wane_light.gd`, `room_sdf.gd`, `shadow_buffer.gd`, `shadow_twin.gd`; `lighting_tuning.gd` extended with `ember_kelvin`, `light_height_u`, `shadow_scale` per profile, `skin_u`, `light_r_u`, `max_steps`, `min_step_u`, `sdf_texel_u`, `dark_slope`, `dark_floor`, `reveal_threshold`;
- shaders: `shaders/lighting/light_common.gdshaderinc`, `shadow_march.gdshader`, `room_sdf_bake.gdshader`; `shaders/post/post.gdshader`;
- `project.godot` `[shader_globals]`: `wane_ambient` (color), `wane_dark` (float), `wane_key` (vec4), `wane_ember` (vec4: x, y, radius, energy), `wane_light_table` (sampler2D), `wane_light_count` (int), `wane_shadow` (sampler2D), `wane_view` (vec4: world x and y of the view's top-left, world units per pixel x and y), `wane_room_sdf` (sampler2D), `wane_room_rect` (vec4), `wane_boil` (float), `wane_time` (float, seconds from the tick).

It replaces `game/lighting/lighting_rig.gd` and the `LightingRig` paths in `game/main.gd`, `tools/replay/film.gd` and the frame bench. Lighting is always on; the fixture word `lighting pitch` and `--lighting=pitch` become "Dark factor 0.15".

Tests: the twin against the bake and the buffer (xvfb), the Clinger reveal (headless), the existing door no-spike gate with the bake at prebuild, and the frame bench.

The API `light_common.gdshaderinc` exposes to 7.2:

```glsl
float wane_visibility(vec2 screen_uv, int caster);           // the shadow buffer's channel
vec3 wane_radiance(vec2 world, vec3 n, vec2 screen_uv);      // ambient + all lights, (0.35 + 0.65 N.L)
float wane_key_irradiance(vec2 world, vec3 n, vec2 screen_uv, bool carrier); // the two-value choice
vec2 wane_line_dir(vec2 world, bool carrier);                // toward the line light (Decision 3.3)
float wane_light_reaching(vec2 world, vec2 screen_uv);       // for the open line's drop-out
```

7.4 **Order and hand-offs.** The three start together. Shaders and lighting render the probe from the spike's generator (`make_sdf.py` in the session's scratch copy of the spike) until 7.1's probe lands, then switch. Lighting delivers `light_common.gdshaderinc` with stub lights on day one so that 7.2 compiles against it. Task 2 (Ash's rig and poses) starts when 7.1 and 7.2 are green on the probe.

## Spike (zz_spike, deleted; the renders are `docs/feel_log/2026-10-20-art-pipeline-spike.png`)

**What it did.** A hand-made Wick-like test figure (8 SVG parts: back arm, body, head, wick, front arm, hand, blade, ember) went through a numpy version of Decision 1. It was rendered through a minimal ink and gouache shader under xvfb (GL Compatibility, llvmpipe, 4 cores). The room was `TileGrid.from_rows` (60 x 34: floor, a 2-tile pillar, a ledge, a crate, a slope pair). The ember was lit with normal mapping and a ray-marched soft shadow, rendered at Dusk (ambient bruise violet × 1.0) and Pitch (× 0.15), at 1x and 4x, with the 64 px silhouette. Both shadow SDFs were timed.

**The bake (Python).**

| Measure | Result |
| --- | --- |
| SDF sign against cairosvg's coverage, on pixels cairo calls firmly in or out | 100% at 1x, 2x, 4x |
| Coverage from the SDF against cairo's anti-aliased coverage | mean error 0.0015 (1x), 0.0003 (4x); worst 0.17 to 0.20 at sharp tips |
| Two builds | byte-identical (all PNGs, one SHA-256) |
| Nearest-segment search, 1543 segments, 4x (256 x 256 px) | brute force 12.3 s; banded 0.34 s; identical inside the band |
| Whole 4x frame | 22.4 s brute force; 6.6 s banded (the rest is the per-pixel winding test) |

**The GPU, on llvmpipe at 1920 x 1080.** Times are the least of 3 rounds of a 30-frame median, with the camera panning.

| Configuration | Frame | Over base |
| --- | --- | --- |
| Room and sprite shaders, no shadow buffer (base) | 57.0 ms | |
| Empty buffer pass at 1.0 (fixed cost of the pass) | 287.5 ms | +230.5 |
| Empty buffer pass at 0.5 | 106.1 ms | +49.0 |
| Room SDF march at 1.0 | 258.5 ms | +201.5 |
| Room SDF march at 0.5 | 115.3 ms | +58.3 (+9 over the empty pass) |
| Canvas SDF march at 1.0 | 341.9 ms | +284.8 (+54 over the empty pass) |
| Canvas SDF march at 0.5 | 146.6 ms | +89.5 (+41 over the empty pass) |
| Room SDF march at 1.0 with canvas-SDF occluders present | 335.7 ms | +278.7 |
| Godot `PointLight2D` with PCF13 shadow maps (buffer off) | 124.0 ms | +67.0 |

**Other numbers.**
- March steps per marched pixel: room SDF mean 3.0 (peak 56), 1.45 M fetches a frame at full 1080p; canvas SDF mean 2.7, 1.28 M.
- Room SDF bake: 512 x 304 texels, 130 shapes; one frame of 122 to 156 ms on llvmpipe; read-back 3 to 4 ms; worst difference from the CPU twin 0.06 u.
- The same bake in GDScript would take 10 to 20 s a room, so the bake is GPU work.
- Twin against buffer: mean 0.0003, 99th percentile 0.000, worst 0.131, 1 of 720 points over 0.1.
- Renders: two runs byte-identical (9 images).

**How to read the GPU table.** llvmpipe is a CPU rasteriser, so its milliseconds are not GPU milliseconds; only the comparisons transfer. On llvmpipe, sampling a full-resolution render target dominates (+230 ms for an empty pass). The march itself is 9 ms at 0.5 scale, and the canvas SDF's per-frame rebuild is 4 to 6 times that. By fetch count, 1.45 M SDF fetches and one buffer write per pixel are well inside the 3.0 ms lighting budget on BUILD.md's reference PC. That and the Deck's figure are measured on hardware, owed with PROGRESS Blocked 2. The half-scale buffer is indistinguishable from full scale at 1x (sheet, row 3 left), so 0.75 and 0.5 are safe defaults for the smaller targets.

**What looked wrong, and the decision each produced.**

| Finding | Decision |
| --- | --- |
| Signed line field: hairline seams on medial ridges | U + side (1.3) |
| Wobble wavelength 0.7 u: hairy edges | Wavelengths in u, with cell counts (1.7, 2.2) |
| Ink lighter than the fill at Pitch | `min(ink, fill × 0.6)` (2.1) |
| The carrier's own ember makes every edge "shadow side" | Line light rule (3.3) |
| 0.3 u hairline is 0.3 px at 1x | `line_min_px` 0.8 (2.1) |
| Edge darkening over the whole back side of an overlap | Measured from the line band (2.4) |
| Rim spikes at T-junctions | Rim direction from ∇S (2.4) |
| Shader variable named `E` | It is a built-in constant; the shader failed to compile |

## Alternatives considered

| Option | Why not |
| --- | --- |
| Bake the finished ink and gouache look into colour sprites (the doc's "renders sources through the ink and gouache shaders" read literally) | The line cannot follow a moving ember, the wobble cannot change per frame and the two values cannot answer the light: section 10 asks for all three |
| Rasterise with cairosvg at 4x and take a Euclidean distance transform | Sub-pixel error at the zero contour, needs supersampling (1024² per frame at 4x x 4) or scipy; exact segment distances are deterministic, resolution-independent and measured fast enough banded |
| One signed line field P | Seams: zero crossings on medial ridges (spike) |
| Store the edge normal instead of the side flag | Two more channels; −∇U with the side flag gives it |
| Godot's own 2D lights (`PointLight2D`, `light()` callback) with normal maps via `CanvasTexture` | Per-light additive callbacks cannot make the two-value choice on the summed light; shadows are PCF shadow maps, not ray-marched (uniform penumbra); measured +67 ms on llvmpipe against the room march's +58 at 0.5 |
| Godot's canvas SDF for the march | Decision 4.6: rebuilt per frame (+41 ms against +9 on llvmpipe), screen-space, no CPU twin, `fragment()`-only on Compatibility |
| Per-sprite march (each lit fragment marches) instead of a screen-space buffer | Cost multiplies with overdraw (5 to 7 parallax layers, crowds); the buffer's scale is the profile lever BUILD.md section 12 names ("lighting pass at 0.75x / 0.5x") |
| Room SDF built in GDScript, or in C++ | GDScript measured 10 to 20 s a room; C++ needs a second implementation and a parity test; the GPU bake is one draw, exact, and the GDScript twin covers the tests |
| Analytic tile SDF evaluated in the march (no texture) | 9 texel fetches and 9 shape SDFs a step near walls against one bilinear fetch |
| Section 8's 0.09 Dark slope | Pitch would be at 0.86 ambient, not 0.15 (Decision 3.5) |
| Ship only 4x textures and let the GPU minify | 16 times the memory of 1x; categorical channels cannot be mip-filtered |

## Feel reason

Light is the third pillar and the Dark the fourth. The ember has to reveal things: the line thins on the side it faces, the two values flip where its light lands, wall faces turned to it light up while their interiors stay ink-black, and a Clinger on the ceiling sits in a shadow you can read before you see it. All of that has to move with the player every frame, so it cannot be baked. What does not move with the light, the shape, is baked once and exactly, so a silhouette is the same at 64 px, 1x and 4K. Shadows that are cheap to march at half scale keep the lighting inside its 3.0 ms on the Deck's profile, so combat frames never pay for the mood. Movement and combat are untouched: the core and every golden hash are unchanged, and the core never reads light.

## Consequences

- Easier: one channel layout serves characters, enemies, props and backgrounds. Palette swaps (zones, hurt, Kindling) are a texture row. Every lit look is reproducible from a tick, so screenshot regression and the gallery are exact.
- Harder: three textures per sheet (48 KB of VRAM for each 64 x 64 u frame at 1x, 192 KB at 2x; Ash's few hundred frames stay in tens of MB, inside BUILD.md's 2 GB at 4K). Every lit shader must include `light_common.gdshaderinc` and stay `unshaded`. Room loads pay one bake at prebuild (about 0.1 to 0.6 s on llvmpipe for zone 1's rooms, by shape count; milliseconds on a GPU).
- Must keep true:
  - the decode constants in two languages, tested to match;
  - no `TIME` in shaders;
  - the art manifest check in CI;
  - the twin tests on any change to the march;
  - rule 8 checked against the art's metadata;
  - "Nothing is drawn without the VFX budget manager" still holds: the bloom is post, not effects.
- Retired with the stand-in: `LightingRig`, `OccluderBuilder`'s occluders as a shadow source (its merge logic moves into `RoomSdf`), `CanvasModulate`, and ADR-0020 Decisions 10 to 13 as they concern lighting (the frame bench and door gates stay).
- Revisit: the shadow scale per profile, and Compatibility against Mobile, on hardware (ADR-0001 Decision 4, PROGRESS Blocked 2); the Dark slope if the director picks another curve (3.5); the 16-light and 16-occluder caps if a room needs more.

## Addendum: the shaders builder (Phase 2 task 1, ink and gouache; docs/feel_log/2026-10-20-ink-gouache-shaders.md)

What building Decisions 2 and 7.2 settled or changed. Every item keeps the interfaces the other two builders depend on, or adds to them.

**Additions to the interface**
- Material uniform `texel_u` (float, u per texel at the bound scale: 1, 0.5, 0.25). The four-tap gradients and the frame-local position need it, and the shader cannot know the scale otherwise. `SpriteSheet` sets it.
- Three more packed globals, because the four vec4s of 7.2 are full: `wane_ink_more` (ink_value 0.18, taper_floor 0.2, ink_over_fill 0.6, emissive_gain 3.0), `wane_ink_light` (line_light_lo -0.2, line_light_hi 0.4, bg_drop_lo 0.15, bg_drop_hi 0.55) and `wane_ink_bg` (bg_break_lo 0.42, bg_break_hi 0.5, bg_thin 0.35, bg_mask_wave_u 48). All in `content/art/ink.tres`; declared in project.godot with the same values (a test holds the two equal).
- `wane_boil` is read by these shaders and written by `InkGlobals.set_tick` (the lighting builder may set it instead; it is one global).
- Per-instance values: the neutral `self_modulate` is `Color(0, 1, 0, 1)` (no flash, full emissive boost, no dissolve, opaque), not white; `InkSprite` sets it. Emissive strength is `palette alpha x emissive_gain x g`, with `emissive_gain` 3 so that the post pass has HDR to bloom.
- `carries_ember` and `palette_row` are material parameters, not per-sprite: `SpriteSheet.material(background, carrier, row, mode)` caches one material per family, so a family batches and instance uniforms are not needed.
- A sheet's frame `rect` in `<asset>.sheet.json` is an object keyed by scale, `{"1": [x, y, w, h], "2": [...], "4": [...]}`; `cell_u` and `origin_u` are `[x, y]` in u. artbuild must write exactly that (Decision 1.6 left the form open).
- `assets/art/build/noise/noise.png` must be imported with mipmaps (the brush streaks and the paper grain are minified at 1x; `filter_linear_mipmap`).

**What the shaders need from `light_common.gdshaderinc` (the lighting builder's file; the stub in this tree follows these)**
- `wane_line_dir` returns the direction toward the line light scaled to its strength: its length is 0 to 1, 0 where no light reaches. The line weight's `line_strength` of Decision 2.1 is that length.
- `wane_key_irradiance` includes N.L: it returns the sum of energy x attenuation x visibility x max(N.L, 0), without ambient. For a carrier it follows the room's key (`wane_key`), not the carrier's own ember, which would otherwise light every surface.
- `wane_light_reaching` is the energy at a point as a share of the ember's own, 0 to 1 (the open line's drop-out thresholds are shares of it).
- `wane_radiance` includes ambient and returns a linear multiplier; a surface's colour is `mix(shadow, lit, step) x radiance`.

**Behaviour decided by looking at the renders** (each is in the feel log)
- Emissive parts carry no ink. The rim band starts under the line, not under the silhouette. `brush_noise` 0.10 to 0.05.
- The line, the rim and the edge darkening are only worked out within reach of a visible edge (the shadow side's weight, or `line_min_px` screen pixels when zoomed out, plus anti-aliasing, wobble, darkening and rim); outside it the output is byte-identical (measured against the unculled shader), and the gradient taps are skipped for most of a sprite.
- Where the four U taps straddle an edge the gradient collapses, so the bevel normal's outward direction stands in (below 0.2 of unit length).

**Measured on the renderer**
- Godot 4.7 Compatibility: `source_color` has no effect on sampling (a 128 byte reads 0.502 through `texture()` and `texelFetch()`), and the viewport holds what the shader writes. Palettes are display values; the HDR image is read back as written. If Mobile is chosen, its sRGB decode will change the palette's look and needs one decision then.
- `self_modulate` reaches the vertex stage as `COLOR`, `MODEL_MATRIX` gives world positions, and `VERTEX` is frame-local when the node sits at the feet pivot, so sprites sharing one material draw different instance values in one frame (tests/screenshot/run_ink_render_tests.gd).
- The dummy renderer parses shaders: a shader that fails to compile lists no uniforms. That is the headless compile test. It keeps no global values, so what `InkGlobals.apply` writes is read back only under a display.
- Built-ins (`FRAGCOORD`, `SCREEN_UV`) are not visible inside functions; `ink_shade` takes them as arguments.
- The probe's GDScript bake takes 0.2 s (1x figure), 2.6 s (4x figure), 1.0 s (stage) and 1.0 s (the noise), and the whole render test file runs in about 25 s on llvmpipe; artbuild replaces the bake.
- **Import settings are part of the channel layout.** Godot's default texture import (`process/fix_alpha_border=true`) overwrites the RGB of every transparent pixel next to an opaque one (measured: a (200, 100, 50, 0) pixel beside an opaque one came back (10, 20, 30, 0)). Every channel here carries data in RGB and alpha, so the default would corrupt the palette index, the brush angle and the taper beside each alpha pixel. project.godot now has `[importer_defaults] texture` with `fix_alpha_border` false, `premult_alpha` false, `compress/mode` 0 (lossless) and `mipmaps/generate` false, for every texture (nothing in this game is a picture); `SpriteSheet` reports a sheet whose `.import` overrides them; `SpriteSheet.load_noise()` builds the noise's mipmaps itself, so the noise needs no `.import` of its own.

## Addendum: the three builders merged (Phase 2 task 1 integration; docs/feel_log/2026-10-20-art-pipeline.md)

What the merge of `tools/artbuild/`, `shaders/ink/` with `game/art/`, and `game/lighting/` settled. The lighting builder's own record is ADR-0024. Each item says who moved.

1. **One `light_common.gdshaderinc`.** The shaders builder's stub is replaced whole by the lighting builder's file, which follows Decision 7.3 and the shaders addendum's four requirements (key irradiance includes N.L and follows the room key for a carrier, `wane_light_reaching` is a share of the ember's own). The ink shaders had declared `wane_boil` themselves; the include declares it, so the ink include no longer does (a redeclaration did not compile). The ink shaders compile and render against the real file (`ci/render.sh`: 28 checks).
2. **One boil rate.** `boil_hz` was a tuned number in both `InkTuning` and `LightingTuning`. It lives in `content/lighting.tres` (`LightingTuning.boil_hz`, 12): `LightField` writes `wane_boil` from the tick, so the shader family has one clock and one number. `InkTuning.boil_hz` and its line in `content/art/ink.tres` are gone; `InkGlobals.set_tick` stays as the tests' and the harness's way to set a boil step by hand.
3. **The shader globals are the union.** `project.godot` declares the shaders builder's seven (`wane_ink`, `wane_ink_wave`, `wane_fill`, `wane_fill_more`, `wane_ink_more`, `wane_ink_light`, `wane_ink_bg`) and the lighting builder's twelve (`wane_ambient`, `wane_dark`, `wane_key`, `wane_ember`, the light table, shadow, view and room field, `wane_boil`, `wane_time`). Where both declared one (`wane_ambient`, `wane_key`, `wane_ember`, `wane_boil`) the lighting builder's value and type stand: ambient is the zone colour (0.2, 0.17, 0.26) times the Dark with no `source_color`, the key is (-0.6, -0.8, 0.5).
4. **A cell and its pivot are per action (artbuild settled Decision 1.6's open form).** `sheet.json` has `cell_u` and `cell_origin_u` on each action; the top-level `cell_u` is the largest and `origin_u` the pivot in source coordinates. `SpriteSheet` had read only the top-level pair, which put a sprite 7 u off its feet on the test prop (found by drawing it). `SpriteSheet.cell_of(action)` and `origin_of(action)` are now per action and `InkSprite.show_frame` sets the node's offset from the action it shows. The top-level numbers remain the fallback for a sheet without the per-action pair.
5. **Pages.** An asset whose frames do not fit one page is packed on several (`<asset>.p<N>@<s>x.*.png`, a frame's `page`). `SpriteSheet` loads every page, `InkSprite` binds the frame's page texture and the material is keyed by page too (`material(background, carrier, row, mode, page)`; the first four arguments are unchanged). No built asset exceeds one page yet; the unit suite reads a sheet with a frame on page 1.
6. **`InkSprite.setup` takes the new sheet's texture.** Setting one node up with the 1x sheet and then the 4x masters left the first texture bound (the 4x picture showed four tiny candles). `setup` now forgets the page it showed.
7. **A blade has a tip in `sheet.json`.** `part_boxes[].tip` (u from the feet pivot) is the vertex of the blade part's main pose farthest from its posed pivot, for parts tagged `blade`. The contact sheet draws its arc through it. A box corner was tried first and was wrong on a diagonal blade. This adds an optional field; Decision 1.6's schema stays valid for older sheets.
8. **Parts and palette (artbuild).** `parts.png` R holds the palette slot (the material), not a per-part index, so the palette stays 16 columns and an asset has at most 15 materials; the parts of a material share a slot. `sheet.json parts[].index` is that slot. Angle bytes decode as byte x pi / 255 modulo pi. The ink shader reads them as such (the render tests and the review pictures agree).
9. **The review (Decision 5) is built as stated.** `tools/artbuild/review.gd` with the wrapper `tools/artbuild/review.sh <asset>` (which first builds the 4x masters, gitignored review products) in the lit test room `tests/screenshot/rooms/lit_test.room`, through `LightField`, frozen at Dusk or Pitch. `--out` defaults to `docs/gallery/<asset>`; this task's pictures are in `docs/feel_log/2026-10-20-art-pipeline/`. `ci/lighting.sh` runs it on the test prop and checks the pictures are drawn and the silhouette is white on black.
10. **The two-value choice follows the Dark.** `wane_key_irradiance` scales the room key by `wane_dark`, so at Pitch a surface that only the room key lights falls from its lit value to its shadow value; ambient is a separate 0.15 multiplier. The render test that held "Pitch ambient is 0.15 of Dusk's" through the stub now holds `wane_dark` at 1 for that check alone, and the flip itself is what Pitch looks like in the review pictures. The tests' light now comes from a real `LightField` (flicker held at tick 0 so a test compares only the boil).

## Addendum, 2026-10-21: Decision 3.5 settled, where the ambient comes from, and harnesses need a field (second review, integration; docs/feel_log/2026-10-21-review2-integration.md)

1. **The slope is in BUILD.md.** Section 8's ambient row reads `base × max(0.15, 1 − 0.53 × (D − 1))` since the Phase 2 task 1 merge, matching `content/lighting.tres` (`dark_slope` 0.53, `dark_floor` 0.15) and `LightingTuning.dark_factor` (pinned at 1.0, 0.682 and 0.15 by `test_lighting.gd`). It was the lead's decision (PROGRESS, For the director); the director may still pick another curve, which is one number. The status line and Decision 3.5 now say so.
2. **The zone's ambient is not a `ZoneDef` field.** Decision 3.5 named `content/zones/<zone>.tres`; no such field exists, and none will: `ZoneDef` is core, `core/` holds no `Color` (core purity), and a zone's light is presentation. `LightField` takes `LightingTuning.ambient_colour` (bruise violet (0.62, 0.56, 0.72), zone 1's from section 10's palette table) and `ambient_colour` is a public property (ADR-0024 Decision 6). When a second zone exists its ambient goes in presentation content keyed by the zone's id (a table in `content/lighting.tres`), and `LightField` picks it on a zone change.
3. **Correction to the merge addendum, item 3.** (0.2, 0.17, 0.26) is only the default `project.godot` declares for `wane_ambient`: what a lit shader sees when no `LightField` has written the globals. The zone colour `LightField` writes is (0.62, 0.56, 0.72) times the Dark. Item 1's "28 checks" was the count at the merge; `ci/render.sh` now prints 30 ink checks and 27 form checks.
4. **No field, no light.** Every grey-box view (`RoomView`, `PlayerView`, `EnemyView`) is on `lit_flat`, so a harness that draws them without a `LightField` draws them by the declared defaults: a dim violet and no light, near black. Every harness builds one: `film.gd`, `render_room.gd`, `review.gd` and now `tools/replay/room_shot.gd` (`--dark dusk|pitch`, `--ember x:y`, frozen at tick 0). The game's command line takes `--lighting=pitch|dusk` (any case); any other word is reported and the game starts at Dusk. `off` (no field) stays the frame bench's baseline, set through `Main.lighting_word`, not a way to play.
