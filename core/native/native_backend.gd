class_name NativeBackend
extends RefCounted
## The one switch between the GDScript reference and the native extension (ADR-0021).
##
## The core asks [method use_native]; nothing else decides. The mode is set once at boot by the
## NativeBoot autoload (game/native/native_boot.gd) from the WANE_NATIVE environment variable or
## the project setting wane/native/mode, and is one of:
##   off   always the GDScript reference
##   auto  native when the library is loaded and current, otherwise the reference (the default)
##   on    native, and a boot error if the library is absent or stale (what CI sets)
## Native and reference give bit-identical results, so the mode never changes a hash: that is
## what the fixtures stage under WANE_NATIVE=on and under WANE_NATIVE=off both prove.

enum Mode { OFF, AUTO, ON }

## The version the library must report: native/src/native_probe.h NATIVE_VERSION.
const EXPECTED_VERSION: int = 4
const PROBE_CLASS: StringName = &"NativeProbe"
const MODE_NAMES: Dictionary[String, Mode] = {"off": Mode.OFF, "auto": Mode.AUTO, "on": Mode.ON}

static var _mode: Mode = Mode.AUTO
static var _probe: Object = null


## Sets the mode and forgets the loaded probe (so a test can switch back and forth).
static func configure(mode_value: Mode) -> void:
	_mode = mode_value
	_probe = null


static func mode() -> Mode:
	return _mode


## The name of the current mode ("off", "auto", "on"), as [method parse_mode] reads it.
static func mode_name() -> String:
	return MODE_NAMES.find_key(_mode)


## The mode named [param text] ("off", "auto", "on", any case), or -1 for anything else.
static func parse_mode(text: String) -> int:
	var key: String = text.strip_edges().to_lower()
	if MODE_NAMES.has(key):
		return MODE_NAMES[key]
	return -1


## Why the native library cannot be used, or an empty string if it can.
static func problem() -> String:
	if not ClassDB.class_exists(PROBE_CLASS):
		return "the native library is not loaded (build it with ci/build_native.sh)"
	var probe: Object = _get_probe()
	var found: int = probe.call(&"version")
	if found != EXPECTED_VERSION:
		return "native library version %d, expected %d (rebuild it)" % [found, EXPECTED_VERSION]
	return ""


static func available() -> bool:
	return problem().is_empty()


## True when native code should run: the mode allows it and the library is loaded and current.
static func use_native() -> bool:
	return _mode != Mode.OFF and available()


## What the native library says about itself (compiler and target), for logs; empty if absent.
static func describe() -> String:
	if not ClassDB.class_exists(PROBE_CLASS):
		return ""
	return _get_probe().call(&"describe")


## Dispatch for the probe's methods. Real ports follow this shape: one static function per native
## method, native when [method use_native], else the [NativeRef] twin.
static func fmix32(h: int) -> int:
	if use_native():
		return _get_probe().call(&"fmix32", h)
	return NativeRef.fmix32(h)


static func fold32(seed_value: int, values: PackedInt64Array) -> int:
	if use_native():
		return _get_probe().call(&"fold32", seed_value, values)
	return NativeRef.fold32(seed_value, values)


## The native probe object itself, for the parity test; null if the library is not loaded.
static func native_probe() -> Object:
	if not ClassDB.class_exists(PROBE_CLASS):
		return null
	return _get_probe()


static func _get_probe() -> Object:
	if _probe == null:
		_probe = ClassDB.instantiate(PROBE_CLASS)
	return _probe
