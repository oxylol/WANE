class_name FileWalk
extends RefCounted
## Recursive, sorted file discovery under res:// for tools and tests. Sorted so every run visits
## files in the same order on every platform.


## Returns every file under [param root] whose name ends with one of [param suffixes], sorted.
static func find(root: String, suffixes: Array[String]) -> Array[String]:
	var found: Array[String] = []
	_walk(root, suffixes, found)
	found.sort()
	return found


static func _walk(dir_path: String, suffixes: Array[String], found: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = false
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_walk(dir_path.path_join(sub), suffixes, found)
	for file: String in dir.get_files():
		for suffix: String in suffixes:
			if file.ends_with(suffix):
				found.append(dir_path.path_join(file))
				break
