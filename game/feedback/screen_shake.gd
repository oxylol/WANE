class_name ScreenShake
extends RefCounted
## Directional screen shake (BUILD.md section 6: "Shake is directional (along the hit) not
## random", "capped at 6 u", "a global scaler in settings"). Each shake swings the view back and
## forth along its direction, fading out over its frames; overlapping shakes add, and the total is
## capped. Stepped per simulation tick; the offset is applied to the drawn view only, never to
## the camera rig.

var tuning: FeedbackTuning
## The player's setting, 0..1 (defaults to the tuning's default).
var scale: float = 0.5

var _shakes: Array[Shake] = []


class Shake:
	var dir: Vector2 = Vector2.RIGHT
	var amplitude: float = 0.0
	var frames: int = 1
	var age: int = 0


func _init(p_tuning: FeedbackTuning) -> void:
	tuning = p_tuning
	scale = tuning.shake_default_scale


## Starts a shake of [param amplitude_u] (at 100%) for [param frames] ticks along [param dir].
func add(dir: Vector2, amplitude_u: float, frames: int) -> void:
	if amplitude_u <= 0.0 or frames <= 0:
		return
	var s := Shake.new()
	s.dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	s.amplitude = amplitude_u
	s.frames = frames
	_shakes.append(s)


func step() -> void:
	for s: Shake in _shakes:
		s.age += 1
	_shakes.assign(_shakes.filter(func(s: Shake) -> bool: return s.age < s.frames))


## The view offset this tick, in units.
func offset() -> Vector2:
	var total := Vector2.ZERO
	for s: Shake in _shakes:
		var fade: float = 1.0 - float(s.age) / float(s.frames)
		var swing: float = cos(TAU * float(s.age) / float(tuning.shake_period_frames))
		total += s.dir * s.amplitude * fade * fade * swing
	total *= scale
	return total.limit_length(tuning.shake_cap_u * scale)


func is_shaking() -> bool:
	return not _shakes.is_empty()
