# ADR-0015: Resolve procs on a bus after the player's hits, and make every Votive content behind a narrow listener API

- Status: Accepted
- Date: 2026-10-19
- BUILD.md sections:
  - 6, Item procs: "Every Taper hit, pogo, spell tick and Dust scale is a proc event with a proc coefficient (Taper 1.0, pogo 0.8, Kindle 0.5 per tick, Dust 0.3 per scale, Radiance 0.2)"; "Votives listen for events. A 10% proc Votive on a 0.5-coefficient hit is a 5% chance. Stacking adds chance linearly to a cap of 100%, then adds extra rolls"; "Proc chains are allowed (a proc can trigger another) to a depth of 3, then stop";
  - 6, Kindling, Flame tier: "+10% damage; ... Votive procs +10% chance"; Hit feedback (hitstop, "Every hit has a weight");
  - 8, Tiers (Tallow Knuckle, Pilgrim's Wick, Bell of the Vigil, Second Ember, Hearthshard, The Abbess's Mercy, Snuffed Blade, Hollow Step) and Stacking math (linear, chance, hyperbolic, diminishing; "A tooltip shows the live number with stacks counted. No hidden math");
  - 10, VFX language: "Every proc has a short, distinct, sub-10-frame VFX ... one bright thing per 100x100 u region per 3 frames";
  - 2, Lore delivery rules ("Every item description is two lines: one mechanical, one in-world. The in-world line is written by a character ... Nothing in the lore explains a mechanic");
  - 13, layer 2 ("the proc event bus, Votive stacking"), layer 3 ("a Votive is a resource with a proc listener script and a stacking curve"), Determinism and replays;
  - 1, pillar 2: "Items change what your hits *do*; they never change how your hits *feel*".
- CLAUDE.md: Content ("A Votive is a resource with a proc listener and a stacking curve; adding one never touches `core/`"), Writing, rule 6 (no tunable literals), rule 7 (the VFX budget), kickoff 8 ("the stress room (200 enemies, 40 procs, Pitch lighting)").
- Checklist lines (BUILD.md section 15): Combat, "With 30 Votives active, the screen stays readable: the player and every enemy telegraph are visible"; Run tension, "A seeded replay of a full run reproduces bit-for-bit"; Process, "Every new system has an ADR".

## Context

Task 8 needs "40 procs" in its stress room, and nothing could proc: there was no event bus, no Votive and no stacking. BUILD.md gives the coefficients, the stacking curves with three quoted points, the chain depth and eight example Votives, and leaves open how the coefficient, the Flame tier's bonus and the extra rolls compose, where procs resolve in the tick, what a proc's own hit is, what "run speed" covers, what a stun is, and how a Votive's script is kept from reaching around the simulation.

## Decision

### 1. Proc events (`core/items/proc_source.gd`, `content/combat/procs.tres`)

A proc event is raised by combat as a hit lands, with its source, the enemy it landed on, the enemy's centre, the damage dealt, the Kindling tier the hit's damage used, its depth in a chain, and its coefficient (per-mille, content: `ProcTuning`):

| Source | Coefficient | Raised by |
| --- | --- | --- |
| TAPER | 1000 | every strike's hit: side 1 to 3, up, the Charged strike, White's automatic Charged strike, the down-strike on an enemy that cannot be pogoed |
| POGO | 800 | the down-strike's bounce off an enemy (it is also a hit on it) |
| KINDLE | 500 | each of Kindle's ticks on an enemy: the cone's hit is its first tick, each burn tick (every 15 f, 2 damage) another |
| DUST | 300 | kept for Moth's wing-scales; no Wick throws one yet |
| RADIANCE | 200 | Radiance's burst reaching an enemy (it deals no damage: the event carries 0) |
| VOTIVE | the Votive's own (`hit_coefficient_permille`) | a hit a Votive's proc landed |

Not proc events: a pogo off the world (spikes, a bell, a wax bulb: there is no hit), the Blaze tier's trails and its finisher's AoE (Kindling's fire, damage that is not a hit, ADR-0013), a parry (0 damage). Kindle's cone counts as a tick: the doc's "spell tick" is a spell's damage, and leaving the cone out would make the spell's own 30-damage hit the one Kindle tick that can never proc. A run with no proc Votive still raises every event (0.3 us each); none is queued.

### 2. The Votive (`core/items/votive.gd`, `content/votives/<id>.tres` and `<id>.gd`)

A Votive is one resource and its listener script, both content:

- `id` (the file's name; test Votives live in `tests/votives/` with ids starting `test_`), `display_name`, `tier` (Candle, Lantern, Star, Relic, Soot);
- `curve` (a `StackingCurve`: linear, chance, hyperbolic or diminishing, its first stack's amount and each further stack's) and the `unit` its mechanical line shows the amount in;
- `listens_to`: one or more triggers, `hit` (a chance proc on every proc event), `blade_hit` (change a Taper or pogo hit's damage before it lands), `bounce` (every pogo bounce, enemy or world), `run` (standing changes whenever the run's Votives change);
- `listener`: a script extending `VotiveListener` that overrides the hook of each trigger it lists and no other;
- `params`: every other number it uses, by name (a radius, a stun's length); the listener lists the names it reads (`params_used`) and validation requires exactly those;
- `hit_coefficient_permille`: the coefficient of the events its own hits raise;
- the item lines: `mechanical_line` (with `{total}`, `{per_stack}` and `{<param>}` filled in from the numbers, so the line never states a number tuning could leave stale), `in_world_line` and its `author`; required for every Votive outside `tests/`.

Validation (the content stage of CI, and every load) also refuses: an id that is not the file's, an unknown trigger, a `hit` Votive whose curve is not a chance (the bus rolls exactly those), a hook its triggers do not list or a trigger without its hook, a mechanical line naming a number the Votive does not have, a number in the in-world line.

**The listener API.** A listener acts only through the object it is handed: `ProcApi` (read its stacks, its curve's value, a param, the proc's level, source, coefficient, target and damage; `hit(enemy, damage)`, `stun_within(radius_u, frames)`, `nearest_enemy(radius_u, skip_target)`, `roll_permille(chance)`, its counter), `BladeHitApi` (`add_damage`), `BounceApi` (`add_air_dashes`), `RunApi` (`add_run_speed_permille`, `remove_dash_cooldown`, `add_max_hearts`). Enemies are handles (their place in the room's list); radii are units. The bus fills the API's fields before each call and holds itself there only for the call. A listener keeps no state of its own: the bus keeps one counter per Votive, in the state hash, and that is all a listener may remember.

**The boundary is checked, not trusted** (`tools/ci/core_purity.gd`, the compile stage): every script under `content/votives/` and `tests/votives/` obeys the core's rules (no floats, Nodes, engine singletons, unseeded randomness, file writes) and the listener's: it extends `VotiveListener`; it names no class but `VotiveListener`, the four APIs, `ProcSource`, `PackedStringArray` and `String`; it has no member or static variable, `class_name`, inner class, signal or annotation; it touches no member whose name starts with an underscore, calls no reflection or loading (`get`, `set`, `call`, `load`, `preload` and the rest), never says `self`; and it holds no integer literal but 0 and 1 (CLAUDE.md rule 6). `tests/unit/test_core_purity.gd` makes each rule fire.

**Adding a Votive never touches `core/`.** The API was committed first (with the test Votives under `tests/votives/`); the content Votives were added in the next commit, whose diff touches nothing under `core/`.

### 3. Stacking maths (`core/items/stacking_curve.gd`), in integers

| Curve | Value at n stacks | Unit, rounding | The doc's points (unit-tested) |
| --- | --- | --- | --- |
| Linear | first + per x (n - 1), no cap | the Votive's own (damage, per-mille of run speed, air dashes, hearts) | Knuckle 3, 6, 30 |
| Chance | (first + per x (n - 1)) x 1000, uncapped | parts per million | 10% x 10 = 1,000,000 ("every hit"); x 15 = 1,500,000 ("every hit plus a 50% chance of a second") |
| Hyperbolic | 1,000,000 x x / (1000 + x), x = k x n per-mille | ppm, rounded down: never 1,000,000 | k = 100: 10 stacks = 500,000 ("50%"); 1 = 90,909 |
| Diminishing | each stack removes k per-mille of what remains | ppm; each removal rounded down, so what remains is never below the exact value | k = 150: 150,000, 277,500, 385,875, 477,993 |

Parts per million keep every chance in this ADR exact (10% on a 0.5 hit at the Flame tier is 55,000) where per-mille would round.

### 4. How the coefficient, the Flame tier and the extra rolls compose

**Relative bonus, scaling the stacked chance, split last:**

`chance (ppm) = curve(stacks) x coefficient / 1000 x (1000 + bonus) / 1000`, rounded down once, at the end; `bonus` is 100 per-mille at Kindling Flame and above (the tier the hit's damage used), 0 below. Then each whole million is a proc for certain, and what remains is one PROCS draw (`Rng.below(1,000,000) < remainder`), made only when something remains.

- "A 10% proc Votive on a 0.5-coefficient hit is a 5% chance": the coefficient multiplies the chance.
- "Votive procs +10% chance" is relative (10% becomes 11%), as the same row's "+10% damage" is relative; an absolute +10 points would double a 10% Lantern at the Flame tier and make a 1% Votive on Radiance ten times likelier: the coefficient would stop meaning anything. The bonus holds at Blaze and White, as every tier's effects build on the last (ADR-0013 keeps Blaze's trails at White).
- The split comes last: the coefficient scales the whole stacked chance, so a weaker hit never procs more often or more times than a stronger one (split first, 15 stacks on a 0.5 hit would be a sure proc plus a 25% second: two procs from a Kindle tick, where a Taper hit with 10 stacks gets one). The expected number of procs is exactly stacks x chance x coefficient x bonus.

| Stacks of 10% | Hit (coefficient) | Tier | Chance | Procs |
| --- | --- | --- | --- | --- |
| 1 | Taper 1.0 | Ember | 10% | one draw at 10% |
| 1 | Kindle tick 0.5 | Ember | 5% | the doc's example |
| 1 | Taper 1.0 | Flame | 11% | |
| 1 | Kindle tick 0.5 | Flame | 5.5% | |
| 1 | Dust 0.3 / Radiance 0.2 | Ember | 3% / 2% | |
| 9 | Taper 1.0 | Flame | 99% | `bell_flame_tier_adds_a_tenth` (90% at Ember: `bell_flame_tier_control`) |
| 10 | Taper 1.0 | Ember | 100% | one, no draw (`bell_rings_on_every_hit_at_ten_stacks`) |
| 10 | Taper 1.0 | Flame | 110% | one, and a draw at 10% |
| 10 | pogo 0.8 | Ember / Flame | 80% / 88% | |
| 10 | Kindle tick 0.5 | Ember | 50% | `bell_on_kindle_ticks_at_half_chance` |
| 15 | Taper 1.0 | Ember | 150% | one, and a draw at 50% (`bell_fifteen_stacks_rolls_a_second`, `_rings_once`) |
| 15 | Kindle tick 0.5 | Ember | 75% | one draw |
| 20 | Kindle tick 0.5 | Ember | 100% | one, no draw |
| 50 | Radiance 0.2 | Ember | 100% | one, no draw (`bell_on_radiance_reach`) |

### 5. Chains, and the order of every roll (`core/items/proc_bus.gd`)

A proc fires at level 1 on a hit's event; a proc's hit raises an event one level deeper, and procs on it fire one level deeper still, to `chain_depth` (3, content). A level-3 proc's hit raises its event (it is counted) and nothing is queued for it: the fourth level never fires (`chain_stops_at_depth_three`).

Order, so a run is a seed and its inputs: events resolve in the order they were raised (this tick's burn ticks in enemy order, then the strike's hits, Kindle's cone, Radiance's reach and the pogo's hit, each in enemy order); an event a proc's hit raises joins the end of the queue (breadth first). For each event, each `hit` Votive in run order (the order the run got them; a scenario's in the order of their option keys): its chance; one PROCS draw if it has a fraction; then each of its procs fires in turn (a `PROC` event, then its listener), and a roll the listener asks for (`roll_permille`) is drawn there and then. Every draw is from the PROCS stream (ADR-0005), so how often items fire never changes what a run finds. `coin_seed_1`/`_2` and `bell_seed_1`/`_2` pin two seeds each.

### 6. Where procs resolve, and what a proc's hit is

`Combat.resolve` (ADR-0013's order gains a step): effects age (burn ticks raise their events); the player's hits (each raises its event); **the procs**; the enemies' hits. Procs resolve with the player's hits, before the enemies': a proc that kills, staggers or stuns an enemy on the tick its swing would land takes the swing away, as the player's own hits do (`bell_stun_takes_the_swing` and its control). The hitstop a tick sets counts from the next tick, as before.

**A proc's hit is proc damage, not a Taper hit** (`Combat.proc_hit`): health and poise, with Kindling's damage bonus, through the same path as a burn (`_damage`); no hitstop of its own, no knockback, no Kindling hit, no Flame. A kill by it is a kill: an ember flies home with its Flame and both freeze for the Kill row's 3 f, as a burn's kill does (`a_kill_by_a_proc_is_a_kill`). Why each:
- No hitstop: forty procs adding their weight would freeze the game for every burst; the hit that raised them already has its hitstop (pillar 2: items never change how a hit feels).
- No Kindling, no Flame: Kindling is "consecutive hits", the player's, and "Kindling White ... feels earned, not inevitable" (section 15); Flame is what "aggression heals" pays for fighting well. A Votive that should grant either says so through the API (a later trigger).
- No knockback: knockback is the blade's push; a proc that should push says so.
- The kill's ember: "Death is a gift. Every kill releases an ember."

**Votives change what a hit does, never how it feels.** A `blade_hit` Votive's damage (Tallow Knuckle) is dealt, but the hit's hitstop is weighed by its damage without it (`tallow_knuckle_never_adds_weight`: ten Knuckles make side 1 deal 40, and it keeps a light hit's 2 f where 40 damage alone weighs 3). The Votive's damage joins the hit before Kindling's bonus multiplies it (`tallow_knuckle_before_kindling`: (10 + 3) x 1.1 = 14).

**A stun** (`Enemy.stun`, the state `stun`): a stagger poise did not cause. The attack under way is lost, a telegraph past its cue too (a poise break loses it the same way, ADR-0013), and the enemy does nothing but carry its momentum; poise is untouched; a stun never shortens a stagger or stun already running (the longer holds); the dead are not stunned. The Bell's stun is 30 frames, the same as a poise break's stagger (content: `stun_frames`, not in BUILD.md).

### 7. The run's Votives and the state

- A scenario names Votives by option: `option votive_<id> <stacks>` (fixture option names are now identifiers; `votive_test_<name>` names `tests/votives/<name>.tres`). The game boots with none. `Simulation.give_votive` gives stacks mid-run (pickups, later) and reapplies the `run` Votives.
- **Run changes** apply to the Wick when the run's Votives change: its movement recompiled with the added run speed (`MovementTuning.compile(run_speed_bonus_permille)`, the one rounding of `Fx.speed` taking the bonus inside it, so with none it is exactly as before); the ground dash's cooldown taken away (`Player.dash_free`, as at Kindling White); the maximum hearts (never below one; the hearts held never above the maximum).
- **The state hash** gains the run's Votives (each id, stacks and counter) and `Player.dash_free`. The proc queue is empty between ticks; this tick's counts are presentation. The **content hash** gains `content/combat/procs.tres` and every Votive the run holds, its curve, params and its listener script's path and source text (`ContentHash` now digests a script held as a value by its source: before, any two scripts hashed alike).
- `Simulation.VERSION` 8 to 9, every golden hash re-blessed. **No behaviour moved**: `tools/replay/state_trace.gd` dumped every one of the 386 existing fixtures' state tick by tick before the change (at 7d623fb) and after (the player's every field, its body, vitals and ember toss; every enemy's every field and body; the kill embers, fire trails and light; the input ring; all five random streams; every event), and compared 5,494,887 values over 51,033 ticks: none differs (the one field only after is `player.dash_free`).

### 8. Presentation

- `SimEvents.PROC` per proc fired (where its event was; a bounce's at the player's centre; the value is the Votive's slot plus 256 x its level) and `SimEvents.STUN` per enemy stunned. A proc's damage is a `HIT` of kind `HitKind.PROC`, which shows no spark.
- Every proc gets a grey-box mark under ten frames, distinct per Votive (`content/votive_looks.tres`, a presentation resource beside `feedback.tres`, so a look never changes the content fingerprint): a shape, a colour, a size, its frames (validated 1 to 9). Every content Votive that can proc has a look and no two look alike; a Votive with none (a test Votive) takes a fallback by its slot, distinct within a run. Grey boxes, never called art.
- Through the VFX budget at `PROC` priority, the lowest but ambient: a proc on the point a hit landed this tick is part of that hit's feedback and joins its group (as a finisher's arc and burst join its spark), once per Votive per hit however often it fired there; anywhere else (a chain's arc to another enemy, Radiance's reach) it takes its 100 u cell only if nothing more important holds it, and anything more important takes the cell from it. With the stress set's 39 procs, the hit's cell shows its spark and one mark per Votive, and each cell the arcs reach shows one mark.
- The F3 overlay lists the run's Votives with their stacks and this tick's procs (how many, from how many events, the deepest level, by Votive), and marks each point a proc fired, labelled by Votive and level (a burst of several Votives as "30 procs, 3 Votives, L1 L3"). A stunned enemy is drawn slumped in its own colour under three diamonds.

### 9. The Votives (content/votives/)

| Votive | Tier | Curve | Trigger | Author of the in-world line |
| --- | --- | --- | --- | --- |
| Tallow Knuckle | Candle | linear, +3 a stack | blade_hit: Taper and pogo hits | the Chandler, of the Tallowborn |
| Pilgrim's Wick | Candle | linear, +80 per-mille a stack | run: run speed | Vesper, once a squire of the Vigil |
| Bell of the Vigil | Lantern | chance, 10% a stack | hit: stun within 120 u for 30 f | Serah Candlewright, Knight-Abbess |
| Second Ember | Lantern | linear, +1 a stack | bounce: air dashes | Moth, of the Lamplighters |
| Hollow Step | Soot | linear, 1 a stack | run: no dash cooldown, max hearts -1 a stack | the Hollow |

- **"Run speed"** is the most the Wick runs at, on the ground and in the air (air control's target is the run speed), with the acceleration and deceleration times kept (so they scale: 0 to max still 6 f), and the turnaround and the landing following it. Not the dash, the jumps, the wall-jumps, the pogo or knockback: a Pilgrim's Wick makes the run faster, not the tech.
- **Second Ember**: a bounce leaves the Wick its own air dashes plus the Votive's, until it lands. Restores never take air dashes away: a bounce, a fresh cling and a wall-jump now restore to at least the Wick's own (`maxi`), so the Votive's extras survive a wall; a landing ends the airtime and sets them back to the Wick's own. Without the Votive this is exactly the old behaviour (the per-tick comparison holds). The proc shows when the bounce actually gave the Wick a dash it did not have.
- **Hollow Step**: the hearts it takes stop at one: a Soot item that killed its carrier at five stacks would be no wager.
- **The Abbess's Mercy is left out**: hearts are whole (`Hearts.current` counts hearts, and everything that moves them moves whole hearts: an enemy's damage, Mend's 1, a hazard's 1), and the Mercy needs quarters ("half a heart; stacks add a quarter"). Hearts in quarters is a change to the hearts model and to the diegetic HUD (the ember's cracks, section 12), a decision for the director, not a Votive's side effect.
- **Hearthshard** waits for the light (its radius and "enemies inside it take 15% more damage" need the ember's light radius, Phase 2's lighting pass); **Snuffed Blade** waits for the Wane Clock.
- The in-world lines are by people of the doc (the Chandler of zone 2, Vesper, the Knight-Abbess, Moth, the Hollow), one voice each, none explaining its mechanic.

### 10. Cost (`tools/bench/proc_bench.gd`, 200 dummies; this container, load 1.6 to 1.8)

| What | Microseconds |
| --- | --- |
| A proc event no Votive listens for | 0.3 |
| Each Votive listening, per event (one PROCS draw, rarely firing) | 0.8 (40 events x 40 Votives: 1.2 ms a tick) |
| A PROCS draw | 0.6 |
| The stress set's burst: one Taper hit, 39 chained procs arcing to the nearest dummy | 1,250 to 1,550 (32 to 40 a proc) |
| ... of which: the enemies' query cells, built once a tick when a proc asks | 120 |
| ... a nearest-enemy question within 160 u | 10 |
| ... a proc hit | 5 |

Two changes keep the bus cheap enough to drive that hard, neither moving a result: `Rng.next_u32` does its modulo-2^32 maths inline (the state words are below 2^32, so x5, x9 and the rotations fit in 64 bits; the golden test still pins the outputs; 1.2 to 0.6 us a draw), and combat answers "within a radius" and "nearest" from `EnemyCells`, the enemies bucketed by 128 u cells once a tick (a linked list per cell in integer arrays; a query reads the cells its radius reaches; `test_enemy_cells.gd` holds it to a full scan). In GDScript a 40-proc burst is still about half of section 13's 3.0 ms for input and simulation: the stress room's perf gate (the next task) measures it beside the 200 enemies' physics (3 to 4.5 ms a tick on its own today, `physics_bench.gd`), and section 13 already names "hitbox resolution" for C++ once profiling demands it.

## Alternatives considered

| Option | Why not |
| --- | --- |
| The Flame tier's bonus as +10 points | Doubles a 10% Lantern at Flame and makes a 1% Votive on Radiance 11 times likelier; the coefficient stops meaning anything |
| Split the chance at 100% before the coefficient | A 0.5-coefficient Kindle tick with 15 stacks would proc twice where a Taper hit with 10 procs once |
| Resolve each proc the moment its event is raised (depth first) | The order would depend on where in combat's code the event was raised; a queue keeps one order: the order things happened, then their consequences |
| Resolve procs after the enemies' hits | A Bell ringing on the tick a swing lands would stun an enemy whose swing had already hit: the player's answer would come a tick late |
| A proc's hit as a Taper hit (hitstop, Kindling, Flame) | Forty procs would freeze the game and fill Kindling and Flame by themselves |
| Draw a roll for every Votive on every event, whole chances included | Wasted draws; a sure chance is sure |
| Votive behaviour in `core/` (a `match` on the id) | Every Votive would touch `core/`; CLAUDE.md forbids it |
| Listener scripts trusted to behave | GDScript cannot sandbox; the static check makes the boundary a CI gate |
| The proc's look in the Votive's own resource | A colour change would change the content fingerprint and report old replays as "different content" |
| Proc marks at PROC priority with no group | The hit's own spark always holds the cell first: a Bell ringing on a Taper hit would never be seen |
| A scan of every enemy for each "nearest" question | 18 us a question over 200 enemies, 0.7 ms for a 39-proc burst before any proc does anything |
| Hearts in quarters for the Abbess's Mercy | A change to the hearts model and the HUD's cracks, the director's to decide |

## Feel reason

Combat (pillar 2): the hit's weight is the blade's, whatever the Votives add, and procs never freeze the game, so a late run's fireworks never cost a frame of the player's control. Movement (pillar 1): Pilgrim's Wick makes the run faster and leaves every tech's numbers alone; Second Ember's dashes survive a wall, so a pogo-wall-dash route never loses what the bounce gave. Light (pillar 3): every proc shows, in its own shape, and never over a hit or a telegraph. The rising dark (pillar 4): the Bell's stun cancels a swing, so Lantern procs answer crowds without replacing the parry: it is a chance, the parry is a certainty.

## Consequences

- `tests/replay/procs/` (36 fixtures) holds each Votive with its control, the stacking points a fixture can show, the Flame tier's bonus, the chain's depth, a proc's kill, the counter, two seeds' rolls twice over, and the stress set's 39-proc burst; `tests/unit/core/items/` the stacking table, the chance table, the bus, the schema; `tests/unit/test_core_purity.gd` the listener rules; `tests/unit/game/test_proc_feedback.gd` the proc marks and the overlay.
- `tools/replay/state_trace.gd` is the tool for the next change that moves every golden hash: dump before, dump after, compare.
- `tools/replay/proc_seeds.gd` finds a seed whose PROCS draws land where a fixture needs them.
- New triggers (on kill, on parry, on a player hit) and new API verbs (heal, grant Flame, push) are added to `core/` once, and from then on any number of Votives use them without touching it; the listener rules list the API classes a listener may name.
- When exports land, `ContentHash` reads a listener's source text; an export that strips scripts to tokens must keep the Votives' digests the same (a build-time digest file, or listeners exported as text).
- Director questions: the Bell's stun at 30 f; a stun cancelling a swing after its cue (a poise break does); Kindle's cone counted as a tick; the relative Flame bonus; Hollow Step's one-heart floor; the Abbess's Mercy and quarter hearts; whether a proc should ever grant Kindling.
