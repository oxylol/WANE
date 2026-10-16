extends GdUnitTestSuite
## Toolchain invariants: the pinned engine (ADR-0001) and the locked warning policy (ADR-0002).

## Every GDScript warning setting and the level ADR-0002 fixes for it. Lowering any of these is
## lowering a gate threshold (CLAUDE.md, Prohibited).
const WARNING_LEVELS: Dictionary[String, int] = {
	"unassigned_variable": 2,
	"unassigned_variable_op_assign": 2,
	"unused_variable": 2,
	"unused_local_constant": 2,
	"unused_private_class_variable": 2,
	"unused_parameter": 2,
	"unused_signal": 2,
	"shadowed_variable": 2,
	"shadowed_variable_base_class": 2,
	"shadowed_global_identifier": 2,
	"unreachable_code": 2,
	"unreachable_pattern": 2,
	"standalone_expression": 2,
	"standalone_ternary": 2,
	"incompatible_ternary": 2,
	"untyped_declaration": 2,
	"inferred_declaration": 0,
	"unsafe_property_access": 2,
	"unsafe_method_access": 2,
	"unsafe_cast": 2,
	"unsafe_call_argument": 2,
	"unsafe_void_return": 2,
	"return_value_discarded": 0,
	"static_called_on_instance": 2,
	"missing_tool": 2,
	"redundant_static_unload": 2,
	"redundant_await": 2,
	"missing_await": 2,
	"assert_always_true": 2,
	"assert_always_false": 2,
	"integer_division": 0,
	"narrowing_conversion": 2,
	"int_as_enum_without_cast": 2,
	"int_as_enum_without_match": 2,
	"enum_variable_without_default": 2,
	"empty_file": 2,
	"deprecated_keyword": 2,
	"confusable_identifier": 2,
	"confusable_local_declaration": 2,
	"confusable_local_usage": 2,
	"confusable_capture_reassignment": 2,
	"confusable_temporary_modification": 2,
	"inference_on_variant": 2,
	"native_method_override": 2,
	"get_node_default_without_onready": 2,
	"onready_with_export": 2,
	"property_used_as_function": 2,
	"constant_used_as_function": 2,
	"function_used_as_property": 2,
}


func test_engine_matches_pinned_version() -> void:
	var pinned: String = FileAccess.get_file_as_string("res://.godot-version").strip_edges()
	var major: int = Engine.get_version_info()["major"]
	var minor: int = Engine.get_version_info()["minor"]
	var patch: int = Engine.get_version_info()["patch"]
	var status: String = Engine.get_version_info()["status"]
	assert_str(_release_name(major, minor, patch, status)).is_equal(pinned)


func test_release_name_drops_zero_patch() -> void:
	assert_str(_release_name(4, 8, 0, "stable")).is_equal("4.8-stable")
	assert_str(_release_name(4, 8, 1, "stable")).is_equal("4.8.1-stable")


func test_warning_levels_are_locked() -> void:
	assert_bool(ProjectSettings.get_setting("debug/gdscript/warnings/enable")).is_true()
	for warning: String in WARNING_LEVELS:
		var level: int = ProjectSettings.get_setting("debug/gdscript/warnings/" + warning)
		(
			assert_int(level)
			. override_failure_message(
				(
					"warning '%s' is at level %d; ADR-0002 fixes it at %d"
					% [warning, level, WARNING_LEVELS[warning]]
				)
			)
			. is_equal(WARNING_LEVELS[warning])
		)


func test_every_engine_warning_is_listed() -> void:
	var properties: Array[Dictionary] = ProjectSettings.get_property_list()
	for i: int in range(properties.size()):
		var setting: String = properties[i]["name"]
		if not setting.begins_with("debug/gdscript/warnings/"):
			continue
		var warning: String = setting.trim_prefix("debug/gdscript/warnings/")
		if warning in ["enable", "directory_rules", "renamed_in_godot_4_hint"]:
			continue
		(
			assert_bool(WARNING_LEVELS.has(warning))
			. override_failure_message(
				"new engine warning '%s' needs a level decided in ADR-0002" % warning
			)
			. is_true()
		)


func test_only_vendored_code_is_excluded_from_warnings() -> void:
	var rules: Dictionary[Variant, Variant] = ProjectSettings.get_setting(
		"debug/gdscript/warnings/directory_rules"
	)
	assert_int(rules.size()).is_equal(1)
	var level: int = rules.get("res://addons/gdUnit4", -1)
	assert_int(level).is_equal(0)


func test_file_walk_is_sorted_and_filtered() -> void:
	var found: Array[String] = FileWalk.find("res://tools/ci", [".gd"])
	assert_bool(found.has("res://tools/ci/file_walk.gd")).is_true()
	var sorted: Array[String] = found.duplicate()
	sorted.sort()
	assert_array(found).is_equal(sorted)
	for path: String in found:
		assert_str(path).ends_with(".gd")


## Godot's release naming: "4.7.2-stable", but "4.8-stable" for a .0 release.
func _release_name(major: int, minor: int, patch: int, status: String) -> String:
	var version: String = "%d.%d" % [major, minor]
	if patch != 0:
		version += ".%d" % patch
	return "%s-%s" % [version, status]
