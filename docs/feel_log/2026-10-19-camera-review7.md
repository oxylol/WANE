# 2026-10-19: Camera review 7 (fall away, death cut, charge hold, shake margin, glide exit)

- Author: Claude
- BUILD.md section and table row: section 5 ("The camera never fights the player"), section 6 (Charged strike: 24 f charge, 3 f startup), section 15 ("never within 80 units of the screen edge")
- Fixture(s): `tests/replay/camera/cam7_*.fixture` (rooms `cam7_death_far`, `cam7_edge_dummy`), `tests/unit/game/test_camera_review_round7.gd`
- Contact sheet: `docs/feel_log/2026-10-19-camera-review7-fall-away.png` (`cam7_cling_walljump_fast`, frames 58 to 79 every 3, overlay on: the track at the right shows the view's path leaving the fall instead of climbing it; at this scale the sheet is small, the numbers below are the measure)

## Change

No tuned number in `content/camera.tres` changed. Five rule fixes:

| Rule | Before | After | Unit |
| --- | --- | --- | --- |
| View rise while Ash falls away from the last support (cling wall-jump, climb let-go, hop off a ledge) | 54 to 60 (committed `cam5_wall_jump_long_drift` 34) | under 32 (the rise only shrinks, then holds) | u of travel against the fall |
| Death by an enemy's hit | view tracked the jump, backstop moved it, frame interpolated across 252 to 871 u, drift up to 478 u | view and drawn player cut with Ash | u |
| Look-down during a held Charged strike, crouched, stick down | 200 u (view 190 u down) | 0 | u |
| Drawn gap to the view's edge through a shake at a borderless edge | 77.75 (100%), 78.88 (50%) | 80.00 | u |
| View speed change on the tick after a glide ends | up to 3.30 | at most 3.00 | u/f |

## Why

H1: above the last support only the follow's lerp acted, so any fall away from the support (off the far side of a ledge, off a climb, after a wall-jump) was chased upward for 10 to 18 ticks, then stopped dead. The suite's hop exemption was wider than its reason and hid it. A hop toward the support is now told from a fall away by the ground the fall lands on (`CameraSubject.ground_below`, steering envelope included): at the support or higher is a hop, lower is a fall away. The ease pauses and the rise only shrinks for the latter. `CameraRun.longest_run_against` exempts only the former.
H2: a death emits `SimEvents.DEATH` with no hazard event; it now cuts as a hazard respawn does, in the rig and in `PlayerView`.
H3: the charge hold has no action, so the subject counted it as not fighting; `charge_held` and `charge_request` now count as fighting.
M1: `GameCamera.apply_shake` cuts the shake per axis to the slack the follow leaves between Ash and the 80 u margin.
L1: `gliding()` is true on the glide's last moving tick, and the follow's first tick after starts from the view's own speed on it. The suites now check 3 u/f outside a glide tick and 5 on one (round 6 had used 5 everywhere).

## Camera paths moved (per tick, 16:9, all 392 fixtures in movement, tech, physics, camera, doors, combat compared before and after)

The core is untouched: sim state, golden hashes and `Simulation.VERSION` are unchanged, nothing to re-bless. Fixtures whose camera path moved, and why:

- Fall away from the support (H1, intended, up to 56 u, a fall the view used to chase): `cam5_wall_jump_long_drift`, `cam5_climb_drop`, `cam5_climb_drop_buffered_jump`, `cam5_borderless_top_up_dash`, `cam_air_spikes_pogo`, `cam_fall_airjump`, `cam_look_then_updash`, `cam_updash`, `cam_shaft_wide_jumps`, `cam_wide_shaft_jumps`, `cam_double_jump_ledge`, `cam_double_jump_in_place`, `cam_jumps_flat`, `cam_pogo_shelf`, `cam_fall_updash`, `cam_box_66x60_roam` (13.6 u), and the new `cam7_cling_walljump_fast`, `cam7_climb_letgo`, `cam7_step_up_hop_off`.
- Sub-unit differences (at most 0.7 u, from the first tick after a glide or the ease pause): `cam_box_*_roam` (the others), `cam_noceiling_climb`, `cam_shaft_wall_jumps`, `movement/dash_on_cling_frame_goes_away`, `wall_coyote`, `wall_jump`, `wall_kick_neutral`, `wall_spent_still_kicks`, `tech/tech06_wall_jump_dash`, and `cam7_tp_up_updash` (L1, 0.05 u).
- Death cut (H2) and charge hold (H3): the new `cam7_death_far` (418 u) and `cam7_crouch_charge` (200 u). No committed fixture moved for them.

## How it plays now

A fall never pulls the view up; a death snaps the view home with Ash; holding a charge crouched does not drop the view; a hit at a room's edge shakes the frame without drawing Ash nearer than 80 u.

## Open questions for the director

Play a wall-jump off a long fall and a hop off a ledge: the view should settle and then follow the fall down. Die to a red dummy far from the spawn: the cut is instant (the fade of task 6 is still to come).
