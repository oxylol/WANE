class_name RoomEditorSuite
extends GdUnitTestSuite
## The base of the room editor's panel suites (Phase 1 task 7; docs/adr/0015): a panel in the
## tree and the ways the mouse and the palette drive it, and a clean-up of the scratch rooms the
## suites save.

const A_ID: String = "test/ed_scratch/a"
const B_ID: String = "test/ed_scratch/b"
const T: int = TileGrid.TILE

var _panel: RoomEditorPanel


func before_test() -> void:
	_panel = auto_free(RoomEditorPanel.new())
	_panel.size = Vector2(1600, 900)
	add_child(_panel)
	_panel.build()


func after_test() -> void:
	var dir: String = ProjectSettings.globalize_path(RoomData.TEST_ROOT + "ed_scratch")
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)


func _tool(tool: int) -> void:
	_panel.tool_list.item_selected.emit(RoomEditorPanel.TOOL_NAMES.keys().find(tool))


func _tile(tile: int) -> void:
	_panel.tile_list.item_selected.emit(RoomEditorPanel.TILE_NAMES.keys().find(tile))


## A press, a move and a release with the left button, at room units.
func _drag(from: Vector2, to: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var canvas: RoomCanvas = _panel.canvas
	canvas.press(button, from)
	canvas.drag_to(to)
	canvas.release(button, to)
	_panel.refresh()


func _click(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_drag(at, at, button)


func _centre(i: int, j: int) -> Vector2:
	return (Vector2(i, j) + Vector2(0.5, 0.5)) * T


func _doc() -> RoomDocument:
	return _panel.document


## The problems of the open room other than doors that have no target yet.
func _real() -> PackedStringArray:
	var out: PackedStringArray = []
	for p: String in _doc().problems():
		if not p.contains("has no target yet"):
			out.append(p)
	return out
