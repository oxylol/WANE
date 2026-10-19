# tools/

Tooling (BUILD.md section 13, layer 6): CI entry points (`ci/`), the replay recorder, player and fixture runner (`replay/`), the F3 debug overlay and frame-stepper (`debug/`), the room editor (`room_editor/`), importers, the style gate, and the art and audio builds (Phase 2). Python dependencies are pinned in `requirements.txt`.

## Room editor

`room_editor/` is the room editor plugin (docs/adr/0015); Godot finds it through `addons/room_editor/`, enabled in `project.godot`. Open the project in the editor and pick the "Rooms" screen. Its picture, to look at the panel on a room: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1700x900 --script tools/room_editor/screenshot.gd -- out.png zone1/05_wall_kick_climb door east` (the last words: `door <name>`, `dummy` or `solid` select something to show its inspector).
