# tests/art

Sources for the art build's own tests (`tools/artbuild/`, ADR-0023). Not shipped art, never in a build of the game.

- `src/candle_stump/`: a prop designed silhouette first at 64 px (a stump of wax with a melted lip, one drip that breaks the outline, a pool, a wick and a flame tagged `emissive`) with two actions, to exercise parts that share a material, a compound path, a tagged emissive part, palette variants and more than one action.
- `build/candle_stump/`: its build output (`python3 tools/artbuild/build.py candle_stump`). Never edit by hand: `python3 tools/artbuild/build.py --check` fails on any byte that a fresh build would not write.
