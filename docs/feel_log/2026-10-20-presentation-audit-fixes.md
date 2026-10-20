# 2026-10-20: Presentation audit fixes (door spike, tunables in content, effects through the budget, stress sheet)

- Author: Claude
- BUILD.md section and table row: section 13, Testing and CI ("no frame-time spike above 20 ms"), Frame budget; section 10, VFX ("enforced by a VFX budget manager"); CLAUDE.md rules 6 and 7
- Fixture(s): none moved (no golden changed, `Simulation.VERSION` the same); `tests/perf/stress_run.fixture` for the sheet
- Contact sheet: `docs/feel_log/2026-10-20-stress-readable.png` (the stress run at Pitch, ticks 468, 470, 472, F3 on, zoom 3)

## Change

No feel number changed. Four things changed in how the presentation is built.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| First crossing into each zone 1 room at Pitch (least of 3 boots, worst room / best room) | 11.54 / 4.04 | 0.38 / 0.08 | ms |
| Boot of the lit scene (every reachable room's walls built once) | 27 | 94 | ms |
| Door crossing gate (`door_max_us`, new) | none | 2.0 | ms |
| Presentation script p99 in the frame bench (gate 5.0) | 3.65 | 3.90 | ms |
| Most effects alive in the VFX budget in the stress run | 18 | 32 | effects |

## Why

1. **The door spike.** The lighting stand-in freed and rebuilt every wall occluder on the tick of the room event. It is now built once per room, hidden, ahead of the crossing; a crossing shows one node and hides another (ADR-0020 Decision 19). `tools/bench/door_bench.gd` measures it in `ci/perf.sh`.
2. **Rule 6.** The spark and burst sizes, the HUD's layout, the VFX shapes' geometry, the combat view's blade, glow and channel, the action dead zone of the input layer and the grey-box player's eye and ember are now fields of `content/feedback.tres`, `content/input/input_settings.tres` and `content/player_view.tres`, each with a `validate()` rule. Every value is the literal it replaced, so nothing looks different (colours stay constants: they are stand-in art for Phase 2).
3. **Rule 7.** Kindle's cone, the Blaze trails, the kill embers, the Charged glow and Mend's channel are spawned into the VFX budget each tick (`VfxBudget.spawn_rect`, kinds `AREA` and `OUTLINE`, and `EMBER`), at priorities that cannot push out a hit; 200 kills at once are capped by the budget's capacity (`tests/unit/game/test_combat_presentation.gd`). The cost is that they are drawn at their tick positions and not interpolated between ticks (ADR-0013).
4. **The stress sheet.** The F3 overlay now draws the labels nearest the camera first and skips any whose text would overlap one already drawn (`DebugOverlay.readable_labels`), so 200 enemies are a few legible labels, and the new sheet is at zoom 3 so Ash is a figure and not a speck. At 3x the overlay's 18 px text is big against the world; at 1x it fits.

## How it plays now

Nothing a player feels changed, except that a door is no longer the frame most likely to hitch at Pitch.

## Open questions for the director

Look at `2026-10-20-stress-readable.png`: is the strike's box and the telegraph readable at this zoom? The 30-Votive readability judgement still belongs to the Phase 2 lighting and art.
