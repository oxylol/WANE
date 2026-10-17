class_name Fx
extends RefCounted
## Fixed-point arithmetic for the simulation core (ADR-0003).
##
## Positions are integers in sub-pixels: [constant SUB] sub-pixels per world unit, where one unit
## is one world pixel at the native 1920x1080 art scale (BUILD.md section 5). Velocities are
## sub-pixels per tick and accelerations are sub-pixels per tick per tick, at [constant HZ] ticks
## per second. Content is authored in BUILD.md's design units and converted here, once, with
## round-half-away-from-zero, so no float ever enters the core.

## Sub-pixels per world unit.
const SUB: int = 256
## Simulation ticks per second.
const HZ: int = 60
## Mask for 32-bit unsigned arithmetic.
const MASK32: int = 0xFFFFFFFF
## A diagonal's share of a straight speed (1 / sqrt(2), in thousandths): an 8-way move at 45
## degrees covers the same distance per tick as a straight one.
const DIAGONAL_PERMILLE: int = 707


## World units to sub-pixels.
static func units(u: int) -> int:
	return u * SUB


## Floor division (rounds toward negative infinity), unlike GDScript's truncating [code]/[/code].
static func div_floor(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Division rounded half away from zero.
static func div_round(a: int, b: int) -> int:
	if b < 0:
		a = -a
		b = -b
	if a >= 0:
		return (2 * a + b) / (2 * b)
	return -((2 * -a + b) / (2 * b))


## Sub-pixel to whole units, rounding toward negative infinity (the unit a position lies in).
static func to_units_floor(sp: int) -> int:
	return div_floor(sp, SUB)


## A speed in units per second to sub-pixels per tick.
static func speed(units_per_second: int) -> int:
	return div_round(units_per_second * SUB, HZ)


## An acceleration in units per second squared to sub-pixels per tick squared.
static func accel(units_per_second2: int) -> int:
	return div_round(units_per_second2 * SUB, HZ * HZ)


## The per-tick change that takes [param amount] to zero (or from zero) in [param ticks] ticks.
static func per_tick(amount: int, ticks: int) -> int:
	return div_round(amount, maxi(ticks, 1))


## [param value] scaled by [param permille] / 1000, rounded half away from zero.
static func permille(value: int, per_mille: int) -> int:
	return div_round(value * per_mille, 1000)


## [param value] scaled by [param percent] / 100, rounded half away from zero.
static func percent(value: int, per_cent: int) -> int:
	return div_round(value * per_cent, 100)


## Moves [param value] toward [param target] by at most [param step] (step is non-negative).
static func approach(value: int, target: int, step: int) -> int:
	if value < target:
		return mini(value + step, target)
	if value > target:
		return maxi(value - step, target)
	return value


## 32-bit unsigned multiply (mod 2^32) without ever exceeding the signed 64-bit range.
static func mul32(a: int, b: int) -> int:
	a &= MASK32
	b &= MASK32
	var lo: int = a * (b & 0xFFFF)
	var hi: int = ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & MASK32


## 32-bit rotate left.
static func rotl32(x: int, k: int) -> int:
	x &= MASK32
	return ((x << k) | (x >> (32 - k))) & MASK32


## MurmurHash3's 32-bit finaliser: a fast, well-distributed integer mix.
static func fmix32(h: int) -> int:
	h &= MASK32
	h ^= h >> 16
	h = mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h
