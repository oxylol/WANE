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

var _panel: RoomEditorPanel


func _enter_tree() -> void:
	_panel = RoomEditorPanel.new()
	_panel.name = "Rooms"
	_panel.build()
	_panel.play_requested.connect(_on_play)
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_make_visible(false)


func _exit_tree() -> void:
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


## Runs the main scene with `-- --room=<id>`, then puts the run arguments back, so the project
## file never keeps them.
func _on_play(room_id: String) -> void:
	var before: Variant = ProjectSettings.get_setting(RUN_ARGS_KEY, "")
	ProjectSettings.set_setting(RUN_ARGS_KEY, "-- --room=%s" % room_id)
	EditorInterface.play_main_scene()
	ProjectSettings.set_setting(RUN_ARGS_KEY, before)
