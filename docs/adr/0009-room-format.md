# ADR-0009: Rooms are text files of tiles, solid boxes and entity markers

- Status: Accepted
- Date: 2026-10-17
- BUILD.md sections: 9 (rooms, zones), 13 ("Room templates and handcrafted vistas"; content as data), CLAUDE.md "Rooms are authored in the room editor plugin (`tools/room_editor/`) and stored as text"
- Checklist lines: none directly; every movement fixture runs in a room

## Context

CLAUDE.md requires rooms authored in an editor plugin and stored as text, so that an agent can read and diff them and replays can name them. The physics (ADR-0008) needs a tile grid plus rectangles for things that change (doors, wax walls), and the simulation needs a spawn point and entity markers. Task 3 needs rooms before the editor exists (task 7).

## Decision

A room is a `.room` text file, parsed by `core/rooms/room_data.gd`:

```
room <id>                          # must match the file's path: content/rooms/<id>.room, or
                                   # tests/replay/rooms/<name>.room for id "test/<name>"
size <width> <height>              # in tiles (32 u); must match the tile block
spawn <x> <y>                      # default player spawn, bottom-centre in units
tiles
<one character per tile, a row per line>
end
solid <left> <top> <right> <bottom> [tag=<word>] [cling=0]   # a SolidBox, in units
entity <kind> <x> <y> [key=value]...                         # a marker for later systems
door <name> <left|right|top|bottom> <from> <to> <room> <door> # an opening to another room
```

Doors, how the player crosses them and what a run keeps are ADR-0014.

- Tile characters (`TileGrid.CHARS`):
  - `.` empty, `#` solid, `S` smooth (solid, not clingable), `=` one-way, `^` spikes, `~` a pit (a hazard filling the tile, nothing to pogo off: movement review 5, H1);
  - `/` and `\` 45-degree slopes rising right and left;
  - `a` `b` a 1:2 slope rising right (low half, then high half), `c` `d` one rising left (high half, then low half).
- A `#` starts a comment anywhere outside the tile block. Outside the grid is solid.
- **Validation**:
  - Loading collects every problem in `RoomData.errors`: unknown directives and characters, sizes that disagree, a missing id, an id that does not match the path, and every rule in `TileGrid.validate()` (ADR-0008: slopes rest on walls, and their raised sides meet walls or matching slopes).
  - A `Simulation` built from a room with errors reports them in `load_errors`, and the fixture runner fails on them.
- **Solid tags**:
  - `tag=pogo` marks a pogo-able object (a bell);
  - `tag=wax` marks a wall that a kindle-dash ignites;
  - `cling=0` makes a solid smooth to the wall-cling.
- **Determinism**:
  - A room's text is part of the content hash (`ContentHash.add_room`), so a replay recorded against a different room reports "recorded with different content" instead of desyncing.
  - The simulation copies the room's solids into its world, so breaking one never changes the room.
- `RoomData.to_text()` is the inverse of `parse()`, for the room editor (task 7).

## Alternatives considered

| Option | Why not |
| --- | --- |
| Godot TileMap scenes (`.tscn`) | The core must not depend on nodes (CLAUDE.md rule 1); TileMap data in a scene is a binary-ish blob, hard to read and diff |
| JSON | Readable but noisy for a grid; the tile block is a picture of the room in text form |
| Godot `Resource` with a packed array | Still unreadable in diffs, and the editor plugin can write plain text just as easily |

## Feel reason

Rooms are where the movement is taught (the 12 tech interactions). Being able to read a room as a picture in a diff makes it easy to review that a gap is "exactly one dash-jump wide".

## Consequences

- Test rooms live in `tests/replay/rooms/`, game rooms in `content/rooms/`.
- Task 7's editor writes this format and refuses rooms that fail validation.
- Entities are parsed but not yet simulated; task 6 (training dummy) and later enemy work give them meaning.
