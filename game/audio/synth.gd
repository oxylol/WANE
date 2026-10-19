class_name Synth
extends RefCounted
## Grey-box sounds synthesized in code (CLAUDE.md: "Every visual and audible thing is authored
## from source"; BUILD.md section 11: "Every sound and every note is synthesized by Claude in
## code"). Phase 1 needs placeholders that read clearly, not the final mix: a hit is a noise burst
## over two partials, a finisher adds a falling sub thump, a parry is a two-partial chime, a
## telegraph is a short rising whistle. The final sounds come from tools/audiobuild/ (Phase 2).
## Every sound is generated once and cached; noise is seeded, so every build sounds the same.

const RATE: int = 44100

## How many variants each sound has (BUILD.md section 11: "3 to 5 variants on everything that
## plays more than once a second"), named base + index: "chime0".."chime2". A hit has one per
## [member FeedbackTuning.spark_variants], up to [constant HIT_VARIANTS].
const HIT_VARIANTS: int = 5
const OTHER_VARIANTS: int = 3
const BASES: Array[String] = [
	"hit",
	"thump",
	"chime",
	"heal",
	"radiance",
	"player_hit",
	"telegraph",
	"telegraph_red",
	"kill",
	"ember",
]

static var _cache: Dictionary[String, AudioStreamWAV] = {}


## The sound named [param id]: a base and a variant index ("hit0".."hit4", "thump0".."thump2",
## "chime" for a parry, "heal" for Mend, "radiance", "player_hit", "telegraph", "telegraph_red",
## "kill", "ember").
static func sound(id: String) -> AudioStreamWAV:
	if not _cache.has(id):
		_cache[id] = _make(id)
	return _cache[id]


## How many variants [param base] has.
static func variants(base: String) -> int:
	return HIT_VARIANTS if base == "hit" else OTHER_VARIANTS


## Variant [param v] of [param base] (wrapped into the variants it has).
static func variant(base: String, v: int) -> AudioStreamWAV:
	return sound("%s%d" % [base, posmod(v, variants(base))])


## True if [param stream] is one of [param base]'s variants.
static func is_variant_of(stream: AudioStream, base: String) -> bool:
	for v: int in range(variants(base)):
		if stream == variant(base, v):
			return true
	return false


static func _make(id: String) -> AudioStreamWAV:
	var base: String = id.rstrip("0123456789")
	var v: int = id.trim_prefix(base).to_int()
	# Each variant detunes its tones (a fifth of a semitone a step) and reseeds its noise.
	var d: float = 1.0 + 0.012 * float(v)
	var samples := PackedFloat32Array()
	match base:
		"hit":
			samples = _mix(_noise(0.07, 11 + v, 0.6), _tone(0.07, 640.0 + 90.0 * v, 0.0, 0.5))
		"thump":
			samples = _mix(_tone(0.18, 120.0 * d, -70.0, 0.9), _noise(0.05, 5 + v, 0.4))
		"chime":
			samples = _mix(_tone(0.45, 1760.0 * d, 0.0, 0.5), _tone(0.45, 2640.0 * d, 0.0, 0.3))
		"heal":
			# Mend's heal: a soft, low, rising pair, never the parry's high chime.
			samples = _mix(_tone(0.5, 523.0 * d, 260.0, 0.35), _tone(0.5, 784.0 * d, 260.0, 0.2))
		"radiance":
			# The burst that lights the room: a broad bloom, a falling sub under a wide chord.
			samples = _mix(
				_mix(_tone(0.6, 880.0 * d, 0.0, 0.3), _tone(0.6, 1320.0 * d, 0.0, 0.25)),
				_mix(_tone(0.5, 110.0 * d, -50.0, 0.7), _noise(0.12, 17 + v, 0.35))
			)
		"player_hit":
			samples = _mix(_tone(0.22, 90.0 * d, -40.0, 0.9), _noise(0.12, 7 + v, 0.7))
		"telegraph":
			samples = _tone(0.30, 420.0 * d, 600.0, 0.35)
		"telegraph_red":
			samples = _mix(_tone(0.30, 300.0 * d, 300.0, 0.35), _tone(0.30, 317.0 * d, 300.0, 0.35))
		"kill":
			samples = _mix(_noise(0.16, 3 + v, 0.5), _tone(0.16, 300.0 * d, -150.0, 0.4))
		"ember":
			samples = _tone(0.08, 1320.0 * d, 400.0, 0.3)
		_:
			push_error("Synth: no sound '%s'" % id)
			samples = _tone(0.05, 440.0, 0.0, 0.2)
	return _wav(samples)


## A sine from [param freq] Hz sweeping by [param sweep] Hz over [param seconds], fading out.
static func _tone(seconds: float, freq: float, sweep: float, gain: float) -> PackedFloat32Array:
	var n: int = int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / float(n)
		phase += TAU * (freq + sweep * t) / RATE
		out[i] = sin(phase) * gain * _envelope(t)
	return out


## Seeded white noise, fading out.
static func _noise(seconds: float, seed_value: int, gain: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n: int = int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in range(n):
		out[i] = rng.randf_range(-1.0, 1.0) * gain * _envelope(float(i) / float(n))
	return out


## A 2 ms attack, then a squared fade.
static func _envelope(t: float) -> float:
	var attack: float = minf(1.0, t * 50.0)
	return attack * (1.0 - t) * (1.0 - t)


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size()))
	for i: int in range(out.size()):
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
