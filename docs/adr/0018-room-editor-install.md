# ADR-0018: Install the room editor from addons/ with a shim, and keep its code in tools/

- Status: Accepted
- Date: 2026-10-19
- BUILD.md sections: 13 (layer 6, Tooling: "a room editor as a Godot editor plugin"; "Rooms are authored in the room editor plugin (`tools/room_editor/`) and stored as text"), 9 (rooms)
- Checklist lines: none directly; every room is authored in it

## Summary

- Godot loads plugins only from `res://addons/` and joins `plugin.cfg`'s `script=` onto that folder, so code in `tools/` cannot be named there.
- `addons/room_editor/` holds `plugin.cfg` and a `plugin.gd` that extends `RoomEditorPlugin`; the code stays in `tools/room_editor/` (see Decision).
- The plugin is enabled in `project.godot` (`editor_plugins/enabled`), so opening the project shows a "Rooms" main screen beside 2D, 3D and Script.
- Play saves the room and runs the main scene with `-- --room=<id>`; the run arguments are put back at once, so the project file never keeps them.
- Opening a room, doors, entities, resizing, saving and the problems list are `RoomDocument` and its two edit helpers, tested headless (see Consequences).
- A door to a room with no file yet is a note, not a problem, so two rooms that lead to each other can be written one after the other.
- Growing a room copies its edge row and column, so walls and door openings carry on; shrinking takes the rows inside the edge (see Resize).

## Context

CLAUDE.md puts the editor at `tools/room_editor/` and BUILD.md section 13 calls it "a Godot editor plugin". Godot only finds plugins under `res://addons/<name>/plugin.cfg`. The `script=` entry is resolved against the plugin's folder: `script="res://tools/room_editor/room_editor_plugin.gd"` was tried and Godot looked for `res://addons/room_editor/res:/tools/room_editor/room_editor_plugin.gd`. So the code cannot be named from `plugin.cfg` where it lives.

The editor also has to agree with the loader. ADR-0009 says "the editor writes this format and refuses rooms that fail validation"; ADR-0014 adds doors, whose strips, floors and pairs the loader checks, and the room joins of ADR-0008. A second copy of those rules in the editor would drift.

## Decision

**Install.** `addons/room_editor/plugin.cfg` names `plugin.gd`, which is `extends RoomEditorPlugin` (a `class_name` in `tools/room_editor/room_editor_plugin.gd`) and nothing else. Every other file is in `tools/room_editor/`: `RoomDocument` (tiles, spawn, size, undo, saving, problems), `RoomDoorEdits` and `RoomObjectEdits` (what `document.doors()` and `document.objects()` return), `RoomHistory`, `EntityKinds`, `RoomCanvas`, `RoomEditorPanel`, and `screenshot.gd` for a picture of the panel. The plugin is listed in `project.godot`.

**One source of truth for problems.** `RoomDocument.problems()` is, in this order: the errors of `RoomData.parse(text)` (format, tiles, `TileGrid.validate`, every door rule); `RoomJoins.errors` with the world tuning's band and reach; `RoomSet.check_doors` (the pairs against the rooms the doors lead to, read from their files); and what only the editor can see: a spawn outside the room or inside a wall, an entity outside the room, a dummy property the dummy does not read or a value it would ignore, a path that is not the id's. `save()` refuses while any exists (`ERR_INVALID_DATA`) and otherwise writes exactly `RoomData.to_text()`.

**Doors.** A new door has the target `?` `?` (a word the text format accepts, so undo's text snapshots keep it) and is a problem until set. A target room with no file yet is a note: the two rooms of a pair cannot both be saved first. Once the file exists, the pair is checked like the loader checks it. `RoomDoorEdits.carve` clears the strip and the two tiles beyond it and lays floor under a side door; the door tool draws a door and carves it as one undo step.

**Resize.** The new size keeps the side picked (right and down, left and up, or both). Growing copies the edge row or column, so a wall stays a wall and a door's opening stays open; shrinking removes the rows and columns just inside the edge, so the edge stays. Solids, entities, doors on the other sides and the spawn move with the content.

**Comments.** `RoomData` keeps the comments before the `room` line (`preamble_notes`), between it and the tiles, above each solid, door and entity, and at the end, and `to_text` writes them back. Every file under `content/rooms/` is written back byte for byte. Entity properties are written sorted, which is the only thing a first save changes in the rest (4 of the test rooms).

**Open rooms.** A room opened in the editor stays open, with its undo history and unsaved edits, when another is picked; the picker marks it.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Move the code to `addons/room_editor/` | The path CLAUDE.md and BUILD.md name is `tools/room_editor/`; the shim keeps the editor with the rest of the tooling |
| A symlink `addons/room_editor` to `tools/room_editor` | A symlink in git breaks on Windows checkouts without developer mode, and the importer treats the folder twice |
| `script=` with a `res://` path in `plugin.cfg` | Tried; Godot joins it onto the plugin's folder and the file is not found |
| Keep the editor's own validation | It would drift from `RoomData`, `RoomJoins` and `RoomSet`, which a run uses; one checker is the rule |
| Refuse a door to a room with no file | Two rooms that lead to each other could never be saved |
| Autosave when switching rooms | Writes a room with problems, or refuses and loses the switch; keeping the open copy loses nothing |

## Feel reason

None directly. The editor is how the 12 teaching rooms and every later room are built, and it refuses the joins, door strips and floors the physics (ADR-0008) and the doors (ADR-0014) depend on, so a room that plays wrongly because of its authoring is caught before it is played.

## Consequences

- `tests/unit/tools/test_room_document.gd` (format, tiles, problems, install), `test_room_edits.gd` (boxes, entities, doors, size), `test_room_editor_panel.gd` and `test_room_editor_doors.gd` (the panel and canvas driven as the mouse drives them, on a base suite `room_editor_suite.gd`). One test opens every room in the repository and checks it has no problems and saves as it is.
- A new `class_name` in `tools/room_editor/` needs `godot --headless --path . --import` once, like any.
- New entity kinds with properties are added to `EntityKinds`; any other kind is placed and saved with free `key=value` text.
- `RoomData` gained `preamble_notes` and `RoomData.Door.clear_u`; `RoomSet.check_doors` is the editor's entry to the pair checks. No simulation behaviour changed.
- Revisit when Godot lets `plugin.cfg` name a script outside its folder.
