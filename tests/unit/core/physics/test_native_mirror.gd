extends GdUnitTestSuite
## The native copy of a world's solid boxes (docs/adr/0022 Decision 3) never goes stale: a box
## shared between two worlds, a list changed in place (a box replaced, two swapped, one removed
## and edited afterwards) all give the answer the GDScript reference gives, as far as the contract
## reaches. The contract: edits to the boxes are always seen; a change to the list itself is seen
## when its length or identity changes, and otherwise at the next [method CollisionWorld.begin_tick]
## (the simulation calls it at the start of every tick) or [method NativeWorld.invalidate].

const U: int = Fx.SUB
const T: int = 32 * U
const ROWS: Array[String] = [
	"#..............#", "#..............#", "################", "################"
]


func _pair() -> Array[CollisionWorld]:
	var native_world: CollisionWorld = PhysicsKit.world(ROWS)
	native_world.native = NativeWorld.create(true)
	assert_object(native_world.native).is_not_null()
	var reference: CollisionWorld = PhysicsKit.world(ROWS)
	reference.native = null
	return [reference, native_world]


## A walk of 10 tiles east from the left of the room, in [param w]: where the body stopped.
func _walk_east(w: CollisionWorld) -> Array[int]:
	var body: Body = Body.make(2 * T, 2 * T, 10 * U, 44 * U)
	w.walk(body, 10 * T)
	return [body.x, body.hit_wall]


func _agree(reference: CollisionWorld, other: CollisionWorld, why: String) -> void:
	assert_array(_walk_east(other)).override_failure_message(why).is_equal(_walk_east(reference))


func test_a_box_shared_by_two_native_worlds_reaches_both() -> void:
	var a: CollisionWorld = PhysicsKit.world(ROWS)
	a.native = NativeWorld.create(true)
	var b: CollisionWorld = PhysicsKit.world(ROWS)
	b.native = NativeWorld.create(true)
	var reference: CollisionWorld = PhysicsKit.world(ROWS)
	reference.native = null
	var box: SolidBox = SolidBox.make(6 * T, T, 7 * T, 2 * T)
	a.solids.append(box)
	b.solids.append(box)
	reference.solids.append(box)
	_agree(reference, a, "first sight, world a")
	_agree(reference, b, "first sight, world b")
	box.enabled = false
	_agree(reference, a, "disabled, world a")
	_agree(reference, b, "disabled, world b")
	box.enabled = true
	box.left += T
	box.right += T
	_agree(reference, a, "moved, world a")
	_agree(reference, b, "moved, world b")


func test_a_box_replaced_in_the_list_is_seen_at_the_next_tick() -> void:
	var p: Array[CollisionWorld] = _pair()
	for w: CollisionWorld in p:
		w.solids.append(SolidBox.make(6 * T, T, 7 * T, 2 * T))
	_agree(p[0], p[1], "before")
	for w: CollisionWorld in p:
		w.solids[0] = SolidBox.make(9 * T, T, 10 * T, 2 * T)
		w.begin_tick()
	_agree(p[0], p[1], "after the replacement")
	assert_int(_walk_east(p[1])[0]).is_equal(9 * T - 10 * U)


func test_two_boxes_swapped_in_the_list_are_seen_at_the_next_tick() -> void:
	var p: Array[CollisionWorld] = _pair()
	for w: CollisionWorld in p:
		w.solids.append(SolidBox.make(6 * T, T, 7 * T, 2 * T))
		w.solids.append(SolidBox.make(9 * T, T, 10 * T, 2 * T))
	_agree(p[0], p[1], "before")
	for w: CollisionWorld in p:
		var first: SolidBox = w.solids[0]
		w.solids[0] = w.solids[1]
		w.solids[1] = first
		w.begin_tick()
	_agree(p[0], p[1], "after the swap")
	# The swapped box is then edited: the edit must reach its new slot.
	for w: CollisionWorld in p:
		w.solids[0].enabled = false
	_agree(p[0], p[1], "an edit after the swap")


func test_a_box_removed_and_then_edited_does_nothing_to_the_world() -> void:
	var p: Array[CollisionWorld] = _pair()
	var gone: Array[SolidBox] = []
	for w: CollisionWorld in p:
		var keep: SolidBox = SolidBox.make(9 * T, T, 10 * T, 2 * T)
		var drop: SolidBox = SolidBox.make(6 * T, T, 7 * T, 2 * T)
		w.solids.append(keep)
		w.solids.append(drop)
		gone.append(drop)
	_agree(p[0], p[1], "before")
	for w: CollisionWorld in p:
		w.solids.remove_at(1)
	_agree(p[0], p[1], "after the removal")
	for box: SolidBox in gone:
		box.left += 10
		box.enabled = false
	for w: CollisionWorld in p:
		w.solids.clear()
	_agree(p[0], p[1], "after the clear")
	for box: SolidBox in gone:
		box.right += 10
	_agree(p[0], p[1], "an edit of a box long gone")
	for w: CollisionWorld in p:
		w.solids.append(SolidBox.make(5 * T, T, 6 * T, 2 * T))
	_agree(p[0], p[1], "a new box")


func test_invalidate_forgets_the_mirror() -> void:
	var p: Array[CollisionWorld] = _pair()
	for w: CollisionWorld in p:
		w.solids.append(SolidBox.make(6 * T, T, 7 * T, 2 * T))
	_agree(p[0], p[1], "before")
	for w: CollisionWorld in p:
		w.solids[0] = SolidBox.make(8 * T, T, 9 * T, 2 * T)
	p[1].native.invalidate()
	_agree(p[0], p[1], "after invalidate")
