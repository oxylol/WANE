extends GdUnitTestSuite

## The boot scene's command line (game/main.gd): the lighting word (second art review I6).


func test_the_command_line_holds_the_dark_at_pitch_or_dusk() -> void:
	assert_str(Main.lighting_arg(PackedStringArray(["--lighting=pitch"]))).is_equal("pitch")
	assert_str(Main.lighting_arg(PackedStringArray(["--room=x", "--lighting=dusk"]))).is_equal(
		"dusk"
	)
	# Any case, and the last one given wins.
	assert_str(Main.lighting_arg(PackedStringArray(["--lighting=Pitch"]))).is_equal("pitch")
	var twice := PackedStringArray(["--lighting=pitch", "--lighting=dusk"])
	assert_str(Main.lighting_arg(twice)).is_equal("dusk")
	assert_str(Main.lighting_arg(PackedStringArray(["--room=x"]))).is_equal("")
	for word: String in ["", "pitch", "dusk"]:
		assert_str(Main.lighting_arg_problem(word)).is_empty()


func test_a_word_that_is_not_a_lighting_word_is_reported_not_silently_dusk() -> void:
	# "off" is the frame bench's baseline (Main.lighting_word), which boots a world with no light:
	# on the command line it is reported like any other word that is not pitch or dusk.
	for word: String in ["off", "bogus", "noon"]:
		var problem: String = Main.lighting_arg_problem(word)
		assert_str(problem).contains(word)
		assert_str(problem).contains(LightWord.PITCH)
		assert_str(problem).contains(LightWord.DUSK)
