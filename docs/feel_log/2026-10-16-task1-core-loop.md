# 2026-10-16: Phase 1 task 1, the core loop, input and replays

- Author: Claude
- BUILD.md section and table row: s5 feel rules ("Input is read every frame, before physics, and acted on the same frame"; "Buffers are generous (8 f) and the buffer always stores the latest input"); s6 hit feedback ("Hitstop is never applied to the player's own input reading"); s13 Layers 1 and 2, Determinism and replays
- Fixture(s): `tests/replay/core/input_buffer_latest_press.fixture`, `tests/replay/core/subframe_tap_is_kept.fixture`
- Contact sheet: none. Nothing is drawn yet; the replay player with the F3 overlay (task 5) takes contact sheets from task 3 on

## Change

No movement or combat number changed: this task builds the loop the numbers will run in. Two input values are set for the first time, both input-layer feel values, not BUILD.md table rows:

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Input buffer depth | none | current frame plus 8 frames of history | player frames |
| Stick quantisation step | none | 8 (with one step of hysteresis) | 1/127 of full deflection |
| Stick dead-zone release | none | 10 (the stick leaves the dead zone at BUILD.md's 12%) | percent of full deflection |

## Why

- **Buffer depth.** BUILD.md says "8 f". Checklist line 1 requires a jump pressed 8 frames before landing to fire on the landing frame, which is a press 8 frames old: the ring must hold the current frame plus 8 behind it (ADR-0004).
- **Latest press only.** Using a press spends every older press of that button, so two quick taps in the air cannot fire a landing jump and then a stray double jump.
- **Hitstop.** Presses during hitstop fold into the frame the player is frozen on, so they fire on the first free frame (1 frame old). A press made during hitstop of a button already used on the hit frame still counts (the independent review found this case dropped; fixed and tested).
- **Triggers.** A held analog trigger presses once. Godot reports every trigger event above its threshold as "pressed", which would have re-fired dash on every cooldown.
- **Stick.** Quantising to steps of 8 with hysteresis keeps sensor noise out of the simulation. It does not affect Ash, whose stick is read as eight directions. It keeps replays of analog play under BUILD.md's 2 KB a minute (measured: under 2048 bytes for a minute of continuously moving, noisy stick). The quantiser must not move BUILD.md's dead zones: the first version registered the stick only at 17.3% raw and read full from 92.4%; it now registers at 12% and reads full at 95%, as section 12 says. Noise on the axis a sideways stick is not pushing no longer flips that axis between +8 and -8 (a band around zero), and a stick resting right on the 12% edge no longer flickers in and out: once out, it stays out until 10%.
- **Latency.** The fixed-step driver steps each tick at the start of its period, so at 60 Hz the frame shows the state that frame's input produced, with no frame of interpolation lag (ADR-0007). The third review found that one late frame (a compositor hiccup) shifted the tick phase for good, so every later frame drew the previous tick: a full frame of added latency until restart. The fourth review then found that deciding to snap frame by frame made variable-refresh displays judder. The driver now locks to a fixed-refresh display after two seconds of vsync-like frames and counts every frame there in whole ticks; anything else is counted exactly and interpolated.
- **Stuck buttons.** A release the layer never saw (released while paused, or consumed by another node) left the button held, and the next press was eaten. Every poll now reads the buttons from the devices, and a button pressed in a pause menu does not jump on resume.

## How it plays now

Nothing to play: the game boots to an empty simulation that records a replay of the session to `user://replays/last_session.wrp`.

## Open questions for the director

None.
