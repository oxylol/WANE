class_name ContentHash
extends RefCounted
## Fingerprint of the content a simulation was built from (a Wick's tuning resources and, from
## Phase 1 task 3, the room), so a replay recorded with different content reports "different
## content" instead of a desync, and golden fixture hashes can tell a content change from a code
## change (ADR-0006). Script variables are hashed in declaration order, which is stable.


static func add_resource(h: StateHasher, res: Resource) -> void:
	if res == null:
		h.add_int(0)
		return
	var script: Script = res.get_script()
	h.add_string(script.resource_path if script != null else res.get_class())
	var props: Array[Dictionary] = res.get_property_list()
	for i: int in range(props.size()):
		var usage: int = props[i]["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var prop: String = props[i]["name"]
		h.add_string(prop)
		_add_value(h, res.get(prop))


static func _add_value(h: StateHasher, v: Variant) -> void:
	match typeof(v):
		TYPE_INT:
			var i: int = v
			h.add_int(i)
		TYPE_BOOL:
			var b: bool = v
			h.add_bool(b)
		TYPE_STRING, TYPE_STRING_NAME:
			h.add_string(str(v))
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = v
			h.add_int(strings.size())
			for item: String in strings:
				h.add_string(item)
		TYPE_ARRAY:
			var count: int = 0
			for item: Variant in v:
				_add_value(h, item)
				count += 1
			h.add_int(count)
		TYPE_OBJECT:
			var obj: Object = v
			add_resource(h, obj as Resource)
		_:
			h.add_string(var_to_str(v))
