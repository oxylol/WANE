class_name BounceApi
extends VotiveApi
## What a Votive may do on a pogo bounce ("bounce" trigger; docs/adr/0015).

var _granted: bool = false


## Grants [param extra] air dashes beyond the Wick's own for the rest of the airtime: the player
## then has at least their own air dashes plus [param extra] (a bounce never takes any away).
## True if that gave the player any they did not have, which shows as the Votive's proc.
func add_air_dashes(extra: int) -> bool:
	var got: bool = _bus._top_up_air_dashes(extra)
	_granted = _granted or got
	return got
