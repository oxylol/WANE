class_name PerfBudget
extends Resource
## The performance gate's numbers (BUILD.md section 13, "Testing and CI" and "Frame budget";
## docs/adr/0020; CLAUDE.md rule 6). All times are microseconds. The CPU part of the frame budget
## is what CI can gate (`tools/bench/stress_bench.gd`, `ci/perf.sh`); the GPU stages wait for a
## runner with a GPU (PROGRESS.md, Blocked 2) and are listed so the report names them.

const PATH: String = "res://content/perf/budget.tres"
## The frame the budget divides (60 Hz), in microseconds.
const FRAME_US: int = 16600

## Input plus [method Simulation.step] in the stress room: the 99th percentile of a tick and the
## worst tick ("Input + simulation step 3.0 ms"; the worst tick is the checklist's "no frame-time
## spike above 20 ms").
@export var sim_p99_us: int = 3000
@export var sim_max_us: int = 20000
## The worst tick of the zone 1 loop, played [member zone_passes] times through.
@export var zone_max_us: int = 20000
@export var zone_passes: int = 6
## The first crossing of a door into a room of zone 1 at Pitch (the room view's tiles and the
## lighting's occluders, drawn on the tick of the room event): no more than an eighth of a frame, so
## a door frame is no frame-time spike (`tools/bench/door_bench.gd`).
@export var door_max_us: int = 2000
## Whole runs of the stress scenario; each tick's time is the least of them (the work of a tick is
## fixed, so the rest is the machine's noise).
@export var repeats: int = 3
## Ticks played before the timings count.
@export var warmup_ticks: int = 120
## What the stress run must have done, or it measured nothing: Votive procs fired, hits landed,
## enemies killed, enemies walking.
@export var min_procs: int = 8000
@export var min_hits: int = 9000
@export var min_kills: int = 80
@export var min_walkers: int = 100
## What the frame bench's run must have shown, or it measured nothing: the most Votive procs
## fired on one tick (the stress room's bursts are 39: "40 procs"), and how many frames the
## presentation drew (`tools/bench/frame_bench.gd`).
@export var min_peak_procs: int = 39
## A tick that fires more procs than this is a crowd hit (an area hit on a pack), not one Taper
## hit's burst; the report counts them apart.
@export var burst_procs_max: int = 60
@export var min_frames: int = 3000
## The rest of section 13's frame budget, for the report (the GPU stages are not measured here).
@export var sprite_us: int = 2000
@export var lighting_us: int = 3000
@export var vfx_us: int = 2000
@export var post_us: int = 1000
@export var audio_ui_us: int = 1000
@export var headroom_us: int = 4600
## "60 fps with 99th-percentile frame time <= 16.0 ms on reference PC settings, <= 15.0 ms on the
## Deck profile": whole frames, on a GPU runner.
@export var reference_p99_us: int = 16000
@export var deck_p99_us: int = 15000


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	for v: int in [sim_p99_us, sim_max_us, zone_max_us, reference_p99_us, deck_p99_us]:
		if v <= 0:
			e.append("every time in the perf budget must be positive")
			break
	if door_max_us <= 0 or door_max_us > sim_max_us:
		e.append("the door crossing's budget must be positive and no more than the spike limit")
	if sim_p99_us > sim_max_us:
		e.append("the 99th percentile cannot be allowed to exceed the worst tick")
	if repeats < 1 or zone_passes < 1 or warmup_ticks < 0:
		e.append("repeats and zone_passes must be at least 1, warmup_ticks not negative")
	if min_procs < 0 or min_hits < 0 or min_kills < 0 or min_walkers < 0:
		e.append("the stress run's minimums must not be negative")
	if min_peak_procs < 0 or min_frames < 1 or burst_procs_max < min_peak_procs:
		e.append("the frame bench's minimums must not be negative, and it must draw frames")
	if frame_total_us() != FRAME_US:
		e.append("the frame budget stages add up to %d us, not %d" % [frame_total_us(), FRAME_US])
	if deck_p99_us > reference_p99_us:
		e.append("the Deck profile's frame cannot be longer than the reference PC's")
	return e


## What the presentation's script time may cost a frame at the 99th percentile: the stages of
## section 13's frame budget that are our GDScript on the CPU, "Sprite and animation submit 2.0",
## "VFX 2.0" and "Audio and UI 1.0" (5.0 ms). The lighting pass and post are the GPU's and are
## not in it.
func presentation_us() -> int:
	return sprite_us + vfx_us + audio_ui_us


## The stages of the frame budget added up (section 13: 16.6 ms).
func frame_total_us() -> int:
	return sim_p99_us + sprite_us + lighting_us + vfx_us + post_us + audio_ui_us + headroom_us
