class_name CameraRun
extends RefCounted
## One fixture played through the simulation and the camera, tick by tick, for the camera suites
## (docs/adr/0011).

## How many recordings [method play_fixture] keeps, oldest dropped first.
const KEPT_RECORDINGS: int = 8

## The recordings of the last fixtures played by [method play_fixture], by what keys them: the
## fixture's text and the camera tuning's fall look-ahead, the one tuning value the subjects depend
## on. The screen-shape loops of the camera suites play each fixture several times in a row.
static var _recordings: Dictionary[String, Recording] = {}

var subjects: Array[CameraSubject] = []
var centers: PackedVector2Array = PackedVector2Array()
var previous: PackedVector2Array = PackedVector2Array()
var gliding: Array[bool] = []
var events: Array[PackedStringArray] = []
## The look-down and the fall's look-ahead on each tick.
var looks: PackedFloat32Array = PackedFloat32Array()
var fall_looks: PackedFloat32Array = PackedFloat32Array()
## The way the lead points on each tick.
var leads: PackedInt32Array = PackedInt32Array()
## The last support's height (feet, y down) on each tick.
var supports: PackedFloat32Array = PackedFloat32Array()
var rig: CameraRig
var room: Rect2
var errors: PackedStringArray = PackedStringArray()


func velocity(f: int) -> Vector2:
	return centers[f] - previous[f]


func view(f: int) -> Rect2:
	var half: Vector2 = rig.half_view()
	return Rect2(centers[f] - half, half * 2.0)


## How near the player's box comes to the view's edge on tick [param f].
func gap(f: int) -> float:
	var b: Rect2 = subjects[f].box
	var v: Rect2 = view(f)
	return minf(
		minf(b.position.x - v.position.x, v.end.x - b.end.x),
		minf(b.position.y - v.position.y, v.end.y - b.end.y)
	)


## The first tick in [param from]..[param to] whose sim events include [param kind].
func first(kind: String, from: int = 0, to: int = -1) -> int:
	var last: int = events.size() - 1 if to < 0 else to
	for f: int in range(from, last + 1):
		if events[f].has(kind):
			return f
	return -1


## The longest stretch, in units of view travel, over which the view moves against the player's
## vertical motion while the player is in the air (not standing, clinging or bouncing: a wall
## slide lags the climb's view on purpose), outside glides. The way down of a hop toward the last
## support (the ground it lands on no lower than the support) is not counted: there the view
## carries on easing up to that support, as BUILD.md section 5 has it ("pausing while the player
## falls away from it"); a fall away from the support is counted (camera reviews 6, M2; 7, H1).
func longest_run_against() -> float:
	var longest: float = 0.0
	var stretch: float = 0.0
	for f: int in range(1, centers.size()):
		var s: CameraSubject = subjects[f]
		if s.teleported or s.respawned or s.entered or gliding[f] or gliding[f - 1]:
			stretch = 0.0
			continue
		var moved: float = s.box.end.y - subjects[f - 1].box.end.y
		var v: float = velocity(f).y
		var hop_down: bool = (
			moved > 0.0
			and v < 0.0
			and s.box.end.y < supports[f] - 0.5
			and s.box.end.y + s.ground_below <= supports[f] + 0.5
		)
		if not s.supported and moved * v < 0.0 and not hop_down:
			stretch += absf(v)
			longest = maxf(longest, stretch)
		else:
			stretch = 0.0
	return longest


## What a fixture does to the camera, apart from the camera: the player's state on every tick (a
## [CameraSubject]), the room it is in and the simulation's events. The simulation never reads the
## camera, so these are the same whatever the camera and the screen's shape; recording them once is
## what lets a sweep over four screen shapes simulate each fixture once instead of four times (the
## camera rig is a tenth of a tick's cost, the simulation and the subject most of the rest).
## The subjects are shared by every [CameraRun] made from a recording: they are not to be changed.
class Recording:
	var errors: PackedStringArray = PackedStringArray()
	## The subject and the room the camera starts from.
	var start: CameraSubject = null
	var start_room: Rect2 = Rect2()
	## On each tick: the subject, the room the camera is shown (it changes through a door) and
	## the simulation's event kinds.
	var subjects: Array[CameraSubject] = []
	var rooms: Array[Rect2] = []
	var events: Array[PackedStringArray] = []


## Plays the fixture at [param path] through a fresh simulation and [param camera]; [member errors]
## holds any problem loading it.
static func play(path: String, camera: CameraRig) -> CameraRun:
	return play_fixture(Fixture.parse_file(path), camera)


## Plays [param fx] (see [method play]). The simulation half is reused when the same fixture text
## was among the last few played with the same look-ahead.
static func play_fixture(fx: Fixture, camera: CameraRig) -> CameraRun:
	var ahead: int = camera.tuning.fall_lead_frames
	if fx.source == "":
		return replay(record(fx, ahead), camera)
	var key: String = "%d|%s" % [ahead, fx.source]
	if not _recordings.has(key):
		if _recordings.size() >= KEPT_RECORDINGS:
			_recordings.erase(_recordings.keys()[0])
		_recordings[key] = record(fx, ahead)
	return replay(_recordings[key], camera)


## Plays [param fx] through a fresh simulation, keeping what the camera is shown.
static func record(fx: Fixture, ahead_frames: int) -> Recording:
	var rec := Recording.new()
	rec.errors.append_array(fx.errors)
	var sim := Simulation.new(fx.scenario)
	rec.errors.append_array(sim.load_errors)
	var shown_room: Rect2 = _room_of(sim)
	rec.start_room = shown_room
	rec.start = CameraSubject.of(sim, ahead_frames)
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		var s: CameraSubject = CameraSubject.of(sim, ahead_frames)
		if s.entered:
			# Through a door: the view cuts to the new room, inside its bounds (docs/adr/0014).
			shown_room = _room_of(sim)
		rec.subjects.append(s)
		rec.rooms.append(shown_room)
		rec.events.append(PackedStringArray(sim.events.kinds))
	return rec


## Shows [param rec] to [param camera], tick by tick.
static func replay(rec: Recording, camera: CameraRig) -> CameraRun:
	var run := CameraRun.new()
	run.errors.append_array(rec.errors)
	run.rig = camera
	run.room = rec.start_room
	run.subjects = rec.subjects.duplicate()
	run.events = rec.events.duplicate()
	run.rig.reset(rec.start, rec.start_room)
	for f: int in range(rec.subjects.size()):
		run.room = rec.rooms[f]
		run.rig.step(rec.subjects[f], run.room)
		run.centers.append(run.rig.center)
		run.previous.append(run.rig.previous)
		run.looks.append(run.rig._look)
		run.fall_looks.append(run.rig._fall_lead)
		run.leads.append(run.rig._lead_dir)
		run.supports.append(run.rig._support_y)
		run.gliding.append(run.rig.gliding())
	return run


static func _room_of(sim: Simulation) -> Rect2:
	return Rect2(0, 0, sim.world.grid.width * TileGrid.TILE, sim.world.grid.height * TileGrid.TILE)
