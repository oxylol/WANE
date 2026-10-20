extends SceneTree
## Scratch: where combat.resolve's time goes in the stress run (mean us per tick, and over the
## ticks that raised procs).


func _initialize() -> void:
	var fx: Fixture = Fixture.parse_file("res://tests/perf/stress_run.fixture")
	var sim := Simulation.new(fx.scenario)
	var names: Array[String] = [
		"age", "strike", "kindle", "radiance", "pogo", "trails", "procs", "enemy_attacks", "door"
	]
	var sums: PackedInt64Array = PackedInt64Array()
	sums.resize(names.size())
	var psums: PackedInt64Array = PackedInt64Array()
	psums.resize(names.size())
	var rows: Array[PackedInt64Array] = []
	var n: int = 0
	var pn: int = 0
	var c: Combat = sim.combat
	for i: int in range(fx.frame_total):
		var frame: InputFrame = fx.input_frame(i)
		sim.events.clear()
		sim.world.begin_tick()
		sim.procs.begin_tick(sim.tick)
		sim.last_input = frame
		if sim.player != null and sim.player.freeze > 0:
			sim.input.merge(frame)
		else:
			sim.input.push(frame)
		sim.player.step(sim.input)
		sim.enemy_batch.run(c.enemies, sim.player, sim.world)
		var pl: Player = sim.player
		var ring: InputRing = sim.input
		var t: PackedInt64Array = PackedInt64Array()
		t.append(Time.get_ticks_usec())
		c._indexed = false
		c._age_effects(pl)
		t.append(Time.get_ticks_usec())
		var stop: int = 0
		stop = maxi(stop, c._strike(pl))
		t.append(Time.get_ticks_usec())
		stop = maxi(stop, c._kindle(pl))
		t.append(Time.get_ticks_usec())
		c._radiance(pl)
		t.append(Time.get_ticks_usec())
		stop = maxi(stop, c._pogo(pl, ring))
		t.append(Time.get_ticks_usec())
		c._trails(pl)
		t.append(Time.get_ticks_usec())
		c.procs.resolve(c, pl)
		c._indexed = false
		t.append(Time.get_ticks_usec())
		if stop > 0:
			pl.freeze = maxi(pl.freeze, stop)
		c._enemy_attacks(pl, ring)
		t.append(Time.get_ticks_usec())
		sim._take_door()
		t.append(Time.get_ticks_usec())
		sim.tick += 1
		var had: bool = sim.procs.fired() > 0
		if i >= 120:
			var row: PackedInt64Array = PackedInt64Array()
			var tot: int = 0
			for k2: int in range(names.size()):
				row.append(t[k2 + 1] - t[k2])
				tot += t[k2 + 1] - t[k2]
			row.append(tot)
			row.append(sim.procs.fired())
			rows.append(row)
			n += 1
			if had:
				pn += 1
			for k: int in range(names.size()):
				sums[k] += t[k + 1] - t[k]
				if had:
					psums[k] += t[k + 1] - t[k]
	print("ticks ", n, " with procs ", pn)
	for k: int in range(names.size()):
		print(
			"%-14s mean %6.2f us   on proc ticks %7.2f us"
			% [names[k], float(sums[k]) / n, float(psums[k]) / maxi(1, pn)]
		)
	rows.sort_custom(func(a: PackedInt64Array, b: PackedInt64Array) -> bool: return a[9] > b[9])
	print("slowest-combat ticks (rank: parts us ... total, procs)")
	for r: int in [0, 5, 10, 20, 30, 37, 45, 60]:
		print(r, " ", rows[r])
	quit(0)
