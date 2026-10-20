class_name SimCache
extends RefCounted
## What simulations built one after another can share (BUILD.md section 13, "they run headless in
## under 10 seconds total"; docs/adr/0006, Shards): the rooms and room sets they read, the content
## resources they load and validate, and the fingerprint of each, none of which a run changes.
## A fixture shard builds about 130 simulations in a row from the same few rooms and the same
## tuning files; building each from scratch parsed, validated and digested all of it again.
##
## A [Simulation] built with a cache is the simulation built without one: the cache hands back
## exactly what the build would have computed ([code]tests/unit/core/test_sim_cache.gd[/code] holds
## every fixture's cached run to a fresh one). It serves content as it was when it first read it,
## so a batch that edits a resource or a room file between builds uses a cache of its own, or none.
## Nothing is shared between processes, and the game builds its simulations without one.


## A content resource and the problems its [code]validate()[/code] reported.
class Loaded:
	var res: Resource = null
	var problems: PackedStringArray = PackedStringArray()


var _loaded: Dictionary[String, Loaded] = {}
var _rooms: Dictionary[String, RoomData] = {}
var _room_sets: Dictionary[String, RoomSet] = {}
var _room_words: Dictionary[String, PackedInt64Array] = {}
var _joins: Dictionary[String, PackedStringArray] = {}
var _resource_words: Dictionary[int, PackedInt64Array] = {}


## Room [param room_id], parsed once ([method RoomData.load_id]). Callers only read it.
func room(room_id: String) -> RoomData:
	var hit: RoomData = _rooms.get(room_id, null)
	if hit == null:
		hit = RoomData.load_id(room_id)
		_rooms[room_id] = hit
	return hit


## The rooms reachable from [param start_id] ([method RoomSet.reach]), each parsed once. Callers
## only read it.
func room_set(start_id: String) -> RoomSet:
	var hit: RoomSet = _room_sets.get(start_id, null)
	if hit == null:
		hit = RoomSet.reach(start_id, self)
		_room_sets[start_id] = hit
	return hit


## The problems with [param target]'s joins ([method RoomJoins.errors]).
func joins_errors(target: RoomData, band_sp: int, reach_sp: int) -> PackedStringArray:
	if _rooms.get(target.id, null) != target:
		return RoomJoins.errors(target, band_sp, reach_sp)
	var key: String = "%s|%d|%d" % [target.id, band_sp, reach_sp]
	if not _joins.has(key):
		_joins[key] = RoomJoins.errors(target, band_sp, reach_sp)
	return _joins[key].duplicate()


## Adds [param target]'s content to the fingerprint [param h] ([method ContentHash.add_room]).
func add_room(h: StateHasher, target: RoomData) -> void:
	if _rooms.get(target.id, null) != target:
		ContentHash.add_room(h, target)
		return
	if not _room_words.has(target.id):
		_room_words[target.id] = ContentHash.room_words(target)
	h.add_ints(_room_words[target.id])


## The resource at [param path] with the problems its validation found, loaded and validated once;
## [code]res[/code] is null if there is no such file.
func load_content(path: String) -> Loaded:
	var hit: Loaded = _loaded.get(path, null)
	if hit != null:
		return hit
	var found := Loaded.new()
	if not ResourceLoader.exists(path):
		return found
	found.res = load(path)
	if found.res == null:
		return found
	if found.res.has_method("validate"):
		found.problems = found.res.call("validate")
	_loaded[path] = found
	return found


## Adds [param res] to the fingerprint [param h] ([method ContentHash.add_resource]); a resource
## this cache loaded is digested once.
func add_resource(h: StateHasher, res: Resource) -> void:
	if res == null or not _is_loaded_here(res):
		ContentHash.add_resource(h, res)
		return
	var key: int = res.get_instance_id()
	if not _resource_words.has(key):
		_resource_words[key] = ContentHash.resource_words(res)
	h.add_ints(_resource_words[key])


func _is_loaded_here(res: Resource) -> bool:
	var loaded: Loaded = _loaded.get(res.resource_path, null)
	return loaded != null and loaded.res == res
