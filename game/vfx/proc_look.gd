class_name ProcLook
extends Resource
## How one Votive's proc shows: a grey-box shape, a colour, a size and a lifetime under ten frames
## (BUILD.md section 10, VFX language: "Every proc has a short, distinct, sub-10-frame VFX";
## docs/adr/0015). A placeholder until Phase 2's authored proc VFX; never called art.

## Shapes drawn by [VfxBudget] for a proc, each expanding and fading over its frames.
enum Shape { RING, CROSS, DIAMOND, SPOKES, SQUARE, TRIANGLE, CHEVRON, STAR }

const SHAPE_NAMES: Array[String] = [
	"ring", "cross", "diamond", "spokes", "square", "triangle", "chevron", "star"
]
## "sub-10-frame".
const MAX_FRAMES: int = 9

## The Votive it shows ([member Votive.id]).
@export var votive_id: String = ""
@export var shape: Shape = Shape.RING
@export var colour: Color = Color.WHITE
## Its reach at full size, world units.
@export var size_u: int = 24
@export var frames: int = 8


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if frames < 1 or frames > MAX_FRAMES:
		e.append("%s: a proc's effect lasts 1 to %d frames" % [votive_id, MAX_FRAMES])
	if size_u <= 0:
		e.append("%s: a proc's effect needs a size" % votive_id)
	if shape < 0 or shape >= SHAPE_NAMES.size():
		e.append("%s: unknown shape %d" % [votive_id, shape])
	return e
