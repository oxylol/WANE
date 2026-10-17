extends GdUnitTestSuite
## ContentHash: equal content hashes equally; any tuned value changes the fingerprint.


func _hash(res: Resource) -> int:
	var h := StateHasher.new()
	ContentHash.add_resource(h, res)
	return h.value()


func test_equal_content_equal_hash() -> void:
	var a: InputSettings = load(InputLayer.SETTINGS_PATH) as InputSettings
	var b: InputSettings = (load(InputLayer.SETTINGS_PATH) as InputSettings).duplicate()
	assert_int(_hash(a)).is_equal(_hash(b))


func test_any_value_changes_the_hash() -> void:
	var a: InputSettings = load(InputLayer.SETTINGS_PATH) as InputSettings
	var base: int = _hash(a)
	var b: InputSettings = a.duplicate()
	b.stick_step += 1
	assert_int(_hash(b)).is_not_equal(base)
	var c: InputSettings = a.duplicate()
	c.bindings = PackedStringArray(["jump=key:Q"])
	assert_int(_hash(c)).is_not_equal(base)


func test_null_and_nested_values() -> void:
	var h := StateHasher.new()
	ContentHash.add_resource(h, null)
	assert_int(h.value()).is_not_equal(StateHasher.new().value())


func test_a_value_inside_a_sub_resource_changes_the_hash() -> void:
	var taper: AttackSet = load("res://content/wicks/ash/taper.tres") as AttackSet
	var base: int = _hash(taper)
	var b: AttackSet = taper.duplicate(true)
	assert_int(_hash(b)).is_equal(base)
	b.attacks[4].pogo_last += 1
	assert_int(_hash(b)).is_not_equal(base)
	var c: AttackSet = taper.duplicate(true)
	var first: AttackDef = c.attacks[0]
	c.attacks[0] = c.attacks[1]
	c.attacks[1] = first
	assert_int(_hash(c)).is_not_equal(base)
