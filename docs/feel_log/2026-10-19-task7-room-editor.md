# 2026-10-19: Phase 1 task 7, the room editor

- Author: Claude
- BUILD.md section and table row: section 13 (layer 6, Tooling: "a room editor as a Godot editor plugin"), section 9 (rooms), CLAUDE.md ("Rooms are authored in the room editor plugin (`tools/room_editor/`) and stored as text"); docs/adr/0009, 0014, 0015.
- Fixture(s): none; the editor is tested headless by `tests/unit/tools/test_room_document.gd`, `test_room_edits.gd`, `test_room_editor_panel.gd` and `test_room_editor_doors.gd`.
- Contact sheet: `docs/feel_log/2026-10-19-task7-room-editor.png`, the panel under xvfb (`tools/room_editor/screenshot.gd`) on `zone1/05_wall_kick_climb` with its right-hand door selected.

## Change

First implementation; no feel number was tuned. The editor's numbers are authoring defaults, not feel: a new room is 40 x 20 tiles inside a one-tile wall with a two-tile floor; a drawn door is at least 2 tiles long (`RoomData.DOOR_DEPTH_TILES`); boxes and entities snap to 16 u (half a tile); undo keeps 200 steps.

## Why

Zone 1's twelve rooms and every later room must be built by a tool that cannot save a room the game would refuse. The picture shows what the director sees: the tool and tile palettes on the left (a swatch for each of the 12 tile kinds, the pit included), the room in the middle drawn with the grey-box colours of the game, and on the right the selected door's name, side, opening in tiles and target, with the doors the target room has listed under it, so a pair can be written without opening the other room. Each door is drawn as its strip (teal; red when a problem names it) with the passage it opens beside the room's edge and a line saying where it leads; the selected door has yellow ends to drag. The problems list at the bottom is the loader's own list.

Read against the picture: the doors, strips and passages read at a glance; labels sit beside each strip, inward, so the spawn marker and a door label can touch in a small room (the spawn label is the one to move if it matters). The unchecked boxes of the entity form are faint in the game's default theme used for the picture; inside the Godot editor they take the editor's theme.

## How it plays now

What an author can do, each proved by a test:

- Open any room under `content/rooms/` (subfolders too) and `tests/replay/rooms/`, or create one by id (`zone1/r13`, `test/name`); rooms already open keep their unsaved edits and undo history when another is picked, and the picker marks them.
- Paint every tile kind (the 12 characters, the pit included) with the paint, rectangle and line tools; the right button erases.
- Draw solid boxes with a tag (`pogo`, `wax`) and the wall-cling off (`cling=0`); select, move, edit and delete them.
- Place, move and delete entities; the training dummy has a form for swings, red swing, light, ticks between swings, hit points, poise and facing, and a text field for any property.
- Set the spawn; resize the room from the right and down, the left and up, or both: growing copies the edge so walls and doors carry on.
- Draw a door by dragging along an edge (it is carved at once: strip and the two tiles beyond cleared, floor laid under a side door); slide it along its side, drag its ends, change its side, opening, name and target in the inspector, or delete it; every drag is one undo step.
- See every loader problem live: `RoomData` errors, `RoomJoins`, door pairs (`RoomSet.check_doors`) once the target room has a file; a door to a room with no file yet is a note. Save is disabled and refused (`ERR_INVALID_DATA`) while any problem stands.
- Save writes exactly what `RoomData.to_text` writes, comments included: every file under `content/rooms/` round-trips byte for byte (a test opens all 151 rooms in the repository); 4 test rooms change only by their entity properties being sorted.
- Play saves and runs `game/main.gd` with `-- --room=<id>`.

## Open questions for the director

- **Play inside the Godot editor.** The panel, the shim and the plugin's loading in the editor are checked headless and under xvfb; Play (`EditorInterface.play_main_scene` with `editor/run/main_run_args`) needs the real editor window, which this environment cannot open. Press Play on a zone 1 room once and say whether the game starts in it.
- **The door workflow.** Draw a door on the right of one room and on the left of the next; the second can be saved only after the first (the first says "no file yet" as a note). Say whether that order is natural or whether a "make the partner door" button is worth having.
