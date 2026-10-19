class_name Voices
extends Node2D
## The audio priority system (CLAUDE.md rule 7: "nothing is heard without the audio priority
## system"; BUILD.md section 11: "Hard cap of 24 simultaneous voices; a priority system drops the
## furthest, quietest sound first"). Every sound plays through [method play] on one of a fixed
## pool of positional voices. When all are busy, the new sound takes the voice of the least
## important sound playing (lowest priority, then furthest from the listener, then quietest), or
## is dropped if every sound playing matters at least as much.

## Priorities, low to high.
enum { AMBIENT, PROC, HIT, TELEGRAPH, PLAYER }

var tuning: FeedbackTuning
## Where the listener is (the camera's centre), for "furthest".
var listener: Vector2 = Vector2.ZERO
## Sounds dropped or cut since the start (for the F3 overlay).
var dropped: int = 0
var stolen: int = 0

var _players: Array[AudioStreamPlayer2D] = []
var _priority: PackedInt32Array = PackedInt32Array()


func _init(p_tuning: FeedbackTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else load(FeedbackTuning.PATH) as FeedbackTuning


func _ready() -> void:
	for i: int in range(tuning.voice_cap):
		var p := AudioStreamPlayer2D.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)
	_priority.resize(tuning.voice_cap)


## Plays [param stream] at [param at] with [param priority]; false if it was dropped.
func play(
	stream: AudioStream, at: Vector2, priority: int, volume_db: float = 0.0, pitch: float = 1.0
) -> bool:
	var slot: int = _free_voice()
	if slot < 0:
		slot = _least_important(priority, at, volume_db)
		if slot < 0:
			dropped += 1
			return false
		stolen += 1
		_players[slot].stop()
	var p: AudioStreamPlayer2D = _players[slot]
	p.stream = stream
	p.position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch
	_priority[slot] = priority
	p.play()
	return true


func playing_count() -> int:
	var n: int = 0
	for p: AudioStreamPlayer2D in _players:
		if p.playing:
			n += 1
	return n


func _free_voice() -> int:
	for i: int in range(_players.size()):
		if not _players[i].playing:
			return i
	return -1


## The voice to cut for a sound of [param priority] at [param at]: among the sounds less
## important, or as important but further away, the lowest priority, then the furthest, then
## the quietest. -1 if the new sound is the least important of all.
func _least_important(priority: int, at: Vector2, volume_db: float) -> int:
	var best: int = -1
	var new_distance: float = at.distance_to(listener)
	for i: int in range(_players.size()):
		if not _outranked(i, priority, new_distance, volume_db):
			continue
		if best < 0 or _ranks_below(i, best):
			best = i
	return best


## True if the sound on voice [param i] matters less than a new one.
func _outranked(i: int, priority: int, distance: float, volume_db: float) -> bool:
	if _priority[i] != priority:
		return _priority[i] < priority
	var d: float = _players[i].position.distance_to(listener)
	if not is_equal_approx(d, distance):
		return d > distance
	return _players[i].volume_db < volume_db


## True if voice [param a] should be cut before voice [param b].
func _ranks_below(a: int, b: int) -> bool:
	if _priority[a] != _priority[b]:
		return _priority[a] < _priority[b]
	var da: float = _players[a].position.distance_to(listener)
	var db: float = _players[b].position.distance_to(listener)
	if not is_equal_approx(da, db):
		return da > db
	return _players[a].volume_db < _players[b].volume_db
