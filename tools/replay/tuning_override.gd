class_name TuningOverride
extends RefCounted
## The --set option of the replay tools: changes a tuning value on the loaded (cached) resource so
## everything built from that path afterwards uses it, to show a feel-log "before" next to its
## "after".


## Applies "res://path.tres:property=value" (an integer); [param held] keeps the changed resource
## alive so the cache keeps the changed copy. Prints why and returns false if it cannot.
static func apply(spec: String, held: Array[Resource]) -> bool:
	var colon: int = spec.rfind(":")
	var eq: int = spec.find("=", colon)
	if colon <= 0 or eq < 0:
		printerr("--set needs <res path>:<property>=<int>, got '%s'" % spec)
		return false
	var res: Resource = load(spec.substr(0, colon))
	var prop: String = spec.substr(colon + 1, eq - colon - 1)
	if res == null or not prop in res:
		printerr("--set: no property '%s' on %s" % [prop, spec.substr(0, colon)])
		return false
	res.set(prop, spec.substr(eq + 1).to_int())
	held.append(res)
	print("set %s" % spec)
	return true
