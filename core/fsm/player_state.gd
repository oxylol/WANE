class_name PlayerState
extends RefCounted
## The player's state hash (CLAUDE.md rule 4: a run is a seed and an input stream, and a desync is
## a P0 bug): every field of a [Player] that can influence a future tick, kept apart from the state
## machine so player.gd stays readable. tests/unit/core/fsm/test_player_state.gd changes every
## field in turn and fails if the hash does not change with it.


static func hash_into(pl: Player, h: StateHasher) -> void:
	pl.body.hash_into(h)
	for v: int in [
		pl.facing,
		pl.loco,
		pl.air_frames,
		pl.air_jumps_left,
		pl.air_dashes_left,
		pl.dash_frame,
		pl.dash_vx,
		pl.dash_vy,
		pl.ground_dash_cooldown,
		pl.carry_frames,
		pl.jump_frame,
		pl.wall_side,
		pl.wall_frames,
		pl.wall_lock,
		pl.action,
		pl.action_frame,
		pl.action_dir,
		pl.chain_timer,
		pl.since_bounce,
		pl.invuln,
		pl.freeze,
		pl.safe_x,
		pl.safe_y,
		pl.turn_left,
		pl.apex_hang_left,
		pl.wall_coyote,
		pl.wall_coyote_side,
		pl.stick_hold_x,
		pl.queued_attack_stick.x,
		pl.queued_attack_stick.y,
		pl.queued_attack_left,
		pl.strike_serial,
		pl.white_hits,
		pl.spell,
		pl.spell_frame,
		pl.spell_dir.x,
		pl.spell_dir.y,
		pl.knock_left,
		pl.knock_vx,
		pl.recoil_left,
		pl.recoil_vx,
		pl.charge_held,
		pl.charge_request,
		pl.charge_stick.x,
		pl.charge_stick.y,
		pl.home_x,
		pl.home_y,
	]:
		h.add_int(v)
	for b: bool in [
		pl.crouching,
		pl.left_by_jump,
		pl.dash_grounded,
		pl.dash_crouched,
		pl.jump_released,
		pl.jump_cut,
		pl.jump_fresh,
		pl.wall_spent,
		pl.action_pogoed,
		pl.kindle_dash,
		pl.apex_hang_used,
		pl.dash_landed,
		pl.wall_fresh,
		pl.radiance_burst,
		pl.charge_broken,
		pl.dash_free,
	]:
		h.add_bool(b)
	h.add_string(pl.chain_next)
	pl.toss.hash_into(h)
	pl.vitals.hash_into(h)
