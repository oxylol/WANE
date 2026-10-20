class_name EnemyBatch
extends RefCounted
## Steps a room's enemies with one call to the native sweep instead of three per enemy
## (docs/adr/0020 Decision 15, stage 1; BUILD.md section 13, "Frame budget": input + simulation step
## 3.0 ms). An enemy on the plain tick of a walker or a stander ([method TrainingDummy.fast_step])
## does its bookkeeping and queues its movement here as one record of
## [constant CollisionWorld.PATROL_IN] integers; [method run] sends the queue to
## [method CollisionWorld.patrol_many] when the enemies are done and each queued enemy takes its
## answer ([method TrainingDummy.land]). Any other tick of any enemy is [method Enemy.step], the
## reference, untouched.
##
## What makes the two the same. Enemies move their own bodies and nothing else; the one thing a
## deferred move could see differently is a [SolidBox] another enemy moves (a dummy with
## `solid=1`), so an enemy that owns a solid box flushes the queue before its step: every move
## that came before it in the room's order has happened, as in the sequential loop. The enemies'
## events come from their full steps, in the room's order, and the queued ticks raise none. The
## test is [code]tests/unit/core/enemies/test_enemy_batch.gd[/code]: whole simulations, state
## hashed every tick, with and without it. Used only with the native sweep: without it the batch
## is the reference loop ([code]WANE_NATIVE=off[/code] runs the code it always did).
##
## Nothing here is state: never hashed, rebuilt every tick.

## Off in tests that play the reference loop beside it.
static var enabled: bool = true

var ops: PackedInt64Array = PackedInt64Array()
var queued: Array[TrainingDummy] = []
var count: int = 0
## Movements sent to the sweep in all and calls made (for the tests: that the batch ran).
var sent: int = 0
var calls: int = 0
var _world: CollisionWorld = null


## One tick of every enemy in [param enemies], in order.
func run(enemies: Array[Enemy], player: Player, world: CollisionWorld) -> void:
	if not enabled or world.native == null:
		for e: Enemy in enemies:
			e.step(player)
		return
	_world = world
	count = 0
	if queued.size() < enemies.size():
		queued.resize(enemies.size())
		ops.resize(CollisionWorld.PATROL_IN * enemies.size())
	for e: Enemy in enemies:
		if not e.fast_step(player, self):
			e.step(player)
	flush()


## Sends the queue to the sweep and lands every queued enemy.
func flush() -> void:
	var n: int = count
	if n == 0:
		return
	count = 0
	sent += n
	calls += 1
	var out: PackedInt64Array = _world.patrol_many(ops, n)
	for k: int in range(n):
		queued[k].land(out, CollisionWorld.PATROL_OUT * k)
