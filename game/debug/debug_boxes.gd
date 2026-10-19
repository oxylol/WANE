class_name DebugBoxes
extends RefCounted
## The rectangles the F3 overlay draws, read from the simulation in world units: the player's
## collider, hurtbox, strike and pogo boxes, the ember, the room's solid boxes, the hazard part
## of every hazard tile in view, a mark where a pogo bounced this tick (the strike hands control
## back on that tick, so its box is already gone: task 5 review, M10), and the hurtbox that touched
## a hazard this tick (the send-back has already moved the player to safe ground: task 5 review 2,
## M1); and combat's (task 6, docs/adr/0013): each enemy's hurtbox with its state, health and
## poise (a dead enemy has no hurtbox: it is drawn as a dimmer outline, kind ENEMY_DEAD), its live
## attack box (white for a parryable attack, red for an unparryable one), Kindle's cone, Blaze's
## fire trails and the kill embers flying home; and the procs that fired this tick (task 8,
## docs/adr/0015), one mark at each point a Votive fired, labelled with each Votive and the chain
## levels it fired at. BUILD.md section 5: "shows hitboxes"; CLAUDE.md rule 8. Boxes are the
## latest tick's, exactly as the simulation resolves them, never interpolated.

enum {
	COLLIDER,
	HURTBOX,
	STRIKE,
	POGO,
	EMBER,
	SOLID,
	HAZARD,
	CONTACT,
	ENEMY,
	ATTACK_WHITE,
	ATTACK_RED,
	SPELL,
	TRAIL,
	KILL_EMBER,
	ENEMY_DEAD,
	DOOR,
	PROC,
}

## Half the size of the marker drawn at the ember, and at a bounce.
const EMBER_HALF_U: float = 4.0
const CONTACT_HALF_U: float = 6.0
const PROC_HALF_U: float = 5.0
## A proc label's line, in units (the overlay's 18 px text and a little air).
const PROC_LABEL_LINE_U: float = 22.0
## How far above the telegraph cue's highest point an enemy's label is drawn.
const LABEL_CLEAR_U: float = 4.0


class Box:
	var kind: int = COLLIDER
	var rect: Rect2 = Rect2()
	var label: String = ""
	## How far above the box's top the label is drawn, in units (clear of the telegraph's bar);
	## negative draws it below (a proc's mark).
	var label_lift: float = 0.0


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
	# Each door's strip: the player goes through when the whole collider is inside it
	# (docs/adr/0014).
	var w_u: int = sim.room.grid.width * TileGrid.TILE
	var h_u: int = sim.room.grid.height * TileGrid.TILE
	for d: RoomData.Door in sim.room.doors:
		var label: String = "door to " + d.target_room
		out.append(_box(DOOR, Rect2(d.strip_u(w_u, h_u)), label))
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
	var cone: Array[Rect2i] = PlayerSpells.kindle_boxes(pl)
	for i: int in range(cone.size()):
		out.append(_box(SPELL, units(cone[i]), "kindle" if i == 0 else ""))
	_add_combat(sim.combat, out)
	var events: SimEvents = sim.events
	for i: int in range(events.count()):
		if events.kinds[i] == SimEvents.POGO:
			var at := Vector2(float(events.xs[i]), float(events.ys[i])) / Fx.SUB
			var half := Vector2(CONTACT_HALF_U, CONTACT_HALF_U)
			out.append(_box(CONTACT, Rect2(at - half, half * 2.0), "bounce"))
		elif events.kinds[i] == SimEvents.HAZARD:
			out.append(
				_box(CONTACT, units(_hurtbox_at(pl, events.xs[i], events.ys[i])), "hazard hit")
			)
	_add_procs(sim, out)
	return out


## One mark at each point a proc fired this tick, labelled "<votive> L<level>..." for one Votive,
## or "<n> procs, <k> Votives, L<level>..." for several (the overlay's text lists them by Votive):
## the label of a burst stays short enough not to bury the enemies' own.
static func _add_procs(sim: Simulation, out: Array[Box]) -> void:
	var events: SimEvents = sim.events
	var points: Array[Vector2i] = []
	var labels: Dictionary[Vector2i, PackedStringArray] = {}
	for i: int in range(events.count()):
		if events.kinds[i] != SimEvents.PROC:
			continue
		var point := Vector2i(events.xs[i], events.ys[i])
		var slot: int = events.values[i] % ProcBus.LEVEL_SHIFT
		var level: int = events.values[i] / ProcBus.LEVEL_SHIFT
		var votive_id: String = (
			sim.procs.votives[slot].id if slot < sim.procs.votives.size() else "?"
		)
		if not labels.has(point):
			points.append(point)
			labels[point] = PackedStringArray()
		var parts: PackedStringArray = labels[point]
		parts.append("%s L%d" % [votive_id, level])
		labels[point] = parts
	for k: int in range(points.size()):
		var at := Vector2(points[k]) / Fx.SUB
		var half := Vector2(PROC_HALF_U, PROC_HALF_U)
		var box: Box = _box(PROC, Rect2(at - half, half * 2.0), _fold(labels[points[k]]))
		# Below the mark, a line lower for each mark before it this tick: clear of the enemies'
		# labels above them and of a neighbour's proc label.
		box.label_lift = -(half.y * 2.0 + PROC_LABEL_LINE_U * (k + 1))
		out.append(box)


## "a L1, a L2" as "a L1 L2"; "a L1, b L1, a L3" as "3 procs, 2 Votives, L1 L3".
static func _fold(parts: PackedStringArray) -> String:
	var ids: PackedStringArray = []
	var levels: PackedStringArray = []
	for part: String in parts:
		var space: int = part.rfind(" ")
		var votive_id: String = part.substr(0, space)
		var level: String = part.substr(space + 1)
		if not ids.has(votive_id):
			ids.append(votive_id)
		if not levels.has(level):
			levels.append(level)
	levels.sort()
	if ids.size() == 1:
		return "%s %s" % [ids[0], " ".join(levels)]
	return "%d procs, %d Votives, %s" % [parts.size(), ids.size(), " ".join(levels)]


## The player's hurtbox with the body's bottom-centre at ([param x], [param y]) (sub-pixels).
static func _hurtbox_at(pl: Player, x: int, y: int) -> Rect2i:
	var now: Rect2i = pl.hurtbox()
	var b: Body = pl.body
	return Rect2i(now.position + Vector2i(x - b.x, y - b.y), now.size)


## Each enemy, its live attack, the fire trails and the kill embers.
static func _add_combat(combat: Combat, out: Array[Box]) -> void:
	for e: Enemy in combat.enemies:
		var b: Body = e.body
		var r: Rect2i = Rect2i(b.left(), b.top(), b.right() - b.left(), b.height)
		var label: String = (
			"%s %s  hp %d/%d  poise %d" % [e.def.kind, e.state_name(), e.hp, e.max_hp, e.poise]
		)
		if e.state == Enemy.TELEGRAPH and e.attack != null:
			# Counts the hitstop that holds the swing back (the core's own countdown).
			label += "  %s lands in %d" % [e.attack.id, e.ticks_to_landing()]
		var box: Box = _box(ENEMY if e.is_alive() else ENEMY_DEAD, units(r), label)
		if EnemyView.cue_progress(e) >= 0.0:
			box.label_lift = EnemyView.cue_extent_px() + LABEL_CLEAR_U
		out.append(box)
		var hit: Rect2i = e.attack_box()
		if hit.size != Vector2i.ZERO:
			var red: bool = not e.attack.parryable
			out.append(
				_box(ATTACK_RED if red else ATTACK_WHITE, units(hit), "unparryable" if red else "")
			)
	for t: FireTrail in combat.trails:
		out.append(_box(TRAIL, units(t.box)))
	for ember: KillEmber in combat.embers:
		var at := Vector2(ember.at) / Fx.SUB
		var half := Vector2(EMBER_HALF_U, EMBER_HALF_U)
		out.append(_box(KILL_EMBER, Rect2(at - half, half * 2.0)))


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
			var tile: int = grid.get_tile(i, j)
			if tile == TileGrid.SPIKES:
				out.append(_box(HAZARD, Rect2(i * t, j * t + inset, t, t - inset)))
			elif tile == TileGrid.PIT:
				out.append(_box(HAZARD, Rect2(i * t, j * t, t, t)))
