class_name ReplayFiles
extends RefCounted
## Replay files on disk (BUILD.md section 13, layer 5, services). The core only encodes and
## decodes; reading and writing files happens here.


static func save(replay: Replay, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(replay.encode())
	f.close()
	return OK


## The replay at [param path], or null if it is missing or not a valid replay.
static func load_file(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		return null
	return Replay.decode(FileAccess.get_file_as_bytes(path))
