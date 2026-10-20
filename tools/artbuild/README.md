# tools/artbuild

SVG part libraries in; sprite-sheet textures, normal and emissive maps and metadata JSON out. Design: `docs/adr/0023-art-pipeline-and-lighting.md` Decision 1 (BUILD.md section 10, Pipeline). Python 3.13 with the packages pinned in `tools/requirements.txt` (numpy, Pillow, CairoSVG, which needs `libcairo2`). Everything is float64 and integer maths with only IEEE-exact operations, so two builds are byte-identical (a unit test and `--check` hold it).

```
python3 tools/artbuild/build.py                       # all assets, all roots
python3 tools/artbuild/build.py candle_stump          # one asset (the manifest keeps the others' lines)
python3 tools/artbuild/build.py --jobs 0              # frames bake in all cores; same bytes
python3 tools/artbuild/build.py --masters candle_stump  # also write the 4x masters for review (never committed)
python3 tools/artbuild/build.py --check               # CI: fresh build, no cache, compared byte for byte
python3 tools/ci/test_artbuild.py                     # the unit tests (about 45 s)
```

Roots (`build.py ROOTS`): `assets/art/src/<asset>/` to `assets/art/build/<asset>/` (and `noise/noise.png`); `tests/art/src/` to `tests/art/build/` (the pipeline's own test prop, not shipped art); `tools/artbuild/tests/data/<asset>/` to `tests/screenshot/data/<asset>/` (the probe figure, which the shader and lighting builders render). Each out root has a `MANIFEST.json` with the SHA-256 of every file; a file that is not in it, other than Godot's `.import` and `.uid`, fails `--check`. Frames cache in `tools/out/artbuild_cache/` under the hash of the sources and of this code.

## A source folder

- `parts.svg`: the subset in `svg.py` (path M L H V C Q Z, circle, ellipse, rect, polygon, `g` with a transform; fills, strokes, gradients, styles and every other element are lint errors). One user unit is 1 u. A part is a leaf element with `id`, `data-z` (unique), `data-pivot`, `data-tags` (`emissive blade eye pogo wax smear`), `data-bevel-u` (default 3), `data-tilt-deg` (default 62) and `data-normal` (`bulge` default, `flat`, `crease`). Several subpaths of one `path` are a union. The root's `data-origin-u="x y"` is the feet pivot.
- `palette.tres`: a Godot text resource whose `metadata/palette` dictionary names materials (lit, shadow, rim, gloss, optional emissive colour and strength), the material of every part and optional variants (see `palette.py`). Parts that share a material share a palette slot; there are 15 slots.
- `pose.json` (optional): actions of frames, each frame a per-part affine and optional smear sub-poses (see `pose.py`). The animator (Phase 2 task 2) emits this from its `.pose.tres` files. Without it the asset is one `idle` frame.

## What comes out (per asset, in `<out>/<asset>/`)

`<asset>@<s>x.shape.png` (S, U, side, emissive), `.normal.png` (normal x, y, z, gloss), `.parts.png` (palette slot, brush angle, taper, flags) for s in 1 and 2 (and 4 with `--masters`); `<asset>.palette.png`; `<asset>.sheet.json` (schema `sheet_schema.json`). Pages beyond the first are `<asset>.p<N>@...`. Decode constants are the block at the top of `channels.py`.

## Where this differs from, or settles, ADR-0023

- `parts.png` R holds the palette **slot** (a material), not a per-part index, so the palette is always 16 columns and an asset has at most 15 materials. `sheet.json` `parts[].index` is the slot.
- A cell is per action, so `sheet.json` has `cell_u` and `cell_origin_u` (the feet pivot inside the cell) per action; the top-level `cell_u` is the largest of them and `origin_u` the pivot in source coordinates. All boxes are in u relative to the pivot, x right and y down.
- The taper is found by casting a ray inward from each visible edge to the part's own outline (half the chord over 2.5 u), which is exact, instead of walking 24 steps.
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

Builds the asset with its 4x masters, then (`tools/artbuild/review.gd`, under xvfb, with the game's own shaders and `LightField`) writes `sil64.png`, `dusk1x.png`, `pitch1x.png`, `detail4x.png` and a contact sheet per action to `docs/gallery/<asset>/` (ADR-0023 Decision 5). The lit test room is `tests/screenshot/rooms/lit_test.room`. `ci/lighting.sh` runs it on the test prop.
