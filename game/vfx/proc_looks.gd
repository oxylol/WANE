class_name ProcLooks
extends Resource
## Every content Votive's proc look ([ProcLook]; docs/adr/0015), kept with the presentation's
## tuning rather than in the Votive's own resource: how a proc shows is not part of the simulation,
## so changing it never changes the content fingerprint a replay is checked against (as
## content/feedback.tres sits beside content/combat/combat.tres). Adding a Votive that can proc (one
## listening to "hit" or "bounce") adds its look here; validation refuses such a content Votive
## without one, a look for anything else, and two Votives that look alike. A Votive with no look (a
## test Votive) is shown by its slot in the run: a shape and a colour from the fallbacks, distinct
## for every Votive of one run.

const PATH: String = "res://content/votive_looks.tres"

@export var looks: Array[ProcLook] = []
@export_group("Fallback")
## For a Votive without a look: its slot picks the shape (slot modulo the shapes) and the colour
## (slot divided by the shapes, modulo these colours).
@export var fallback_colours: Array[Color] = [Color(0.8, 0.8, 0.8)]
@export var fallback_size_u: int = 20
@export var fallback_frames: int = 6

var _fallback: ProcLook = ProcLook.new()


## The look of [param votive_id], or the fallback for its [param slot] in the run.
func look_for(votive_id: String, slot: int) -> ProcLook:
	for look: ProcLook in looks:
		if look.votive_id == votive_id:
			return look
	var shapes: int = ProcLook.SHAPE_NAMES.size()
	_fallback.votive_id = votive_id
	_fallback.shape = (slot % shapes) as ProcLook.Shape
	_fallback.colour = fallback_colours[(slot / shapes) % fallback_colours.size()]
	_fallback.size_u = fallback_size_u
	_fallback.frames = fallback_frames
	return _fallback


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	var ids: PackedStringArray = []
	var seen: Dictionary[String, String] = {}
	for look: ProcLook in looks:
		e.append_array(look.validate())
		if ids.has(look.votive_id):
			e.append("%s has two looks" % look.votive_id)
		ids.append(look.votive_id)
		var key: String = "%d %s" % [look.shape, look.colour.to_html(false)]
		if seen.has(key):
			e.append("%s looks like %s (same shape and colour)" % [look.votive_id, seen[key]])
		seen[key] = look.votive_id
	var content: PackedStringArray = content_proc_ids()
	for votive_id: String in content:
		if not ids.has(votive_id):
			e.append("content Votive %s procs but has no proc look" % votive_id)
	for votive_id: String in ids:
		if not content.has(votive_id):
			e.append("a look for %s, which is no content Votive that procs" % votive_id)
	if fallback_colours.is_empty():
		e.append("the fallback needs at least one colour")
	if fallback_frames < 1 or fallback_frames > ProcLook.MAX_FRAMES or fallback_size_u <= 0:
		e.append("the fallback lasts 1 to %d frames and has a size" % ProcLook.MAX_FRAMES)
	return e


## The id of every Votive under content/votives/ that can show a proc: one listening to "hit" or
## "bounce".
static func content_proc_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	var files: PackedStringArray = DirAccess.get_files_at(Votive.CONTENT_ROOT)
	files.sort()
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var votive: Votive = load(Votive.CONTENT_ROOT + file) as Votive
		if votive != null and (votive.hears("hit") or votive.hears("bounce")):
			out.append(votive.id)
	return out
