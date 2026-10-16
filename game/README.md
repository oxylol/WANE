# game/: presentation

The Godot scene tree as a view of the core (BUILD.md section 13, layer 4). It reads core state snapshots and draws them; it never decides anything that a replay would need. Floats live here, not in `core/`. Rendering interpolates between the last two simulation states.

`game/input/` is BUILD.md's input layer (section 13, layer 1). It lives under `game/` because it reads Godot's `Input` singleton, which the core may not touch: it polls devices every frame, applies remapping and dead zones (nowhere else), and hands the core one `InputFrame` per tick.
