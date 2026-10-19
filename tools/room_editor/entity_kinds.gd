class_name EntityKinds
extends RefCounted
## What the room editor knows about entity kinds: the properties a kind reads and what values
## they take, so the editor can offer them and name a wrong one. Only the training dummy is
## simulated in Phase 1 (core/enemies/training_dummy.gd, `from_entity`); any other kind is
## placed and saved as a marker with free key=value properties.

## How a property's value is written: a flag is 1 (a property that is off is left out), a count
## is an integer from 1 (left out for the content's default), a facing is -1 or 1.
enum Type { FLAG, COUNT, FACING }

const DUMMY: String = "dummy"
## The kinds the editor offers when placing an entity.
const KINDS: Array[String] = [DUMMY]


## One property of an entity kind.
class PropSpec:
	var key: String = ""
	var label: String = ""
	var type: int = Type.FLAG
	var max_value: int = 1

	func _init(p_key: String, p_label: String, p_type: int, p_max: int = 1) -> void:
		key = p_key
		label = p_label
		type = p_type
		max_value = p_max

	## Whether [param value] is written as this property's value.
	func accepts(value: String) -> bool:
		if type == Type.FACING:
			return value == "-1" or value == "1"
		if not value.is_valid_int():
			return false
		if type == Type.FLAG:
			return value.to_int() == 0 or value.to_int() == 1
		return value.to_int() >= 1 and value.to_int() <= max_value


## The properties of [param kind], in the order the editor lists them; none for a kind the
## editor does not know.
static func props_of(kind: String) -> Array[PropSpec]:
	var out: Array[PropSpec] = []
	if kind == DUMMY:
		out.append(PropSpec.new("attack", "Swings", Type.FLAG))
		out.append(PropSpec.new("red", "Red swing (unparryable)", Type.FLAG))
		out.append(PropSpec.new("light", "Light (staggers on one hit)", Type.FLAG))
		out.append(PropSpec.new("period", "Ticks between swings", Type.COUNT, 600))
		out.append(PropSpec.new("hp", "Hit points", Type.COUNT, 9999))
		out.append(PropSpec.new("poise", "Poise", Type.COUNT, 9999))
		out.append(PropSpec.new("facing", "Faces (before it turns)", Type.FACING))
	return out


## The spec of property [param key] of [param kind], or null.
static func prop(kind: String, key: String) -> PropSpec:
	for spec: PropSpec in props_of(kind):
		if spec.key == key:
			return spec
	return null


## Problems with entity [param e], as the editor words them: a property the kind does not read,
## or a value it cannot use (the loader would quietly use the default).
static func problems(e: RoomData.RoomEntity, index: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if props_of(e.kind).is_empty():
		return out
	var keys: Array[String] = []
	for k: String in e.props:
		keys.append(k)
	keys.sort()
	for k: String in keys:
		var spec: PropSpec = prop(e.kind, k)
		var label: String = "entity %d (%s at %d, %d)" % [index + 1, e.kind, e.x_u, e.y_u]
		if spec == null:
			out.append("%s: a %s has no property '%s'" % [label, e.kind, k])
		elif not spec.accepts(e.props[k]):
			out.append("%s: '%s=%s' is not a valid value" % [label, k, e.props[k]])
	return out
