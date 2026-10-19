# 2026-10-19: Merge of the engine work (core review 2, physics 8, camera 7, presentation, procs)

- Author: Claude
- BUILD.md section and table row: section 5 (Taper side 1 recoil), section 6 (hit feedback), section 8 (Votives, Bell of the Vigil)
- Fixture(s): `tests/replay/procs/bell_stun_takes_the_swing.fixture`, `tests/replay/procs/bell_stun_takes_the_swing_control.fixture`
- Contact sheet: none; no number changed (the merge only joins five branches that all branched from 7d623fb)

## Change

Five branches merged in order: 503c5b5 (movement and combat review fixes, Simulation.VERSION 10), 3f3d7db (physics review 8), aecf859 (camera review 7), 86c934c (presentation fixes of tasks 5 and 6), 8b0e6c1 (proc event bus and Votives, ADR-0015, VERSION 9). Simulation.VERSION is 11: both the review fixes and the procs moved the state hash (`charge_broken` on one side, `dash_free` on the other; the hash now holds both). Every golden hash was re-blessed once, after the merge.

Textual conflicts only: `golden_hashes.txt` (re-blessed), `vfx_budget.gd` (the budget keeps `lifetime(kind)` and takes the proc mark's own `life`; `PROC_MARK` lives `ProcLook.MAX_FRAMES`), `hit_feedback.gd` (the player's origin for the smear and the per-hit proc groups), `debug_boxes.gd` and `debug_overlay.gd` (BURST and PROC both), `run_tests.gd` (`--unit-time-limit` and the 2400 s limit of an instrumented run: the larger of the two applies there), the replay README (the fixture keys of both).

Death by an enemy's hit sends `SimEvents.DEATH`; one rule for it on each side of the line: the camera cuts on it (`CameraSubject.respawned`, camera review 7) and the drawn player does not slide (`PlayerView`, task 5 review 3). Both were already in the merged result, so nothing was added.

`core/fsm/player.gd` was 1004 lines after the merge (cap 1000): the horizontal speed (ground and air speed, the knockback hold, the turnaround) moved to `PlayerSpeed` (`core/fsm/player_speed.gd`), as earlier fixes moved PlayerContacts and PlayerCombat. No behaviour moved; it is 954 lines now.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Simulation.VERSION | 10 / 9 | 11 | version |
| Fixtures whose expectations moved | 0 | 2 (one input line each) | fixtures |

## Why

Of 466 fixtures, 465 passed on the merged code with their expectations untouched (the golden hashes only differed by the version). One interaction moved: in `bell_stun_takes_the_swing_control` the player struck on frame 40 and stood still, and the dummy's swing on frame 53 was expected to cost a heart. With the side 1 recoil (60 u/s for 8 f, ADR-0013, from the core fixes) Ash now stands at 192 u instead of 200 u when the swing lands, outside its reach: before 200.00 u, after 192.00 u on frame 53. The recoil is documented behaviour, so the expectation moved, not the code. The fixture now holds right from frame 43 (the recoil rides under a held stick), which keeps Ash in reach: the control's swing lands on frame 53 as before. `bell_stun_takes_the_swing` held the same input, since without it the line "nothing hits Ash" would hold vacuously (Ash is out of reach whether or not the Bell stuns); with it, the line is only true because the Bell removed the swing.

## How it plays now

The Bell still stops a swing that was promised (the fixture proves it with Ash in reach), and a strike backs Ash off 8 u when nothing is held.

## Open questions for the director

None from the merge. Still open from the core fixes: the side 1 recoil's 8 u is small (`recoil_frames` in `content/combat/combat.tres`).
