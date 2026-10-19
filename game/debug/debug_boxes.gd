class_name DebugBoxes
extends RefCounted
## The rectangles the F3 overlay draws, read from the simulation in world units: the player's
## collider, hurtbox, strike and pogo boxes, the ember, the room's solid boxes, the hazard part
## of every spike tile in view, and a mark where a pogo bounced this tick (the strike hands control
## back on that tick, so its box is already gone: task 5 review, M10). BUILD.md section 5: "shows
## hitboxes"; CLAUDE.md rule 8. Boxes are the latest tick's, exactly as the simulation resolves
## them, never interpolated.

enum { COLLIDER, HURTBOX, STRIKE, POGO, EMBER, SOLID, HAZARD, CONTACT }

## Half the size of the marker drawn at the ember, and at a bounce.
const EMBER_HALF_U: float = 4.0
const CONTACT_HALF_U: float = 6.0


class Box:
	var kind: int = COLLIDER
	var rect: Rect2 = Rect2()
	var label: String = ""


## Every box to draw for [param sim], hazards only inside [param view].
static func collect(sim: Simulation, view: Rect2) -> Array[Box]:
	var out: Array[Box] = []
	for s: SolidBox in sim.world.solids:
		if not s.enabled:
			continue
		var r := Rect2(
			float(s.left) / Fx.SUB,
			float(s.top) / Fx.SUB,
			float(s.right - s.left) / Fx.SUB,
			float(s.bottom - s.top) / Fx.SUB
		)
		var label: String = s.tag
		if not s.clingable:
			label = (label + " no-cling").strip_edges()
		out.append(_box(SOLID, r, label))
	_add_hazards(sim.world, view, out)
	var pl: Player = sim.player
	if pl == null:
		return out
	var b: Body = pl.body
	out.append(_box(COLLIDER, units(Rect2i(b.left(), b.top(), b.right() - b.left(), b.height))))
	out.append(_box(HURTBOX, units(pl.hurtbox()), "invulnerable" if pl.is_invulnerable() else ""))
	var strike: Rect2i = pl.strike_box()
	var pogo: Rect2i = pl.pogo_box()
	if strike.size != Vector2i.ZERO:
		var id: String = pl.current_attack().id
		out.append(_box(STRIKE, units(strike), id + (" + pogo" if pogo == strike else "")))
	if pogo.size != Vector2i.ZERO:
		out.append(_box(POGO, units(pogo), "pogo"))
	if pl.toss.active:
		var at := Vector2(float(pl.toss.x) / Fx.SUB, float(pl.toss.y) / Fx.SUB)
		var half := Vector2(EMBER_HALF_U, EMBER_HALF_U)
		out.append(_box(EMBER, Rect2(at - half, half * 2.0), "ember"))
	var events: SimEvents = sim.events
	for i: int in range(events.count()):
		if events.kinds[i] == SimEvents.POGO:
			var at := Vector2(float(events.xs[i]), float(events.ys[i])) / Fx.SUB
			var half := Vector2(CONTACT_HALF_U, CONTACT_HALF_U)
			out.append(_box(CONTACT, Rect2(at - half, half * 2.0), "bounce"))
	return out


## A sub-pixel rectangle in units.
static func units(r: Rect2i) -> Rect2:
	return Rect2(Vector2(r.position) / Fx.SUB, Vector2(r.size) / Fx.SUB)


static func _box(kind: int, rect: Rect2, label: String = "") -> Box:
	var box := Box.new()
	box.kind = kind
	box.rect = rect
	box.label = label
	return box


## The part of each spike tile in [param view] that hurts: below the world's spike inset.
static func _add_hazards(world: CollisionWorld, view: Rect2, out: Array[Box]) -> void:
	var t: int = TileGrid.TILE
	var grid: TileGrid = world.grid
	var inset: float = float(world.spike_inset_sp) / Fx.SUB
	var i0: int = maxi(0, floori(view.position.x / t))
	var i1: int = mini(grid.width - 1, floori(view.end.x / t))
	var j0: int = maxi(0, floori(view.position.y / t))
	var j1: int = mini(grid.height - 1, floori(view.end.y / t))
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			if grid.get_tile(i, j) == TileGrid.SPIKES:
				out.append(_box(HAZARD, Rect2(i * t, j * t + inset, t, t - inset)))
