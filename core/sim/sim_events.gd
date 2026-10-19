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
## The player went through a door into another room this tick (docs/adr/0014); at the arrival.
const ROOM: String = "room"
const IGNITE: String = "ignite"
const HAZARD: String = "hazard"
const DROP_THROUGH: String = "drop_through"
## Combat (Phase 1 task 6; docs/adr/0013). A hit's value carries its kind and direction
## ([method HitKind.encode]); other values are noted.
## An enemy attack's telegraph starts (value 1 if it is red, unparryable).
const TELEGRAPH: String = "telegraph"
## The swing lands in exactly [member CombatParams.telegraph_cue_frames] ticks: its sound's cue
## (value 1 if it is red). From this tick the attack is committed.
const TELEGRAPH_CUE: String = "telegraph_cue"
## A player strike, pogo or spell lands on an enemy; a kill carries the killing hit's value.
const HIT: String = "hit"
const KILL: String = "kill"
## An enemy's poise breaks (the value is the enemy's index in [member Combat.enemies]).
const STAGGER: String = "stagger"
const PARRY: String = "parry"
## An enemy hits the player ([constant HitKind.PLAYER], along the knockback).
const PLAYER_HIT: String = "player_hit"
## A kill's ember reaches the player and its Flame is granted.
const EMBER_HOME: String = "ember_home"
## The player's hearts ran out (Phase 1: back to the room's spawn). x and y are where the player
## died (bottom-centre, sub-pixels, before the send-back); by the end of the tick the player stands
## at the room's spawn. Sent for any death, by an enemy's hit (after its [constant PLAYER_HIT], in
## combat's resolve) or by a hazard (after its [constant HAZARD], in the player's step); the value
## is 0.
const DEATH: String = "death"
## A spell or Mend starts (the value is [PlayerSpells] KINDLE, RADIANCE or MEND).
const CAST: String = "cast"
## A spell press with too little Flame.
const FIZZLE: String = "fizzle"
## Radiance bursts.
const RADIANCE: String = "radiance"
## Mend heals (the value is the hearts after it).
const HEAL: String = "heal"
## The attack has been held long enough for the Charged strike, and the hold let go to ask for it.
const CHARGE_READY: String = "charge_ready"
const CHARGE_RELEASE: String = "charge_release"

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


## True if [param kind] was added at index [param from] or later: an event since that point of
## the tick ([method count] taken then).
func has_since(kind: String, from: int) -> bool:
	return kinds.find(kind, from) >= 0


func count() -> int:
	return kinds.size()
