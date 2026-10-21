# ADR-0024: Build the lighting pass as a field of tick-driven globals, a baked room field and a marched buffer

- Status: Accepted
- Date: 2026-10-20
- BUILD.md sections: 10 (Lighting, Style), 8 (The Dark), 12 (Performance targets), 13 (Frame budget, Testing and CI), 15 (Graphics and feel)
- Checklist lines: Graphics and feel "At Pitch ambient, the ember's light reveals a Clinger 30 frames before it drops", "The ember's flicker is visible on nearby normal-mapped surfaces as the player walks", "The game holds 60 fps in the stress room on the Deck profile with the lighting pass on"

## Summary

- `LightField` replaces the stand-in: a 16-light table, the `wane_*` globals, room fields built at prebuild, one shadow buffer, one post pass (Decision 1).
- Everything time-varying derives from `present(tick, alpha, ember)`; `freeze(tick, factor)` makes a render reproducible (see Decision 2).
- A room's field bakes on the GPU one room a frame, read back once; the current room goes first; headless skips it (see Decision 3).
- The bake is exact to 0.03 u mean, 2 u worst (0.7 of a texel at ridges); the buffer matches the CPU twin to a mean 0.0017 (see Decision 4).
- Grey boxes are lit by `lit_flat`: tiles take a bevel normal from the field, everything else is flat; emissives are `emissive` plus bloom (see Decision 5).
- Light kinds are `LightKind` resources inside `content/lighting.tres`; the ember's numbers stay flat there (see Decision 6).
- The renderer-free half is three unit suites; the GPU half is `ci/lighting.sh` under xvfb, a CI job (see Decision 7).
- The core is untouched: no `casts_shadow` on `EnemyDef`; dynamic occluders come through `set_occluders` and the room's boxes (see Decision 8).

## Context

ADR-0023 designed the pass and fixed its interfaces; this records what building it changed or settled. BUILD.md section 10: "2D ray-marched soft shadows from the ember against the collision layer", "a per-zone ambient color multiplied by the Wane Clock's darkness factor (section 8). At Pitch, ambient is 0.15 and the world is the ember". The ink shaders and the art are built by others against `light_common.gdshaderinc`, so Phase 1's grey boxes need a surface shader of their own to be lit at all, and the stress room and a zone room must be judged at Dusk and Pitch before any art exists.

## Decision

1. **The field.** `game/lighting/light_field.gd` (`LightField`, a `Node2D` under the world) owns the table (RGBA32F, 16 x 4: row 0 x, y, radius, height; row 1 rgb times energy and the flags; row 2 falloff and the penumbra radius), culls to the view grown by each light's radius, ranks by `LightKind.priority` (ember 0, Beacon 1, fire 2, Gutter Ember 3, eye 4) and keeps `max_lights`. A shadow channel goes to the first light that asks for it; on the minimum profile channel 3 casts nothing but still lights. Every global it writes is also kept in `LightField.globals`, because the dummy renderer cannot be asked.
2. **Time.** `present(tick, alpha, ember_at)` stores the tick and fills the table at once (tests, headless); `_process` fills it again only if the camera moved the view since, so the light is placed against the view that is drawn whatever the node order. Flicker, fire, the boil (`wane_boil` = floor(seconds x `boil_hz`), 12) and `wane_time` come from the tick and the fraction. `boil_hz` is in `LightingTuning`, not `InkTuning`.
3. **Rooms.** `prebuild(id, grid)` builds the `RoomSdf` shapes (script, once, cached by id and grid stamp) and queues the bake; one bake runs at a time (`begin_bake`: a half-float `SubViewport`, `UPDATE_ONCE`, read back on `frame_post_draw`, kept as an `RH` texture and image); `show_world` puts its own room first and binds the globals, so a crossing into a baked room is a pointer swap (0.14 ms in `ci/lighting.sh`, 0.06 ms headless in `door_bench`). `settle()` awaits the queue for renders. The exact field treats everything outside its rectangle as solid, so it is continuous across the border's outer edge.
3b. **Stand-in room.** `RoomView` draws a backdrop behind the air (a stand-in for the lit parallax layers): without a surface behind the air the ember would light nothing but the tile edges and the shadows would have nothing to fall on.
4. **Numbers.** Measured on the CI image's llvmpipe: a 27-shape room bakes at 4 u a texel (160 x 96) with mean error 0.028 u and worst 1.96 u against the exact field (the bound is 0.7 of a texel: bilinear sampling rounds off ridges); 1406 buffer points against `ShadowTwin` with the baked field: mean error 0.0017, 0.7% off by more than 0.1. The flicker shows on a surface at Pitch: crest over trough 1.073 (the ember's 8% peak to peak).
5. **Surfaces.** `LightSurfaces` shares one `lit_flat` material (flat normal) and one bevel material (normal from the field's gradient within 6 u of a wall, tilt 0.95) and one `emissive` material (boost 1.5, so the post pass blooms it). Used by `RoomView`, `PlayerView`, `EnemyView` (cues and the thrown ember emissive), `CombatView`, `VfxBudget`; the F3 overlay is not lit.
6. **Content.** `content/lighting.tres` holds the ember's numbers flat and `beacon`, `fire`, `gutter_ember`, `eye` as `LightKind` sub-resources; `validate()` covers all of them (CI content stage). The default ambient is bruise violet (0.62, 0.56, 0.72) until zones carry their own; `ambient_colour` and `key` are public properties a zone or room assigns. `wane_ambient` is the colour times the Dark factor with no `source_color` hint, so 0.15 is the literal multiplier in the HDR linear pass.
7. **Tests.** `test_lighting.gd` (numbers, shader gates: no clock, no Godot lights, every global declared and set), `test_room_sdf.gd` (shapes, exactness, Lipschitz, the twin, the Clinger line), `test_light_field.gd` (table, ranking, channels, the Dark, rooms built once). `tools/lighting/gpu_check.gd` via `ci/lighting.sh` and a CI job holds the bake and the buffer to the twin, the lit shader to its numbers (Pitch against Dusk, near against far, a wall's shadow, the flicker) and the crossing under 2 ms, and fails on any shader error. `tools/lighting/render.sh` renders a room or a fixture frame at any Dark.
8. **Casters.** `EnemyDef.casts_shadow` is not added: it is core content and this task is presentation only. `LightField.occluders()` reads the room's enabled solid boxes (nearest the ember first, 16 at most) and `set_occluders` takes more (enemies' boxes, circles), so the Clinger task wires its own.
9. **Words and profiles.** `LightWord` holds `pitch` (a level past 2.6, so the factor is the 0.15 floor), `dusk` (the default) and `off` (no field; the frame bench's baseline). `--lighting-profile=pc|deck|min` and `frame_bench --profile` pick the buffer's scale 1.0, 0.75, 0.5.
10. **Clinger.** `ShadowTwin.revealed(p, light, reach, falloff)` is visibility times attenuation; `reveal_threshold` is 0.1, a starting value the Clinger task replaces with its own drop distance.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Fill the table only in `_process` | Headless tests and the frame bench would have nothing to read, and a harness that does not run `_process` would render with last frame's light |
| Bake every room in one frame at boot | Twelve full bakes in one frame on llvmpipe is over a second; one a frame spreads it and the current room goes first |
| Read the room's field on the CPU for the lit surfaces | A per-fragment CPU lookup does not exist; the GPU reads the same texture the march does |
| A real `source_color` ambient | It would convert 0.15 to 0.015 in the linear pass: the doc's number would not be the multiplier |
| Add `casts_shadow` to `EnemyDef` now | Touches `core/`, its schema and its content hash for a thing no enemy needs yet |
| Bloom from a downsample chain in sub-viewports | More passes and state for a 1.0 ms budget; nine fetches from the screen's mip levels are the same look for one pass |

## Feel reason

The ember has to reveal things. Shadows are marched through the room's own field, so a wall's lit skin and its black interior, a hanging wall's soft shadow and a ceiling's corner are the same numbers as the CPU twin that tests the Clinger line. The Dark is a multiplier on one colour, so Dusk and Pitch are one number apart and a render at either is reproducible from a tick. Movement and combat are untouched: the core and every golden hash are unchanged.

## Consequences

- Easier: the art builders include `light_common.gdshaderinc` and read `wane_radiance`; a new light kind is a resource; any frame of any fixture renders at any Dark with `tools/lighting/render.sh`.
- Harder: `light_common.gdshaderinc`, `room_sdf_bake.gdshader`, `shadow_march.gdshader` and the twin change together, and the twin tests run on any change to the march; the 12 declared globals, `project.godot` and `LightField._write_globals` agree (a test).
- Not measured here: GPU milliseconds. On llvmpipe at 1080p the stress run is 290 ms a frame with the pass, 131 ms with the post pass left out and 77 ms with no field (the lit materials still bound), so a CPU rasteriser is dominated by the post pass's mip chain and its 9 taps; the shadow buffer's scale did not move it (deck 351, min 336 ms against the PC's 290, within noise). The Deck's 3.0 ms (lighting) and 1.0 ms (post) are owed with PROGRESS Blocked 2.
- Revisit when: the Dark slope is confirmed (ADR-0023 Decision 3.5); the real sprites arrive (the bevel and the backdrop stand-ins go); the Clinger lands (`reveal_threshold`); the GPU numbers exist.

## Addendum, 2026-10-21: the stand-in room judged lit, and pogo-able surfaces as light (second review, integration; docs/feel_log/2026-10-21-review2-integration.md)

The grey-box colours were chosen unlit (review F1, F2) and then drawn through `lit_flat`, which multiplies them by the violet ambient and the 2400 K ember. Lit, the floors they were chosen for failed: at Dusk a plain box against a smooth box was a colour gap of 0.135 (floor 0.18), a plain box against its wall a luma gap of 0.098 (floor 0.12), and the merge's backdrop (0.26) sat on the walls' value (0.30), so floor against air was a contrast of 1.1. Pitch put the bell, the one surface whose function is "strike it", at (5, 11, 19) against a (7, 6, 9) wall, and section 10's "pogo-able surfaces are emissive" was not met.

1. **The floors hold lit.** `tests/unit/game/test_views.gd` judges every box kind, every box against its wall and every wall against the air unlit (the editor) and in three lights from `LightField`'s own table at tick 0 through the shader's formula: Dusk out of the ember's reach (the ambient alone, which is also what lights a solid's face inside its own shadow: the march leaves all but a skin turned to the ember dark, so a box's face is lit like this at Dusk wherever the ember is), Dusk at half its reach, and Pitch at a fifth of it (84 u, where the ember reaches a face in its pool: section 10's "At Pitch ... the world is the ember", so nothing is asked of Pitch beyond the ember's reach but light that is emitted). The floors are unchanged (0.18, 0.12, and 0.12 for wall against air), and every lit box stays under the post pass's shoulder knee so the screen shows the gaps as computed.
2. **The boxes keep their hue.** Under the ember a tan box and an amber one become one colour (blue is a quarter of red at 2400 K). The solid boxes' layer is `LightSurfaces.make_lit(item, false, true)`, the existing `keep_hue` stand-in the player's and the enemies' boxes use: the light brightens or darkens a box but does not tint it, because its colour says what it does. Tiles and the air still take the light's colour.
3. **The values.** The air is dark (0.11, 0.10, 0.13): the backdrop of Decision 3b stays, so shadows have a surface, but darker than any wall, so the playable space reads; the solid beyond the room (0.20) sits between air and wall again. Walls (0.34, 0.34, 0.39) and (0.40, 0.36, 0.32); boxes plain (0.60, 0.62, 0.70), smooth (0.86, 0.66, 0.46), wax (0.90, 0.52, 0.08), bell (0.22, 0.56, 0.80): the director's hue families, spread in value. Every tile colour moved from `RoomView` constants into `content/feedback.tres` (`tile_*`; CLAUDE.md rule 6), shared with the room editor, which draws the air in the air's colour now, not the passage's.
4. **Pogo-able surfaces are light.** A bell's strike mark and the spikes' teeth (section 5's "a bell, a spike") are drawn on two emissive layers (`LightSurfaces.make_emissive`) at `pogo_glow` 0.75 of their colour, times `emissive_boost` 1.5: the mark gives off about 1.09 luma, the teeth 0.45, so both read at Pitch out of the ember's reach. A pit has nothing to pogo off and does not glow; wax's "softens as emissive intensity rises near the ember" belongs to the wax material's art. The bell's body stays lit. What `LightSurfaces` lacks: a lit-plus-emissive material (`lit_flat`'s `emissive` uniform, which nothing sets) would let a whole bell be lit and glow faintly; the mark alone as pure light is what the existing API gives.
