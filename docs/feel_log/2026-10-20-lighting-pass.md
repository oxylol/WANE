# 2026-10-20: Phase 2 task 1, the lighting pass

- Author: Claude
- BUILD.md section and table row: section 10, Lighting ("the player's ember (radius 420 u at base, warm 2400 K, flicker at 0.5 Hz with ±4% amplitude)", "2D ray-marched soft shadows from the ember against the collision layer", "At Pitch, ambient is 0.15 and the world is the ember"); section 8, The Dark
- Fixture(s): `tests/perf/stress_run.fixture` (tick 520), `tests/replay/zone1/05_kick_climb.fixture` (tick 150), room `zone1/05_wall_kick_climb` at its spawn; rendered with `tools/lighting/render.sh`, held at Dusk (Dark factor 1.0) and Pitch (0.15)
- Contact sheet: `docs/feel_log/2026-10-20-lighting-pass.png` (rows: the climb, the stress room, room 05; left Dusk, right Pitch); the buffers: `docs/feel_log/2026-10-20-lighting-pass-buffers.png` (room 05's shadow buffer, R the ember, and its distance field)

## Change

The Phase 1 stand-in (Godot's `PointLight2D`, merged `LightOccluder2D`s, a `CanvasModulate` at 0.15) is replaced by the pass of ADR-0023, built as in ADR-0024. Nothing in the core or any golden hash changed.

| Number | Before (stand-in) | After | Unit |
| --- | --- | --- | --- |
| Ember radius | 420 | 420 (`ember_radius_u`) | u |
| Ember colour | (1.00, 0.66, 0.36) by hand | 2400 K black body, (1.00, 0.61, 0.24) | rgb |
| Ember flicker | 0.5 Hz, 4%, from accumulated frame time | 0.5 Hz, 4%, from the tick | |
| Light height | 0 (flat) | 40 | u |
| Shadows | PCF5 shadow map, uniform penumbra | ray-marched through a baked room field, penumbra from the ember's 8 u radius | |
| Ambient at Pitch | 0.15 x (0.78, 0.84, 1.0) on lit items | 0.15 x (0.62, 0.56, 0.72) in the linear HDR pass | |
| Wall faces | one hard shadow edge | a lit skin 14 u deep on faces turned to the ember, black interior | u |
| Emissives | unshaded | unshaded, x1.5, bloom above 1.0 | |
| Presentation script p99, stress run, headless | 3.8 to 4.1 | 2.95 (3.48 without the native library) | ms |
| First crossing into a zone 1 room, worst | 0.08 to 0.38 | 0.06 (headless), 0.14 (GPU run) | ms |
| Dark factor | not built | 1 - 0.53 (D - 1), floor 0.15 | |

## Why

Light is the third pillar. Godot's lights could not make the two-value choice on a summed light, gave a uniform penumbra, and a per-light `light()` callback does not know about the Dark. The new pass owns the light table and the shadow buffer, so every shader reads one `wane_radiance`.

Critique of the sheet against section 10:

- **What works.** The ember is a warm pool with a long soft falloff and a visible edge where a wall stops it: in room 05 (bottom right) the ceiling block's corner draws a diagonal soft shadow across the lit corridor, and on the stress hill (middle right) the shadow runs down the far slope with a penumbra that widens away from the hill. At Dusk the same frames are legible in violet with the ember a warm pool on top, so the Dark is one number between them. The telegraphs and the Charged cone bloom and read as light. Silhouettes of unlit enemies at Pitch are faint grey boxes, so the crowd is there to be feared without being a lit floor.
- **What is thin.** A wall's lit skin is only where the straight line from the face to the ember is inside the wall for under 14 u, so it is a lens next to the player and nothing further along the wall (top right: the player on a wall, a dim warm lens on the wall behind him). That is ADR-0023 Decision 4.3's rule, and with real tile art the wall sprite's own normal map carries the rake; with grey boxes it is a hairline. The bevel normal (6 u) is the only normal mapping Phase 1's boxes can show, and it reads at the hill top as an orange rim.
- **What is missing on purpose.** No sprite has a normal map or an emissive map yet; the stand-in backdrop behind the air (`RoomView`) is a flat wall standing in for the lit parallax layers; eyes are a light kind with no enemy to carry them. The bloom is soft and low (threshold 1.0, strength 0.55, 14 px).
- **A judgement call.** Pitch's enemies beyond the ember read at about #0d0b0d against a #060507 void (a hair above it), and a wall in the dark at about #0b090b. BUILD.md says only the ember and eyes are visible by D = 4: that holds, and the floor stays 0.15 unless the director wants the far crowd gone altogether (see the questions).

## How it plays now

The world is dark and the ember lights it, with its shadows, at the numbers in section 10. Crossing a door costs a pointer swap: every zone 1 room's field is built at boot and baked one a frame, the room on show first. `godot --path . -- --lighting=pitch` holds the Dark at Pitch; the default is Dusk.

What proves it: `tests/unit/game/test_lighting.gd`, `test_room_sdf.gd`, `test_light_field.gd` (headless: the numbers, the shapes against the exact distance, the march on its CPU twin including the Clinger line, the table, rooms built once), and `ci/lighting.sh` under a display: the baked field against the exact one (mean 0.028 u), the shadow buffer against the twin (mean error 0.0017), Pitch darker than Dusk, the ember brighter near than far, a wall's shadow, the flicker on a surface (crest over trough 1.073), a crossing under 2 ms and no shader errors. `ci/perf.sh --only frame` passes: presentation p99 2.95 ms against 5.0, door crossing 0.06 ms against 2.0.

## Measured, not gated

Software rendering (llvmpipe, 4 cores) at 1080p, stress run, windowed: 290 ms a frame with the pass; 131 ms with the post pass left out; 77 ms with no field. The shadow buffer's scale did not move it (deck 0.75: 351 ms, min 0.5: 336 ms), so on a CPU rasteriser the cost is the post pass and the lit shaders, not the march. These numbers say nothing about a GPU; the Deck's 3.0 ms lighting and 1.0 ms post budgets are owed with PROGRESS Blocked 2.

## Open questions for the director

- **The Dark's slope.** ADR-0023 Decision 3.5 uses `1 - 0.53 (D - 1)` (Gloam 0.68, Pitch 0.15) because section 8's 0.09 would leave Pitch at 0.86. Confirm or pick a curve (`dark_slope` in `content/lighting.tres`).
- **Look at** the sheet at full size, Pitch on the right: is the ember's pool the right size and warmth, is the falloff too quick (`falloff_power` 1.6), is the floor of 0.15 too bright for the crowd beyond it?
- **Look at** the wall skin (top right): is a 14 u lens enough to read a wall you are clinging to, or does the grey box want a wider skin until the art lands (`skin_u`)?
- **Judge the ambient colour** (0.62, 0.56, 0.72, the Guttering Fields' "bruise violet" guessed at): the zone's own value replaces it.
