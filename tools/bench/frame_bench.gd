extends SceneTree
## The performance gate's presentation half (BUILD.md section 13: "Performance | a stress room
## (200 enemies, 40 procs, Pitch lighting) ... 60 fps with 99th-percentile frame time <= 16.0 ms"
## and the frame budget "Input + simulation step 3.0 ms; Sprite and animation submit 2.0; Lighting
## pass 3.0; VFX 2.0; Post 1.0; Audio and UI 1.0; Headroom 4.6"; docs/adr/0020). Plays the stress
## room's scripted run (tests/perf/stress_run.fixture) through the game's real scene tree: the
## boot scene game/main.tscn with its views, the camera, the hit feedback, the VFX budget, the
## voices, the HUD and, because the fixture says `lighting pitch`, the Phase 1 stand-in lighting
## ([LightingRig]). The driver steps exactly one tick a frame, from the fixture's inputs, through
## [method SimDriver.step_once]; the engine then runs the frame (the views' _process, every _draw).
##
## Per frame it records, in microseconds: the simulation step ([member SimDriver.last_step_us]),
## the tick as a whole (input, step, replay record, and the views capturing it), the time in the
## nodes' _process and in the queued _draw callbacks ([FrameProbes]: two probe nodes bracket every
## other node, the end of the frame's message queue closes the draw span) and the frame's wall time
## (the gap between one frame's start and the next's). The presentation's script time is the tick
## less the step (the views capturing it) plus the two probed spans: what the sprite, VFX, audio and
## UI stages cost in GDScript, read directly. It is not the wall time less the step, which this
## gate used before ADR-0020 Decision 18: wall time has a floor, so that figure rose by a
## millisecond when a native step fell by three and a half. That difference is still reported, as
## "frame less step", and not gated. Godot's Performance.TIME_PROCESS is not used: it is sampled
## once a second, not per frame. As in stress_bench.gd a frame's figure is the least over the
## repeated passes (the replay fixes the work).
##
## Headless (the dummy renderer) this is our script cost and is gated: the presentation's 99th
## percentile against sprite + VFX + audio and UI (5.0 ms, [method PerfBudget.presentation_us])
## and its worst frame against the spike limit. In a window (xvfb and llvmpipe: software
## rendering, no GPU) the same numbers are recorded and not gated: PROGRESS.md, Blocked 2.
## The report also lists what the VFX budget refused and displaced, and the voices in use on the
## ticks where a Taper hit fires its 39 procs.
##
##   godot --headless --path . --script tools/bench/frame_bench.gd [-- options]
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 \
##     --script tools/bench/frame_bench.gd -- --ticks 900
##
## Options: --quiet (the gate lines only), --report <path> (the full report to a file too),
## --repeats N (passes; the budget's by default, 1 in a window), --ticks N (only the first N
## ticks), --lighting pitch|off (default: the fixture's), --worst N (frames listed, default 8).

## Phases of a pass.
enum { SETUP, RUN, TEARDOWN }

const FIXTURE: String = "res://tests/perf/stress_run.fixture"
const P99: int = 990
const HEADLESS: String = "headless"

var _lines: PackedStringArray = PackedStringArray()
var _quiet: bool = false
var _failures: PackedStringArray = PackedStringArray()
var _budget: PerfBudget
var _fixture: Fixture
var _repeats: int = 1
var _total: int = 0
var _lighting: String = ""
var _gated: bool = false
var _worst: int = 8
var _report: String = ""

var _phase: int = SETUP
var _pass: int = 0
var _frame: int = 0
var _main: Main
var _driver: SimDriver
var _vfx: VfxBudget
var _voices: Voices
var _input: ScriptedInput
var _entered: int = 0
var _sim: PackedInt32Array = PackedInt32Array()
var _tick: PackedInt32Array = PackedInt32Array()
var _wall: PackedInt32Array = PackedInt32Array()
var _proc: PackedInt32Array = PackedInt32Array()
var _draw: PackedInt32Array = PackedInt32Array()
var _probes: FrameProbes = FrameProbes.new()
var _unread: int = 0
var _best_sim: PackedInt32Array = PackedInt32Array()
var _best_tick: PackedInt32Array = PackedInt32Array()
var _best_wall: PackedInt32Array = PackedInt32Array()
var _best_present: PackedInt32Array = PackedInt32Array()
var _runs_present: Array[PackedInt32Array] = []
var _best_proc: PackedInt32Array = PackedInt32Array()
var _best_draw: PackedInt32Array = PackedInt32Array()
var _best_gap: PackedInt32Array = PackedInt32Array()
var _best_capture: PackedInt32Array = PackedInt32Array()
var _facts: Facts = Facts.new()
var _end_hash: int = 0
var _vfx_capacity: int = 0
var _voice_cap: int = 0


## The scripted player: the fixture's input for the frame the bench is on.
class ScriptedInput:
	extends InputLayer
	var fixture: Fixture
	var index: int = 0

	func poll() -> InputFrame:
		return fixture.input_frame(index)


## What the pass showed, read from the first pass only. The peaks are the ticks that fire
## [member PerfBudget.min_peak_procs] procs or more: a burst (one Taper hit, up to
## [member PerfBudget.burst_procs_max]) or a crowd hit (an area hit on a pack).
class Facts:
	extends RefCounted
	var bursts: Peaks = Peaks.new()
	var crowd: Peaks = Peaks.new()
	var refused: int = 0
	var displaced: int = 0
	var dropped: int = 0
	var stolen: int = 0
	var max_effects: int = 0
	var draw_calls: int = 0
	var procs_total: int = 0
	var most_procs: int = 0
	var frames: int = 0
	var load_errors: PackedStringArray = PackedStringArray()


## The ticks of one kind of peak: what was alive and sounding on each.
class Peaks:
	extends RefCounted
	var voices: PackedInt32Array = PackedInt32Array()
	var effects: PackedInt32Array = PackedInt32Array()
	var procs: PackedInt32Array = PackedInt32Array()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_quiet = args.has("--quiet")
	_budget = load(PerfBudget.PATH) as PerfBudget
	if _budget == null:
		printerr("no perf budget at %s" % PerfBudget.PATH)
		quit(1)
		return
	for problem: String in _budget.validate():
		_fail("budget: %s" % problem)
	_fixture = Fixture.parse_file(FIXTURE)
	for e: String in _fixture.errors:
		_fail("stress fixture: %s" % e)
	_gated = DisplayServer.get_name() == HEADLESS
	_repeats = _arg_int(args, "--repeats", _budget.repeats if _gated else 1)
	_total = mini(_arg_int(args, "--ticks", _fixture.frame_total), _fixture.frame_total)
	_lighting = _arg_str(args, "--lighting", _fixture.lighting)
	_worst = _arg_int(args, "--worst", 8)
	_report = _arg_str(args, "--report", "")
	if _total <= 0 or not _failures.is_empty():
		_finish()
		return
	Engine.max_fps = 0
	if not _gated:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	match _phase:
		SETUP:
			_setup()
			return false
		RUN:
			return _run(now)
		_:
			_phase = SETUP
			_pass += 1
			if _pass >= _repeats:
				_finish()
				return true
	return false


## Builds the boot scene on the stress scenario, with the scripted input in place of the devices.
func _setup() -> void:
	Main.scenario_override = _fixture.scenario.copy()
	Main.lighting_word = _lighting if _lighting != "" else "off"
	_main = (load("res://game/main.tscn") as PackedScene).instantiate() as Main
	_main.save_on_exit = false
	root.add_child(_main)
	_driver = _main.get_node("SimDriver")
	_driver.set_process(false)
	_vfx = _main.get_node("World/Vfx")
	_voices = _main.get_node("World/Voices")
	_input = ScriptedInput.new()
	_input.fixture = _fixture
	_driver.input_layer = _input
	if _pass == 0:
		_facts.load_errors = _driver.sim.load_errors
		_vfx_capacity = _vfx.tuning.vfx_capacity
		_voice_cap = _vfx.tuning.voice_cap
	_probes.attach(root)
	for s: PackedInt32Array in [_sim, _tick, _wall, _proc, _draw]:
		s.resize(_total)
	_frame = 0
	_phase = RUN


## One frame of the run: closes the previous frame's figures, then plays this frame's tick.
func _run(now: int) -> bool:
	if _frame > 0:
		_wall[_frame - 1] = now - _entered
		if _probes.take():
			_proc[_frame - 1] = _probes.process_us
			_draw[_frame - 1] = _probes.draw_us
		else:
			_unread += 1
	if _frame >= _total:
		_end_pass()
		return false
	_entered = now
	_input.index = _frame
	_driver.step_once()
	var done: int = Time.get_ticks_usec()
	_tick[_frame] = done - now
	_sim[_frame] = _driver.last_step_us
	if _pass == 0:
		_note(_frame)
	_frame += 1
	return false


## Counts what the presentation did on this tick (first pass only; the reads are outside every
## figure's tick but inside the frame's wall time, which the later passes' least value drops).
func _note(_i: int) -> void:
	var fired: int = _driver.sim.procs.fired()
	var f: Facts = _facts
	f.procs_total += fired
	f.most_procs = maxi(f.most_procs, fired)
	f.frames += 1
	var effects: int = _vfx.effects.size()
	f.max_effects = maxi(f.max_effects, effects)
	f.draw_calls = maxi(
		f.draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	)
	if fired >= _budget.min_peak_procs and fired > 0:
		var kind: Peaks = f.bursts if fired <= _budget.burst_procs_max else f.crowd
		kind.voices.append(_voices.playing_count())
		kind.effects.append(effects)
		kind.procs.append(fired)


func _end_pass() -> void:
	var present := PackedInt32Array()
	var capture := PackedInt32Array()
	var gap := PackedInt32Array()
	for i: int in range(_total):
		capture.append(maxi(0, _tick[i] - _sim[i]))
		present.append(capture[i] + _proc[i] + _draw[i])
		gap.append(maxi(0, _wall[i] - _sim[i]))
	PerfStats.fold_min(_best_sim, _sim)
	PerfStats.fold_min(_best_tick, _tick)
	PerfStats.fold_min(_best_wall, _wall)
	PerfStats.fold_min(_best_present, present)
	_runs_present.append(present)
	PerfStats.fold_min(_best_capture, capture)
	PerfStats.fold_min(_best_proc, _proc)
	PerfStats.fold_min(_best_draw, _draw)
	PerfStats.fold_min(_best_gap, gap)
	if _pass == 0:
		_facts.refused = _vfx.refused
		_facts.displaced = _vfx.displaced
		_facts.dropped = _voices.dropped
		_facts.stolen = _voices.stolen
		_end_hash = _driver.sim.state_hash()
	elif _driver.sim.state_hash() != _end_hash:
		_fail(
			(
				"frame run desync: pass %d ended on hash %d, pass 1 on %d"
				% [_pass + 1, _driver.sim.state_hash(), _end_hash]
			)
		)
	_main.queue_free()
	_phase = TEARDOWN


func _finish() -> void:
	_probes.detach()
	if _total > 0 and not _best_wall.is_empty():
		_report_run()
	if _report != "":
		_write_report(_report)
	if _failures.is_empty():
		print("FRAME GATE PASSED" if _gated else "FRAME RUN RECORDED (not gated: no GPU)")
		quit(0)
	else:
		print("FRAME GATE FAILED: %d over budget" % _failures.size())
		for f: String in _failures:
			print("  " + f)
		quit(1)


func _report_run() -> void:
	var from: int = _budget.warmup_ticks
	var mode: String = "headless, dummy renderer: our script cost, gated"
	if not _gated:
		mode = (
			"%s, %s: software rendering, recorded and not gated (no GPU: PROGRESS.md, Blocked 2)"
			% [DisplayServer.get_name(), RenderingServer.get_video_adapter_name()]
		)
	_say(
		(
			(
				"frame run: %d frames of the stress room through game/main.tscn, lighting %s, "
				+ "best of %d passes, first %d not counted; %s"
			)
			% [_total, _lighting if _lighting != "" else "off", _repeats, from, mode]
		),
		false
	)
	for e: String in _facts.load_errors:
		_fail("frame run load error: %s" % e)
	if _unread > 0:
		_fail(
			(
				"frame run: the probes were not read on %d frames, the figures are not the run's"
				% _unread
			)
		)
	var present: PackedInt32Array = PerfStats.sorted_from(_best_present, from)
	var series: Dictionary[String, PackedInt32Array] = {
		"simulation step": _best_sim,
		"tick (input, step, views capture it)": _best_tick,
		"views capture a tick": _best_capture,
		"views _process (probed)": _best_proc,
		"views _draw (probed)": _best_draw,
		"presentation script (capture, _process, _draw)": _best_present,
		"frame less step (engine included, not gated)": _best_gap,
		"frame, wall time": _best_wall,
	}
	for label: String in series:
		var s: PackedInt32Array = PerfStats.sorted_from(series[label], from)
		var gate: bool = label.begins_with("presentation")
		_say(
			(
				"  %-48s p50 %6s ms, p99 %6s ms, max %6s ms"
				% [
					label,
					PerfStats.ms(PerfStats.percentile(s, 500)),
					PerfStats.ms(PerfStats.percentile(s, P99)),
					PerfStats.ms(s[s.size() - 1] if not s.is_empty() else 0)
				]
			),
			gate
		)
	var p99: int = PerfStats.percentile(present, P99)
	var top: int = present[present.size() - 1] if not present.is_empty() else 0
	var allowed: int = _budget.presentation_us()
	_say(
		(
			(
				"presentation script: p99 %s ms (gate %s = sprites %s + VFX %s + audio and UI %s), "
				+ "max %s ms (gate %s)"
			)
			% [
				PerfStats.ms(p99),
				PerfStats.ms(allowed),
				PerfStats.ms(_budget.sprite_us),
				PerfStats.ms(_budget.vfx_us),
				PerfStats.ms(_budget.audio_ui_us),
				PerfStats.ms(top),
				PerfStats.ms(_budget.sim_max_us),
			]
		),
		true
	)
	var singles: PackedStringArray = []
	for us: int in PerfStats.p99_each(_runs_present, from):
		singles.append(PerfStats.ms(us))
	_say(
		(
			"  single passes (what a player gets; not gated): presentation p99 %s ms (gate %s)"
			% [" / ".join(singles), PerfStats.ms(allowed)]
		),
		true
	)
	if _gated:
		if p99 > allowed:
			_fail("presentation p99 %s ms over %s ms" % [PerfStats.ms(p99), PerfStats.ms(allowed)])
		if top > _budget.sim_max_us:
			_fail(
				(
					"presentation max %s ms over %s ms"
					% [PerfStats.ms(top), PerfStats.ms(_budget.sim_max_us)]
				)
			)
	_report_facts()
	if _facts.frames < _budget.min_frames and _total >= _budget.min_frames:
		_fail("frame run drew %d frames, at least %d wanted" % [_facts.frames, _budget.min_frames])
	if _total >= _budget.min_frames and _facts.most_procs < _budget.min_peak_procs:
		_fail(
			(
				"frame run: no tick fired %d procs (most %d): the burst is not in the run"
				% [_budget.min_peak_procs, _facts.most_procs]
			)
		)
	if not _quiet:
		_say("  slowest frames by presentation script (frame, ms):", false)
		for i: int in PerfStats.worst(_best_present, from, _worst):
			_say(
				(
					"    %5d  presentation %6s ms, step %6s ms, wall %6s ms"
					% [
						i,
						PerfStats.ms(_best_present[i]),
						PerfStats.ms(_best_sim[i]),
						PerfStats.ms(_best_wall[i])
					]
				),
				false
			)


## The VFX budget's and the voices' counts, with the peaks.
func _report_facts() -> void:
	var f: Facts = _facts
	_say(
		(
			(
				"procs fired %d over the run, most %d on one tick; ticks with %d procs or more: "
				+ "%d bursts (up to %d), %d crowd hits"
			)
			% [
				f.procs_total,
				f.most_procs,
				_budget.min_peak_procs,
				f.bursts.procs.size(),
				_budget.burst_procs_max,
				f.crowd.procs.size()
			]
		),
		true
	)
	_say(
		(
			"VFX budget over the run: refused %d, displaced %d, most effects alive %d of %d"
			% [f.refused, f.displaced, f.max_effects, _vfx_capacity]
		),
		true
	)
	for kind: String in ["bursts", "crowd"]:
		var p: Peaks = f.bursts if kind == "bursts" else f.crowd
		_say(
			(
				"voices at the %s: most %d of %d in use, median %d; effects alive: most %d, median %d"
				% [
					kind,
					_most(p.voices),
					_voice_cap,
					_median(p.voices),
					_most(p.effects),
					_median(p.effects)
				]
			),
			true
		)
	_say("voices over the run: dropped %d, stolen %d" % [f.dropped, f.stolen], true)
	if _gated:
		_say(
			(
				"(headless the dummy audio driver never finishes a stream, so voices stay occupied: "
				+ "read the voice counts from a windowed run)"
			),
			false
		)
	else:
		_say("draw calls in the busiest frame: %d" % f.draw_calls, false)


func _most(values: PackedInt32Array) -> int:
	var top: int = 0
	for v: int in values:
		top = maxi(top, v)
	return top


func _median(values: PackedInt32Array) -> int:
	var sorted: PackedInt32Array = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] if not sorted.is_empty() else 0


func _fail(message: String) -> void:
	_failures.append(message)
	_say("FAIL " + message, true)


## Prints [param line] unless the run is quiet (a gate line, [param gate], prints always).
func _say(line: String, gate: bool) -> void:
	_lines.append(line)
	if gate or not _quiet:
		print(line)


func _write_report(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s" % path)
		return
	f.store_string("\n".join(_lines) + "\n")
	f.close()


func _arg_int(args: PackedStringArray, key: String, fallback: int) -> int:
	var s: String = _arg_str(args, key, "")
	return s.to_int() if s.is_valid_int() else fallback


func _arg_str(args: PackedStringArray, key: String, fallback: String) -> String:
	var i: int = args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback
