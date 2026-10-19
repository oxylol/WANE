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
## fire trails and the kill embers flying home. BUILD.md section 5: "shows
## hitboxes"; CLAUDE.md rule 8. Boxes are the latest tick's, exactly as the simulation resolves
## them, never interpolated.

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
	BURST,
}

## Half the size of the marker drawn at the ember, and at a bounce.
const EMBER_HALF_U: float = 4.0
const CONTACT_HALF_U: float = 6.0
## How far above the telegraph cue's highest point, or the health bar's (without a cue), an
## enemy's label is drawn.
const LABEL_CLEAR_U: float = 4.0


## What the overlay remembers from the ticks before the one it shows, because the simulation
## has already forgotten it: the swing each telegraphing enemy is about to land (a parry
## staggers the enemy and clears its attack on the tick the swing lands, so the box that was
## parried is gone from the simulation on that very tick: task 5 review 3, M1). Index for index
## with the combat's enemies. Fed by [method note] after every tick.
class Memory:
	extends RefCounted
	var swings: Array[Rect2i] = []

	## Takes what [param sim] holds after a tick.
	func note(sim: Simulation) -> void:
		swings.clear()
		if sim == null or sim.combat == null:
			return
		for e: Enemy in sim.combat.enemies:
			swings.append(DebugBoxes.swing_box(e) if e.state == Enemy.TELEGRAPH else Rect2i())


class Box:
	var kind: int = COLLIDER
	var rect: Rect2 = Rect2()
	var label: String = ""
	## How far above the box's top the label is drawn, in units (clear of the telegraph's bar).
	var label_lift: float = 0.0


## Every box to draw for [param sim], hazards only inside [param view].
## [param memory] gives the parried swing's box on a parry tick (without it the parry is only
## marked where it happened).
static func collect(sim: Simulation, view: Rect2, memory: Memory = null) -> Array[Box]:
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
		# The down-strike's box is its pogo box: it is labelled once, with both names above.
		out.append(_box(POGO, units(pogo), "" if pogo == strike else "pogo"))
	if pl.toss.active:
		var at := Vector2(float(pl.toss.x) / Fx.SUB, float(pl.toss.y) / Fx.SUB)
		var half := Vector2(EMBER_HALF_U, EMBER_HALF_U)
		out.append(_box(EMBER, Rect2(at - half, half * 2.0), "ember"))
	var cone: Array[Rect2i] = PlayerSpells.kindle_boxes(pl)
	for i: int in range(cone.size()):
		out.append(_box(SPELL, units(cone[i]), "kindle" if i == 0 else ""))
	_add_combat(sim.combat, out)
	_add_contacts(sim, pl, memory, out)
	return out


## What happened this tick, marked where it happened: a bounce, a hazard, a parry (with the swing
## that was parried), a hit on the player (its contact point, and the hurtbox that took it when
## it was the lethal one: the send-back has already moved the player), a burn, and a Blaze
## finisher's burst.
static func _add_contacts(
	sim: Simulation, pl: Player, memory: Memory, out: Array[Box]
) -> void:
	var events: SimEvents = sim.events
	for i: int in range(events.count()):
		var at := Vector2(float(events.xs[i]), float(events.ys[i])) / Fx.SUB
		var half := Vector2(CONTACT_HALF_U, CONTACT_HALF_U)
		match events.kinds[i]:
			SimEvents.POGO:
				out.append(_box(CONTACT, Rect2(at - half, half * 2.0), "bounce"))
			SimEvents.HAZARD:
				out.append(
					_box(CONTACT, units(_hurtbox_at(pl, events.xs[i], events.ys[i])), "hazard hit")
				)
			SimEvents.PARRY:
				out.append(_box(CONTACT, Rect2(at - half, half * 2.0), "parry"))
				if memory != null:
					var point := Vector2i(events.xs[i], events.ys[i])
					for swing: Rect2i in memory.swings:
						if swing.size != Vector2i.ZERO and swing.has_point(point):
							out.append(_box(ATTACK_WHITE, units(swing), "parried"))
			SimEvents.PLAYER_HIT:
				out.append(_box(CONTACT, Rect2(at - half, half * 2.0), "hit"))
			SimEvents.DEATH:
				out.append(
					_box(CONTACT, units(_hurtbox_at(pl, events.xs[i], events.ys[i])), "lethal hit")
				)
			SimEvents.HIT:
				_add_hit_marks(sim, events.values[i], at, half, out)


## A burn is marked on the enemy it burned; a finisher at Blaze draws its burst: every other enemy
## whose centre is within the radius of the struck enemy's centre burns (the box is the circle's
## bounding square; the test is the centre's distance).
static func _add_hit_marks(
	sim: Simulation, value: int, at: Vector2, half: Vector2, out: Array[Box]
) -> void:
	var kind: int = HitKind.kind_of(value)
	if kind == HitKind.BURN:
		out.append(_box(CONTACT, Rect2(at - half, half * 2.0), "burn"))
	elif kind == HitKind.FINISHER and sim.player.vitals.kindling.tier() >= Kindling.BLAZE:
		var r: float = float(sim.combat.params.blaze_aoe_radius) / Fx.SUB
		out.append(
			_box(BURST, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), "burst %.0f u" % r)
		)


## Where [param e]'s swing lands when it comes, as [method Enemy.attack_box] would give it on its
## landing tick.
static func swing_box(e: Enemy) -> Rect2i:
	if e.attack == null:
		return Rect2i()
	var w: int = Fx.units(e.attack.box_w_u)
	var left: int = e.body.x + Fx.units(e.attack.box_x_u)
	if e.facing < 0:
		left = e.body.x - Fx.units(e.attack.box_x_u) - w
	return Rect2i(left, e.body.y + Fx.units(e.attack.box_y_u), w, Fx.units(e.attack.box_h_u))


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
			# The window is the last parry_window_frames of the player's own frames before the
			# landing: a press from the tick the swing is that close parries it (BUILD.md
			# section 6; the countdown above counts the world's ticks).
			if e.attack.parryable and e.ticks_to_landing() <= combat.params.parry_window_frames:
				label += "  PARRY WINDOW OPEN"
		if e.burn_left > 0:
			label += "  burning %d" % e.burn_left
		var box: Box = _box(ENEMY if e.is_alive() else ENEMY_DEAD, units(r), label)
		# Clear of the health and poise bars always, and of the telegraph's cue while it is up.
		box.label_lift = EnemyView.BARS_GAP_PX + LABEL_CLEAR_U
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
