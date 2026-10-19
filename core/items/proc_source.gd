class_name ProcSource
extends RefCounted
## What raised a proc event (BUILD.md section 6, Item procs: "Every Taper hit, pogo, spell tick
## and Dust scale is a proc event with a proc coefficient (Taper 1.0, pogo 0.8, Kindle 0.5 per
## tick, Dust 0.3 per scale, Radiance 0.2)"; docs/adr/0015). Each source's coefficient is content
## ([ProcTuning]); a Votive's own hit carries the coefficient its resource gives
## ([member Votive.hit_coefficient_permille]).
##
## - TAPER: a strike's hit (side, up, the down-strike on an enemy that cannot be pogoed, the
##   Charged strike, White's automatic Charged strike).
## - POGO: the down-strike's bounce off an enemy, which is also a hit on it.
## - KINDLE: one of Kindle's ticks on an enemy: the cone's hit, then each burn tick.
## - DUST: one of Moth's wing-scales (no Wick throws them yet; the coefficient is kept for Moth).
## - RADIANCE: Radiance's burst reaching an enemy.
## - VOTIVE: a hit a Votive's proc landed, one level deeper in the chain.

enum { TAPER, POGO, KINDLE, DUST, RADIANCE, VOTIVE }

const NAMES: Array[String] = ["taper", "pogo", "kindle", "dust", "radiance", "votive"]
