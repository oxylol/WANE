@tool
class_name RoomEditorPlugin
extends EditorPlugin
## The room editor plugin (CLAUDE.md: "Rooms are authored in the room editor plugin
## (`tools/room_editor/`)"). Adds a "Rooms" main screen with the [RoomEditorPanel]. Play runs
## the game in the edited room by passing `--room=<id>` to the main scene (game/main.gd).
##
## Godot loads plugins only from res://addons/, so addons/room_editor/ holds the plugin.cfg and a
## one-line script that extends this class; everything else lives here (docs/adr/0015).

const RUN_ARGS_KEY: String = "editor/run/main_run_args"

## The most frames to wait for the game to start before the run arguments are put back anyway.
const WAIT_FRAMES: int = 600

var _panel: RoomEditorPanel
var _args_before: Variant = ""
var _waiting: bool = false
var _waited: int = 0


func _enter_tree() -> void:
	_panel = RoomEditorPanel.new()
	_panel.name = "Rooms"
	_panel.build()
	_panel.play_requested.connect(_on_play)
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_make_visible(false)
	set_process(false)


func _exit_tree() -> void:
	_restore_args()
	if _panel != null:
		_panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible


func _get_plugin_name() -> String:
	return "Rooms"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMap", "EditorIcons")


## Runs the main scene with `-- --room=<id>`. The run arguments are put back once the game is
## running (or [constant WAIT_FRAMES] frames have passed), not straight after the call, so a launch
## the editor defers still reads them; the project file never keeps them.
func _on_play(room_id: String) -> void:
	if not _waiting:
		_args_before = ProjectSettings.get_setting(RUN_ARGS_KEY, "")
	ProjectSettings.set_setting(RUN_ARGS_KEY, "-- --room=%s" % room_id)
	_waiting = true
	_waited = 0
	set_process(true)
	EditorInterface.play_main_scene()


func _process(_delta: float) -> void:
	_waited += 1
	if EditorInterface.is_playing_scene() or _waited >= WAIT_FRAMES:
		_restore_args()


func _restore_args() -> void:
	if _waiting:
		ProjectSettings.set_setting(RUN_ARGS_KEY, _args_before)
	_waiting = false
	set_process(false)
