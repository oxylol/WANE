# CODEMAP: read this first

Godot 4.7.2, strict GDScript, headless. `core/` is the deterministic 60 Hz simulation (no Node, ints in 1/256-unit sub-pixels, `Fx.SUB`); `game/` draws it; `content/` holds every tunable number; a run is a seed plus inputs. Law `CLAUDE.md`; spec `docs/BUILD.md` (s5 movement, s6 combat, s13 architecture, s15 checklist; headings only); status `PROGRESS.md`.

Entries read `path symbol`: grep the file for the symbol. `tools/ci/test_codemap.py` checks each path exists and defines its symbol.

## Directories

- `core/sim/` Simulation, Scenario, InputFrame, InputRing, Fx (fixed-point), StateHasher, ContentHash, SimCache, Replay, ReplayRecorder, ReplayPlayer, SimEvents.
- `core/physics/` TileGrid, SolidBox, Body, CollisionWorld (moves), CollisionQueries, WorldTuning, FlatWalk (flat-floor fast path).
- `core/fsm/` Player and its parts (PlayerStrikes, PlayerWall, PlayerContacts, PlayerSpeed, PlayerSpells, PlayerCombat, PlayerInput, PlayerState, PlayerProbe, EmberToss); MovementTuning to MovementParams; KitTuning to KitParams.
- `core/combat/` Combat, AttackSet and AttackDef (the Taper), CombatTuning to CombatParams, Flame, Kindling, Hearts, Vitals, KillEmber, FireTrail, HitKind, EnemyCells (query cells, native `WaneCells`).
- `core/enemies/` Enemy, EnemyDef, EnemyAttack, EnemyProbe, TrainingDummy, EnemyBatch (one native call). `core/rooms/` RoomData, RoomSet, RoomJoins, ZoneDef. `core/rng/` Rng, RngStreams. `core/native/` NativeBackend (`use_native`, off/auto/on), NativeWorld (box mirror), NativeRef (twins of `native/src/`: sweep.cpp is CollisionWorld, cells.cpp EnemyCells; `game/native/native_boot.gd` reads `WANE_NATIVE`). `core/items/` ProcBus, StackingCurve, Votive, VotiveListener, ProcSource, RunMods.
- `game/` root: SimDriver, Main, ReplayFiles, EaseMath. `game/input/` InputLayer, InputSettings. `game/camera/` CameraRig, CameraSubject, GameCamera, CameraTuning. `game/feedback/` HitFeedback, ScreenShake, FeedbackOverlay, FeedbackTuning. `game/vfx/` VfxBudget (`spawn`, `spawn_rect`). `game/lighting/` LightField, RoomSdf, ShadowBuffer, ShadowTwin, LightKind, LightWord (shaders: `shaders/lighting/`). `game/audio/` Voices, Synth. `game/debug/` DebugOverlay, DebugBoxes, DebugControls, InputHistory. Views: `game/player/` and siblings.
- `content/` see Tunable numbers. `tools/ci/` test gate (`tools/ci/quiet_report.gd`); `tools/replay/` fixtures, runner, play, film, trace, bless; `tools/bench/` physics, proc, stress, stage and frame benches (PerfStats, PerfBudget, FrameProbes), `tools/perf/make_stress.py`; `tools/room_editor/` the room editor (below).
- `tests/unit/` gdUnit4 suites. `tests/replay/` fixtures by folder (camera, combat, core, doors, movement, physics, procs, rooms, tech, zone1), test rooms `tests/replay/rooms/`, goldens `tests/replay/golden_hashes.txt`. `tests/support/` PhysicsKit, CameraRun, ShaftJumps. `tests/perf/` the stress room `tests/perf/rooms/stress.room` and run `tests/perf/stress_run.fixture`.
- `ci/` `ci/test.sh`, `ci/unit.sh`, `ci/perf.sh`, `ci/lint.sh`, `ci/setup_godot.sh`, `ci/build_native.sh`, `ci/native_release_check.sh`; `.github/workflows/ci.yml`. `docs/adr/`, `docs/feel_log/`.

## Entry points

- Loop: `game/sim_driver.gd _process` to `game/sim_driver.gd _run_owed_ticks` to `game/sim_driver.gd step_once`: `InputLayer.poll`, `Simulation.step`, `ReplayRecorder.record`, signal `ticked`. `game/main.gd _on_ticked` then updates views, camera, feedback, HUD, overlay.
- Simulation: `core/sim/simulation.gd _init` builds rng, ring, rooms, world, tunings, player, enemies. `core/sim/simulation.gd step`: ring push, `Player.step`, each `Enemy.step`, `Combat.resolve`, `_take_door`, tick+1, hash every 60 ticks. `VERSION` sits at the top.
- Player: `core/fsm/player.gd step`: hitstop, timers, strike and spell advance, turn, crouch, toss, dash, jump, attack, spell start, `_move`, `_after_move`.
- Combat: `core/combat/combat.gd resolve`: effects age, player hits (strike, spells, pogo, trails), enemy hits (parry window).
- Collision moves: `core/physics/collision_world.gd move_x`, `:367 move_y`, `:455 landing_contact`, `:520 walk`, `:853 drop_through`.
- Rooms: `core/rooms/room_data.gd parse` (problems in `errors`), `:91 load_id`, `:348 build_world`; `core/rooms/room_set.gd reach` (rooms reachable by doors); `core/rooms/room_joins.gd errors`.
- Room editor: `addons/room_editor/plugin.cfg` shim to `tools/room_editor/room_editor_plugin.gd RoomEditorPlugin`; `tools/room_editor/room_editor_panel.gd RoomEditorPanel`; `tools/room_editor/room_document.gd RoomDocument`; in the same folder RoomCanvas, RoomHistory, RoomDoorEdits, RoomObjectEdits, EntityKinds.
- Input: `core/sim/input_ring.gd push`, `:97 merge`, `:123 press_age`, `:170 consume`; ages 0 to 8.
- Hashes: `core/sim/state_hasher.gd add_int` (stateful classes have `hash_into`); `core/sim/content_hash.gd add_resource`, `:21 add_room`. Replays: `core/sim/replay.gd encode`, `core/sim/replay_player.gd verify`.
- Fixtures: `tools/replay/fixture.gd parse_file`; `tools/replay/fixture_runner.gd run_all` (`plan_shards`, 10 s budget), `run_fixture`, `_bless`.
- Films: `tools/replay/film.gd _initialize` (the game's own views, F3 on); `tools/replay/play.gd _initialize` (headless).
- Camera: `game/camera/camera_rig.gd step` (per tick), `game/camera/game_camera.gd show_at` (between ticks).
- Feedback: `game/feedback/hit_feedback.gd on_tick` reads SimEvents; sparks via `game/vfx/vfx_budget.gd spawn` and `:134 claim_screen`, sounds via `game/audio/voices.gd play`.
- Lighting (`-- --lighting=pitch|dusk|off`): `game/lighting/light_field.gd present`, `prebuild`; `tools/lighting/render.sh`, `ci/lighting.sh`. Frame bench `tools/bench/frame_bench.gd _run`; doors `tools/bench/door_bench.gd _finish`.
- F3: `game/debug/debug_overlay.gd toggle`; `game/debug/debug_controls.gd handle_key` (F3 overlay, F4 pause, F5 one tick, F6 ten).

## Fixture language (spec: `tests/replay/README.md`, ADR-0006)

Header `fixture`, `doc` (required), `seed`, `room <id>` (test/<name> means <name>.room in `tests/replay/rooms/`; other ids are in `content/rooms/`), `wick`, `spawn x y`, `option k v`, `frames N`; blocks `input ... end` (`<frame> jump|atk|dash|spell|mend|vessel|toss|L|R|U|D`, `!jump` a one-tick tap) and `expect ... end` (`at F`, `during A..B`, `never A..B`, `mark name A..B`).
A condition is `key op value`, keys from `core/sim/simulation.gd probe`: player keys in `core/fsm/player_probe.gd read`, `enemy.<k>` and `enemy<n>.<k>` in `core/enemies/enemy_probe.gd read`, `event.<name>`, `held.<BUTTON>`, `press_age.<BUTTON>`. Values: integers, `12u` (x256), `key@mark`, `key@(mark+3)`, sums, or a word. A word must be an identifier listed by `probe_words(key)` (`state`, `action`, `chain`, `spell`, `tier`, `room`, enemy `state`) or the fixture fails; so does any expectation that cannot be evaluated.

## Tunable numbers (.tres files in BUILD.md units, compiled at load, each with `validate()`)

- `content/wicks/ash/movement.tres` (`core/fsm/movement_tuning.gd compile`), `content/wicks/ash/kit.tres` (`core/fsm/kit_tuning.gd compile`), `content/wicks/ash/taper.tres` (AttackSet); loaded by `Simulation._build_player`.
- `content/combat/combat.tres` (`core/combat/combat_tuning.gd compile`); `content/physics/world.tres` (WorldTuning); `content/enemies/dummy.tres` (EnemyDef; kinds in `Simulation.ENEMY_KINDS`); `content/zones/zone1.tres` (ZoneDef); `content/perf/budget.tres` (PerfBudget).
- Presentation: `content/camera.tres`, `content/feedback.tres`, `content/player_view.tres`, `content/input/input_settings.tres`, `content/lighting.tres`.
- Rooms: `content/rooms/zone1/` (12 tech rooms; routes, controls and `zone1_loop` in `tests/replay/zone1/`), `content/rooms/sandbox.room`. A tuning change needs a feel-log entry, a BUILD.md update, and a re-bless.

## Commands (repo root; `godot` on PATH or `GODOT`)

- Import: `godot --headless --path . --import`. Compile check only (5 s, includes core purity): `godot --headless --path . --script tools/ci/run_tests.gd -- --stage compile`.
- Agents: `ci/test.sh --quiet` (one line per stage, failures only) and `ci/unit.sh --quiet <suite or folder>`; see `tests/README.md`.
- All: `ci/test.sh` (must print `ALL STAGES PASSED`). Stages in order: `compile` (every script, core purity), `content` (every .tres validates, every .room parses), `fixtures` (expectations, replay round trip, goldens), `unit` (gdUnit4).
- One fixture, no golden check: `godot --headless --path . --script tools/replay/check.gd -- tests/replay/movement/jump_tap.fixture`. Probe table: `tools/replay/trace.gd -- <fixture> state x y`.
- Bless: `godot --headless --path . --script tools/replay/bless.gd`. It refuses if a fixture's hash changed with the same inputs and content and `Simulation.VERSION` is unchanged: bump it in `core/sim/simulation.gd`, bless, commit `tests/replay/golden_hashes.txt`.
- Contact sheet, F3 on (needs a display): `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1920x1080 --script tools/replay/film.gd -- out.png --overlay on --zoom 3 <fixture>`.
- One gdUnit suite: `ci/unit.sh --quiet tests/unit/core/test_rng.gd`; raw failures: `python3 tools/ci/unit_failures.py`.
- Lint: `ci/lint.sh` (gdlint, gdformat --check, greps; needs `tools/requirements.txt`); fix format with `gdformat <file>`.
- Coverage (gate 85%): `python3 tools/ci/gd_coverage.py --min 85`. Python tests: `tools/ci/test_*.py`. Benches: `tools/bench/*_bench.gd`. Perf gate: `ci/perf.sh [--only stress|zone|frame]` (`PERF_LIB=release`; CI jobs `perf`, `perf-stress`) against `content/perf/budget.tres`; `tools/bench/stage_bench.gd` times a tick's stages.

## Rules agents trip on

- Warnings are errors (ADR-0002): type everything; no `@warning_ignore` or `# gdlint:` comments; `Fx.div_floor` or `Fx.div_round` for possibly negative operands.
- Typed collections only (`Array[T]`, `Dictionary[K, V]`); `ci/lint.sh` rejects bare ones.
- No tunable literals in code: designer numbers live in `content/*.tres` with a `validate()` rule.
- `core/` purity (`tools/ci/core_purity.gd`): no float, float literal, Vector2, Rect2, Color, float maths (`lerp`, `floor`, `round`, `sqrt`), `randi`, the word `seed`, Node, `Time`, `OS`, `Input`, `_process`, `await`, file writes. Use Vector2i, Rect2i, RngStreams.
- `gdlintrc`: tabs, 100 columns, 1000 lines a file (`core/fsm/player.gd` is near it), 20 public methods, 10 arguments.
- Fixture words are identifiers and a fixture needs a `doc` line. A change that moves a golden needs `Simulation.VERSION` + 1. The doc wins over code unless an ADR says otherwise.

## ADR index (files in `docs/adr/`)

- `0001-pin-engine-and-toolchain`, `0002-gdscript-warning-policy` (warnings are errors), `0003-integer-subpixel-units` (256 per unit), `0004-input-frames-and-ring-buffer`, `0005-rng-split-streams`, `0000-template`: the foundations.
- `0006-replays-and-fixtures` `.wrp`, fixture language, goldens, 10 s budget.
- `0007-fixed-step-driver`, `0008-physics-sweep` (32 u tiles, validated slopes), `0009-room-format` (tiles, solids, markers, doors).
- `0010-player-movement-rules`
- `0011-camera` Rest on support heights.
- `0012-debug-overlay-and-frame-stepper` F3 overlay; F4 to F6 step.
- `0013-combat` Combat resolves once per tick, after all movement.
- `0014-doors-and-zones` Paired `door` lines.
- `0015-procs-and-votives` Proc bus after the player's hits; Votives are content.
- `0016-tech-rooms-teach-they-do-not-gate` A tech room is the cheapest route, not the only one.
- `0017-ember-toss-cancel-over-a-chasm`
- `0019-zone1-grey-box-gates-and-teaches`
- `0020-stress-room-and-perf-gate` Stress room, perf gates, the gate met (Decision 17).
- `0022-native-physics-sweep`
- `0021-native-extension-toolchain` godot-cpp pin, `WANE_NATIVE`, parity rules.
- `0018-room-editor-install`
- `0023-art-pipeline-and-lighting` Baked SDF channels, live ink shaders, room SDF shadows.
