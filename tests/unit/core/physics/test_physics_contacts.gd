extends GdUnitTestSuite
## Contacts: wall proximity for wall-cling (clingable versus smooth walls, BUILD.md section 5 feel
## rules), the spike volume, and solid boxes.

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
