class_name SimEvents
extends RefCounted
## What happened this tick, for presentation (squash on landing, dust, sparks, camera shake) and
## for tests. Cleared at the start of every tick. Events never feed back into the simulation, so
## they are not part of the state hash.

const JUMP: String = "jump"
const AIR_JUMP: String = "air_jump"
const WALL_JUMP: String = "wall_jump"
const WALL_KICK: String = "wall_kick"
const LAND: String = "land"
const DASH: String = "dash"
const WALL_CLING: String = "wall_cling"
const LEDGE_GRAB: String = "ledge_grab"
const POGO: String = "pogo"
const ATTACK: String = "attack"
const TOSS: String = "toss"
const TELEPORT: String = "teleport"
const IGNITE: String = "ignite"
const HAZARD: String = "hazard"
const DROP_THROUGH: String = "drop_through"
## Combat (Phase 1 task 6). The value is the enemy's index in [member Simulation.enemies] unless
## noted.
## An enemy attack's telegraph starts (value 1 if it is red, unparryable).
const TELEGRAPH: String = "telegraph"
## A player strike, pogo or spell lands on an enemy.
const HIT: String = "hit"
const KILL: String = "kill"
const STAGGER: String = "stagger"
const PARRY: String = "parry"
## An enemy hits the player (the value is the enemy's index).
const PLAYER_HIT: String = "player_hit"
## A kill's ember reaches the player and its Flame is granted.
const EMBER_HOME: String = "ember_home"

var kinds: Array[String] = []
var xs: Array[int] = []
var ys: Array[int] = []
## Event-specific integer (attack index, vertical speed at landing, direction...).
var values: Array[int] = []


func clear() -> void:
	kinds.clear()
	xs.clear()
	ys.clear()
	values.clear()


func add(kind: String, x: int, y: int, value: int = 0) -> void:
	kinds.append(kind)
	xs.append(x)
	ys.append(y)
	values.append(value)


func has(kind: String) -> bool:
	return kinds.has(kind)


func count() -> int:
	return kinds.size()
