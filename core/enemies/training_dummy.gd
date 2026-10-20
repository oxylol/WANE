class_name TrainingDummy
extends Enemy
## The grey-box training dummy (Phase 1 task 6: "against a grey-box training dummy with poise").
## It stands, faces the player, takes hits, staggers when its poise breaks and comes back
## [member respawn_frames] after it dies ([DummyDef]), so every hit, finisher, kill and pogo can
## be practised.
## With attacks on it swings at a steady rhythm so the parry can be practised too: a white
## (parryable) swing, or a red (unparryable) one.
##
## Room entity: `entity dummy <x> <y> [attack=1] [period=<ticks between swings>] [red=1]
## [light=1] [hp=<n>] [poise=<n>] [facing=-1|1] [solid=1] [trigger=<units>]`. hp and poise override
## the dummy's content for one marker (a one-hit kill, a poise break on the first hit); facing sets
## the way it faces before it first turns to the player. `solid=1` gives it a body the player cannot
## pass while it lives (a [SolidBox] as wide and tall as the dummy): a dash or a run stops at it, so
## only a kill clears the way (zone 1 room 1, BUILD.md s5 tech 1). The body is out of the way while
## the dummy is dead, and stays out while the player stands where it would come back. trigger makes
## it an ambusher: its rhythm runs only while the player is within that many units of it,
## horizontally, and starts over from zero whenever she is not, so its first swing lands a fixed
## time after she comes into range, whatever she did before (a boss that opens when you reach it).
## `patrol=1` makes it walk (docs/adr/0020): at [member DummyDef.patrol_speed_ups] in the way it
## faces, turning at a wall and at a ledge ([member DummyDef.patrol_drop_u]), or walking off the
## ledge and falling with `fall=1`; it stands for a swing (facing the player as it starts) and
## walks on after. A standing dummy is as it was.

## Ticks between the end of one swing and the start of the next ([member DummyDef.swing_period],
## or the marker's), and ticks a kill keeps it down ([member DummyDef.respawn_frames]).
var period: int = 0
var attacks_on: bool = false
var red: bool = false
var respawn_frames: int = 0
## Horizontal range of the ambush, in sub-pixels; 0 = the rhythm always runs.
var trigger_range: int = 0
## The body of a solid dummy (null for one the player walks through).
var blocker: SolidBox
## The way a walking dummy goes (-1 or 1; 0 = it stands), its speed in sub-pixels a tick, and
## whether it walks off ledges instead of turning back.
var patrol_dir: int = 0
var patrol_step: int = 0
var patrol_falls: bool = false
## How far below its feet the floor ahead must be missing for it to turn at a ledge, in sub-pixels.
var patrol_drop: int = 0
var _idle: int = 0


## Builds a dummy from a room entity marker and its content.
static func from_entity(
	e: RoomData.RoomEntity,
	p_def: DummyDef,
	p_params: CombatParams,
	p_world: CollisionWorld,
	p_events: SimEvents
) -> TrainingDummy:
	var d := TrainingDummy.new(p_def, p_params, p_world, p_events, Fx.units(e.x_u), Fx.units(e.y_u))
	d.attacks_on = e.prop_int("attack") != 0
	d.respawn_frames = p_def.respawn_frames
	d.period = maxi(1, e.prop_int("period", p_def.swing_period))
	d.red = e.prop_int("red") != 0
	d.trigger_range = Fx.units(maxi(0, e.prop_int("trigger")))
	d.light = e.prop_int("light", 1 if p_def.light else 0) != 0
	d.max_hp = maxi(1, e.prop_int("hp", p_def.hp))
	d.max_poise = maxi(1, e.prop_int("poise", p_def.poise))
	d.hp = d.max_hp
	d.poise = d.max_poise
	d.facing = -1 if e.prop_int("facing", -1) < 0 else 1
	if e.prop_int("patrol") != 0:
		d.patrol_dir = d.facing
		d.patrol_step = Fx.speed(p_def.patrol_speed_ups)
		d.patrol_falls = e.prop_int("fall") != 0
		d.patrol_drop = Fx.units(p_def.patrol_drop_u)
	if e.prop_int("solid") != 0:
		d.blocker = SolidBox.make(0, 0, 0, 0)
		d.blocker.clingable = false
		d.blocker.tag = "dummy"
		d.sync_blocker(null)
		p_world.solids.append(d.blocker)
	return d


## One tick. Its own body is out of the world while it moves, so a knock does not push it against
## itself.
func step(player: Player) -> void:
	if blocker != null:
		blocker.enabled = false
	super.step(player)
	if blocker != null:
		sync_blocker(player.body if player != null else null)


## The body follows the dummy, and is solid while it lives and the player is not inside it.
func sync_blocker(player_body: Body) -> void:
	blocker.left = body.left()
	blocker.right = body.right()
	blocker.top = body.top()
	blocker.bottom = body.y
	blocker.enabled = is_alive()
	if blocker.enabled and player_body != null:
		var pb: Body = player_body
		blocker.enabled = not blocker.overlaps(pb.left(), pb.right(), pb.top(), pb.y)


func _think(player: Player) -> void:
	if player != null and patrol_dir == 0:
		facing = 1 if player.body.x > body.x else -1
	if attacks_on and not def.attacks.is_empty() and _swing_due(player):
		if player != null:
			facing = 1 if player.body.x > body.x else -1
		var a: EnemyAttack = def.find_attack("red" if red else "swing")
		if a != null:
			start_attack(a)
			return
	if patrol_dir != 0:
		_patrol()


## Counts the rhythm by a tick; true on the tick a swing is due.
func _swing_due(player: Player) -> bool:
	if trigger_range > 0 and (player == null or absi(player.body.x - body.x) > trigger_range):
		_idle = 0
		return false
	_idle += 1
	if _idle >= period:
		_idle = 0
		return true
	return false


## One step of the walk: turn at a wall or at a ledge, then walk (a body in the air keeps its
## way and falls; [method Enemy._move] lets it). On the ground the whole step is
## [method CollisionWorld.patrol_walk], one call to the native sweep.
func _patrol() -> void:
	if body.on_ground:
		var flags: int = world.patrol_walk(body, patrol_dir, patrol_step, patrol_drop, patrol_falls)
		if (flags & CollisionWorld.PATROL_LEDGE) != 0:
			patrol_dir = -patrol_dir
		facing = patrol_dir
		if (flags & CollisionWorld.PATROL_WALL) != 0:
			patrol_dir = -patrol_dir
		settled = true
		return
	facing = patrol_dir
	body.clear_contacts()
	world.move_x(body, patrol_dir * patrol_step)
	var wall: int = body.hit_wall
	body.clear_contacts()
	if wall != 0:
		patrol_dir = -patrol_dir


## Comes back whole at its marker, at rest (task 6 review, H5: a dummy killed in the air came back
## where it hung, with the launch still on it).
func _while_dead() -> void:
	if state_frame >= respawn_frames:
		hp = max_hp
		poise = max_poise
		_idle = 0
		body.x = home_x
		body.y = home_y
		body.vy = 0
		knock_vx = 0
		trail_burned.clear()
		world.refresh_ground(body)
		_set_state(IDLE)


func hash_into(h: StateHasher) -> void:
	super.hash_into(h)
	h.add_int(_idle)
	if patrol_dir != 0:
		h.add_int(patrol_dir)
