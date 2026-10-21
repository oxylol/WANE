# 2026-10-21: Phase 2 task 1, second review: the grey boxes judged lit, pogo-able surfaces as light, the room shot lit

- Author: Claude (the integration fixer of the second review)
- BUILD.md section and table row: section 10, Lighting ("judge every asset lit, at Dusk and at Pitch"; "Light is information: pogo-able surfaces are emissive"); section 5, Feel rules ("Every surface tells you what it is at a glance. Pogo-able things glow"); section 8, The Dark (the ambient row)
- Findings: integration I1, I2, I3, I5 (the editor's half), I6, I8 (`tests/README.md`), I9
- Fixture(s): none (presentation only; `core/` and `tests/replay/golden_hashes.txt` are untouched, 556 fixtures pass)
- Contact sheet: `docs/feel_log/2026-10-21-review2-integration/` (the layout of each picture is below)

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| air behind the room (`tile_air_colour`, was `RoomView.BACKDROP`) | (0.26, 0.25, 0.29) | (0.11, 0.10, 0.13) | sRGB |
| clingable wall (`tile_solid_colour`, was `RoomView.SOLID`) | (0.30, 0.30, 0.34) | (0.34, 0.34, 0.39) | sRGB |
| smooth wall (`tile_smooth_colour`, was `RoomView.SMOOTH`) | (0.36, 0.33, 0.30) | (0.40, 0.36, 0.32) | sRGB |
| plain box `box_solid_colour` | (0.44, 0.46, 0.54) | (0.60, 0.62, 0.70) | sRGB |
| smooth box `box_smooth_colour` | (0.58, 0.50, 0.40) | (0.86, 0.66, 0.46) | sRGB |
| wax `box_wax_colour` | (0.82, 0.62, 0.22) | (0.90, 0.52, 0.08) | sRGB |
| bell `box_pogo_colour` | (0.28, 0.58, 0.76) | (0.22, 0.56, 0.80) | sRGB |
| `pogo_glow` (new): share of a bell mark's and the spikes' colour given off as light | none (lit like any box) | 0.75 (times `emissive_boost` 1.5) | share |
| how the boxes take the light | tinted (violet ambient, 2400 K ember) | brightened or darkened only (`keep_hue`) | |

The other tile colours (one-way, spikes, pit and its lip, the beyond 0.20, a door's passage 0.07) keep their values and move, with the three above, from constants in `game/rooms/room_view.gd` into `content/feedback.tres` (`tile_*`; CLAUDE.md rule 6). The room editor reads the same numbers.

## Why

**I2, the floors did not hold lit.** The colours were chosen unlit (review F1, F2) and the merge drew them through `lit_flat`. What the reviewer measured at Dusk: plain box (70, 66, 99) against smooth box (93, 72, 74), a colour gap of 0.135 against the test's floor 0.18; plain box against its wall a luma gap of 0.098 against 0.12; in room 12 the air (40, 35, 52) and the floor (45, 41, 60), a contrast of about 1.1, and the solid beyond the room (27, 25, 36) darker than the air. The test compared the content colours and never saw the light. Now `tests/unit/game/test_views.gd` judges the same floors unlit and in three lights taken from `LightField`'s own table at tick 0 through the shader's formula (the one `tools/lighting/gpu_check.gd` holds the GPU to; in this run its flat-surface maths agreed to 0.0001): Dusk's ambient alone (0.62, 0.56, 0.72), which is also what lights a box's face, since a solid's interior is in its own shadow apart from a skin turned to the ember; Dusk at half the ember's reach; Pitch at a fifth of it (84 u). Put back to the merge's colours, the test fails 19 assertions, unlit and in all three lights; with the new ones it passes.

Two things had to change, not one. Under the ember's 2400 K, blue is a quarter of red, so a tan box and an amber one become the same colour whatever their values (the smooth box against the wax was 0.055 apart at Pitch). The boxes' layer now keeps its hue (`LightSurfaces.make_lit(item, false, true)`, the stand-in the player's and the enemies' boxes already use: a box's colour says what it does). Then the values were spread: the air went dark, so a wall stands 0.13 to 0.20 luma above it in every light, and each box stands 0.15 to 0.24 above its wall.

**I3, the bell was the hardest thing to find at Pitch.** Section 10: "pogo-able surfaces are emissive"; section 5: "Pogo-able things glow"; the pogo section names "a bell, a spike". The bell's strike mark and the spikes' teeth are now drawn on two emissive layers. A pit has nothing in it to pogo off, so it does not glow. The bell's body stays lit, because `LightSurfaces` has no lit-plus-emissive material (`lit_flat`'s `emissive` uniform is never set); ADR-0024's addendum names that as the API to add.

**I1, the room shot.** `tools/replay/room_shot.gd` drew `RoomView` with no `LightField`, so `lit_flat` ran on `project.godot`'s defaults (a dim violet and no light): bell (14, 25, 50), air (13, 10, 19). It now builds a field, freezes it at tick 0 at `--dark dusk|pitch` with the ember at `--ember x:y` (the window's centre by default), and turns off the project's stretch so a picture pixel is a view pixel. Without that, the view shrank by the picture's height: a 1120 x 384 u window filled less than half of a 1600 px picture.

**I5, the editor.** It drew the air in the passage's colour (0.07) and the game drew the backdrop (0.26), so a room did not look the same in both, against `draw_tile`'s doc comment. Both now take `tile_air_colour`. The editor shows the colours as they are and the game lights them.

**I6, `--lighting=off`.** On the command line it booted a near-black game, and a misspelt word quietly meant Dusk. The game takes `pitch` or `dusk` in any case. Any other word, `off` included, prints `--lighting=<word> is not a lighting word (pitch or dusk); starting at Dusk`. `off` stays the frame bench's baseline, set through `Main.lighting_word`. Tested in `tests/unit/game/test_main_args.gd`.

**I9.** ADR-0023 said Decision 3.5 waited on the director and that the ambient came from `content/zones/<zone>.tres`. BUILD.md section 8 already carried 0.53. `ZoneDef` is core and can hold no `Color`. The ADR's status, Decision 3.5 and a dated addendum now say what is true.

## The pictures, and the critique against section 10

- `rooms_dusk.png`, `rooms_pitch.png`: rooms 03, 07, 09 and 12 from top to bottom, before (bc051df) on the left and after on the right, from `tools/lighting/render.sh` at half size.
- `boxes.png`: a scratch room (deleted after) holding a plain box, a smooth box, a wax box and a bell side by side, with spikes on a step, a one-way platform and a smooth wall. It is drawn by the new room shot at Dusk with the ember far, Dusk near, Pitch near and Pitch far, top to bottom.
- `room_shot09.png`: `tools/replay/room_shot.gd -- out.png 'zone1/09_reverse_pogo:800:700:600:340'` at Dusk, then `--dark pitch --ember 900:900`.
- `editor09.png`: the room editor on room 09, unlit, with the air now in the game's colour.

Measured (x, y in each full-size render):

| Where | Before | After |
| --- | --- | --- |
| room 12 Dusk: air (500, 200) / floor (500, 1000) | (40, 35, 52) / (45, 41, 60) | (17, 14, 23) / (51, 46, 68) |
| room 07 Dusk: smooth roof (1000, 300) / floor (1000, 850) / air (300, 400) | (92, 72, 74) / (47, 43, 62) / (44, 36, 52) | (129, 99, 69) / (54, 49, 72) / (17, 13, 22) |
| room 09 Pitch: bell body (1150, 800) / mark (1150, 764) / wall (1300, 900) | (7, 13, 21) / (23, 21, 28) / (7, 6, 9) | (5, 13, 18) / (230, 235, 243) / (7, 7, 10) |
| room 03 Pitch: spikes far from the ember (1500, 368), (900, 880) | (18, 5, 5), (17, 5, 5) | (227, 84, 67), (227, 84, 67) |
| box room Dusk: plain / smooth / wax / bell / mark | n/a | (87, 90, 102) / (128, 98, 68) / (132, 76, 10) / (33, 83, 119) / (230, 235, 242) |
| room shot 09 Dusk: bell / mark / air / floor | (14, 25, 50) / (48, 42, 66) / (13, 10, 19) / (15, 13, 22) (the reviewer's, unlit by any field) | (31, 82, 117) / (230, 235, 242) / (23, 17, 24) / (51, 46, 67) |

Critique:

- **Value structure (Style, "heavy blacks"; Lighting, "the engine draws the world dark and the player lights it").** Before, the air and the walls were one value at Dusk and the room read as a single violet field with outlines. Now there are three values: dark air, mid walls, light boxes. The playable space reads at a glance in every room on the sheet. The solid beyond the room sits between air and wall again.
- **Function boxes.** The four kinds read apart at Dusk in the box room and in rooms 07, 09 and 12. Kept hue means a box does not take the room's violet: in room 07 the smooth roof is a warm tan slab in a violet room. That is by design for a stand-in whose colour is its meaning, but it is the most "unlit-looking" thing on screen. At Pitch a box's face is dark, like any solid's, except the skin turned to the ember. Section 10's "the world is the ember" is what it should be.
- **Pogo-able surfaces at Pitch.** This is the change that matters. Room 03's pogo chain is a line of glowing teeth across a black room, and room 09's bell is a white strike face where before there was nothing. The light is emitted, so it is the same at Dusk: there the spikes are a hotter red than the lit red they were, and the mark is the brightest thing after the ember. Neither blooms much (the mark's luma is about 1.09 before the shoulder, the teeth 0.45).
- **Shadows (Lighting, "shadows are the game's depth cue").** A darker backdrop shows less of the ember's pool and its shadows. At Dusk the bell's shadow wedge is still plain in `room_shot09.png` and `boxes.png`. At Pitch the pool on the air is subtler than before. That is the price of the playable space reading, and the stand-in goes when the parallax layers arrive (ADR-0024 Decision 3b).
- **Not judged here:** sprites, the ink line and the gouache fill. These are grey boxes, and the shaders fixer owns those.

## For the director

- Look at `rooms_pitch.png`, right column: is a glowing pogo surface the read you want at Pitch, or should it glow less at Dusk (one number, `pogo_glow`)?
- Look at room 07 in `rooms_dusk.png`: the smooth roof is now a bright tan slab. It is the grey box's meaning (smooth, no cling), but it is loud.
- The air is darker, so the ember's pool on the backdrop is quieter at Pitch. If you would rather see the light cone than the room's edges, the trade-off is `tile_air_colour`.
- Run the game with `-- --lighting=pitch` and walk room 03: the spikes are the route.
