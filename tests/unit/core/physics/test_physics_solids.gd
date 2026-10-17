extends GdUnitTestSuite
## Solid boxes (doors, wax walls) in every sweep, point and fit queries, and the hashes that put
## physics state into replays.

const U: int = PhysicsKit.U


func _open() -> CollisionWorld:
	return PhysicsKit.world(["..........", "..........", "..........", "..........", "##########"])


func test_solid_blocks_both_horizontal_directions_and_upward() -> void:
	var w: CollisionWorld = _open()
	w.solids.append(SolidBox.make(100 * U, 40 * U, 140 * U, 128 * U))
	var right: Body = PhysicsKit.body(80, 128)
	assert_int(w.move_x(right, 30 * U)).is_equal(10 * U)
	var left: Body = PhysicsKit.body(160, 128)
	assert_int(w.move_x(left, -30 * U)).is_equal(-10 * U)
	var under: Body = PhysicsKit.body(120, 100)
	w.solids[0].top = 0
	w.solids[0].bottom = 40 * U
	assert_int(w.move_y(under, -30 * U)).is_equal(-16 * U)
	assert_bool(under.hit_ceiling).is_true()


func test_lift_onto_and_duck_under_solid_boxes() -> void:
	var w: CollisionWorld = _open()
	w.solids.append(SolidBox.make(100 * U, 100 * U, 160 * U, 128 * U))
	var b: Body = PhysicsKit.body(85, 106)
	assert_int(w.move_x(b, 9 * U, 8 * U)).is_equal(9 * U)
	assert_int(b.y).is_equal(100 * U)
	var v: CollisionWorld = _open()
	v.solids.append(SolidBox.make(100 * U, 0, 160 * U, 30 * U))
	var c: Body = PhysicsKit.body(85, 70)
	assert_int(v.move_x(c, 9 * U, 0, 6 * U)).is_equal(9 * U)
	assert_int(c.top()).is_equal(30 * U)


func test_walking_onto_a_solid_box_top_stands_on_it() -> void:
	var w: CollisionWorld = _open()
	w.solids.append(SolidBox.make(0, 128 * U, 320 * U, 140 * U))
	w.grid.set_tile(3, 4, TileGrid.EMPTY)
	var b: Body = PhysicsKit.body(80, 128)
	w.refresh_ground(b)
	assert_bool(b.on_ground).is_true()
	PhysicsKit.walk(w, b, 30 * U)
	assert_bool(b.on_ground).is_true()
	assert_int(b.y).is_equal(128 * U)


func test_point_solid_and_body_fits() -> void:
	var w: CollisionWorld = PhysicsKit.world(["....", "../#", "####"])
	assert_bool(w.point_solid(110 * U, 40 * U)).is_true()
	assert_bool(w.point_solid(20 * U, 40 * U)).is_false()
	# The slope at (2, 1): its surface at x = 72 is y = 56; below that is solid.
	assert_bool(w.point_solid(72 * U, 57 * U)).is_true()
	assert_bool(w.point_solid(72 * U, 55 * U)).is_false()
	w.solids.append(SolidBox.make(0, 0, 10 * U, 10 * U))
	assert_bool(w.point_solid(5 * U, 5 * U)).is_true()
	assert_bool(w.body_fits(20 * U, 64 * U, PhysicsKit.HALF_W, PhysicsKit.STAND)).is_true()
	assert_bool(w.body_fits(72 * U, 60 * U, PhysicsKit.HALF_W, PhysicsKit.STAND)).is_false()
	assert_bool(w.body_fits(110 * U, 64 * U, PhysicsKit.HALF_W, PhysicsKit.STAND)).is_false()


func test_hashes_cover_every_physics_field() -> void:
	var a: Body = PhysicsKit.body(10, 20)
	var b: Body = PhysicsKit.body(10, 20)
	assert_int(_hash_body(a)).is_equal(_hash_body(b))
	b.on_ground = true
	assert_int(_hash_body(a)).is_not_equal(_hash_body(b))
	var s: SolidBox = SolidBox.make(1, 2, 3, 4)
	var t: SolidBox = SolidBox.make(1, 2, 3, 4)
	t.enabled = false
	var hs := StateHasher.new()
	s.hash_into(hs)
	var ht := StateHasher.new()
	t.hash_into(ht)
	assert_int(hs.value()).is_not_equal(ht.value())
	var g: TileGrid = TileGrid.from_rows(PackedStringArray(["#..", "./#"]))
	var g2: TileGrid = TileGrid.from_rows(PackedStringArray(["#..", "./#"]))
	var hg := StateHasher.new()
	g.hash_into(hg)
	var hg2 := StateHasher.new()
	g2.hash_into(hg2)
	assert_int(hg.value()).is_equal(hg2.value())
	g2.set_tile(0, 0, TileGrid.EMPTY)
	var hg3 := StateHasher.new()
	g2.hash_into(hg3)
	assert_int(hg3.value()).is_not_equal(hg.value())


func test_every_slope_kind_has_edge_heights() -> void:
	var t: int = TileGrid.TILE_SP
	assert_bool(TileGrid.slope_edge_heights(TileGrid.SLOPE_L) == Vector2i(t, 0)).is_true()
	assert_bool(TileGrid.slope_edge_heights(TileGrid.SLOPE_R_LO) == Vector2i(0, t / 2)).is_true()
	assert_bool(TileGrid.slope_edge_heights(TileGrid.SLOPE_R_HI) == Vector2i(t / 2, t)).is_true()
	assert_bool(TileGrid.slope_edge_heights(TileGrid.SLOPE_L_HI) == Vector2i(t, t / 2)).is_true()
	assert_bool(TileGrid.slope_edge_heights(TileGrid.SOLID) == Vector2i(t, t)).is_true()
	assert_int(TileGrid.slope_surface(TileGrid.SOLID, 0, 1, 5)).is_equal(t)


func _hash_body(b: Body) -> int:
	var h := StateHasher.new()
	b.hash_into(h)
	return h.value()


func test_empty_regions_never_count_as_blocked() -> void:
	var w: CollisionWorld = PhysicsKit.world(["####", "####"])
	assert_bool(w.region_blocked(10 * U, 10 * U, 0, 50 * U)).is_false()
	assert_bool(w.region_blocked(0, 50 * U, 20 * U, 20 * U)).is_false()
	assert_bool(w.region_blocked(10 * U, 11 * U, 20 * U, 21 * U)).is_true()


func test_a_body_placed_inside_a_solid_box_is_not_held_up_by_it() -> void:
	# A foot point inside a solid box finds no floor there (a teleport into a closing door must
	# not stand the body on the door's inside).
	var w: CollisionWorld = _open()
	w.solids.append(SolidBox.make(90 * U, 60 * U, 110 * U, 100 * U))
	var b: Body = PhysicsKit.body(100, 80)
	w.refresh_ground(b)
	assert_bool(b.on_ground).is_false()


func test_drop_through_needs_one_ways_alone_at_a_tile_top() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["..........", "..........", "..======..", "..........", "##########"]
	)
	# On a slope: never.
	var s: CollisionWorld = PhysicsKit.world(["......", "......", "../###", "######"])
	var on_slope: Body = PhysicsKit.body(80, 80)
	s.refresh_ground(on_slope)
	assert_bool(on_slope.on_slope).is_true()
	assert_bool(s.can_drop_through(on_slope)).is_false()
	# Standing on a solid box's top, which is not at a tile top: never.
	var o: CollisionWorld = _open()
	o.solids.append(SolidBox.make(80 * U, 70 * U, 140 * U, 90 * U))
	var on_solid: Body = PhysicsKit.body(100, 70)
	o.refresh_ground(on_solid)
	assert_bool(on_solid.on_ground).is_true()
	assert_bool(o.can_drop_through(on_solid)).is_false()
	# A solid box whose top is level with the one-way, under the box: it holds the box up.
	var plank := SolidBox.make(100 * U, 64 * U, 110 * U, 96 * U)
	w.solids.append(plank)
	var b: Body = PhysicsKit.body(112, 64)
	w.refresh_ground(b)
	assert_bool(w.can_drop_through(b)).is_false()
	plank.enabled = false
	assert_bool(w.can_drop_through(b)).is_true()
