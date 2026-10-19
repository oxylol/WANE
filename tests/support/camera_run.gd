class_name CameraRun
extends RefCounted
## One fixture played through the simulation and the camera, tick by tick, for the camera suites
## (docs/adr/0011).

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
## slide lags the climb's view on purpose), outside glides.
func longest_run_against() -> float:
	var longest: float = 0.0
	var stretch: float = 0.0
	for f: int in range(1, centers.size()):
		var s: CameraSubject = subjects[f]
		if s.teleported or s.respawned or gliding[f] or gliding[f - 1]:
			stretch = 0.0
			continue
		var moved: float = s.box.end.y - subjects[f - 1].box.end.y
		var v: float = velocity(f).y
		if not s.supported and moved * v < 0.0:
			stretch += absf(v)
			longest = maxf(longest, stretch)
		else:
			stretch = 0.0
	return longest


## Plays the fixture at [param path] through a fresh simulation and [param camera]; [member errors]
## holds any problem loading it.
static func play(path: String, camera: CameraRig) -> CameraRun:
	return play_fixture(Fixture.parse_file(path), camera)


## Plays [param fx] (see [method play]).
static func play_fixture(fx: Fixture, camera: CameraRig) -> CameraRun:
	var run := CameraRun.new()
	run.errors.append_array(fx.errors)
	var sim := Simulation.new(fx.scenario)
	run.errors.append_array(sim.load_errors)
	run.rig = camera
	run.room = Rect2(
		0, 0, sim.world.grid.width * TileGrid.TILE, sim.world.grid.height * TileGrid.TILE
	)
	run.rig.reset(CameraSubject.of(sim, run.rig.tuning.fall_lead_frames), run.room)
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		var s: CameraSubject = CameraSubject.of(sim, run.rig.tuning.fall_lead_frames)
		run.rig.step(s, run.room)
		run.subjects.append(s)
		run.centers.append(run.rig.center)
		run.previous.append(run.rig.previous)
		run.looks.append(run.rig._look)
		run.fall_looks.append(run.rig._fall_lead)
		run.leads.append(run.rig._lead_dir)
		run.supports.append(run.rig._support_y)
		run.gliding.append(run.rig.gliding())
		run.events.append(PackedStringArray(sim.events.kinds))
	return run
