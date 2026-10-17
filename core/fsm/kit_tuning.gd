class_name KitTuning
extends Resource
## A Wick's ability numbers that are not movement: hurtbox, hazard recovery and spells (BUILD.md
## section 6). Task 6 adds Flame, Kindling, Kindle, Mend and Radiance here. Units as BUILD.md
## gives them; [method compile] converts to sub-pixels.

## [method fit_offsets] for each reach asked for so far: sorting the 2401 offsets of a 24 u reach
## took 7 ms, every time a simulation was built. The arrays are only ever read.
static var _fit_cache: Dictionary[int, PackedInt32Array] = {}

@export_group("Hurtbox")
## The hurtbox is the collider inset by these amounts (smaller than the sprite; CLAUDE.md rule 8).
@export var hurt_inset_x_u: int = 3
@export var hurt_inset_top_u: int = 8
@export var hurt_inset_bottom_u: int = 2
## Invulnerability after a hazard sends the player back to safe ground (BUILD.md "Player hit:
## 20 f of invulnerability").
@export var hazard_invuln_frames: int = 20
## Safe ground, where a hazard sends the player back to, needs the same flat floor this far beyond
## the collider on each side (not in BUILD.md): a respawn never stands on a ledge's lip.
@export var safe_ground_margin_u: int = 16

@export_group("Ember Toss")
## BUILD.md s6: "Throw the ember as a 600 u/s projectile that stops on walls; press again to
## teleport to it with 6 f of invulnerability", "3 f startup", "12 s cd".
@export var toss_speed_ups: int = 600
@export var toss_startup_frames: int = 3
@export var toss_invuln_frames: int = 6
@export var toss_cooldown_frames: int = 720
## Not in BUILD.md (feel values, flagged for the director): how long the ember flies before it
## stops in the air, and how long it waits for the teleport once stopped.
@export var toss_flight_frames: int = 40
@export var toss_linger_frames: int = 120
## Frames a toss press is remembered while the throw cannot start (the feel rules' 8 f).
@export var toss_buffer_frames: int = 8
## How far from the ember the teleport may move the body to fit it (not in BUILD.md): an ember
## stopped on a wall needs half the body's width (10 u), one on a floor half its height (22 u).
@export var toss_fit_reach_u: int = 24


func compile() -> KitParams:
	var k := KitParams.new()
	k.hurt_inset_x = Fx.units(hurt_inset_x_u)
	k.hurt_inset_top = Fx.units(hurt_inset_top_u)
	k.hurt_inset_bottom = Fx.units(hurt_inset_bottom_u)
	k.hazard_invuln_frames = hazard_invuln_frames
	k.safe_ground_margin = Fx.units(safe_ground_margin_u)
	k.toss_speed = Fx.speed(toss_speed_ups)
	k.toss_startup = toss_startup_frames
	k.toss_invuln = toss_invuln_frames
	k.toss_cooldown = toss_cooldown_frames
	k.toss_flight = toss_flight_frames
	k.toss_linger = toss_linger_frames
	k.toss_buffer = toss_buffer_frames
	k.toss_fit_reach_u = toss_fit_reach_u
	k.toss_fit_offsets = fit_offsets(toss_fit_reach_u)
	return k


## The teleport's candidate offsets from the ember, in sub-pixels as (x, y) pairs, nearest first:
## the straight-line offsets (a wall, a floor or a ceiling beside the ember) up to [param reach_u]
## units, then every other offset in the square of that reach. Ties break in a fixed order (up
## before down, left before right), so the search is deterministic.
static func fit_offsets(reach_u: int) -> PackedInt32Array:
	if _fit_cache.has(reach_u):
		return _fit_cache[reach_u]
	var axis: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for oy: int in range(-reach_u, reach_u + 1):
		for ox: int in range(-reach_u, reach_u + 1):
			if ox == 0 or oy == 0:
				axis.append(Vector2i(ox, oy))
			else:
				rest.append(Vector2i(ox, oy))
	axis.sort_custom(_nearer)
	rest.sort_custom(_nearer)
	var out := PackedInt32Array()
	for list: Array[Vector2i] in [axis, rest]:
		for v: Vector2i in list:
			out.append(Fx.units(v.x))
			out.append(Fx.units(v.y))
	_fit_cache[reach_u] = out
	return out


static func _nearer(a: Vector2i, b: Vector2i) -> bool:
	var da: int = a.x * a.x + a.y * a.y
	var db: int = b.x * b.x + b.y * b.y
	if da != db:
		return da < db
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if hurt_inset_x_u < 0 or hurt_inset_top_u < 0 or hurt_inset_bottom_u < 0:
		e.append("hurtbox insets must not be negative")
	if safe_ground_margin_u < 0:
		e.append("safe_ground_margin_u must not be negative")
	if toss_startup_frames < 1 or toss_speed_ups <= 0 or toss_flight_frames < 1:
		e.append("ember toss needs a startup, a speed and a flight time")
	if toss_cooldown_frames < 0 or toss_linger_frames < 0 or toss_invuln_frames < 0:
		e.append("ember toss timers must not be negative")
	if toss_buffer_frames < 1 or toss_buffer_frames > InputRing.HISTORY:
		e.append("toss_buffer_frames must be 1 to the input ring's %d frames" % InputRing.HISTORY)
	if toss_fit_reach_u < 0 or toss_fit_reach_u > 31:
		# The fit search keeps one bit per unit of offset in a 64-bit mask (2 * reach + 1 bits).
		e.append("toss_fit_reach_u must be 0 to 31")
	return e
