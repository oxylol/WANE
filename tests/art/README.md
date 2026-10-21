# tests/art

Sources for the art build's own tests (`tools/artbuild/`, ADR-0023). Not shipped art, never in a build of the game.

- `src/candle_stump/`: a prop designed silhouette first at 64 px (a stump of wax with a melted lip, one drip that breaks the outline, a pool, a wick and a flame tagged `emissive`) with two actions, to exercise parts that share a material, a compound path, a tagged emissive part, palette variants and more than one action.
- `src/crawler/`: a wide, low creature (115 u across its legs, 38 u tall) with four jointed legs, three spines, a hooked jaw and one `emissive eye`, with `idle` and a four-frame `skitter`. The review's 64 px silhouette must draw it whole and its Pitch picture must light the eye as a tiny point light, not as a fire (`tools/artbuild/review_check.py`, run by `ci/lighting.sh`).
- `build/<asset>/`: the build output (`python3 tools/artbuild/build.py`). Never edit by hand: `python3 tools/artbuild/build.py --check` fails on a render a fresh build would not draw (a PNG is compared by its pixels and must carry no extra chunk), and on any file in `build/` that no source builds.
