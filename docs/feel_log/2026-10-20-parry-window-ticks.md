# 2026-10-20: The parry window is 8 ticks when the press connects; dash-jump audit notes

- Author: Claude
- BUILD.md section and table row: section 6, Parry ("Press attack in the 8 f before an enemy's hit lands ... the 8 frames that end on the frame it lands"); section 5, Dash, "Dash-jump" and Air control
- Fixture(s): `tests/replay/combat/parry_window_connecting_first_frame`, `_last_frame`, `_too_early`, `_too_early_9`, `_too_late`; `tests/replay/movement/dash_jump_released_stick_decays`, `dash_jump_early_press_waits_for_frame_5`, `dash_jump_press_on_dash_frame_1_waits`
- Contact sheet: `docs/feel_log/2026-10-20-parry-window-ticks.png` (`parry_window_connecting_too_early`: the press 8 frames before the landing strikes the dummy, the swing hits, hearts 5 to 4, the red hit vignette on the landing frame)

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Parry window when the press connects with the telegraphing enemy | 10 | 8 | ticks |
| Parry window when the press does not connect | 8 | 8 | ticks |
| `parry_window_frames` | 8 | 8 | frames (now counted in world ticks) |
| `Simulation.VERSION` | 11 | 12 | |

Dash-jump (no number changed): a released stick decays the kept speed (documented, fixture); an early press waits for dash frame 5 (documented, fixtures).

## Why

The ring counts player frames, and a player frozen in hitstop does not advance them. Pressing attack at a telegraphing dummy made the strike connect 3 frames later and freeze Ash for 2 f, so on the landing tick the press looked 2 frames younger: presses 9 and 10 frames early parried. "The 8 frames that end on the frame it lands" are the world's frames. The ring now stamps each press with its tick and the parry reads ticks. The contact sheet shows the edge case: the press 8 ticks early no longer parries and the swing hits.

Per-tick state of every committed fixture was compared before re-blessing, with the new stamps left out of the hash: nothing moved. Only the hash changed (the stamps are ring state), hence VERSION 12 and a full re-bless.

The two dash-jump audit entries are not defects. BUILD.md "keeps 100% dash speed" is the conversion at the jump and the hold while the stick holds forward (ADR-0010); a released stick gets ordinary air deceleration, as in any jump. A jump pressed on dash frames 2 to 4 waits in the 8 f buffer for frame 5, the first frame of the spec's window, and is never eaten.

## How it plays now

Pressing at the dummy 8 or more frames early is a mistimed parry on purpose: the swing hits. The same press at 1 to 7 frames before, or on the landing frame, parries, whichever way Ash faces.

## Open questions for the director

Play a dash-jump with the jump pressed at the same time as the dash, or on its second to fourth frame: the jump comes out up to 4 frames after the press. If that feels late, the lever is `dash_jump_first` in `content/wicks/ash/movement.tres` (BUILD.md would change with it). Also, releasing the stick on a dash-jump sheds the speed over about 22 frames; say if you want it to carry.
