# 2026-10-20: Grey-box solid boxes coloured by function

Phase 1, director feedback after playing zone 1 ("what are the purple walls"). BUILD.md section 10, "Light is information"; the grey boxes are Phase 1 stand-ins, not art.

## Before, after, why

| Number | Before | After | Why |
| --- | --- | --- | --- |
| every solid box (`RoomView.BOX`) | (0.44, 0.40, 0.50), one colour for all | removed; boxes are drawn by tag from `content/feedback.tres` | the director could not tell a wax screen from a bell from a wall: every box was the same purple-grey |
| plain box `box_solid_colour` | n/a | (0.44, 0.46, 0.54) | a lighter shade of the clingable wall, so a box reads as a solid that can be clung to |
| smooth box `box_smooth_colour` (cling = 0) | n/a | (0.58, 0.50, 0.40) | the smooth wall's tan: no cling |
| wax `box_wax_colour` | n/a | (0.82, 0.62, 0.22) | amber: breaks to a Kindle dash |
| bell `box_pogo_colour` | n/a | (0.28, 0.58, 0.76) | steel blue: pogo-able |
| bell strike mark `box_pogo_mark_colour`, `box_mark_u` | n/a | (0.95, 0.97, 1.0), 10 u | a pale mark on the top edge where the pogo lands; first drawn red, then made pale so it is not read as the spikes' red (a33d3ca) |
| cling = 0 side strips `box_side_u` | n/a | 4 u of the smooth colour | wax and bells paint over the cling flag, so a strip down each side says the wall cannot be clung to |

Picture: `2026-10-20-box-colours.png` (room 12's wax, room 07's smooth roof, room 09's bell). The legibility floors are tested in `tests/unit/game/test_views.gd`. The colours were retuned for the lighting pass on 2026-10-21 (`2026-10-21-review2-integration.md`), where the bell's strike mark and the spikes' teeth also became emissive.
