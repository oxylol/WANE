class_name RoomHistory
extends RefCounted
## The room editor's undo and redo: whole-room text snapshots (rooms are a few kilobytes), one
## per edit, or one per drag between [method begin_stroke] and [method end_stroke].

## The most undo steps kept.
const DEPTH: int = 200

var _undo: Array[String] = []
var _redo: Array[String] = []
var _stroke: bool = false
var _stroke_saved: bool = false


## Starts a drag: the edits until [method end_stroke] undo together.
func begin_stroke() -> void:
	_stroke = true
	_stroke_saved = false


func end_stroke() -> void:
	_stroke = false


## Records [param before] (the room's text before an edit), once per stroke.
func record(before: String) -> void:
	if _stroke and _stroke_saved:
		return
	_stroke_saved = true
	_undo.append(before)
	if _undo.size() > DEPTH:
		_undo.pop_front()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## The text to restore for an undo, given the [param current] text; "" if there is none.
func undo(current: String) -> String:
	if _undo.is_empty():
		return ""
	_redo.append(current)
	return _undo.pop_back()


func redo(current: String) -> String:
	if _redo.is_empty():
		return ""
	_undo.append(current)
	return _redo.pop_back()
