extends GdUnitTestSuite
## Contacts: wall proximity for wall-cling (clingable versus smooth walls, BUILD.md section 5 feel
## rules), the spike and pit hazard volumes, and solid boxes.

const U: int = PhysicsKit.U
const HALF_W: int = PhysicsKit.HALF_W
const STAND: int = PhysicsKit.STAND
const CROUCH: int = PhysicsKit.CROUCH


func test_wall_near_respects_clingable_walls_and_reach() -> void:
	var w: CollisionWorld = PhysicsKit.world(["S.....#.", "S.....#.", "S.....#.", "########"])
	# The right wall's face is 1 unit from the box: reach 2 finds it, reach 1 does not.
	var b: Body = PhysicsKit.body(181, 80)
	assert_bool(w.wall_near(b, 1, 2 * U)).is_true()
	assert_bool(w.wall_near(b, 1, U)).is_false()
	var c: Body = PhysicsKit.body(43, 80)
	assert_bool(w.wall_near(c, -1, 2 * U)).is_false()
	assert_bool(w.wall_near(c, -1, 2 * U, true)).is_true()


func test_spike_volume() -> void:
	var w: CollisionWorld = PhysicsKit.world(["....", "....", ".^^.", "####"])
	var above: Body = PhysicsKit.body(64, 76)
	assert_bool(w.touches_spikes(above.left(), above.right(), above.top(), above.y)).is_false()
	var inside: Body = PhysicsKit.body(64, 77)
	assert_bool(w.touches_spikes(inside.left(), inside.right(), inside.top(), inside.y)).is_true()


func test_a_pit_is_a_hazard_through_its_whole_tile_and_nothing_to_pogo_off() -> void:
	# Physics review 8, L3: the pit (ADR-0008 decision 1; movement review 5, H1) is a hazard from
	# its tile's top edge down to its bottom, with no inset, and only spikes answer touches_spikes,
	# the pogo's test.
	var w: CollisionWorld = PhysicsKit.world(["....", ".~~.", "....", "....", "....", "####"])
	var top: int = 32 * U
	var level: Body = Body.make(64 * U, top, HALF_W, STAND)
	assert_bool(_hazard(w, level)).override_failure_message("level with its top").is_false()
	var dipped: Body = Body.make(64 * U, top + 1, HALF_W, STAND)
	assert_bool(_hazard(w, dipped)).override_failure_message("a sub-pixel in").is_true()
	var deep: Body = Body.make(64 * U, top + TileGrid.TILE_SP, HALF_W, STAND)
	assert_bool(_hazard(w, deep)).override_failure_message("at its bottom").is_true()
	assert_bool(w.touches_spikes(deep.left(), deep.right(), deep.top(), deep.y)).is_false()
	# Beside it (the tile's edge is exclusive) and under it, the head clear of its bottom: out.
	var beside: Body = Body.make(32 * U - HALF_W, top + 16 * U, HALF_W, STAND)
	assert_bool(_hazard(w, beside)).override_failure_message("beside").is_false()
	var under: Body = Body.make(64 * U, 64 * U + STAND, HALF_W, STAND)
	assert_bool(_hazard(w, under)).override_failure_message("under").is_false()
	under.y -= 1
	assert_bool(_hazard(w, under)).override_failure_message("head a sub-pixel in").is_true()


func test_spikes_hurt_from_their_inset_down_and_are_pogo_able() -> void:
	# Physics review 8, L3: touches_hazard counts spikes as touches_spikes does, from
	# spike_inset_sp below the tile's top, and follows the world's tuning of it.
	var w: CollisionWorld = PhysicsKit.world(["....", "....", ".^^.", "####"])
	var top: int = 64 * U
	var at_inset: Body = Body.make(64 * U, top + w.spike_inset_sp, HALF_W, STAND)
	assert_bool(_hazard(w, at_inset)).is_false()
	var below: Body = Body.make(64 * U, top + w.spike_inset_sp + 1, HALF_W, STAND)
	assert_bool(_hazard(w, below)).is_true()
	assert_bool(w.touches_spikes(below.left(), below.right(), below.top(), below.y)).is_true()
	var flush: Body = Body.make(64 * U, top + 1, HALF_W, STAND)
	assert_bool(_hazard(w, flush)).is_false()
	w.spike_inset_sp = 0
	assert_bool(_hazard(w, flush)).is_true()


func _hazard(w: CollisionWorld, b: Body) -> bool:
	return w.touches_hazard(b.left(), b.right(), b.top(), b.y)


func test_solid_boxes_block_and_support_until_disabled() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "........", "########"])
	var door: SolidBox = SolidBox.make(160 * U, 0, 192 * U, 96 * U)
	w.solids.append(door)
	var b: Body = PhysicsKit.body(145, 96)
	assert_int(PhysicsKit.walk(w, b, 9 * U)).is_equal(5 * U)
	door.enabled = false
	assert_int(PhysicsKit.walk(w, b, 9 * U)).is_equal(9 * U)
	var ledge: SolidBox = SolidBox.make(0, 50 * U, 64 * U, 60 * U)
	w.solids.append(ledge)
	var c: Body = PhysicsKit.body(30, 20)
	w.move_y(c, 40 * U)
	assert_int(c.y).is_equal(50 * U)
	assert_bool(c.on_ground).is_true()


func test_world_tuning_validates_and_seeds_new_worlds() -> void:
	# A world starts with WorldTuning's defaults (never an untuned 0), and the game's content
	# file is what the game applies.
	var fresh := CollisionWorld.new(TileGrid.new(2, 2))
	var defaults := WorldTuning.new()
	assert_int(fresh.spike_inset_sp).is_equal(Fx.units(defaults.spike_inset_u))
	var content: WorldTuning = load(WorldTuning.PATH) as WorldTuning
	assert_array(Array(content.validate())).is_empty()
	var bad := WorldTuning.new()
	bad.spike_inset_u = TileGrid.TILE
	assert_int(bad.validate().size()).is_equal(1)
	bad.spike_inset_u = -1
	assert_int(bad.validate().size()).is_equal(1)


func test_wall_near_finds_clingable_solid_boxes_only() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "........", "########"])
	var door := SolidBox.make(112 * U, 0, 120 * U, 96 * U)
	w.solids.append(door)
	var b: Body = PhysicsKit.body(101, 96)
	assert_bool(w.wall_near(b, 1, 2 * U)).is_true()
	assert_bool(w.wall_near(b, -1, 2 * U)).is_false()
	door.clingable = false
	assert_bool(w.wall_near(b, 1, 2 * U)).is_false()
