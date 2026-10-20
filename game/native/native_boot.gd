extends Node
## Autoload: reads the native switch once, before anything steps (ADR-0021). The environment
## variable WANE_NATIVE (off, auto, on) wins over the project setting wane/native/mode, which
## defaults to auto. Mode "on" with the library absent or stale is an error that ends the
## process with exit code 1, so a CI job that asks for native never silently runs the reference.

const ENV_VAR: String = "WANE_NATIVE"
const SETTING: String = "wane/native/mode"
const DEFAULT_MODE: String = "auto"

var _failed: bool = false


func _init() -> void:
	var text: String = OS.get_environment(ENV_VAR)
	var source: String = ENV_VAR
	if text.is_empty():
		text = str(ProjectSettings.get_setting(SETTING, DEFAULT_MODE))
		source = SETTING
	var parsed: int = NativeBackend.parse_mode(text)
	if parsed < 0:
		push_error("native: %s is '%s'; expected off, auto or on" % [source, text])
		_failed = true
		return
	NativeBackend.configure(parsed as NativeBackend.Mode)
	if parsed == NativeBackend.Mode.ON:
		var why: String = NativeBackend.problem()
		if not why.is_empty():
			push_error("native: mode on but %s" % why)
			_failed = true


func _enter_tree() -> void:
	if _failed:
		get_tree().quit(1)
