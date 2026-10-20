class_name PerfStats
extends RefCounted
## The statistics the perf bench reports (`tools/bench/stress_bench.gd`): per-tick times in
## microseconds, folded across repeated runs and read as percentiles.


## Folds [param run] into [param best]: each tick keeps the least time any run gave it. A tick's
## work is fixed by the replay, so the least is the cost of the code and the rest is the machine
## (a vCPU descheduled for 4 ms inside one dummy's step is the usual excess). The first run sets
## [param best] when it is empty.
static func fold_min(best: PackedInt32Array, run: PackedInt32Array) -> void:
	if best.is_empty():
		best.append_array(run)
		return
	for i: int in range(mini(best.size(), run.size())):
		if run[i] < best[i]:
			best[i] = run[i]


## The times from tick [param from] on, sorted ascending.
static func sorted_from(samples: PackedInt32Array, from: int) -> PackedInt32Array:
	var out: PackedInt32Array = samples.slice(clampi(from, 0, samples.size()))
	out.sort()
	return out


## The [param permille]/1000 percentile of [param sorted] by the nearest-rank rule: the smallest
## value that at least that share of the samples do not exceed. 0 for no samples.
static func percentile(sorted: PackedInt32Array, permille: int) -> int:
	if sorted.is_empty():
		return 0
	var rank: int = (sorted.size() * permille + 999) / 1000
	return sorted[clampi(rank - 1, 0, sorted.size() - 1)]


## The 99th percentile of each run alone, from tick [param from] on. [method fold_min] gives the
## code's cost; a player gets one run, so a report that names the gate's figure also names these.
static func p99_each(runs: Array[PackedInt32Array], from: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for run: PackedInt32Array in runs:
		out.append(percentile(sorted_from(run, from), 990))
	return out


## The worst tick of each run alone, from tick [param from] on.
static func max_each(runs: Array[PackedInt32Array], from: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for run: PackedInt32Array in runs:
		var sorted: PackedInt32Array = sorted_from(run, from)
		out.append(sorted[sorted.size() - 1] if not sorted.is_empty() else 0)
	return out


## How many ticks from tick [param from] on took more than [param limit] microseconds.
static func count_over(samples: PackedInt32Array, from: int, limit: int) -> int:
	var n: int = 0
	for i: int in range(clampi(from, 0, samples.size()), samples.size()):
		if samples[i] > limit:
			n += 1
	return n


## The indices of the [param count] slowest ticks from tick [param from] on, slowest first (the
## earlier tick first among equals).
static func worst(samples: PackedInt32Array, from: int, count: int) -> PackedInt32Array:
	var order: Array[int] = []
	for i: int in range(clampi(from, 0, samples.size()), samples.size()):
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return samples[a] > samples[b] or (samples[a] == samples[b] and a < b)
	)
	return PackedInt32Array(order.slice(0, count))


## Microseconds as milliseconds with two decimals: "3.07".
static func ms(us: int) -> String:
	return "%.2f" % (float(us) / 1000.0)
