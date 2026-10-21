# tools/artbuild

SVG part libraries in; sprite-sheet textures, normal and emissive maps and metadata JSON out. Design: `docs/adr/0023-art-pipeline-and-lighting.md` Decision 1 (BUILD.md section 10, Pipeline). Python 3.13 with the packages pinned in `tools/requirements.txt` (numpy, Pillow, CairoSVG, which needs `libcairo2`). Everything is float64 and integer maths with only IEEE-exact operations, so two builds are byte-identical (a unit test holds it) and `--check` compares a PNG by its pixels (below).

```
python3 tools/artbuild/build.py                       # all assets, all roots
python3 tools/artbuild/build.py candle_stump          # one asset (the manifest keeps the others' lines)
python3 tools/artbuild/build.py --jobs 0              # frames bake in all cores; same bytes
python3 tools/artbuild/build.py --masters candle_stump  # also write the 4x masters for review (never committed)
python3 tools/artbuild/build.py --check               # CI: fresh build, no cache, compared with what is committed (below)
python3 tools/ci/test_artbuild.py                     # the unit tests (about a minute; 64 s measured with the machine loaded)
```

Roots (`build.py ROOTS`): `assets/art/src/<asset>/` to `assets/art/build/<asset>/` (and `noise/noise.png`); `tests/art/src/` to `tests/art/build/` (the pipeline's own test prop, not shipped art); `tools/artbuild/tests/data/<asset>/` to `tests/screenshot/data/<asset>/` (the probe figure, which the shader and lighting builders render). Each out root has a `MANIFEST.json` with the SHA-256 of every file. `--check` fails on: a render that differs from a fresh build (a PNG is compared by its decoded pixels, so another zlib is no difference, but it must hold only the chunks the build writes, IHDR, IDAT and IEND, with nothing after IEND; every other file is compared byte for byte); a missing file; a manifest line that is stale, missing, or names a file of an asset with no source; and **any file anywhere under an out root** that no source builds (a stock picture, a new folder, the render of an asset whose source was deleted). The only tolerated extras are the 4x masters (`<asset>/<asset>[.pN]@4x.<kind>.png`, gitignored review products) and Godot's `.import` beside a built file or a master. A corrupt PNG or manifest is reported as a difference, not a traceback. A full build removes the files of a removed action (and their `.import`) and the folder of an asset whose source is gone. Frames cache in `tools/out/artbuild_cache/` under the hash of the sources and of every `.py` file of this package.

## A source folder

- `parts.svg`: the subset in `svg.py` (path M L H V C Q Z, circle, ellipse, rect, polygon, `g` with a transform; fills, strokes, gradients, styles and every other element are lint errors). One user unit is 1 u. A part is a leaf element with `id`, `data-z` (unique), `data-pivot`, `data-tags` (`emissive blade eye pogo wax smear`), `data-bevel-u` (default 8, 0.25 to 16; ADR-0026 Decision 7), `data-tilt-deg` (default 62, 0 to 89) and `data-normal` (`bulge` default, `flat`, `crease`). Several subpaths of one `path` are a union. The root's `data-origin-u="x y"` is the feet pivot.
- `palette.tres`: a Godot text resource whose `metadata/palette` dictionary names materials (lit, shadow, rim, gloss, optional emissive colour and strength), the material of every part and optional variants (see `palette.py`). Parts that share a material share a palette slot; there are 15 slots. A part tagged `emissive` needs a material with an `emissive` colour and an `emissive_strength` above 0 (a variant may switch a glow off); without them the part would be drawn with no ink and no glow.
- `pose.json` (optional): actions of frames, each frame a per-part affine and optional smear sub-poses, for parts tagged `smear` only (see `pose.py`). The animator (Phase 2 task 2) emits this from its `.pose.tres` files. Without it the asset is one `idle` frame. Frame timing is the animation spec, so the reader is strict: an unknown key (`tiks`), a `key` or `loop` that is not true or false, an `fps` or `ticks` that is not an integer in range (fps 1 to 60, ticks 1 or more), a NaN or infinite affine, an affine that collapses the part, or a key given twice, are all `source error`s, never a default.

## What comes out (per asset, in `<out>/<asset>/`)

`<asset>@<s>x.shape.png` (S, U, side, emissive), `.normal.png` (normal x, y, z, gloss), `.parts.png` (palette slot, brush angle, taper, flags) for s in 1 and 2 (and 4 with `--masters`); `<asset>.palette.png`; `<asset>.sheet.json` (schema `sheet_schema.json`). Pages beyond the first are `<asset>.p<N>@...`. Decode constants are the block at the top of `channels.py`.

## Where this differs from, or settles, ADR-0023

- `parts.png` R holds the palette **slot** (a material), not a per-part index, so the palette is always 16 columns and an asset has at most 15 materials. `sheet.json` `parts[].index` is the slot.
- A cell is per action, so `sheet.json` has `cell_u` and `cell_origin_u` (the feet pivot inside the cell) per action; the top-level `cell_u` is the largest of them and `origin_u` the pivot in source coordinates. All boxes are in u relative to the pivot, x right and y down.
- The taper is found by casting a ray inward from each visible edge to the part's own outline (half the chord over 2.5 u), which is exact, instead of walking 24 steps.
- A smeared part's taper channel is its age per pixel: where along its arc the part last covered the pixel (0 the tail, 1 its own pose), interpolated between the arc's sub-poses (`channels.sweep_ages`); its parts texels also reach 1.5 u over its anti-aliased fringe, so the shader fades the fringe with the ribbon (ADR-0023 addendum of the fix round 2b).
- Edges are cut where outlines cross and classified by their midpoint (exact), instead of being split to 0.25 u first. Overlapping subpaths of one part, and a smear's sub-poses, are a union with no interior edge.
- The normal's tilt is linear in the angle, `tilt_deg x (1 - depth/bevel)`, as the ADR text says (the spike tilted by slope).
- Reductions: normal and gloss are reduced from the 4x master with Mitchell weighted by silhouette coverage, so the silhouette edge does not dilute them, then renormalised; emissive is a box average; everything else is evaluated exactly at each scale's pixel centres.
- `.import` files: Godot's default `fix_alpha_border` rewrites the colour of pixels with zero alpha, which is most of the data in these textures. `project.godot` `[importer_defaults]` turns it (and premultiplied alpha) off for new imports; a test checks that every committed `.import` of a built texture agrees.
- The probe is a folder (`tools/artbuild/tests/data/probe/parts.svg`, `palette.tres`, `pose.json`), not a single file.
- A blade-tagged part reports `tip` (u from the pivot) beside its box: the main pose's vertex farthest from the posed pivot. The review draws the arc through it.

## The review

```
tools/artbuild/review.sh <asset> [--root res://dir] [--out dir] [--carries-ember] [action...]
```

Builds the asset with its 4x masters, then (`tools/artbuild/review.gd`, under xvfb, with the game's own shaders and `LightField`) writes `sil64.png`, `dusk1x.png`, `pitch1x.png`, `detail4x.png` and a contact sheet per action to `docs/gallery/<asset>/` (ADR-0023 Decision 5). The lit test room is `tests/screenshot/rooms/lit_test.room`. `ci/lighting.sh` runs it on the test prop and on the test crawler.

- `sil64.png` draws the first frame at the scale that makes the asset's tallest frame 64 px, white on black, in a view that is 96 px square or larger on the side where the frame would not fit with a 12 px margin: a wide, low asset (the Soot-tick, the Gnawer) is drawn whole at the same scale, never cut to a bar.
- An asset's emissive regions are lights of their own kind: kind `eye` is `LightingTuning.eye` (24 u, steady, BUILD.md section 10 "enemy eyes: point lights, tiny"), every other emissive part is a `fire`. A Wick (`--carries-ember`) is lit by its own ember.
- The script exits 2 for bad arguments or no build of the asset, 1 for a script or shader error, and `review.sh` passes that status on.
- `tools/artbuild/review_check.py <dir> <sheet.json>` measures the crawler's pictures (a whole silhouette about 64 px tall and wider than tall; a dark wall above the eye at Pitch and a bright glint) and is what `ci/lighting.sh` runs on them; `tests/art/src/crawler/` is the wide test creature with `emissive eye` that it needs.
