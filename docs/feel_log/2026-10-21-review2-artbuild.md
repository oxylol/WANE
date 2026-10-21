# 2026-10-21: Phase 2 task 1, second review, the art build (artbuild)

- Author: Claude
- BUILD.md section and table row: section 10, Style (silhouette at 64 px), Lighting ("enemy eyes (point lights, tiny)"), Pipeline (Review); Immaculate Checklist, Graphics: "Every enemy is identifiable by silhouette alone at 64 pixels tall"
- Fixture(s): none (presentation and tooling only; `core/` and every golden hash are untouched)
- Contact sheet: `docs/feel_log/2026-10-21-review2-artbuild/` (`crawler_before_after.png`, the crawler's review in `crawler/`, the first review's pictures of it in `before/`)

## Change

No tunable number moved (rule 6): every limit below is a validation bound of the build tool, not a design value. The review's eye light is `LightingTuning.eye`, which already existed in `content/lighting.tres` (24 u, energy 0.9, steady) and which `review.gd` now uses.

| What | Before | After |
| --- | --- | --- |
| `build.py --check` scope | the folders of the assets just built | every file under every out root |
| a PNG compared in `--check` | decoded pixels only | decoded pixels and the chunk types the build writes |
| `sil64.png` of the test crawler | 96 x 96, one white bar on both edges | 213 x 96, whole |
| light of an `emissive eye` region in the review | `fire` (160 u, 1800 K, flickering) | `eye` (24 u, steady) |
| `review.sh` exit status on a failed review | 0 | the review's own (2, 1, 0) |
| art unit tests (`tools/ci/test_artbuild.py`) | 98 | 134 |
| the reviewer's one-line mutants of the Python build caught | 3 of 9 | 9 of 9 (the six survivors are killed) |

## Why: each finding, the measurement and the picture

**T1, `--check` ignored everything outside the built folders.** `check_root` scanned only `scope_of(files, built)`. Reproduced on the real tree: `assets/art/build/stock/wax_stock.png` (a copy of a candle render) printed `check ok`, exit 0. Now it prints `not build output (renders are never hand-edited): assets/art/build/stock/wax_stock.png`, exit 1; the same for a PNG at `tests/art/build/readme.png`, a copied build folder, the committed render of an asset whose source was deleted and its manifest lines, a text chunk added to a PNG (the pixels equal, so the pixel hash passed), and trailing bytes after IEND. A recompression by another zlib still passes (ADR-0026's choice stands). A corrupt PNG or manifest is a line of output, not a traceback. A full build now removes the render of a deleted source and the `.import` of a removed PNG, so the repair is one command. The 4x masters are tolerated by exact name, not by "contains `@4x.`", and `.uid` is no longer ignored (no root holds one). Tests: 12 in `CheckMode` and 3 in `Cli`, taken from the reviewer's tamper script.

**T2, an eye lit as a campfire.** `review.gd` spawned `LightingTuning.fire` at every emissive region. Measured on the crawler's `pitch1x.png` (mean luminance 0 to 255): the wall 24 to 40 u above the eye 52.3, now 19.2; 40 to 60 u 41.8, now 18.7; the body's middle 86.1, now 44.1; the far wall 4.7 either way; the glint itself 234, now 237. In `crawler_before_after.png` (bottom row) the old picture is a creature glowing orange on a lit floor; the new one is a dark body with a small warm point and a halo of about 24 u. The Clinger line ("the ember reveals it 30 frames before it drops") and the style gate's "reads at Pitch" are judged on this picture, so it had to be the game's light. `ci/lighting.sh` now reviews the crawler and `tools/artbuild/review_check.py` fails the old pictures (wall 52.3 against a limit of 35).

**T3, `sil64.png` cut a wide asset to a bar.** The view was a fixed 96 px square. It is now 96 px or larger on the side where the frame does not fit with a 12 px margin, at the same scale (the tallest frame 64 px). Before: white in columns 0 to 95, 60 white pixels on the picture's edge, the head off the picture. After: white from x 13 to 199 and y 17 to 82, none on the edge; the view is 213 x 96. A candle (taller than wide) keeps its 96 x 96 view. The new crawler is 115 u across its legs and 38 u tall.

**T4, bad `pose.json` accepted or crashing.** `{"tiks": 5}` built with 3 ticks and exit 0; a NaN affine wrote a sheet.json with six bare `NaN` tokens (not JSON; Godot cannot read it) that the validator called a number. Now every one of those is a `source error` (the Cli test builds seven bad sources through `main()` and asserts the message, the exit 1 and that nothing is written): unknown keys at every level of the pose, a `key` or `loop` that is not a boolean, `true` for `fps` or `ticks`, a non-finite or collapsing affine, a number or key given twice, wrong container types; `data-bevel-u="abc"`, a bad group transform, a vertex beyond 4096 u; a numeric palette material, a list for `variants`. `sheet.json` is written with `allow_nan=False` and the schema's "number" is finite.

**T5, an emissive part that vanishes.** A part tagged `emissive` whose material has no `emissive` colour was accepted: the shader drops the ink around it and draws no glow. It is now a `PaletteError` naming the part and the material (also strength 0, and a strength with no colour); a variant may still switch a glow off for closed eyes.

**T6, six of nine mutants survived.** See Tests.

**T8, a line after Z.** `M10 10 L30 10 L30 30 Z L10 30 L10 50 L40 50 Z` lost the start point of its second subpath (4680 of 65536 pixels disagreed with cairosvg). Fixed, and the 16 syntax cases the reviewer compared with cairosvg are now a test (`SyntaxAgainstCairo`), the new case included. Path data must begin with a moveto.

**T9, `review.sh` always exited 0.** `... | grep -v ... || true` swallowed the script's status. Now `review.sh candle_stump --root res://nowhere` exits 2 and `review.sh` with no argument exits 2 with a usage line.

**T10, stale documents.** The README said bevel default 3 (it is 8, max 16, since ADR-0026), "byte for byte" (a PNG is compared by its pixels), "about 45 s" (64 to 69 s measured with the machine loaded) and that a `.uid` is tolerated in an out root; it, `tests/art/README.md`, the `build.py` docstring and ADR-0023 1.1 and 1.8 now say what the code does, and the review 2 addendum in ADR-0023 records the decisions.

## Tests that pin it (each mutated and caught)

Mutants are one line of `tools/artbuild/*.py` changed in a private copy of the tree, with the outputs rebuilt first where the line feeds them, then `tools/ci/test_artbuild.py` (134 tests, 64 to 69 s with the machine loaded) and `tools/ci/test_ink_layout.py` (3) run. A mutant is killed when either fails. All 21 were killed; the six marked R are the reviewer's survivors.

| Mutant (one line) | Killed by |
| --- | --- |
| R: `noise.py` wobble1 cells 16 to 8 | `test_the_noise_cell_counts_are_the_shaders` (reads `noise.py` as literals, compares the shader's `INK_WOBBLE1_CELLS`, `INK_WOBBLE2_CELLS`, `INK_NOISE_PX`, `INK_BRUSH_TILE_U`) |
| R: `MAX_BEVEL_U` 16 to 1600; tilt lower bound 0 to -90 | `test_the_bevel_and_tilt_ranges_have_both_ends` |
| R: fps upper bound 60 to 6000 | `test_fps_and_ticks_have_their_bounds` |
| R: the `--check` toolchain gate off | `test_check_needs_the_pinned_toolchain_and_a_build_only_warns` |
| R: `tool_hash` ignores the package's code | `test_editing_any_module_of_the_package_changes_the_hash` and one more |
| `check_root` stops scanning the out root | three `CheckMode` tests (copied folder, deleted source, picture at the out root) |
| `check_root` stops flagging manifest lines of an asset with no source | `test_a_deleted_source_leaves_nothing_unflagged` |
| `manifest.same` allows any chunk | `test_a_chunk_added_by_hand_fails_but_another_deflate_stream_does_not` |
| the master pattern becomes `.*@4x.*`; any `.import` tolerated | `test_only_a_real_master_or_the_import_of_a_known_file_is_tolerated` |
| unknown pose keys ignored; a NaN affine allowed; `key` truthy | `test_a_typo_is_an_error_not_a_default`, `test_an_affine_is_six_finite_numbers_that_keep_the_part`, `test_every_field_has_its_type`, and the `Cli` source-error test |
| the emissive check off | `test_an_emissive_part_needs_a_material_that_glows` |
| `parse_path` after Z as before | `test_a_drawing_command_after_z_starts_at_the_closed_subpaths_start`, `test_every_syntax_fills_what_cairosvg_fills` |
| duplicate keys allowed; NaN a number in the schema | `test_the_file_may_not_hold_nan_or_a_key_twice`, `test_json_has_no_nan_and_neither_has_a_sheet` |
| a bad group transform escapes as `ValueError`; the coordinate bound off | `test_a_number_that_is_not_one_is_a_message`, `test_a_part_off_the_page_is_rejected` |
| `SMEAR_STEP_U` 0.5 to 4 | three smear tests (killed before this change too) |

What the GPU tests hold: `ci/lighting.sh` fails the first review's pictures of the crawler (a clipped silhouette on its edge, the wall above the eye at 52.3 against a limit of 35), measured with `tools/artbuild/review_check.py`, whose own tests (`test_review_check.py`, 8) draw synthetic pictures for each failure. `ci/render.sh`: 30 and 27 checks, 0 failed. `ci/lighting.sh`: passed, 72 s with the machine loaded.

## Critique of the new pictures (against BUILD.md section 10)

The crawler is a test creature, not shipped art; it was drawn three times. First a flat lizard (legs read as planks, the head a ball with a seam); then a domed tick whose near legs lay across the belly as planks; now all four legs are behind the carapace so only the knees and feet show. At 64 px (`crawler/sil64.png`) it reads as a domed beetle with three spines, two bent legs trailing at the left and a head with a hooked jaw at the right; the legs are hairlines about 3 px wide, which is as thin as an enemy's legs should go before they vanish. The two front legs are mostly hidden behind the head and the jaw: a known weakness of this test creature (a real enemy would give them their own silhouette). At Dusk (`crawler/detail4x.png`) the ink line is open and wobbles, the carapace has two values and a rim, the spines are lit bone, the eye is a bright disc with a glow. At Pitch (`crawler/pitch1x.png`) the creature is a dark shape against the ember-lit wall with a warm glint at the head: the figure and the ground separate by the ember on the left, the eye shows where it looks. The skitter (`crawler/skitter.png`) swings the legs 14 degrees either way over four frames; the body bobs 0.6 u on the passing frames.

## How it plays now

Nothing the player holds changed. The art build refuses a stock picture, a typo in a pose and an eye with no glow; the review draws a wide enemy whole and lights its eyes as eyes.

## Open questions for the director

Look at `crawler_before_after.png`: the top row is the silhouette before and after, the bottom row the Pitch picture before and after. Is a 24 u eye light the right size for a Clinger (BUILD.md says "tiny")? `LightingTuning.eye` is 24 u, energy 0.9 (one number each in `content/lighting.tres`); the review is the only caller today.
