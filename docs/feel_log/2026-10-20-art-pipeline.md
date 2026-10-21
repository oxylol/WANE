# 2026-10-20: Phase 2 task 1, the art pipeline made whole

- Author: Claude
- BUILD.md section and table row: section 10, Style, Lighting, Animation (the baking line) and Pipeline (Review); section 8, The Dark
- Fixture(s): none (presentation only; the core and every golden hash are untouched: 545 fixtures, no hash moved)
- Contact sheet: `docs/feel_log/2026-10-20-art-pipeline/` (the pictures below), `2026-10-20-art-pipeline-spike.png` for where it started

## Change

First implementation of the joined pipeline; no tuned number changed except that `boil_hz` now has one home (`content/lighting.tres`, 12; it was in two files). What was joined and why is ADR-0023's second addendum: artbuild bakes SVG parts, the ink and gouache shaders draw them, the lighting pass lights them, and one command (`tools/artbuild/review.sh <asset>`) writes the three-size review.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `boil_hz` | 12 in `ink.tres` and 12 in `lighting.tres` | 12 in `lighting.tres` only | Hz |

## What was looked at, and what it says (BUILD.md section 10)

Two built assets went through the whole path: the candle stump (`tests/art/src/candle_stump`, a prop with a tagged emissive flame) and the probe figure (`tools/artbuild/tests/data/probe`, a Wick-shaped figure with a chest ember and a blade with a smear). Neither is shipped art; they are the pipeline's test subjects, and Ash is the first real one (task 2). Every picture below was opened.

**Silhouette at 64 px** (`sil64.png`, `probe/sil64.png`). The stump reads as a candle: a blob with a lip, a pool and a flame tip that breaks the outline. The probe reads as a Wick: ball head with a tuft, a tall tapering robe, a blade. The blade is one pixel wide at 64 px. That is right for a thin blade, but a Wick's weapon must survive at 64 px, so Ash's blade is drawn at least 3 u wide at its base. Nothing was decorated to be understood.

**Line** (`detail4x.png`, `probe/detail4x.png`). Heavy on the side away from the light (about 5 px at 4x, the 1.3 u of `ink.tres`), a hairline on the lit side, a wobble that moves every fifth tick, and a taper at the drip tip and the blade point. The line pools at the stump's drips, which is the look wanted. Where the line meets the pool's edge the shadow-side weight reads slightly blobby at 4x; at 1x it reads as weight, not blobs. Left as it is until a real asset shows it is a problem.

**Value separation** (`dusk1x.png`, `probe/dusk1x.png`). The two values show at the edges (the rim, the shadow-side line) and not across large parts: the stump's body and the probe's robe read as one flat value, because the bevel that gives a part its normal is 3 u deep by default and the terminator only exists inside it. The shaders are doing what ADR-0023 says. The finding is for Ash and every large part: give them `data-bevel-u` of 8 to 12 so the form turns across the part, and judge the terminator in the review, not in isolation. Not changed here: it is an asset decision, and a default that rounds everything would flatten small parts.

**Readability at Pitch** (`pitch1x.png`, `probe/pitch1x.png`). The ember reveals the figure within about 200 u and the room falls to black beyond it, which is the brief. The stump, lit from 120 u to its left, shows its lit left edge and its white-hot flame and loses its right side and its line to the dark, as it should. The probe carries its own ember, so it never loses its chest. At Pitch a surface that only the room key lights falls to its shadow value (the key is scaled by the Dark), which is why the probe's head goes from cream to orange between Dusk and Pitch. I judge that correct and not a bug, and it is recorded in ADR-0023.

**Emissive** (`detail4x.png`). The flame is white-hot with an orange bloom and no ink line, the chest ember is a white disc with a halo; both survive Pitch. The probe's wick tuft is orange from the flame's bloom, as intended.

**Smear and arc** (`probe/swing.png`). The swing's middle frame carries a pale fan, the smear, and its last frame is the blade at full extension (the sheet flags only that frame, and the contact sheet marks it in red); the arc drawn over the row passes through each frame's real tip (the first version used a box corner and drew a rectangle; wrong, fixed by adding the tip to `sheet.json`). The sheet's key poses at 4x are below the row. Three frames with one smear frame is thin for a Signature but is enough to check the machinery.

**The lit test room** (`dusk1x.png` against `pitch1x.png`). Soft shadows from the ledge fall across the backdrop in a wide cone; the wall interior on the right is black with a 14 u lit skin on the face turned to the ember; the crate on the left is a Phase 1 flat box and is the one thing in the room that looks like a placeholder (it is). The ember's falloff at Dusk is gentle; at Pitch it is a pool with a hard-ish rim on the floor.

**Ash's grey box and a zone 1 room under the new lighting** (`zone1/`). Ash is still the Phase 1 box (cyan at Dusk, green at Pitch because it is lit, not tinted). At 1x (`ash_1x_dusk.png`, `ash_1x_pitch.png`) the ember rakes across the floor and the far dummy is a lit slab at Dusk and gone at Pitch beyond the ember's reach, which is the brief's "the world is the ember". Room 5 (`room05_*.png`) shows the ember lighting the climb's foot and the column's skin; the black block at the left of the floor is solid beyond the room's edge.

## Bugs the joined picture found (all fixed, all in the tests)

1. `SpriteSheet` read only the top-level `cell_u` and `origin_u`, so a sprite stood 7 u off its feet on the candle (the artbuild's cells are per action). Now per action.
2. `InkSprite.setup` left the first sheet's texture on the node, so the 4x review showed four tiny candles. Now it takes the new sheet's.
3. The ink include declared `wane_boil` and so did the lighting include: neither shader compiled until one stopped.
4. The ink render tests lit with the stub's `wane_ember` global; the real light reads a table. They now light through a `LightField`.
5. The review's first contact sheet cut its title at one frame wide (now at least 560 px) and marked every frame of the swing, and the idle, as smear because `sheet.json` lists a false flag for each smear-tagged part; it now marks only a true one.

## How it plays now

Nothing the player holds changed: this task draws no gameplay art. The director can run `tools/artbuild/review.sh candle_stump --root res://tests/art/build --out docs/feel_log/x` and open the five pictures, or `tools/lighting/render.sh out --room zone1/01_dash_slash` for a lit zone 1 room at Dusk and Pitch.

## Open questions for the director

1. Look at `probe/detail4x.png` and `detail4x.png`: is a heavy, slightly blobby shadow-side line (1.3 u) the ink you want, or thinner (1.0 u)? It is one number in `content/art/ink.tres`.
2. Look at `probe/pitch1x.png`: the head drops from cream to orange at Pitch because the key light is dark there. Do you want a Wick's head to hold its lit value at Pitch (a gloss that follows the ember), or is losing the warmth the point?
3. Listen for nothing; this task is silent.
