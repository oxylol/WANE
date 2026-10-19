# CODEMAP: read this first

Godot 4.7.2, strict GDScript, headless. `core/` is the deterministic 60 Hz simulation (no Node, ints in 1/256-unit sub-pixels, `Fx.SUB`); `game/` draws it; `content/` holds every tunable number; a run is a seed plus inputs. Law `CLAUDE.md`; spec `docs/BUILD.md` (s5 movement, s6 combat, s13 architecture, s15 checklist; headings only); status `PROGRESS.md`.

Entries read `path symbol`: grep the file for the symbol. `tools/ci/test_codemap.py` checks each path exists and defines its symbol.

## Directories

- `core/sim/` Simulation, Scenario, InputFrame, InputRing, Fx (fixed-point), StateHasher, ContentHash, Replay, ReplayRecorder, ReplayPlayer, SimEvents.
- `core/physics/` TileGrid, SolidBox, Body, CollisionWorld (moves), CollisionQueries, WorldTuning.
- `core/fsm/` Player and its parts (PlayerStrikes, PlayerWall, PlayerContacts, PlayerSpeed, PlayerSpells, PlayerCombat, PlayerInput, PlayerState, PlayerProbe, EmberToss); MovementTuning to MovementParams; KitTuning to KitParams.
- `core/combat/` Combat, AttackSet and AttackDef (the Taper), CombatTuning to CombatParams, Flame, Kindling, Hearts, Vitals, KillEmber, FireTrail, HitKind.
- `core/enemies/` Enemy, EnemyDef, EnemyAttack, EnemyProbe, TrainingDummy. `core/rooms/` RoomData, RoomSet, RoomJoins, ZoneDef. `core/rng/` Rng, RngStreams. `core/items/` ProcBus, StackingCurve, Votive, VotiveListener, ProcSource, RunMods (docs/adr/0015). `core/clock/` empty.
- `game/` root: SimDriver, Main (boot scene), ReplayFiles, EaseMath. `game/input/` InputLayer, InputSettings. `game/camera/` CameraRig, CameraSubject, GameCamera, CameraTuning. `game/feedback/` HitFeedback, ScreenShake, FeedbackOverlay, FeedbackTuning. `game/vfx/` VfxBudget. `game/audio/` Voices, Synth. `game/debug/` DebugOverlay, DebugBoxes, DebugControls, InputHistory. Grey-box views: `game/player/`, `game/enemies/`, `game/combat/`, `game/rooms/`, `game/ui/`. Empty: `game/hub/`, `game/lighting/`, `shaders/`, `assets/`.
- `content/` see Tunable numbers. `tools/ci/` test gate; `tools/replay/` fixtures, runner, play, film, trace, bless; `tools/bench/` physics bench; `tools/debug/`, `tools/importers/`, `tools/style_gate/` empty; no room editor yet.
- `tests/unit/` gdUnit4 suites. `tests/replay/` fixtures by folder (camera, combat, core, doors, movement, physics, rooms, tech), test rooms `tests/replay/rooms/`, goldens `tests/replay/golden_hashes.txt`. `tests/support/` PhysicsKit, CameraRun, ShaftJumps. `tests/perf/`, `tests/screenshot/` empty.
- `ci/` `ci/test.sh`, `ci/lint.sh`, `ci/setup_godot.sh`; `.github/workflows/ci.yml`. `docs/adr/`, `docs/feel_log/` (one entry per tuning change).

## Entry points

- Loop: `game/sim_driver.gd _process` to `game/sim_driver.gd _run_owed_ticks` to `game/sim_driver.gd step_once`: `InputLayer.poll`, `Simulation.step`, `ReplayRecorder.record`, signal `ticked`. `game/main.gd _on_ticked` then updates views, camera, feedback, HUD, overlay. Slow motion is the driver's (`game/sim_driver.gd slow`).
- Simulation: `core/sim/simulation.gd _init` builds rng, ring, rooms, world, tunings, player, enemies. `core/sim/simulation.gd step`: ring push, `Player.step`, each `Enemy.step`, `Combat.resolve`, `_take_door`, tick+1, hash every 60 ticks. `VERSION` sits at the top.
- Player: `core/fsm/player.gd step`: hitstop, timers, strike and spell advance, turn, crouch, toss, dash, jump, attack, spell start, `_move`, `_after_move`.
- Combat: `core/combat/combat.gd resolve`: effects age, player hits (strike, spells, pogo, trails), enemy hits (parry window).
- Collision moves: `core/physics/collision_world.gd move_x`, `:367 move_y`, `:455 landing_contact`, `:520 walk`, `:853 drop_through`.
- Rooms: `core/rooms/room_data.gd parse` (problems in `errors`), `:91 load_id`, `:348 build_world`; `core/rooms/room_set.gd reach` (rooms reachable by doors); `core/rooms/room_joins.gd errors`.
- Input: `core/sim/input_ring.gd push`, `:97 merge`, `:123 press_age`, `:170 consume`; ages 0 to 8.
- Hashes: `core/sim/state_hasher.gd add_int` (stateful classes have `hash_into`); `core/sim/content_hash.gd add_resource`, `:21 add_room`. Replays: `core/sim/replay.gd encode`, `core/sim/replay_player.gd verify`.
- Fixtures: `tools/replay/fixture.gd parse_file`; `tools/replay/fixture_runner.gd run_all` (sharded, 10 s budget), `:218 run_fixture`, `:489 _bless`.
- Films: `tools/replay/film.gd _initialize` (the game's own views, F3 on); `tools/replay/play.gd _initialize` (headless).
- Camera: `game/camera/camera_rig.gd step` (per tick), `game/camera/game_camera.gd show_at` (between ticks).
- Feedback: `game/feedback/hit_feedback.gd on_tick` reads SimEvents; sparks via `game/vfx/vfx_budget.gd spawn` and `:134 claim_screen`, sounds via `game/audio/voices.gd play`.
- F3: `game/debug/debug_overlay.gd toggle`; `game/debug/debug_controls.gd handle_key` (F3 overlay, F4 pause, F5 one tick, F6 ten).

## Fixture language (spec: `tests/replay/README.md`, ADR-0006)

Header `fixture`, `doc` (required), `seed`, `room <id>` (test/<name> means <name>.room in `tests/replay/rooms/`; other ids are in `content/rooms/`), `wick`, `spawn x y`, `option k v`, `frames N`; blocks `input ... end` (`<frame> jump|atk|dash|spell|mend|vessel|toss|L|R|U|D`, `!jump` a one-tick tap) and `expect ... end` (`at F`, `during A..B`, `never A..B`, `mark name A..B`).
A condition is `key op value`. The key is a `core/sim/simulation.gd probe` key: player keys in `core/fsm/player_probe.gd read`, `enemy.<k>` and `enemy<n>.<k>` in `core/enemies/enemy_probe.gd read`, `event.<name>`, `held.<BUTTON>`, `press_age.<BUTTON>`. The value is an integer, `12u` (units, times 256), `key@mark`, `key@(mark+3)`, sums, or a word. A word must be an identifier listed by `probe_words(key)` (`state`, `action`, `chain`, `spell`, `tier`, `room`, enemy `state`) or the fixture fails; so does any expectation that cannot be evaluated.

## Tunable numbers (.tres files in BUILD.md units, compiled at load, each with `validate()`)

- `content/wicks/ash/movement.tres` (`core/fsm/movement_tuning.gd compile`), `content/wicks/ash/kit.tres` (`core/fsm/kit_tuning.gd compile`), `content/wicks/ash/taper.tres` (AttackSet); loaded by `Simulation._build_player`.
- `content/combat/combat.tres` (`core/combat/combat_tuning.gd compile`); `content/physics/world.tres` (WorldTuning); `content/enemies/dummy.tres` (EnemyDef; kinds in `Simulation.ENEMY_KINDS`); `content/zones/zone1.tres` (ZoneDef).
- Presentation: `content/camera.tres`, `content/feedback.tres`, `content/player_view.tres`, `content/input/input_settings.tres`.
- Rooms: `content/rooms/zone1/` (12 tech rooms), `content/rooms/sandbox.room`. A tuning change needs a feel-log entry, a BUILD.md update, and a re-bless.

## Commands (repo root; `godot` on PATH or `GODOT`)

- Import: `godot --headless --path . --import`. Compile check only (5 s, includes core purity): `godot --headless --path . --script tools/ci/run_tests.gd -- --stage compile`.
- Agents: `ci/test.sh --quiet` (one line per stage, failures only) and `ci/unit.sh --quiet <suite or folder>`; see `tests/README.md`.
- All: `ci/test.sh` (must print `ALL STAGES PASSED`). Stages in order: `compile` (every script, `tools/ci/core_purity.gd`), `content` (every .tres validates, every .room parses), `fixtures` (expectations, replay round trip, goldens), `unit` (gdUnit4). Select with `-- --stage fixtures --stage unit`.
- One fixture, no golden check: `godot --headless --path . --script tools/replay/check.gd -- tests/replay/movement/jump_tap.fixture`. Probe table: `tools/replay/trace.gd -- <fixture> state x y vy`.
- Bless: `godot --headless --path . --script tools/replay/bless.gd`. It refuses ("refusing to bless") if a fixture's hash changed with the same inputs and content and `Simulation.VERSION` is unchanged: bump it in `core/sim/simulation.gd`, bless, commit `tests/replay/golden_hashes.txt` with the change.
- Contact sheet, F3 on (needs a display): `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1920x1080 --script tools/replay/film.gd -- out.png --overlay on --zoom 3 <fixture>` (`--every --from --frames --scale --set`).
- One gdUnit suite: `godot --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -rd reports -a res://tests/unit/core/test_rng.gd`; failures: `python3 tools/ci/unit_failures.py`.
- Lint: `ci/lint.sh` (gdlint, gdformat --check, greps; needs `tools/requirements.txt`); fix format with `gdformat <file>`.
- Coverage (gate 85%): `python3 tools/ci/gd_coverage.py --min 85`. Python tests: `python3 tools/ci/test_gd_coverage.py`, `python3 tools/ci/test_codemap.py`. Bench: `tools/bench/physics_bench.gd`.

## Rules agents trip on

- Warnings are errors (ADR-0002): type everything; no `@warning_ignore` or `# gdlint:` comments; `Fx.div_floor` or `Fx.div_round` for possibly negative operands.
- Typed collections only (`Array[T]`, `Dictionary[K, V]`); `ci/lint.sh` rejects bare ones.
- No tunable literals in code: designer numbers live in `content/*.tres` with a `validate()` rule.
- `core/` purity (`tools/ci/core_purity.gd`): no float, float literal, Vector2, Rect2, Color, float maths (`lerp`, `floor`, `round`, `sqrt`), `randi`, the word `seed`, Node, `Time`, `OS`, `Input`, `_process`, `await`, file writes. Use Vector2i, Rect2i, RngStreams.
- `gdlintrc`: tabs, 100-character lines, 1000 lines per file (`core/fsm/player.gd` is near it), 20 public methods, 10 arguments.
- Fixture words are identifiers and a fixture needs a `doc` line. A change that moves a golden needs `Simulation.VERSION` + 1. The doc wins over code unless an ADR says otherwise.

## ADR index (files in `docs/adr/`)

- `0001-pin-engine-and-toolchain` Godot 4.7.2, gdUnit4, gdtoolkit pinned.
- `0002-gdscript-warning-policy` Type and safety warnings are errors.
- `0003-integer-subpixel-units` Int sub-pixels, 256 per unit; content in design units.
- `0004-input-frames-and-ring-buffer` Latched presses; 8-frame ring.
- `0005-rng-split-streams` xoshiro128**, five streams.
- `0006-replays-and-fixtures` `.wrp`, fixture language, goldens, 10 s budget.
- `0007-fixed-step-driver` Step at the start of each period; lock to vsync.
- `0008-physics-sweep` 32 u tiles, solid boxes, validated slopes.
- `0009-room-format` Room text format: tiles, solids, markers, doors.
- `0010-player-movement-rules` How Ash's layers read BUILD.md s5.
- `0011-camera` Rest on support heights; never outrun the player.
- `0012-debug-overlay-and-frame-stepper` F3 overlay from the latest tick; F4 to F6 step.
- `0013-combat` Combat resolves once per tick, after all movement.
- `0014-doors-and-zones` Paired `door` lines, crossed inside the strip.
- `0015-procs-and-votives` The proc bus after the player's hits; a Votive is content behind a narrow listener API.
- `0000-template` The ADR template.
